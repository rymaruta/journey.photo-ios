import Foundation

// Linux では URLSession・URLProtocol が別モジュールに居る（`APIClient` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **端末の中だけで答える見本の通信**（UI テストだけ・Debug のみ・2026-10-22）。`-JPPreviewLocalBackend YES`。
///
/// 鍵を持たない見本の入り方（`PreviewSession`）では、いいね・保存・コメント・投稿が鍵の無いところで止まり、
/// 「押せる・結果が画面に出る」を UI テストで確かめられなかった。
///
/// 2026-10-22 判断: **staging の試験用の利用者は使わない。** CI は資格情報を持たず（`AuthStore.restore` の注記）、
/// 持たせるのは Actions の秘密に触る変更になる。ここで**鍵の要る口だけ**を端末の中で答える:
///
/// - 画面・ViewModel・Service・`APIClient`（JSON の組み立てと読み取り）は**本物の道をそのまま通る**。
///   入れ替えるのは通信の向こう側だけ（`URLProtocol`）なので、送る口を止める・答えの読み方を壊すと試験が落ちる
/// - **サーバーには何も書かない。** 答えるのは見本の鍵（`token`）を付けた要求と、見本の置き場（`host`）だけ。
///   それ以外（公開の一覧・いいね数・画像）は本物を読む
/// - 知らない口は 503 で断る（401 にしない——401 は「取り直し → ログアウト」に倒れる）
/// - ログアウト → ログインは見本の認証（`authGateway`）。Amplify には触らない
///
/// 🔴 **Release には中身を入れない**（2026-10-22 確かめ役の指摘）。見本のメール・パスワード・答え手は `#if DEBUG` の内側だけで、
/// Release の `PreviewBackend` は下の「何も差し替えない」口（どれも nil）だけを持つ
enum PreviewBackend {
#if DEBUG

    /// 見本の鍵（JWT ではない）。これを付けた要求だけに答える
    static let token = "preview-local-backend"
    /// 投稿の本体を置く見本の置き場（`.invalid` は外へ出ない名前）
    static let host = "preview-local.invalid"
    /// 見本の認証で通るメールアドレスとパスワード（資格情報ではない・端末の中だけ）
    static let email = "preview@journey-photo.test"
    static let password = "Preview-1234"

    static var isOn: Bool { PreviewSession.localBackend }

    /// API に付ける鍵の出どころ。見本の通信が入っていなければ nil（本物の Cognito）
    static var tokenProvider: TokenProviding? { isOn ? PreviewToken() : nil }

    /// API が使う URLSession。見本の通信が入っていなければ nil（今までどおり）
    static var session: URLSession? { isOn ? sharedSession : nil }

    /// 投稿の本体（S3 への PUT）を運ぶ口。見本の通信が入っていなければ nil（背景の転送）。
    /// 2026-10-22 判断: `URLProtocol` は upload タスクの本文を受け取れない作りがあり、本体が届いたかを確かめられない。
    /// 本体は答え手へ**直に渡す**（空なら 400 で断る——空の写真で投稿が通ったように見せない）
    static var transfer: PhotoTransfer? { isOn ? PreviewTransfer() : nil }

    struct PreviewTransfer: PhotoTransfer {
        func upload(_ request: URLRequest, body: Data, key: String) async throws -> URLResponse {
            guard let url = request.url else { throw APIError.unreachable }
            let reply = await PreviewBackend.reply(method: request.httpMethod ?? "PUT", route: PreviewBackend.route(url, basePath: ""),
                                                   body: body, userId: PreviewSession.userId, publicLikes: { _ in nil })
            guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                                 headerFields: nil) else { throw APIError.unreachable }
            return response
        }
    }

    /// 1本だけ作る。作るときに `URLSession.shared` にも答え手を足す（投稿した写真の画像を一覧が読む）
    private static let sharedSession: URLSession = {
        _ = URLProtocol.registerClass(PreviewBackendProtocol.self)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIClient.requestTimeout
        config.protocolClasses = [PreviewBackendProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }()

    /// 見本の認証（`AuthStore` の口）。見本の通信が入っていなければ nil（本物の Amplify）
    static var authGateway: AuthStoreGateway? {
        guard isOn else { return nil }
        return AuthStoreGateway(
            isSignedIn: { PreviewSession.userId != nil },
            currentUserId: {
                guard let id = PreviewSession.userId else { throw WrongCredentials() }
                return id
            },
            currentUsername: {
                guard let id = PreviewSession.userId else { throw WrongCredentials() }
                return id
            },
            isSessionExpired: { false },
            signOut: { .signedOut },
            deleteUser: { throw WrongCredentials() },
            signIn: { email, password in
                guard email.trimmingCharacters(in: .whitespacesAndNewlines) == PreviewBackend.email,
                      password == PreviewBackend.password else { throw WrongCredentials() }
                return true
            }
        )
    }

    struct WrongCredentials: LocalizedError {
        var errorDescription: String? { AuthMessage.text(for: .notAuthorized) }
    }

    struct PreviewToken: TokenProviding {
        func idToken() async throws -> String? { PreviewBackend.token }
    }

    /// この要求に答えるか（見本の鍵を付けた要求と、見本の置き場）
    static func handles(_ request: URLRequest) -> Bool {
        if request.url?.host == host { return true }
        return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)"
    }

    // MARK: - 端末の中の状態

    /// 押したいいね・保存・書いたコメント・置いた本体。**アプリを終えると消える**（試験ごとにまっさら）
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var liked: [String] = []
        private var saved: [String] = []
        /// 押す前の公開のいいね数（本物を1回だけ読む）
        private var base: [String: Int] = [:]
        private var comments: [String: [[String: Any]]] = [:]
        private var blobs: [String: Data] = [:]
        private var seq = 0

        func with<T>(_ body: (Store) -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body(self)
        }

        fileprivate func next() -> Int { seq += 1; return seq }
        fileprivate func isLiked(_ id: String) -> Bool { liked.contains(id) }
        fileprivate func setLiked(_ id: String, _ on: Bool) {
            liked.removeAll { $0 == id }
            if on { liked.insert(id, at: 0) }
        }
        fileprivate var likedIds: [String] { liked }
        fileprivate func baseLikes(_ id: String) -> Int? { base[id] }
        fileprivate func setBase(_ id: String, _ n: Int) { if base[id] == nil { base[id] = n } }
        fileprivate func isSaved(_ id: String) -> Bool { saved.contains(id) }
        fileprivate func setSaved(_ id: String, _ on: Bool) {
            saved.removeAll { $0 == id }
            if on { saved.insert(id, at: 0) }
        }
        fileprivate var savedIds: [String] { saved }
        fileprivate func comments(_ id: String) -> [[String: Any]] { comments[id] ?? [] }
        fileprivate func addComment(_ id: String, _ c: [String: Any]) { comments[id, default: []].insert(c, at: 0) }
        fileprivate func removeComment(_ id: String, _ cid: String) {
            comments[id]?.removeAll { ($0["id"] as? String) == cid }
        }
        fileprivate func blob(_ key: String) -> Data? { blobs[key] }
        fileprivate func setBlob(_ key: String, _ data: Data) { blobs[key] = data }
    }

    static let store = Store()

    // MARK: - 答え

    struct Reply {
        let status: Int
        let body: Data
        var contentType = "application/json"

        static func json(_ object: Any, status: Int = 200) -> Reply {
            Reply(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
        }
        static let unsupported = Reply.json(["error": "見本の通信では使えない口です（UI テスト）"], status: 503)
    }

    /// 要求の道を、API の土台（`basePath`）からの部品に分ける。見本の置き場は先頭に `host` を付けた形
    static func route(_ url: URL, basePath: String) -> [String] {
        let parts = url.path.split(separator: "/").map(String.init)
        if url.host == host { return [host] + parts }
        let base = basePath.split(separator: "/").map(String.init)
        guard parts.starts(with: base) else { return parts }
        return Array(parts.dropFirst(base.count))
    }

    /// 1本の要求に答える。`publicLikes` は押す前の公開のいいね数（本物を読む・読めなければ nil）
    static func reply(method: String, route parts: [String], body: Data?, userId: String?, now: Date = Date(),
                      store: Store = PreviewBackend.store,
                      publicLikes: (String) async -> Int?) async -> Reply {
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        let uid = userId ?? "preview"
        let stamp = ISO8601DateFormatter().string(from: now)

        // 見本の置き場（投稿の本体の PUT と、その画像の GET）
        if parts.first == host {
            let key = parts.dropFirst(2).joined(separator: "/")
            switch (method, parts.dropFirst().first) {
            case ("PUT", "put"?):
                // 本体が届いていない（空）なら断る——投稿の試験が「写真の中身が答え手に届いたか」を見る
                guard let body, !body.isEmpty else { return .json(["error": "本体が空です"], status: 400) }
                store.with { $0.setBlob(key, body) }
                return Reply(status: 200, body: Data())
            case ("GET", "img"?):
                guard let data = store.with({ $0.blob(key) }), !data.isEmpty else { return Reply(status: 404, body: Data()) }
                return Reply(status: 200, body: data, contentType: "image/jpeg")
            default:
                return Reply(status: 404, body: Data())
            }
        }

        switch (method, parts) {
        // いいね（押す前の公開の数に、押していれば 1 を足す）
        case (_, let p) where (method == "POST" || method == "DELETE") && p.count == 3 && p[0] == "photos" && p[2] == "like":
            let id = p[1]
            let base = await knownBase(id, store: store, publicLikes: publicLikes)
            let on = method == "POST"
            store.with { $0.setLiked(id, on) }
            var answer: [String: Any] = ["liked": on]
            if let base { answer["likes"] = base + (on ? 1 : 0) }
            return .json(answer)
        case ("GET", let p) where p == ["user", "likes"]:
            return .json(["photoIds": store.with { $0.likedIds }])
        case ("GET", let p) where p.count == 3 && p[0] == "user" && p[1] == "likes":
            let id = p[2]
            let base = await knownBase(id, store: store, publicLikes: publicLikes)
            let on = store.with { $0.isLiked(id) }
            var answer: [String: Any] = ["liked": on]
            if let base { answer["count"] = base + (on ? 1 : 0) }
            return .json(answer)

        // 保存
        case ("POST", let p) where p.count == 3 && p[0] == "photos" && p[2] == "save":
            store.with { $0.setSaved(p[1], true) }
            return .json(["saved": true])
        case ("DELETE", let p) where p.count == 3 && p[0] == "photos" && p[2] == "save":
            store.with { $0.setSaved(p[1], false) }
            return .json(["saved": false])
        case ("GET", let p) where p == ["user", "saves"]:
            return .json(["photoIds": store.with { $0.savedIds }])
        case ("GET", let p) where p.count == 3 && p[0] == "user" && p[1] == "saves":
            return .json(["saved": store.with { $0.isSaved(p[2]) }])

        // コメント（この端末で書いたものだけ・新しい順）
        case ("GET", let p) where p.count == 3 && p[0] == "user" && p[1] == "comments":
            let items = store.with { $0.comments(p[2]) }
            return .json(["items": items, "count": items.count])
        case ("POST", let p) where p.count == 3 && p[0] == "photos" && p[2] == "comments":
            guard let text = json["text"] as? String, !text.isEmpty else {
                return .json(["error": "コメントを入力してください"], status: 400)
            }
            let comment: [String: Any] = store.with { s in
                let c: [String: Any] = ["id": "preview-c\(s.next())", "uid": uid, "name": "見本の利用者", "text": text, "t": stamp]
                s.addComment(p[1], c)
                return c
            }
            return .json(["comment": comment])
        case ("DELETE", let p) where p.count == 4 && p[0] == "photos" && p[2] == "comments":
            store.with { $0.removeComment(p[1], p[3]) }
            return .json([:])

        // 投稿（置き場をもらう → 本体を置く → 1行作る）
        case ("POST", let p) where p == ["upload", "presigned-url"]:
            let name = (json["fileName"] as? String) ?? "photo.jpg"
            let type = (json["fileType"] as? String) ?? "image/jpeg"
            let n = store.with { $0.next() }
            let key = "uploads/\(uid)/preview-\(n)-\(name)"
            return .json([
                "presignedUrl": "https://\(host)/put/\(key)",
                "key": key,
                "publicUrl": "https://\(host)/img/\(key)",
                "photoId": "preview-\(n)",
                "contentType": type,
            ])
        case ("POST", let p) where p == ["upload", "save"]:
            guard let src = json["publicUrl"] as? String else { return .json(["error": "publicUrl がありません"], status: 400) }
            let n = store.with { $0.next() }
            var photo: [String: Any] = [
                "id": "preview-photo-\(n)", "src": src, "userId": uid, "uploadedBy": uid,
                "published": (json["published"] as? Bool) ?? true, "createdAt": stamp, "updatedAt": stamp,
            ]
            for field in ["title", "description", "location", "category", "audience", "date", "groupId", "spotId"] {
                if let value = json[field] { photo[field] = value }
            }
            if let thumb = json["thumbUrl"] as? String { photo["thumbSrc"] = thumb }
            return .json(["success": true, "photo": photo])
        case ("DELETE", let p) where p == ["upload", "discard"]:
            return .json([:])

        default:
            return .unsupported
        }
    }

    /// 押す前の公開のいいね数。1回だけ本物を読んで覚える（読めなければ nil・数を出さない）
    private static func knownBase(_ id: String, store: Store, publicLikes: (String) async -> Int?) async -> Int? {
        if let known = store.with({ $0.baseLikes(id) }) { return known }
        guard let read = await publicLikes(id) else { return nil }
        store.with { $0.setBase(id, read) }
        return store.with { $0.baseLikes(id) }
    }

    /// 本物の公開のいいね数（鍵なしで読む・見本の答え手を通さない別の URLSession）
    static func readPublicLikes(_ photoId: String) async -> Int? {
        struct Count: Decodable { let likes: Int }
        let url = AppConfig.userAPIBaseURL.appendingPathComponent("photos").appendingPathComponent(photoId)
            .appendingPathComponent("like")
        guard let (data, response) = try? await plainSession.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONDecoder().decode(Count.self, from: data))?.likes
    }

    private static let plainSession = URLSession(configuration: .ephemeral)

    /// 送られた本文（`httpBody`、無ければ流れから読む）
    static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
#else
    // Release: 何も差し替えない（見本の答え手・見本の認証・見本のメールとパスワードの中身は入れない）
    static var tokenProvider: TokenProviding? { nil }
    static var session: URLSession? { nil }
    static var transfer: PhotoTransfer? { nil }
    static var authGateway: AuthStoreGateway? { nil }
#endif
}

#if DEBUG
/// 見本の通信の答え手（`PreviewBackend`）。見本の鍵・見本の置き場の要求だけを引き受ける
final class PreviewBackendProtocol: URLProtocol {

    private var work: Task<Void, Never>?
    /// 止められた（`stopLoading`）。読み書きは `startLoading` を受けたスレッドだけ
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { PreviewBackend.handles(request) }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// 🔴 **`client` は `startLoading` を受けたスレッドからだけ呼ぶ**（2026-10-22 確かめ役の指摘・`URLProtocol` の決まり）。
    /// 答えを作るのは `Task`（公開のいいね数を読みに行く）なので、できた答えはそのスレッドの run loop へ戻して返す
    override func startLoading() {
        let request = self.request
        let body = PreviewBackend.body(of: request)
        let home = HomeLoop.current()
        work = Task { [weak self] in
            guard let url = request.url else { return }
            let reply = await PreviewBackend.reply(
                method: request.httpMethod ?? "GET",
                route: PreviewBackend.route(url, basePath: AppConfig.userAPIBaseURL.path),
                body: body, userId: PreviewSession.userId,
                publicLikes: { await PreviewBackend.readPublicLikes($0) })
            home.perform { self?.deliver(reply, url: url) }
        }
    }

    private func deliver(_ reply: PreviewBackend.Reply, url: URL) {
        guard !stopped, let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                                       headerFields: ["Content-Type": reply.contentType]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stopped = true
        work?.cancel()
    }

    /// `startLoading` を受けたスレッドの run loop。そこへ仕事を戻す
    private struct HomeLoop: @unchecked Sendable {
        #if canImport(Darwin)
        let loop: CFRunLoop
        static func current() -> HomeLoop { HomeLoop(loop: CFRunLoopGetCurrent()) }
        func perform(_ block: @escaping () -> Void) {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, block)
            CFRunLoopWakeUp(loop)
        }
        #else
        // Linux の試験はこの答え手を URLSession に通さない（`reply` を直に呼ぶ）。形だけ持つ
        static func current() -> HomeLoop { HomeLoop() }
        func perform(_ block: @escaping () -> Void) { block() }
        #endif
    }
}
#endif

extension APIClient {
    /// アプリの API の口（Cognito の鍵）。`AppEnvironment` を受け取れない所（画面の init・通知）が使う。
    /// UI テストの見本の通信（`PreviewBackend`・Debug のみ）のときだけ、鍵と URLSession を端末の中の答え手へ向ける
    /// （2026-10-22 判断: 写真の詳細・投稿・マイページ・通知が各自 `CognitoTokenProvider` で作っていたので、1か所に寄せた）
    static func app() -> APIClient {
        APIClient(tokenProvider: PreviewBackend.tokenProvider ?? CognitoTokenProvider(), session: PreviewBackend.session)
    }
}

extension UploadService {
    /// アプリの投稿の口（本体は背景の転送）。UI テストの見本の通信のときだけ、本体を端末の中の答え手へ直に渡す
    static func app(api: APIClient) -> UploadService {
        PreviewBackend.transfer.map { UploadService(api: api, transfer: $0) } ?? UploadService(api: api)
    }
}
