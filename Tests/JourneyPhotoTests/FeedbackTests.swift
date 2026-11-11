import XCTest
@testable import JourneyPhoto

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

    func testRetryableErrors() {
        XCTAssertTrue(FeedbackService.isRetryable(APIError.unreachable))
        XCTAssertTrue(FeedbackService.isRetryable(APIError.server(status: 503, message: "")))
        XCTAssertFalse(FeedbackService.isRetryable(APIError.server(status: 429, message: "今日はこれ以上送れません")))
        XCTAssertFalse(FeedbackService.isRetryable(APIError.server(status: 400, message: "")))
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
            throw APIError.server(status: 429, message: "今日はこれ以上送れません。明日また送ってください")
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
