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
/// - **ページングが無い。** 全件が要る画面（おすすめ・カテゴリ・タグ・検索・地図など）は
///   今もこちら。ホームの「新着」は `GET /feed` のページ読み（`PublicFeedService`・
///   2026-10-03）に移した。仕上げ（限定公開・ブロック）は `presentFeed` が同じ道で掛ける
actor PublicGalleryService {

    private let url: URL
    private let session: URLSession
    private let snapshot: PhotoSnapshotStore

    /// 自分で編集して保存した写真の新しい行（`PhotoEditLedger`）。**出すところで重ねる**
    /// ——一覧は建て直しまで古い静的 JSON なので、重ねないとホーム・探す・地図から
    /// 開き直した写真が編集前に戻って見えた。詳細の画面も同じ控えを引く（主スレッドから
    /// 同期で読むので actor の外に置く）
    nonisolated let edits: PhotoEditLedger

    /// 見せない相手と、見せない写真。
    ///
    /// **公開一覧は静的な JSON なので、サーバー側では絞れない。**
    /// `GET /stories` はブロックを両向きに落として返すが、`photos.json` は
    /// ビルド時に焼いた全員ぶん。ブロックした相手の写真がそのまま出ると、
    /// 「ブロックしたのに見える」になる（審査 1.2 で見られるところでもある）。
    /// だから**出すところで落とす**。
    ///
    /// 自分で消した・非公開にした写真（`ModerationSnapshot.gone`）も同じ道で落とす
    /// ——この JSON は建て直しまで古く、控え（`cached`・`snapshot`）も残るので、
    /// 消した写真が一覧に出続け、押すと 404 の写真が開いていた。
    private var hiding = ModerationSnapshot()

    /// **写しを丸ごと受け取る。** 集合を1つずつ渡す形だと、足した集合（`gone`）を
    /// 渡し忘れた呼び出しが、黙って空で上書きする
    func setHidden(_ hiding: ModerationSnapshot) {
        self.hiding = hiding
    }

    /// 公開範囲を絞った写真の取り方。**ログインしている間だけ入る**
    /// （`JourneyPhotoApp` が入れ替える）。
    ///
    /// ここに置く理由は `setHidden` と同じ——**出すところで足せば、
    /// 一覧・検索・地図・近くの写真・お気に入りの全部に一度に効く**。
    /// 画面ごとに `restrictedFeed()` を呼んで回ると、必ずどこかが漏れる。
    private var restrictedLoader: (@Sendable () async throws -> [Photo])?

    func setRestrictedLoader(_ loader: (@Sendable () async throws -> [Photo])?) {
        // 🔴 **前の人が編集した写真の控えを、口の差し替えと同じ手番で捨てる。**
        // 差し替えの後（画面の側）で捨てていた頃は、その間に始まった読み直しが
        // `merged` まで進むと、前の人の編集後の姿が次の人の一覧に重なった。
        // ここ（actor の上）で捨てれば、この後の `merged` は必ず空の控えで重ねる
        edits.clear()
        restrictedLoader = loader
        // ログインし直した人に、前の人ぶんを見せない
        restrictedCache = nil
        restrictedCachedAt = nil
        restrictedEpoch += 1
        for watcher in epochWatchers.values { watcher.yield(restrictedEpoch) }
    }

    /// 読み出し口を入れ替えた回数。**手元に一覧を持ち続ける画面が、
    /// 前の人の読み出し口で読んだ一覧を持ったままか**を見分けるのに使う
    private(set) var restrictedEpoch = 0
    private var epochWatchers: [UUID: AsyncStream<Int>.Continuation] = [:]

    /// 読み出し口が入れ替わるたびに、その回数を流す。**今の回数から始める**
    /// ——画面を開き直したときに、離れていた間の入れ替えを取りこぼさない。
    ///
    /// 探すは一度読んだら読み直さない作りで、ログアウトや別の人のログインの
    /// あとも、前の人の「フォロワーのみ」「親しい友達」の写真が残っていた。
    /// 入れ替えた**後**に流すので、読み直しが前の人の読み出し口を通らない
    func restrictedChanges() -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        let id = UUID()
        epochWatchers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeWatcher(id) }
        }
        continuation.yield(restrictedEpoch)
        return stream
    }

    private func removeWatcher(_ id: UUID) {
        epochWatchers[id] = nil
    }

    private var restrictedCache: [Photo]?
    private var restrictedCachedAt: Date?

    /// 絞られたぶんを取る。**失敗しても公開一覧は出す。**
    /// ここで投げると、絞った写真が1枚も無い大多数の人まで
    /// 「読み込めませんでした」になる。
    /// - Returns: 写真と、**それを読んだ読み出し口の回**（`restrictedEpoch`）。
    ///   回は返す直前に確かめた値——読んでいる間に替わったら今の口で読み直すので、
    ///   返る回は中身と必ず揃う。呼ぶ側はこれで「誰の一覧か」を見分ける
    private func restrictedPhotos(force: Bool) async -> (photos: [Photo], epoch: Int) {
        guard let restrictedLoader else { return ([], restrictedEpoch) }
        if !force, let restrictedCache, let restrictedCachedAt,
           Date().timeIntervalSince(restrictedCachedAt) < Self.cacheLifetime {
            return (restrictedCache, restrictedEpoch)
        }
        let startedAt = Date()
        let epoch = restrictedEpoch
        // **catch の中で await しない**（Xcode 26.3 の SILGen が落ちた形に近い）。
        // 結果を外へ持ち出してから分ける
        let loaded: Result<[Photo], Error>
        do {
            loaded = .success(try await restrictedLoader())
        } catch {
            loaded = .failure(error)
        }
        switch loaded {
        case .success(let raw):
            // **いまの数の時刻を付ける。** この口は DynamoDB から直に来るので
            // 数は新しい。付けないと、押した答え（`LikeCountStore`）が
            // 永久に勝ち、他の人のいいねが引き下げ更新でも出ない
            let photos = raw.map { photo -> Photo in
                var stamped = photo
                stamped.likesAsOf = startedAt
                return stamped
            }
            // 🔴 **読んでいる間に読み出し口が替わったら、控えに書かない。**
            // 書くと、ログアウトした後に前の人ぶんが60秒出続ける。
            // 空で返しもしない——返した一覧を持ち続ける画面（ホーム）で、
            // 次の読み直しまで限定公開の写真が欠けたままになる。今の口で読み直す
            guard epoch == restrictedEpoch else { return await restrictedPhotos(force: true) }
            restrictedCache = photos
            restrictedCachedAt = Date()
            return (photos, epoch)
        case .failure(let error):
            print("[gallery] 公開範囲を絞った写真を取れませんでした: \(error)")
            // 直前に取れていたぶんは出す（圏外で消える方が驚かれる）
            guard epoch == restrictedEpoch else { return await restrictedPhotos(force: true) }
            return (restrictedCache ?? [], epoch)
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

    /// いまの数の要求を出す**直前**に待つ口。**本番は nil**（何もしない）。
    /// 試験が「取りに行っている最中」を作るのに使う——遅さを `URLProtocol`
    /// の応答で作ると、Linux の Foundation では別スレッドから `client` を
    /// 叩いてまれに落ちる
    private let beforeLiveRequest: (@Sendable () async -> Void)?

    /// 一覧の要求を出す**直前**に待つ口。**本番は nil**。試験が「取りに行っている最中」を
    /// 作るのに使う（`beforeLiveRequest` と同じ理由で、遅さを `URLProtocol` で作らない）
    private let beforeStaticRequest: (@Sendable () async -> Void)?

    init(url: URL = AppConfig.publicPhotosURL,
         liveURL: URL? = nil,
         session: URLSession? = nil,
         snapshot: PhotoSnapshotStore = PhotoSnapshotStore(),
         edits: PhotoEditLedger = PhotoEditLedger(),
         beforeLiveRequest: (@Sendable () async -> Void)? = nil,
         beforeStaticRequest: (@Sendable () async -> Void)? = nil) {
        self.url = url
        self.beforeStaticRequest = beforeStaticRequest
        self.edits = edits
        self.liveURL = liveURL
        self.snapshot = snapshot
        self.beforeLiveRequest = beforeLiveRequest
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
    /// 「この近くで撮られた写真」（`PhotoDetailView`）まで。サイト側は一覧 JSON を
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
        try await fetchPhotosTagged(force: force).photos
    }

    /// `fetchPhotos` と同じ。**どの読み出し口の回で作った一覧か**も返す。
    /// 手元に一覧を持ち続ける画面が、人の切り替えの前に読んだ一覧を
    /// 切り替えの後に書き込まないために使う（探す）
    func fetchPhotosTagged(force: Bool = false) async throws -> (photos: [Photo], epoch: Int) {
        if !force, let fresh = freshCache {
            await refreshLiveCounts(force: false)
            return await merged(fresh, force: force)
        }
        // **いいねのいまの数は、一覧と同時に取りに行く**
        // （順に待つと、起き抜けの Lambda のぶん一覧が遅れる）
        async let live: Void = refreshLiveCounts(force: force)
        let photos = try await fetchStaticList(force: force)
        await live
        return await merged(photos, force: force)
    }

    /// 静的 JSON を取る。**圏外・壊れた応答なら前回の控え**。
    ///
    /// **条件付きで取る**（`ConditionalGet`・2026-10-02）。控えに前回の `ETag` が
    /// あれば `If-None-Match` を付け、変わっていなければ 304（本文なし）で
    /// 控えの中身を使う。60秒の控え（`freshCache`）の判断はその手前のまま
    ///
    /// **同時の取得は1本にまとめる**（docs/QUALITY_2026-10-03.md の P2）。起動直後はホーム・探す・
    /// 地図・お知らせが同じ一覧を同時に取りに来て、同じ JSON を何本も落としていた。
    ///
    /// 2026-10-07 判断: 前回まとめなかったのは「取り消しの挙動が変わる」ため——呼び手の
    /// `Task` の中で取ると、最初の呼び手（たとえば閉じた画面）が取り消されたとき、相乗りした
    /// ほかの呼び手の取得まで止まる。だから取得は**どの呼び手にも属さない `Task`** で走らせ
    /// （いいねの数の `liveInFlight` と同じ）、呼び手は `valueReleasingOnCancel` で待つ。
    /// 取り消された呼び手は**待ちだけ**を外し、今までどおり端末の控え（無ければ unreachable）で
    /// 戻る。取得は続き、ほかの呼び手と `cached` に届く。
    /// 引き下げ更新（`force`）は途中の取得に相乗りしない——引く前に始まった取得で済ませない
    /// （`refreshLiveCounts` と同じ約束）。新しい取得を始め、以後の呼び手はそちらに乗る
    ///
    /// **もう取り消されている呼び手は、新しい取得を始めない**（`RequestCancellation` の約束・
    /// `testCancelledGalleryFetchDoesNotReachTheNetwork`）。取得はどの呼び手にも属さないので、
    /// 始めてしまうと誰も待たない要求が出る。途中の取得に乗るのは構わない（もう出ている）
    private func fetchStaticList(force: Bool) async throws -> [Photo] {
        let task: Task<[Photo], Error>
        if !force, let inFlight = staticInFlight {
            task = inFlight.task
        } else {
            guard !Task.isCancelled else { return try cancelledStaticList() }
            let id = UUID()
            task = Task { try await self.loadStaticList(id: id) }
            staticInFlight = (id, task)
        }
        do {
            return try await task.valueReleasingOnCancel()
        } catch is CancellationError {
            // 待っていた側が取り消された（取得は続いている）
            return try cancelledStaticList()
        }
    }

    /// 取り消された呼び手の戻り方。**まとめる前と同じ**——圏外と同じ道（端末の控え、無ければ unreachable）
    private func cancelledStaticList() throws -> [Photo] {
        if let cached = snapshot.load() { return cached }
        throw APIError.unreachable
    }

    /// 取りに行っている最中の一覧。**同時に来た呼び出しはこれを待つ**（`fetchStaticList`）
    private var staticInFlight: (id: UUID, task: Task<[Photo], Error>)?

    /// 一覧を1回取る本体。**「取得中」の印はここで消す**——自分の印のときだけ
    /// （引き下げ更新が後から始めた取得の印を、先に終わった古い取得が消さない）。
    /// 印を立てるのは `fetchStaticList` で、この本体はそのあとにしか actor の上で走らない
    private func loadStaticList(id: UUID) async throws -> [Photo] {
        defer { if staticInFlight?.id == id { staticInFlight = nil } }
        await beforeStaticRequest?()
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            // 304 のときは**端末の控え**を読む。手元の一覧（`cached`）は使わない
            // ——このサービスは画面ごとに別に作られることがあり（`GalleryViewModel` の既定）、
            // 印と控えのファイルは共有なので、別の口が新しい回を書いた後に
            // 自分の古い一覧を「変わっていない」として出してしまう
            let snapshot = self.snapshot
            let outcome = try await ConditionalGet.fetch(url, session: session, validators: snapshot.validators) {
                snapshot.load()
            }
            switch outcome {
            case .notModified(let photos):
                cached = photos
                cachedAt = Date()
                return photos
            case .fetched(let body, let reply):
                (data, response) = (body, reply)
            }
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
                snapshot.save(data, validator: HTTPValidator(response: http))
            } else {
                // 控えていない中身の印を残さない（前の回の印で 304 を受けると、
                // 今回とは違う控えを「変わっていない」として出す）
                snapshot.validators.clear()
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
    ///
    /// **自分で編集した写真は編集後の行を重ねる**（`edits`）。限定の行を足した**後**に重ねる
    /// ——限定の行は今の行なので、たいてい追いついていて控えが捨てられる。
    /// `visible` より前に重ねる（編集で非公開にした写真を落とすため）
    private func merged(_ photos: [Photo], force: Bool) async -> (photos: [Photo], epoch: Int) {
        let counted = LiveLikes.apply(liveCounts ?? [:], asOf: liveCountsAsOf ?? .distantPast, to: photos)
        let (extra, epoch) = await restrictedPhotos(force: force)
        if extra.isEmpty { return (visible(edits.apply(to: counted)), epoch) }
        return (visible(edits.apply(to: RestrictedFeed.merge(publicPhotos: counted, restricted: extra))), epoch)
    }

    /// **ページで読んだ公開写真**（`GET /feed`・`PublicFeedService`）を、`merged` と同じ
    /// 仕上げで出せる形にする（2026-10-03）。
    ///
    /// いいねのいまの数・絞ったぶん（読んだ範囲だけ・`RestrictedFeed.mergeLoaded`）・
    /// 自分の編集・ブロックと消した写真の絞り（`visible`）を、`merged` と同じ順で通す。
    /// **`/feed` は今の行を返すが、端末にしか無い「通報した写真」はここでしか落とせない**。
    /// 通信はしない（絞ったぶんは控えが古ければ読み直す）
    ///
    /// - Parameter loadsRestricted: false なら限定公開は**手元の控えだけ**で重ねる（読みに行かない）。
    ///   全件（`fetchPhotos`）と同時に走る1ページ目で使う——両方が読みに行くと、起動時に
    ///   `/feed/restricted` を2度読む。全件が読み終えたら呼ぶ側が掛け直す
    func presentFeed(_ raw: [Photo], reachedEnd: Bool, loadsRestricted: Bool = true) async -> [Photo] {
        let counted = LiveLikes.apply(liveCounts ?? [:], asOf: liveCountsAsOf ?? .distantPast, to: raw)
        let extra: [Photo]
        if loadsRestricted {
            extra = await restrictedPhotos(force: false).photos
        } else {
            extra = restrictedLoader == nil ? [] : (restrictedCache ?? [])
        }
        let mixed = RestrictedFeed.mergeLoaded(publicPhotos: counted, restricted: extra, reachedEnd: reachedEnd)
        return visible(edits.apply(to: mixed))
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
        await beforeLiveRequest?()
        do {
            try RequestCancellation.throwIfCancelled()
            let (data, response) = try await session.cancellableData(for: request)
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
    /// あわせて、ブロックした相手と、自分が通報した・消した・非公開にした写真を落とす。
    private func visible(_ photos: [Photo]) -> [Photo] {
        hiding.visible(photos.filter { $0.published != false })
    }
}
