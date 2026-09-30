import XCTest
@testable import JourneyPhoto

/// 複数枚のストーリー（モック4-5）。
final class StoryQueueTests: XCTestCase {

    /// 🔴 **自分より前を外したら1つ繰り上がる。** ずらさないと、
    /// 画面に出ている絵と触っている文字が1つずれる
    /// 🔴 **出せたぶんは id で外す。** 送っている間に並びが変わると、
    /// `removeFirst(出せた数)` は範囲外で落ちていた（3枚で送り始め、送信中に2枚外し、
    /// 3本目で失敗 → 出せた2 > 残り1）
    func testDropPostedRemovesByIdEvenIfTheListShrank() {
        struct Shot: Identifiable { let id: Int }
        let now = [Shot(id: 3)]                       // 送信中に1と2を外した後の並び
        XCTAssertEqual(StoryQueue.dropPosted(now, posted: [1, 2]).map(\.id), [3])
        let all = [Shot(id: 1), Shot(id: 2), Shot(id: 3)]
        XCTAssertEqual(StoryQueue.dropPosted(all, posted: [1, 2]).map(\.id), [3])
        XCTAssertEqual(StoryQueue.dropPosted(all, posted: []).map(\.id), [1, 2, 3])
    }

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

    /// 並べ替え。**編集していた写真を追いかける**——並びを実際に動かして、
    /// どの位置からどこへ移しても、移したあとの `current` が同じ写真を指すこと
    func testMovingFollowsTheShotBeingEdited() {
        let shots = ["a", "b", "c", "d"]
        for from in shots.indices {
            for to in shots.indices where to != from {
                for current in shots.indices {
                    var moved = shots
                    moved.insert(moved.remove(at: from), at: to)
                    let next = StoryQueue.currentAfterMoving(from: from, to: to, current: current)
                    XCTAssertEqual(moved[next], shots[current], "from \(from) to \(to) current \(current)")
                }
            }
        }
    }

    // MARK: - 座標（撮影地は全部で1つ）

    func testSharedCoordsWhenAllAgree() {
        let kyoto = Photo.Coords(lat: 35.01, lng: 135.77)
        XCTAssertEqual(StoryQueue.sharedCoords([kyoto, kyoto]), kyoto)
    }

    /// 座標の無い写真は数えない（ある写真どうしが同じなら、その座標）
    func testSharedCoordsIgnoresShotsWithoutGPS() {
        let kyoto = Photo.Coords(lat: 35.01, lng: 135.77)
        XCTAssertEqual(StoryQueue.sharedCoords([nil, kyoto, nil]), kyoto)
        XCTAssertNil(StoryQueue.sharedCoords([nil, nil]))
        XCTAssertNil(StoryQueue.sharedCoords([]))
    }

    /// 🔴 食い違えば送らない（同じ地名の札が別々の場所に立った）
    func testSharedCoordsIsNilWhenShotsDisagree() {
        let kyoto = Photo.Coords(lat: 35.01, lng: 135.77)
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.77)
        XCTAssertNil(StoryQueue.sharedCoords([kyoto, tokyo]))
        XCTAssertNil(StoryQueue.sharedCoords([kyoto, nil, kyoto, tokyo]))
    }
}
