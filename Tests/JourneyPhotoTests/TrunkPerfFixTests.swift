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

    /// 1. 型の一覧・特別なトランクの一覧は、生の絵（`drawingGroup` が送る 1 コマごとに描き直される）を並べない
    func testModelListsUseStillImages() throws {
        let models = try source("Features/Trunk/TrunkModelsView.swift")
        XCTAssertEqual(models.components(separatedBy: "TrunkFigureStill(").count - 1, 2, "型の一覧と特別なトランクの両方で画素の絵を使う")
        XCTAssertFalse(models.contains("TrunkFigureFit("), "特別なトランクの一覧に生の絵が戻っている")
        XCTAssertFalse(models.contains("                TrunkFigure(model:"), "型の一覧に生の絵が戻っている")
        XCTAssertTrue(models.contains("LazyVStack(spacing: 20) {\n                    ForEach(TrunkModel.pro)"), "画面の外の札まで作っている")
        let still = try source("Features/Trunk/TrunkStill.swift")
        // 画面から外れたら手放す・画面の倍率で描く・塗るのは主スレッドの外
        XCTAssertTrue(still.contains(".onDisappear {\n            image = nil"), "画面から外れても絵を持ち続ける")
        XCTAssertTrue(still.contains("let scale = max(1, displayScale)"), "画面の倍率で描いていない")
        XCTAssertTrue(still.contains("Task.detached(priority: .userInitiated)"), "絵を主スレッドで塗っている")
    }

    /// 1. 余白を付けた絵の画素が整数になる（端数だと置くときに縮んで、生の絵と画素がずれる）。幅 140（型の一覧）と 300（特別なトランク）・1〜3 倍
    func testStillPaddingLandsOnWholePixels() {
        for width in [140.0, 300.0] {
            let k = width / TrunkLooks.canvasWidth
            for scale in [1.0, 2.0, 3.0] {
                for pad in [TrunkStillLayout.padTop, TrunkStillLayout.padSide, TrunkStillLayout.padBottom] {
                    let px = pad * k * scale
                    XCTAssertEqual(px, px.rounded(), accuracy: 1e-9, "幅 \(width)・\(scale) 倍で余白 \(pad) が \(px) 画素（端数）")
                }
            }
        }
        // 影（下へ 30＋ぼかし 25）より余白が広い
        XCTAssertGreaterThanOrEqual(TrunkStillLayout.padBottom, 30 + 25 * 2)
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

    /// 3. 回す箱の絵は主スレッドの外で塗り切ってから渡し、2 回目は使い回す
    func testSpinTexturesAreSettledOffMainAndKept() throws {
        let spin = try source("Features/Trunk/TrunkSpinViewer.swift")
        XCTAssertTrue(spin.contains("textures = await " + "TrunkTextures" + ".settled(made)"), "正面の絵を塗らずに SceneKit に渡している")
        XCTAssertTrue(spin.contains("boxFaces = await " + "TrunkTextures" + ".settled(box)"), "側面などの絵を塗らずに SceneKit に渡している")
        XCTAssertTrue(spin.contains("if let kept = " + "TrunkTextures" + ".kept(key) {"), "2 回目に開いても絵を描き直している")
        XCTAssertTrue(spin.contains("TrunkTextures" + ".keep(key, faces: textures, box: boxFaces)"))
        XCTAssertTrue(spin.contains("UIApplication.didReceiveMemoryWarningNotification"), "メモリが足りないときに手放さない")
    }

    /// 測定専用の差し替えは、Release では必ず空（ふだんの描き方を変えない）
    func testDiagIsEmptyWithoutTheFlag() {
        UserDefaults.standard.removeObject(forKey: PreviewSession.trunkDiagKey)
        XCTAssertTrue(PreviewSession.trunkDiag.isEmpty)
    }
}
