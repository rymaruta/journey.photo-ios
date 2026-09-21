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

        // **数を決め打つ。** `0..<count` を回すだけだと、`count` が 0 でも
        // ループが1周も回らずに緑になる（何も触っていないのに合格）
        let expected = 5      // ホーム / 探す / 投稿 / 旅 / マイページ
        XCTAssertEqual(tabBar.buttons.count, expected, "タブの数が違う")

        // **中央（投稿）は画面を持たない。** 押すとシートが出てタブは
        // 元へ戻るので、ほかと同じ判定（題が描けたか）は当たらない
        let postTab = 2

        for index in 0..<expected where index != postTab {
            let tab = tabBar.buttons.element(boundBy: index)
            XCTAssertTrue(tab.exists, "タブ \(index) が無い")
            tab.tap()

            // **「生きているか」では見ない。** `runningForeground` は
            // 呼んだ瞬間に真なので、固い落ち方しか捕まらない。
            // どのタブも `navigationTitle` を持つので、**題が描けたか**を見る
            // ——描けないタブはここで落ちる
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15),
                          "タブ \(index) の中身が描けない")
        }

        // **中央のタブも触る。** 触らないと「押しても何も出ない」が
        // 見張られない（投稿の入口はここだけになった）
        tabBar.buttons.element(boundBy: postTab).tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 15)
                      || app.buttons["投稿"].waitForExistence(timeout: 5),
                      "投稿の2択が出ない")
    }
}
