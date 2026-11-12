import Foundation

/// **①「フィルムを現像するみたいに」**（2026-11-12・札 #543・資料「画面デザインの案」第6章 段2）。
///
/// 旅から帰ったら、ホームの上の札に「現像前の旅」が1つ届く。押すと端末が選んだ10コマが
/// 色を抜いた札で1枚ずつ出て、**右へ払う＝載せる・左へ払う＝外す**。払い終えたら一冊の表紙で
/// 「投稿する」を押すだけ（5秒は取り消せる）。押す回数は 今 5回（＋ → 旅 → 格子 → 入れる → 投稿）→ 2回。
///
/// **端末の中だけで済む。** 旅は端末の写真の一冊（`DeviceTripShelfStore`・サーバーに送らない）から探し、
/// 払った結果も端末にだけ残す（`DevelopProgressStore`）。外へ出るのは最後の投稿だけ。
/// **通知は使わない**（章の推奨。端末の写真は前面にいる間だけ読む作りで、帰った瞬間に知らせる材料が無い）
enum DevelopTrips {

    /// 旅が終わってから何日のあいだ札を出すか（章の推奨値 7日・2026-11-12 判断）
    static let freshDays = 7
    /// 一度に払うコマの数。**今の「旅の写真からまとめて」の最初の選びと同じ10枚**（`UploadViewModel.maxSelection`）
    static let frameLimit = 10
    /// 「投稿する」を押してから送り出すまでの取り消しの間（秒・章「5秒の取り消す」）
    static let undoSeconds: Double = 5

    // MARK: - 札に出す旅

    /// ホームに出す「現像前の旅」。**いちばん新しく終わった旅だけを見る**（一冊の札 `HomeTopCard.bookReady` と同じ考え。
    /// 古い旅の札を後から出さない）。
    ///
    /// - `books`: 端末の写真の一冊の棚（`DeviceTripShelfStore.books`——**投稿した日がある旅はもう落ちている**）
    /// - 終わった: 最後の旅先の写真の日（端末の暦）が今日より前。2026-11-12 判断: 旅の最中の札にしない
    ///   ——同じ日のうちは、まだ撮るかもしれない
    /// - 終わってから `freshDays` 日以内
    /// - 札を閉じた旅（「この旅は出さない」・投稿した）は出さない（`closed`）
    /// - 端末が選ぶコマが2枚に届かない旅は出さない（一冊は2枚から・`LibraryTrips.canAddToTrips`）
    static func candidate(books: [LibraryTrip], now: Date, closed: Set<String>,
                          timeZone: TimeZone = .current) -> LibraryTrip? {
        guard let latest = books.max(by: { $0.end < $1.end }) else { return nil }
        let since = daysSince(latest.end, now: now, timeZone: timeZone)
        guard since >= 1, since <= freshDays, !closed.contains(latest.id),
              LibraryTrips.canAddToTrips(count: frames(of: latest).count) else { return nil }
        return latest
    }

    /// `date` の日から `now` の日まで何日か（端末の暦の日で数える）
    static func daysSince(_ date: Date, now: Date, timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: now)).day ?? 0
    }

    /// 払うコマ（旅の並び＝日時順の id）。**今の自動の選び方**（日ごとにばらける・`LibraryTrips.spreadPick`）
    static func frames(of trip: LibraryTrip) -> [String] {
        LibraryTrips.spreadPick(trip, limit: frameLimit)
    }

    /// 札の2行目「金沢の旅 · 3日 · 42枚」（地名が無ければ期間）
    static func cardLine(_ trip: LibraryTrip, name: String?) -> String {
        "\(DeviceTrips.title(of: trip, name: name)) · \(TripBook.daysLabel(LibraryTrips.calendarDays(trip)))"
            + " · " + PhotoMapViewModel.photoCountLabel(trip.shots.count)
    }

    // MARK: - 払う判定（章「払う判定」）

    /// 払った向き
    enum Decision: String, Codable, Equatable {
        /// 右へ払った＝載せる
        case keep
        /// 左へ払った＝外す
        case skip
    }

    /// 払ったと見なす横の距離（pt）。**今の札（`TripPickerView.swipeThreshold`）と同じ線**
    static let swipeDistance: Double = 110
    /// 勢いで払ったと見なす最小の距離（pt）
    static let flickDistance: Double = 30
    /// 勢いの速さ（pt/秒）。章の 0.6pt/ms
    static let flickSpeed: Double = 600
    /// 色が戻りきる距離（pt）。払った量 0 → 120pt で色 0 → 100%
    static let colorDistance: Double = 120

    /// 指を離したときの判定。足りなければ nil（札は元へ跳ね戻る）
    ///
    /// - Parameters:
    ///   - dx: 横の動き（右が正・pt）
    ///   - velocity: 離す直前の横の速さ（pt/秒・右が正）
    static func decide(dx: Double, velocity: Double) -> Decision? {
        if dx >= swipeDistance || (dx >= flickDistance && velocity >= flickSpeed) { return .keep }
        if dx <= -swipeDistance || (dx <= -flickDistance && velocity <= -flickSpeed) { return .skip }
        return nil
    }

    /// 払っている間に戻る色の量（0〜1）。**右へ払うときだけ戻る**（左は外すので色は戻らない）
    static func colorAmount(dx: Double) -> Double {
        max(0, min(1, dx / colorDistance))
    }

    // MARK: - 払い終えたあと

    /// 載せたコマ（旅の並び）
    static func kept(_ frames: [String], decisions: [String: Decision]) -> [String] {
        frames.filter { decisions[$0] == .keep }
    }

    /// 次に払うコマの位置（決めていない最初のコマ）。全部決めていれば `frames.count`
    static func nextIndex(_ frames: [String], decisions: [String: Decision]) -> Int {
        frames.firstIndex { decisions[$0] == nil } ?? frames.count
    }

    /// 投稿の並び。**表紙を先頭に、残りは旅の並び**（表紙は載せた1枚目がおまかせ・押せば替わる）
    static func uploadOrder(kept: [String], cover: String?) -> [String] {
        guard let cover, kept.contains(cover) else { return kept }
        return [cover] + kept.filter { $0 != cover }
    }

    /// 一番上の札の文字「4 / 10 · DAY 1 · 金沢市」（地名が無ければ「4 / 10 · DAY 1 · 9.12」）
    static func counter(index: Int, total: Int, day: LibraryTrip.Day?, place: String?) -> String {
        let head = "\(min(index + 1, total)) / \(total)"
        guard let day else { return head }
        if let place, !place.isEmpty { return "\(head) · DAY \(day.number) · \(place)" }
        return "\(head) · DAY \(day.number) · \(day.month).\(day.day)"
    }

    /// コマの写真の日（無ければ nil）
    static func day(of shotId: String, in trip: LibraryTrip) -> LibraryTrip.Day? {
        trip.days.first { day in day.shots.contains { $0.id == shotId } }
    }

    /// 表紙の眉「TRIP · 9.12 – 9.14」（1日なら「TRIP · 9.12」）。**旅の時間帯で出す**
    static func coverEyebrow(_ trip: LibraryTrip) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = trip.timeZone
        let a = calendar.dateComponents([.month, .day], from: trip.start)
        let b = calendar.dateComponents([.month, .day], from: trip.end)
        let head = "\(a.month ?? 0).\(a.day ?? 0)"
        let tail = "\(b.month ?? 0).\(b.day ?? 0)"
        return head == tail ? "TRIP · \(head)" : "TRIP · \(head) – \(tail)"
    }

    // MARK: - 状態の字（章「状態」・2026-11-12 札 #543）

    /// 札の3行目。**一部の写真だけ許可**のときだけ「選んで許可した写真の中から見つけました」（それ以外は出さない）
    static func cardDetail(limited: Bool) -> String? {
        limited ? L("選んで許可した写真の中から見つけました", "Found among the photos you allowed") : nil
    }

    /// 一部だけ許可した人の追加の口（今の「写真を選び直す」と同じ `DeviceTripShelfStore.addMorePhotos`）
    static let addMoreLabel = L("ほかの写真も選べるようにする", "Allow more photos")

    /// 表紙の画面の圏外の一言。**圏外のときだけ**。払うのは端末の中だけで最後までできるが、投稿は通信できる所で
    static func coverNotice(offline: Bool) -> String? {
        offline ? L("通信できないので、地名はあとで入ります。投稿は通信できる所で",
                    "You're offline. Place names will be added later. Post when you're connected.") : nil
    }

    /// 「投稿する」を押せるか（圏外では押せない・送る途中・取り消しの間も押せない）
    static func canPost(offline: Bool, undoShown: Bool, posting: Bool) -> Bool {
        !offline && !undoShown && !posting
    }

    /// 読めないコマを飛ばしたときの札（写真の上のガラス）。題と説明
    static let unreadableTitle = L("この写真は読み込めませんでした", "This photo couldn't be loaded")
    static let unreadableDetail = L("iCloud から落とせなかった写真は飛ばします",
                                    "Photos that couldn't be downloaded from iCloud are skipped")
    /// 読めないコマの札を出しておく秒数（そのあとは下の一行だけ残す）
    static let unreadableNoticeSeconds: Double = 2.5

    /// 取り消しの札の字「8枚の旅を投稿します」
    static func postingNotice(count: Int) -> String {
        L("\(count)枚の旅を投稿します", count == 1 ? "Posting 1 photo" : "Posting \(count) photos")
    }
}

/// 払った結果（端末の中だけ・サーバーに送らない）。**途中で閉じても、次は続きのコマから**（章「途中で閉じた」）
struct DevelopProgress: Codable, Equatable {
    /// コマの id → 払った向き
    var decisions: [String: DevelopTrips.Decision] = [:]
    /// 表紙に選んだコマ（無ければ載せた1枚目）
    var cover: String?
    /// 札を閉じた（「この旅は出さない」・投稿した）。**二度と出さない**
    var closed = false
    /// 最後に触った時刻（古い控えを消す）
    var updatedAt: Date
}

/// 払った結果の置き場（`UserDefaults`・人ごと）。鍵は旅の id
final class DevelopProgressStore {

    /// 控えを残す日数。札は7日で消えるので、それより長く持たない（30日で消す）
    static let keepDays = 30

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ userId: String) -> String { "develop.progress.v1.\(userId)" }

    func all(for userId: String?) -> [String: DevelopProgress] {
        guard let userId, let data = defaults.data(forKey: key(userId)),
              let decoded = try? JSONDecoder().decode([String: DevelopProgress].self, from: data) else { return [:] }
        return decoded
    }

    func progress(_ tripId: String, for userId: String?) -> DevelopProgress? {
        all(for: userId)[tripId]
    }

    /// 閉じた旅（札に出さない）
    func closed(for userId: String?) -> Set<String> {
        Set(all(for: userId).filter { $0.value.closed }.map(\.key))
    }

    func save(_ progress: DevelopProgress, trip tripId: String, for userId: String?, now: Date = Date()) {
        guard let userId else { return }
        var entries = all(for: userId)
        var stamped = progress
        stamped.updatedAt = now
        entries[tripId] = stamped
        // 古い控えは消す（札は7日で消えるので、端末に溜めない）
        let limit = now.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        entries = entries.filter { $0.value.updatedAt >= limit }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key(userId)) }
    }

    /// 札を閉じる（「この旅は出さない」・投稿した）
    func close(_ tripId: String, for userId: String?, now: Date = Date()) {
        var current = progress(tripId, for: userId) ?? DevelopProgress(updatedAt: now)
        current.closed = true
        save(current, trip: tripId, for: userId, now: now)
    }

    /// 閉じた印を外す（投稿を取り消した）
    func reopen(_ tripId: String, for userId: String?, now: Date = Date()) {
        guard var current = progress(tripId, for: userId) else { return }
        current.closed = false
        save(current, trip: tripId, for: userId, now: now)
    }

    /// 消す（サインアウト）
    func removeAll(for userId: String) {
        defaults.removeObject(forKey: key(userId))
    }
}
