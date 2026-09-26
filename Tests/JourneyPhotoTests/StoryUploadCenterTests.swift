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
        XCTAssertTrue(center.start([job(1), job(2), job(3)], send: { sent.append($0.imageData[0]) },
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
        center.start([job(1), job(2), job(3)], send: { j in
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
        center.start([job(1), job(2), job(3)], send: { j in
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
        center.start([job(1), job(2)], send: { _ in throw Boom() })
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
        center.start([job(1)], send: { _ in throw Boom() })
        await settle(center)
        XCTAssertFalse(center.start([job(9)], send: { _ in XCTFail("受けてしまった") }))
        XCTAssertFalse(center.start([], send: { _ in }), "空の並びも受けない")
    }
}
