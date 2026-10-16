// CoreBluetooth の模型（2026-10-16・すれちがい `PassRadio` に要るぶんだけ）。
//
// **足してあるのは、アプリが使う口だけ。** どれも本物の CoreBluetooth に実在する名前・形で、
// 模型は素通し（電波は出ず、何も見つからない）。実在しない口をここに置くと、手元では通って
// 実機で落ちる。本物の委譲の口は `@objc optional` なので、模型は空の既定実装で任意扱いにする
// （`Shims/CoreLocation` と同じ作り）。
import Foundation

public let CBAdvertisementDataServiceUUIDsKey = "kCBAdvDataServiceUUIDs"
public let CBAdvertisementDataLocalNameKey = "kCBAdvDataLocalName"
public let CBCentralManagerScanOptionAllowDuplicatesKey = "kCBScanOptionAllowDuplicates"
public let CBCentralManagerOptionRestoreIdentifierKey = "kCBRestoreIdentifierKey"
public let CBCentralManagerOptionShowPowerAlertKey = "kCBInitOptionShowPowerAlert"
public let CBPeripheralManagerOptionRestoreIdentifierKey = "kCBRestoreIdentifierKey"
public let CBCentralManagerRestoredStatePeripheralsKey = "kCBRestoredPeripherals"

public final class CBUUID: NSObject {
    public let uuidString: String
    public init(string theString: String) { uuidString = theString.uppercased() }
    public override func isEqual(_ object: Any?) -> Bool {
        (object as? CBUUID)?.uuidString == uuidString
    }
    public override var hash: Int { uuidString.hashValue }
}

public enum CBManagerState: Int {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

public enum CBManagerAuthorization: Int {
    case notDetermined, restricted, denied, allowedAlways
}

open class CBManager: NSObject {
    open var state: CBManagerState { .unknown }
    /// iOS 13.1 からのクラス属性
    open class var authorization: CBManagerAuthorization { .notDetermined }
}

open class CBAttribute: NSObject {
    open var uuid: CBUUID { CBUUID(string: "0000") }
}

public struct CBCharacteristicProperties: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let read = CBCharacteristicProperties(rawValue: 0x02)
}

public struct CBAttributePermissions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let readable = CBAttributePermissions(rawValue: 0x01)
}

open class CBCharacteristic: CBAttribute {
    open var value: Data? { nil }
}

public final class CBMutableCharacteristic: CBCharacteristic {
    private let type: CBUUID
    private let stored: Data?
    public init(type UUID: CBUUID, properties: CBCharacteristicProperties, value: Data?,
                permissions: CBAttributePermissions) {
        type = UUID
        stored = value
    }
    public override var uuid: CBUUID { type }
    public override var value: Data? { stored }
}

open class CBService: CBAttribute {
    open var characteristics: [CBCharacteristic]? { nil }
}

public final class CBMutableService: CBService {
    private let type: CBUUID
    private var stored: [CBCharacteristic]?
    public init(type UUID: CBUUID, primary isPrimary: Bool) { type = UUID }
    public override var uuid: CBUUID { type }
    public override var characteristics: [CBCharacteristic]? {
        get { stored }
        set { stored = newValue }
    }
}

public protocol CBPeripheralDelegate: NSObjectProtocol {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
}
public extension CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {}
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {}
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {}
}

open class CBPeer: NSObject {
    open var identifier: UUID { UUID() }
}

open class CBPeripheral: CBPeer {
    public weak var delegate: CBPeripheralDelegate?
    open var services: [CBService]? { nil }
    open func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    open func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {}
    open func readValue(for characteristic: CBCharacteristic) {}
}

public protocol CBCentralManagerDelegate: NSObjectProtocol {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any])
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}
public extension CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {}
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {}
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {}
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {}
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {}
}

open class CBCentralManager: CBManager {
    public weak var delegate: CBCentralManagerDelegate?
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?, options: [String: Any]? = nil) {
        self.delegate = delegate
    }
    open var isScanning: Bool { false }
    open func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}
    open func stopScan() {}
    open func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {}
    open func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
}

public protocol CBPeripheralManagerDelegate: NSObjectProtocol {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager)
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any])
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?)
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?)
}
public extension CBPeripheralManagerDelegate {
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {}
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {}
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {}
}

open class CBPeripheralManager: CBManager {
    public weak var delegate: CBPeripheralManagerDelegate?
    public init(delegate: CBPeripheralManagerDelegate?, queue: DispatchQueue?, options: [String: Any]? = nil) {
        self.delegate = delegate
    }
    open var isAdvertising: Bool { false }
    open func add(_ service: CBMutableService) {}
    open func removeAllServices() {}
    open func startAdvertising(_ advertisementData: [String: Any]?) {}
    open func stopAdvertising() {}
}
