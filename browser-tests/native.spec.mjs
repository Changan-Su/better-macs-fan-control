import { test, expect } from "@playwright/test";
async function mockNative(
    page,
    { signed = true, canControl = true, fanCount = 1 } = {},
) {
    await page.addInitScript(
        ({ signed, canControl, fanCount }) => {
            window.BETTER_FAN_NATIVE = true;
            window.calls = [];
            window.confirmApply = false;
            window.rejectApply = false;
            const state = {
                fans: Array.from({ length: fanCount }, (_, id) => ({
                    id,
                    name: "实测风扇 " + (id + 1),
                    min: 1500,
                    max: 5300,
                    rpm: 1900,
                    controllable: true,
                    config: {
                        mode: "auto",
                        rpm: 2600,
                        sensor: "TC0P",
                        start: 55,
                        end: 80,
                    },
                })),
                sensors: [
                    {
                        id: "TC0P",
                        raw: "TC0P",
                        name: "CPU 接近温度",
                        value: 61,
                        group: "chip",
                        icon: "chip",
                    },
                ],
                fanDetectionAvailable: true,
                deviceName: "TestMac1,1",
                deviceModel: "macOS 测试夹具",
                signed,
                canControl,
                serviceStatus: "enabled",
                thermalState: 0,
            };
            window.webkit = {
                messageHandlers: {
                    native: {
                        postMessage: async (request) => {
                            window.calls.push(request);
                            if (request.command === "snapshot")
                                return structuredClone(state);
                            if (request.command === "apply") {
                                if (window.rejectApply)
                                    throw Error("硬件拒绝写入");
                                await new Promise((resolve) => {
                                    window.finishApply = resolve;
                                });
                                for (const f of state.fans)
                                    if (request.fanIDs.includes(f.id))
                                        f.config = request.config;
                                return { ok: true };
                            }
                            if (request.command === "reset") {
                                for (const f of state.fans)
                                    f.config.mode = "auto";
                                return { ok: true };
                            }
                            return { ok: true };
                        },
                    },
                },
            };
            document.addEventListener("DOMContentLoaded", () =>
                document.body.classList.add("native-mode"),
            );
        },
        { signed, canControl, fanCount },
    );
    await page.goto("/native/");
    await expect(page.locator("#device-name")).toHaveText("TestMac1,1");
}
test("native shows measured data and actual hardware bounds", async ({
    page,
}) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await mockNative(page);
    await expect(page.locator(".fan-reading strong")).toHaveText("1,900");
    await expect(page.locator("#fan-count")).toHaveText("1 只风扇");
    await page.locator('[data-mode="fixed"]').click();
    await expect(page.locator("#rpm-number")).toHaveAttribute("min", "1500");
    await expect(page.locator("#rpm-number")).toHaveAttribute("max", "5300");
    await page.locator("#rpm-number").fill("1200");
    await expect(page.locator("#apply-control")).toBeDisabled();
    expect(errors).toEqual([]);
});
test("native commits only after service confirmation", async ({ page }) => {
    await mockNative(page);
    await page.locator('[data-mode="fixed"]').click();
    await page.locator("#rpm-number").fill("3000");
    await page.locator("#apply-control").click();
    await expect(page.locator("#footer-control")).toHaveText("控制权：macOS");
    await expect(page.locator("#apply-control")).toBeDisabled();
    await page.evaluate(() => window.finishApply());
    await expect(page.locator("#footer-control")).toHaveText(
        "控制权：Better Fan",
    );
    const requests = await page.evaluate(() =>
        window.calls.filter((x) => x.command === "apply"),
    );
    expect(requests[0].fanIDs).toEqual([0]);
    expect(requests[0].config.rpm).toBe(3000);
});
test("native failure does not claim application", async ({ page }) => {
    await mockNative(page);
    await page.evaluate(() => (window.rejectApply = true));
    await page.locator('[data-mode="fixed"]').click();
    await page.locator("#apply-control").click();
    await expect(page.locator("#toast")).toContainText("硬件拒绝写入");
    await expect(page.locator("#footer-control")).toHaveText("控制权：macOS");
});
test("unsigned build remains read-only with real readings", async ({
    page,
}) => {
    await mockNative(page, { signed: false, canControl: false });
    await expect(page.locator('[data-mode="full"]')).toBeDisabled();
    await expect(page.locator("#overview-status")).toContainText(
        "仅支持真实监测",
    );
    await expect(page.locator(".fan-reading strong")).toHaveText("1,900");
});
test("native fanless device does not render simulated fans", async ({
    page,
}) => {
    await mockNative(page, { fanCount: 0 });
    await expect(page.locator("#fanless-state")).toBeVisible();
    await expect(page.locator(".fan-card")).toHaveCount(0);
    await page.locator('.nav [data-page="control"]').click();
    await expect(page.locator("#control-blocked")).toContainText("没有可调节");
});
