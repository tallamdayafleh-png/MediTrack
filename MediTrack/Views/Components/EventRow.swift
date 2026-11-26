import SwiftUI

/// Colored circle with the event's SF Symbol.
struct EventIcon: View {
    let type: MedicationEventType
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(type.color.opacity(0.18))
            Image(systemName: type.symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(type.color)
        }
        .frame(width: size, height: size)
    }
}

/// Shows weight difference and movement only when the firmware sent them.
struct EventDetailsText: View {
    let event: MedicationEvent

    var body: some View {
        if let text = Self.text(for: event) {
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
    }

    static func text(for event: MedicationEvent) -> String? {
        var parts: [String] = []
        if let diff = event.weightDifference { parts.append("Δ \(diff) raw counts") }
        if let moved = event.movementDetected { parts.append(moved ? "Movement detected" : "No movement") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct EventRow: View {
    let event: MedicationEvent

    var body: some View {
        HStack(spacing: 12) {
            EventIcon(type: event.type)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.type.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                EventDetailsText(event: event)
            }
            Spacer(minLength: 8)
            if event.isTest { TestBadge() }
        }
        .padding(.vertical, 4)
    }
}
