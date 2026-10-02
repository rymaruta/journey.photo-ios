import Foundation

// Linux では URLSession が別モジュールに居る（`PublicGalleryService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 前回の応答の「版の印」（`ETag` と `Last-Modified`）。
///
/// **静的 JSON（`photos.json`・`spots.json`）を丸ごと落とし直さないため**（2026-10-02）。
/// 本番はどちらも `ETag`（弱い印 `W/"…"`）と `Last-Modified` を返し、
/// `If-None-Match`／`If-Modified-Since` を付けると中身が同じなら 304（本文なし）で返す
/// （curl で確かめた）。サイトは `no-store` なので URLSession の控えは使えない
/// ——印と中身は自分で持つ。
struct HTTPValidator: Codable, Equatable, Sendable {
    var etag: String?
    var lastModified: String?

    init(etag: String?, lastModified: String?) {
        self.etag = etag
        self.lastModified = lastModified
    }

    /// 応答から取る。**どちらも無ければ nil**（印の無い応答では条件付きにしない）
    init?(response: HTTPURLResponse) {
        let etag = Self.header("ETag", in: response)
        let lastModified = Self.header("Last-Modified", in: response)
        guard etag != nil || lastModified != nil else { return nil }
        self.init(etag: etag, lastModified: lastModified)
    }

    /// 要求に条件を付ける。**`ETag` があればそちらを優先**（両方付けると、
    /// サーバーは `If-None-Match` を見る——RFC 9110 の決まり。付けておいて害は無い）
    func apply(to request: inout URLRequest) {
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
    }

    /// 鍵の大小は見ない（サーバーによって違う。HTTP/2 は小文字）
    private static func header(_ name: String, in response: HTTPURLResponse) -> String? {
        let lowered = name.lowercased()
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, key.lowercased() == lowered,
                  let value = value as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

/// 端末に残した控え（`PhotoSnapshotStore`・`SpotSnapshotStore`）の隣に置く、版の印。
///
/// 🔴 **印は、控えの中身と同じ回のものでなければならない。** 違う回の印を送ると、
/// 304 で古い中身を「最新」として出し続ける。だから控えを書くときは
/// **印を先に消し → 中身を書き → 書けたときだけ印を書く**（`saveSnapshot`）。
/// 途中で落ちても「印が無い」側に倒れる（次は条件なしで取るだけ）。
struct ValidatorStore {

    private let url: URL

    /// - Parameter snapshotURL: 控えのファイル。印はその隣（`<名前>.validator`）
    init(snapshotURL: URL) {
        self.url = snapshotURL.appendingPathExtension("validator")
    }

    func load() -> HTTPValidator? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HTTPValidator.self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// 控えの中身と印を、**ずれない順で**書く。印が nil なら印は残さない
    func saveSnapshot(_ data: Data, to snapshotURL: URL, validator: HTTPValidator?) {
        clear()
        // 失敗しても何も言わない（控えが取れないだけで、本筋は動いている）
        guard (try? data.write(to: snapshotURL, options: .atomic)) != nil else { return }
        guard let validator, let encoded = try? JSONEncoder().encode(validator) else { return }
        try? encoded.write(to: url, options: .atomic)
    }
}

/// 条件付きの取得（`If-None-Match`／`If-Modified-Since`）。写真の一覧と
/// スポットの索引の2か所で使う。
///
/// - 控えに印があれば条件を付けて取る
/// - **304 なら控えの中身**（`unchanged`）を返す
/// - 304 なのに控えが無い・壊れている → 印を捨て、**条件なしで取り直す**
/// - それ以外の応答はそのまま返す（200 で中身と印を書くのは呼ぶ側——
///   「読めたものだけを控える」の判断が口ごとに違うため）
///
/// **URLSession に 304 を 200 へ差し替えさせない。** 条件の見出しは自分で付け、
/// 要求は `reloadIgnoringLocalCacheData`（端末の HTTP 控えを使わない）で出す
/// （`plainRequest`）。実機の URLSession で 304 がそのまま届くことは、
/// Linux の試験では確かめられない。
enum ConditionalGet {

    enum Outcome<Value: Sendable>: Sendable {
        /// 304。控えの中身
        case notModified(Value)
        /// 304 以外の応答（200・404・5xx…）。読むのは呼ぶ側
        case fetched(Data, URLResponse)
    }

    static func fetch<Value: Sendable>(
        _ url: URL,
        session: URLSession,
        validators: ValidatorStore,
        unchanged: @Sendable () async -> Value?
    ) async throws -> Outcome<Value> {
        if let validator = validators.load() {
            var request = plainRequest(url)
            validator.apply(to: &request)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 304 else {
                return .fetched(data, response)
            }
            if let value = await unchanged() { return .notModified(value) }
            // 印だけ残って中身が無い（消された・壊れた）。印を捨てて条件なしで取る
            print("[conditional] 304 でしたが控えが読めません。条件なしで取り直します: \(url.lastPathComponent)")
            validators.clear()
        }
        try RequestCancellation.throwIfCancelled()
        let (data, response) = try await session.data(for: plainRequest(url))
        return .fetched(data, response)
    }

    /// 🔴 **要求ごとに「端末の HTTP 控えを使わない」を付ける。** `URLRequest` の既定は
    /// `useProtocolCachePolicy` で、`URLSessionConfiguration.requestCachePolicy` が
    /// 要求の側に効くとは限らない。スポットの索引は `public, max-age=3600` で配られるので、
    /// 控えが効くと URLSession が古い 200 を返したり、304 を自分の控えで 200 に
    /// 差し替えたりする（印と中身は自分で持つので、それをさせない）
    private static func plainRequest(_ url: URL) -> URLRequest {
        URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    }
}
