import Foundation

// Linux では URLSession が別モジュールに居る。**iOS では何も起きない**が、
// これがないと Linux 上で `swift build` / `swift test` ができない
// （Xcode の無い環境で型検査できる唯一の層なので、そこを塞がない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 公開写真の一覧。
///
/// **API ではなく、静的サイトに置かれたスナップショットを読む。**
/// api-user に公開フィードの口が無いため（公開で叩けるのは
/// `/profile/{userId}`・`/users/search`・いいね数・コメント取得だけ）、
/// `scripts/deploy-static-site.js` がサイト直下に配っている
/// `app/data/photos.json` を取得する。
///
/// 割り切っている点:
/// - **最新とは限らない。** 反映はサイト再ビルド待ち（投稿時に
///   `repository_dispatch` が走るので通常は数分）
/// - **ページングが無い。** 30枚規模では丸ごと読んで問題ないが、
///   数百枚を超えたら api-user 側に `GET /feed` を足すこと
actor PublicGalleryService {

    private let url: URL
    private let session: URLSession
    private let snapshot: PhotoSnapshotStore

    /// 見せない相手と、見せない写真。
    ///
    /// **公開一覧は静的な JSON なので、サーバー側では絞れない。**
    /// `GET /stories` はブロックを両向きに落として返すが、`photos.json` は
    /// ビルド時に焼いた全員ぶん。ブロックした相手の写真がそのまま出ると、
    /// 「ブロックしたのに見える」になる（審査 1.2 で見られるところでもある）。
    /// だから**出すところで落とす**。
    private var hiddenUserIds: Set<String> = []
    private var hiddenPhotoIds: Set<String> = []

    func setHidden(userIds: Set<String>, photoIds: Set<String>) {
        hiddenUserIds = userIds
        hiddenPhotoIds = photoIds
    }

    init(url: URL = AppConfig.publicPhotosURL,
         session: URLSession? = nil,
         snapshot: PhotoSnapshotStore = PhotoSnapshotStore()) {
        self.url = url
        self.snapshot = snapshot
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            // 一覧 JSON はサイト側が no-store で配っている（HTML と同じ扱い）。
            // 端末側でも溜めない
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// 直前に取れた一覧と、その時刻。**短い間だけ使い回す。**
    ///
    /// この口は**画面を開くたびに全員が叩く**——一覧・検索・地図・
    /// お気に入り・タグ・お知らせ、そして写真を1枚開くたびに
    /// 「近い写真」（`RelatedPhotosRow`）まで。サイト側は一覧 JSON を
    /// `no-store` で配っている（HTML と同じ扱い）ので、**毎回まるごと
    /// 落とし直していた**。写真をぽんぽん開くだけで往復が積み上がる。
    ///
    /// 絞り込み（`visible`）は返すときに掛けるので、控えを使い回しても
    /// ブロックの反映は遅れない。
    private var cached: [Photo]?
    private var cachedAt: Date?
    static let cacheLifetime: TimeInterval = 60

    private var freshCache: [Photo]? {
        guard let cached, let cachedAt,
              Date().timeIntervalSince(cachedAt) < Self.cacheLifetime else { return nil }
        return cached
    }

    /// - Parameter force: 控えを無視して取り直す。**引き下げ更新はこちら**
    ///   ——利用者が自分で引いたのに古いものを出さない。
    func fetchPhotos(force: Bool = false) async throws -> [Photo] {
        if !force, let fresh = freshCache { return visible(fresh) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            // **圏外なら前回のぶんを出す。** 出せなければそのとき初めて諦める
            if let cached = snapshot.load() { return visible(cached) }
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("HTTP 応答ではありません")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let cached = snapshot.load() { return visible(cached) }
            throw APIError.server(status: http.statusCode, message: "")
        }
        do {
            let list = try JSONDecoder.api.decode(LenientPhotoList.self, from: data)
            if list.dropped > 0 {
                // 黙って捨てない。**どの写真が出ていないのか**を追えるように
                print("[gallery] 読めなかった写真の行を \(list.dropped) 件落としました")
            }
            let photos = list.photos
            // **読めたものだけを控える。** 壊れた応答（キャプティブポータルの
            // ログイン HTML など）を控えると、次から圏外でそれが出る。
            // 1件も読めなかった回も控えない——**前回の良い控えを空で上書き
            // しない**（写真が本当に0枚なら dropped も0なので控える）
            if !photos.isEmpty || list.dropped == 0 {
                snapshot.save(data)
            }
            cached = photos
            cachedAt = Date()
            return visible(photos)
        } catch {
            if let cached = snapshot.load() { return visible(cached) }
            throw APIError.decoding(String(describing: error))
        }
    }

    /// 公開 JSON には非公開の写真は載らないが、`published` が明示的に
    /// false の行が混ざっても出さない（二重の守り）。
    /// あわせて、ブロックした相手と、自分が通報した写真を落とす。
    private func visible(_ photos: [Photo]) -> [Photo] {
        photos.filter { photo in
            guard photo.published != false else { return false }
            guard !hiddenPhotoIds.contains(photo.id) else { return false }
            let owner = photo.userId ?? photo.uploadedBy
            guard let owner else { return true }
            return !hiddenUserIds.contains(owner)
        }
    }
}
