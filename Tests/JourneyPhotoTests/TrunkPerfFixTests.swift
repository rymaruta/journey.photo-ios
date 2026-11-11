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
        // 止まった箱は表示の刻み（CADisplayLink）も止め、触る・向き・裏返すで再び動かす
        XCTAssertTrue(medal.contains("link.isPaused = true"), "止まっていても毎コマ主スレッドを起こしている")
        XCTAssertEqual(medal.components(separatedBy: "        wake()\n").count - 1, 3, "向きのボタン・裏返す・指で触るで刻みを動かさない")
        XCTAssertTrue(medal.contains("            dragging = true\n            wake()"), "指で触っても刻みを動かさない")
    }

    /// 3. 回す箱の絵は、2 回目に開いたら使い回す。トランクの画面では先に作らない（2026-11-11 判断・先に作ると
    /// トランクの画面のメモリが +80MB だった）。トランクの画面から戻ったら手放す
    func testSpinTexturesAreKeptButNotPrewarmed() throws {
        let spin = try source("Features/Trunk/TrunkSpinViewer.swift")
        XCTAssertTrue(spin.contains("if let kept = " + "TrunkTextures" + ".kept(key) {"), "2 回目に開いても絵を描き直している")
        XCTAssertTrue(spin.contains("if let textures, let boxFaces { " + "TrunkTextures" + ".keep(key, faces: textures, box: boxFaces) }"),
                      "描いた絵を取っておかない")
        XCTAssertTrue(spin.contains("UIApplication.didReceiveMemoryWarningNotification"), "メモリが足りないときに手放さない")
        XCTAssertFalse(spin.contains("func prewarm("), "回す画面の絵を先に作っている（メモリが戻らない）")
        let trunk = try source("Features/Trunk/TrunkView.swift")
        XCTAssertFalse(trunk.contains(".prewarm("), "トランクの画面で回す画面の絵を先に作っている")
        XCTAssertTrue(trunk.contains("if !showSpin, !showStick, !showPaywall { " + "TrunkTextures" + ".forget() }"), "戻っても絵を手放さない")
        // 人のトランクの画面も同じく、離れたら手放す（2026-11-11 確かめ役の指摘）
        let theirs = try source("Features/Trunk/TheirTrunkView.swift")
        XCTAssertTrue(theirs.contains("if !showSpin { " + "TrunkTextures" + ".forget() }"), "人のトランクから離れても絵を手放さない")
    }

    /// 4. 回す箱の正面の貼り絵には胴の影を描かない（4 隅にしか入らず面の角の丸みで描かれない。塗る時間 約 0.9→0.28 秒・run 1029）。
    /// 型の一覧・ふた・入口の札などほかの絵は影を描く（既定 true）
    func testSpinFrontSkipsOnlyTheBodyShadow() throws {
        let spin = try source("Features/Trunk/TrunkSpinViewer.swift")
        XCTAssertTrue(spin.contains(".environment(\\.trunkBodyShadow, PreviewSession.trunkDiag.contains(\"spinshadow\"))"),
                      "回す箱の正面に胴の影を塗っている（1 回目に開く間が長い）")
        XCTAssertEqual(spin.components(separatedBy: "trunkBodyShadow").count - 1, 1, "正面のほかの面にも影の切り替えを入れている")
        let box = try source("Features/Trunk/TrunkBoxView.swift")
        XCTAssertTrue(box.contains("let diag: Set<String> = castsShadow ? measured : measured.union([\"noshadow\"])"),
                      "影の切り替えが胴の仕上げに届いていない")
        XCTAssertTrue(box.contains("static let defaultValue = true"), "ほかの絵の影まで消えている")
    }

    /// 測定専用の差し替えは、Release では必ず空（ふだんの描き方を変えない）
    func testDiagIsEmptyWithoutTheFlag() {
        UserDefaults.standard.removeObject(forKey: PreviewSession.trunkDiagKey)
        XCTAssertTrue(PreviewSession.trunkDiag.isEmpty)
    }
}
