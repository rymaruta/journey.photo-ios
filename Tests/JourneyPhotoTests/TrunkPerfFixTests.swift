import XCTest
@testable import JourneyPhoto

/// 旅のトランクの重さの直し（2026-11-11・owner「旅のトランク重すぎる」・run 992 / 997 の数）。
/// 見た目が前と同じか・重さが減ったかは Mac の UI テスト（`testTrunkStillMatchesLive`・`testTrunkSpinMatchesBefore`・
/// `testMeasuresTrunk…`）が画素と数で見る。ここは作りが戻っていないかを見る
final class TrunkPerfFixTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 2. 回す箱は、角度・絵が変わったときだけ描く（止まっている間に毎秒 60 コマ描かない）
    func testSpinBoxDrawsOnlyWhileMoving() throws {
        let medal = try source("Features/Profile/MedalViewerView.swift")
        XCTAssertTrue(medal.contains("view.rendersContinuously = Self.rendersContinuously(for: shape)"))
        XCTAssertTrue(medal.contains("guard case .box = shape else { return true }\n        return PreviewSession.trunkDiag.contains(\"spincont\")"),
                      "箱が描き続ける作りに戻っている")
        XCTAssertTrue(medal.contains("if isBox, velocity == 0 { return }"), "止まりきった箱の角度を毎コマ書き換えている")
        XCTAssertTrue(medal.contains("if isBox, abs(velocity) < Self.boxStopSpeed { velocity = 0 }"), "箱の惰性が止まらない")
        XCTAssertFalse(medal.contains("view.rendersContinuously = true"))
    }

    /// 3. 回す箱の絵は、トランクの画面を開いたときに先に作り（主スレッドの外で塗る）、回す画面では使い回す
    func testSpinTexturesArePrewarmedAndKept() throws {
        let trunk = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(trunk.contains(".task(id: spinKey) {"), "トランクの画面で回す箱の絵を先に作っていない")
        XCTAssertTrue(trunk.contains("await " + "TrunkTextures" + ".prewarm(spinKey)"))
        XCTAssertTrue(trunk.contains("if !showSpin, !showStick, !showPaywall { " + "TrunkTextures" + ".forget() }"), "戻っても絵を手放さない")
        let spin = try source("Features/Trunk/TrunkSpinViewer.swift")
        XCTAssertTrue(spin.contains("if let kept = " + "TrunkTextures" + ".kept(key) {"), "先に作った絵を使っていない")
        XCTAssertTrue(spin.contains("let painted = await TrunkStill.settle("), "先に作る絵を主スレッドで塗っている")
        XCTAssertTrue(spin.contains("UIApplication.didReceiveMemoryWarningNotification"), "メモリが足りないときに手放さない")
    }

    /// 測定専用の差し替えは、Release では必ず空（ふだんの描き方を変えない）
    func testDiagIsEmptyWithoutTheFlag() {
        UserDefaults.standard.removeObject(forKey: PreviewSession.trunkDiagKey)
        XCTAssertTrue(PreviewSession.trunkDiag.isEmpty)
    }
}
