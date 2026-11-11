import XCTest
@testable import JourneyPhoto

/// とおまわり号の中を減らした（2026-11-11 owner「遠回り号の中も減らしていいよ。あと家具も減らしていいよ。最大 100 個くらい」）。
/// 部屋は 2〜3 つ、家具は 85 点。隠した部屋・消した家具の保存は書き換えない
final class CamperRoomTrimTests: XCTestCase {

    /// 隠した部屋（前の張り出し・軒先・荷物室・ロフト・運転席の上）を頼まれたら車の部屋を開く。入れる部屋はそのまま開く
    func testHiddenRoomOpensTheCarRoom() {
        for stage in CamperStage.allCases {
            let rooms = CamperRoomKind.rooms(stage)
            for kind in CamperRoomKind.allCases {
                let opened = CamperRoomKind.opening(kind, stage: stage)
                XCTAssertTrue(rooms.contains(opened), "\(stage) \(kind) → \(opened) は入れない部屋")
                XCTAssertEqual(opened, rooms.contains(kind) ? kind : .car, "\(stage) \(kind)")
            }
            // トレーラーの無い段でトレーラーを頼まれても車の部屋
            if stage != .trailer { XCTAssertEqual(CamperRoomKind.opening(.trailer, stage: stage), .car) }
        }
    }

    /// 隠した部屋から車の部屋へ移っても、部屋は空にならない（保存の無い人は最初の並び）。落ちずに組める
    func testCarRoomIsNotEmptyWhenFallingBack() {
        let d = UserDefaults(suiteName: "CamperRoomTrimTests.\(UUID().uuidString)")!
        let store = CamperRoomStore(userId: "u1", defaults: d)
        for stage in CamperStage.allCases {
            let layout = CamperRoomLayout.make(CamperRoomKind.opening(.loft, stage: stage), stage: stage)
            XCTAssertEqual(layout.kind, .car)
            let doc = store.load(layout)
            let owned = CamperRoomCatalog.owned(CamperStats(), CamperRoomStats())
            let shown = CamperRoomEditor(doc: doc, layout: layout).shown(owned: owned)
            XCTAssertGreaterThanOrEqual(shown.all.count, 4, "\(stage) の車の部屋が空")
            XCTAssertFalse(CamperRoomBuilder.build(layout, doc: shown).items.isEmpty, "\(stage)")
        }
    }

    /// 隠した部屋に置いた家具と、消した組み合わせの家具（id「分類.x000」）は、保存から消さない（戻せば現れる）。
    /// 部屋には持っている家具だけが出る
    func testHiddenRoomAndRemovedFurnitureStayInTheSave() throws {
        let d = UserDefaults(suiteName: "CamperRoomTrimTests.\(UUID().uuidString)")!
        let store = CamperRoomStore(userId: "u1", defaults: d)
        let loft = CamperRoomLayout.make(.loft, stage: .camper)
        var hidden = CamperRoomDocument(room: .loft)
        hidden.upsert(.floor("a", "seating.floor_cushion", x: 0, z: 0))
        store.save(hidden)
        let car = CamperRoomLayout.make(.car, stage: .camper)
        var doc = CamperRoomRules.starterDocument(car)
        doc.upsert(.floor("b", "seating.x012", x: 6, z: 5))
        store.save(doc)
        // 部屋を減らした後も、隠した部屋の保存はそのまま読める
        XCTAssertEqual(store.load(loft).all.map(\.k), ["seating.floor_cushion"])
        let saved = store.load(car)
        XCTAssertTrue(saved.all.contains { $0.k == "seating.x012" }, "消した家具が保存から消えた")
        XCTAssertNil(CamperRoomCatalog.furniture("seating.x012"))
        let owned = CamperRoomCatalog.owned(CamperStats(), CamperRoomStats())
        let shown = CamperRoomEditor(doc: saved, layout: car).shown(owned: owned)
        XCTAssertFalse(shown.all.contains { $0.k == "seating.x012" }, "消した家具が部屋に出ている")
        XCTAssertEqual(shown.all.count, saved.all.count - 1)
    }

    /// 残した張り出しの名前は「張り出し」（前と後ろの区別が要らなくなった）
    func testSlideOutName() {
        XCTAssertEqual(CamperRoomKind.sideRear.name, L("張り出し", "Slide-out"))
    }
}
