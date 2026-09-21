import XCTest

/// 各画面を撮る。
///
/// **見た目は Linux では一切確かめられない。** 手元にあるのは `Shims/` の
/// 模型で、修飾子は素通し＝配置も色も文字の折り返しも再現しない。
/// 実際に描かれた絵を見られるのは、CI の macOS ランナーで動く
/// シミュレータだけ。ここで撮って `.xcresult` に貼り、ワークフロー側が
/// 取り出す。
///
/// **落とさない。** 撮影は「確かめる」ものではなく「見る」ためのもの。
/// 1画面出なかったくらいで赤くすると、本来の見張り（`SmokeTests`）の
/// 結果が読めなくなる。出なかったところは撮らずに先へ進む。
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        // **既定は「落ちた時だけ残す」。** これを付けないと緑の回には
        // 1枚も残らない（撮ったつもりで何も無い、がいちばん時間を捨てる）
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCapturesEveryScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) {
            shoot(app, "01-同意画面")
            agree.tap()
        }

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20) else {
            shoot(app, "02-タブが出なかった")
            return
        }

        let names = ["ギャラリー", "さがす", "お知らせ", "マイページ"]
        for (index, name) in names.enumerated() where index < tabBar.buttons.count {
            tabBar.buttons.element(boundBy: index).tap()
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
            // **少し待ってから撮る。** 写真は通信で来るので、描いた直後は
            // 枠だけの絵になる（それを「表示が壊れている」と読み違える）
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "1\(index)-\(name)")
        }

        // ギャラリーに戻って、1枚目の写真を開いたところ
        tabBar.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 2)
        let firstPhoto = app.scrollViews.buttons.firstMatch
        if firstPhoto.waitForExistence(timeout: 10) {
            firstPhoto.tap()
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "20-写真の詳細")
        }
    }
}
