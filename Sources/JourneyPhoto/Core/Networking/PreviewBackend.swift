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
                      stories: Bool = false,
                      dm: Bool = false,
                      publicFeed: () async -> [[String: Any]] = { [] },
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

        // メッセージ（`-JPPreviewDM` のときだけ・2026-11-10 札 #505）
        if dm, parts.first == "dm",
           let answer = dmReply(method: method, parts: parts, json: json, me: uid, now: now,
                                samplePhoto: method == "GET" && parts.count == 2 ? dmSamplePhoto(await publicFeed()) : nil) {
            return answer
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
                var c: [String: Any] = ["id": "preview-c\(s.next())", "uid": uid, "name": "見本の利用者", "text": text, "t": stamp]
                // 返信（札 #541 の ②）。相手がこの端末のコメントに在れば、サーバーと同じ形で相手を書く（`comments.ts`）
                if let replyTo = json["replyTo"] as? String,
                   let target = s.comments(p[1]).first(where: { ($0["id"] as? String) == replyTo }) {
                    c["replyTo"] = ["id": replyTo, "uid": target["uid"] ?? "", "name": target["name"] ?? ""]
                }
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

        // ストーリー（`-JPPreviewStories` のときだけ・2026-10-22）。一覧は公開の新着の作者から作る（`previewStories`）。
        // 見た・反応・返信は受けたことにするだけ（何も書かない）
        case ("GET", let p) where stories && p == ["stories"]:
            return .json(previewStories(feed: await publicFeed(), me: uid, now: now,
                                        sharedStory: PreviewSession.sharedStory))
        case ("POST", let p) where stories && p.count == 3 && p[0] == "stories" && (p[2] == "view" || p[2] == "replies"):
            return .json([:])
        case ("GET", let p) where stories && p.count == 3 && p[0] == "stories" && p[2] == "viewers":
            return .json(["viewers": [Any]()])
        case ("GET", let p) where stories && p.count == 3 && p[0] == "stories" && p[2] == "replies":
            return .json(["items": [Any]()])

        // フォロー中（`-JPPreviewDM` のときだけ・2026-11-10「新しいメッセージ」とプロフィールの「メッセージ」を撮る）。
        // 公開の新着の作者と、見本の会話の相手の一部をフォローしていることにする（`dmFollowing`）
        case ("GET", let p) where dm && p == ["user", "following"]:
            return .json(["userIds": dmFollowing(feed: await publicFeed(), me: uid).map { $0["id"] as? String ?? "" }])
        case ("GET", let p) where dm && p.count == 3 && p[0] == "users" && p[1] == uid && p[2] == "following":
            let users = dmFollowing(feed: await publicFeed(), me: uid)
            return .json(["users": users, "total": users.count])

        default:
            return .unsupported
        }
    }

    // MARK: - メッセージの見本（2026-11-10 札 #505）

    /// 見本の相手（uid は UUID の形・名前は見本の名前）
    static let dmPeers: [(id: String, name: String, username: String?)] = [
        ("0b6f1c1e-1111-4aaa-8aaa-000000000001", "夕焼けの人", "yuyake"),
        ("0b6f1c1e-1111-4aaa-8aaa-000000000002", "港の写真家", "minato"),
        ("0b6f1c1e-1111-4aaa-8aaa-000000000003", "山の朝", "yamaasa"),
        ("0b6f1c1e-1111-4aaa-8aaa-000000000004", "旅の記録", "tabi_log"),
        ("0b6f1c1e-1111-4aaa-8aaa-000000000005", "", nil),            // 退会した人
        ("0b6f1c1e-1111-4aaa-8aaa-000000000006", "桜の便り", "sakura"),  // リクエスト
        ("0b6f1c1e-1111-4aaa-8aaa-000000000007", "海辺の散歩", "umibe"),  // リクエスト
        ("0b6f1c1e-1111-4aaa-8aaa-000000000008", "雪の駅", "yukieki"),    // 自分が始めて3通使い切った
    ]

    /// 見本のフォロー中（`GET /users/{me}/following` の `users` の形）。**公開の新着の作者**（まだ会話が無い人・
    /// 顔の写真が出る）を先に、見本の会話の相手（夕焼けの人・港の写真家・山の朝＝既にある会話）を後ろに
    static func dmFollowing(feed: [[String: Any]], me: String) -> [[String: Any]] {
        var seen = Set<String>()
        var out: [[String: Any]] = []
        for photo in feed {
            guard let user = (photo["userId"] as? String) ?? (photo["uploadedBy"] as? String),
                  user != me, seen.insert(user).inserted, seen.count <= 6 else { continue }
            var row: [String: Any] = ["id": user]
            if let name = photo["displayName"] as? String, !name.isEmpty { row["name"] = name }
            out.append(row)
        }
        for p in dmPeers.prefix(3) where seen.insert(p.id).inserted {
            var row: [String: Any] = ["id": p.id, "name": p.name]
            if let u = p.username { row["username"] = u }
            out.append(row)
        }
        return out
    }

    /// 会話の見本に載せる写真（公開の新着の1枚目・2026-11-11 札 #541）。無ければ nil（写真の通を出さない）
    static func dmSamplePhoto(_ feed: [[String: Any]]) -> [String: Any]? {
        guard let first = feed.first(where: { ($0["id"] as? String) != nil && ($0["src"] as? String) != nil }),
              let id = first["id"] as? String else { return nil }
        let src = (first["thumbSrc"] as? String) ?? (first["src"] as? String) ?? ""
        var quote: [String: Any] = ["id": id, "state": "live", "src": src]
        if let title = first["title"] as? String, !title.isEmpty { quote["title"] = title }
        if let location = first["location"] as? String, !location.isEmpty { quote["location"] = location }
        if let owner = (first["userId"] as? String) ?? (first["uploadedBy"] as? String) { quote["ownerId"] = owner }
        return quote
    }

    /// `/dm` の答え。知らない口は nil（ふだんの 503 へ）
    static func dmReply(method: String, parts: [String], json: [String: Any], me: String, now: Date,
                        samplePhoto: [String: Any]? = nil) -> Reply? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func ago(_ minutes: Double) -> String { iso.string(from: now.addingTimeInterval(-minutes * 60)) }
        func conv(_ i: Int) -> String { DMRules.conversationId(me, dmPeers[i].id) }
        func thread(_ i: Int, _ minutes: Double, _ excerpt: String, unread: Int, state: String,
                    lastMine: Bool = false) -> [String: Any] {
            let p = dmPeers[i]
            var row: [String: Any] = ["id": conv(i), "peerId": p.id, "name": p.name.isEmpty ? "退会したユーザー" : p.name,
                                      "t": ago(minutes), "excerpt": excerpt, "unread": unread, "state": state]
            if let u = p.username { row["username"] = u }
            if p.name.isEmpty { row["deleted"] = true }
            row["lastMine"] = lastMine
            return row
        }
        switch (method, parts.count) {
        case ("GET", 1):
            let items = [
                thread(0, 12, "夕焼けの色がすごい。どこですか？", unread: 1, state: "inbox"),
                thread(1, 40, "この曲いいね", unread: 2, state: "inbox"),
                thread(5, 50, "こんにちは。写真をよく見ています。", unread: 2, state: "request"),
                thread(2, 60 * 24, "ありがとう！また撮ったら見せますね", unread: 0, state: "inbox", lastMine: true),
                thread(6, 60 * 30, "行ってみたいです", unread: 1, state: "request"),
                thread(7, 60 * 50, "どこで撮りましたか", unread: 0, state: "pending"),
                thread(3, 60 * 24 * 3, "来月ここに行く予定です", unread: 0, state: "inbox"),
                thread(4, 60 * 24 * 28, "ありがとうございました", unread: 0, state: "inbox"),
            ]
            return Reply.json(["items": items, "unread": 2, "requestCount": 2])
        case ("GET", 2):
            let id = parts[1]
            guard let i = dmPeers.indices.first(where: { conv($0) == id }) else {
                return Reply.json(["error": "会話が見つかりません", "code": "notFound"], status: 404)
            }
            let p = dmPeers[i]
            func msg(_ n: Int, mine: Bool, _ text: String, _ minutes: Double, story: Bool = false) -> [String: Any] {
                var m: [String: Any] = ["id": "preview-dm-\(i)-\(n)", "from": mine ? me : p.id, "mine": mine,
                                        "text": text, "t": ago(minutes)]
                if story {
                    // 引用札（2026-11-10 の欄）: リクエストは見られる動画、ほかは終わったストーリー
                    m["via"] = "story"
                    m["storyId"] = "preview-story-dm-\(i)"
                    m["story"] = i == 5 || i == 6
                        ? ["id": "preview-story-dm-\(i)", "state": "live", "mediaType": "video",
                           "expiresAt": iso.string(from: now.addingTimeInterval(3600))] as [String: Any]
                        : ["id": "preview-story-dm-\(i)", "state": "ended"]
                }
                return m
            }
            var answer: [String: Any] = ["id": id, "peerId": p.id, "name": p.name.isEmpty ? "退会したユーザー" : p.name,
                                         "t": ago(1), "canSend": true]
            if let u = p.username { answer["username"] = u }
            switch i {
            case 4:
                answer["deleted"] = true
                answer["canSend"] = false
                answer["state"] = "inbox"
                answer["items"] = [msg(1, mine: false, "ありがとうございました", 60 * 24 * 28)]
            case 5, 6:
                answer["state"] = "request"
                answer["items"] = [msg(1, mine: false, "夕焼けの色がすごい。どこですか？", 60 * 26, story: true),
                                   msg(2, mine: false, "こんにちは。写真をよく見ています。", 50)]
            case 7:
                answer["state"] = "pending"
                answer["canSend"] = false
                answer["requestRemaining"] = 0
                answer["items"] = [msg(1, mine: true, "はじめまして。写真をよく見ています", 60 * 52, story: true),
                                   msg(2, mine: true, "夕焼けの色がすごい", 60 * 51),
                                   msg(3, mine: true, "どこですか？", 60 * 50)]
            default:
                answer["state"] = "inbox"
                var items = [msg(1, mine: false, "夕焼けの色がすごい。どこですか？", 60 * 26, story: true),
                             msg(2, mine: true, "ありがとうございます。伊豆の海沿いです。", 60 * 25.8),
                             msg(3, mine: true, "地図はここに載っています journey-photo.com/spots", 60 * 25.75),
                             msg(4, mine: false, "行ってみたい", 60 * 25.7),
                             msg(5, mine: false, "日没の30分前に着くのがおすすめです", 60 * 25.6)]
                // 写真の通（2026-11-11 札 #541）: 写真だけの1通（`photoOnly`）と、見られなくなった写真の1通
                if let samplePhoto, let pid = samplePhoto["id"] as? String {
                    var photo = msg(6, mine: true, "写真を送りました", 30)
                    photo["photoId"] = pid
                    photo["photoOnly"] = true
                    photo["photo"] = samplePhoto
                    items.append(photo)
                    var gone = msg(7, mine: false, "この写真もよかった", 20)
                    gone["photoId"] = "preview-gone-photo"
                    gone["photo"] = ["id": "preview-gone-photo", "state": "gone"] as [String: Any]
                    items.append(gone)
                }
                items.append(msg(8, mine: false, "この曲いいね", 12))
                answer["items"] = items
            }
            return Reply.json(answer)
        case ("POST", 3) where parts[2] == "messages":
            let text = (json["text"] as? String) ?? ""
            if text.contains("http") || text.contains("www.") {
                return Reply.json(["error": "承認されるまではリンクを送れません", "code": "requestUrl"], status: 400)
            }
            let message: [String: Any] = ["id": (json["id"] as? String) ?? "preview-dm-sent", "from": me, "mine": true,
                                          "text": text, "t": iso.string(from: now)]
            // まだ会話の無い相手（新しいメッセージ・プロフィールから）への1通目は、承認待ち（`pending`）
            let known = dmPeers.indices.contains { conv($0) == parts[1] }
            return Reply.json(["success": true, "conversationId": parts[1], "state": known ? "inbox" : "pending",
                               "message": message])
        case ("PUT", 3), ("POST", 3), ("DELETE", 2), ("DELETE", 3):
            return Reply.json(["ok": true, "success": true])
        default:
            return nil
        }
    }

    /// 見本のストーリーの一覧（`GET /stories` の形）。**公開の新着の作者ごとに1本**（先頭の人は2本・輪の切れ目を
    /// 見せる）と、自分にも1本。写真は公開の写真の `src` をそのまま使う（新しく画像を置かない）。
    /// 作者の顔の輪・人のページの輪を UI テストで撮るため——どの写真を開いても、その作者に輪が出る
    /// - Parameter sharedStory: 1人目の2本目に**紹介した写真**（その人の写真）を付ける（札 #541・`-JPPreviewSharedStory`）
    static func previewStories(feed: [[String: Any]], me: String, now: Date, sharedStory: Bool = false) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        let created = iso.string(from: now.addingTimeInterval(-3600))
        let expires = iso.string(from: now.addingTimeInterval(23 * 3600))
        var seen = Set<String>()
        var out: [[String: Any]] = []
        func story(_ id: String, src: String, user: String, name: Any?) -> [String: Any] {
            var row: [String: Any] = ["id": id, "src": src, "userId": user, "createdAt": created, "expiresAt": expires]
            if let name = name as? String, !name.isEmpty { row["displayName"] = name }
            return row
        }
        for photo in feed {
            guard let src = photo["src"] as? String,
                  let user = (photo["userId"] as? String) ?? (photo["uploadedBy"] as? String),
                  user != me, seen.insert(user).inserted, seen.count <= 8 else { continue }
            // 人のストーリーには曲と「札を焼き込んだ」印を付ける（名前の下の ♪ の行・長い曲名は流れる・2026-10-28）
            var row = story("preview-story-\(seen.count)", src: src, user: user, name: photo["displayName"])
            row["song"] = previewStorySong
            row["songOnPhoto"] = true
            out.append(row)
            if seen.count == 1 {
                var second = story("preview-story-\(seen.count)b", src: src, user: user, name: photo["displayName"])
                if sharedStory, let photoId = photo["id"] as? String { second["sharedPhotoId"] = photoId }
                out.append(second)
            }
        }
        if let src = feed.first?["src"] as? String {
            out.insert(story("preview-story-me", src: src, user: me, name: nil), at: 0)
        }
        return out
    }

    /// 見本のストーリーの曲（長い曲名・見る画面の名前の下の行が横に流れるのを撮る）。試聴は鳴らなくてよい
    static let previewStorySong: [String: Any] = [
        "title": "夜明けの港で聴くバラード（Long Version）", "artist": "Journey Photo Band",
        "previewUrl": "https://audio-ssl.itunes.apple.com/preview.m4a",
    ]

    /// 公開の新着（鍵なしで読む・見本の答え手を通さない）。読めなければ空（ストーリーが並ばないだけ）
    static func readPublicFeed() async -> [[String: Any]] {
        var parts = URLComponents(url: AppConfig.userAPIBaseURL.appendingPathComponent("feed"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "limit", value: "30")]
        guard let url = parts?.url,
              let (data, response) = try? await plainSession.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return object["items"] as? [[String: Any]] ?? []
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
                stories: PreviewSession.stories,
                dm: PreviewSession.dm,
                publicFeed: { await PreviewBackend.readPublicFeed() },
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
        APIClient(tokenProvider: PreviewBackend.tokenProvider ?? CognitoTokenProvider(), session: PreviewBackend.session,
                  limiter: RequestLimiter.shared, writeLimiter: RequestLimiter.sharedWrites, retryPause: previewRetryPause)
    }

    /// 見本の通信(`PreviewBackend.session` が有るとき)は 503 を「未対応」の答えに使うので、再試行で待たない
    /// (待つと画面写真・UI テストが1秒ずつ延びる)。本番は nil で既定の待ち
    static var previewRetryPause: (@Sendable (TimeInterval) async -> Void)? {
        guard PreviewBackend.session != nil else { return nil }
        return { @Sendable _ in }
    }
}

extension UploadService {
    /// アプリの投稿の口（本体は背景の転送）。UI テストの見本の通信のときだけ、本体を端末の中の答え手へ直に渡す
    static func app(api: APIClient) -> UploadService {
        PreviewBackend.transfer.map { UploadService(api: api, transfer: $0) } ?? UploadService(api: api)
    }
}
