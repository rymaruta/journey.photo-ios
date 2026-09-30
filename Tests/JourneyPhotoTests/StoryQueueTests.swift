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

    // MARK: - 座標（撮影地は全部で1つ・`StoryQueue.coordsToSend`）

    private let kyoto = Photo.Coords(lat: 35.01, lng: 135.77)
    /// 京都から約1.1km（丸めの境目をまたぐ隣のマス）
    private let kyotoNext = Photo.Coords(lat: 35.02, lng: 135.77)
    private let tokyo = Photo.Coords(lat: 35.68, lng: 139.77)
    /// 京都から約40km
    private let osaka = Photo.Coords(lat: 34.69, lng: 135.50)

    /// 🔴 GPS の無い写真には付けない（その写真の本当の位置ではない）
    func testShotsWithoutGPSGetNoCoords() {
        XCTAssertEqual(StoryQueue.coordsToSend([nil, kyoto, nil]), [nil, kyoto, nil])
    }

    /// 🔴 近い写真は自分の座標のまま（丸めの境目をまたいでも消さない）
    func testNearbyShotsKeepTheirOwnCoords() {
        XCTAssertEqual(StoryQueue.coordsToSend([kyoto, kyotoNext, kyoto]), [kyoto, kyotoNext, kyoto])
    }

    /// 🔴 基準（座標のある最初の写真）から遠い写真だけ送らない（同じ地名で別の街に札が立った）
    func testFarShotsGetNoCoords() {
        XCTAssertEqual(StoryQueue.coordsToSend([kyoto, tokyo, kyotoNext]), [kyoto, nil, kyotoNext])
        XCTAssertEqual(StoryQueue.coordsToSend([nil, tokyo, kyoto]), [nil, tokyo, nil])
    }

    /// 🔴 基準は多数派（10km 以内の仲間がいちばん多い写真）。1枚目だけ別の街でも残りを消さない
    func testBaseIsTheMajority() {
        XCTAssertEqual(StoryQueue.coordsToSend([osaka, kyoto, kyoto, kyoto]), [nil, kyoto, kyoto, kyoto])
    }

    /// 並べ替えても、どの写真に座標が付くかは変わらない
    func testMajorityDoesNotDependOnOrder() {
        let shots: [Photo.Coords?] = [osaka, kyoto, kyotoNext, nil, kyoto]
        let expected = shots.map { c -> Photo.Coords? in c == osaka ? nil : c }
        var orders: [[Int]] = []
        func permute(_ rest: [Int], _ done: [Int]) {
            if rest.isEmpty { orders.append(done); return }
            for (i, x) in rest.enumerated() {
                var r = rest; r.remove(at: i); permute(r, done + [x])
            }
        }
        permute(Array(shots.indices), [])
        for order in orders {
            XCTAssertEqual(StoryQueue.coordsToSend(order.map { shots[$0] }), order.map { expected[$0] }, "\(order)")
        }
    }

    /// 仲間の数が同じなら前の写真が基準
    func testTieGoesToTheEarlierShot() {
        XCTAssertEqual(StoryQueue.coordsToSend([kyoto, osaka]), [kyoto, nil])
        XCTAssertEqual(StoryQueue.coordsToSend([osaka, kyoto]), [osaka, nil])
    }

    func testNoBaseMeansNoCoords() {
        XCTAssertEqual(StoryQueue.coordsToSend([nil, nil]), [nil, nil])
        XCTAssertEqual(StoryQueue.coordsToSend([]), [])
    }
}
