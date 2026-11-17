import FanControlCore
import Foundation
import IOKit.pwr_mgt

final class Helper: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "com.changansu.BetterFan.controller")
    let controller = FanController(driver: SMCHardware())
    var owner: UUID?
    var heartbeat = ProcessInfo.processInfo.systemUptime
    var timer: DispatchSourceTimer?
    var signals: [DispatchSourceSignal] = []
    var powerPort: io_connect_t = 0
    var notificationPort: IONotificationPortRef?
    var notifier: io_object_t = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        guard connection.effectiveUserIdentifier != 0,
            let team = CodeIdentity.teamID(),
            let requirement = CodeIdentity.requirement(identifier: appBundleIdentifier, team: team)
        else { return false }
        connection.setCodeSigningRequirement(requirement)
        let id = UUID()
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = Session(helper: self, id: id)
        let disconnected: () -> Void = { [weak self] in
            self?.queue.async { [weak self] in
                guard let self, self.owner == id else { return }
                self.owner = nil
                try? self.controller.restoreOwned()
            }
        }
        connection.invalidationHandler = disconnected
        connection.interruptionHandler = disconnected
        connection.resume()
        return true
    }

    func handle(_ data: Data, session: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            do {
                guard data.count <= 65536 else { throw FanError.message("请求过大。") }
                let request = try JSONDecoder().decode(ControlRequest.self, from: data)
                switch request.command {
                case "snapshot", "heartbeat":
                    if self.owner == session {
                        self.heartbeat = ProcessInfo.processInfo.systemUptime
                    }
                case "apply":
                    guard self.owner == nil || self.owner == session else {
                        throw FanError.message("另一窗口正在控制风扇。")
                    }
                    guard let ids = request.fanIDs, let config = request.config else {
                        throw FanError.message("调速参数不完整。")
                    }
                    let thermal = ProcessInfo.processInfo.thermalState
                    guard config.mode == .auto || (thermal != .serious && thermal != .critical)
                    else { throw FanError.message("系统正处于热压力状态，请使用系统自动。") }
                    try self.controller.apply(ids: ids, config: config)
                    self.owner = self.controller.hasOverrides ? session : nil
                    self.heartbeat = ProcessInfo.processInfo.systemUptime
                case "reset":
                    guard self.owner == nil || self.owner == session else {
                        throw FanError.message("另一窗口正在控制风扇。")
                    }
                    try self.controller.restoreOwned()
                    self.owner = nil
                default: throw FanError.message("不支持的操作。")
                }
                reply(
                    ControlReply(
                        ok: true, error: self.controller.lastFailure,
                        telemetry: self.controller.telemetry()
                    ).data())
            } catch {
                reply(
                    ControlReply(
                        ok: false, error: error.localizedDescription,
                        telemetry: self.controller.telemetry()
                    ).data())
            }
        }
    }

    func startGuards() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let state = ProcessInfo.processInfo.thermalState
            do {
                try self.controller.tick(
                    leaseExpired: ProcessInfo.processInfo.systemUptime - self.heartbeat > 15,
                    thermalEmergency: state == .serious || state == .critical)
            } catch { NSLog("Better Fan: %@", error.localizedDescription) }
            if !self.controller.hasOverrides { self.owner = nil }
        }
        timer.resume()
        self.timer = timer
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in
                try? self?.controller.restoreOwned()
                exit(0)
            }
            source.resume()
            signals.append(source)
        }
        powerPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(), &notificationPort,
            { context, _, type, argument in
                guard let context else { return }
                let helper = Unmanaged<Helper>.fromOpaque(context).takeUnretainedValue()
                let token = Int(bitPattern: argument)
                if type == UInt32(0xe000_0280) {
                    helper.queue.async {
                        try? helper.controller.restoreOwned()
                        helper.owner = nil
                        IOAllowPowerChange(helper.powerPort, token)
                    }
                } else if type == UInt32(0xe000_0270) {
                    IOAllowPowerChange(helper.powerPort, token)
                }
            }, &notifier)
        if let notificationPort,
            let source = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue()
        {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
}

final class Session: NSObject, FanHelperProtocol {
    let helper: Helper
    let id: UUID
    init(helper: Helper, id: UUID) {
        self.helper = helper
        self.id = id
    }
    func request(_ data: Data, withReply reply: @escaping (Data) -> Void) {
        helper.handle(data, session: id, reply: reply)
    }
}

guard geteuid() == 0 else {
    fputs("BetterFanHelper must be launched by SMAppService.\n", stderr)
    exit(1)
}
guard CodeIdentity.teamID() != nil else {
    fputs("A Developer ID signed build is required for privileged control.\n", stderr)
    exit(1)
}
let helper = Helper()
let listener = NSXPCListener(machServiceName: helperServiceName)
listener.delegate = helper
helper.startGuards()
listener.resume()
RunLoop.main.run()
