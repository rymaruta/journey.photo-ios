import Foundation

// Linux では URLSession が別モジュールに居る（`PublicGalleryService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの索引（`app/data/spots.json`）。
///
/// **API ではなく、静的サイトに置かれた JSON を読む。** Web の
/// `content/spots.json`（人が持つ台帳）から、Next のルートハンドラが
/// アプリ向けの薄い索引を書き出し、サイト直下に配る。写真の一覧
/// （`PublicGalleryService`）と同じ4段で読む:
///
///     控え（60秒） → 通信 → 圏外なら前回のぶん → 読めなければ前回のぶん
///
/// 違いは**取れなくても写真の機能を止めない**こと。本番は Web の変更が
/// `main` に入るまでこの URL が 404 で、そのあいだ地図はスポットのピンを
/// 出さないだけ——呼ぶ側（`PhotoMapViewModel`）は `try?` で受ける。
///
/// **404 だけは控えに落とさない。** 404 は「索引を下げた」なので、空を返して
/// 控えも消す（下げたものを圏外で出し続けない）。5xx（サーバーの都合）と
/// 圏外は控えがあればそれを出す。
///
/// **スポットのための API は足していない**（`AppConfig.publicSpotsURL` の注記）。
actor OfficialSpotService {

    private let url: URL
    private let session: URLSession
    private let snapshot: SpotSnapshotStore
    /// 索引の要求を出す**直前**に待つ口。**本番は nil**（何もしない）。
    /// 試験が「索引が遅い回」を作るのに使う（`PublicGalleryService` の
    /// `beforeLiveRequest` と同じ理由）
    private let beforeRequest: (@Sendable () async -> Void)?
    /// 取れた本文を使い回す長さ。**短く**（下書きに戻した・文を直した場所の古い本文を出し続けない）
    private let bodyLifetime: TimeInterval
    /// 「無い（404）」を覚える長さ。こちらは長くてよい（無いものを開くたびに叩かない）
    private let missingBodyLifetime: TimeInterval

    init(url: URL = AppConfig.publicSpotsURL,
         session: URLSession? = nil,
         snapshot: SpotSnapshotStore = SpotSnapshotStore(),
         beforeRequest: (@Sendable () async -> Void)? = nil,
         bodyLifetime: TimeInterval = OfficialSpotService.cacheLifetime,
         missingBodyLifetime: TimeInterval = OfficialSpotService.cacheLifetime * 10) {
        self.url = url
        self.snapshot = snapshot
        self.beforeRequest = beforeRequest
        self.bodyLifetime = bodyLifetime
        self.missingBodyLifetime = missingBodyLifetime
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            // 索引は `public, max-age=3600` で配られるが、端末側の控えは
            // 自分で持つ（`snapshot`）ので、URLSession には溜めさせない
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// 直前に取れた索引と、その時刻。**短い間だけ使い回す**
    /// （地図を開くたびに 1,400件を落とし直さない）
    private var cached: [OfficialSpot]?
    private var cachedAt: Date?
    static let cacheLifetime: TimeInterval = 60

    private var freshCache: [OfficialSpot]? {
        guard let cached, let cachedAt,
              Date().timeIntervalSince(cachedAt) < Self.cacheLifetime else { return nil }
        return cached
    }

    /// - Parameter force: 控えを無視して取り直す（引き下げ更新）。
    func fetchIndex(force: Bool = false) async throws -> [OfficialSpot] {
        if !force, let fresh = freshCache { return fresh }
        await beforeRequest?()
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            (data, response) = try await session.data(from: url)
        } catch {
            // **圏外なら前回のぶんを出す。** 出せなければそのとき初めて諦める
            if let cached = snapshot.load() { return cached }
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("HTTP 応答ではありません")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 {
                // 索引が無い＝下げた。古い控えを出さず、控えも消す。
                // 60秒は「無い」を覚える（地図を開くたびに叩き直さない）
                snapshot.clear()
                cached = []
                cachedAt = Date()
                return []
            }
            if let cached = snapshot.load() { return cached }
            throw APIError.server(status: http.statusCode, message: "")
        }
        // **200 の HTML は読もうとする前に退ける。** キャプティブポータル
        // （ホテル・空港の Wi-Fi）は JSON の要求にも 200 でログイン画面を返す。
        // 中身の復号で弾けることが多いが、種別が言っているなら先に信じる
        // ——控えに落とすと、次から圏外でその HTML が「索引」として出る
        if Self.isHTML(http) {
            print("[spots] 索引の応答が HTML でした（キャプティブポータルの可能性）")
            if let cached = snapshot.load() { return cached }
            throw APIError.decoding("索引の応答が HTML でした")
        }
        do {
            let list = try JSONDecoder.api.decode(LenientOfficialSpotList.self, from: data)
            if list.dropped > 0 {
                // 黙って捨てない。**どの行が出ていないのか**を追えるように
                print("[spots] 読めなかった・重複した索引の行を \(list.dropped) 件落としました")
            }
            let spots = list.spots
            // **読めたものだけを控える。** 1件も読めなかった回も控えない
            // ——前回の良い控えを空で上書きしない（本当に0件なら dropped も0）
            if !spots.isEmpty || list.dropped == 0 {
                snapshot.save(data)
            }
            cached = spots
            cachedAt = Date()
            return spots
        } catch {
            if let cached = snapshot.load() { return cached }
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - 本文（`/app/data/spots/<slug>.json`・2026-09-27）

    /// 取れた本文と、取れなかった（404）ことの控え。**開くたびに叩き直さない**
    private var bodies: [String: (body: SpotBody?, at: Date)] = [:]

    /// 撮影スポットの本文。索引の隣の `spots/<slug>.json`。
    ///
    /// **取れなければ nil**（まだ本番に無い 404・圏外・HTML・壊れた中身）。
    /// 画面は本文の節を出さないだけで、索引の内容はそのまま出す——投げない。
    /// 綴りが `[a-z0-9-]` でない slug は叩かない（パスに混ぜない）
    func fetchBody(slug: String) async -> SpotBody? {
        guard !slug.isEmpty, slug.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }) else {
            return nil
        }
        if let hit = bodies[slug],
           Date().timeIntervalSince(hit.at) < (hit.body == nil ? missingBodyLifetime : bodyLifetime) {
            return hit.body
        }
        let bodyURL = url.deletingLastPathComponent()
            .appendingPathComponent("spots")
            .appendingPathComponent("\(slug).json")
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            (data, response) = try await session.data(from: bodyURL)
        } catch {
            // 圏外は前回見た本文を出す（開き直すまでの間だけ・端末に書き残さない）
            return bodies[slug]?.body
        }
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode), !Self.isHTML(http) else {
            if http.statusCode == 404 {
                // 無い（下書きに戻した・まだ出ていない）。**古い本文を出さない**
                bodies[slug] = (nil, Date())
                return nil
            }
            return bodies[slug]?.body
        }
        guard let body = try? JSONDecoder.api.decode(SpotBody.self, from: data), body.slug == slug else {
            print("[spots] 本文が読めませんでした: \(slug)")
            // 読めない本文で前回のぶんを出し続けない
            bodies[slug] = nil
            return nil
        }
        bodies[slug] = (body, Date())
        return body
    }

    /// `Content-Type` が `text/html` か。鍵の大小は見ない（サーバーによって違う）
    private static func isHTML(_ response: HTTPURLResponse) -> Bool {
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, name.lowercased() == "content-type",
                  let type = value as? String else { continue }
            return type.lowercased().hasPrefix("text/html")
        }
        return false
    }
}
