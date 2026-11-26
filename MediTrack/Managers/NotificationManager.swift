import Combine
import Foundation
@preconcurrency import UserNotifications

/// Handles notification permission, live event alerts and daily reminders.
/// Live BLE event alerts and scheduled reminders are kept separate:
/// event alerts fire immediately, reminders are scheduled with iOS and work even if the app is closed.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // Which event types trigger an alert. Saved between launches.
    @Published var notifyRemoved: Bool { didSet { defaults.set(notifyRemoved, forKey: Keys.removed) } }
    @Published var notifyAdded: Bool { didSet { defaults.set(notifyAdded, forKey: Keys.added) } }
    @Published var notifyUnconfirmed: Bool { didSet { defaults.set(notifyUnconfirmed, forKey: Keys.unconfirmed) } }
    @Published var notifyHandled: Bool { didSet { defaults.set(notifyHandled, forKey: Keys.handled) } }
    @Published var notifyTestEvents: Bool { didSet { defaults.set(notifyTestEvents, forKey: Keys.tests) } }

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private static let reminderPrefix = "reminder-"

    private enum Keys {
        static let removed = "meditrack.notify.removed"
        static let added = "meditrack.notify.added"
        static let unconfirmed = "meditrack.notify.unconfirmed"
        static let handled = "meditrack.notify.handled"
        static let tests = "meditrack.notify.tests"
    }

    override init() {
        let d = UserDefaults.standard
        // Ordinary bottle handling is off by default so the user isn't spammed.
        d.register(defaults: [Keys.removed: true, Keys.added: true, Keys.unconfirmed: true,
                              Keys.handled: false, Keys.tests: true])
        notifyRemoved = d.bool(forKey: Keys.removed)
        notifyAdded = d.bool(forKey: Keys.added)
        notifyUnconfirmed = d.bool(forKey: Keys.unconfirmed)
        notifyHandled = d.bool(forKey: Keys.handled)
        notifyTestEvents = d.bool(forKey: Keys.tests)
        super.init()
        center.delegate = self   // lets banners show while the app is open
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var statusText: String {
        switch authorizationStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Permission

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization error: \(error)")
        }
        await refreshStatus()
    }

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    // MARK: - Live event alerts

    func notify(for event: MedicationEvent) {
        guard shouldNotify(event) else { return }

        let content = UNMutableNotificationContent()
        let text = Self.text(for: event.type)
        content.title = event.isTest ? "[TEST] \(text.title)" : text.title
        content.body = text.body
        content.sound = .default

        // trigger: nil = deliver immediately
        let request = UNNotificationRequest(identifier: "event-\(event.id.uuidString)", content: content, trigger: nil)
        center.add(request) { error in
            if let error { print("Event notification failed: \(error)") }
        }
    }

    private func shouldNotify(_ event: MedicationEvent) -> Bool {
        if event.isTest && !notifyTestEvents { return false }
        switch event.type {
        case .medicationRemoved: return notifyRemoved
        case .medicationAdded: return notifyAdded
        case .unconfirmedWeightLoss: return notifyUnconfirmed
        case .bottleHandled: return notifyHandled
        case .unknown: return false
        }
    }

    private static func text(for type: MedicationEventType) -> (title: String, body: String) {
        switch type {
        case .medicationRemoved:
            return ("Medication Activity Detected",
                    "Your medication bottle was handled and a possible medication removal was detected.")
        case .medicationAdded:
            return ("Medication Refill Detected",
                    "An increase in medication bottle weight was detected.")
        case .unconfirmedWeightLoss:
            return ("Unconfirmed Medication Activity",
                    "A weight change was detected without sufficient movement confirmation.")
        case .bottleHandled:
            return ("Bottle Handled",
                    "Your medication bottle was picked up and returned with no significant weight change.")
        case .unknown:
            return ("Unknown Device Event", "The medication bottle sent an unrecognised event.")
        }
    }

    // MARK: - Daily reminders

    /// Schedules (or replaces) a daily reminder. Disabled reminders are cancelled.
    func schedule(_ reminder: MedicationReminder) {
        cancel(reminder)
        guard reminder.isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Medication Reminder"
        let name = reminder.medicationName.isEmpty ? "medication" : reminder.medicationName
        content.body = reminder.dosage.isEmpty
            ? "It is time for your scheduled \(name) reminder."
            : "It is time for your scheduled \(name) reminder (\(reminder.dosage))."
        content.sound = .default

        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: Self.identifier(for: reminder), content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("Reminder scheduling failed: \(error)") }
        }
    }

    func cancel(_ reminder: MedicationReminder) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: reminder)])
    }

    /// Number of reminders iOS currently has scheduled (shown on the Debug screen).
    func pendingReminderCount() async -> Int {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.reminderPrefix) }
            .count
    }

    private static func identifier(for reminder: MedicationReminder) -> String {
        reminderPrefix + reminder.id.uuidString
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Without this, iOS hides notifications while the app is in the foreground.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
