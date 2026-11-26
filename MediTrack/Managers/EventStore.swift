import Combine
import Foundation

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case removed = "Removed"
    case added = "Added"
    case handled = "Handled"
    case unconfirmed = "Unconfirmed"

    var id: String { rawValue }

    func matches(_ event: MedicationEvent) -> Bool {
        switch self {
        case .all: return true
        case .removed: return event.type == .medicationRemoved
        case .added: return event.type == .medicationAdded
        case .handled: return event.type == .bottleHandled
        case .unconfirmed: return event.type == .unconfirmedWeightLoss
        }
    }
}

/// Saves medication events on the iPhone using UserDefaults + Codable (JSON).
@MainActor
final class EventStore: ObservableObject {
    /// Newest first.
    @Published private(set) var events: [MedicationEvent] = []
    /// Set if saved data could not be read (the bad data is backed up, not silently lost).
    @Published private(set) var loadError: String?

    /// Called after every new event is saved. The app uses this to send notifications.
    var onNewEvent: (@MainActor (MedicationEvent) -> Void)?

    private let storageKey = "meditrack.events.v1"
    private let maxEvents = 1000
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var latest: MedicationEvent? { events.first }

    var testEventCount: Int { events.filter(\.isTest).count }

    func add(_ event: MedicationEvent) {
        events.insert(event, at: 0)
        if events.count > maxEvents { events.removeLast(events.count - maxEvents) }
        save()
        onNewEvent?(event)
    }

    func events(matching filter: HistoryFilter) -> [MedicationEvent] {
        events.filter(filter.matches)
    }

    func count(_ filter: HistoryFilter) -> Int {
        events.filter(filter.matches).count
    }

    /// Possible-removal events received today.
    func removalCountToday(includeTests: Bool) -> Int {
        events.filter {
            $0.type == .medicationRemoved
                && Calendar.current.isDateInToday($0.timestamp)
                && (includeTests || !$0.isTest)
        }.count
    }

    func clear() {
        events = []
        save()
    }

    func clearTestEvents() {
        events.removeAll(where: \.isTest)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }  // first launch
        do {
            events = try JSONDecoder()
                .decode([MedicationEvent].self, from: data)
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            // Keep a copy of the unreadable data so it can be inspected, then start fresh.
            defaults.set(data, forKey: storageKey + ".corrupt-backup")
            loadError = "Saved history could not be read and was reset. (\(error.localizedDescription))"
            events = []
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(events), forKey: storageKey)
        } catch {
            print("EventStore save failed: \(error)")
        }
    }
}
