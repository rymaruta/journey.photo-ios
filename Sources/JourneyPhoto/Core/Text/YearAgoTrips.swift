import Foundation

/// **②「去年の旅が届くみたいに」**（2026-11-12・札 #543・資料「画面デザインの案」第6章 段2）。
///
/// ストーリーの列の先頭（自分の輪の右・人の輪より前）に「1年前」の輪が出る。押すとストーリーのように
/// 去年の今日の旅が流れ、「ストーリーに出す」か「投稿にする」を1回押すだけ。押す回数は 口なし → 3回
/// （輪 → 出す → 作る画面の「ストーリーに送る」）。
///
/// **端末の中だけで済む。** 去年の旅は端末の写真の一冊（`DeviceTripShelfStore`・直近3年）から探し、
/// 見るのも端末の中。**人のストーリーの閲覧（`StoryViewerView`）は使わない**——あちらは「見た」を
/// サーバーへ知らせる作りなので、この輪は別の閲覧（`YearAgoStoryView`）で何も送らない。
/// **通知は使わない**（章の推奨・初版）
enum YearAgoTrips {

    /// 何年前まで遡るか。**端末の写真を読むのは直近3年**（`DeviceTrips.lookbackYears`）
    static var maxYears: Int { DeviceTrips.lookbackYears }
    /// 見せる写真の上限（その日の写真から・章「最大4枚」）
    static let photoLimit = 4
    /// 1枚を見せる秒数（章「1枚 4秒」）
    static let secondsPerPhoto: Double = 4
    /// ほこりが自然に晴れる秒数（飾り・なでないと見られない形にはしない）
    static let dustSeconds: Double = 0.6
    /// 右を叩くと次になる幅の割合（右 2/3）
    static let nextZone: Double = 2.0 / 3.0
    /// 下へ払って閉じる距離（pt）。人のストーリーの閉じ方（`StoryViewerView`）と同じ考えで、縦が横より大きいとき
    static let closeDistance: Double = 110

    /// 輪に出す1日
    struct Pick: Equatable {
        /// 何年前か（1〜3）
        let yearsAgo: Int
        let trip: LibraryTrip
        let day: LibraryTrip.Day
        /// 見せる写真（日時順・最大 `photoLimit` 枚）
        let photoIds: [String]
    }

    /// 今日の輪。**1年前の今日の旅が無ければ2年前、3年前**。どれも無ければ nil（輪を出さない）。
    ///
    /// - `trips`: 端末の写真から探した旅（`DeviceTripShelfStore.trips` を覚えた時間帯で切り直したもの）。
    ///   **家の近くの日常の写真は旅にならない**（`LibraryTrips.find` が 50km で落とす）ので出ない
    /// - 日は**撮った土地の暦**（`LibraryTrip.Day.key`）で、今日（端末の暦）の n 年前と同じ月日
    /// - 同じ日に旅が2つあれば、写真の多い方（並びが開くたびに変わらない）
    /// - 位置のある写真が無い日は出さない（`spreadPick` が選べない）
    static func find(trips: [LibraryTrip], now: Date, timeZone: TimeZone = .current) -> Pick? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for years in 1...max(1, maxYears) {
            guard let target = calendar.date(byAdding: .year, value: -years, to: now) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: target)
            let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let hits = trips.compactMap { trip -> (LibraryTrip, LibraryTrip.Day, [String])? in
                guard let day = trip.days.first(where: { $0.key == key }) else { return nil }
                let ids = photos(of: day, in: trip)
                return ids.isEmpty ? nil : (trip, day, ids)
            }
            guard let best = hits.max(by: { lhs, rhs in
                if lhs.1.shots.count != rhs.1.shots.count { return lhs.1.shots.count < rhs.1.shots.count }
                return lhs.0.id > rhs.0.id
            }) else { continue }
            return Pick(yearsAgo: years, trip: best.0, day: best.1, photoIds: best.2)
        }
        return nil
    }

    /// その日の写真から最大 `photoLimit` 枚（**今の自動の選び方**・`LibraryTrips.spreadPick` を1日だけの旅にかける）
    static func photos(of day: LibraryTrip.Day, in trip: LibraryTrip) -> [String] {
        guard let first = day.shots.first, let last = day.shots.last else { return [] }
        let oneDay = LibraryTrip(id: trip.id, shots: day.shots, start: first.date, end: last.date,
                                 days: [day], center: day.center, timeZone: trip.timeZone,
                                 zoneIsKnown: trip.zoneIsKnown)
        return LibraryTrips.spreadPick(oneDay, limit: photoLimit)
    }

    // MARK: - 字

    /// 輪の名前「1年前」
    static func ringName(_ years: Int) -> String {
        L("\(years)年前", years == 1 ? "1 year ago" : "\(years) years ago")
    }

    /// 閲覧の頭「1年前の今日」
    static func headline(_ years: Int) -> String {
        L("\(years)年前の今日", years == 1 ? "1 year ago today" : "\(years) years ago today")
    }

    /// 閲覧の題「竹富町 · 2025.11.11」。地名が無ければ日付だけ（圏外で引けていない）
    static func title(name: String?, day: LibraryTrip.Day, year: Int) -> String {
        let date = String(format: "%04d.%02d.%02d", year, day.month, day.day)
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return date }
        return "\(name) · \(date)"
    }

    /// 題の年（日の鍵の頭）
    static func year(of day: LibraryTrip.Day) -> Int {
        Int(day.key.prefix(4)) ?? 0
    }

    /// 題の下「3日の旅の2日目 · 端末の写真から4枚」（1日の旅なら「日帰りの旅 · …」）
    static func subtitle(trip: LibraryTrip, day: LibraryTrip.Day, count: Int) -> String {
        let days = LibraryTrips.calendarDays(trip)
        let head = days <= 1
            ? L("日帰りの旅", "A day trip")
            : L("\(days)日の旅の\(day.number)日目", "Day \(day.number) of a \(days)-day trip")
        return head + " · " + L("端末の写真から\(count)枚", count == 1 ? "1 photo on this iPhone" : "\(count) photos on this iPhone")
    }

    /// ストーリーの作る画面に最初から置く文字「1年前の今日 · 竹富町」（動かせる・消せる）
    static func storyText(years: Int, name: String?) -> String {
        let head = headline(years)
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return head }
        return "\(head) · \(name)"
    }

    /// 圏外の一言（写真の上のガラス）。**見るのは端末の中だけでできる**ので閲覧は止めない。送るのはあとで
    static func offlineNotice(offline: Bool) -> String? {
        offline ? L("通信できないので、送るのはあとで", "You're offline. You can share it later.") : nil
    }

    /// 本体が端末に無い写真（iCloud）を落としている間の字。**読めるまで進みを止める**
    static let loadingText = L("写真を読み込んでいます", "Loading photo")

    /// 進めてよいか（押さえていない・本体を読んでいない・今の1枚が読めた）
    static func canAdvance(held: Bool, sharing: Bool, loaded: Bool) -> Bool {
        !held && !sharing && loaded
    }

    // MARK: - 見方

    /// 叩いた位置で次へ進むか（右 2/3＝次、左 1/3＝前）
    static func tapGoesNext(x: Double, width: Double) -> Bool {
        guard width > 0 else { return true }
        return x >= width * (1 - nextZone)
    }

    /// 下へ払って閉じるか（縦が横より大きく、下へ `closeDistance` 以上）
    static func swipeCloses(dx: Double, dy: Double) -> Bool {
        dy >= closeDistance && abs(dy) > abs(dx)
    }

    // MARK: - 輪の状態

    /// 輪の見え方
    enum RingState: Equatable {
        /// 出さない（今日はもう出した・旅が無い）
        case hidden
        /// まだ見ていない（真鍮の輪）
        case unseen
        /// 見た（灰の細い輪・人の輪と同じ）
        case seen
    }

    /// 今日の輪の見え方。**見たら灰、その日のうちは残す。出したら消す**（同じ日に二重に出さない）。
    /// 日が変わると次の日の旅に替わる（印は日の鍵で持つ）
    static func ringState(pick: Pick?, todayKey: String, seenDay: String?, postedDay: String?) -> RingState {
        guard pick != nil, postedDay != todayKey else { return .hidden }
        return seenDay == todayKey ? .seen : .unseen
    }

    /// 端末の暦の今日の鍵（`YYYY-MM-DD`）
    static func todayKey(_ now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 「1年前」の輪を見た日・出した日（`UserDefaults`・人ごと・端末の中だけ）
final class YearAgoRingStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func seenKey(_ userId: String) -> String { "yearAgo.seenDay.\(userId)" }
    private func postedKey(_ userId: String) -> String { "yearAgo.postedDay.\(userId)" }

    func seenDay(for userId: String?) -> String? {
        userId.flatMap { defaults.string(forKey: seenKey($0)) }
    }

    func postedDay(for userId: String?) -> String? {
        userId.flatMap { defaults.string(forKey: postedKey($0)) }
    }

    func markSeen(_ day: String, for userId: String?) {
        guard let userId else { return }
        defaults.set(day, forKey: seenKey(userId))
    }

    func markPosted(_ day: String, for userId: String?) {
        guard let userId else { return }
        defaults.set(day, forKey: postedKey(userId))
    }
}
