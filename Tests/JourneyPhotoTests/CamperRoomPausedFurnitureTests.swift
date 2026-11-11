import XCTest
@testable import JourneyPhoto

/// 一時的に下げた家具（`CamperRoomCatalog.paused`・2026-11-06）。外すのは入口（`all`）だけで、形のコードも保存した部屋も消さない
final class CamperRoomPausedFurnitureTests: XCTestCase {

    func testPausedFurnitureAreOnTheBoardButLeaveEveryList() {
        let paused = CamperRoomCatalog.paused
        // 2026-11-06 の 8 点 ＋ 2026-11-11 の似た家具 11 点
        XCTAssertEqual(paused.count, 19)
        for id in paused {
            // 板の行は残る（戻すときは paused から id を消すだけ）
            XCTAssertTrue(CamperRoomCatalog.board.contains { $0.id == id }, id)
            XCTAssertFalse(CamperRoomCatalog.all.contains { $0.id == id }, "\(id) が一覧に残っている")
            XCTAssertNil(CamperRoomCatalog.furniture(id), id)
            XCTAssertFalse(CamperRoomCatalog.available.contains { $0.id == id }, id)
        }
    }

    func testStartersAndServerPiecesAndFramesAreNeverPaused() {
        for f in CamperRoomCatalog.board where CamperRoomCatalog.paused.contains(f.id) {
            XCTAssertFalse(f.unlock.isStarter, "\(f.id) は最初から持つ家具（新しい利用者の最初の部屋が寂しくなる）")
            XCTAssertTrue(f.unlock.isAvailable, "\(f.id) はもともと近日の家具（下げる意味が無い）")
            XCTAssertEqual(f.photoSlots, 0, "\(f.id) は写真を飾る家具（この部屋の主役）")
        }
        // 2026-11-06 の「部品が少ない順」では、平らな敷物は部品が少ないのが当たり前なので選ばなかった。
        // 2026-11-11 の「似た家具」では、似た丸い敷物（毛足の丸・楕円の輪）の片方だけを下げた。例外はこの 1 点だけ
        let rugException = "room_rug.shag_round"
        XCTAssertTrue(CamperRoomCatalog.paused.contains(rugException))
        for f in CamperRoomCatalog.board where CamperRoomCatalog.paused.contains(f.id) && f.id != rugException {
            XCTAssertFalse(f.isRug, f.id)
        }
    }

    func testEveryCategoryStillHasFurnitureAfterPausing() {
        for c in CamperRoomCategory.allCases {
            XCTAssertFalse(CamperRoomCatalog.all.filter { $0.category == c }.isEmpty, "\(c) の家具が無くなった")
        }
    }

    func testFormsAreKeptSoTheyCanComeBack() {
        for id in CamperRoomCatalog.paused {
            XCTAssertNotNil(CamperRoomFurnitureModels.mesh(id), "\(id) の形のコードが消えている（戻せない）")
        }
    }

    /// すでに置いた家具は、下げている間は部屋に出ないが、保存した部屋には残る（戻すとそのまま現れる）
    func testPlacedPausedFurnitureIsHiddenButNotErasedFromTheSavedRoom() {
        let camper = CamperRoomLayout.make(.car, stage: .camper)
        let id = "wall_shelf.spice_rack"
        XCTAssertTrue(CamperRoomCatalog.paused.contains(id))
        var doc = CamperRoomRules.starterDocument(camper)
        doc.upsert(.wall("p", id, .back, c: 8, row: 1))
        let editor = CamperRoomEditor(doc: doc, layout: camper)
        let owned = CamperRoomCatalog.owned(CamperStats(), CamperRoomStats())
        XCTAssertFalse(owned.contains(id))
        XCTAssertFalse(editor.shown(owned: owned).all.contains { $0.k == id }, "下げた家具が部屋に出ている")
        XCTAssertTrue(editor.doc.all.contains { $0.k == id }, "保存した部屋から消えた")
    }
}
