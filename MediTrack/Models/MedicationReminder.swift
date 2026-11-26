import Foundation

/// A daily repeating reminder. Hour and minute are stored instead of a Date
/// so the reminder means "every day at 8:00" regardless of time zone changes.
struct MedicationReminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var medicationName: String
    var hour: Int
    var minute: Int
    var dosage: String
    var isEnabled: Bool

    /// A Date today at this reminder's time, used by the DatePicker.
    var timeOfDay: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    var timeText: String {
        timeOfDay.formatted(date: .omitted, time: .shortened)
    }

    /// The next time this reminder will fire.
    var nextOccurrence: Date? {
        Calendar.current.nextDate(after: Date(),
                                  matching: DateComponents(hour: hour, minute: minute),
                                  matchingPolicy: .nextTime)
    }
}
