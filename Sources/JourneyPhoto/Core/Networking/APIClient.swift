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
}

extension TokenProviding {
    /// 既定は「取り直せない」。**試験の差し替えはこれのまま**——401 は今までどおり
    /// 呼び手に返る（取り直しを見る試験だけが自分で持つ）
    func refreshedIdToken() async throws -> String? { nil }
    func sessionExpired() async {}
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

    init(baseURL: URL = AppConfig.userAPIBaseURL,
         tokenProvider: TokenProviding,
         session: URLSession? = nil,
         beforeRequest: (@Sendable (URLRequest) async -> Void)? = nil) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.beforeRequest = beforeRequest
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
        as type: Response.Type
    ) async throws -> Response {
        let data = try await send(method, path, query: query, body: body, authorized: true)
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
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        var request = URLRequest(url: try url(for: path, query: query))
        request.httpMethod = method.rawValue
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
        let second = await attempt(request, bearer: fresh)
        if case .failure(let retryError) = second, (retryError as? APIError)?.isAuthExpired == true {
            await tokenProvider.sessionExpired()
        }
        return try second.get()
    }

    /// 鍵を付けて1回送る（失敗も値で返す——上の注記）
    private func attempt(_ request: URLRequest, bearer token: String) async -> Result<Data, Error> {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            return .success(try await perform(request))
        } catch {
            return .failure(error)
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        await beforeRequest?(request)
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            throw APIError.notAuthenticated
        } catch let error as URLError where error.code == .cancelled {
            // **取り消しを「通信できません」と言わない。** 画面を離れた・
            // 引き下げ更新の途中で描き直された回に、失敗の文が残っていた。
            // 画面は `CancellationError` を失敗として扱わない
            throw CancellationError()
        } catch {
            throw APIError.unreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("HTTP 応答ではありません")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    private func url(for path: String, query: [String: String]) throws -> URL {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(normalized),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.decoding("URL を組み立てられませんでした: \(path)")
        }
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
