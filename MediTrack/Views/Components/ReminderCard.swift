import SwiftUI

struct ReminderCard: View {
    let reminder: MedicationReminder
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(reminder.isEnabled ? Theme.accent : Theme.inactive)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reminder.timeText)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(reminder.isEnabled ? .white : Theme.inactive)
                        Text(reminder.medicationName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        if !reminder.dosage.isEmpty {
                            Text(reminder.dosage)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("Enabled", isOn: Binding(get: { reminder.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}
