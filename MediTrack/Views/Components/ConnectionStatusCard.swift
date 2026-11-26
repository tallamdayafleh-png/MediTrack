import UIKit
import SwiftUI

struct ConnectionStatusCard: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.openURL) private var openURL

    private var state: ConnectionState { bluetooth.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(state.color.opacity(0.18))
                    Image(systemName: state.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(state.color)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(bluetooth.deviceName ?? "No device")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if state.isBusy {
                    ProgressView().tint(Theme.accent)
                }
            }

            Text(state.detail)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            actionButton
        }
        .card()
        .animation(.easeInOut(duration: 0.25), value: state)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .ready:
            Button { bluetooth.disconnect() } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
        case .scanning, .connecting, .reconnecting, .discoveringServices:
            Button("Cancel") { bluetooth.disconnect() }
                .buttonStyle(SecondaryButtonStyle())
        case .permissionDenied:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
        case .bluetoothOff, .bluetoothUnavailable:
            EmptyView()
        case .disconnected, .failed:
            Button { bluetooth.connect() } label: {
                Label("Connect to MediTrack", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}
