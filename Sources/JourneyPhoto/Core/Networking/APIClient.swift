import Foundation

/// 認証トークンの出どころ。テストで差し替えられるように protocol にしてある。
protocol TokenProviding: Sendable {
    /// Cognito の **ID トークン**を返す。未ログインなら nil。
    ///
    /// **アクセストークンではない。** API Gateway の JWT オーソライザは
    /// `audience` に Cognito のクライアント ID を指定している
    /// （`api-user/serverless.yml`）。アクセストークンの `aud` は空で
    /// `client_id` に入るため、送ると全部 401 になる。
    func idToken() async throws -> String?
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

    init(baseURL: URL = AppConfig.userAPIBaseURL,
         tokenProvider: TokenProviding,
         session: URLSession? = nil) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            config.waitsForConnectivity = false
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
        body: (any Encodable)? = nil
    ) async throws -> Data {
        try await send(method, path, query: query, body: body, authorized: true)
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
        authorized: Bool
    ) async throws -> Data {
        var request = URLRequest(url: try url(for: path, query: query))
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.api.encode(AnyEncodable(body))
        }

        if authorized {
            guard let token = try await tokenProvider.idToken() else {
                throw APIError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            throw APIError.notAuthenticated
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
