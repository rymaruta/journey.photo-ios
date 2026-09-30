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

    // 画面の文言は `NotificationText.line(for:)`（まとめ表示と一緒に決めるため）

    /// 押されたプッシュ通知の中身から、行き先を決めるための1件を作る。
    ///
    /// サーバーは中身の最上位に `type`・`photoId`・`byId`・`targetUserId` を入れて送る
    /// （`api-user/src/notify.ts` の `deliverPush`・`apns.ts` の `pushPayload`）。
    /// **お知らせの一覧と同じ復号を通す**——知らない種類は nil のまま（行き先なし）。
    /// 文字列でない値・`aps` は読まない。種類が無ければ nil（押しても一覧を開くだけ）
    static func fromPush(_ userInfo: [AnyHashable: Any]) -> AppNotification? {
        var fields: [String: String] = [:]
        for key in ["type", "photoId", "byId", "targetUserId"] {
            if let value = userInfo[key] as? String, !value.isEmpty { fields[key] = value }
        }
        guard fields["type"] != nil,
              let data = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
        return try? JSONDecoder().decode(AppNotification.self, from: data)
    }
}
