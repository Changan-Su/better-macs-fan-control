import XCTest

@testable import FanControlCore

final class MockDriver: FanDriver {
    var fans = [
        FanReading(id: 0, name: "Left", min: 1500, max: 5500, rpm: 2000),
        FanReading(id: 1, name: "Right", min: 1200, max: 6000, rpm: 2000),
    ]
    var sensors = [TemperatureReading(id: "TC0P", name: "CPU", value: 65)]
    var writes: [(Int, Double)] = []
    var resets: [Int] = []
    var failWrite: Int?
    var failRestore = false
    var detected = true
    func readTelemetry() -> Telemetry {
        .init(fans: fans, sensors: sensors, fanDetectionAvailable: detected)
    }
    func setManual(fan: Int, rpm: Double) throws {
        writes.append((fan, rpm))
        if fan == failWrite { throw FanError.message("write failed") }
    }
    func restoreAutomatic(fan: Int) throws {
        resets.append(fan)
        if failRestore { throw FanError.message("reset failed") }
    }
}

final class ControllerTests: XCTestCase {
    func testWholeBatchIsValidatedBeforeWriting() {
        let driver = MockDriver()
        let actual = FanController(driver: driver)
        XCTAssertThrowsError(try actual.apply(ids: [0, 1], config: .init(mode: .fixed, rpm: 5700)))
        XCTAssertTrue(driver.writes.isEmpty)
        XCTAssertFalse(actual.hasOverrides)
    }
    func testIndependentMaximumAndSingleFanScope() throws {
        let driver = MockDriver()
        let c = FanController(driver: driver)
        try c.apply(ids: [1], config: .init(mode: .full))
        XCTAssertEqual(driver.writes.count, 1)
        XCTAssertEqual(driver.writes[0].0, 1)
        XCTAssertEqual(driver.writes[0].1, 6000)
        XCTAssertEqual(c.telemetry().fans[0].config.mode, .auto)
    }
    func testCurveUsesSelectedSensorAndActualRange() throws {
        let fan = MockDriver().fans[0]
        let config = FanConfiguration(mode: .sensor, sensor: "TC0P", start: 50, end: 80)
        let result = try FanController.target(
            config, fan: fan, sensors: [.init(id: "TC0P", name: "CPU", value: 65)])
        XCTAssertEqual(result, 3500)
        XCTAssertThrowsError(try FanController.target(config, fan: fan, sensors: []))
        XCTAssertThrowsError(
            try FanController.target(
                .init(mode: .sensor, sensor: "TC0P", start: 90, end: 80), fan: fan, sensors: []))
    }
    func testLeaseLossRestoresOnlyOwnedFans() throws {
        let driver = MockDriver()
        let c = FanController(driver: driver)
        try c.apply(ids: [1], config: .init(mode: .fixed, rpm: 3000))
        try c.tick(leaseExpired: true, thermalEmergency: false)
        XCTAssertEqual(driver.resets, [1])
        XCTAssertFalse(c.hasOverrides)
    }
    func testMissingSensorAndThermalPressureRestoreControl() throws {
        for thermal in [false, true] {
            let driver = MockDriver()
            let c = FanController(driver: driver)
            try c.apply(ids: [0], config: .init(mode: .sensor, sensor: "TC0P", start: 50, end: 80))
            if !thermal { driver.sensors = [] }
            try? c.tick(leaseExpired: false, thermalEmergency: thermal)
            XCTAssertEqual(driver.resets, [0])
            XCTAssertFalse(c.hasOverrides)
        }
    }
    func testPartialWriteRollsBackEveryTouchedFan() {
        let driver = MockDriver()
        let c = FanController(driver: driver)
        driver.failWrite = 1
        XCTAssertThrowsError(try c.apply(ids: [0, 1], config: .init(mode: .fixed, rpm: 3000)))
        XCTAssertEqual(driver.resets, [0, 1])
        XCTAssertFalse(c.hasOverrides)
    }
    func testFailedRollbackRetainsOwnershipForRetry() throws {
        let driver = MockDriver()
        let c = FanController(driver: driver)
        driver.failWrite = 0
        driver.failRestore = true
        XCTAssertThrowsError(try c.apply(ids: [0], config: .init(mode: .fixed, rpm: 3000)))
        XCTAssertTrue(c.hasOverrides)
        driver.failRestore = false
        try c.tick(leaseExpired: true, thermalEmergency: false)
        XCTAssertFalse(c.hasOverrides)
    }
    func testRejectsUnknownDuplicateAndNonFiniteInputs() {
        let driver = MockDriver()
        let c = FanController(driver: driver)
        for ids in [[], [0, 0], [9]] {
            XCTAssertThrowsError(try c.apply(ids: ids, config: .init(mode: .full)))
        }
        XCTAssertThrowsError(try c.apply(ids: [0], config: .init(mode: .fixed, rpm: .nan)))
        XCTAssertThrowsError(try c.apply(ids: [0], config: .init(mode: .external)))
        XCTAssertTrue(driver.writes.isEmpty)
    }
    func testDoesNotTakeOverAnExternalController() {
        let driver = MockDriver()
        driver.fans[0].config.mode = .external
        let c = FanController(driver: driver)
        XCTAssertThrowsError(try c.apply(ids: [0], config: .init(mode: .full)))
        XCTAssertTrue(driver.writes.isEmpty)
    }
    func testRestoreDoesNotChangeExternalOrUnownedFans() throws {
        let driver = MockDriver()
        driver.fans[0].config.mode = .external
        let controller = FanController(driver: driver)
        try controller.apply(ids: [0, 1], config: .init())
        XCTAssertTrue(driver.resets.isEmpty)
    }
    func testCodeRequirementsRejectUntrustedParameters() {
        XCTAssertNil(
            CodeIdentity.requirement(identifier: appBundleIdentifier, team: "bad\" or true"))
        XCTAssertNil(CodeIdentity.requirement(identifier: "evil", team: "ABCD123456"))
        XCTAssertTrue(
            CodeIdentity.requirement(identifier: appBundleIdentifier, team: "ABCD123456")!.contains(
                "anchor apple generic"))
    }
}
