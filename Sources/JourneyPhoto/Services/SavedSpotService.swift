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
        canRemove(key) && key.utf8.count <= maxKeyBytes
    }

    /// 外す要求に載せてよい鍵。**長さは見ない**——サーバーは外すときに長さを見ない
    /// （昔の長い鍵も外せるように・`savedSpots.ts` の `isStoredSpotSlug`）。ここで
    /// 弾くと、サーバーにある長い鍵をアプリから外せず、次の同期で戻ってきた。
    /// `.` と `..` はパスで畳まれて別の口（`DELETE /user`）に届くので弾く
    static func canRemove(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("#") && !key.contains("/") && key != "." && key != ".."
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
    /// 🔴 **鍵は `pathSegment` で1つの区切りに収める。** 以前は符号化せずにそのまま
    /// 道に入れていたので、`/` や `..` を含む鍵が道の区切りとして読まれ、別の口を
    /// 叩きえた。日本語の地名はそのまま通す（`APIClient` が符号化し直さない）
    @discardableResult
    func unsave(_ key: String) async throws -> [String] {
        let slug = try Self.pathSegment(key)
        return try await api.authorized(.delete, "/user/spots/\(slug)", as: List.self).slugs
    }

    /// 行きたい場所の鍵を、道の1区切りとして符号化する。`/`・`?`・`#`・`%` も符号化し、
    /// 日本語は UTF-8 の `%XX` にする（サーバーは1回だけ戻す）。
    /// **空と、点だけの鍵（`.`・`..`）は要求を出さずに失敗にする**——符号化しても
    /// 道の正規化で親へ上がりうる
    static func pathSegment(_ key: String) throws -> String {
        guard !key.isEmpty, !key.allSatisfy({ $0 == "." }) else { throw APIError.invalidIdentifier }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw APIError.invalidIdentifier
        }
        return encoded
    }
}
