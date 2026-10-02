import XCTest
@testable import JourneyPhoto

/// 選んでいるタブの色（`TabBarStyle`）。**真鍮で、中身の白（`WebTheme.foreground`）ではない**
/// （owner の好み 2026-09-29。TabView の tint が中身の白に負けていた疑い・2026-10-02）
@MainActor
final class TabBarStyleTests: XCTestCase {

    func testSelectedTabIsBrass() async {
        XCTAssertEqual(TabBarStyle.selectedHex, 0xC9A66B, "選んでいるタブが真鍮でない")
        XCTAssertEqual(TabBarStyle.selectedHex, BrandPalette.accent)
        XCTAssertNotEqual(TabBarStyle.selectedHex, 0xFFFFFF, "選んでいるタブが白（中身の tint）になっている")
    }

    /// 🔴 **起動時に色を書いている。** 呼び出しを消すと、上の色の試験は通ったまま札が白に戻る
    func testAppLaunchAppliesTheTabBarStyle() async {
        // 起動は設定（Info.plist の値）を読むので、試験の値を渡す
        let saved = AppConfig.testOverrides
        defer { AppConfig.testOverrides = saved }
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPApiBaseURL": "https://api.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
        let before = TabBarStyle.appliedCount
        _ = JourneyPhotoApp()
        XCTAssertEqual(TabBarStyle.appliedCount, before + 1,
                       "起動（JourneyPhotoApp.init）で TabBarStyle.apply を呼んでいない")
    }

    /// 🔴 **白の tint はタブの子（NavigationStack）そのものに付けない**（2026-10-02）。
    /// iOS 18 以降の TabView は選んでいるタブの子の tint を札の選択色に使うと見られ、
    /// 付けると「マイページ」などの選んでいる札が白に戻る（iOS 26 の絵）。
    /// NavigationStack の中（根の画面）に付ける
    func testWhiteTintIsInsideTheNavigationStacks() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/App/RootView.swift"),
                              encoding: .utf8)
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var onTabChild = 0
        var inside = 0
        for (i, line) in lines.enumerated() where line == ".tint(WebTheme.foreground)" && i > 0 {
            if lines[i - 1] == "}" { onTabChild += 1 }
            if i + 1 < lines.count, lines[i + 1] == "}" { inside += 1 }
        }
        XCTAssertEqual(onTabChild, 0, "白の tint が NavigationStack の外（タブの子）に付いている——札が白になる")
        XCTAssertEqual(inside, 4, "4つのタブの根の画面に白の tint が付いていない")
    }
}
