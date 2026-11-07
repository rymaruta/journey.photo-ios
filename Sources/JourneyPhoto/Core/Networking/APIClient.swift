import Foundation

// Linux では URLSession が別モジュールに居る。**iOS では何も起きない**が、
// これがないと Linux 上で `swift build` / `swift test` ができない
// （Xcode の無い環境で型検査できる唯一の層なので、そこを塞がない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 認証トークンの出どころ。テストで差し替えられるように protocol にしてある。
protocol TokenProviding: Sendable {
    /// Cognito の **ID トークン**を返す。未ログインなら nil。
    ///
    /// **アクセストークンではない。** API Gateway の JWT オーソライザは
    /// `audience` に Cognito のクライアント ID を指定している
    /// （`api-user/serverless.yml`）。アクセストークンの `aud` は空で
    /// `client_id` に入るため、送ると全部 401 になる。
    func idToken() async throws -> String?

    /// **401 を受けたあと**、手元の控えを使わずに Cognito から取り直した ID トークン。
    /// nil は「取り直せない（ログインが切れている）」。通信できない回は投げる
    /// （圏外の人をログアウトさせない）。
    ///
    /// 同時に何本 401 になっても、取り直しは1本にまとめること（`TokenRefresher`）
    func refreshedIdToken() async throws -> String?

    /// 取り直しても通らなかった（またはそもそも取り直せなかった）。ログアウトに倒す
    func sessionExpired() async

    /// サーバーが「この人は退会済み」（410・`APIError.isAccountGone`）と答えた。
    /// `idToken` は**その要求に付けた**鍵——退会の途中の扱い（`AuthStore.noteDeletionPending`）は、
    /// 鍵の人がいまログイン中の人と同じときだけ入る（人が替わったあとに届いた古い 410 を除く）
    func accountGone(idToken: String) async
}

extension TokenProviding {
    /// 既定は「取り直せない」。**試験の差し替えはこれのまま**——401 は今までどおり
    /// 呼び手に返る（取り直しを見る試験だけが自分で持つ）
    func refreshedIdToken() async throws -> String? { nil }
    func sessionExpired() async {}
    func accountGone(idToken: String) async {}
}

/// api-user を叩く薄いクライアント。
///
/// 1エンドポイント 1メソッドは書かない。Service 層（PhotoService など）が
/// パスと型を決め、ここは「HTTP と JSON と認証」だけを持つ。
actor APIClient {

    private let baseURL: URL
    private let tokenProvider: TokenProviding
    private let session: URLSession

    /// Web 側（`lib/utils/api.ts`）と同じ考え方で、応答が無いまま待ち続けない。
    static let requestTimeout: TimeInterval = 20

    /// 要求を出す**直前**に待つ口。**本番は nil**（何もしない）。
    /// 試験が「この口だけ遅い」を作るのに使う——遅さを `URLProtocol` の応答で
    /// 作ると、Linux の Foundation では別スレッドから `client` を叩いてまれに落ちる
    /// （`PublicGalleryService.beforeLiveRequest` と同じ理由）
    private let beforeRequest: (@Sendable (URLRequest) async -> Void)?

    /// 同時に飛ばす本数の絞り（2026-11-07 判断・`RequestLimiter`）。**通信している間だけ**枠を使う——
    /// 鍵を待つ間・再試行の待ちの間は枠を握らない
    private let limiter: RequestLimiter

    /// 枠を取った**直後**に呼ぶ口。**本番は nil**。試験が「枠を持ったまま止まる要求」を作って、
    /// 同時数が絞られていることを見るのに使う（`beforeRequest` は枠を取る前なので使えない）
    private let afterAcquire: (@Sendable (URLRequest) async -> Void)?

    /// 503・429 のあとの待ち。**本番は `Task.sleep`**。試験が実際に待たずに済むよう差し替えられる
    private let retryPause: @Sendable (TimeInterval) async -> Void

    /// 503・429 を受けたときの待ちの範囲（秒）。サーバーが `Retry-After` を付けなければ
    /// 0.5〜1.5 秒のばらつき（同時に弾かれた要求が同じ瞬間に戻って、また弾かれるのを避ける）
    static let retryJitter: ClosedRange<TimeInterval> = 0.5...1.5
    /// `Retry-After` に従う上限（秒）。画面を長く待たせない——これより長い指示は上限に丸める
    static let retryAfterCap: TimeInterval = 5

    init(baseURL: URL = AppConfig.userAPIBaseURL,
         tokenProvider: TokenProviding,
         session: URLSession? = nil,
         maxConcurrentRequests: Int = RequestLimiter.defaultLimit,
         retryPause: (@Sendable (TimeInterval) async -> Void)? = nil,
         afterAcquire: (@Sendable (URLRequest) async -> Void)? = nil,
         beforeRequest: (@Sendable (URLRequest) async -> Void)? = nil) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.beforeRequest = beforeRequest
        self.limiter = RequestLimiter(limit: maxConcurrentRequests)
        self.afterAcquire = afterAcquire
        self.retryPause = retryPause ?? Self.sleepPause
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            // **繋がるまで待たない。** 圏外なら早く諦めて、控えを出す方へ倒す。
            // Linux の corelibs では読み取り専用なので、Apple 側だけで設定する
            #if canImport(Darwin)
            config.waitsForConnectivity = false
            #endif
            self.session = URLSession(configuration: config)
        }
    }

    enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    // MARK: - 呼び出し口

    /// 認証付きで叩いて JSON を型に流し込む。
    func authorized<Response: Decodable>(
        _ method: Method,
        _ path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await send(method, path, query: query, body: body, authorized: true, cachePolicy: cachePolicy)
        return try decode(data)
    }

    /// 認証付きで叩いて、応答の中身は捨てる。
    @discardableResult
    func authorizedVoid(
        _ method: Method,
        _ path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        try await send(method, path, query: query, body: body, authorized: true, timeout: timeout)
    }

    /// 認証なしで叩く（公開プロフィール・いいね数・コメント取得など）。
    func anonymous<Response: Decodable>(
        _ method: Method,
        _ path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await send(method, path, query: query, body: body, authorized: false)
        return try decode(data)
    }

    // MARK: - 実装

    private func send(
        _ method: Method,
        _ path: String,
        query: [String: String],
        body: (any Encodable)?,
        authorized: Bool,
        timeout: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) async throws -> Data {
        var request = URLRequest(url: try url(for: path, query: query))
        request.httpMethod = method.rawValue
        // **端末の HTTP 控えを使わない口だけ指定する**（`Cache-Control: max-age` 付きで返る本人の口。
        // 例: 光と天気の一覧 `LightForecastService`）
        if let cachePolicy { request.cachePolicy = cachePolicy }
        // **長く掛かると分かっている口だけ延ばす**（退会: サーバーは最長29秒）
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.api.encode(AnyEncodable(body))
        }

        guard authorized else { return try await perform(request) }
        guard let token = try await tokenProvider.idToken() else {
            throw APIError.notAuthenticated
        }

        // 🔴 **401 を受けたら、取り直して1回だけやり直す。** ID トークンは1時間で切れる。
        // Amplify は手元の控えが切れる少し前に更新するが、端末の時計のずれや、
        // 送っている途中で切れた回はサーバーが 401 を返す。そのまま投げていたので、
        // 画面は「ログインの有効期限が切れました」を出したまま、ログイン中の見た目で
        // 何もできなかった（`APIError.isAuthExpired` はどこからも読まれていなかった）。
        //
        // **やり直すのは1回だけ。** 取り直しても 401 なら、本当に切れている——
        // ログアウトに倒す（`TokenProviding.sessionExpired`）。認証の要らない口は上で
        // 返しているので、ここへは来ない。
        //
        // `catch … where` の中で await しない（Xcode 26.3 のコンパイラが落ちた・
        // `AuthGateway.idToken` の注記）。答えを `Result` に取ってから分ける
        let first = await attempt(request, bearer: token)
        guard case .failure(let error) = first else { return try first.get() }
        guard (error as? APIError)?.isAuthExpired == true else { throw error }

        guard let fresh = try await tokenProvider.refreshedIdToken() else {
            await tokenProvider.sessionExpired()
            throw error
        }
        // 🔴 **取り直した鍵が別の人のものなら送り直さない。** 期限切れでログアウトし、
        // 別のアカウントで入り直した直後に古い要求の 401 が返ると、取り直した鍵は
        // **新しい人の**ものになる——そのまま送り直すと、前の人の操作（いいね・削除）が
        // 新しい人として通る。同じ人と確かめられた回だけ送り直す（読めない鍵も送らない）。
        // 新しい人のログインは正しいので、ログアウトには倒さない
        guard Self.isSamePerson(token, fresh) else { throw error }
        let second = await attempt(request, bearer: fresh)
        if case .failure(let retryError) = second, (retryError as? APIError)?.isAuthExpired == true {
            await tokenProvider.sessionExpired()
        }
        return try second.get()
    }

    /// 2つの ID トークンが同じ人（`sub`）のものか。どちらかが読めなければ false
    static func isSamePerson(_ sent: String, _ refreshed: String) -> Bool {
        guard let before = IdTokenClaims.subject(fromJWT: sent),
              let after = IdTokenClaims.subject(fromJWT: refreshed) else { return false }
        return before == after
    }

    /// 鍵を付けて1回送る（失敗も値で返す——上の注記）。
    ///
    /// 🔴 **退会済み（410）は、どの口でもここで1回だけ知らせる（2026-10-21 判断）。**
    /// サーバーは 10/18 から退会した人の書く口を 410 で塞ぐ（`liveCaller.ts`）が、アプリが
    /// 「退会の途中」に入るのは自分のプロフィールの読み込みだけで、投稿・コメント・いいねでは
    /// 日本語の断り文が出るだけだった。鍵を付けて送るのはここだけなので、ここで拾う。
    /// 401 の送り直しの2本目もここを通る（知らせるのは 410 を受けた1本ぶんだけ）。
    /// 付けた鍵を渡す——**いまの人ではなく、送った人**で確かめる（`TokenProviding.accountGone`）
    private func attempt(_ request: URLRequest, bearer token: String) async -> Result<Data, Error> {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let result: Result<Data, Error>
        do {
            result = .success(try await perform(request))
        } catch {
            result = .failure(error)
        }
        if case .failure(let error) = result, (error as? APIError)?.isAccountGone == true {
            await tokenProvider.accountGone(idToken: token)
        }
        return result
    }

    /// 1回送る。**503・429（スロットル）のときだけ、読むだけの要求（GET）を1回だけ**待って送り直す
    /// （2026-11-07 判断）。書く要求（POST/PUT/PATCH/DELETE）は送り直さない——サーバーが
    /// 処理したあとに 503 を返したのか分からず、二重に書く（二重のいいね・二重の投稿）恐れがある。
    /// 401 の取り直し（`send`）とは別の層: 401 の送り直しの2本目もここを通るので、それぞれ1回まで。
    /// 待っている間は枠（`limiter`）を返しているので、ほかの要求を止めない
    private func perform(_ request: URLRequest) async throws -> Data {
        let first = await performOnce(request)
        guard case .failure(let error) = first else { return try first.get() }
        guard let throttled = error as? Throttled else { throw error }
        guard request.httpMethod == Method.get.rawValue else { throw throttled.underlying }
        await retryPause(Self.retryDelay(retryAfter: throttled.retryAfter, jitter: Double.random(in: Self.retryJitter)))
        // 待っている間に画面を離れた要求は、送り直さない
        try Task.checkCancellation()
        let second = await performOnce(request)
        if case .failure(let retryError) = second, let again = retryError as? Throttled {
            throw again.underlying
        }
        return try second.get()
    }

    /// スロットルの印（`performOnce` の中だけ）。送り直すかは `perform` が決める
    private struct Throttled: Error {
        let underlying: APIError
        let retryAfter: TimeInterval?
    }

    /// 待つ秒数。`Retry-After`（秒）があればそれに従い（上限 `retryAfterCap`）、無ければ `jitter`
    @Sendable private static func sleepPause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    static func retryDelay(retryAfter: TimeInterval?, jitter: TimeInterval) -> TimeInterval {
        if let retryAfter, retryAfter >= 0 { return min(retryAfter, retryAfterCap) }
        return jitter
    }

    /// `Retry-After` の秒数。日付の形は読まない（nil で、ばらつきの待ちになる）
    static func retryAfterSeconds(_ header: String?) -> TimeInterval? {
        guard let header, let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    private func performOnce(_ request: URLRequest) async -> Result<Data, Error> {
        do {
            return .success(try await transfer(request))
        } catch {
            return .failure(error)
        }
    }

    private func transfer(_ request: URLRequest) async throws -> Data {
        await beforeRequest?(request)
        let data: Data
        let response: URLResponse
        // 枠を取るのは通信の間だけ。取り消されたら待ちから外れて `CancellationError`
        // （`acquire` が最初に取り消しを見る——通信の手前で止める今までの振る舞いのまま）
        try await limiter.acquire()
        await afterAcquire?(request)
        // 答えを `Result` に取って、枠を返してから分ける（`catch` の中で await しない・上の注記）
        let outcome: Result<(Data, URLResponse), Error>
        do {
            try RequestCancellation.throwIfCancelled()
            outcome = .success(try await session.cancellableData(for: request))
        } catch {
            outcome = .failure(error)
        }
        await limiter.release()
        switch outcome {
        case .success(let pair):
            (data, response) = pair
        case .failure(let error):
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                throw APIError.notAuthenticated
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                // **取り消しを「通信できません」と言わない。** 画面を離れた・
                // 引き下げ更新の途中で描き直された回に、失敗の文が残っていた。
                // 画面は `CancellationError` を失敗として扱わない
                throw CancellationError()
            }
            throw APIError.unreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("HTTP 応答ではありません")
        }
        guard (200..<300).contains(http.statusCode) else {
            Self.errorBodySink?.set(data)
            let failure = APIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
            if http.statusCode == 503 || http.statusCode == 429 {
                throw Throttled(underlying: failure,
                                retryAfter: Self.retryAfterSeconds(http.value(forHTTPHeaderField: "Retry-After")))
            }
            throw failure
        }
        return data
    }

    /// パスに書いてよい文字。`.urlPathAllowed` に **`%` を足す**——呼び手が先に符号化した
    /// 部分（行きたい場所の鍵の `/` → `%2F`・`SavedSpotService.pathSegment`）を二重にしない。
    /// 生の日本語は今までどおりここで1回だけ符号化される
    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.insert("%")
        return set
    }()

    /// 🔴 **`appendingPathComponent` を使わない。** あれは `%` も符号化するので、
    /// 呼び手が `/` を `%2F` にして渡しても `%252F` に化け、鍵の中の `/` を
    /// 道の区切りから守る手段が無かった。ほかの口の値は `PathID` が英数字・`-`・`_` に
    /// 絞っているので、組み方を変えても同じ URL になる
    private func url(for path: String, query: [String: String]) throws -> URL {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let encoded = normalized.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed),
              // 壊れた `%`（`%z` など）を `percentEncodedPath` に入れると Foundation が落とす
              encoded.removingPercentEncoding != nil else {
            throw APIError.decoding("URL を組み立てられませんでした: \(path)")
        }
        let base = components.percentEncodedPath
        components.percentEncodedPath = (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/" + encoded
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw APIError.decoding("URL を組み立てられませんでした: \(path)")
        }
        return url
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T { return empty }
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// 失敗の本文の受け取り口。**呼び手が `withValue` で置いたときだけ**、4xx / 5xx の本文をここに残す
    /// （`APIError.server` は本文の `code` を持たないので。いまは購入の `code` だけ・`PurchaseService`）
    @TaskLocal static var errorBodySink: APIErrorBody?

    /// api-user のエラー本文の `code`（`{ "error": "...", "code": "..." }`・`http.ts` の `jsonError`）。無ければ nil
    static func errorCode(from data: Data?) -> String? {
        struct Envelope: Decodable { let code: String? }
        guard let data, let code = (try? JSONDecoder().decode(Envelope.self, from: data))?.code, !code.isEmpty else {
            return nil
        }
        return code
    }

    /// api-user のエラー本文は `{ "error": "..." }`（`http.ts` の `jsonError`）。
    /// 日本語のメッセージがそのまま画面に出せる文になっているので拾う。
    static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable { let error: String? }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           let message = envelope.error, !message.isEmpty {
            return message
        }
        return ""
    }
}

/// 本文を読み捨てる応答用。
struct EmptyResponse: Decodable {}

/// `any Encodable` をそのまま JSONEncoder に渡せない（Swift 5.9）ための包み。
private struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) {
        self.encodeTo = { encoder in try wrapped.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws { try encodeTo(encoder) }
}

extension JSONDecoder {
    /// api-user のキーは camelCase そのまま。日付は ISO8601 文字列で来るが、
    /// 欠けている写真があるので `String` のまま持ち、表示側で解釈する。
    static let api: JSONDecoder = JSONDecoder()
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        // 送信側で null を省くと、api-user の「未指定＝変更しない」判定と
        // 揃う（`photoUpdate.ts` は undefined を「触らない」と読む）
        return encoder
    }()
}

/// 失敗の本文を受け取る入れ物（`APIClient.errorBodySink`）
final class APIErrorBody: @unchecked Sendable {
    private let lock = NSLock()
    private var _data: Data?
    var data: Data? { lock.lock(); defer { lock.unlock() }; return _data }
    func set(_ data: Data) { lock.lock(); _data = data; lock.unlock() }
}
