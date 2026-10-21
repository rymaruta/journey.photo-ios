import XCTest
@testable import JourneyPhoto

/// とおまわり号の中の使いやすさ（2026-10-21）: やり直す・押して置く・置ける所・新しい家具の印・手引き・二度押し・端で追うカメラ・
/// 接写の一覧の頁
final class CamperRoomUsabilityTests: XCTestCase {

    private let camper = CamperRoomLayout.make(.car, stage: .camper)
    private var owned: Set<String> { CamperRoomCatalog.owned(CamperStats(), CamperRoomStats()) }

    // MARK: やり直す

    /// 元に戻した手をやり直せる。新しい手を打つと、やり直す手は消える
    func testRedoAfterUndoAndClearedByNewMove() throws {
        var e = CamperRoomEditor(doc: CamperRoomRules.starterDocument(camper), layout: camper)
        XCTAssertFalse(e.canRedo)
        let trunk = try XCTUnwrap(e.doc.items.first { $0.k == "storage.trunk" })
        e.stow(trunk.u)
        let stowed = e.doc
        XCTAssertTrue(e.undo())
        XCTAssertNotNil(e.doc.item(trunk.u))
        XCTAssertTrue(e.canRedo)
        XCTAssertTrue(e.redo())
        XCTAssertEqual(e.doc, stowed)
        XCTAssertFalse(e.canRedo)
        XCTAssertFalse(e.redo())
        // もう一度戻して、別の手を打つとやり直しは消える
        XCTAssertTrue(e.undo())
        XCTAssertTrue(e.canRedo)
        let f = try XCTUnwrap(CamperRoomCatalog.furniture("photo_frame.landscape"))
        XCTAssertNotNil(e.place(f, owned: owned))
        XCTAssertFalse(e.canRedo)
        // やり直した手も元に戻せる
        XCTAssertTrue(e.undo())
    }

    // MARK: 押して置く

    /// 選んだ所に置ける。ぶつかる所は理由つきで断り、文書は変えない。持っていない家具・違う家具の場所は断る
    func testPlaceAtChosenSpot() throws {
        var e = CamperRoomEditor(doc: CamperRoomRules.starterDocument(camper), layout: camper)
        let trunk = try XCTUnwrap(e.doc.items.first { $0.k == "storage.trunk" })
        e.stow(trunk.u)
        let f = try XCTUnwrap(CamperRoomCatalog.furniture("storage.trunk"))
        let before = e.doc
        // 台所（左奥）にぶつかる所
        switch e.place(f, at: .floor("x", f.id, x: 0, z: 0), owned: owned) {
        case .success: XCTFail("台所の上に置けてしまう")
        case .failure(let check): XCTAssertFalse(check.ok)
        }
        XCTAssertEqual(e.doc, before)
        // 置ける所（firstFit が選ぶ所）を指定すれば、そこに置く
        let spot = try XCTUnwrap(CamperRoomRules.firstFit(f, uid: "x", in: e.doc, layout: camper))
        guard case .success(let uid) = e.place(f, at: spot, owned: owned) else { return XCTFail("置ける所に置けない") }
        let placed = try XCTUnwrap(e.doc.item(uid))
        XCTAssertEqual(placed.x, spot.x)
        XCTAssertEqual(placed.z, spot.z)
        XCTAssertNotEqual(uid, "x")
        // 置いたら棚から消える（もう一度は置けない）
        if case .success = e.place(f, at: spot, owned: owned) { XCTFail("同じ家具を 2 つ置けてしまう") }
        // 持っていない家具は置けない
        let futon = try XCTUnwrap(CamperRoomCatalog.furniture("bed.futon"))
        if case .success = e.place(futon, at: .floor("y", futon.id, x: 6, z: 6), owned: owned) { XCTFail("持っていない家具が置ける") }
    }

    /// 置ける所は、置けるどの場所の占めるマスも含み、台所と扉の前は含まない
    func testFitAreaCoversEveryFittingSpot() throws {
        var e = CamperRoomEditor(doc: CamperRoomRules.starterDocument(camper), layout: camper)
        let trunk = try XCTUnwrap(e.doc.items.first { $0.k == "storage.trunk" })
        e.stow(trunk.u)
        let f = try XCTUnwrap(CamperRoomCatalog.furniture("storage.trunk"))
        let area = e.fitArea(f)
        XCTAssertFalse(area.isEmpty)
        XCTAssertFalse(area.ceiling)
        let first = try XCTUnwrap(CamperRoomRules.firstFit(f, uid: "x", in: e.doc, layout: camper)?.rect)
        if first.w == f.width { XCTAssertTrue(Set(first.cells).isSubset(of: area.cells)) }
        XCTAssertTrue(area.cells.isDisjoint(with: Set(camper.kitchen.cells)), "台所のマスが光る")
        XCTAssertTrue(area.cells.isDisjoint(with: Set(camper.doorClearance.cells)), "扉の前が光る")
        // 壁の物は壁のマス（窓の上は含まない）
        let frame = try XCTUnwrap(CamperRoomCatalog.furniture("photo_frame.landscape"))
        let wall = e.fitArea(frame)
        XCTAssertTrue(wall.cells.isEmpty)
        XCTAssertFalse(wall.wall.isEmpty)
        for c in wall.wall {
            let item = CamperRoomItem.wall("t", frame.id, c.wall, c: c.column, row: c.row)
            XCTAssertNotNil(item.wallSpan)
        }
        // 天井の物は天井に出す
        let vent = try XCTUnwrap(CamperRoomCatalog.board.first { $0.placement == .ceiling })
        XCTAssertTrue(e.fitArea(vent).ceiling)
    }

    /// 押した所: 床は指の下のマス、部屋の外（空）を押したら nil、壁は先に当たる壁
    func testSpotUnderTheFinger() throws {
        let cam = CamperRoomCamera.overview(camper)
        let viewport = CGSize(width: 390, height: 440)
        let f = try XCTUnwrap(CamperRoomCatalog.furniture("storage.trunk"))
        let target = try XCTUnwrap(cam.project(CV3(66, 0, 72), viewport: viewport, layout: camper))
        let spot = try XCTUnwrap(CamperRoomPick.spot(for: f, ray: cam.ray(target, viewport: viewport, layout: camper), layout: camper))
        XCTAssertEqual(spot.x, 5)
        XCTAssertEqual(spot.z, 6)
        XCTAssertEqual(spot.k, f.id)
        // 上を向いた光線は床に当たらない
        XCTAssertNil(CamperRoomPick.spot(for: f, ray: (CV3(50, 10, 50), CV3(0, 1, 0)), layout: camper))
        let frame = try XCTUnwrap(CamperRoomCatalog.furniture("photo_frame.landscape"))
        let onWall = try XCTUnwrap(cam.project(CV3(120, 50, 0), viewport: viewport, layout: camper))
        let hung = try XCTUnwrap(CamperRoomPick.spot(for: frame, ray: cam.ray(onWall, viewport: viewport, layout: camper), layout: camper))
        XCTAssertEqual(hung.w, .back)
        XCTAssertEqual(hung.row, 1)
        XCTAssertNil(CamperRoomPick.spot(for: frame, ray: (CV3(50, 40, 50), CV3(0, 1, 0)), layout: camper))
    }

    // MARK: カメラ

    /// 二度押し: 離れていれば押した所へ寄り、寄っていれば初めの向きへ戻る
    func testDoubleTapZoomsInAndBack() {
        let start = CamperRoomCamera.overview(camper)
        let near = start.doubleTapped(floor: CV3(40, 0, 30), layout: camper)
        XCTAssertEqual(near.zoom, CamperRoomCamera.doubleTapZoom, accuracy: 0.001)
        XCTAssertEqual(near.target.x, 40, accuracy: 0.001)
        XCTAssertEqual(near.target.z, 30, accuracy: 0.001)
        XCTAssertTrue(near.differs(from: start))
        // 部屋の外を押しても、狙いは部屋の中
        let outside = start.doubleTapped(floor: CV3(-500, 0, 999), layout: camper)
        XCTAssertEqual(outside.target.x, 0, accuracy: 0.001)
        XCTAssertEqual(outside.target.z, camper.size.z, accuracy: 0.001)
        XCTAssertEqual(near.doubleTapped(floor: nil, layout: camper), start)
        XCTAssertFalse(start.differs(from: CamperRoomCamera.overview(camper)))
        var turned = start
        turned.yaw += 10
        XCTAssertTrue(turned.differs(from: start))
    }

    /// 二度押しの見分け（0.35 秒・44pt）
    func testDoubleTapTiming() {
        let t = Date()
        XCTAssertTrue(CamperRoomTaps.isDouble(last: t, lastPoint: CGPoint(x: 100, y: 100), now: t.addingTimeInterval(0.2), point: CGPoint(x: 110, y: 104)))
        XCTAssertFalse(CamperRoomTaps.isDouble(last: t, lastPoint: CGPoint(x: 100, y: 100), now: t.addingTimeInterval(0.5), point: CGPoint(x: 100, y: 100)))
        XCTAssertFalse(CamperRoomTaps.isDouble(last: t, lastPoint: CGPoint(x: 100, y: 100), now: t.addingTimeInterval(0.1), point: CGPoint(x: 200, y: 100)))
    }

    /// 持ち上げた家具を画面の端へ運ぶと、寄っているときだけカメラが少し追う（真ん中・寄っていないときは追わない）
    func testCameraFollowsAtTheEdge() throws {
        let viewport = CGSize(width: 390, height: 440)
        let start = CamperRoomCamera.overview(camper)
        XCTAssertNil(start.following(CGPoint(x: 2, y: 200), viewport: viewport, layout: camper))
        var near = start
        near.zoom = 3
        XCTAssertNil(near.following(CGPoint(x: 195, y: 220), viewport: viewport, layout: camper))
        let left = try XCTUnwrap(near.following(CGPoint(x: 4, y: 220), viewport: viewport, layout: camper))
        let right = try XCTUnwrap(near.following(CGPoint(x: 386, y: 220), viewport: viewport, layout: camper))
        XCTAssertNotEqual(left.target, near.target)
        // 左と右で逆へ追う
        let dl = left.target - near.target, dr = right.target - near.target
        XCTAssertLessThan(dl.x * dr.x + dl.z * dr.z, 0)
        // 部屋の外へは出ない
        var edge = near
        for _ in 0..<500 { edge = edge.following(CGPoint(x: 0, y: 0), viewport: viewport, layout: camper) ?? edge }
        XCTAssertGreaterThanOrEqual(edge.target.x, 0)
        XCTAssertLessThanOrEqual(edge.target.x, camper.size.x)
        XCTAssertGreaterThanOrEqual(edge.target.z, 0)
        XCTAssertLessThanOrEqual(edge.target.z, camper.size.z)
    }

    // MARK: 接写の一覧

    /// 板と別種の 104 点を 8 点ずつ、漏れも重なりもなく頁に分ける
    func testContactSheetPagesCoverTheBoard() {
        XCTAssertEqual(CamperRoomContactPages.count, 13)
        let ids = (0..<CamperRoomContactPages.count).flatMap { CamperRoomContactPages.page($0).map(\.id) }
        XCTAssertEqual(ids, CamperRoomCatalog.board.map(\.id))
        XCTAssertTrue(CamperRoomContactPages.page(99).isEmpty)
        XCTAssertEqual(CamperRoomContactPages.marker(mood: .night, page: 2), "contact-ready night 3/13")
    }
}

/// 新しい家具の印と手引き（退会で消すのは @MainActor の `AccountLocalData`）
@MainActor
final class CamperRoomSeenTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "camper.room.usability.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: 新しい家具の印

    /// 初めては全部見たにする（印が並ばない）。後から届いた家具だけが新しい。見たら消える。退会で消える
    func testNewFurnitureMarks() async {
        let d = defaults()
        let store = CamperRoomSeenStore(userId: "u1", defaults: d)
        XCTAssertNil(store.load())
        XCTAssertEqual(store.news(owned: ["a", "b"]), [])
        XCTAssertEqual(store.load(), ["a", "b"])
        XCTAssertEqual(store.news(owned: ["a", "b", "c"]), ["c"])
        store.markSeen(["c"])
        XCTAssertEqual(store.news(owned: ["a", "b", "c"]), [])
        // 人ごと
        XCTAssertEqual(CamperRoomSeenStore(userId: "u2", defaults: d).news(owned: ["z"]), [])
        // 名前の無い人は覚えない
        XCTAssertNil(CamperRoomSeenStore(userId: nil, defaults: d).load())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AccountLocalData.remove(userId: "u1", username: nil, defaults: d, draftDirectory: dir, offlineTripsRoot: dir, passRoot: dir)
        XCTAssertNil(store.load())
    }

    /// 手引きは端末に 1 回
    func testCoachShowsOnce() async {
        let d = defaults()
        XCTAssertTrue(CamperRoomCoach.shouldShow(d))
        CamperRoomCoach.done(d)
        XCTAssertFalse(CamperRoomCoach.shouldShow(d))
        XCTAssertEqual(CamperRoomView.coachLines.count, 3)
    }
}
