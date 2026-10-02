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
}
