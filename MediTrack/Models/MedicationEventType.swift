import SwiftUI

/// The kinds of events the MG24 firmware can report.
/// `unknown` lets the app survive firmware changes or garbled BLE data without crashing.
enum MedicationEventType: String, Codable, CaseIterable, Identifiable {
    case medicationRemoved
    case medicationAdded
    case bottleHandled
    case unconfirmedWeightLoss
    case unknown

    var id: String { rawValue }

    /// Maps the firmware's one-letter code (R/A/H/U) or its full name to an event type.
    init(firmwareCode code: String) {
        switch code.uppercased() {
        case "R", "MEDICATION_REMOVED": self = .medicationRemoved
        case "A", "MEDICATION_ADDED": self = .medicationAdded
        case "H", "NO_SIGNIFICANT_CHANGE": self = .bottleHandled
        case "U", "UNCONFIRMED_WEIGHT_LOSS": self = .unconfirmedWeightLoss
        default: self = .unknown
        }
    }

    /// Decoding never fails: an unrecognised stored value becomes `.unknown`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MedicationEventType(rawValue: raw) ?? .unknown
    }

    /// The name used by the Arduino firmware.
    var firmwareName: String {
        switch self {
        case .medicationRemoved: return "MEDICATION_REMOVED"
        case .medicationAdded: return "MEDICATION_ADDED"
        case .bottleHandled: return "NO_SIGNIFICANT_CHANGE"
        case .unconfirmedWeightLoss: return "UNCONFIRMED_WEIGHT_LOSS"
        case .unknown: return "UNKNOWN"
        }
    }

    /// Wording shown to the user. Removal is always "possible", never "taken".
    var title: String {
        switch self {
        case .medicationRemoved: return "Possible medication removal"
        case .medicationAdded: return "Medication added"
        case .bottleHandled: return "Bottle handled"
        case .unconfirmedWeightLoss: return "Unconfirmed weight change"
        case .unknown: return "Unknown event"
        }
    }

    var explanation: String {
        switch self {
        case .medicationRemoved:
            return "The bottle was handled and its weight dropped significantly. This does not confirm the medication was taken."
        case .medicationAdded:
            return "The bottle weight increased after handling. The bottle may have been refilled."
        case .bottleHandled:
            return "The bottle was picked up and returned without a significant weight change."
        case .unconfirmedWeightLoss:
            return "The weight dropped, but the accelerometer did not confirm the bottle was moved."
        case .unknown:
            return "The device sent data this version of the app does not recognise."
        }
    }

    var symbol: String {
        switch self {
        case .medicationRemoved: return "pills.fill"
        case .medicationAdded: return "plus.circle.fill"
        case .bottleHandled: return "hand.raised.fill"
        case .unconfirmedWeightLoss: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .medicationRemoved: return Theme.success
        case .medicationAdded: return Theme.accent
        case .bottleHandled: return Theme.neutral
        case .unconfirmedWeightLoss: return Theme.warning
        case .unknown: return Theme.inactive
        }
    }
}
