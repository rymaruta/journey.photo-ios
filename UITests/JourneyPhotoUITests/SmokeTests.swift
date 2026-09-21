import XCTest

/// 起動スモーク。
///
/// **単体テストでは捕まらないものを見る。** アプリの実体を起動して、
/// 同意画面 → タブ、と実際に触る。ここでしか捕まらないのは:
///
///   - Info.plist の値が欠けていて `AppConfig` が `fatalError` で落ちる
///   - `@EnvironmentObject` を配り忘れていて描画時に落ちる
///     （`Tools/check-swift-refs.js` は静的に見るが、取りこぼす）
///   - `Amplify` の初期化が実機で投げる
///   - タブの1つが body の型検査を通っても描けない
///
/// Web 側が「実ブラウザのスモーク（Chromium）」を必ず通しているのと同じ役目
/// （`photo-gallery/CLAUDE.md`）。**通信は当てにしない**——staging には
/// 写真が1枚も無いので、中身ではなく「落ちずに描けたか」だけを見る。
final class SmokeTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchesAndEveryTabDraws() {
        let app = XCUIApplication()
        // **毎回まっさらから。** 同意の記録が残っていると初回の道を通らない
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launch()

        // 同意画面 → タブ
        // **名札で指す。** 並び順で掴むと「利用規約」のリンクを押して
        // Safari が開き、以後の判定が全部無意味になる
        let agree = app.buttons["legal.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 30), "起動画面が出ない（落ちている可能性）")
        agree.tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "タブが出ない")

        // **全部のタブを踏む。** 描けないタブはここで落ちる
        for index in 0..<tabBar.buttons.count {
            let tab = tabBar.buttons.element(boundBy: index)
            guard tab.exists else { continue }
            tab.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10),
                          "タブ \(index) を開いてアプリが落ちた")
        }
    }
}
