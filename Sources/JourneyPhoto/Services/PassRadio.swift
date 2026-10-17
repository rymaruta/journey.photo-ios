import Foundation
import CoreBluetooth
import Combine
import CoreLocation

/// すれちがいの電波（Bluetooth Low Energy・2026-10-16）。
///
/// **2026-10-16 判断: サーバーを使わず、近くの人を Bluetooth で見つける。**
///
/// 1. 自分の端末は、アプリ固有のサービス（`serviceUUID`）で広告する（周辺機器の役）。特性は1つ
///    （`characteristicUUID`・読むだけ）で、中身は `PassExchange.Payload`（版・名刺の写真の id・
///    出身を出すか・ひとこと）。値は特性に焼いて渡す（読みの依頼に応える処理を持たない）
/// 2. 同時に、同じサービスを探す（中心の役）。見つけたら繋いで特性を1つ読み、**読んだらすぐ切る**
/// 3. 読んだ中身は `PassStore` が綴じる。**同じ相手（同じ写真）は1日1回まで**（`PassStore.accepts`）
///
/// 🔴 **中身は暗号化していない・誰でも読める**（2026-10-16 の読み直し）。アプリでなくても、近くで
/// Bluetooth を調べる道具（LightBlue など）から繋げば、名刺の写真の id とひとことが読める。写真の id から
/// 公開一覧で持ち主が分かり、**値は名刺を変えるまで日をまたいでも同じ**。誰が読んだかはこちらでは分からず、
/// ブロックした人の端末にも届きうる。画面と説明の文はこの事実に合わせてある（`PassSettingsView`）。
/// 値を日ごとに変わる形で包む・サーバーで回る合言葉にする案は owner が決める（v1 ではしない）
///
/// 背景でも動くように `bluetooth-central`・`bluetooth-peripheral` の背景の仕事を宣言してあり
/// （`project.yml`）、OS に起こされたときのために復元の識別子を付ける。
///
/// ⚠️ **確かめていないこと**: 実機での見つかりやすさ。iOS は背景の広告をサービスの「あふれ領域」に
/// 移し、背景どうし（両方ともアプリを閉じている）では見つけ合えないことが多い（Apple の文書）。
/// 片方が画面を開いているときに見つかる、を最初の目安にしている
final class PassRadio: NSObject, ObservableObject {

    static let shared = PassRadio()

    /// アプリ固有のサービス（**変えると前の版と見つけ合えなくなる**）
    static let serviceUUID = CBUUID(string: "6A3E2C1B-7F44-4D0B-9C3E-1B5A0D2F8E61")
    /// 版 1 の中身の特性（前のアプリが読む・ひとことまで）
    static let characteristicUUID = CBUUID(string: "6A3E2C1C-7F44-4D0B-9C3E-1B5A0D2F8E61")
    /// 版 2 の中身の特性（発・着の字つき・2026-10-16）。**版 1 と並べて出す**——前のアプリとも交換できる
    static let characteristicV2UUID = CBUUID(string: "6A3E2C1D-7F44-4D0B-9C3E-1B5A0D2F8E61")

    /// 読む特性を選ぶ: **版 2 があれば版 2、無ければ版 1**（前のアプリの端末は版 1 だけを出している）
    static func characteristicToRead(_ uuids: [CBUUID]) -> CBUUID? {
        if uuids.contains(characteristicV2UUID) { return characteristicV2UUID }
        if uuids.contains(characteristicUUID) { return characteristicUUID }
        return nil
    }
    static let centralRestoreId = "photo.journey.pass.central"
    static let peripheralRestoreId = "photo.journey.pass.peripheral"

    /// 読めた端末に繋ぎ直すまでの間
    static let retryInterval: TimeInterval = 10 * 60
    /// 読めなかった端末に、`retryInterval` の間に試してよい回数
    static let maxFailures = 3
    /// 繋いでから読み終えるまで待つ長さ（過ぎたら切る）
    static let connectTimeout: TimeInterval = 10
    /// 同時に繋ぐ数
    static let maxConnections = 3

    /// 端末ごとの記録（読めた時・読めなかった時）
    struct PeerRecord: Equatable {
        var lastSuccess: Date?
        var failures: [Date] = []
    }

    /// 受け取った中身（主スレッドで呼ぶ）
    var onReceive: ((PassExchange.Payload) -> Void)?

    private var central: CBCentralManager?
    /// 中心の管理者が復元の識別子つきか（許可を尋ねるためだけに作った管理者は付いていない）
    private var centralRestorable = false
    private var peripheralManager: CBPeripheralManager?
    /// 載せている中身（版 2・nil なら止めている）。足し終えたかはこの中身で見分ける
    private var payload: Data?
    /// 版 1 の中身（前のアプリ向け・同じ設定から作るので、版 2 が同じなら同じ）
    private var legacyPayload: Data?
    /// 足し終えた（`didAdd` が成功した）サービスの中身。同じなら足し直さない
    private var publishedPayload: Data?
    /// 足している途中の中身（`didAdd` を待っている順）。**1つの変数で持つと**、続けて2回変えたときに
    /// 前の `didAdd` を後の中身の答えと取り違えた（2026-10-16 の読み直し）
    private var pendingAdds: [Data] = []
    /// 足せずに一度だけ足し直した中身（同じ中身で何度も足し直さない）
    private var retriedPayload: Data?
    /// 古い記録を最後に掃除した時（前面の重ねて受ける知らせは多いので、数秒に1回に間引く）
    private var lastPrune = Date.distantPast
    static let pruneInterval: TimeInterval = 5
    /// 前面か（前面だけ同じ端末の知らせを重ねて受け、読めなかった相手を拾い直す）
    private var foreground = false
    private var connecting: [UUID: CBPeripheral] = [:]
    /// 繋ぎ始めた時（`connectTimeout` を過ぎたものは、次の知らせのときに自分で切る）
    private var connectStarted: [UUID: Date] = [:]
    private var peers: [UUID: PeerRecord] = [:]

    /// 動いているか（設定の画面の表示用）
    private(set) var isRunning = false

    /// 電波の管理者が知らせてきた Bluetooth の状態（設定の画面の案内・2026-10-16）。
    /// 🔴 **Bluetooth を切っても何も知らせていなかった**——オンのまま、すれちがいが黙って止まっていた。
    /// 管理者を手放したら（止めた）分からないので `.unknown` に戻す
    @Combine.Published private(set) var powerState: CBManagerState = .unknown

    /// 設定の画面に「Bluetooth がオフです」を出すか。すれちがいをオンにしていて、電源が切れているときだけ
    static func showsPowerOffNotice(enabled: Bool, state: CBManagerState) -> Bool {
        enabled && state == .poweredOff
    }

    /// 載せる中身を決める。**nil なら止めて、電波の管理者も手放す**
    /// （手放さないと OS の Bluetooth の印が残る）。
    ///
    /// 🔴 **初めて管理者を作ったときに、OS の Bluetooth の許可のダイアログが出る**。
    /// オンにする説明（`PassIntroSheet`）を見せてからだけ呼ぶ
    func apply(payload next: Data?, legacy: Data? = nil, foreground: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let next else { stop(); return }
        let wasForeground = self.foreground
        self.foreground = foreground
        payload = next
        legacyPayload = legacy
        isRunning = true
        // 許可を尋ねるためだけに作った管理者（識別子なし）は作り直す——OS に起こされたときに復元できない
        if central != nil, !centralRestorable {
            central?.delegate = nil
            central = nil
        }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil,
                                       options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreId,
                                                 CBCentralManagerOptionShowPowerAlertKey: false])
            centralRestorable = true
        } else if let central {
            if wasForeground != foreground, central.isScanning { central.stopScan() }
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
        centralRestorable = false
    }

    func stop() {
        payload = nil
        legacyPayload = nil
        publishedPayload = nil
        pendingAdds = []
        isRunning = false
        if let central {
            if central.state == .poweredOn { central.stopScan() }
            for peripheral in connecting.values { central.cancelPeripheralConnection(peripheral) }
        }
        connecting = [:]
        connectStarted = [:]
        if let peripheralManager, peripheralManager.state == .poweredOn {
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
        }
        central?.delegate = nil
        peripheralManager?.delegate = nil
        central = nil
        centralRestorable = false
        peripheralManager = nil
        powerState = .unknown
    }

    // MARK: - 中心の役（探す・読む）

    private func startScanning(_ central: CBCentralManager) {
        guard payload != nil, central.state == .poweredOn, !central.isScanning else { return }
        // 前面だけ重ねて受ける（背景では OS が重ねない）。繋ぐかは端末ごとの記録で間引く
        central.scanForPeripherals(withServices: [Self.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: foreground])
    }

    /// 探し直す。**重ねて受けない探し方では、一度知らされた端末は二度と知らされない**——読めなかった相手を
    /// 拾い直すために、読めなかったときに止めてから探し直す
    private func restartScanning() {
        guard let central, central.state == .poweredOn else { return }
        if central.isScanning { central.stopScan() }
        startScanning(central)
    }

    /// 繋ぐか: 同時の数に空きがある・最近読めた端末ではない・読めなかった回数が上限に達していない
    static func shouldConnect(_ record: PeerRecord?, connecting: Int, now: Date) -> Bool {
        guard connecting < maxConnections else { return false }
        guard let record else { return true }
        if let success = record.lastSuccess, now.timeIntervalSince(success) < retryInterval { return false }
        return record.failures.filter { now.timeIntervalSince($0) < retryInterval }.count < maxFailures
    }

    /// `connectTimeout` を過ぎた接続待ち。**背景では遅らせた処理が走らないことがある**ので、知らせが来るたびに見る
    static func staleConnections(_ started: [UUID: Date], now: Date) -> [UUID] {
        started.filter { now.timeIntervalSince($0.value) >= connectTimeout }.map(\.key)
    }

    /// 古い記録を掃除する（見送りの間を過ぎたものは要らない）
    static func pruned(_ peers: [UUID: PeerRecord], now: Date) -> [UUID: PeerRecord] {
        peers.compactMapValues { record in
            var r = record
            r.failures = r.failures.filter { now.timeIntervalSince($0) < retryInterval }
            if let s = r.lastSuccess, now.timeIntervalSince(s) >= retryInterval { r.lastSuccess = nil }
            return r.lastSuccess == nil && r.failures.isEmpty ? nil : r
        }
    }

    private func sweepStale(now: Date) {
        for id in Self.staleConnections(connectStarted, now: now) {
            if let peripheral = connecting[id] { finish(peripheral, succeeded: false) } else { connectStarted[id] = nil }
        }
    }

    private func finish(_ peripheral: CBPeripheral, succeeded: Bool) {
        let id = peripheral.identifier
        guard connecting[id] != nil || connectStarted[id] != nil else { return }
        connecting[id] = nil
        connectStarted[id] = nil
        central?.cancelPeripheralConnection(peripheral)
        var record = peers[id] ?? PeerRecord()
        if succeeded {
            record.lastSuccess = Date()
            record.failures = []
        } else {
            record.failures.append(Date())
        }
        peers[id] = record
        if !succeeded { restartScanning() }
    }

    // MARK: - 周辺機器の役（広告する）

    /// `didAdd` の答えで、足し終えた中身をどうするか
    enum Published: Equatable {
        case keep
        case clear
        case set(Data)
    }

    /// `didAdd` の答えの後にすること
    enum AddFollowUp: Equatable {
        /// 何もしない（前の中身の答え・同じ中身の後の答えを待つ）
        case none
        /// 広告する
        case advertise
        /// 止める（もう一度試した後も足せなかった）
        case stop
        /// 止めて、数秒後に一度だけ足し直す
        case stopAndRetry
    }

    /// 足せなかったときに足し直すまでの間
    static let addRetryDelay: TimeInterval = 3

    static func followUp(_ published: Published, alreadyRetried: Bool) -> AddFollowUp {
        switch published {
        case .keep: return .none
        case .set: return .advertise
        case .clear: return alreadyRetried ? .stop : .stopAndRetry
        }
    }

    /// `didAdd` の答えを、足した順の先頭の中身の答えとして読む。**いま載せる中身の答えだけで決める**——
    /// 続けて2回変えたとき、前の中身の答えを後の中身の答えと取り違えない（2026-10-16 の読み直し）
    static func afterAdd(pending: [Data], current: Data?, failed: Bool) -> (pending: [Data], published: Published) {
        var rest = pending
        guard !rest.isEmpty else { return (rest, .keep) }
        let added = rest.removeFirst()
        guard added == current else { return (rest, .keep) }
        if failed { return (rest, .clear) }
        // 後にもう一度同じ中身を足している（その答えを待つ）
        if rest.contains(added) { return (rest, .keep) }
        return (rest, .set(added))
    }

    private func publish(_ manager: CBPeripheralManager) {
        guard let payload, manager.state == .poweredOn else { return }
        guard payload.count <= PassExchange.payloadByteLimit else { return }
        if publishedPayload == payload {
            if !manager.isAdvertising { startAdvertising(manager) }
            return
        }
        guard pendingAdds.last != payload else { return }
        manager.stopAdvertising()
        manager.removeAllServices()
        publishedPayload = nil
        var characteristics: [CBCharacteristic] = [
            CBMutableCharacteristic(type: Self.characteristicV2UUID, properties: [.read],
                                    value: payload, permissions: [.readable]),
        ]
        if let legacyPayload, legacyPayload.count <= PassExchange.payloadByteLimit {
            characteristics.append(CBMutableCharacteristic(type: Self.characteristicUUID, properties: [.read],
                                                           value: legacyPayload, permissions: [.readable]))
        }
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = characteristics
        pendingAdds.append(payload)
        // 広告は `didAdd` が成功してから（足せなかったサービスを広告しない）
        manager.add(service)
    }

    private func startAdvertising(_ manager: CBPeripheralManager) {
        // 名前は載せない（端末の名前・持ち主が分かる文字を出さない）
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
    }
}

extension PassRadio: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // 許可を尋ねるためだけに作った管理者（`requestAuthorization`）は、答えが来たら手放す
        // （手放すと `stop` が `.unknown` に戻す）
        guard payload != nil else {
            if central.state != .unknown { stop() }
            return
        }
        powerState = central.state
        if central.state == .poweredOn {
            startScanning(central)
        } else {
            connecting = [:]
            connectStarted = [:]
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
        sweepStale(now: now)
        if now.timeIntervalSince(lastPrune) >= Self.pruneInterval {
            peers = Self.pruned(peers, now: now)
            lastPrune = now
        }
        let id = peripheral.identifier
        guard payload != nil, connecting[id] == nil,
              Self.shouldConnect(peers[id], connecting: connecting.count, now: now) else { return }
        connecting[id] = peripheral
        connectStarted[id] = now
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        // 前面では遅らせて切る（背景で走らなかった分は、次の知らせの `sweepStale` が切る）
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout) { [weak self] in
            guard let self, self.connecting[id] != nil else { return }
            self.sweepStale(now: Date())
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(peripheral, succeeded: false)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // 読み終える前に切れた（読めた回は `finish` が先に片づけている）
        finish(peripheral, succeeded: false)
    }
}

extension PassRadio: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            finish(peripheral, succeeded: false)
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicV2UUID, Self.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let found = service.characteristics ?? []
        guard error == nil, let wanted = Self.characteristicToRead(found.map(\.uuid)),
              let characteristic = found.first(where: { $0.uuid == wanted }) else {
            finish(peripheral, succeeded: false)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, let payload = PassExchange.decode(data) else {
            finish(peripheral, succeeded: false)
            return
        }
        finish(peripheral, succeeded: true)
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
            pendingAdds = []
        }
    }

    /// OS に起こされた。焼いた値は前の起動のもの——中身が同じかは分からないので足し直す
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        publishedPayload = nil
        pendingAdds = []
    }

    /// サービスを足せたか。**足せなかったら広告しない**（次に決め直したとき足し直す）
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { print("[pass] サービスを足せませんでした: \((error as NSError).code)") }
        let answer = Self.afterAdd(pending: pendingAdds, current: payload, failed: error != nil)
        pendingAdds = answer.pending
        if case .set(let added) = answer.published { publishedPayload = added }
        if answer.published == .clear { publishedPayload = nil }
        switch Self.followUp(answer.published, alreadyRetried: payload != nil && retriedPayload == payload) {
        case .none:
            return
        case .advertise:
            retriedPayload = nil
            if !peripheral.isAdvertising { startAdvertising(peripheral) }
        case .stop:
            // **足せなかったサービスを広告しない**（前の版は .clear でも広告へ進んでいた・2026-10-16 の読み直し）
            peripheral.stopAdvertising()
        case .stopAndRetry:
            peripheral.stopAdvertising()
            retriedPayload = payload
            let tried = payload
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.addRetryDelay) { [weak self] in
                guard let self, let tried, self.payload == tried, let manager = self.peripheralManager else { return }
                self.publish(manager)
            }
        }
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

    /// 市区町村の名前。引けなければ nil。**Apple の地図へは約1km に丸めた座標だけを渡す**
    /// （`PassExchange.lookupCoords`・位置の利用目的の文と同じ約束）
    func placeName(for coords: Photo.Coords) async -> String? {
        let rounded = PassExchange.lookupCoords(coords)
        let location = CLLocation(latitude: rounded.lat, longitude: rounded.lng)
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
            radio.apply(payload: PassExchange.encode(payload), legacy: PassExchange.encodeV1(payload),
                        foreground: isForeground)
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
