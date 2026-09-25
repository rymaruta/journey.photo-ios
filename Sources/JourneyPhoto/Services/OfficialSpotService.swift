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

    init(url: URL = AppConfig.publicSpotsURL,
         session: URLSession? = nil,
         snapshot: SpotSnapshotStore = SpotSnapshotStore()) {
        self.url = url
        self.snapshot = snapshot
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
        let data: Data
        let response: URLResponse
        do {
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
                print("[spots] 読めなかった索引の行を \(list.dropped) 件落としました")
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
