import AppKit
import FanControlCore
import ServiceManagement
import WebKit

final class HardwareService {
    let queue = DispatchQueue(label: "com.changansu.BetterFan.reader")
    let hardware = SMCHardware()
    var connection: NSXPCConnection?
    var latestError: String?
    var activity: NSObjectProtocol?
    let service = SMAppService.daemon(plistName: helperServiceName + ".plist")
    var signed: Bool { CodeIdentity.teamID() != nil }

    func helper(_ request: ControlRequest, completion: @escaping (ControlReply) -> Void) {
        guard signed else {
            completion(
                .init(ok: false, error: "此版本未使用 Developer ID 签名，仅支持真实监测。风扇控制需要已签名版本和后台服务授权。"))
            return
        }
        if connection == nil {
            let peer = NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
            peer.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
            if let team = CodeIdentity.teamID(),
                let requirement = CodeIdentity.requirement(
                    identifier: helperServiceName, team: team)
            {
                peer.setCodeSigningRequirement(requirement)
            }
            peer.invalidationHandler = { [weak self] in
                DispatchQueue.main.async { self?.connection = nil }
            }
            peer.interruptionHandler = { [weak self] in
                DispatchQueue.main.async {
                    self?.connection?.invalidate()
                    self?.connection = nil
                }
            }
            peer.resume()
            connection = peer
        }
        var finished = false
        let finish: (ControlReply) -> Void = { response in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(response)
            }
        }
        guard
            let proxy = connection?.remoteObjectProxyWithErrorHandler({
                finish(.init(ok: false, error: "控制服务连接失败：" + $0.localizedDescription))
            }) as? FanHelperProtocol,
            let data = try? JSONEncoder().encode(request)
        else {
            finish(.init(ok: false, error: "无法创建控制请求。"))
            return
        }
        proxy.request(data) { data in
            finish(
                (try? JSONDecoder().decode(ControlReply.self, from: data))
                    ?? .init(ok: false, error: "控制服务返回了无效结果。"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) {
            finish(.init(ok: false, error: "控制服务响应超时。请检查后台服务；连接中断时辅助服务会尝试交回系统。"))
        }
    }

    func snapshot(completion: @escaping ([String: Any]) -> Void) {
        if signed && service.status == .enabled {
            helper(.init(command: "snapshot")) { response in
                if response.ok, let telemetry = response.telemetry {
                    self.latestError = response.error
                    completion(self.state(telemetry, canControl: true))
                } else {
                    self.latestError = response.error
                    self.read(completion: completion)
                }
            }
        } else {
            read(completion: completion)
        }
    }
    func read(completion: @escaping ([String: Any]) -> Void) {
        queue.async {
            let telemetry = self.hardware.readTelemetry()
            DispatchQueue.main.async { completion(self.state(telemetry, canControl: false)) }
        }
    }
    func state(_ telemetry: Telemetry, canControl: Bool) -> [String: Any] {
        let overriding = telemetry.fans.contains {
            [.fixed, .sensor, .full].contains($0.config.mode)
        }
        if overriding && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "保持风扇调节服务心跳")
        }
        if !overriding, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        let data = (try? JSONEncoder().encode(telemetry)) ?? Data()
        var result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        result["deviceName"] = String(cString: bytes)
        result["deviceModel"] = ProcessInfo.processInfo.operatingSystemVersionString
        result["canControl"] = canControl
        result["signed"] = signed
        result["serviceStatus"] =
            service.status == .requiresApproval
            ? "requiresApproval" : service.status == .enabled ? "enabled" : "notRegistered"
        result["error"] = latestError
        result["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
        return result
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandlerWithReply,
    WKNavigationDelegate, NSWindowDelegate
{
    var window: NSWindow!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    let hardware = HardwareService()
    var terminatePending = false
    var heartbeatTimer: DispatchSourceTimer?
    let smokeTest = CommandLine.arguments.contains("--smoke-test")
    var interfaceURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(smokeTest ? .prohibited : .regular)
        let appMenu = NSMenu()
        let root = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(
            withTitle: "关于 Better Fan",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(
            withTitle: "退出 Better Fan", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        root.submenu = submenu
        appMenu.addItem(root)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [
            ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a"),
            ("剪切", "cut:", "x"),
        ] {
            edit.addItem(
                withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        editItem.submenu = edit
        appMenu.addItem(editItem)
        NSApp.mainMenu = appMenu
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addScriptMessageHandler(
            self, contentWorld: .page, name: "native")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source:
                    "window.BETTER_FAN_NATIVE = true; document.addEventListener('DOMContentLoaded',()=>document.body.classList.add('native-mode','native-loading'));",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1190, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Better Fan"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 820, height: 650)
        window.contentView = web
        window.delegate = self
        if !smokeTest {
            window.setFrameAutosaveName("BetterFanWindow")
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html") else {
            showFatal("缺少界面资源，请重新安装完整应用。")
            return
        }
        interfaceURL = url.standardizedFileURL
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        if smokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                fputs("Native interface did not finish loading.\n", stderr)
                exit(1)
            }
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "fanblades", accessibilityDescription: "Better Fan")
        let menu = NSMenu()
        let show = NSMenuItem(
            title: "打开 Better Fan", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let reset = NSMenuItem(title: "恢复系统自动", action: #selector(resetFans), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 4, repeating: 4)
        timer.setEventHandler { [weak self] in
            guard let self, self.hardware.activity != nil, self.hardware.connection != nil else {
                return
            }
            self.hardware.helper(.init(command: "heartbeat")) { response in
                if !response.ok { self.hardware.latestError = response.error }
            }
        }
        timer.resume()
        heartbeatTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(resetFans), name: NSWorkspace.willSleepNotification,
            object: nil)
    }
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func resetFans() {
        hardware.helper(.init(command: "reset")) { [weak self] response in
            self?.emitNotice(response.ok ? "已确认恢复系统自动" : response.error ?? "恢复自动失败")
        }
    }
    func emitNotice(_ text: String) {
        if let data = try? JSONSerialization.data(withJSONObject: [text]),
            let json = String(data: data, encoding: .utf8)
        {
            web.evaluateJavaScript("window.BetterFanNative?.notice(\(json)[0])")
        }
    }
    func showFatal(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        showWindow()
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !hardware.signed || hardware.connection == nil { return .terminateNow }
        if terminatePending { return .terminateLater }
        terminatePending = true
        hardware.helper(.init(command: "reset")) { response in
            if response.ok {
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                let alert = NSAlert()
                alert.messageText = "尚未确认风扇已恢复系统自动"
                alert.informativeText = response.error ?? "请重试恢复自动。"
                alert.addButton(withTitle: "返回并重试")
                alert.addButton(withTitle: "仍然退出")
                let quit = alert.runModal() == .alertSecondButtonReturn
                self.terminatePending = false
                NSApp.reply(toApplicationShouldTerminate: quit)
            }
        }
        return .terminateLater
    }
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL, url.standardizedFileURL == interfaceURL {
            decisionHandler(.allow)
        } else {
            if navigationAction.navigationType == .linkActivated,
                ["https", "http"].contains(url.scheme)
            {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
    func verifySmokeTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.web.evaluateJavaScript(
                """
                Boolean(window.BetterFanNative &&
                    document.getElementById('device-name')?.textContent !== 'MacBook Pro 14″' &&
                    !document.body.classList.contains('native-loading') &&
                    document.querySelector('.app-footer > span:last-child')?.textContent === '仅监测')
                """
            ) { result, error in
                if result as? Bool == true {
                    print("Native interface rendered macOS telemetry in monitoring mode.")
                    exit(0)
                }
                if let error { fputs("Native interface: \(error.localizedDescription)\n", stderr) }
            }
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.frameInfo.isMainFrame,
            message.frameInfo.request.url?.standardizedFileURL == interfaceURL,
            let body = message.body as? [String: Any], let command = body["command"] as? String
        else {
            replyHandler(nil, "拒绝不可信请求。")
            return
        }
        if command == "snapshot" {
            if smokeTest {
                hardware.read { state in
                    replyHandler(state, nil)
                    self.verifySmokeTest()
                }
            } else {
                hardware.snapshot { state in
                    let first = (state["fans"] as? [[String: Any]])?.first
                    let rpm = first?["rpm"] as? Double
                    self.statusItem.button?.title = rpm.map { " \(Int($0)) RPM" } ?? ""
                    replyHandler(state, nil)
                }
            }
            return
        }
        guard !smokeTest else {
            replyHandler(nil, "Smoke test is read-only.")
            return
        }
        if command == "menuVisibility" {
            statusItem.isVisible = body["visible"] as? Bool ?? true
            replyHandler(["ok": true], nil)
            return
        }
        if command == "authorize" {
            guard hardware.signed else {
                replyHandler(nil, "此构建未使用 Developer ID 签名，仅支持监测。请使用已签名版本后启用控制服务。")
                return
            }
            guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
                replyHandler(nil, "请先将 Better Fan 拖入“应用程序”文件夹，再启用控制服务。")
                return
            }
            do {
                if hardware.service.status == .notRegistered { try hardware.service.register() }
                if hardware.service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
                replyHandler(["ok": true], nil)
            } catch { replyHandler(nil, error.localizedDescription) }
            return
        }
        if command == "apply" || command == "reset" {
            do {
                let data = try JSONSerialization.data(withJSONObject: body)
                let request = try JSONDecoder().decode(ControlRequest.self, from: data)
                hardware.helper(request) { response in
                    if response.ok {
                        replyHandler(["ok": true], nil)
                    } else {
                        replyHandler(nil, response.error ?? "操作未成功，当前设置未确认。")
                    }
                }
            } catch { replyHandler(nil, error.localizedDescription) }
            return
        }
        replyHandler(nil, "不支持的操作。")
    }
}

let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.run()
