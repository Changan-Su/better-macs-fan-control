import Foundation

public enum ControlMode: String, Codable { case auto, fixed, sensor, full, external }

public struct FanConfiguration: Codable, Equatable {
    public var mode: ControlMode
    public var rpm: Double
    public var sensor: String
    public var start: Double
    public var end: Double
    public init(
        mode: ControlMode = .auto, rpm: Double = 2600, sensor: String = "", start: Double = 55,
        end: Double = 80
    ) {
        self.mode = mode
        self.rpm = rpm
        self.sensor = sensor
        self.start = start
        self.end = end
    }
}

public struct FanReading: Codable {
    public var id: Int
    public var name: String
    public var min: Double
    public var max: Double
    public var rpm: Double
    public var config: FanConfiguration
    public var controllable: Bool
    public init(
        id: Int, name: String, min: Double, max: Double, rpm: Double,
        config: FanConfiguration = .init(), controllable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.min = min
        self.max = max
        self.rpm = rpm
        self.config = config
        self.controllable = controllable
    }
}

public struct TemperatureReading: Codable {
    public var id: String
    public var name: String
    public var raw: String
    public var value: Double
    public var group: String
    public var icon: String
    public init(
        id: String, name: String, value: Double, group: String = "other", icon: String = "temp"
    ) {
        self.id = id
        self.raw = id
        self.name = name
        self.value = value
        self.group = group
        self.icon = icon
    }
}

public struct Telemetry: Codable {
    public var fans: [FanReading]
    public var sensors: [TemperatureReading]
    public var fanDetectionAvailable: Bool
    public init(
        fans: [FanReading], sensors: [TemperatureReading], fanDetectionAvailable: Bool = true
    ) {
        self.fans = fans
        self.sensors = sensors
        self.fanDetectionAvailable = fanDetectionAvailable
    }
}

public struct ControlRequest: Codable {
    public var command: String
    public var fanIDs: [Int]?
    public var config: FanConfiguration?
    public init(command: String, fanIDs: [Int]? = nil, config: FanConfiguration? = nil) {
        self.command = command
        self.fanIDs = fanIDs
        self.config = config
    }
}

public struct ControlReply: Codable {
    public var ok: Bool
    public var error: String?
    public var telemetry: Telemetry?
    public init(ok: Bool, error: String? = nil, telemetry: Telemetry? = nil) {
        self.ok = ok
        self.error = error
        self.telemetry = telemetry
    }
    public func data() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

@objc public protocol FanHelperProtocol {
    func request(_ data: Data, withReply reply: @escaping (Data) -> Void)
}

public enum FanError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

public let helperServiceName = "com.changansu.BetterFan.Helper"
public let appBundleIdentifier = "com.changansu.BetterFan"
