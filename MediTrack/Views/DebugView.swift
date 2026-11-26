import SwiftUI

/// Developer-only tools. Everything generated here is saved with source = .developerTest
/// and shown with a TEST badge, so it can't be confused with real hardware data.
struct DebugView: View {
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var notifications: NotificationManager
    @State private var payload = "R,1517,1"
    @State private var parseResult: String?
    @State private var pendingReminders: Int?

    private let testTypes: [(type: MedicationEventType, label: String)] = [
        (.medicationRemoved, "Test medication removal"),
        (.medicationAdded, "Test medication refill"),
        (.bottleHandled, "Test bottle handling"),
        (.unconfirmedWeightLoss, "Test unconfirmed weight loss")
    ]

    var body: some View {
        Form {
            Section {
                ForEach(testTypes, id: \.type) { item in
                    Button {
                        store.add(MedicationEvent(type: item.type, source: .developerTest, rawPayload: "TEST"))
                    } label: {
                        Label(item.label, systemImage: item.type.symbol)
                            .foregroundStyle(item.type.color)
                    }
                }
            } header: {
                Text("Generate test events")
            } footer: {
                Text("Test events are labeled TEST and saved separately from hardware events. Never use them as experimental results.")
            }

            Section {
                TextField("Payload", text: $payload)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Parse only") { parseResult = describe(EventParser.parse(payload)) }
                Button("Parse and add as test event") {
                    let parsed = EventParser.parse(payload)
                    parseResult = describe(parsed)
                    if let parsed {
                        store.add(MedicationEvent(type: parsed.type,
                                                  weightDifference: parsed.weightDifference,
                                                  movementDetected: parsed.movementDetected,
                                                  source: .developerTest,
                                                  rawPayload: parsed.raw))
                    }
                }
                if let parseResult {
                    Text(parseResult)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Parser tester")
            } footer: {
                Text("Try R, A, H, U, \"R,1517,1\", \"A,-2545,1\", or garbage to check malformed data doesn't crash the app.")
            }

            Section("BLE contract") {
                LabeledContent("Device name", value: BLEConstants.deviceName)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Service UUID").font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(BLEConstants.serviceUUIDString).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Event characteristic UUID").font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(BLEConstants.eventCharacteristicUUIDString).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }

            Section("Live status") {
                LabeledContent("Connection", value: bluetooth.state.label)
                LabeledContent("Last payload", value: bluetooth.lastPayload ?? "None yet")
                if let date = bluetooth.lastPayloadDate {
                    LabeledContent("Received", value: date.formatted(date: .omitted, time: .standard))
                }
                LabeledContent("Hardware events", value: "\(store.events.count - store.testEventCount)")
                LabeledContent("Test events", value: "\(store.testEventCount)")
                LabeledContent("Notifications", value: notifications.statusText)
                LabeledContent("Scheduled reminders", value: pendingReminders.map(String.init) ?? "…")
            }

            Section("Bluetooth log") {
                if bluetooth.log.isEmpty {
                    Text("No Bluetooth activity yet.").foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(Array(bluetooth.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption2, design: .monospaced))
                    }
                }
            }

            Section {
                Button("Delete test events only", role: .destructive) { store.clearTestEvents() }
                    .disabled(store.testEventCount == 0)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .task { pendingReminders = await notifications.pendingReminderCount() }
    }

    private func describe(_ parsed: ParsedEvent?) -> String {
        guard let parsed else { return "Empty payload, ignored" }
        let weight = parsed.weightDifference.map(String.init) ?? "nil"
        let movement = parsed.movementDetected.map { $0 ? "true" : "false" } ?? "nil"
        return "type: \(parsed.type.firmwareName)\nweight: \(weight)\nmovement: \(movement)"
    }
}
