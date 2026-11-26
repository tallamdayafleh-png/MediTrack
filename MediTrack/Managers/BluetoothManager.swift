import Combine
import Foundation
@preconcurrency import CoreBluetooth

/// The BLE contract agreed with the firmware team.
/// Do NOT change these without telling the firmware team.
enum BLEConstants {
    static let deviceName = "MediTrack"
    static let serviceUUIDString = "7A1E0001-6B8A-4D21-9C4F-2E31A7B10001"
    static let eventCharacteristicUUIDString = "7A1E0002-6B8A-4D21-9C4F-2E31A7B10001"

    static var serviceUUID: CBUUID { CBUUID(string: serviceUUIDString) }
    static var eventCharacteristicUUID: CBUUID { CBUUID(string: eventCharacteristicUUIDString) }

    static let restoreIdentifier = "edu.ucmerced.meditrack.central"
    static let scanTimeout: UInt64 = 15      // seconds
    static let connectTimeout: UInt64 = 10   // seconds, for connecting to a remembered device
}

enum ConnectionState: Equatable {
    case bluetoothUnavailable   // no BLE hardware (e.g. the simulator)
    case bluetoothOff
    case permissionDenied
    case disconnected
    case scanning
    case connecting
    case reconnecting
    case discoveringServices
    case ready                  // connected AND subscribed to notifications
    case failed(String)

    var label: String {
        switch self {
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        case .bluetoothOff: return "Bluetooth is off"
        case .permissionDenied: return "Permission denied"
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .discoveringServices: return "Discovering services…"
        case .ready: return "Connected"
        case .failed: return "Connection failed"
        }
    }

    var detail: String {
        switch self {
        case .bluetoothUnavailable: return "This device has no Bluetooth LE. The iOS Simulator can't use Bluetooth, so use a physical iPhone."
        case .bluetoothOff: return "Turn on Bluetooth in Control Center or Settings."
        case .permissionDenied: return "Allow Bluetooth access for MediTrack in Settings."
        case .disconnected: return "Not receiving events. Power on the bottle and tap Connect."
        case .scanning: return "Looking for a device advertising the MediTrack service."
        case .connecting: return "Connecting to the medication bottle."
        case .reconnecting: return "Connection lost. MediTrack will reconnect when the bottle is back in range."
        case .discoveringServices: return "Subscribing to medication events."
        case .ready: return "Receiving live events from the bottle."
        case .failed(let message): return message
        }
    }

    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .scanning, .connecting, .reconnecting, .discoveringServices: return "antenna.radiowaves.left.and.right"
        case .bluetoothOff, .bluetoothUnavailable: return "antenna.radiowaves.left.and.right.slash"
        case .permissionDenied: return "lock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .disconnected: return "bolt.horizontal.circle"
        }
    }

    /// True while something is in progress (show a spinner / Cancel button).
    var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .reconnecting, .discoveringServices: return true
        default: return false
        }
    }
}

/// iPhone = BLE central, MG24 = BLE peripheral.
/// Flow: scan → discover → connect → discover service → discover characteristic
///       → subscribe to notifications → receive data → parse → `onEvent`.
@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var deviceName: String?
    @Published private(set) var lastPayload: String?
    @Published private(set) var lastPayloadDate: Date?
    @Published private(set) var log: [String] = []
    @Published var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: Keys.autoReconnect) }
    }

    /// Called for every event received from real hardware.
    var onEvent: (@MainActor (ParsedEvent) -> Void)?

    private var central: CBCentralManager!
    /// Strong reference: CoreBluetooth drops the connection if nobody holds the peripheral.
    private var peripheral: CBPeripheral?
    private var eventCharacteristic: CBCharacteristic?
    private var userRequestedDisconnect = false
    private var timeoutTask: Task<Void, Never>?

    private enum Keys {
        static let savedPeripheral = "meditrack.ble.savedPeripheralID"
        static let autoReconnect = "meditrack.ble.autoReconnect"
    }

    override init() {
        UserDefaults.standard.register(defaults: [Keys.autoReconnect: true])
        autoReconnect = UserDefaults.standard.bool(forKey: Keys.autoReconnect)
        super.init()
        // queue: .main → every delegate callback arrives on the main thread, safe for SwiftUI.
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.restoreIdentifier
        ])
    }

    // MARK: - Remembered device

    private var savedPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: Keys.savedPeripheral).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Keys.savedPeripheral) }
    }

    var hasSavedDevice: Bool { savedPeripheralID != nil }

    // MARK: - Public controls

    func connect() {
        userRequestedDisconnect = false
        guard central.state == .poweredOn else {
            handleStateChange(central.state)
            return
        }
        if let p = peripheral, p.state == .connected || p.state == .connecting { return }

        // 1. Already connected at the system level (e.g. after state restoration)?
        if let p = central.retrieveConnectedPeripherals(withServices: [BLEConstants.serviceUUID]).first {
            addLog("Found already-connected device")
            attach(p, timeout: true)
            return
        }
        // 2. A device we connected to before?
        if let id = savedPeripheralID, let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            addLog("Connecting to remembered device")
            attach(p, timeout: true)
            return
        }
        // 3. Otherwise scan.
        startScan()
    }

    func disconnect() {
        userRequestedDisconnect = true
        cancelTimeout()
        if central.isScanning { central.stopScan() }
        if let p = peripheral {
            if let c = eventCharacteristic, p.state == .connected { p.setNotifyValue(false, for: c) }
            central.cancelPeripheralConnection(p)
            addLog("Disconnected by user")
        }
        peripheral = nil
        eventCharacteristic = nil
        if central.state == .poweredOn { state = .disconnected }
    }

    /// Forget the remembered MG24 (use if the board is replaced).
    func forgetDevice() {
        disconnect()
        savedPeripheralID = nil
        deviceName = nil
        addLog("Forgot saved device")
    }

    // MARK: - Internals

    private func startScan() {
        if central.isScanning { central.stopScan() }
        state = .scanning
        addLog("Scanning for \(BLEConstants.deviceName)")
        // withServices: nil so we can also match by name, in case the firmware doesn't put the
        // service UUID in its advertising packet. We filter results in didDiscover, so we never
        // connect to unrelated devices. (Background scanning would require a service UUID here.)
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        startTimeout(seconds: BLEConstants.scanTimeout) { [weak self] in
            guard let self, self.state == .scanning else { return }
            self.central.stopScan()
            self.fail("No MediTrack device found. Check that the MG24 is powered on and advertising.")
        }
    }

    private func attach(_ p: CBPeripheral, timeout: Bool) {
        peripheral = p
        p.delegate = self
        deviceName = p.name ?? BLEConstants.deviceName
        state = .connecting
        central.connect(p, options: nil)
        if timeout {
            startTimeout(seconds: BLEConstants.connectTimeout) { [weak self] in
                guard let self, self.state == .connecting, let p = self.peripheral else { return }
                // Remembered device didn't answer (maybe its address changed). Fall back to scanning.
                self.addLog("Connect timed out, scanning instead")
                self.central.cancelPeripheralConnection(p)
                self.peripheral = nil
                self.startScan()
            }
        }
    }

    private func fail(_ message: String) {
        cancelTimeout()
        state = .failed(message)
        addLog("Error: \(message)")
    }

    private func startTimeout(seconds: UInt64, action: @escaping @MainActor () -> Void) {
        cancelTimeout()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func addLog(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        log.insert("\(time)  \(message)", at: 0)
        if log.count > 100 { log.removeLast() }
        print("[BLE] \(message)")
    }

    private func handleStateChange(_ newState: CBManagerState) {
        switch newState {
        case .poweredOn:
            addLog("Bluetooth powered on")
            if let p = peripheral {
                // Restored by iOS, or Bluetooth was toggled off and on.
                if p.state == .connected {
                    state = .discoveringServices
                    p.discoverServices([BLEConstants.serviceUUID])
                } else if !userRequestedDisconnect {
                    state = .reconnecting
                    central.connect(p, options: nil)
                }
            } else if autoReconnect && hasSavedDevice && !userRequestedDisconnect {
                connect()
            } else {
                state = .disconnected
            }
        case .poweredOff:
            cancelTimeout()
            eventCharacteristic = nil
            state = .bluetoothOff
            addLog("Bluetooth powered off")
        case .unauthorized:
            state = .permissionDenied
            addLog("Bluetooth permission denied")
        case .unsupported:
            state = .bluetoothUnavailable
        case .resetting:
            state = .disconnected
        case .unknown:
            break
        @unknown default:
            state = .bluetoothUnavailable
        }
    }

    private func handleIncoming(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        lastPayload = text
        lastPayloadDate = Date()
        addLog("Received \"\(text)\"")
        guard let parsed = EventParser.parse(data) else {
            addLog("Ignored empty payload")
            return
        }
        if parsed.type == .unknown { addLog("Unknown event code, saved as Unknown") }
        onEvent?(parsed)
    }
}

// MARK: - CBCentralManagerDelegate
// Delegate methods are `nonisolated` because the protocol isn't tied to the main actor.
// We created the manager with queue: .main, so `MainActor.assumeIsolated` is safe here.

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { handleStateChange(central.state) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else { return }
            peripheral = restored
            restored.delegate = self
            deviceName = restored.name ?? BLEConstants.deviceName
            addLog("Restored connection state from iOS")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard state == .scanning else { return }
            let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
            guard services.contains(BLEConstants.serviceUUID) || name == BLEConstants.deviceName else { return }

            addLog("Discovered \(name ?? "device") (RSSI \(RSSI))")
            central.stopScan()
            cancelTimeout()
            attach(peripheral, timeout: false)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            cancelTimeout()
            savedPeripheralID = peripheral.identifier
            deviceName = peripheral.name ?? BLEConstants.deviceName
            state = .discoveringServices
            addLog("Connected, discovering services")
            peripheral.discoverServices([BLEConstants.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            fail(error?.localizedDescription ?? "Could not connect to the device.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            // Ignore callbacks for a peripheral we already let go of.
            guard self.peripheral?.identifier == peripheral.identifier else { return }
            eventCharacteristic = nil

            if userRequestedDisconnect {
                self.peripheral = nil
                // Keep a failure message on screen (e.g. "service not found") instead of hiding it.
                if case .failed = state {} else { state = .disconnected }
                return
            }
            addLog("Unexpected disconnect\(error.map { ": \($0.localizedDescription)" } ?? "")")
            if autoReconnect {
                // A pending connect never times out: iOS reconnects as soon as the bottle is in range,
                // even while the app is in the background.
                state = .reconnecting
                central.connect(peripheral, options: nil)
            } else {
                self.peripheral = nil
                state = .disconnected
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error { fail("Service discovery failed: \(error.localizedDescription)"); return }
            guard let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else {
                fail("Connected, but the MediTrack service was not found. Check the service UUID in the firmware.")
                userRequestedDisconnect = true
                central.cancelPeripheralConnection(peripheral)
                return
            }
            peripheral.discoverCharacteristics([BLEConstants.eventCharacteristicUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            if let error { fail("Characteristic discovery failed: \(error.localizedDescription)"); return }
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == BLEConstants.eventCharacteristicUUID }) else {
                fail("The event characteristic was not found. Check the characteristic UUID in the firmware.")
                return
            }
            guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
                fail("The event characteristic does not support notifications. Enable BLENotify in the firmware.")
                return
            }
            eventCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            if let error { fail("Could not subscribe to events: \(error.localizedDescription)"); return }
            if characteristic.isNotifying {
                state = .ready   // only now do we consider the device connected
                addLog("Subscribed to event notifications")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            if let error { addLog("Read error: \(error.localizedDescription)"); return }
            guard characteristic.uuid == BLEConstants.eventCharacteristicUUID,
                  let data = characteristic.value else { return }
            handleIncoming(data)
        }
    }
}
