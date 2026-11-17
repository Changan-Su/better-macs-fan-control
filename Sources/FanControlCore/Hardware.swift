import Foundation
import IOKit

public final class SMCHardware: FanDriver {
    private let smc = SMC()
    private var temperatureKeys: [String]?
    public init() {}
    public func readTelemetry() -> Telemetry {
        let count = smc.getValue("FNum")
        let number = count.flatMap { $0.isFinite && $0 >= 0 && $0 <= 10 ? Int($0) : nil }
        var fans: [FanReading] = []
        for id in 0..<(number ?? 0) {
            guard let rpm = smc.getValue("F\(id)Ac"), rpm.isFinite else { continue }
            let minimum = smc.getValue("F\(id)Mn") ?? 0
            let maximum = smc.getValue("F\(id)Mx") ?? 0
            let mode = smc.getValue(smc.fanModeKey(id))
            let mask = smc.getValue("FS! ").map { Int($0) }
            let automatic = mode.map { $0 == 0 || $0 == 3 } ?? mask.map { $0 & (1 << id) == 0 }
            fans.append(
                FanReading(
                    id: id, name: number == 2 ? (id == 0 ? "左侧风扇" : "右侧风扇") : "风扇 \(id + 1)",
                    min: minimum, max: maximum, rpm: rpm,
                    config: .init(mode: automatic == true ? .auto : .external),
                    controllable: maximum > minimum && mode != nil
                        || maximum > minimum && mask != nil))
        }
        if temperatureKeys == nil {
            let keys = smc.getAllKeys().filter { $0.hasPrefix("T") }
            if !keys.isEmpty { temperatureKeys = keys }
        }
        let names = [
            "TC0P": "CPU 接近温度", "TC0D": "CPU 核心温度", "TC0E": "CPU 温度", "TG0P": "GPU 接近温度",
            "TG0D": "GPU 核心温度", "TB0T": "电池温度", "TB1T": "电池温度 2", "TA0P": "进风口温度",
        ]
        let sensors = (temperatureKeys ?? []).compactMap { key -> TemperatureReading? in
            guard let value = smc.getValue(key), value.isFinite, value > 0, value < 130 else {
                return nil
            }
            let cpu = key.hasPrefix("TC") || key.hasPrefix("Tp")
            let gpu = key.hasPrefix("TG") || key.hasPrefix("Tg")
            return TemperatureReading(
                id: key,
                name: names[key]
                    ?? (cpu ? "CPU 温度（\(key)）" : gpu ? "GPU 温度（\(key)）" : "温度传感器 \(key)"),
                value: value, group: cpu || gpu ? "chip" : "other",
                icon: cpu ? "chip" : gpu ? "gpu" : "temp")
        }.sorted { ($0.group == "chip" ? 0 : 1, $0.id) < ($1.group == "chip" ? 0 : 1, $1.id) }
        return Telemetry(
            fans: fans, sensors: sensors,
            fanDetectionAvailable: number != nil && fans.count == number)
    }
    public func setManual(fan id: Int, rpm: Double) throws {
        guard (0...9).contains(id), rpm.isFinite, rpm >= 0, rpm <= 20000 else {
            throw FanError.message("无效的风扇控制参数。")
        }
        if smc.getValue(smc.fanModeKey(id)) != 1 { smc.setFanMode(id, mode: .forced) }
        smc.setFanSpeed(id, speed: Int(rpm.rounded()))
        let mode = smc.getValue(smc.fanModeKey(id))
        let forced = mode == 1 || (mode == nil && (Int(smc.getValue("FS! ") ?? 0) & (1 << id)) != 0)
        guard forced, let actual = smc.getValue("F\(id)Tg"), abs(actual - rpm) <= 5 else {
            throw FanError.message("SMC 未确认调速。请恢复系统自动，并检查机型支持或控制权限。")
        }
    }
    public func restoreAutomatic(fan id: Int) throws {
        guard (0...9).contains(id) else { throw FanError.message("风扇编号无效。") }
        smc.setFanMode(id, mode: .automatic)
        let mode = smc.getValue(smc.fanModeKey(id))
        let mask = smc.getValue("FS! ")
        guard
            mode == 0 || mode == 3 || (mode == nil && mask != nil && (Int(mask!) & (1 << id)) == 0)
        else { throw FanError.message("未能确认风扇已恢复自动，请检查其他风扇应用。") }
        #if arch(arm64)
            // Ftst is global: release it only when no fan remains in manual mode.
            if let count = smc.getValue("FNum"),
                (0..<Int(count)).allSatisfy({
                    let m = smc.getValue(smc.fanModeKey($0))
                    return m == 0 || m == 3
                })
            {
                guard smc.resetFanControl() else { throw FanError.message("未能释放全局风扇控制，请重试恢复自动。") }
            }
        #endif
    }
}
