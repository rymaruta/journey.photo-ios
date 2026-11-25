import Foundation

/// **友達が、あなたの行きたい場所で撮った**（札 #710 の案9・2026-11-23 owner 承認）。
///
/// フォロー中の人の新しい公開の写真のうち、自分の「行きたい場所」で撮ったものを、ホームの上の札に1枚出す。
/// 写真の詳細には「あなたの行きたい場所です　話す ›」の1行を出す。
///
/// 2026-11-23 判断（案の頁の決まり）:
/// - 何度も出さない決まり5つ: (1) 札は同じ人と同じ場所の組で1回だけ (2) ホームに出すのは1日に1枚まで（いちばん新しい写真）
///   (3) 撮ってから（投稿してから）7日を過ぎた写真では出さない (4) ⋯ の「この知らせは出さない」で、その人の分は以後出さない
///   (5) 行きたい場所から外した場所では出さない。写真の詳細の1行は、行きたい場所と合う限りいつでも出す（数は増えない）
/// - プッシュとお知らせの一覧には入れない（お知らせはサーバーが作る物で、入れるにはサーバーの変更が要る）
/// - 相手には知らせない。出すのは相手が全体に公開している写真だけ
/// - 「話す」は今の写真を引用するメッセージの道（`DMPhotoSend`）。持ち主の写真へ連れて行くだけで、保存や書き出しの道は作らない
/// - 端末の中だけで突き合わせる（行きたい場所の鍵の当て方は `WishVisit` と同じ）。サーバー・DB は変えない
enum FriendWish {

    /// 札に出せる1枚
    struct Hit: Equatable {
        let photo: Photo
        /// 当たった行きたい場所の鍵
        let key: String
        /// 場所の名前（札の題）
        let place: String
        /// 写真の持ち主
        let ownerId: String

        /// 「同じ人と同じ場所」の組の鍵
        var pair: String { "\(ownerId)#\(key)" }
    }

    /// 撮ってから何日のあいだ札に出すか
    static let freshDays = 7

    /// 写真が当たる行きたい場所の鍵（無ければ nil）。**自分の写真・全体に公開でない写真は当てない**
    static func wishedKey(of photo: Photo, keys: Set<String>, spots: [OfficialSpot], me: String?) -> String? {
        guard !keys.isEmpty, let owner = owner(of: photo), owner != me, isPublic(photo) else { return nil }
        return WishVisit.visits(keys: keys, mine: [photo], spots: spots).keys.sorted().first
    }

    /// 札の候補（新しい順）。フォロー中の人の、7日以内の、全体に公開の写真で、行きたい場所に当たるもの
    static func hits(photos: [Photo], following: Set<String>, me: String?, keys: Set<String>,
                     spots: [OfficialSpot], muted: Set<String>, now: Date) -> [Hit] {
        guard !following.isEmpty, !keys.isEmpty else { return [] }
        let since = now.addingTimeInterval(-Double(freshDays) * 86_400)
        var out: [Hit] = []
        for photo in photos {
            guard let owner = owner(of: photo), following.contains(owner), !muted.contains(owner),
                  let created = date(photo.createdAt), created >= since, created <= now.addingTimeInterval(3600),
                  let key = wishedKey(of: photo, keys: keys, spots: spots, me: me) else { continue }
            out.append(Hit(photo: photo, key: key, place: WishVisit.name(of: key, photo: photo, spots: spots), ownerId: owner))
        }
        return out.sorted { ($0.photo.createdAt ?? "") > ($1.photo.createdAt ?? "") }
    }

    /// 今日の札（無ければ nil）。**状態は変えない**——出した印は `record` で付ける（同じ日のうちは同じ1枚を返す）
    static func pick(_ hits: [Hit], state: State, today: String) -> Hit? {
        if state.day == today {
            // 今日はもう1枚決めた（1日に1枚まで）。その写真がまだ当たっていれば同じ札、外れていれば出さない
            return hits.first { $0.photo.id == state.photoId }
        }
        let shown = Set(state.shownPairs)
        return hits.first { !shown.contains($0.pair) }
    }

    /// 出した印を付ける（同じ人と同じ場所の組・今日の1枚）
    static func record(_ hit: Hit, state: State, today: String) -> State {
        var next = state
        next.day = today
        next.photoId = hit.photo.id
        if !next.shownPairs.contains(hit.pair) { next.shownPairs.append(hit.pair) }
        next.shownPairs = Array(next.shownPairs.suffix(State.limit))
        return next
    }

    /// 「この知らせは出さない」: その人の分は以後出さない
    static func mute(_ ownerId: String, state: State) -> State {
        var next = state
        if !next.muted.contains(ownerId) { next.muted.append(ownerId) }
        return next
    }

    /// 端末に残す印（人ごと・`FriendWishMemory`）
    struct State: Codable, Equatable {
        /// 出した「人#場所」の組
        var shownPairs: [String] = []
        /// 「この知らせは出さない」を選んだ人
        var muted: [String] = []
        /// 札を決めた日（`YYYY-MM-DD`）と、その写真
        var day: String?
        var photoId: String?

        static let limit = 500
    }

    // MARK: - 言葉

    static var eyebrowLabel: String { L("行きたい場所", "Wish list") }
    static func takenBy(_ name: String) -> String { L("\(name) さんが撮りました", "Taken by \(name)") }
    static var yourPlace: String { L("あなたの行きたい場所です", "It's on your wish list") }
    static var talk: String { L("話す", "Message") }
    static var muteTitle: String { L("この知らせは出さない", "Don't show these") }
    /// 「話す」の言葉の候補（押すと欄に入るだけ。勝手に送らない・AI は使わない）
    static var suggestions: [String] {
        [L("ここ、ずっと行きたかった場所です！", "I've always wanted to go here!"),
         L("何時ごろに行きましたか？", "What time did you go?"),
         L("混んでいましたか？", "Was it crowded?")]
    }
    /// 候補のチップに出す短い字
    static var suggestionChips: [String] {
        [L("ずっと行きたかった場所です", "Always wanted to go"),
         L("何時ごろ行きましたか", "What time?"),
         L("混んでいましたか", "Crowded?")]
    }

    // MARK: - 下ごしらえ

    private static func owner(of photo: Photo) -> String? {
        let id = photo.userId ?? photo.uploadedBy
        guard let id, !id.isEmpty else { return nil }
        return id
    }

    /// 全体に公開の写真か（公開範囲が付いていない・非公開でない）
    private static func isPublic(_ photo: Photo) -> Bool {
        (photo.audience ?? "").isEmpty && photo.published != false
    }

    /// 読み手は1回だけ作って使い回す（写真ごとに作らない・2026-11-23 確かめ役の指摘）
    // 2026-11-25 判断（Swift 6）: ISO8601DateFormatter は Sendable と書かれていないが、Apple の文書で複数のスレッドから使ってよい。作った後は設定を変えないので `nonisolated(unsafe)` にする
    nonisolated(unsafe) static let plainFormatter = ISO8601DateFormatter()
    // 2026-11-25 判断（Swift 6）: ISO8601DateFormatter は Sendable と書かれていないが、Apple の文書で複数のスレッドから使ってよい。作った後は設定を変えないので `nonisolated(unsafe)` にする
    nonisolated(unsafe) static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let d = plainFormatter.date(from: raw) { return d }
        return fractionalFormatter.date(from: raw)
    }
}

/// 友達の行きたい場所の札の印の置き場（`UserDefaults`・人ごと・端末の中だけ）
final class FriendWishMemory {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ userId: String) -> String { "friendWish.v1.\(userId)" }

    func state(for userId: String?) -> FriendWish.State {
        guard let userId, let data = defaults.data(forKey: key(userId)),
              let state = try? JSONDecoder().decode(FriendWish.State.self, from: data) else { return .init() }
        return state
    }

    func save(_ state: FriendWish.State, for userId: String?) {
        guard let userId, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(userId))
    }

    func removeAll(for userId: String) {
        defaults.removeObject(forKey: key(userId))
    }
}
