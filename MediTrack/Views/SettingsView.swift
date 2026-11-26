import UIKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var reminders: ReminderStore
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.medicationName) private var medicationName = ""
    @State private var confirmClear = false

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Medication name", text: $medicationName)
                }

                Section {
                    LabeledContent("Status", value: bluetooth.state.label)
                    LabeledContent("Device", value: bluetooth.deviceName ?? "None")
                    if bluetooth.state == .ready || bluetooth.state.isBusy {
                        Button("Disconnect", role: .destructive) { bluetooth.disconnect() }
                    } else {
                        Button("Connect") { bluetooth.connect() }
                    }
                    Toggle("Reconnect automatically", isOn: $bluetooth.autoReconnect)
                    if bluetooth.hasSavedDevice {
                        Button("Forget saved device", role: .destructive) { bluetooth.forgetDevice() }
                    }
                } header: {
                    Text("Bluetooth device")
                }

                Section {
                    LabeledContent("Permission", value: notifications.statusText)
                    if notifications.authorizationStatus == .notDetermined {
                        Button("Allow Notifications") {
                            Task {
                                await notifications.requestAuthorization()
                                reminders.rescheduleAll()
                            }
                        }
                    } else if notifications.authorizationStatus == .denied {
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    Toggle("Possible medication removal", isOn: $notifications.notifyRemoved)
                    Toggle("Medication added", isOn: $notifications.notifyAdded)
                    Toggle("Unconfirmed weight change", isOn: $notifications.notifyUnconfirmed)
                    Toggle("Bottle handled", isOn: $notifications.notifyHandled)
                    Toggle("Developer test events", isOn: $notifications.notifyTestEvents)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Bottle-handled alerts are off by default so ordinary handling doesn't send constant notifications.")
                }

                Section("Data") {
                    LabeledContent("Saved events", value: "\(store.events.count)")
                    if let error = store.loadError {
                        Text(error).font(.footnote).foregroundStyle(Theme.warning)
                    }
                    Button("Clear activity history", role: .destructive) { confirmClear = true }
                        .disabled(store.events.isEmpty)
                }

                Section {
                    NavigationLink {
                        DebugView()
                    } label: {
                        Label("Debug & test events", systemImage: "ladybug")
                    }
                } header: {
                    Text("Developer")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Text("MediTrack is a university engineering prototype built for CSE 157 / EECS 257 at UC Merced. A detected medication removal means the bottle's weight decreased after handling. It does not confirm that medication was taken. MediTrack does not provide medical advice or dosing recommendations.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .task { await notifications.refreshStatus() }
            .confirmationDialog("Clear all activity history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { store.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes \(store.events.count) saved events from this iPhone.")
            }
        }
    }
}
