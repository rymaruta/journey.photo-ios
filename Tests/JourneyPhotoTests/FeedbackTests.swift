import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 意見箱（札 #546・2026-11-11）。送る本文の形・口の選び方・圏外の下書き（残す・送り直す・捨てる）を見る。
final class FeedbackTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func draft(_ text: String = "使いやすい", userId: String? = "u1", wantsReply: Bool = true,
                       createdAt: Date = Date()) -> FeedbackDraft {
        FeedbackDraft(text: text, screen: "settings", wantsReply: wantsReply, userId: userId, createdAt: createdAt)
    }

    // MARK: - 送る本文

    func testBodyHasNoChoiceFieldAndOnlyOsVersion() throws {
        let d = draft()
        let body = FeedbackService.body(for: d, photoSize: nil, signedIn: true, appVersion: "1.1.20 (3)", os: "iOS 18.1")
        XCTAssertEqual(body, FeedbackService.Body(id: d.id, text: "使いやすい", screen: "settings", appVersion: "1.1.20 (3)",
                                                  os: "iOS 18.1", platform: "ios", wantsReply: true, photo: nil))
        // 自由記述だけ: 種類・👍／👎 の欄は送らない。端末の識別子・位置も送らない
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(body), encoding: .utf8))
        for key in ["kind", "rating", "type", "device", "model", "lat", "lng", "location"] {
            XCTAssertFalse(json.contains("\"\(key)\""), key)
        }
        XCTAssertTrue(FeedbackService.osVersion.hasPrefix("iOS "))
    }

    func testSignedOutNeverPromisesReply() {
        let body = FeedbackService.body(for: draft(wantsReply: true), photoSize: 10, signedIn: false)
        XCTAssertFalse(body.wantsReply)
        XCTAssertEqual(body.photo, FeedbackService.Body.Photo(contentType: "image/jpeg", size: 10))
        XCTAssertEqual(FeedbackService.path(signedIn: false), "/feedback")
        XCTAssertEqual(FeedbackService.path(signedIn: true), "/user/feedback")
    }

    /// 書いた人がいまもログインしているときだけ、ログインした人の口（人が替わったら前の人の名で送らない）
    func testSignedInOnlyForTheSameAuthor() {
        XCTAssertTrue(FeedbackOutbox.signedIn(draft(userId: "u1"), currentUserId: "u1"))
        XCTAssertFalse(FeedbackOutbox.signedIn(draft(userId: "u1"), currentUserId: "u2"))
        XCTAssertFalse(FeedbackOutbox.signedIn(draft(userId: "u1"), currentUserId: nil))
        XCTAssertFalse(FeedbackOutbox.signedIn(draft(userId: nil), currentUserId: "u1"))
    }

    func testFailureKinds() {
        XCTAssertEqual(FeedbackService.failure(APIError.unreachable), .unreachable)
        XCTAssertEqual(FeedbackService.failure(APIError.server(status: 503, message: "")), .serverBusy)
        // その日の上限はサーバーの印（feedback_limit）で見分ける。印の無い 429 は混雑として普通に送り直す
        XCTAssertEqual(FeedbackService.failure(FeedbackService.DailyLimit(message: "今日はこれ以上送れません")), .dailyLimit)
        XCTAssertEqual(FeedbackService.failure(APIError.server(status: 429, message: "")), .serverBusy)
        XCTAssertEqual(FeedbackService.failure(FeedbackService.PhotoFailed()), .photoFailed)
        XCTAssertEqual(FeedbackService.failure(APIError.server(status: 401, message: "")), .signedOut)
        XCTAssertEqual(FeedbackService.failure(APIError.notAuthenticated), .signedOut)
        XCTAssertEqual(FeedbackService.failure(APIError.server(status: 400, message: "")), .rejected)
    }

    /// 次の日の区切りはサーバーと同じ JST の0時（UTC 15:00）
    func testNextJSTMidnight() {
        let utc1459 = Date(timeIntervalSince1970: 1_762_873_140)   // 2025-11-11T14:59:00Z = JST 23:59
        XCTAssertEqual(FeedbackService.nextJSTMidnight(after: utc1459), Date(timeIntervalSince1970: 1_762_873_200))
        let utc1500 = Date(timeIntervalSince1970: 1_762_873_200)   // ちょうど JST 0:00 → 次の日の 0:00
        XCTAssertEqual(FeedbackService.nextJSTMidnight(after: utc1500), Date(timeIntervalSince1970: 1_762_873_200 + 86_400))
    }

    /// その日の上限（429）は**消さない**。次の JST の0時まで送らず、その後に送る
    func testDailyLimitKeepsDraftUntilTomorrow() async throws {
        let outbox = FeedbackOutbox(root: root)
        let now = Date(timeIntervalSince1970: 1_762_873_140)
        let d = draft(createdAt: now)
        try outbox.save(d, photo: nil)
        let outcome = await outbox.deliver(d, currentUserId: "u1", now: now) { _, _, _ in
            throw FeedbackService.DailyLimit(message: "今日はこれ以上送れません。明日また送ってください")
        }
        XCTAssertEqual(outcome, .tomorrow)
        XCTAssertEqual(outbox.all().first?.notBefore, Date(timeIntervalSince1970: 1_762_873_200))
        var tried = 0
        await outbox.flush(currentUserId: "u1", now: now.addingTimeInterval(30)) { _, _, _ in tried += 1 }
        XCTAssertEqual(tried, 0, "上限の日のうちは送り直さない")
        XCTAssertEqual(outbox.all().count, 1)
        let sent = await outbox.flush(currentUserId: "u1", now: now.addingTimeInterval(120)) { _, _, _ in tried += 1 }
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(outbox.all(), [])
    }

    /// ログインが切れていたら、その場でログインしていない人の口で送る（先頭で詰まらない）
    func testSignedOutFallsBackToAnonymousImmediately() async throws {
        let outbox = FeedbackOutbox(root: root)
        let d = draft(userId: "u1", wantsReply: false)
        try outbox.save(d, photo: nil)
        var calls: [Bool] = []
        let outcome = await outbox.deliver(d, currentUserId: "u1") { _, _, signedIn in
            calls.append(signedIn)
            if signedIn { throw APIError.server(status: 401, message: "") }
        }
        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(calls, [true, false])
        XCTAssertEqual(outbox.all(), [])
    }

    // MARK: - 圏外の下書き

    func testSaveKeepsTextAndPhotoUntilSent() throws {
        let outbox = FeedbackOutbox(root: root)
        let d = draft()
        try outbox.save(d, photo: Data([1, 2, 3]))
        XCTAssertEqual(outbox.all(), [d])
        XCTAssertEqual(outbox.photo(for: d.id), Data([1, 2, 3]))
        outbox.remove(d.id)
        XCTAssertEqual(outbox.all(), [])
        XCTAssertNil(outbox.photo(for: d.id))
    }

    func testIdMustBeUUIDShaped() throws {
        let outbox = FeedbackOutbox(root: root)
        let bad = FeedbackDraft(id: "../../x", text: "a", screen: "s", wantsReply: false, userId: nil)
        try outbox.save(bad, photo: nil)
        XCTAssertEqual(outbox.all(), [])
    }

    func testOfflineKeepsDraftAndStopsFlush() async throws {
        let outbox = FeedbackOutbox(root: root)
        let first = draft("1", createdAt: Date(timeIntervalSinceNow: -20))
        let second = draft("2", createdAt: Date(timeIntervalSinceNow: -10))
        try outbox.save(first, photo: nil)
        try outbox.save(second, photo: nil)
        var tried: [String] = []
        let sent = await outbox.flush(currentUserId: "u1") { d, _, _ in
            tried.append(d.text)
            throw APIError.unreachable
        }
        XCTAssertEqual(sent, 0)
        // 圏外なら1件目で止める（全部を順に叩かない）・どちらも残る
        XCTAssertEqual(tried, ["1"])
        XCTAssertEqual(outbox.all().map(\.text), ["1", "2"])
    }

    func testFlushSendsOldestFirstAndRemoves() async throws {
        let outbox = FeedbackOutbox(root: root)
        try outbox.save(draft("後", userId: "u2", createdAt: Date(timeIntervalSinceNow: -5)), photo: nil)
        try outbox.save(draft("先", userId: "u1", createdAt: Date(timeIntervalSinceNow: -50)), photo: Data([9]))
        var calls: [(String, Data?, Bool)] = []
        let sent = await outbox.flush(currentUserId: "u1") { d, photo, signedIn in
            calls.append((d.text, photo, signedIn))
        }
        XCTAssertEqual(sent, 2)
        XCTAssertEqual(calls.map(\.0), ["先", "後"])
        XCTAssertEqual(calls[0].1, Data([9]))
        // u2 が書いた分は、いまの人（u1）の口では送らない
        XCTAssertEqual(calls.map(\.2), [true, false])
        XCTAssertEqual(outbox.all(), [])
    }

    func testRejectedDraftIsDroppedNotRetriedForever() async throws {
        let outbox = FeedbackOutbox(root: root)
        let d = draft()
        try outbox.save(d, photo: nil)
        let outcome = await outbox.deliver(d, currentUserId: "u1") { _, _, _ in
            throw APIError.server(status: 400, message: "ひとことを書いてください")
        }
        guard case .dropped = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(outbox.all(), [])
    }

    func testTrimDropsOldAndOverflow() throws {
        let outbox = FeedbackOutbox(root: root)
        try outbox.save(draft("古い", createdAt: Date(timeIntervalSinceNow: -FeedbackOutbox.maxAge - 60)), photo: nil)
        XCTAssertEqual(outbox.all(), [])
        for i in 0..<(FeedbackOutbox.maxCount + 3) {
            try outbox.save(draft("\(i)", createdAt: Date(timeIntervalSinceNow: Double(i - 100))), photo: nil)
        }
        let kept = outbox.all()
        XCTAssertEqual(kept.count, FeedbackOutbox.maxCount)
        XCTAssertEqual(kept.first?.text, "3")
    }

    /// 写真だけ送れなかったら、本文は届いた扱いで下書きを消す（残すと本文が二重に届く）
    func testPhotoFailureCountsAsDeliveredAndIsNotResent() async throws {
        let outbox = FeedbackOutbox(root: root)
        let d = draft()
        try outbox.save(d, photo: Data([1]))
        let outcome = await outbox.deliver(d, currentUserId: "u1") { _, _, _ in throw FeedbackService.PhotoFailed() }
        XCTAssertEqual(outcome, .sentWithoutPhoto)
        XCTAssertTrue(outcome.isDelivered)
        XCTAssertEqual(outbox.all(), [])
    }

    /// ログインが切れて未ログインの口で送った回は、返事が欲しいを選んでいれば「返事は約束できない」と分かる
    func testSignedOutFallbackTellsReplyIsNotPromised() async throws {
        let outbox = FeedbackOutbox(root: root)
        let wants = draft(wantsReply: true)
        try outbox.save(wants, photo: nil)
        let a = await outbox.deliver(wants, currentUserId: "u1") { _, _, signedIn in
            if signedIn { throw APIError.notAuthenticated }
        }
        XCTAssertEqual(a, .sentWithoutReply)
        let plain = draft(wantsReply: false)
        try outbox.save(plain, photo: nil)
        let b = await outbox.deliver(plain, currentUserId: "u1") { _, _, signedIn in
            if signedIn { throw APIError.notAuthenticated }
        }
        XCTAssertEqual(b, .sent)
    }
}

/// `FeedbackService.send` の断りの見分け（本物の `APIClient` を模型の通信で動かす）
final class FeedbackServiceSendTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service(put: (@Sendable (URLRequest, Data) async throws -> URLResponse)? = nil) -> FeedbackService {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: nil), session: session,
                            retryPause: { _ in })
        return FeedbackService(api: api, putPhoto: put)
    }

    private let draft = FeedbackDraft(text: "a", screen: "settings", wantsReply: false, userId: nil)

    func testDailyLimitIsRecognisedByServerCode() async {
        StubProtocol.respond(status: 429, body: #"{"error":"今日はこれ以上送れません。明日また送ってください","code":"feedback_limit"}"#)
        do {
            try await service().send(draft, photo: nil, signedIn: false)
            XCTFail("断られるはず")
        } catch {
            XCTAssertEqual(FeedbackService.failure(error), .dailyLimit)
        }
    }

    func testPlain429IsNotTheDailyLimit() async {
        StubProtocol.respond(status: 429, body: #"{"message":"Too Many Requests"}"#)
        do {
            try await service().send(draft, photo: nil, signedIn: false)
            XCTFail("断られるはず")
        } catch {
            XCTAssertEqual(FeedbackService.failure(error), .serverBusy)
        }
    }

    func testPhotoPut4xxIsPhotoFailed() async {
        StubProtocol.respond(status: 200, body: #"{"ok":true,"id":"x","upload":{"url":"https://s3.example.test/put","contentType":"image/jpeg"}}"#)
        let put: @Sendable (URLRequest, Data) async throws -> URLResponse = { request, _ in
            HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        }
        do {
            try await service(put: put).send(draft, photo: Data([1]), signedIn: false)
            XCTFail("写真は送れないはず")
        } catch {
            XCTAssertEqual(FeedbackService.failure(error), .photoFailed)
        }
    }
}

/// 退会したら、その人の送れていない意見の下書きも端末から消す（`AccountLocalData`・審査 5.1.1(v)）
@MainActor
final class FeedbackAccountDeletionTests: XCTestCase {

    func testAccountDeletionRemovesOnlyThatPersonsDrafts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = FeedbackOutbox(root: root)
        let mine = FeedbackDraft(text: "mine", screen: "settings", wantsReply: false, userId: "gone")
        let theirs = FeedbackDraft(text: "theirs", screen: "settings", wantsReply: false, userId: "other")
        try outbox.save(mine, photo: Data([1]))
        try outbox.save(theirs, photo: nil)
        AccountLocalData.remove(userId: "gone", username: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                draftDirectory: root.appendingPathComponent("drafts"),
                                offlineTripsRoot: root.appendingPathComponent("trips"),
                                passRoot: root.appendingPathComponent("pass"),
                                feedbackRoot: root)
        XCTAssertEqual(outbox.all(), [theirs])
        XCTAssertNil(outbox.photo(for: mine.id))
    }
}

/// 意見箱の入口の置き場（2026-11-14 判断・札 #546）。写真の詳細に「使ってみてどう？」を出さない
/// （コメントの塊のすぐ下に出て、コメントの入力・返信と紛れた）。設定の「意見を送る」は残す。
final class FeedbackPlacementTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 注記（`//` の行）を除いたコード
    private func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testPhotoDetailHasNoFeedbackPrompt() throws {
        let view = code(try source("Features/PhotoDetail/PhotoDetailView.swift"))
        XCTAssertFalse(view.contains("FeedbackPrompt("), "写真の詳細に「使ってみてどう？」を置かない（コメント欄と紛れる）")
        XCTAssertFalse(view.contains("FeedbackSheet("))
        XCTAssertFalse(view.contains("使ってみてどう"))
    }

    func testSettingsKeepsFeedbackEntry() throws {
        let settings = code(try source("Features/Settings/SettingsView.swift"))
        XCTAssertTrue(settings.contains("FeedbackSheet(screen: \"settings\")"), "意見を送る入口が設定に無い")
        XCTAssertTrue(settings.contains("\"settings.feedback\""))
    }
}
