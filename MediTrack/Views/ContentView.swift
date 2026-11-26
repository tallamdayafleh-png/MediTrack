import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "waveform.path.ecg") }
            HistoryView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            RemindersView()
                .tabItem { Label("Reminders", systemImage: "bell.badge") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}
