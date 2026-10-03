import Foundation

/// 公開写真のページ（api-user の `GET /feed`・認証なし・2026-10-03 に本番へ出た口）。
///
/// `photos.json` と同じ項目の写真を**新しい順に決まった枚数ずつ**返す。
/// 非公開・ストーリー・公開範囲を絞った写真は入らない（絞ったぶんは
/// `PublicGalleryService.presentFeed` が `/feed/restricted` から重ねる）。
///
/// 契約（photo-gallery `docs/api-reference.md` の「公開写真のページ」）:
/// - `limit` は 1〜60（省くと 30、60 を超えると 60 に丸める。0 以下・数でない値は 400）
/// - `cursor` は前の応答の `nextCursor` を**そのまま**渡す。中身を読まない・作らない
/// - 🔴 **続きの有無は `nextCursor` だけで決める。** `items` が `limit` より少なくても、
///   空でも、`nextCursor` があれば続きがある
struct PublicFeedService: Sendable {

    /// 1回に読む枚数。サーバーの既定と同じ
    static let pageSize = 30

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 1ページ読む。`cursor` が nil なら先頭から
    func page(cursor: String?, limit: Int = PublicFeedService.pageSize) async throws -> FeedPage {
        var query = ["limit": String(min(max(limit, 1), 60))]
        if let cursor { query["cursor"] = cursor }
        return try await api.anonymous(.get, "/feed", query: query, as: FeedPage.self)
    }
}

/// `GET /feed` の答え。`{"items": Photo[], "nextCursor": string | null}`
struct FeedPage: Decodable, Equatable {
    let items: [Photo]
    /// nil なら最後のページ
    let nextCursor: String?

    init(items: [Photo], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    private enum CodingKeys: String, CodingKey { case items, nextCursor }

    /// **行は寛容に読む**（`photos.json` と同じ `LenientPhotoList`）。読めない行が1つ
    /// 混ざっただけでページごと捨てると、そこで一覧が止まる。`items` 自体が無い答えは壊れている
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode(LenientPhotoList.self, forKey: .items)
        if list.dropped > 0 {
            print("[feed] 読めなかった写真の行を \(list.dropped) 件落としました")
        }
        items = list.photos
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}
