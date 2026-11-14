import XCTest
@testable import JourneyPhoto

/// とおまわり号の中の ⟲ ⟳（2026-11-14・人間工学の点検 6・WCAG 2.5.7）: 指で引かなくても部屋を回せる。
/// 1 回で 30°、読み上げの「右へ回す・左へ回す」と同じ値と同じ式
final class CamperRoomTurnTests: XCTestCase {

    private let camper = CamperRoomLayout.make(.car, stage: .camper)

    /// ⟳ で向きが 30° 変わり、⟲ で元に戻る。ほかの値（見下ろし・寄り・狙う点）は変えない
    func testTurnRightThenLeftReturns() {
        let start = CamperRoomCamera.overview(camper)
        let right = start.turned(by: CamperRoomTurn.right.degrees)
        XCTAssertEqual(right.yaw - start.yaw, 30, accuracy: 0.001)
        XCTAssertEqual(right.pitch, start.pitch)
        XCTAssertEqual(right.zoom, start.zoom)
        XCTAssertEqual(right.target, start.target)
        XCTAssertTrue(right.differs(from: start), "30° 回しても「向きを戻す」が出ない")
        let back = right.turned(by: CamperRoomTurn.left.degrees)
        XCTAssertEqual(back.yaw, start.yaw, accuracy: 0.001)
        XCTAssertFalse(back.differs(from: start))
    }

    /// ボタンの値・印・名前（読み上げの操作と同じ）
    func testTurnButtonsMatchVoiceActions() {
        XCTAssertEqual(CamperRoomCamera.turnStep, 30)
        XCTAssertEqual(CamperRoomTurn.allCases, [.left, .right], "⟲ を左、⟳ を右に並べる")
        XCTAssertEqual(CamperRoomTurn.right.degrees, 30)
        XCTAssertEqual(CamperRoomTurn.left.degrees, -30)
        XCTAssertEqual(CamperRoomTurn.right.symbol, "arrow.clockwise")
        XCTAssertEqual(CamperRoomTurn.left.symbol, "arrow.counterclockwise")
        XCTAssertEqual(CamperRoomTurn.right.id, "camper.room.turn.right")
        XCTAssertEqual(CamperRoomTurn.left.id, "camper.room.turn.left")
    }

    /// 回せる範囲の端（横 ±90°）では止まり、その向きのボタンは押せない。反対の向きは押せる
    func testTurnStopsAtRangeEdge() {
        var c = CamperRoomCamera.overview(camper)
        var taps = 0
        while c.canTurn(by: CamperRoomTurn.right.degrees), taps < 20 {
            c = c.turned(by: CamperRoomTurn.right.degrees)
            taps += 1
        }
        XCTAssertEqual(c.yaw, CamperRoomCamera.yawRange.upperBound, accuracy: 0.001)
        XCTAssertLessThan(taps, 20)
        XCTAssertFalse(c.canTurn(by: CamperRoomTurn.right.degrees))
        XCTAssertTrue(c.canTurn(by: CamperRoomTurn.left.degrees))
        XCTAssertEqual(c.turned(by: CamperRoomTurn.right.degrees), c, "端でもう一度押しても動かない")
    }

    /// 画面: 上の札の並びに ⟲ ⟳ を置き、読み上げの操作と同じ `turn(_:)` を通す。引いて回す操作も残す
    func testRoomViewHasTurnButtonsAndKeepsDrag() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Camper/Room/CamperRoomView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("ForEach(CamperRoomTurn.allCases, id: \\.self) { direction in"), "上の並びに ⟲ ⟳ が無い")
        XCTAssertTrue(text.contains("return Button { turn(direction) } label: {"), "⟲ ⟳ が読み上げと同じ turn(_:) を通らない")
        XCTAssertTrue(text.contains(".accessibilityAction(named: CamperRoomTurn.right.label) { turn(CamperRoomTurn.right) }"))
        XCTAssertTrue(text.contains(".accessibilityAction(named: CamperRoomTurn.left.label) { turn(CamperRoomTurn.left) }"))
        XCTAssertTrue(text.contains("camera = camera.turned(by: direction.degrees)"))
        XCTAssertTrue(text.contains("camera = g.camera.dragged(dx: dx, dy: dy)"), "指で引いて回す操作が消えた")
        XCTAssertFalse(text.contains("指一本で部屋を回し、"), "下の説明が長いまま（回すのはボタンで分かる）")
    }
}
