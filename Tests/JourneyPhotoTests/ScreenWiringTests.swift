import XCTest
@testable import JourneyPhoto

/// 🔴 **画面が判定の関数につながっていること**（2026-10-02 のレビュー）。
///
/// 判定（`StoryPlayback.timeUp`・`StoryReel.faceLook`・`PhotoMapView.listEmpty` …）は
/// それぞれの試験で縛っているが、**画面側のつなぎを外しても**それらは通ったままになる。
/// 画面は Linux で描けないので、ソースに**つなぎの呼び出しが残っていること**を見る。
/// 書き方を変えたら、ここも合わせて直す（消したら落ちるのが目的）
final class ScreenWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// 読み上げ: 自動で送らない判定に読み上げの状態を渡す・操作を出す
    func testStoryViewerWiresVoiceOver() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("@Environment(\\.accessibilityVoiceOverEnabled)"))
        XCTAssertEqual(count("voiceOver: voiceOverOn", in: viewer), 2,
                       "時計（timeUp）と動画の終わり（mediaEnded）の両方に読み上げの状態を渡していない")
        XCTAssertTrue(viewer.contains(".onChange(of: voiceOverOn) { _, _ in settlePendingEnd() }"),
                      "読み上げを切っても控えた動画の終わりで進まない")
        XCTAssertTrue(viewer.contains(#".accessibilityAction(named: L("次へ", "Next")) { forward() }"#))
        XCTAssertTrue(viewer.contains(#".accessibilityAction(named: L("前へ", "Previous")) { voiceOverBack() }"#))
        XCTAssertTrue(viewer.contains("StoryPlayback.voiceOverPrevious("))
        XCTAssertTrue(viewer.contains(".accessibilityAction(.escape)"))
        XCTAssertEqual(count("StoryPlayback.forward(", in: viewer), 1)
        XCTAssertTrue(viewer.contains(".onTapGesture { forward() }"),
                      "右を押したときと読み上げの「次へ」が別の判定になっている")
    }

    /// 動きを減らす: 面の見せ方は `faceLook` の答えだけで描く
    func testStoryReelWiresReduceMotion() throws {
        let reel = try source("Features/Stories/StoryReelView.swift")
        XCTAssertTrue(reel.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(reel.contains("StoryReel.faceLook(minX: minX, width: width, reduceMotion: reduceMotion)"))
        XCTAssertTrue(reel.contains(".rotation3DEffect(.degrees(look.angle)"))
        XCTAssertTrue(reel.contains(".offset(x: look.offsetX)"))
        XCTAssertTrue(reel.contains(".opacity(look.opacity)"))
        XCTAssertFalse(reel.contains("StoryReel.cubeAngle("), "faceLook を通らずに回している")
        // ばねは「動きを減らす」を見る1か所（settleAnimation）だけ
        XCTAssertEqual(count(".spring(", in: reel), 1, "ばねを settleAnimation の外で使っている")
        XCTAssertTrue(reel.contains("reduceMotion ? .easeOut(duration: 0.2) : .spring("))
    }

    /// 地図のリスト: 空と失敗を `listEmpty` で分けている
    func testMapListWiresListEmpty() throws {
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("switch Self.listEmpty(loadFailed: model.loadFailed, photosEmpty: model.photos.isEmpty,"))
    }

    /// ログアウト: メニューと設定の両方が共有の印（`AuthStore.startSigningOut`）を通る
    func testSignOutButtonsShareTheGate() throws {
        for path in ["Features/Common/SiteMenuView.swift", "Features/Settings/SettingsView.swift"] {
            let screen = try source(path)
            XCTAssertTrue(screen.contains("auth.startSigningOut {"), "\(path) が共有の印を通らずにログアウトしている")
            XCTAssertFalse(screen.contains("await auth.signOut()"), "\(path) が直にログアウトしている")
        }
    }

    /// ストーリー: 選んだ写真は上限時間つきで読む（`StorySimpleRules.readPicks`）
    func testStoryComposerReadsPicksWithTimeout() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("StorySimpleRules.readPicks("), "上限時間を通らずに写真を読んでいる")
        XCTAssertEqual(count("loadTransferable(", in: composer), 1, "readPicks の外で写真を読んでいる")
    }
}
