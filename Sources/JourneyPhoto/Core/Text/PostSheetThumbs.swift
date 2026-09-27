import Foundation

/// 「投稿する」のシートの札に敷く写真（`PostSheet`）。
///
/// **その人自身が最近出した写真だけ。** 以前はサイト全体の新しい順の先頭
/// 2枚を敷いていて、ほかの人が開くと知らない人の写真が出ていた
/// （owner:「どうせならユーザー自身の写真にして欲しい」）。
///
/// - 公開しているものだけ（下書きは「まだ見せていない」写真）
/// - 新しい順（`createdAt` は ISO8601 なので文字列の順＝時刻の順。無い行は後ろ）
/// - 足りなければ足りないまま（**他人の写真で埋めない**。札は印だけの無地になる）
enum PostSheetThumbs {
    static func pick(fromMine photos: [Photo], count: Int = 2) -> [URL] {
        Array(photos
            .filter { $0.published != false }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .lazy
            .compactMap(\.gridImageURL)
            .prefix(count))
    }

    /// **開くたびに取りに行かない。** 下の「＋」を押すたびに `GET /user/photos`
    /// （Lambda 1回・全行の署名）が走っていた。同じ人なら `maxAge` の間は前の答えを使う。
    /// 人が替われば使わない（前の人の写真を次の人に見せない）
    struct Cache {
        private(set) var userId: String?
        private(set) var urls: [URL] = []
        private(set) var at: Date?
        static let maxAge: TimeInterval = 5 * 60

        func urls(for userId: String, now: Date = Date()) -> [URL]? {
            guard self.userId == userId, let at, now.timeIntervalSince(at) < Self.maxAge else { return nil }
            return urls
        }

        mutating func store(_ urls: [URL], for userId: String, now: Date = Date()) {
            self.userId = userId
            self.urls = urls
            self.at = now
        }
    }

    @MainActor static var cache = Cache()
}
