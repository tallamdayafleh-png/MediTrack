import SwiftUI

/// App entry point. Creates the shared managers once and wires the data flow:
/// MG24 → BluetoothManager → EventStore (saved) → NotificationManager (alert) → SwiftUI views.
@main
struct MediTrackApp: App {
    @StateObject private var eventStore: EventStore
    @StateObject private var notifications: NotificationManager
    @StateObject private var reminders: ReminderStore
    @StateObject private var bluetooth: BluetoothManager

    init() {
        let store = EventStore()
        let notes = NotificationManager()
        let reminderStore = ReminderStore(notifications: notes)
        let ble = BluetoothManager()

        // Every saved event (hardware or test) may trigger a notification.
        store.onNewEvent = { event in
            notes.notify(for: event)
        }
        // Every event from the hardware is saved with source = .hardware.
        ble.onEvent = { parsed in
            store.add(MedicationEvent(type: parsed.type,
                                      weightDifference: parsed.weightDifference,
                                      movementDetected: parsed.movementDetected,
                                      source: .hardware,
                                      rawPayload: parsed.raw))
        }

        _eventStore = StateObject(wrappedValue: store)
        _notifications = StateObject(wrappedValue: notes)
        _reminders = StateObject(wrappedValue: reminderStore)
        _bluetooth = StateObject(wrappedValue: ble)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventStore)
                .environmentObject(notifications)
                .environmentObject(reminders)
                .environmentObject(bluetooth)
                .preferredColorScheme(.dark)
                .task {
                    // Shows the permission prompt on first launch only.
                    await notifications.requestAuthorization()
                    reminders.rescheduleAll()
                }
        }
    }
}
