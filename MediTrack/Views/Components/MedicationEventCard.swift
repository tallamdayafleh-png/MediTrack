import SwiftUI

/// The large "Latest activity" card on the dashboard.
struct MedicationEventCard: View {
    let event: MedicationEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader("Latest activity")
                Spacer()
                if event?.isTest == true { TestBadge() }
            }

            if let event {
                HStack(alignment: .top, spacing: 14) {
                    EventIcon(type: event.type, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.type.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(event.type.color)
                        Text(event.type.explanation)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        EventDetailsText(event: event)
                            .padding(.top, 2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .id(event.id)
            } else {
                HStack(spacing: 14) {
                    EventIcon(type: .unknown, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No activity yet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Events from the bottle will appear here.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .card()
        .animation(.easeInOut(duration: 0.3), value: event?.id)
    }
}
