import Foundation
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    
    @Published var isConnected = false
    @Published var isPoweredOn = false
    @Published var connectionStatus = "Disconnected"
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var isScanning = false
    
    var connectedPeripheral: CBPeripheral?
    
    // UUIDs for ELK-BLEDDM / Lotus Lantern
    private let serviceUUID = CBUUID(string: "FFF0")
    private let writeUUID = CBUUID(string: "FFF3")
    
    // Reconnection Logic
    private var reconnectAttempt = 0
    private var reconnectTimer: Timer?
    private let maxReconnectAttempts = 5
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.stopScanning()
        }
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }
    
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        connectionStatus = "Connecting..."
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        reconnectTimer?.invalidate()
        reconnectAttempt = 0
    }
    
    func togglePower() {
        let newState = !isPoweredOn
        send(LEDProtocol.power(newState))
        isPoweredOn = newState
        Haptics.play(.medium)
    }
    
    func setPower(on: Bool) {
        send(LEDProtocol.power(on))
        isPoweredOn = on
    }
    
    func setColor(r: Int, g: Int, b: Int) {
        send(LEDProtocol.color(r: r, g: g, b: b))
    }
    
    func setBrightness(_ value: Int) {
        send(LEDProtocol.brightness(value))
    }
    
    func setEffectSpeed(_ value: Int) {
        send(LEDProtocol.speed(value))
    }
    
    func setMode(_ value: UInt8) {
        if let mode = LEDProtocol.EffectMode(rawValue: value) {
            send(LEDProtocol.effect(mode))
        }
    }
    
    private func send(_ bytes: [UInt8]) {
        guard let peripheral = connectedPeripheral, let characteristic = writeCharacteristic else { return }
        let data = Data(bytes)
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
    
    private func handleDisconnection() {
        isConnected = false
        writeCharacteristic = nil
        
        if reconnectAttempt < maxReconnectAttempts {
            reconnectAttempt += 1
            let delay = pow(2.0, Double(reconnectAttempt)) // Exponential backoff
            connectionStatus = "Reconnecting in \(Int(delay))s (Attempt \(reconnectAttempt))"
            
            reconnectTimer?.invalidate()
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self, let p = self.connectedPeripheral else { return }
                self.centralManager.connect(p, options: nil)
            }
        } else {
            connectionStatus = "Connection Lost"
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        default:
            connectionStatus = "Bluetooth Unavailable"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "Connected"
        reconnectAttempt = 0
        reconnectTimer?.invalidate()
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        handleDisconnection()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleDisconnection()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([writeUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == writeUUID {
            writeCharacteristic = characteristic
            // Initial sync if possible (usually not supported by these LEDs, but we set our default)
            setPower(on: true)
        }
    }
}
