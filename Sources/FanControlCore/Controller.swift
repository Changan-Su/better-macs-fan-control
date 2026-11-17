import Foundation

public protocol FanDriver: AnyObject {
    func readTelemetry() -> Telemetry
    func setManual(fan: Int, rpm: Double) throws
    func restoreAutomatic(fan: Int) throws
}

/// Owned only by the helper's serial queue. No hardware write occurs on initialization.
public final class FanController {
    private let driver: FanDriver
    public private(set) var configurations: [Int: FanConfiguration] = [:]
    public private(set) var lastFailure: String?
    public var hasOverrides: Bool { !configurations.isEmpty }
    public init(driver: FanDriver) { self.driver = driver }

    public func telemetry() -> Telemetry {
        var result = driver.readTelemetry()
        for i in result.fans.indices {
            if let config = configurations[result.fans[i].id] { result.fans[i].config = config }
        }
        return result
    }

    public func apply(ids: [Int], config: FanConfiguration) throws {
        let current = driver.readTelemetry()
        guard current.fanDetectionAvailable, !ids.isEmpty, ids.count <= 10,
            Set(ids).count == ids.count
        else {
            throw FanError.message("无法确认风扇，或作用范围无效。")
        }
        guard config.mode != .external else { throw FanError.message("不支持该控制方式。") }
        var targets: [(FanReading, Double?)] = []
        for id in ids {
            guard let fan = current.fans.first(where: { $0.id == id }), fan.controllable else {
                throw FanError.message("这只风扇无法调节。")
            }
            if config.mode == .auto, configurations[id] == nil { continue }
            if fan.config.mode == .external, configurations[id] == nil {
                throw FanError.message("风扇正由其他应用控制，请先在该应用中恢复自动。")
            }
            targets.append((fan, try Self.target(config, fan: fan, sensors: current.sensors)))
        }
        // Validate the entire batch before the first write. On a partial failure, restore every affected fan.
        var touched: [Int] = []
        do {
            for (fan, rpm) in targets {
                touched.append(fan.id)
                if let rpm {
                    configurations[fan.id] = config
                    try driver.setManual(fan: fan.id, rpm: rpm)
                } else {
                    try driver.restoreAutomatic(fan: fan.id)
                    configurations.removeValue(forKey: fan.id)
                }
            }
            lastFailure = nil
        } catch {
            for id in touched {
                do {
                    try driver.restoreAutomatic(fan: id)
                    configurations.removeValue(forKey: id)
                } catch { lastFailure = error.localizedDescription }
            }
            throw error
        }
    }

    public static func target(
        _ config: FanConfiguration, fan: FanReading, sensors: [TemperatureReading]
    ) throws -> Double? {
        guard fan.min.isFinite, fan.max.isFinite, fan.min >= 0, fan.max > fan.min, fan.max <= 20000
        else { throw FanError.message("风扇转速范围无效，保持系统控制。") }
        switch config.mode {
        case .auto: return nil
        case .full: return fan.max
        case .fixed:
            guard config.rpm.isFinite, config.rpm >= fan.min, config.rpm <= fan.max else {
                throw FanError.message("目标转速超出该风扇的实际范围。")
            }
            return config.rpm.rounded()
        case .sensor:
            guard config.start.isFinite, config.end.isFinite, config.start >= 20, config.end <= 100,
                config.end - config.start >= 4.999,
                let sensor = sensors.first(where: { $0.id == config.sensor }), sensor.value.isFinite
            else { throw FanError.message("温度参数无效，或参考传感器已不可用。") }
            let fraction = min(
                1, max(0, (sensor.value - config.start) / (config.end - config.start)))
            return (fan.min + (fan.max - fan.min) * fraction).rounded()
        case .external: throw FanError.message("不支持的控制方式。")
        }
    }

    public func restoreOwned() throws {
        var failures: [String] = []
        for id in Array(configurations.keys) {
            do {
                try driver.restoreAutomatic(fan: id)
                configurations.removeValue(forKey: id)
            } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty {
            lastFailure = failures.joined(separator: "；")
            throw FanError.message(lastFailure!)
        }
    }

    public func tick(leaseExpired: Bool, thermalEmergency: Bool) throws {
        guard hasOverrides else { return }
        if leaseExpired || thermalEmergency || lastFailure != nil {
            try restoreOwned()
            return
        }
        let current = driver.readTelemetry()
        guard current.fanDetectionAvailable else {
            try restoreOwned()
            throw FanError.message("设备读数丢失，已尝试交回系统。")
        }
        do {
            for (id, config) in configurations {
                guard let fan = current.fans.first(where: { $0.id == id }),
                    let rpm = try Self.target(config, fan: fan, sensors: current.sensors)
                else { throw FanError.message("风扇或传感器不可用。") }
                try driver.setManual(fan: id, rpm: rpm)
            }
        } catch {
            try? restoreOwned()
            lastFailure = error.localizedDescription
            throw error
        }
    }
}
