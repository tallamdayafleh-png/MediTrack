import UIKit
import SwiftUI

struct RemindersView: View {
    @EnvironmentObject private var reminders: ReminderStore
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(\.openURL) private var openURL
    @State private var isAdding = false
    @State private var editing: MedicationReminder?

    var body: some View {
        NavigationStack {
            List {
                if !notifications.isAuthorized {
                    Section { permissionBanner }
                        .listRowBackground(Theme.card)
                }

                Section {
                    if reminders.reminders.isEmpty {
                        Text("No reminders yet. Tap + to add a daily reminder.")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(reminders.reminders) { reminder in
                            ReminderCard(reminder: reminder,
                                         onToggle: { reminders.setEnabled(reminder, $0) },
                                         onEdit: { editing = reminder })
                        }
                        .onDelete { reminders.delete(atOffsets: $0) }
                    }
                } footer: {
                    Text("Reminders repeat daily and work without an internet connection. MediTrack does not provide dosing recommendations.")
                }
                .listRowBackground(Theme.card)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Reminders")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add reminder")
                }
            }
            .sheet(isPresented: $isAdding) {
                ReminderEditorView(reminder: nil) { save($0, isNew: true) }
            }
            .sheet(item: $editing) { reminder in
                ReminderEditorView(reminder: reminder,
                                   onSave: { save($0, isNew: false) },
                                   onDelete: { reminders.delete(reminder) })
            }
            .task { await notifications.refreshStatus() }
        }
    }

    private func save(_ reminder: MedicationReminder, isNew: Bool) {
        if isNew { reminders.add(reminder) } else { reminders.update(reminder) }
        if notifications.authorizationStatus == .notDetermined {
            Task {
                await notifications.requestAuthorization()
                reminders.rescheduleAll()
            }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications are off", systemImage: "bell.slash.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
            Text("Reminders can't alert you until notifications are allowed.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if notifications.authorizationStatus == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else {
                Button("Allow Notifications") {
                    Task {
                        await notifications.requestAuthorization()
                        reminders.rescheduleAll()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.medicationName) private var defaultMedicationName = ""

    private let original: MedicationReminder?
    private let onSave: (MedicationReminder) -> Void
    private let onDelete: (() -> Void)?

    @State private var name: String
    @State private var time: Date
    @State private var dosage: String
    @State private var isEnabled: Bool

    init(reminder: MedicationReminder?,
         onSave: @escaping (MedicationReminder) -> Void,
         onDelete: (() -> Void)? = nil) {
        original = reminder
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: reminder?.medicationName ?? "")
        _time = State(initialValue: reminder?.timeOfDay
                      ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())
                      ?? Date())
        _dosage = State(initialValue: reminder?.dosage ?? "")
        _isEnabled = State(initialValue: reminder?.isEnabled ?? true)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Medication name", text: $name)
                    TextField("Dosage note (optional)", text: $dosage)
                }
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Repeats every day at this time.")
                }
                if let onDelete {
                    Section {
                        Button("Delete Reminder", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onSave(MedicationReminder(id: original?.id ?? UUID(),
                                                  medicationName: trimmedName,
                                                  hour: parts.hour ?? 8,
                                                  minute: parts.minute ?? 0,
                                                  dosage: dosage.trimmingCharacters(in: .whitespaces),
                                                  isEnabled: isEnabled))
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                if name.isEmpty && original == nil { name = defaultMedicationName }
            }
        }
    }
}
