import SwiftUI

/// Central place for MediTrack's colors and shared styles.
enum Theme {
    static let background = Color(red: 0.04, green: 0.07, blue: 0.13)   // dark navy
    static let card = Color(red: 0.09, green: 0.13, blue: 0.21)
    static let cardBorder = Color.white.opacity(0.06)
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.95)       // cyan
    static let success = Color(red: 0.25, green: 0.82, blue: 0.50)      // green
    static let warning = Color(red: 1.00, green: 0.62, blue: 0.20)      // orange
    static let neutral = Color(red: 0.62, green: 0.70, blue: 0.82)      // bottle handled
    static let inactive = Color(white: 0.55)                             // gray
    static let secondaryText = Color.white.opacity(0.62)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
    }
}

/// Marks developer-generated events so they're never mistaken for sensor data.
struct TestBadge: View {
    var body: some View {
        Text("TEST")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.warning.opacity(0.2), in: Capsule())
            .foregroundStyle(Theme.warning)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(Theme.background)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
    }
}

extension ConnectionState {
    var color: Color {
        switch self {
        case .ready: return Theme.success
        case .scanning, .connecting, .reconnecting, .discoveringServices: return Theme.accent
        case .bluetoothOff, .permissionDenied, .failed: return Theme.warning
        case .disconnected, .bluetoothUnavailable: return Theme.inactive
        }
    }
}

/// Keys shared by @AppStorage across screens.
enum SettingsKeys {
    static let medicationName = "meditrack.medicationName"
}
