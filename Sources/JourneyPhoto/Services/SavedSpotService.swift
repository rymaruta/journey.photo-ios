import Foundation

/// 「行きたい場所」のサーバーの口（`api-user/src/savedSpots.ts`・`spots#<uid>`）。
///
/// **本人だけの一覧。** 行 ID は JWT の `sub` からしか作らないので、
/// 誰の一覧かを渡す口は無い（他人の「行きたい」は読めない）。
///
/// 入るのは撮影地のスラッグ（`LocationSlug.make`＝Web の `slugify(_, "location")`）と
/// 台帳のスポットの鍵（`SPOT-<slug>`・`SavedSpotKey`）。どちらも Web の
/// `useSavedSpots` と同じ文字列なので、アプリで押した場所が Web の一覧にも並ぶ。
///
/// 🔴 **書き込みの失敗は失敗として返る**（サーバーは 500 / 503 を返す）。
/// いいねと違ってこの一覧が唯一の状態なので、飲み込むと画面だけが
/// 「行きたい」と言い続ける——呼び出し側（`WishlistSync`）が戻して知らせる。
struct SavedSpotService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// サーバーが**新しく**受け取る鍵の長さ（バイト）。`savedSpots.ts` の
    /// `MAX_SLUG_BYTES`＝`clampSlugBytes` と同じ 200
    static let maxKeyBytes = 200

    /// 送ってよい鍵か。**送れないものは端末にだけ残す**（`WishlistStore` の「未送信」）。
    ///
    ///  - 空・`#` を含む … サーバーが 400 で断る（行 ID の区切り）
    ///  - 200 バイトを超える … 同じく 400（今の `LocationSlug.make` は作らないが、
    ///    切り詰めを入れる前の端末には残っているかもしれない）
    ///  - `/` を含む … **パス片に置けない。** 外す口は `DELETE /user/spots/{slug}` で、
    ///    `%2F` を API Gateway がどう扱うかを確かめられない（`savedSpotKey.ts` が
    ///    `spot/` をやめたのと同じ理由）。`slugify` は `/` を `-` にするので正しい鍵には無い
    static func canSend(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("#") && !key.contains("/") && key.utf8.count <= maxKeyBytes
    }

    private struct List: Decodable { let slugs: [String] }

    /// 自分の「行きたい場所」（新しい順）
    func mySpots() async throws -> [String] {
        try await api.authorized(.get, "/user/spots", as: List.self).slugs
    }

    private struct SaveBody: Encodable { let slug: String }

    /// 足す（冪等・`POST /user/spots`）。応答はサーバーの一覧（新しい順）
    @discardableResult
    func save(_ key: String) async throws -> [String] {
        try await api.authorized(.post, "/user/spots", body: SaveBody(slug: key), as: List.self).slugs
    }

    /// 外す（冪等・`DELETE /user/spots/{slug}`）。応答はサーバーの一覧（新しい順）
    ///
    /// 🔴 **ここでは符号化しない。** `APIClient` は `appendingPathComponent` で
    /// パスを組み、そこで1回符号化される。ほかの口のように `addingPercentEncoding`
    /// を先に掛けると `パリ` が `%25E3%2583…` と**二重に**なり、サーバーは
    /// `%E3%83…` という別の鍵を外しにいく——200 が返るのに外れない
    /// （写真 ID・ユーザー ID は ASCII なので他の口では表に出ていない）
    @discardableResult
    func unsave(_ key: String) async throws -> [String] {
        try await api.authorized(.delete, "/user/spots/\(key)", as: List.self).slugs
    }
}
