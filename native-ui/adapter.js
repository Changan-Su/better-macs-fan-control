if (window.BETTER_FAN_NATIVE) {
    const call = (command, params = {}) =>
        window.webkit.messageHandlers.native.postMessage({
            command,
            ...params,
        });
    let previousBanner,
        device = null,
        pending = false,
        nativeUndo = null,
        initialized = false,
        pollSequence = 0,
        pollRunning = false;
    const history = [];
    const originalEditor = renderEditor,
        originalPreview = renderPreview,
        originalFans = renderFans;
    // Mutable model arrays are replaced only with validated readings from Swift.
    fans.splice(0);
    sensors.splice(0);
    available = () =>
        Boolean(
            device?.canControl &&
            device?.fanDetectionAvailable &&
            fans.length &&
            sensors.length &&
            !pending,
        );
    selectedFans = () =>
        scope === "both"
            ? fans.map((_, i) => i)
            : fans[Number(scope)]
              ? [Number(scope)]
              : [];
    overallMode = () =>
        fans.length && fans.every((f) => f.config.mode === fans[0].config.mode)
            ? fans[0].config.mode
            : fans.length
              ? "mixed"
              : "auto";
    loadDraft = () => {
        draft = { ...(fans[selectedFans()[0]]?.config || defaultConfig()) };
        if (draft.mode === "external") draft.mode = "auto";
        if (!sensors.some((s) => s.id === draft.sensor))
            draft.sensor = sensors[0]?.id || "";
        renderEditor();
    };
    draftError = () => {
        const chosen = selectedFans().map((i) => fans[i]);
        if (!chosen.length) return "没有可调节的风扇。";
        const min = Math.max(...chosen.map((f) => f.min)),
            max = Math.min(...chosen.map((f) => f.max));
        if (
            draft.mode === "fixed" &&
            (!Number.isFinite(draft.rpm) || draft.rpm < min || draft.rpm > max)
        )
            return `请输入 ${num(min)}–${num(max)} RPM 之间的转速。`;
        if (
            draft.mode === "sensor" &&
            (!Number.isFinite(draft.start) ||
                !Number.isFinite(draft.end) ||
                draft.start < 20 ||
                draft.end > 100 ||
                draft.end - draft.start < 4.999 ||
                !sensors.some((s) => s.id === draft.sensor))
        )
            return `请选择可用传感器，提速温度应低于全速温度至少 ${prefs.unit === "f" ? 9 : 5}°。`;
        return "";
    };
    renderStatus = () => {
        if (!device) return;
        const count = fans.length,
            failed = !device.fanDetectionAvailable,
            noFans = !failed && !count;
        const title = failed
            ? "无法读取风扇信息"
            : noFans
              ? "这台 Mac 没有可调节的风扇"
              : device.error
                ? "控制服务需要检查"
                : !device.canControl
                  ? "正在监测这台 Mac"
                  : "风扇控制服务已连接";
        const description =
            device.error ||
            (failed
                ? "未显示模拟读数。请检查机型支持或重新打开应用。"
                : noFans
                  ? "可以继续查看可用的温度传感器。"
                  : !device.signed
                    ? "此预览版未使用 Developer ID 签名，当前仅支持真实监测。"
                    : !device.canControl
                      ? "调速前，请启用并授权后台控制服务。"
                      : overallMode() === "auto"
                        ? "风扇由 macOS 自动调节。"
                        : "当前设置由控制服务执行，可随时恢复系统自动。");
        $("#overview-status").className =
            "status-strip" + (failed || device.error ? " warning" : "");
        const banner = `<div class="row"><div class="status-icon">${icon(failed ? "info" : "shield")}</div><div><h2>${escapeHTML(title)}</h2><p>${escapeHTML(description)}</p></div></div>${device.signed && !device.canControl ? '<button class="btn" data-action="authorize">启用风扇控制</button>' : ""}`;
        if (banner !== previousBanner) {
            $("#overview-status").innerHTML = banner;
            previousBanner = banner;
        }
        $("#fans-section").classList.toggle("hidden", noFans || failed);
        $("#fanless-state").classList.toggle("hidden", !noFans);
        $("#modes-section").classList.toggle("hidden", noFans || failed);
        $("#fan-count").textContent = `${count} 只风扇`;
        $("#device-name").textContent = device.deviceName;
        $("#device-model").textContent = device.deviceModel;
        $("#device-status").innerHTML =
            '<span class="dot"></span>' +
            (failed ? "读数不可用" : "真实设备读数");
        $(".nav .badge").textContent = sensors.length;
        const auto = fans.filter((f) => f.config.mode === "auto").length;
        const external = fans.some((f) => f.config.mode === "external");
        $("#control-source").textContent = external
            ? "部分风扇由系统或其他应用管理"
            : auto === count
              ? "当前由 macOS 自动调节"
              : auto
                ? "风扇分别设置"
                : "当前由 Better Fan 调节";
        $("#footer-control").textContent =
            "控制权：" +
            (external
                ? "系统 / 其他应用"
                : auto === count
                  ? "macOS"
                  : auto
                    ? "macOS / Better Fan"
                    : "Better Fan");
        $("#footer-status").textContent = failed
            ? "等待设备读数"
            : "真实读数 · 每 2 秒更新";
        $$(".app-footer>span").at(-1).textContent = device.canControl
            ? "后台服务已授权"
            : "仅监测";
        $$(".reset-button").forEach(
            (b) =>
                (b.disabled =
                    !device.canControl ||
                    pending ||
                    !fans.some((f) =>
                        ["fixed", "sensor", "full"].includes(f.config.mode),
                    )),
        );
        $$(".mode").forEach((b) => {
            b.classList.toggle("active", b.dataset.mode === overallMode());
            b.setAttribute("aria-pressed", b.dataset.mode === overallMode());
            b.disabled = !available();
        });
        $("#mode-note-text").textContent = !device.canControl
            ? "监测无需后台权限。启用控制需要已签名版本，并在系统设置中授权辅助服务。"
            : pending
              ? "正在等待控制服务确认，请稍候…"
              : "编辑参数后，点击“应用设置”才会生效。";
    };
    renderFans = () => {
        originalFans();
        $$("#fan-cards .fan-card").forEach((card, i) => {
            const f = fans[i];
            if (f.config.mode === "external") {
                card.querySelector(".tag").textContent = "外部控制";
                card.querySelector(".fan-reading p").textContent =
                    "由系统或其他应用指定转速";
            }
        });
    };
    const sensorFor = (kind) =>
        sensors.find((s) =>
            kind === "cpu" ? /^(TC|Tp)/.test(s.id) : /^(TG|Tg)/.test(s.id),
        );
    renderReadings = () => {
        const cpu = sensorFor("cpu"),
            gpu = sensorFor("gpu");
        const keys = prefs.stars
            .map((id) => sensors.find((s) => s.id === id))
            .filter(Boolean);
        $("#key-temperatures").innerHTML = keys.length
            ? keys
                  .map(
                      (s) =>
                          `<div class="temp-row"><span class="row">${icon(s.icon)}${escapeHTML(s.name)}</span><span class="temp-value">${temp(s.value, false)}<small>°${prefs.unit.toUpperCase()}</small></span></div>`,
                  )
                  .join("")
            : '<p class="muted" style="padding:16px 0">暂无可用温度。没有用模拟数据补齐。</p>';
        $("#legend-cpu").textContent = temp(cpu?.value ?? null);
        $("#legend-gpu").textContent = temp(gpu?.value ?? null);
        $("#menubar-reading").textContent =
            (cpu ? temp(cpu.value) : "温度 —") +
            (fans.length ? `  ${num(Math.round(fans[0].rpm))} RPM` : "");
        $("#trend-tooltip").textContent = "本次启动后的实测记录";
        $("#menu-mode").textContent = fans.length
            ? overallMode() === "external"
                ? "外部控制"
                : modeName(overallMode())
            : "仅温度监测";
        $("#menu-readings").innerHTML = fans
            .map(
                (f) =>
                    `<div class="popover-row"><span>${escapeHTML(f.name)}</span><strong>${num(Math.round(f.rpm))} RPM</strong></div>`,
            )
            .join("");
        renderChart();
    };
    renderChart = () => {
        const cutoff = Date.now() - Number(period) * 60000,
            samples = history.filter((s) => s.time >= cutoff);
        const values = samples
            .flatMap((s) => [s.cpu, s.gpu])
            .filter(Number.isFinite);
        const lower = values.length
            ? Math.floor((Math.min(...values) - 10) / 10) * 10
            : 20;
        const upper = Math.max(
            lower + 30,
            values.length
                ? Math.ceil((Math.max(...values) + 10) / 10) * 10
                : 80,
        );
        let html = [upper, (upper + lower) / 2, lower]
            .map((v) => {
                const y = 10 + ((upper - v) / (upper - lower)) * 105;
                return `<line class="grid" x1="28" x2="413" y1="${y}" y2="${y}"/><text x="0" y="${y + 3}">${temp(v, false)}°</text>`;
            })
            .join("");
        if (samples.length > 1) {
            const duration = Math.max(1, samples.at(-1).time - samples[0].time);
            for (const key of ["cpu", "gpu"]) {
                let path = "",
                    connected = false;
                for (const sample of samples) {
                    if (!Number.isFinite(sample[key])) {
                        connected = false;
                        continue;
                    }
                    const x =
                            28 +
                            ((sample.time - samples[0].time) / duration) * 385,
                        y =
                            10 +
                            ((upper - sample[key]) / (upper - lower)) * 105;
                    path += `${connected ? "L" : "M"}${x},${y} `;
                    connected = true;
                }
                html += `<path class="chart-line ${key === "gpu" ? "gpu" : ""}" d="${path}"/>`;
            }
        } else html += '<text x="135" y="63">正在积累本次启动后的读数…</text>';
        $("#temperature-chart").innerHTML = html;
        const minutes = samples.length
            ? Math.round((Date.now() - samples[0].time) / 60000)
            : 0;
        $("#chart-start").textContent = minutes
            ? `${minutes} 分钟前`
            : "本次启动";
        $("#chart-middle").textContent = "";
        $("#temperature-chart").setAttribute(
            "aria-label",
            "本次启动后的真实温度趋势",
        );
    };
    renderPreview = () => {
        if (!fans.length) return;
        originalPreview();
        if (draft.mode === "fixed") {
            const chosen = selectedFans().map((i) => fans[i]);
            const min = Math.max(...chosen.map((f) => f.min)),
                max = Math.min(...chosen.map((f) => f.max));
            if (Number.isFinite(draft.rpm) && max > min) {
                const y = 145 - ((draft.rpm - min) / (max - min)) * 115;
                $("#curve-chart").innerHTML =
                    `<path d="M40 20V145H265" fill="none" stroke="var(--line)"/><path d="M40 ${y}H258" stroke="var(--accent)" stroke-width="2.5"/><text x="150" y="170" text-anchor="middle" fill="var(--muted)" font-size="10">保持固定转速</text>`;
            }
        }
        $("#preview-note").textContent =
            "应用后由后台服务按真实风扇范围执行；只有收到服务确认，界面才会显示已应用。";
    };
    renderEditor = () => {
        if (!fans.length) {
            $("#control-blocked").classList.remove("hidden");
            $("#control-blocked").textContent = device?.fanDetectionAvailable
                ? "这台 Mac 没有可调节的风扇。"
                : "暂时无法确认风扇信息。";
            $(".control-layout").classList.add("hidden");
            return;
        }
        $(".control-layout").classList.remove("hidden");
        originalEditor();
        $(".scope-buttons").innerHTML =
            `<button data-scope="both" class="${scope === "both" ? "active" : ""}" aria-pressed="${scope === "both"}" ${available() ? "" : "disabled"}>全部风扇</button>` +
            fans
                .map(
                    (f, i) =>
                        `<button data-scope="${i}" class="${scope === String(i) ? "active" : ""}" aria-pressed="${scope === String(i)}" ${available() ? "" : "disabled"}>${escapeHTML(f.name)}</button>`,
                )
                .join("");
        if (!available())
            $("#control-blocked").textContent = pending
                ? "正在等待控制服务确认…"
                : device?.error ||
                  "当前仅监测。请使用已签名版本，并启用后台控制服务后再调速。";
        const chosen = selectedFans().map((i) => fans[i]),
            min = Math.max(...chosen.map((f) => f.min)),
            max = Math.min(...chosen.map((f) => f.max));
        if (draft.mode === "fixed") {
            for (const id of ["rpm-range", "rpm-number"]) {
                const input = $("#" + id);
                if (input) {
                    input.min = min;
                    input.max = max;
                }
            }
            $(".range-labels").innerHTML =
                `<span>${num(min)} RPM</span><span>${num(max)} RPM</span>`;
        }
        const notice = $(".config-area .notice");
        if (notice)
            notice.textContent =
                draft.mode === "sensor"
                    ? `低于 ${temp(draft.start)} 时保持硬件报告的最低转速；到 ${temp(draft.end)} 时达到最高转速。参数需按实际机型和部件选择。`
                    : draft.mode === "full"
                      ? "风扇会保持最高转速，噪音明显增加。完成高负载任务后可以恢复系统自动。"
                      : draft.mode === "auto"
                        ? "不由应用指定转速，恢复后由 macOS 自动管理。"
                        : "固定转速不会随负载提高；如果不确定合适数值，请保持系统自动。";
        $("#apply-control").disabled =
            !available() || !draftChanged() || !!draftError();
    };
    const savedConfigs = () =>
        fans.map((f) => ({ id: f.id, config: { ...f.config } }));
    async function perform(request, message, recordUndo = true) {
        if (pending) return;
        const before = savedConfigs();
        pending = true;
        renderStatus();
        renderEditor();
        updateDraftState();
        $("#apply-control").disabled = true;
        try {
            await call(request.command, request);
            if (recordUndo) nativeUndo = before;
            await poll(true);
            loadDraft();
            notify(message, recordUndo);
        } catch (error) {
            notify(String(error.message || error));
            await poll(true);
        } finally {
            pending = false;
            renderStatus();
            if (page === "control") renderEditor();
        }
    }
    applyDraft = () => {
        if (!available() || draftError()) return;
        return perform(
            {
                command: "apply",
                fanIDs: selectedFans().map((i) => fans[i].id),
                config: draft,
            },
            "设置已由控制服务确认",
        );
    };
    resetFans = () => perform({ command: "reset" }, "已确认恢复系统自动");
    undoChange = async () => {
        if (!nativeUndo || !available()) return;
        const before = nativeUndo;
        pending = true;
        try {
            for (const entry of before) {
                if (entry.config.mode === "external") continue;
                await call("apply", {
                    fanIDs: [entry.id],
                    config: entry.config,
                });
            }
            await poll(true);
            loadDraft();
            notify("已撤销上次调节");
            nativeUndo = null;
        } catch (error) {
            notify("撤销未完成：" + String(error.message || error));
            await poll(true);
        } finally {
            pending = false;
            renderAll();
        }
    };
    async function poll(force = false) {
        if (pollRunning && !force) return;
        pollRunning = true;
        const sequence = ++pollSequence;
        try {
            const latest = await call("snapshot");
            if (sequence === pollSequence) receive(latest);
        } catch (error) {
            if (sequence !== pollSequence) return;
            device = {
                ...device,
                canControl: false,
                error: String(error.message || error),
            };
            if (initialized) renderStatus();
            else {
                document.body.dataset.loadError = "无法读取本机数据，正在重试…";
            }
        } finally {
            if (sequence === pollSequence) pollRunning = false;
        }
    }
    function receive(state) {
        if (!Array.isArray(state.fans) || !Array.isArray(state.sensors))
            throw Error("设备返回无效读数");
        const oldFans = JSON.stringify(
            fans.map((f) => [f.id, f.config, f.min, f.max]),
        );
        const oldSensors = sensors.map((s) => s.id).join();
        device = state;
        fans.splice(0, fans.length, ...state.fans);
        sensors.splice(0, sensors.length, ...state.sensors);
        if (!initialized || !selectedFans().length) scope = "both";
        if (!initialized) {
            prefs.stars = prefs.stars.filter((id) =>
                sensors.some((s) => s.id === id),
            );
            if (!prefs.stars.length)
                prefs.stars = sensors.slice(0, 3).map((s) => s.id);
            draft = {
                ...(fans[0]?.config || defaultConfig()),
                sensor: sensors[0]?.id || "",
            };
            if (draft.mode === "external") draft.mode = "auto";
        }
        const dirty = draftChanged();
        renderPrefs();
        renderStatus();
        const structureChanged =
            oldFans !==
            JSON.stringify(fans.map((f) => [f.id, f.config, f.min, f.max]));
        if (!initialized || structureChanged) renderFans();
        else refreshLiveReadings();
        if (!initialized || oldSensors !== sensors.map((s) => s.id).join())
            renderSensors();
        const cpu = sensorFor("cpu"),
            gpu = sensorFor("gpu");
        history.push({ time: Date.now(), cpu: cpu?.value, gpu: gpu?.value });
        while (history.length && history[0].time < Date.now() - 3600000)
            history.shift();
        renderReadings();
        if (!initialized) renderEditor();
        else if (page === "control") {
            renderPreview();
            updateDraftState();
            $("#apply-control").disabled =
                !available() || !dirty || !!draftError();
        }
        initialized = true;
        document.body.classList.remove("native-loading");
    }
    document.addEventListener(
        "click",
        (event) => {
            const button = event.target.closest("button");
            if (!button || button.disabled) return;
            if (
                button.dataset.action === "authorize" ||
                button.dataset.dialog === "authorize"
            ) {
                event.stopImmediatePropagation();
                event.preventDefault();
                call("authorize")
                    .then(() => {
                        notify("请在系统设置中允许后台服务，然后返回此窗口。");
                        poll(true);
                    })
                    .catch((error) => notify(String(error.message || error)));
                return;
            }
            if (button.dataset.dialog === "full") {
                event.stopImmediatePropagation();
                event.preventDefault();
                closeDialog();
                perform(
                    {
                        command: "apply",
                        fanIDs: fans.map((f) => f.id),
                        config: { ...defaultConfig(), mode: "full" },
                    },
                    "全速散热已由控制服务确认",
                );
                return;
            }
            if (button.dataset.mode === "full") {
                event.stopImmediatePropagation();
                openDialog(
                    "将所有风扇调至全速？",
                    "请确认各风扇的实际最高转速",
                    `<p class="dialog-copy">噪音会明显增加。可随时恢复系统自动。</p><div class="comparison">${fans.map((f) => `<div><span>${escapeHTML(f.name)}</span><strong>${num(f.max)} RPM</strong></div>`).join("")}</div>`,
                    '<button class="btn" data-dialog="close">取消</button><button class="btn primary" data-dialog="full">应用全速散热</button>',
                );
                return;
            }
            if (button.id === "reset-demo") {
                event.stopImmediatePropagation();
                prefs = {
                    unit: "c",
                    theme: "system",
                    stars: sensors.slice(0, 3).map((s) => s.id),
                };
                save();
                renderAll();
                notify("显示偏好已恢复默认，风扇运行方式未改变");
                return;
            }
            if (button.dataset.action === "guide") {
                event.stopImmediatePropagation();
                openDialog(
                    "如何使用 Better Fan",
                    "系统自动适合大多数日常使用",
                    `<p class="dialog-copy">总览显示这台 Mac 的真实读数。若未启用辅助服务，应用只监测，不改变风扇。<br><br>启用控制后，选择单只或全部风扇，再选择系统自动、随温度调节、固定转速或全速散热。编辑不立即生效，点击“应用设置”并收到服务确认后才会执行。<br><br>服务会在连接失效、心跳超时、系统睡眠或热压力升高时尝试将本应用控制的风扇交回系统。若硬件拒绝恢复，界面会保留错误，不能保证恢复成功。</p>`,
                    '<button class="btn primary" data-dialog="close">知道了</button>',
                );
                return;
            }
        },
        true,
    );
    $("#setting-menubar").addEventListener("click", () =>
        call("menuVisibility", {
            visible:
                $("#setting-menubar").getAttribute("aria-checked") === "true",
        }).catch((error) => notify(String(error.message || error))),
    );
    $("#setting-live").closest(".setting-row").hidden = true;
    $("#page-settings h2:nth-of-type(2)").textContent = "显示偏好";
    $("#reset-demo").textContent = "恢复默认显示";
    $("#reset-demo")
        .closest(".setting-row")
        .querySelector("strong").textContent = "重置显示偏好";
    $("#reset-demo").closest(".setting-row").querySelector("p").textContent =
        "恢复单位、外观和关注列表；不改变风扇设置";
    $("#page-overview .page-heading p").textContent =
        "了解这台 Mac 的真实运行状态，再选择散热方式。";
    $("#page-sensors .page-heading p").textContent =
        "仅显示此机型当前可读取的传感器，保留原始 SMC 名称。";
    $("#menubar .tag").textContent = "快捷控制";
    window.BetterFanNative = { receive, notice: notify };
    poll();
    setInterval(() => poll(), 2000);
}
