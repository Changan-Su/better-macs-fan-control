import FanControlCore
import Foundation

// Deliberately read-only. This executable exposes no SMC write command.
let snapshot = SMCHardware().readTelemetry()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let data = try? encoder.encode(snapshot) {
    FileHandle.standardOutput.write(data)
    print("")
}
