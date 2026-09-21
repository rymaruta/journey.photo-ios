import Foundation

/// お知らせ（いいね・コメント・フォロー・ストーリー返信）。
struct NotificationService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    struct Page: Decodable {
        let items: [AppNotification]
        let unread: Int
    }

    func fetch() async throws -> Page {
        try await api.authorized(.get, "/user/notifications", as: Page.self)
    }

    /// 既読にする。**開いたときに1回だけ**呼ぶ。
    func markRead() async throws {
        try await api.authorizedVoid(.put, "/user/notifications")
    }
}

/// 1件のお知らせ。`api-user/src/notify.ts` の型に対応する。
///
/// **知らない種類は何も出さない**——サーバーが種類を足したときに、
/// 既定の文言で嘘を出すより、出さない方がまし（Web 側の
/// `NotificationsBell` と同じ判断）。
struct AppNotification: Decodable, Identifiable, Equatable {

    enum Kind: String, Decodable {
        case like, comment, follow, storyreply
    }

    /// 種類。未知の文字列は nil にする
    let kind: Kind?
    let photoId: String?
    let photoSrc: String?
    let byName: String?
    let byId: String?
    let atLocation: String?
    /// follow 通知は写真を伴わないため、リンク先のユーザーID を持つ
    let targetUserId: String?
    /// 作られた時刻（ISO8601）
    let t: String?
    let deleted: Bool?

    /// サーバーは id を持たない。並びは安定しているので、
    /// 時刻と相手と写真の組で区別する
    var id: String {
        [t ?? "", byId ?? "", photoId ?? "", kind?.rawValue ?? ""].joined(separator: "|")
    }

    private enum CodingKeys: String, CodingKey {
        case type, photoId, photoSrc, byName, byId, atLocation, targetUserId, t, deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decodeIfPresent(String.self, forKey: .type)
        self.kind = rawType.flatMap(Kind.init(rawValue:))
        self.photoId = try container.decodeIfPresent(String.self, forKey: .photoId)
        self.photoSrc = try container.decodeIfPresent(String.self, forKey: .photoSrc)
        self.byName = try container.decodeIfPresent(String.self, forKey: .byName)
        self.byId = try container.decodeIfPresent(String.self, forKey: .byId)
        self.atLocation = try container.decodeIfPresent(String.self, forKey: .atLocation)
        self.targetUserId = try container.decodeIfPresent(String.self, forKey: .targetUserId)
        self.t = try container.decodeIfPresent(String.self, forKey: .t)
        self.deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
    }

    /// 画面に出す1行。種類が分からないものは nil を返して**描かない**。
    var summary: String? {
        let who = (deleted == true) ? Labels.Common.deletedUser : (byName ?? L("だれか", "Someone"))
        switch kind {
        case .like: return L("\(who) さんがいいねしました", "\(who) liked your photo")
        case .comment: return L("\(who) さんがコメントしました", "\(who) commented")
        case .follow: return L("\(who) さんがフォローしました", "\(who) followed you")
        case .storyreply: return L("\(who) さんがストーリーに返信しました", "\(who) replied to your story")
        case .none: return nil
        }
    }
}
