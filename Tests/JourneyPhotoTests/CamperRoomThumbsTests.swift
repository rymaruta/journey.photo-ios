import XCTest
import UIKit
@testable import JourneyPhoto

/// 家具の小さな絵の控え（2026-10-21 点検）: 上限で古い絵から捨てる・同じ絵を二重に描かない・メモリの警告で捨てる
@MainActor
final class CamperRoomThumbsTests: XCTestCase {

    func testCacheDropsOldestOverTheCostLimit() async {
        var c = CamperThumbCache<Int>(costLimit: 300)
        c.insert(1, key: "a", cost: 100)
        c.insert(2, key: "b", cost: 100)
        c.insert(3, key: "c", cost: 100)
        XCTAssertEqual(c.totalCost, 300)
        // a を使うと、いちばん古いのは b
        XCTAssertEqual(c.value("a"), 1)
        c.insert(4, key: "d", cost: 100)
        XCTAssertNil(c.value("b"), "上限を超えたのに、いちばん古い絵が捨てられない")
        XCTAssertEqual(c.value("a"), 1)
        XCTAssertEqual(c.value("d"), 4)
        XCTAssertLessThanOrEqual(c.totalCost, 300)
        c.removeAll()
        XCTAssertEqual(c.count, 0)
        XCTAssertEqual(c.totalCost, 0)
    }

    func testThumbsAreCappedAndNotDrawnTwice() async throws {
        let one = CamperRoomThumbs.side * CamperRoomThumbs.side * 4
        let thumbs = CamperRoomThumbs(costLimit: one * 2) { _, _ in CamperBitmap(width: 2, height: 2) }
        let ids = CamperRoomCatalog.board.filter(\.built).prefix(3).map(\.id)
        // 同じ鍵を同時に 2 回頼んでも、描くのは 1 回
        async let first = thumbs.image(ids[0], silhouette: false)
        async let second = thumbs.image(ids[0], silhouette: false)
        _ = await (first, second)
        XCTAssertEqual(thumbs.renderCount, 1)
        // 控えにあれば描かない
        _ = await thumbs.image(ids[0], silhouette: false)
        XCTAssertEqual(thumbs.renderCount, 1)
        // 影絵は別の絵
        _ = await thumbs.image(ids[0], silhouette: true)
        XCTAssertEqual(thumbs.renderCount, 2)
        // 上限（2 枚）を超えると古い絵から捨てる
        _ = await thumbs.image(ids[1], silhouette: false)
        XCTAssertEqual(thumbs.cachedCount, 2)
        XCTAssertNil(thumbs.cached(ids[0], silhouette: false))
        // メモリの警告で全部捨てる
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(thumbs.cachedCount, 0)
    }
}
