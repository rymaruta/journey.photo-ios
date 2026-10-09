import Foundation

// 「電波なしで使える旅」（Pro・板 72〜72e・2026-10-09）の、画面を持たない決まり。
//
// 画面は `Features/Trips/Offline*.swift`、端末への書き込みは `Core/Storage/OfflineTripStore.swift`。
// ここは Linux でも試験で見張れるものだけを置く:
//   - 端末に残す中身の形（`OfflineTripManifest`）
//   - どの場所を何番で保存するか（`OfflineTripPlan.stops`）
//   - 光の時刻の並べ方（`OfflineLight`）
//   - 保存の状態の移り変わり（`OfflineSaveStatus.reduce`）と、札の姿（`OfflineSaveStatus.phase`）
//   - 保存したあとにプランが変わったか（`OfflineTripPrint`）
//   - 容量の数え方・書き方（`OfflineTripBytes`）と文面（`OfflineTripText`）

// MARK: - 端末に残す中身

/// 端末に保存した旅の中身（`manifest.json`）。**圏外の画面はこれだけで組む**（サーバーを読まない）。
struct OfflineTripManifest: Codable, Equatable, Identifiable {
    /// 形を変えたら上げる。読めない版は「保存していない」と同じに扱う（壊れた画面を出さない）
    static let currentVersion = 1

    var version: Int = OfflineTripManifest.currentVersion
    let planId: String
    let title: String
    let startDate: String?
    let endDate: String?
    let savedAt: Date
    /// 保存したときのプランの指紋。いまのプランと比べて「変わった」を出す
    let print: OfflineTripPrint
    let days: [Day]
    /// 旅全体の地図の画像（ファイル名）。座標のある場所が無ければ nil
    let overviewMap: String?
    /// 保存した中身の大きさ（バイト）。**書き終えたあとに数えた値**
    var bytes: Int64

    var id: String { planId }

    /// 何か所保存したか（日をまたいで数える）
    var stopCount: Int { days.reduce(0) { $0 + $1.stops.count } }

    struct Day: Codable, Equatable {
        /// 1から
        let number: Int
        /// `YYYY-MM-DD`。日付の決まらない日は nil（光の時刻も無い）
        let date: String?
        let stops: [Stop]
    }

    struct Stop: Codable, Equatable, Identifiable {
        /// 旅全体の通し番号（1から）。**地図の画像の点と同じ番号**
        let number: Int
        /// `OfflineTripPlan.key`（"spot:sp_…" / "location:slug"）
        let key: String
        let name: String
        /// 住所の代わりの地域（「[都道府県] [市区町村]」）。台帳に番地は無い
        let address: String?
        let coords: Photo.Coords?
        let note: String?
        /// その日の光の時刻（日付・座標・時刻帯が揃ったときだけ）
        let light: OfflineLight?
        let samples: [Sample]
        /// この場所の周りの地図の画像（ファイル名）
        let map: String?

        var id: Int { number }
    }

    /// 作例1枚。**作者とライセンスは画像と一緒に残す**（CC BY・CC BY-SA の条件。圏外でも出典を出す）
    struct Sample: Codable, Equatable {
        let file: String
        let title: String
        /// 出典の1行（「写真: 作者 / CC BY-SA 4.0」・その他の出どころは規約の文のまま）
        let credit: String
        let sourceUrl: URL?
        let licenseUrl: URL?
    }
}

// MARK: - どの場所を保存するか

enum OfflineTripPlan {

    /// 1か所あたりに保存する作例の数（owner 2026-10-09「3枚」）
    static let samplesPerStop = 3

    /// 保存する1か所（まだ画像を取る前）
    struct Stop: Equatable {
        let number: Int
        let dayIndex: Int
        let date: String?
        let key: String
        let item: TripItem
        let name: String
        let address: String?
        let coords: Photo.Coords?
        let note: String?
        /// その日・その場所の光の時刻（**保存する前に計算する**。旅の日付で）
        let light: OfflineLight?
    }

    /// 項目の鍵。**スポットと撮影地を混ぜない**（`SavedSpotKey` と同じ理由）
    static func key(_ item: TripItem) -> String {
        switch item {
        case .spot(let spotId, _): return "spot:\(spotId)"
        case .location(let slug, _): return "location:\(slug)"
        }
    }

    /// プランの全部の場所に、**日程の順のまま**通し番号を振る（地図の点・行の番号と揃える）。
    /// 名前・座標は `TripDayMap.stops` と同じ引き方（地図で見る と同じ場所を指す）
    static func stops(of plan: TripPlan, index: [OfficialSpot], places: [DerivedSpot.Place]) -> [Stop] {
        var number = 0
        var result: [Stop] = []
        for (di, day) in plan.days.enumerated() {
            let date = TripPlanText.dayDate(index: di, day: day, start: plan.startDate, end: plan.endDate)
            for map in TripDayMap.stops(of: day, index: index, places: places) {
                let item = day.items[map.number - 1]
                number += 1
                let address: String?
                let zone: TimeZone?
                switch item {
                case .spot(let spotId, _):
                    let spot = index.first { $0.spotId == spotId }
                    address = spot.flatMap(Self.address)
                    zone = spot.flatMap { SunTimes.timeZone(named: $0.timeZone, country: $0.region?.country) }
                case .location:
                    address = nil
                    zone = map.coords.flatMap(Self.zoneForLocation)
                }
                let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(Stop(number: number, dayIndex: di, date: date, key: key(item), item: item,
                                   name: map.name, address: address, coords: map.coords,
                                   note: (note?.isEmpty ?? true) ? nil : note,
                                   light: OfflineLight.make(date: date, coords: map.coords, zone: zone)))
            }
        }
        return result
    }

    /// 「[国] [都道府県] [市区町村]」。どれも無ければ nil
    static func address(_ spot: OfficialSpot) -> String? {
        let parts = [spot.region?.country, spot.region?.prefecture, spot.region?.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// 撮影地（写真から作った場所）の時計。**台帳の時刻帯が無いので、日本の中に入るときだけ東京**
    /// （2026-10-09 判断: 端末の時計で外国の場所の時刻を出すと、ありもしない時刻になる。
    /// 日本の外の撮影地は光の時刻を出さない）
    static func zoneForLocation(_ coords: Photo.Coords) -> TimeZone? {
        let inJapan = (20.0...46.0).contains(coords.lat) && (122.0...154.0).contains(coords.lng)
        return inJapan ? TimeZone(identifier: "Asia/Tokyo") : nil
    }
}

// MARK: - 光の時刻

/// 1日ぶんの光の時刻（**その土地の時計の文字**で残す。旅先で端末の時計が違っても読み替えない）
struct OfflineLight: Codable, Equatable {
    /// 「6:20〜6:45」
    let morningBlue: String?
    /// 「6:51」
    let sunrise: String?
    let sunset: String?
    let eveningBlue: String?

    var isEmpty: Bool { morningBlue == nil && sunrise == nil && sunset == nil && eveningBlue == nil }

    /// その日・その場所の光の時刻。日付・座標・時計のどれかが無い、計算できない日は nil
    static func make(date: String?, coords: Photo.Coords?, zone: TimeZone?) -> OfflineLight? {
        guard let date, let coords, let zone,
              let times = SunTimes.compute(date, lat: coords.lat, lng: coords.lng) else { return nil }
        let light = OfflineLight(morningBlue: span(times.morningBlue, zone),
                                 sunrise: clock(times.sunrise, zone),
                                 sunset: clock(times.sunset, zone),
                                 eveningBlue: span(times.eveningBlue, zone))
        return light.isEmpty ? nil : light
    }

    /// 板の書き方「6:51」（時の頭の 0 を落とす）
    static func clock(_ date: Date?, _ zone: TimeZone) -> String? {
        guard let hhmm = SunTimes.clock(date, in: zone) else { return nil }
        return hhmm.hasPrefix("0") ? String(hhmm.dropFirst()) : hhmm
    }

    /// 「6:20〜6:45」。どちらかの端が無ければ nil
    static func span(_ s: SunTimes.Span, _ zone: TimeZone) -> String? {
        guard let a = clock(s.start, zone), let b = clock(s.end, zone) else { return nil }
        return "\(a)〜\(b)"
    }

    /// 場所の画面の4つの枠（板 72d）。**一日の順**（朝のブルーアワー → 日の出 → 日の入り → 夕のブルーアワー）。
    /// 無いもの（白夜・極夜）は枠ごと出さない
    var entries: [(label: String, value: String)] {
        [
            (L("朝のブルーアワー", "Morning blue hour"), morningBlue),
            (L("日の出", "Sunrise"), sunrise),
            (L("日の入り", "Sunset"), sunset),
            (L("夕のブルーアワー", "Evening blue hour"), eveningBlue),
        ].compactMap { pair in pair.1.map { (pair.0, $0) } }
    }

    /// 旅の画面の行の小さい1行（板 72c「日の出 6:52 · 日の入り 16:39」）。
    /// 日の出と日の入りを先に。どちらも無い日（白夜・極夜）はブルーアワーを出す
    var line: String? {
        var parts: [String] = []
        if let sunrise { parts.append(L("日の出 \(sunrise)", "Sunrise \(sunrise)")) }
        if let sunset { parts.append(L("日の入り \(sunset)", "Sunset \(sunset)")) }
        if parts.isEmpty {
            if let morningBlue { parts.append(L("ブルーアワー \(morningBlue)", "Blue hour \(morningBlue)")) }
            if let eveningBlue { parts.append(L("ブルーアワー \(eveningBlue)", "Blue hour \(eveningBlue)")) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - プランが変わったか

/// プランの指紋。**圏外で出す中身に効くものだけ**（題・日付・場所の並び・メモ）
struct OfflineTripPrint: Codable, Equatable {
    let title: String
    let startDate: String?
    let endDate: String?
    /// 日ごとの項目の鍵（並びのまま）
    let days: [[String]]
    /// 鍵 → メモ（同じ鍵が2回あれば、あとの方）
    let notes: [String: String]

    init(_ plan: TripPlan) {
        title = plan.title
        startDate = plan.startDate
        endDate = plan.endDate
        days = plan.days.map { $0.items.map(OfflineTripPlan.key) }
        var notes: [String: String] = [:]
        for day in plan.days {
            for item in day.items {
                if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    notes[OfflineTripPlan.key(item)] = note
                }
            }
        }
        self.notes = notes
    }

    /// 保存したあとの変わり方
    enum Change: Equatable {
        case none
        /// 場所が増えただけ
        case added(Int)
        /// 場所が減っただけ
        case removed(Int)
        /// それ以外（並び・日付・メモ・題・増減の両方）
        case other
    }

    /// 残った場所の（何日目, 鍵）の並び。**空の日は数えない**（圏外の画面にも出ない）
    private static func placed(_ days: [[String]], keeping keys: Set<String>) -> [[String]] {
        days.enumerated().flatMap { di, keysInDay in keysInDay.filter(keys.contains).map { ["\(di)", $0] } }
    }

    /// 保存したとき（self）から、いま（`current`）までの変わり方
    func change(to current: OfflineTripPrint) -> Change {
        guard self != current else { return .none }
        let before = Set(days.flatMap { $0 }), after = Set(current.days.flatMap { $0 })
        let added = after.subtracting(before).count, removed = before.subtracting(after).count
        // 増えた・減った場所を除くと、ほかは同じか（並び・日付・メモ・題）
        let sameRest = title == current.title && startDate == current.startDate && endDate == current.endDate
            && Self.placed(days, keeping: after) == Self.placed(current.days, keeping: before)
            && notes.filter({ after.contains($0.key) }) == current.notes.filter({ before.contains($0.key) })
        if sameRest, added > 0, removed == 0 { return .added(added) }
        if sameRest, removed > 0, added == 0 { return .removed(removed) }
        return .other
    }
}

// MARK: - 保存の状態

/// 1つの旅の保存の状態。**端末にあるもの（`saved`・`partial`）と、いま走っているもの（`running`）を分けて持つ**。
///
/// 決まり（owner 2026-10-09）:
///  - 保存中は画面を移っても続ける（`OfflineTripStore` が持つ。画面は見ているだけ）
///  - 「止める」・アプリを閉じた・電波が切れた → 途中まで残し、次は「続きから保存」
///  - 保存し直しの途中で止まっても、前に保存した中身は残す（圏外で何も出ないよりよい）
struct OfflineSaveStatus: Equatable {
    struct Saved: Equatable {
        let bytes: Int64
        let savedAt: Date
    }
    struct Progress: Equatable {
        var done: Int
        let total: Int
        var bytes: Int64
        /// 保存し終えたときのおおよその大きさ（板「12 / 24 MB」の右）
        let estimate: Int64
    }
    struct Partial: Equatable {
        let done: Int
        let total: Int
    }

    var saved: Saved?
    var running: Progress?
    var partial: Partial?
    /// 保存できなかった理由（次に押すまで出す）
    var error: String?

    enum Event: Equatable {
        case started(total: Int, estimate: Int64, alreadyDone: Int)
        case progressed(done: Int, bytes: Int64)
        case finished(bytes: Int64, at: Date)
        /// 止めた・電波が切れた・アプリが裏で止められた。**途中まで残す**
        case stopped
        case failed(String)
        /// 起動し直したら途中のものが残っていた
        case foundPartial(done: Int, total: Int)
        /// 端末から削除した（保存済み・途中の両方）
        case deleted
    }

    static func reduce(_ s: OfflineSaveStatus, _ event: Event) -> OfflineSaveStatus {
        var s = s
        switch event {
        case .started(let total, let estimate, let alreadyDone):
            s.running = Progress(done: min(alreadyDone, total), total: total, bytes: 0, estimate: estimate)
            s.partial = nil
            s.error = nil
        case .progressed(let done, let bytes):
            guard var r = s.running else { return s }
            r.done = min(max(done, r.done), r.total)
            r.bytes = max(bytes, 0)
            s.running = r
        case .finished(let bytes, let at):
            s.saved = Saved(bytes: bytes, savedAt: at)
            s.running = nil
            s.partial = nil
            s.error = nil
        case .stopped:
            if let r = s.running { s.partial = Partial(done: r.done, total: r.total) }
            s.running = nil
        case .failed(let message):
            if let r = s.running { s.partial = Partial(done: r.done, total: r.total) }
            s.running = nil
            s.error = message
        case .foundPartial(let done, let total):
            guard s.running == nil else { return s }
            s.partial = Partial(done: min(done, total), total: total)
        case .deleted:
            s = OfflineSaveStatus()
        }
        return s
    }

    /// 札の姿（板 72b）
    enum Phase: Equatable {
        /// Pro でなく、端末にも何も無い（押すと Pro の案内）
        case free
        /// 1 保存前
        case before
        /// 2 保存中
        case saving(Progress)
        /// 途中で止まった（owner 2026-10-09「続きから保存」）
        case interrupted(Partial)
        /// 3 保存済み
        case saved(Saved)
        /// 4 保存したあとにプランが変わった
        case stale(Saved, OfflineTripPrint.Change)
        /// Pro かどうか分からず、端末にも何も無い（札を出さない）
        case hidden
    }

    /// - Parameters:
    ///   - isPro: サーバーのプロフィールの `pro`。読めなかったら nil
    ///   - change: 保存したときから、いまのプランまでの変わり方
    func phase(isPro: Bool?, change: OfflineTripPrint.Change) -> Phase {
        if let running { return .saving(running) }
        // **途中のものは保存済みより先に出す**（続きから保存を押せるように）
        if let partial { return .interrupted(partial) }
        if let saved { return change == .none ? .saved(saved) : .stale(saved, change) }
        switch isPro {
        case .some(true): return .before
        case .some(false): return .free
        case .none: return .hidden
        }
    }
}

/// 新しく保存する・保存し直す・続きから保存するのは Pro だけ。**見る・消すは誰でも**
/// （owner 2026-10-09: Pro が切れても、保存済みの旅は見られる・消せる）
enum OfflineTripAccess {
    enum Action: Equatable { case save, resume, resave, view, delete }

    /// Pro の案内を出すべきか（押したときの行き先）
    static func needsPro(_ action: Action, isPro: Bool?) -> Bool {
        switch action {
        case .view, .delete: return false
        case .save, .resume, .resave: return isPro != true
        }
    }
}

// MARK: - 容量

enum OfflineTripBytes {

    /// 1か所のおおよその大きさ（作例3枚と周りの地図1枚）。保存前の「約 24 MB」に使う
    static let perStopEstimate: Int64 = 3 * 450_000 + 180_000
    /// 旅全体の地図とファイルの記録
    static let overheadEstimate: Int64 = 300_000

    static func estimate(stops: Int) -> Int64 {
        guard stops > 0 else { return 0 }
        return Int64(stops) * perStopEstimate + overheadEstimate
    }

    /// 置き場の中のファイルの大きさの合計（下の階層も数える）。読めないファイルは 0 として数える
    static func count(in directory: URL, fileManager: FileManager = .default) -> Int64 {
        guard let walker = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// 「24 MB」「4.2 MB」「1.3 GB」。**1000 で割る**（iOS の設定の「ストレージ」と同じ数え方）。
    /// 10 MB 未満は小数1桁、0.1 MB に届かないものは「0.1 MB 未満」（0 と言わない）
    static func label(_ bytes: Int64) -> String {
        let mb = Double(max(bytes, 0)) / 1_000_000
        if bytes <= 0 { return "0 MB" }
        if mb < 0.1 { return L("0.1 MB 未満", "< 0.1 MB") }
        if mb < 10 { return String(format: "%.1f MB", mb) }
        if mb < 1000 { return "\(Int(mb.rounded())) MB" }
        return String(format: "%.1f GB", mb / 1000)
    }
}

// MARK: - 文面

enum OfflineTripText {

    /// 「10月9日」（年は出さない・板の書き方）
    static func shortDate(ymd: String?) -> String? {
        guard let (_, m, d) = TakenDay.ymd(ymd ?? "") else { return nil }
        return L("\(m)月\(d)日", "\(englishMonth(m)) \(d)")
    }

    static func shortDate(_ date: Date, in zone: TimeZone = .current) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        let parts = c.dateComponents([.month, .day], from: date)
        let m = parts.month ?? 1, d = parts.day ?? 1
        return L("\(m)月\(d)日", "\(englishMonth(m)) \(d)")
    }

    private static func englishMonth(_ m: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names[min(max(m, 1), 12) - 1]
    }

    /// 保存済みの札・帯の小さい行「24 MB · 10月9日に保存」
    static func savedLine(bytes: Int64, savedAt: Date, zone: TimeZone = .current) -> String {
        L("\(OfflineTripBytes.label(bytes)) · \(shortDate(savedAt, in: zone))に保存",
          "\(OfflineTripBytes.label(bytes)) · Saved \(shortDate(savedAt, in: zone))")
    }

    /// 保存前の札の説明（板 72b-1）
    static func beforeBody(stops: Int) -> String {
        L("\(stops) か所の作例・光の時刻・メモと、周りの地図を画像で端末に保存します。圏外でも、どこで・いつ・何を撮るかを確かめられます。",
          "Saves examples, light times and notes for \(stops) \(stops == 1 ? "place" : "places"), plus map images, to this iPhone. Even with no signal, you can check where, when and what to shoot.")
    }

    /// 「約 24 MB · Wi‑Fi のあるところで保存すると安心です」
    static func estimateLine(stops: Int) -> String {
        L("約 \(OfflineTripBytes.label(OfflineTripBytes.estimate(stops: stops))) · Wi‑Fi のあるところで保存すると安心です",
          "About \(OfflineTripBytes.label(OfflineTripBytes.estimate(stops: stops))) · Best saved on Wi‑Fi")
    }

    /// 保存中の左「3 / 6 か所」
    static func progressPlaces(done: Int, total: Int) -> String {
        L("\(done) / \(total) か所", "\(done) / \(total) places")
    }

    /// 保存中の右「12 / 24 MB」。大きさの見込みを超えたら、見込みは数えた値に合わせる
    static func progressBytes(bytes: Int64, estimate: Int64) -> String {
        let total = max(bytes, estimate)
        return "\(OfflineTripBytes.label(bytes).replacingOccurrences(of: " MB", with: "")) / \(OfflineTripBytes.label(total))"
    }

    /// 読み上げ「6 か所のうち 3 か所」
    static func progressAccessibility(done: Int, total: Int) -> String {
        L("\(total) か所のうち \(done) か所", "\(done) of \(total) places")
    }

    /// 途中で止まった札の説明（owner 2026-10-09「続きから保存」）
    static func interruptedBody(done: Int, total: Int) -> String {
        L("\(total) か所のうち \(done) か所まで保存しました。電波のあるところで、続きから保存できます。",
          "Saved \(done) of \(total) places. You can continue saving where you have a signal.")
    }

    /// 保存したあとにプランが変わった（板 72b-4）。変わっていなければ nil
    static func staleMessage(_ change: OfflineTripPrint.Change) -> String? {
        switch change {
        case .none:
            return nil
        case .added(let n):
            return L("保存したあとに場所が \(n) か所増えました。増えた場所は、保存し直すまで圏外では出ません。",
                     "\(n) \(n == 1 ? "place was" : "places were") added after saving. They won't appear offline until you save again.")
        case .removed(let n):
            return L("保存したあとに場所が \(n) か所減りました。保存し直すまで、圏外では外した場所も出ます。",
                     "\(n) \(n == 1 ? "place was" : "places were") removed after saving. Offline, they'll still appear until you save again.")
        case .other:
            return L("保存したあとにプランが変わりました。保存し直すまで、圏外では保存したときの内容が出ます。",
                     "The trip changed after saving. Offline, you'll see the saved version until you save again.")
        }
    }

    /// 一覧（板 72e）の行の小さい行「12月24日〜25日 · 4 か所 · 24 MB · 10月9日に保存」
    static func savedRow(_ m: OfflineTripManifest, zone: TimeZone = .current) -> String {
        var parts: [String] = []
        if let range = dateRange(start: m.startDate, end: m.endDate, short: true) { parts.append(range) }
        parts.append(L("\(m.stopCount) か所", "\(m.stopCount) \(m.stopCount == 1 ? "place" : "places")"))
        parts.append(OfflineTripBytes.label(m.bytes))
        parts.append(L("\(shortDate(m.savedAt, in: zone))に保存", "Saved \(shortDate(m.savedAt, in: zone))"))
        return parts.joined(separator: " · ")
    }

    /// 日程の幅。`short` は「12月24日〜25日」（同じ月なら後ろの月を省く）、そうでなければ「2026年12月24日 〜 2026年12月25日」
    static func dateRange(start: String?, end: String?, short: Bool) -> String? {
        if short {
            guard let a = shortDate(ymd: start ?? end) else { return nil }
            guard let s = start, let e = end, s != e, let b = shortDate(ymd: e) else { return a }
            if let (_, m1, _) = TakenDay.ymd(s), let (_, m2, d2) = TakenDay.ymd(e), m1 == m2 {
                return L("\(a)〜\(d2)日", "\(a)–\(d2)")
            }
            return "\(a)〜\(b)"
        }
        guard let a = TakenDay.label(start ?? end) else { return nil }
        guard let s = start, let e = end, s != e, let b = TakenDay.label(e) else { return a }
        return "\(a) 〜 \(b)"
    }

    /// 設定の行「2 件 · 48 MB」
    static func settingsDetail(count: Int, bytes: Int64) -> String {
        L("\(count) 件 · \(OfflineTripBytes.label(bytes))", "\(count) \(count == 1 ? "trip" : "trips") · \(OfflineTripBytes.label(bytes))")
    }

    /// 圏外の帯（板 72c・72d）
    static var offlineBanner: String {
        L("電波がありません。保存した内容を出しています", "No signal. Showing what you saved.")
    }

    /// 電波があるときに「見え方を確かめる」で開いた画面の帯
    static var previewBanner: String {
        L("電波がないときは、この内容を出します", "This is what you'll see with no signal.")
    }

    /// 帯の2行目「10月9日に保存 · 電波が戻るまでプランは変えられません」
    static func bannerDetail(savedAt: Date, zone: TimeZone = .current) -> String {
        L("\(shortDate(savedAt, in: zone))に保存 · 電波が戻るまでプランは変えられません",
          "Saved \(shortDate(savedAt, in: zone)) · You can't edit the trip until you're back online")
    }

    /// 地図アプリで開くの下の注記（owner 2026-10-09: 圏外でも押せるまま、添えるだけ）
    static var mapsNote: String {
        L("電波が無いと開けないことがあります", "May not open without a signal")
    }

    /// 削除の確かめ（板 72b-5）
    static func deleteBody(bytes: Int64) -> String {
        L("旅行プランはそのまま残ります。\(OfflineTripBytes.label(bytes)) が空きます。電波のあるところで、いつでも保存し直せます。",
          "Your trip plan stays. This frees \(OfflineTripBytes.label(bytes)). You can save it again anytime you have a signal.")
    }

    /// 座標の1行「35.65858, 139.74543」（写すときも同じ文字）
    static func coordinates(_ c: Photo.Coords) -> String {
        String(format: "%.5f, %.5f", c.lat, c.lng)
    }

    /// 保存できなかった理由（電波が切れた・置き場が足りない・その他）
    enum Failure: Equatable { case offline, noSpace, notPro, unknown }

    static func failureMessage(_ f: Failure) -> String {
        switch f {
        case .offline:
            return L("電波が切れたため止めました。電波のあるところで、続きから保存できます。",
                     "Stopped because the connection was lost. You can continue where you have a signal.")
        case .noSpace:
            return L("iPhone の空きが足りないため保存できませんでした。", "Not enough free space on this iPhone.")
        case .notPro:
            return L("Pro かどうかを確かめられませんでした。電波のあるところでもう一度お試しください。",
                     "Couldn't confirm your Pro membership. Please try again with a signal.")
        case .unknown:
            return L("保存できませんでした。もう一度お試しください。", "Couldn't save. Please try again.")
        }
    }
}

// MARK: - 地図の画像の範囲

enum OfflineTripMap {

    /// 画像の大きさ（pt）。旅全体は板 72c の 358×196、場所ごとは板 72d の 358×104（2026-10-09 に足した）
    static let overviewSize = (width: 358.0, height: 196.0)
    static let stopSize = (width: 358.0, height: 104.0)
    /// 場所ごとの地図の幅（緯度の度・約 2.5 km）。座標は約1kmに丸めてあるので、それより狭くしない
    static let stopSpan = 0.025
    /// 旅全体の最小の幅（1か所だけ・近い場所だけの旅）
    static let minOverviewSpan = 0.05
    /// 点が縁で切れないように足す余白（幅に対する割合）
    static let padding = 0.35

    struct Region: Equatable {
        let lat: Double
        let lng: Double
        let latDelta: Double
        let lngDelta: Double
    }

    /// 座標を全部含む範囲。座標が無ければ nil。**経度 180° をまたぐ旅は考えない**（太平洋の島をまたぐ旅は稀）
    static func overview(_ coords: [Photo.Coords]) -> Region? {
        let valid = coords.filter { $0.lat.isFinite && $0.lng.isFinite && abs($0.lat) <= 90 && abs($0.lng) <= 180 }
        guard let first = valid.first else { return nil }
        var minLat = first.lat, maxLat = first.lat, minLng = first.lng, maxLng = first.lng
        for c in valid.dropFirst() {
            minLat = min(minLat, c.lat); maxLat = max(maxLat, c.lat)
            minLng = min(minLng, c.lng); maxLng = max(maxLng, c.lng)
        }
        let latDelta = min(max((maxLat - minLat) * (1 + padding * 2), minOverviewSpan), 170)
        let lngDelta = min(max((maxLng - minLng) * (1 + padding * 2), minOverviewSpan), 350)
        return Region(lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2, latDelta: latDelta, lngDelta: lngDelta)
    }

    /// 1か所の周り
    static func around(_ c: Photo.Coords) -> Region {
        Region(lat: c.lat, lng: c.lng, latDelta: stopSpan, lngDelta: stopSpan)
    }
}
