import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: EventStore
    @State private var filter: HistoryFilter = .all
    @State private var confirmClear = false

    private struct DaySection: Identifiable {
        let day: Date
        let events: [MedicationEvent]
        var id: Date { day }
    }

    private var sections: [DaySection] {
        let groups = Dictionary(grouping: store.events(matching: filter)) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        return groups.keys.sorted(by: >).map { day in
            DaySection(day: day, events: (groups[day] ?? []).sorted { $0.timestamp > $1.timestamp })
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if sections.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(dayTitle(section.day)) {
                                ForEach(section.events) { event in
                                    EventRow(event: event)
                                        .listRowBackground(Theme.card)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Activity")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.events.isEmpty)
                    .accessibilityLabel("Clear history")
                }
            }
            .confirmationDialog("Clear all activity history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { store.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes \(store.events.count) saved events from this iPhone.")
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { option in
                    let selected = option == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filter = option }
                    } label: {
                        Text("\(option.rawValue)  \(store.count(option))")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? Theme.accent : Theme.card, in: Capsule())
                            .foregroundStyle(selected ? Theme.background : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(Theme.inactive)
            Text(filter == .all ? "No activity yet" : "No \(filter.rawValue.lowercased()) events")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Events received from the bottle are saved here.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
}
