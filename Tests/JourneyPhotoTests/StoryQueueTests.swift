import XCTest
@testable import JourneyPhoto

/// 複数枚のストーリー（モック4-5）。
final class StoryQueueTests: XCTestCase {

    /// 🔴 **自分より前を外したら1つ繰り上がる。** ずらさないと、
    /// 画面に出ている絵と触っている文字が1つずれる
    func testRemovingBeforeCurrentShiftsDown() {
        // 3枚のうち添字0を外した（残り2枚）。編集中は添字2だった
        XCTAssertEqual(StoryQueue.currentAfterRemoving(0, current: 2, count: 2), 1)
        XCTAssertEqual(StoryQueue.currentAfterRemoving(0, current: 1, count: 2), 0)
    }

    /// 自分より後ろを外しても動かない
    func testRemovingAfterCurrentKeepsIt() {
        XCTAssertEqual(StoryQueue.currentAfterRemoving(2, current: 0, count: 2), 0)
    }

    /// **最後の1枚を編集中に外したら、最後へ寄せる**（並びの外を指さない）
    func testRemovingTheLastOneStaysInRange() {
        XCTAssertEqual(StoryQueue.currentAfterRemoving(2, current: 2, count: 2), 1)
    }

    /// 全部外したら 0（空の並びで添字 -1 を作らない）
    func testEmptyQueuePointsAtZero() {
        XCTAssertEqual(StoryQueue.currentAfterRemoving(0, current: 0, count: 0), 0)
    }

    /// 上限を超えて足させない（サーバーの1日の上限を1回で使い切らせない）
    func testRemainingStopsAtTheCap() {
        XCTAssertEqual(StoryQueue.remaining(0), StoryQueue.maxShots)
        XCTAssertEqual(StoryQueue.remaining(StoryQueue.maxShots), 0)
        XCTAssertEqual(StoryQueue.remaining(StoryQueue.maxShots + 5), 0)
    }

    /// 🔴 **途中で失敗したら「何枚出て何枚残ったか」を言う。**
    /// 「投稿できませんでした」だけだと、出たぶんが在ることが伝わらず
    /// 押し直して二重に出す
    func testPartialFailureSaysHowManyWentOut() {
        let text = StoryQueue.partialFailure(posted: 2, total: 5, reason: "通信に失敗")
        XCTAssertTrue(text.contains("2"))
        XCTAssertTrue(text.contains("3"))
        XCTAssertTrue(text.contains("通信に失敗"))
    }

    /// 1枚も出ていない回は、理由だけを出す（「0枚は出せました」と言わない）
    func testNothingPostedJustSaysWhy() {
        XCTAssertEqual(StoryQueue.partialFailure(posted: 0, total: 3, reason: "通信に失敗"),
                       "通信に失敗")
    }
}
