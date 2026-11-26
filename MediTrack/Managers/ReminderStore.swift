import Combine
import Foundation

/// Saves daily reminders locally and keeps the scheduled notifications in sync.
@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [MedicationReminder] = []

    private let storageKey = "meditrack.reminders.v1"
    private let notifications: NotificationManager

    init(notifications: NotificationManager) {
        self.notifications = notifications
        load()
    }

    func add(_ reminder: MedicationReminder) {
        reminders.append(reminder)
        sortAndSave()
        notifications.schedule(reminder)
    }

    func update(_ reminder: MedicationReminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
        sortAndSave()
        notifications.schedule(reminder)   // replaces the old one, or cancels it if disabled
    }

    func setEnabled(_ reminder: MedicationReminder, _ isEnabled: Bool) {
        var updated = reminder
        updated.isEnabled = isEnabled
        update(updated)
    }

    func delete(_ reminder: MedicationReminder) {
        reminders.removeAll { $0.id == reminder.id }
        save()
        notifications.cancel(reminder)
    }

    func delete(atOffsets offsets: IndexSet) {
        let toDelete = offsets.map { reminders[$0] }
        for reminder in toDelete { delete(reminder) }
    }

    /// Re-registers every reminder with iOS, e.g. after notification permission is granted.
    func rescheduleAll() {
        for reminder in reminders { notifications.schedule(reminder) }
    }

    /// The enabled reminder that fires soonest.
    var nextReminder: (reminder: MedicationReminder, date: Date)? {
        reminders
            .filter(\.isEnabled)
            .compactMap { r in r.nextOccurrence.map { (reminder: r, date: $0) } }
            .min { $0.date < $1.date }
    }

    // MARK: - Persistence

    private func sortAndSave() {
        reminders.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([MedicationReminder].self, from: data) else { return }
        reminders = saved
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
