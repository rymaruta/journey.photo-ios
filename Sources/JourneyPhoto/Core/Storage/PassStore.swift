import Foundation
import Combine

/// すれちがいの置き場（受け取ったカードと設定・板「10 すれちがい」・2026-10-16）。
///
/// **端末の中だけ。** 置き場は Application Support/pass/<人>.json（iCloud のバックアップから外す）。
/// サーバーには何も送らない（2026-10-16 判断: サーバーを変えない）。人ごとに分ける
/// （同じ端末で人が替わったとき、前の人の帳を見せない・`OfflineTripStore` と同じ理由）。
///
/// **1つだけ持つ**（`shared`）。電波（`PassRadio`）は画面の無いときにも OS に起こされて
/// カードを受け取るので、SwiftUI の `@StateObject` ではなく、起動の最初（`AppDelegate`）から居る
/// この1つに書く。画面には `environmentObject(PassStore.shared)` で配る。
@MainActor
final class PassStore: ObservableObject {

    static let shared = PassStore()

    @Published private(set) var settings = PassSettings()
    @Published private(set) var encounters: [PassEncounter] = []
    /// 公開一覧に今ある、カードの写真（引けたものだけ。**ここに無い写真のカードは出さない**——
    /// 非公開にした・消した・ブロックした人の写真は公開一覧から落ちる）
    @Published private(set) var photos: [String: Photo] = [:]
    /// カードの持ち主の公開プロフィール（名前・アイコン・居住地）
    @Published private(set) var owners: [String: UserProfile] = [:]
    /// 通知を押した（束を開く）合図。**数で持つ**（続けて2回押しても2回目が効く）
    @Published private(set) var openRequests = 0
    /// 夕方の知らせが前面で届いた合図（ホームが「いま」を入れ直す）
    @Published private(set) var arrivals = 0
    private(set) var hasPendingOpen = false

    private(set) var userId: String?

    /// 今日は家から離れているか（「旅のあいだ」・前面で位置が取れたときに覚える）
    private var away: (day: String, value: Bool)?
    /// 自分の居住地（プロフィールの自由入力・読めたときに覚える）。**背景の起動でも**家からの距離を
    /// 決められるように、帳と同じ置き場に持つ
    @Published private(set) var homeLocation: String?

    private let root: URL
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let fileManager: FileManager
    /// 束の知らせを予約する（試験で差し替える）
    private let schedule: (_ day: String, _ at: Date, _ count: Int) async -> Void

    static let lastUserKey = "journey-photo-pass-last-user"

    init(root: URL? = nil, defaults: UserDefaults = .standard, calendar: Calendar = .current,
         fileManager: FileManager = .default,
         schedule: ((_ day: String, _ at: Date, _ count: Int) async -> Void)? = nil) {
        self.root = root ?? Self.defaultRoot(fileManager)
        self.defaults = defaults
        self.calendar = calendar
        self.fileManager = fileManager
        self.schedule = schedule ?? { day, at, count in await PassBundleNotifier.schedule(day: day, at: at, count: count) }
    }

    static func defaultRoot(_ fileManager: FileManager = .default) -> URL {
        (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory).appendingPathComponent("pass", isDirectory: true)
    }

    private func fileURL(for userId: String) -> URL {
        root.appendingPathComponent(OfflineTripStore.hex(userId) + ".json")
    }

    /// 退会した人の帳と設定を消す（`AccountLocalData`）
    static func removeData(for userId: String, root: URL? = nil, defaults: UserDefaults = .standard,
                           fileManager: FileManager = .default) {
        guard !userId.isEmpty else { return }
        let base = root ?? defaultRoot(fileManager)
        try? fileManager.removeItem(at: base.appendingPathComponent(OfflineTripStore.hex(userId) + ".json"))
        if defaults.string(forKey: lastUserKey) == userId { defaults.removeObject(forKey: lastUserKey) }
        PassBundleNotifier.cancelAll()
    }

    // MARK: - 人の切り替え

    func use(userId: String?) {
        let id = userId.flatMap { $0.isEmpty ? nil : $0 }
        defaults.set(id, forKey: Self.lastUserKey)
        switchTo(id)
    }

    /// 前に使っていた人（OS に起こされた起動で、まだログインの確認が済んでいない回）
    func useLastUser() {
        switchTo(defaults.string(forKey: Self.lastUserKey))
    }

    private func switchTo(_ id: String?) {
        guard id != userId else { return }
        if userId != nil, id != userId {
            // 前の人の夕方の知らせを次の人に鳴らさない
            PassBundleNotifier.cancelAll()
        }
        userId = id
        photos = [:]
        owners = [:]
        away = nil
        homeLocation = nil
        guard let id, let file = load(id) else {
            settings = PassSettings()
            encounters = []
            return
        }
        settings = file.settings
        encounters = file.encounters
        homeLocation = file.homeLocation
        // 人を替える・期限切れで止めるときに夕方の知らせを消したので、まだ届いていない束の分を予約し直す
        rescheduleNotices()
        if let day = file.awayDay, let value = file.awayValue { away = (day, value) }
    }

    // MARK: - 設定

    /// 設定を変える。**ログインしていなければ何もしない**（誰の名刺か決まらない）
    func update(_ change: (inout PassSettings) -> Void) {
        guard userId != nil else { return }
        var next = settings
        change(&next)
        next.note = PassExchange.cleanNote(next.note)
        next.originLabel = next.originLabel.map(PassExchange.cleanLabel)
        next.destinationLabel = next.destinationLabel.map(PassExchange.cleanLabel).flatMap { $0.isEmpty ? nil : $0 }
        guard next != settings else { return }
        settings = next
        if !next.enabled { PassBundleNotifier.cancelAll() }
        save()
    }

    /// 電波に載せる中身。**オンで、名刺の一枚を選んであるときだけ**
    var payload: PassExchange.Payload? {
        guard userId != nil, settings.enabled, let photoId = settings.cardPhotoId else { return nil }
        // 連絡先の形の字は載せない（前の版で書いて残っている字も・2026-10-16 owner の決定）
        func allowed(_ text: String) -> String { PassExchange.containsContact(text) ? "" : text }
        return PassExchange.Payload(photoId: photoId, showsFrom: settings.showsFrom, note: allowed(settings.note),
                                    origin: allowed(settings.originLabel ?? ""),
                                    destination: allowed(settings.destinationLabel ?? ""))
    }

    /// 自分の居住地を覚える（マイページ・設定がプロフィールを読んだとき）
    func noteHome(_ text: String?) {
        guard userId != nil else { return }
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (value?.isEmpty ?? true) ? nil : value
        guard next != homeLocation else { return }
        homeLocation = next
        save()
    }

    /// 自分の居住地の都道府県（「旅のあいだ」・名刺の表の「〇〇から」）
    var homePrefecture: String? { PassExchange.homePrefecture(homeLocation) }

    /// 今日は家から離れているかを覚える（前面で位置が取れた・分からなかった）
    func noteAway(_ value: Bool?, now: Date = Date()) {
        guard let value else { return }
        let day = PassExchange.dayKey(now, calendar: calendar)
        if let away, away.day == day, away.value == value { return }
        away = (day, value)
        save()
    }

    /// 今日、家から離れているか。**今日の分を覚えていなければ nil**（分からない日は交換しない）
    func awayToday(now: Date = Date()) -> Bool? {
        guard let away, away.day == PassExchange.dayKey(now, calendar: calendar) else { return nil }
        return away.value
    }

    /// いま交換してよいか（オン・名刺あり・「いつ」の決まり）
    func exchangeAllowed(isForeground: Bool, now: Date = Date()) -> Bool {
        guard payload != nil else { return false }
        return PassExchange.allowsExchange(mode: settings.mode, isForeground: isForeground,
                                           awayFromHome: awayToday(now: now))
    }

    // MARK: - 受け取る

    /// この中身を受け取るか（**場所を引く前に**決める——要らない回に位置や地名を引かない）。
    /// 自分の名刺・同じ日に同じ写真・1日の上限を超えた回は受け取らない
    func accepts(_ payload: PassExchange.Payload, at date: Date = Date()) -> Bool {
        guard userId != nil, settings.enabled else { return false }
        if payload.photoId == settings.cardPhotoId { return false }
        let day = PassExchange.dayKey(PassExchange.deliveryDate(for: date, calendar: calendar), calendar: calendar)
        let sameDay = encounters.filter {
            PassExchange.dayKey($0.deliverAt, calendar: calendar) == day
        }
        guard sameDay.count < PassExchange.dailyLimit else { return false }
        return !sameDay.contains { $0.photoId == payload.photoId }
    }

    /// 受け取ったカードを綴じる。**時刻は時の単位・場所は 0.1 度に丸めて**持つ
    @discardableResult
    func record(_ payload: PassExchange.Payload, at date: Date = Date(),
                placeName: String? = nil, place: Photo.Coords? = nil) -> PassEncounter? {
        guard accepts(payload, at: date) else { return nil }
        let deliverAt = PassExchange.deliveryDate(for: date, calendar: calendar)
        let coarse = place.map(PassExchange.coarse)
        let card = PassEncounter(id: UUID().uuidString, photoId: payload.photoId, note: payload.note,
                                 showsFrom: payload.showsFrom,
                                 metHour: PassExchange.hourStart(date, calendar: calendar),
                                 deliverAt: deliverAt,
                                 placeName: placeName, placeLat: coarse?.lat, placeLng: coarse?.lng,
                                 number: (encounters.map(\.number).max() ?? 0) + 1,
                                 opened: false, ownerId: nil,
                                 originLabel: payload.origin.isEmpty ? nil : payload.origin,
                                 destinationLabel: payload.destination.isEmpty ? nil : payload.destination,
                                 // 連絡先の形は受け取った時に一度だけ判定して持つ（描くたびに判定し直さない）
                                 noteContact: PassExchange.containsContact(payload.note),
                                 originContact: PassExchange.containsContact(payload.origin),
                                 destinationContact: PassExchange.containsContact(payload.destination))
        encounters.append(card)
        save()
        let day = PassExchange.dayKey(deliverAt, calendar: calendar)
        let count = encounters.filter { PassExchange.dayKey($0.deliverAt, calendar: calendar) == day }.count
        let schedule = schedule
        Task { await schedule(day, deliverAt, count) }
        return card
    }

    /// まだ届いていない束の知らせを予約し直す（オンのときだけ・日ごとに1つ・枚数つき）
    func rescheduleNotices(now: Date = Date()) {
        guard settings.enabled else { return }
        let pending = Dictionary(grouping: encounters.filter { $0.deliverAt > now }) {
            PassExchange.dayKey($0.deliverAt, calendar: calendar)
        }
        let schedule = schedule
        for (day, cards) in pending {
            guard let at = cards.map(\.deliverAt).min() else { continue }
            Task { await schedule(day, at, cards.count) }
        }
    }

    // MARK: - 見せる

    /// 見せてよいカードか: 届いていて・写真が公開一覧に今あり・通報した写真ではなく・持ち主をブロックしておらず・
    /// 自分ではない
    func isVisible(_ card: PassEncounter, blocked: Set<String>, reported: Set<String> = [],
                   now: Date = Date()) -> Bool {
        guard card.deliverAt <= now, !reported.contains(card.photoId), let photo = photos[card.photoId] else { return false }
        guard let owner = photo.userId ?? photo.uploadedBy else { return false }
        return owner != userId && !blocked.contains(owner)
    }

    /// 帳に綴じたカード（届いたもの・見せてよいもの）
    func book(blocked: Set<String>, reported: Set<String> = [], now: Date = Date()) -> [PassEncounter] {
        encounters.filter { isVisible($0, blocked: blocked, reported: reported, now: now) }
    }

    /// まだ開いていない束（届いたもの・見せてよいもの）
    func unopened(blocked: Set<String>, reported: Set<String> = [], now: Date = Date()) -> [PassEncounter] {
        book(blocked: blocked, reported: reported, now: now).filter { !$0.opened }.sorted { $0.number < $1.number }
    }

    /// 画面から: 「見せない」の写し（ブロック・通報）で絞る
    func book(hiding: ModerationSnapshot, now: Date = Date()) -> [PassEncounter] {
        book(blocked: hiding.blocked, reported: hiding.reported, now: now)
    }

    func unopened(hiding: ModerationSnapshot, now: Date = Date()) -> [PassEncounter] {
        unopened(blocked: hiding.blocked, reported: hiding.reported, now: now)
    }

    /// ひとことを伏せる／出す（カードの「…」・この端末だけ）
    func setNoteHidden(_ id: String, _ hidden: Bool) {
        guard let i = encounters.firstIndex(where: { $0.id == id }), (encounters[i].noteHidden ?? false) != hidden else { return }
        encounters[i].noteHidden = hidden
        save()
    }

    /// 区間の字を伏せる／出す（伏せたら自動の形に戻す・この端末だけ）
    func setLabelsHidden(_ id: String, _ hidden: Bool) {
        guard let i = encounters.firstIndex(where: { $0.id == id }), (encounters[i].labelsHidden ?? false) != hidden else { return }
        encounters[i].labelsHidden = hidden
        save()
    }

    /// ひとことを通報できた: 印を付け、そのひとことを伏せる（2026-10-16 の読み直し）
    func markNoteReported(_ id: String) {
        guard let i = encounters.firstIndex(where: { $0.id == id }) else { return }
        encounters[i].noteReported = true
        encounters[i].noteHidden = true
        // 区間の字も同じ通報に入れて送ったので、一緒に伏せる（自動の形に戻る）
        encounters[i].labelsHidden = true
        save()
    }

    /// 帳から外す（カードの「…」）。**記録ごと消す**（次に同じ人とすれちがえば、また届く）
    func remove(_ id: String) {
        let before = encounters.count
        encounters.removeAll { $0.id == id }
        if encounters.count != before { save() }
    }

    /// 届いたが、まだ写真を引けていないカードがあるか（ホームで引きに行くかを決める）
    func hasDelivered(now: Date = Date()) -> Bool {
        encounters.contains { $0.deliverAt <= now }
    }

    func markOpened(_ ids: [String]) {
        let set = Set(ids)
        var changed = false
        for i in encounters.indices where set.contains(encounters[i].id) && !encounters[i].opened {
            encounters[i].opened = true
            changed = true
        }
        if changed { save() }
    }

    /// 届いたカードの写真と持ち主を引く。**写真は公開一覧から**（ブロックした人・通報した写真・
    /// 自分で消した写真は一覧の側で落ちている）。公開範囲を絞った写真はカードにしない
    func resolve(gallery: PublicGalleryService, profiles: ProfileService, now: Date = Date()) async {
        let owner = userId
        let due = encounters.filter { $0.deliverAt <= now }
        guard owner != nil, !due.isEmpty else { return }
        guard let all = try? await gallery.fetchPhotos() else { return }
        guard userId == owner else { return }
        let found = applyResolved(all: all, now: now)
        let ownerIds = Set(found.values.compactMap { $0.userId ?? $0.uploadedBy })
        for id in ownerIds where owners[id] == nil {
            guard let profile = try? await profiles.publicProfile(userId: id) else { continue }
            guard userId == owner else { return }
            owners[id] = profile
        }
    }

    /// 公開一覧（`all`）から、届いたカードの写真と持ち主を決める。**一覧に無い写真のカードは見せない**
    /// （次に引いたときに一覧へ戻っていれば、また見える）。返すのは引けた写真
    @discardableResult
    func applyResolved(all: [Photo], now: Date = Date()) -> [String: Photo] {
        let wanted = Set(encounters.filter { $0.deliverAt <= now }.map(\.photoId))
        var found: [String: Photo] = [:]
        for photo in all where wanted.contains(photo.id) && PassExchange.isPublicCard(photo) {
            found[photo.id] = photo
        }
        photos = found
        var changed = false
        for i in encounters.indices {
            guard let photo = found[encounters[i].photoId],
                  let ownerId = photo.userId ?? photo.uploadedBy,
                  encounters[i].ownerId != ownerId else { continue }
            encounters[i].ownerId = ownerId
            changed = true
        }
        if changed { save() }
        return found
    }

    /// 帳のための持ち主の名前と都道府県（**相手が出すと決めた都道府県だけ**）
    var ownerNames: [String: String] { owners.mapValues(\.name) }

    func prefecture(for card: PassEncounter) -> String? {
        guard card.showsFrom, let owner = card.ownerId else { return nil }
        return PassExchange.homePrefecture(owners[owner]?.homeLocation)
    }

    var ownerPrefectures: [String: String] {
        owners.compactMapValues { PassExchange.homePrefecture($0.homeLocation) }
    }

    // MARK: - 通知を押した

    func noteArrival() { arrivals += 1 }

    func requestOpen() {
        hasPendingOpen = true
        openRequests += 1
    }

    /// 押された分を受け取る（1回だけ）
    func takePendingOpen() -> Bool {
        defer { hasPendingOpen = false }
        return hasPendingOpen
    }

    // MARK: - 見本（絵の撮影・Debug のみ）

    /// 見本のカードを入れる（`PreviewSession.passSample`・Debug のみ）。公開一覧の写真から作る。
    /// **起動のたびに入れ直す**（前の回に開いた印が残ると、ホームの札が出ず絵が撮れない）
    func seedPreview(photoIds: [String], now: Date = Date()) {
        guard userId != nil, !photoIds.isEmpty else { return }
        let names = ["京都市", "京都市", "金沢市", "札幌市", "京都市", "鳥取市", "京都市"]
        encounters = photoIds.prefix(7).enumerated().map { index, id in
            let met = now.addingTimeInterval(-Double(3 + index) * 3600)
            return PassEncounter(
                id: UUID().uuidString, photoId: id, note: index == 0 ? "夕方の街を歩くのが好き" : "",
                showsFrom: true, metHour: PassExchange.hourStart(met, calendar: calendar),
                deliverAt: now.addingTimeInterval(-60), placeName: names[index % names.count],
                placeLat: 35.0, placeLng: 135.8, number: index + 1, opened: false, ownerId: nil,
                // 1枚目は和文2字と和文4字の区間（字数が違っても発・着の大きさがそろい、矢印が中央に来るかを撮る）
                originLabel: index == 0 ? "東京" : nil, destinationLabel: index == 0 ? "フランス" : nil)
        }
        settings.enabled = true
        // 自分のカードの見本（名刺の一枚を選ぶ画面）も同じ区間・裏のひとことつきで撮る
        settings.setOrigin(.custom, text: "東京")
        settings.setDestination(custom: true, text: "フランス")
        if settings.note.isEmpty { settings.note = "霧の朝が好きです" }
        save()
    }

    // MARK: - 読み書き

    private struct File: Codable {
        var settings: PassSettings
        var encounters: [PassEncounter]
        var awayDay: String?
        var awayValue: Bool?
        var homeLocation: String?
    }

    private func load(_ id: String) -> File? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? Self.decoder.decode(File.self, from: data)
    }

    private func save() {
        guard let id = userId else { return }
        let file = File(settings: settings, encounters: encounters, awayDay: away?.day, awayValue: away?.value,
                        homeLocation: homeLocation)
        guard let data = try? Self.encoder.encode(file) else { return }
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            var url = fileURL(for: id)
            // 🔴 **ロック中にも書ける形にする。** カードは画面を閉じている間（OS に起こされた電波の知らせ）に
            // 届くので、既定の「完全な保護」だとロック中に書けない。`.completeUntilFirstUserAuthentication`
            // （起動後に一度ロックを解いてから）にする
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            // 道筋（人の id の 16 進）を出さない。種類と番号だけ
            let ns = error as NSError
            print("[pass] 書けませんでした: \(ns.domain) \(ns.code)")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
