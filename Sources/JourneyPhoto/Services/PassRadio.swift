import Foundation
import CoreBluetooth
import CoreLocation

/// すれちがいの電波（Bluetooth Low Energy・2026-10-16）。
///
/// **2026-10-16 判断: サーバーを使わず、近くの人を Bluetooth で見つける。**
///
/// 1. 自分の端末は、アプリ固有のサービス（`serviceUUID`）で広告する（周辺機器の役）。特性は1つ
///    （`characteristicUUID`・読むだけ）で、中身は `PassExchange.Payload`（版・名刺の写真の id・
///    出身を出すか・ひとこと）。**値は特性に焼いて渡す**（読みの依頼に応える処理を持たない＝誰が
///    読んだかをこちらは知らない・覚えない）
/// 2. 同時に、同じサービスを探す（中心の役）。見つけたら繋いで特性を1つ読み、**読んだらすぐ切る**
/// 3. 読んだ中身は `PassStore` が綴じる。**同じ相手（同じ写真）は1日1回まで**（`PassStore.accepts`）。
///    同じ端末に何度も繋がないよう、繋いだ端末は `retryInterval` の間は見送る
///
/// 背景でも動くように `bluetooth-central`・`bluetooth-peripheral` の背景の仕事を宣言してあり
/// （`project.yml`）、OS に起こされたときのために復元の識別子を付ける。
///
/// ⚠️ **確かめていないこと**: 実機での見つかりやすさ。iOS は背景の広告をサービスの「あふれ領域」に
/// 移し、背景どうし（両方ともアプリを閉じている）では見つけ合えないことが多い（Apple の文書）。
/// 片方が画面を開いているときに見つかる、を最初の目安にしている
final class PassRadio: NSObject {

    static let shared = PassRadio()

    /// アプリ固有のサービス（**変えると前の版と見つけ合えなくなる**）
    static let serviceUUID = CBUUID(string: "6A3E2C1B-7F44-4D0B-9C3E-1B5A0D2F8E61")
    static let characteristicUUID = CBUUID(string: "6A3E2C1C-7F44-4D0B-9C3E-1B5A0D2F8E61")
    static let centralRestoreId = "photo.journey.pass.central"
    static let peripheralRestoreId = "photo.journey.pass.peripheral"

    /// 同じ端末に繋ぎ直すまでの間
    static let retryInterval: TimeInterval = 10 * 60
    /// 繋いでから読み終えるまで待つ長さ（過ぎたら切る）
    static let connectTimeout: TimeInterval = 10
    /// 同時に繋ぐ数
    static let maxConnections = 3

    /// 受け取った中身（主スレッドで呼ぶ）
    var onReceive: ((PassExchange.Payload) -> Void)?

    private var central: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    /// 載せている中身（nil なら止めている）
    private var payload: Data?
    /// サービスを足し終えた中身（同じなら足し直さない）
    private var publishedPayload: Data?
    private var connecting: [UUID: CBPeripheral] = [:]
    private var lastTried: [UUID: Date] = [:]

    /// 動いているか（設定の画面の表示用）
    private(set) var isRunning = false

    /// 載せる中身を決める。**nil なら止めて、電波の管理者も手放す**
    /// （手放さないと OS の Bluetooth の印が残る）。
    ///
    /// 🔴 **初めて中身を渡したときに、OS の Bluetooth の許可のダイアログが出る**（管理者を作った時）。
    /// オンにする説明（`PassIntroSheet`）を見せてからだけ呼ぶ
    func apply(payload next: Data?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let next else { stop(); return }
        payload = next
        isRunning = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil,
                                       options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreId,
                                                 CBCentralManagerOptionShowPowerAlertKey: false])
        } else if let central {
            startScanning(central)
        }
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil,
                                                    options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreId])
        } else if let peripheralManager {
            publish(peripheralManager)
        }
    }

    /// Bluetooth の許可をいま尋ねる（オンにする説明の「オンにする」を押したとき）。まだ尋ねていないときだけ
    /// 管理者を作り、交換してよい時でなければ、答えが来たところで手放す（`centralManagerDidUpdateState`）。
    ///
    /// 2026-10-16 判断: 「旅のあいだ」では、家から離れた日まで電波を出さない。そのときに初めて尋ねると、
    /// 旅先で何の前触れもなくダイアログが出るので、説明を読んだその場で尋ねる
    func requestAuthorization() {
        guard CBManager.authorization == .notDetermined, central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func stop() {
        payload = nil
        publishedPayload = nil
        isRunning = false
        if let central {
            if central.state == .poweredOn { central.stopScan() }
            for peripheral in connecting.values { central.cancelPeripheralConnection(peripheral) }
        }
        connecting = [:]
        if let peripheralManager, peripheralManager.state == .poweredOn {
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
        }
        central?.delegate = nil
        peripheralManager?.delegate = nil
        central = nil
        peripheralManager = nil
    }

    // MARK: - 中心の役（探す・読む）

    private func startScanning(_ central: CBCentralManager) {
        guard payload != nil, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(withServices: [Self.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// 繋ぐか: 動いている・同時の数に空きがある・最近繋いだ端末ではない
    static func shouldConnect(lastTried: Date?, connecting: Int, now: Date) -> Bool {
        guard connecting < maxConnections else { return false }
        guard let lastTried else { return true }
        return now.timeIntervalSince(lastTried) >= retryInterval
    }

    private func finish(_ peripheral: CBPeripheral) {
        connecting[peripheral.identifier] = nil
        central?.cancelPeripheralConnection(peripheral)
    }

    // MARK: - 周辺機器の役（広告する）

    private func publish(_ manager: CBPeripheralManager) {
        guard let payload, manager.state == .poweredOn else { return }
        if publishedPayload != payload {
            manager.stopAdvertising()
            manager.removeAllServices()
            let characteristic = CBMutableCharacteristic(type: Self.characteristicUUID, properties: [.read],
                                                         value: payload, permissions: [.readable])
            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            service.characteristics = [characteristic]
            manager.add(service)
            publishedPayload = payload
        }
        if !manager.isAdvertising {
            // 名前は載せない（端末の名前・持ち主が分かる文字を出さない）
            manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
        }
    }
}

extension PassRadio: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // 許可を尋ねるためだけに作った管理者（`requestAuthorization`）は、答えが来たら手放す
        guard payload != nil else {
            if central.state != .unknown { stop() }
            return
        }
        if central.state == .poweredOn {
            startScanning(central)
        } else {
            connecting = [:]
        }
    }

    /// OS に起こされた。前の起動で繋ぎかけていた端末は切る（読み直しは次に見つけたとき）
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in peripherals { central.cancelPeripheralConnection(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let now = Date()
        let id = peripheral.identifier
        guard payload != nil, connecting[id] == nil,
              Self.shouldConnect(lastTried: lastTried[id], connecting: connecting.count, now: now) else { return }
        lastTried[id] = now
        // 古い記録を掃除する（見送りの間を過ぎたものは要らない）
        lastTried = lastTried.filter { now.timeIntervalSince($0.value) < Self.retryInterval }
        connecting[id] = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout) { [weak self] in
            guard let self, self.connecting[id] != nil else { return }
            self.finish(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connecting[peripheral.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connecting[peripheral.identifier] = nil
    }
}

extension PassRadio: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            finish(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            finish(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { finish(peripheral) }
        guard error == nil, let data = characteristic.value, let payload = PassExchange.decode(data) else { return }
        onReceive?(payload)
    }
}

extension PassRadio: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            publish(peripheral)
        } else {
            // 電源が落ちるとサービスは消える。入ったら足し直す
            publishedPayload = nil
        }
    }

    /// OS に起こされた。焼いた値は前の起動のもの——中身が同じかは分からないので足し直す
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        publishedPayload = nil
    }
}

/// 位置から「〇〇のあたり」を引く（すれちがいの粗い場所・2026-10-16）。
///
/// - **許可を新しく求めない。** 撮影地マップで「使用中のみ許可」をもらっているときだけ使う
/// - 背景では新しい位置を取りに行かない（「使用中のみ」では取れない）。**前面で取れた最後の位置が
///   `PassExchange.placeFreshness` より新しいときだけ**使い、古ければ場所なしで綴じる
/// - 持つのは市区町村の名前と 0.1 度に丸めた座標だけ（`PassStore.record`）
@MainActor
final class PassPlaceFinder: NSObject, CLLocationManagerDelegate {

    static let shared = PassPlaceFinder()

    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        m.delegate = self
        return m
    }()

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// 新しい位置（取れていなければ nil）
    func recentFix(now: Date = Date()) -> Photo.Coords? {
        guard isAuthorized, let location = manager.location,
              now.timeIntervalSince(location.timestamp) <= PassExchange.placeFreshness else { return nil }
        return Photo.Coords(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
    }

    /// 前面に来たときに1回だけ取り直す（許可があるときだけ・尋ねない）
    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// 市区町村の名前。引けなければ nil
    func placeName(for coords: Photo.Coords) async -> String? {
        let location = CLLocation(latitude: coords.lat, longitude: coords.lng)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return PassExchange.placeName(locality: mark.locality, administrativeArea: mark.administrativeArea)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        let coords = Photo.Coords(lat: c.latitude, lng: c.longitude)
        Task { @MainActor in PassCoordinator.shared.noteFix(coords) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// すれちがいの置き場・電波・位置をつなぐ（2026-10-16）。
///
/// 呼ばれる所: 起動（`AppDelegate`・OS に起こされた回も）・人が決まった・前面／背面・設定を変えた。
/// 毎回「いま交換してよいか」（`PassStore.exchangeAllowed`）を決め直して、電波を載せる／止める
@MainActor
final class PassCoordinator {

    static let shared = PassCoordinator()

    private let store = PassStore.shared
    private let radio = PassRadio.shared
    private let places = PassPlaceFinder.shared
    private(set) var isForeground = false

    private init() {
        radio.onReceive = { [weak self] payload in
            MainActor.assumeIsolated { self?.receive(payload) }
        }
    }

    /// 起動したとき。**オンにしていた人だけ**電波を戻す（OS に起こされた回の復元もここから）
    func launch() {
        store.useLastUser()
        refresh()
    }

    /// 前面／背面が変わった
    func setForeground(_ value: Bool) {
        isForeground = value
        if value, store.settings.enabled { places.refresh() }
        refresh()
    }

    /// オンにした（説明の「オンにする」を押した）: 決め直して、まだなら Bluetooth の許可を尋ねる
    func turnedOn() {
        refresh()
        radio.requestAuthorization()
    }

    /// 決め直す（設定を変えた・人が替わった）
    func refresh(now: Date = Date()) {
        if store.exchangeAllowed(isForeground: isForeground, now: now), let payload = store.payload {
            radio.apply(payload: PassExchange.encode(payload))
        } else {
            radio.stop()
        }
    }

    /// 前面で位置が取れた。今日は家から離れているかを覚える
    func noteFix(_ coords: Photo.Coords) {
        guard store.settings.enabled else { return }
        store.noteAway(PassExchange.isAway(current: coords, homePrefecture: store.homePrefecture))
        refresh()
    }

    private func receive(_ payload: PassExchange.Payload) {
        let now = Date()
        // **いま交換してよい回だけ**（日をまたいだ・前面でなくなった）。場所を引く前に決める
        guard store.exchangeAllowed(isForeground: isForeground, now: now), store.accepts(payload, at: now) else { return }
        let fix = places.recentFix(now: now)
        Task { @MainActor in
            let name: String?
            if let fix { name = await places.placeName(for: fix) } else { name = nil }
            store.record(payload, at: now, placeName: name, place: fix)
        }
    }
}
