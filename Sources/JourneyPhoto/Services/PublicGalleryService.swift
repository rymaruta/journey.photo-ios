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

    /// 公開範囲を絞った写真の取り方。**ログインしている間だけ入る**
    /// （`JourneyPhotoApp` が入れ替える）。
    ///
    /// ここに置く理由は `setHidden` と同じ——**出すところで足せば、
    /// 一覧・検索・地図・関連写真・お気に入りの全部に一度に効く**。
    /// 画面ごとに `restrictedFeed()` を呼んで回ると、必ずどこかが漏れる。
    private var restrictedLoader: (@Sendable () async throws -> [Photo])?

    func setRestrictedLoader(_ loader: (@Sendable () async throws -> [Photo])?) {
        restrictedLoader = loader
        // ログインし直した人に、前の人ぶんを見せない
        restrictedCache = nil
        restrictedCachedAt = nil
    }

    private var restrictedCache: [Photo]?
    private var restrictedCachedAt: Date?

    /// 絞られたぶんを取る。**失敗しても公開一覧は出す。**
    /// ここで投げると、絞った写真が1枚も無い大多数の人まで
    /// 「読み込めませんでした」になる。
    private func restrictedPhotos(force: Bool) async -> [Photo] {
        guard let restrictedLoader else { return [] }
        if !force, let restrictedCache, let restrictedCachedAt,
           Date().timeIntervalSince(restrictedCachedAt) < Self.cacheLifetime {
            return restrictedCache
        }
        let startedAt = Date()
        do {
            // **いまの数の時刻を付ける。** この口は DynamoDB から直に来るので
            // 数は新しい。付けないと、押した答え（`LikeCountStore`）が
            // 永久に勝ち、他の人のいいねが引き下げ更新でも出ない
            let photos = try await restrictedLoader().map { photo -> Photo in
                var stamped = photo
                stamped.likesAsOf = startedAt
                return stamped
            }
            restrictedCache = photos
            restrictedCachedAt = Date()
            return photos
        } catch {
            print("[gallery] 公開範囲を絞った写真を取れませんでした: \(error)")
            // 直前に取れていたぶんは出す（圏外で消える方が驚かれる）
            return restrictedCache ?? []
        }
    }

    /// いいねの**いまの数**を取る口（管理 API の `GET /photos`）。nil なら叩かない。
    ///
    /// **既定は nil。** 本物の口は `AppEnvironment` が `AppConfig.livePhotosURL`
    /// を渡す——既定に置くと、設定を入れていない試験がここで落ちる
    private let liveURL: URL?
    private var liveCounts: [String: Int]?
    /// `liveCounts` を**取りに行った時刻**（写した写真の `likesAsOf` になる）
    private var liveCountsAsOf: Date?
    /// 取りに行っている最中の要求。**同時に来た呼び出しはこれを待つ**
    /// （待たずに返すと、その画面だけ静的 JSON の古い数で出て、
    ///  控えの間は取り直さない）
    private var liveInFlight: Task<Void, Never>?
    /// **最後に取りに行った時刻**（取れたかどうかは問わない）。
    /// 取れた時刻で見ると、失敗した後は控えがある間も呼ぶたびに
    /// 叩き直し、一覧を最大 `liveTimeout` ずつ待たせる
    private var liveAttemptedAt: Date?

    /// いまの数を待つ上限。**一覧を出すのをこれ以上遅らせない**
    /// （Lambda の起き抜けは数秒かかる。間に合わなければ静的 JSON の数で出す）
    static let liveTimeout: TimeInterval = 4

    init(url: URL = AppConfig.publicPhotosURL,
         liveURL: URL? = nil,
         session: URLSession? = nil,
         snapshot: PhotoSnapshotStore = PhotoSnapshotStore()) {
        self.url = url
        self.liveURL = liveURL
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
        if !force, let fresh = freshCache {
            await refreshLiveCounts(force: false)
            return await merged(fresh, force: force)
        }
        // **いいねのいまの数は、一覧と同時に取りに行く**
        // （順に待つと、起き抜けの Lambda のぶん一覧が遅れる）
        async let live: Void = refreshLiveCounts(force: force)
        let photos = try await fetchStaticList()
        await live
        return await merged(photos, force: force)
    }

    /// 静的 JSON を取る。**圏外・壊れた応答なら前回の控え**。
    private func fetchStaticList() async throws -> [Photo] {
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
            if let cached = snapshot.load() { return cached }
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
            return photos
        } catch {
            if let cached = snapshot.load() { return cached }
            throw APIError.decoding(String(describing: error))
        }
    }

    /// 公開一覧に、絞られたぶんを足してから絞り込む。
    ///
    /// **`visible` は最後に通す**——ブロックした相手の「フォロワーのみ」の
    /// 写真も落とすため。サーバー側（`restrictedFeed.ts`）でも落としているが、
    /// 端末にしか無い「通報した写真」はここでしか落とせない。
    ///
    /// いいねの数は**ここで**いまの数に差し替える（`LiveLikes`）。
    /// 取れていなければ静的 JSON の数のまま。
    private func merged(_ photos: [Photo], force: Bool) async -> [Photo] {
        let counted = LiveLikes.apply(liveCounts ?? [:], asOf: liveCountsAsOf ?? .distantPast, to: photos)
        let extra = await restrictedPhotos(force: force)
        if extra.isEmpty { return visible(counted) }
        return visible(RestrictedFeed.merge(publicPhotos: counted, restricted: extra))
    }

    /// いいねのいまの数を取り直す。**失敗しても何も投げない**
    /// ——直前に取れた数か、静的 JSON の数のまま出す。
    private func refreshLiveCounts(force: Bool) async {
        guard let liveURL else { return }
        if let liveInFlight {
            await liveInFlight.value
            // **引き下げ更新は、途中の要求の結果で済ませない。**
            // 最大 `liveTimeout` 前に始まった要求で、失敗していることもある
            guard force else { return }
            // 待っている間に別の呼び出しが取り直し始めていたら、それを待つ
            if let restarted = self.liveInFlight {
                await restarted.value
                return
            }
        }
        if !force, let liveAttemptedAt,
           Date().timeIntervalSince(liveAttemptedAt) < Self.cacheLifetime {
            return
        }
        let startedAt = Date()
        liveAttemptedAt = startedAt
        // **呼んだ側の取り消しに巻き込まない**（巻き込まれると、控えの間は
        // 取り直さないので、別の画面まで古い数のままになる）
        let task = Task { await self.loadLiveCounts(from: liveURL, startedAt: startedAt) }
        liveInFlight = task
        await task.value
    }

    /// 🔴 **「取得中」の印は、ここ（要求の中）で消す。** 始めた呼び出し元が
    /// 戻ったときに消すと、待っていた引き下げ更新の方が先に再開した場合に
    /// **終わった要求**を「始め直された要求」と見分けられず、自分では
    /// 取りに行かずに返っていた（Swift は後から待った方を先に起こすらしく、
    /// 手元の再現では毎回そうなった）。印を立てるのは `refreshLiveCounts`
    /// で、この本体はそのあとにしか actor の上で走らないので、消すのは
    /// 必ずこの要求の印
    private func loadLiveCounts(from liveURL: URL, startedAt: Date) async {
        defer { liveInFlight = nil }
        var request = URLRequest(url: liveURL)
        request.timeoutInterval = Self.liveTimeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let counts = LiveLikes.counts(from: data) else { return }
            liveCounts = counts
            liveCountsAsOf = startedAt
        } catch {
            print("[gallery] いいねのいまの数を取れませんでした: \(error)")
        }
    }

    /// 公開 JSON には非公開の写真は載らないが、`published` が明示的に
    /// false の行が混ざっても出さない（二重の守り）。
    /// あわせて、ブロックした相手と、自分が通報した写真を落とす。
    private func visible(_ photos: [Photo]) -> [Photo] {
        BlockFilter.photos(photos.filter { $0.published != false },
                           blocked: hiddenUserIds, reported: hiddenPhotoIds)
    }
}
