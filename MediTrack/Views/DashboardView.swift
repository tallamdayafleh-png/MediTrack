import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var reminders: ReminderStore
    @AppStorage(SettingsKeys.medicationName) private var medicationName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ConnectionStatusCard()
                    MedicationEventCard(event: store.latest)
                    stats
                    recentActivity
                    pillCount
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MediTrack")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text(medicationName.isEmpty ? "Smart medication tracker" : "Tracking \(medicationName)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Circle()
                .fill(bluetooth.state.color)
                .frame(width: 10, height: 10)
                .accessibilityLabel(bluetooth.state.label)
        }
        .padding(.top, 8)
    }

    private var stats: some View {
        HStack(spacing: 12) {
            let tests = store.removalCountToday(includeTests: true) - store.removalCountToday(includeTests: false)
            StatTile(symbol: "pills.fill",
                     color: Theme.success,
                     title: "Removals today",
                     value: "\(store.removalCountToday(includeTests: true))",
                     subtitle: tests > 0 ? "incl. \(tests) test" : "Possible removals")

            if let next = reminders.nextReminder {
                StatTile(symbol: "bell.fill",
                         color: Theme.accent,
                         title: "Next reminder",
                         value: next.date.formatted(date: .omitted, time: .shortened),
                         subtitle: next.reminder.medicationName)
            } else {
                StatTile(symbol: "bell.slash",
                         color: Theme.inactive,
                         title: "Next reminder",
                         value: "None",
                         subtitle: "Add one in Reminders")
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Recent activity")
            if store.events.isEmpty {
                Text("No events received yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(Array(store.events.prefix(5).enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider().overlay(Theme.cardBorder) }
                    EventRow(event: event)
                }
            }
        }
        .card()
    }

    /// Placeholder only. No pill count is shown until the load cell is calibrated.
    private var pillCount: some View {
        HStack(spacing: 12) {
            Image(systemName: "flask")
                .font(.title3)
                .foregroundStyle(Theme.inactive)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pill count · Experimental")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Unavailable until the weight sensor is calibrated.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }
}

private struct StatTile: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .card()
    }
}
