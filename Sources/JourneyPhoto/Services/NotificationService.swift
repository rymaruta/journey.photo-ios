import Foundation

/// お知らせ（いいね・コメント・フォロー・ストーリー返信・新しいメダル）。
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
        case like, comment, follow, storyreply, badge
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
    /// 新しいメダル（`badge`）の鍵と段。**自分の出来事**なので相手（`byId`）は持たない
    let key: String?
    let tier: Int?

    /// サーバーは id を持たない。並びは安定しているので、
    /// 時刻と相手と写真の組で区別する
    var id: String {
        var parts = [t ?? "", byId ?? "", photoId ?? "", kind?.rawValue ?? ""]
        // メダルは同じ時刻に2つ届きうる（段が2つ上がった・2種類同時）ので鍵と段でも分ける
        if let key { parts += [key, tier.map(String.init) ?? ""] }
        return parts.joined(separator: "|")
    }

    private enum CodingKeys: String, CodingKey {
        case type, photoId, photoSrc, byName, byId, atLocation, targetUserId, t, deleted, key, tier
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
        // 段は数でも数の文字列でも読む（プッシュの中身は文字にして通す・`fromPush`）。
        // 壊れていても行は落とさない
        let rawKey: String? = try? container.decodeIfPresent(String.self, forKey: .key)
        self.key = (rawKey?.isEmpty ?? true) ? nil : rawKey
        self.tier = LenientInt.read(container, .tier)
    }

    // 画面の文言は `NotificationText.line(for:)`（まとめ表示と一緒に決めるため）

    /// 押されたプッシュ通知の中身から、行き先を決めるための1件を作る。
    ///
    /// サーバーは中身の最上位に `type`・`photoId`・`byId`・`targetUserId`（メダルは `key`・`tier`）を入れて送る
    /// （`api-user/src/notify.ts` の `deliverPush`・`apns.ts` の `pushPayload`）。
    /// **お知らせの一覧と同じ復号を通す**——知らない種類は nil のまま（行き先なし）。
    /// 文字列でない値・`aps` は読まない。種類が無ければ nil（押しても一覧を開くだけ）
    static func fromPush(_ userInfo: [AnyHashable: Any]) -> AppNotification? {
        var fields: [String: String] = [:]
        for key in ["type", "photoId", "byId", "targetUserId", "key"] {
            if let value = userInfo[key] as? String, !value.isEmpty { fields[key] = value }
        }
        // 段は数で届くことがある（APNs の中身の JSON）。文字にして同じ復号に通す
        if let tier = userInfo["tier"] as? Int {
            fields["tier"] = String(tier)
        } else if let tier = userInfo["tier"] as? String, !tier.isEmpty {
            fields["tier"] = tier
        }
        guard fields["type"] != nil,
              let data = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
        return try? JSONDecoder().decode(AppNotification.self, from: data)
    }
}
