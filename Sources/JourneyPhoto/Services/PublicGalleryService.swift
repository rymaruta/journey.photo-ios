import Foundation

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
    private let snapshot = PhotoSnapshotStore()

    init(url: URL = AppConfig.publicPhotosURL, session: URLSession? = nil) {
        self.url = url
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

    func fetchPhotos() async throws -> [Photo] {
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
            return visible(photos)
        } catch {
            if let cached = snapshot.load() { return visible(cached) }
            throw APIError.decoding(String(describing: error))
        }
    }

    /// 公開 JSON には非公開の写真は載らないが、`published` が明示的に
    /// false の行が混ざっても出さない（二重の守り）。
    private func visible(_ photos: [Photo]) -> [Photo] {
        photos.filter { $0.published != false }
    }
}
