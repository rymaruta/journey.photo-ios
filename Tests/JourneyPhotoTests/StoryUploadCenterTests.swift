import XCTest
@testable import JourneyPhoto

/// ストーリーを裏で送る係（板 27「投稿した直後」）。
///
/// 投稿画面にあった決まり（**途中で失敗したら止める・出たぶんは残す・残りを持つ**）が
/// 係へ移っても崩れていないことを見る。
@MainActor
final class StoryUploadCenterTests: XCTestCase {

    private struct Boom: LocalizedError { var errorDescription: String? { "通信できませんでした" } }

    private func job(_ n: UInt8) -> StoryUploadCenter.Job {
        StoryUploadCenter.Job(imageData: Data([n]), caption: "", location: "", coords: nil,
                              song: nil, durationSec: 5, archive: false)
    }

    @discardableResult
    private func startIn(_ center: StoryUploadCenter, _ jobs: [StoryUploadCenter.Job],
                         send: @escaping (StoryUploadCenter.Job) async throws -> Void,
                         onAllSent: @escaping () -> Void = {}) -> Bool {
        center.start(jobs, ownerId: "me", currentUserId: { [unowned self] in self.currentUser },
                     send: { job, _ in try await send(job) }, onAllSent: onAllSent)
    }

    /// テスト用: いまログインしている人（既定は投稿した本人）
    private var currentUser: String? = "me"

    /// 係の中の `Task` が片付くまで待つ（送っている間は `.sending`）
    private func settle(_ center: StoryUploadCenter) async {
        for _ in 0..<200 {
            if case .sending = center.phase { await Task.yield(); continue }
            return
        }
    }

    func testSendsInOrderThenGoesIdleAndCountsFinished() async {
        let center = StoryUploadCenter()
        var sent: [UInt8] = []
        var cleared = false
        XCTAssertTrue(startIn(center, [job(1), job(2), job(3)], send: { sent.append($0.imageData[0]) },
                                   onAllSent: { cleared = true }))
        await settle(center)
        XCTAssertEqual(sent, [1, 2, 3])
        XCTAssertEqual(center.phase, .idle)
        XCTAssertEqual(center.finished, 1)
        XCTAssertTrue(cleared, "全部出したら下書きを片付ける")
    }

    /// 🔴 **途中で失敗したら止める。** 残りを送り続けない・出たぶんを数えて知らせる
    func testStopsAtFirstFailureAndKeepsTheRest() async {
        let center = StoryUploadCenter()
        var sent: [UInt8] = []
        var cleared = false
        startIn(center, [job(1), job(2), job(3)], send: { j in
            if j.imageData[0] == 2 { throw Boom() }
            sent.append(j.imageData[0])
        }, onAllSent: { cleared = true })
        await settle(center)
        XCTAssertEqual(sent, [1], "失敗のあとの3本目を出していない")
        guard case .failed(let message, let remaining) = center.phase else {
            return XCTFail("失敗で止まっていない: \(center.phase)")
        }
        XCTAssertEqual(remaining, 2)
        XCTAssertTrue(message.contains("1枚は出せました"), message)
        XCTAssertFalse(cleared, "出し切っていないのに下書きを消した")
        XCTAssertEqual(center.finished, 0)
    }

    /// 送り直しは**残りだけ**（出たぶんを二重に出さない）
    func testRetrySendsOnlyTheRemaining() async {
        let center = StoryUploadCenter()
        var sent: [UInt8] = []
        var failOnce = true
        startIn(center, [job(1), job(2), job(3)], send: { j in
            if j.imageData[0] == 2 && failOnce { failOnce = false; throw Boom() }
            sent.append(j.imageData[0])
        })
        await settle(center)
        center.retry()
        await settle(center)
        XCTAssertEqual(sent, [1, 2, 3])
        XCTAssertEqual(center.phase, .idle)
        XCTAssertEqual(center.finished, 1)
    }

    func testDiscardDropsTheRestWithoutCountingFinished() async {
        let center = StoryUploadCenter()
        startIn(center, [job(1), job(2)], send: { _ in throw Boom() })
        await settle(center)
        center.discard()
        XCTAssertEqual(center.phase, .idle)
        XCTAssertEqual(center.finished, 0)
        XCTAssertFalse(center.isBusy)
    }

    /// **片付いていない並びがあれば、新しい投稿を受けない**（2つの並びが混ざると
    /// どれが出たのか分からない。二度押しの二重投稿もここで止まる）
    func testRejectsNewJobsWhileFailedOrSending() async {
        let center = StoryUploadCenter()
        startIn(center, [job(1)], send: { _ in throw Boom() })
        await settle(center)
        XCTAssertFalse(startIn(center, [job(9)], send: { _ in XCTFail("受けてしまった") }))
        XCTAssertFalse(startIn(center, [], send: { _ in }), "空の並びも受けない")
    }

    /// 🔴 **二度押し。** 1回目の直後（係の Task が動き出す前）でも2回目を受けない
    func testRejectsSecondStartImmediately() async {
        let center = StoryUploadCenter()
        var sent = 0
        XCTAssertTrue(startIn(center, [job(1)], send: { _ in sent += 1 }))
        XCTAssertFalse(startIn(center, [job(2)], send: { _ in sent += 100 }),
                       "Task が動き出す前の2回目を受けた")
        await settle(center)
        XCTAssertEqual(sent, 1)
    }

    /// 🔴 **別の人でログインし直したら、前の人の残りを送らない**
    func testDoesNotSendAsAnotherUser() async {
        let center = StoryUploadCenter()
        var sent: [UInt8] = []
        startIn(center, [job(1), job(2)], send: { j in
            if j.imageData[0] == 1 { throw Boom() }
            sent.append(j.imageData[0])
        })
        await settle(center)
        currentUser = "someone-else"
        center.retry()
        await settle(center)
        XCTAssertEqual(sent, [], "別の人として送った")
        XCTAssertEqual(center.phase, .idle, "残りを捨てていない")
    }

    /// 🔴 **誰か分からない間（圏外で起動して確かめられない）の「もう一度送る」は、
    /// 残りを捨てない。** 捨てていたので、送信待ちが知らせも無く消えていた
    func testRetryWhileTheUserIsUnknownKeepsTheQueue() async {
        let center = StoryUploadCenter()
        var sent: [UInt8] = []
        var failFirst = true
        startIn(center, [job(1), job(2)], send: { j in
            if failFirst { failFirst = false; throw Boom() }
            sent.append(j.imageData[0])
        })
        await settle(center)
        currentUser = nil
        center.retry()
        await settle(center)
        guard case .failed(_, let remaining) = center.phase else {
            return XCTFail("残りを捨てた: \(center.phase)")
        }
        XCTAssertEqual(remaining, 2)
        XCTAssertEqual(sent, [])
        // 本人に戻れば送り直せる
        currentUser = "me"
        center.retry()
        await settle(center)
        XCTAssertEqual(sent, [1, 2])
    }

    /// 🔴 **送っている最中にログアウトしたら、残りを捨てて落ちない**
    /// （返事を待つ間に並びを空にすると、戻った `run` が空から取り出して落ちていた）
    func testUserChangeWhileSendingDropsTheRestWithoutCrashing() async {
        let center = StoryUploadCenter()
        var sent: [UInt8] = []
        var inFlight = false
        var release = false
        startIn(center, [job(1), job(2), job(3)], send: { j in
            // **返事を待っている最中**を作る（ここで止まっている間にログアウトさせる）
            inFlight = true
            while !release { await Task.yield() }
            sent.append(j.imageData[0])
        })
        for _ in 0..<200 where !inFlight { await Task.yield() }
        XCTAssertTrue(inFlight, "1本目の送信が始まらない")
        center.userChanged(to: nil)
        release = true
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(sent, [1], "ログアウトのあとも2本目以降を送った")
        XCTAssertEqual(center.phase, .idle)
        XCTAssertEqual(center.finished, 0)
    }

    func testFailureIsReportedOnce() async {
        let center = StoryUploadCenter()
        var reported: [String] = []
        center.start([job(1)], ownerId: "me", currentUserId: { "me" },
                     send: { _, _ in throw Boom() }, onFailed: { reported.append($0) })
        await settle(center)
        XCTAssertEqual(reported.count, 1)
    }

    // MARK: - 端末に残す・送り直しで二重にしない

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("story-uploads-\(UUID().uuidString)")
    }

    /// 🔴 **送っている途中で強制終了しても、残りが消えない。** 起動し直したら
    /// 「送れませんでした」として戻り、送り直すかやめるかを選べる
    func testUnsentJobsSurviveARelaunch() async throws {
        let dir = tempDir()
        let center = StoryUploadCenter(directory: dir)
        var release = false
        center.start([job(1), job(2), job(3)], ownerId: "me", currentUserId: { "me" },
                     send: { j, _ in
            if j.imageData[0] == 1 { return }
            // 2本目の返事を待っている間に「強制終了」する
            while !release { await Task.yield() }
            throw Boom()
        })
        // 1本目を送り終えて、2本目の返事を待っているところまで進める
        for _ in 0..<2000 {
            if case .sending(let done, _) = center.phase, done == 1 { break }
            await Task.yield()
        }

        let relaunched = StoryUploadCenter(directory: dir)
        guard case .failed(_, let remaining) = relaunched.phase else {
            return XCTFail("戻っていない: \(relaunched.phase)")
        }
        XCTAssertEqual(remaining, 2, "出せた1本目まで戻した・残りを落とした")

        var sent: [UInt8] = []
        relaunched.configure(currentUserId: { "me" }, send: { j, _ in sent.append(j.imageData[0]) },
                             discardUpload: { _ in })
        relaunched.retry()
        await settle(relaunched)
        XCTAssertEqual(sent, [2, 3], "戻した画像で送れていない")
        XCTAssertEqual(relaunched.phase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "送り終えたのに端末に残った")
        release = true
        center.userChanged(to: nil)
    }

    /// 起動直後に別の人でログインしていたら、前の人の残りは送らない
    func testRestoredJobsAreDroppedForAnotherUser() async {
        let dir = tempDir()
        let center = StoryUploadCenter(directory: dir)
        center.start([job(1)], ownerId: "me", currentUserId: { "me" }, send: { _, _ in throw Boom() })
        await settle(center)
        let relaunched = StoryUploadCenter(directory: dir)
        XCTAssertTrue(relaunched.isBusy)
        relaunched.userChanged(to: "someone-else")
        XCTAssertFalse(relaunched.isBusy)
        XCTAssertFalse(StoryUploadCenter(directory: dir).isBusy, "端末から消えていない")
    }

    /// 🔴 **上げ終えた画像を覚え、送り直しに渡す**（`StoryService.post` が一覧で
    /// 出ていたかを確かめ、上げ直さない）。起動し直しても覚えている
    func testUploadedMediaIsRememberedForTheRetry() async {
        let dir = tempDir()
        let center = StoryUploadCenter(directory: dir)
        let media = StoryService.UploadedMedia(key: "uploads/me/a.jpg", publicUrl: "https://x/uploads/me/a.jpg")
        center.start([job(1)], ownerId: "me", currentUserId: { "me" }, send: { _, record in
            await record(media)
            throw Boom()   // 行を作る返事が落ちた
        })
        await settle(center)

        let relaunched = StoryUploadCenter(directory: dir)
        var seen: StoryService.UploadedMedia?
        relaunched.configure(currentUserId: { "me" }, send: { j, _ in seen = j.uploaded },
                             discardUpload: { _ in })
        relaunched.retry()
        await settle(relaunched)
        XCTAssertEqual(seen, media)
    }

    /// やめたら、上げ終えていた画像を片づける
    func testDiscardCleansUpUploadedMedia() async {
        let center = StoryUploadCenter()
        var discarded: [String] = []
        center.configure(currentUserId: { "me" }, send: { _, _ in }, discardUpload: { discarded.append($0) })
        center.start([job(1)], ownerId: "me", currentUserId: { "me" }, send: { _, record in
            await record(StoryService.UploadedMedia(key: "k1", publicUrl: "https://x/k1"))
            throw Boom()
        })
        await settle(center)
        center.discard()
        // 片づけは裏の Task で走る。**回数ではなく結果で待つ**（混んだ機械で落ちないように）
        for _ in 0..<2000 where discarded.isEmpty { await Task.yield() }
        XCTAssertEqual(discarded, ["k1"])
    }

    /// 🔴 **起動し直して送り終えたら、その投稿の元の下書きを片づける**
    /// （残すと「続きから」で同じ投稿をもう1本出しやすい）
    func testRestoredRunClearsTheDraftItCameFrom() async {
        let dir = tempDir()
        let center = StoryUploadCenter(directory: dir)
        center.start([job(1)], ownerId: "me", currentUserId: { "me" }, draftToClear: "2026-09-27T00:00:00Z",
                     send: { _, _ in throw Boom() })
        await settle(center)
        let relaunched = StoryUploadCenter(directory: dir)
        var cleared: [String] = []
        relaunched.configure(currentUserId: { "me" }, send: { _, _ in }, discardUpload: { _ in },
                             clearDraft: { cleared.append($0) })
        relaunched.retry()
        await settle(relaunched)
        XCTAssertEqual(cleared, ["2026-09-27T00:00:00Z"])
    }

    /// 画像を読めずに落としたぶんを「出せた」に数えない
    func testMissingImagesAreNotCountedAsPosted() async throws {
        let dir = tempDir()
        let center = StoryUploadCenter(directory: dir)
        center.start([job(1), job(2)], ownerId: "me", currentUserId: { "me" }, send: { _, _ in throw Boom() })
        await settle(center)
        // 2本のうち1本の画像が消えた
        let images = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".jpg") }
        try FileManager.default.removeItem(at: dir.appendingPathComponent(try XCTUnwrap(images.first)))
        let relaunched = StoryUploadCenter(directory: dir)
        guard case .failed(let message, let remaining) = relaunched.phase else {
            return XCTFail("戻っていない")
        }
        XCTAssertEqual(remaining, 1)
        XCTAssertFalse(message.contains("出せました"), message)
    }
}
