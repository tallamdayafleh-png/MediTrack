import Combine
import Foundation

/// The result of parsing one BLE payload.
struct ParsedEvent: Equatable {
    let type: MedicationEventType
    let weightDifference: Int?
    let movementDetected: Bool?
    let raw: String
}

/// Parses the firmware's event format. Supports both:
///   Simple:   "R"            (just the event code)
///   Enhanced: "R,1517,1"     (code, raw weight difference, IMU movement 1/0)
/// Weight and movement are optional. Anything unrecognised becomes `.unknown`
/// instead of crashing. Empty payloads return nil and are ignored.
enum EventParser {
    static func parse(_ data: Data) -> ParsedEvent? {
        parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> ParsedEvent? {
        // Strip whitespace, newlines and control characters such as a trailing "\0" from Arduino strings.
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !cleaned.isEmpty else { return nil }

        let fields = cleaned
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let type = MedicationEventType(firmwareCode: fields[0])
        let weight = fields.count > 1 ? Int(fields[1]) : nil
        let movement = fields.count > 2 ? parseBool(fields[2]) : nil

        return ParsedEvent(type: type,
                           weightDifference: weight,
                           movementDetected: movement,
                           raw: String(cleaned.prefix(64)))
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes", "y": return true
        case "0", "false", "no", "n": return false
        default: return nil
        }
    }
}
