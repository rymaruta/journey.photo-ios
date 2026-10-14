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

    /// **お知らせは開いたら閉じられること。** タブからシートへ移したときに
    /// 閉じるボタンを付け忘れ、「開いたら閉じられない」になった（2026-09-25）。
    /// ログインしていなくても同じシートが出る（中身がログインの案内になるだけ）
    func testNotificationsSheetCloses() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 30), "起動画面が出ない（落ちている可能性）")
        agree.tap()

        let bell = app.buttons["header.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20), "見出しのお知らせが無い")
        bell.tap()

        let close = app.buttons["notifications.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "お知らせに閉じるボタンが無い")
        close.tap()

        // 閉じたら見出しのベルがまた押せる（シートが残っていない）
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "閉じるを押してもお知らせが閉じない")
        XCTAssertTrue(bell.isHittable, "閉じた後にホームへ戻っていない")
    }

    /// **見出しの絵は、絵の外でも 44pt の高さの中なら押せること**（2026-10-14 絵を小さくしたとき）。
    /// 箱は幅 28・高さ 44。絵の中心から 19pt 下（19pt の絵の端から約 9pt 外）を押して開くか見る。
    /// 🔴 run 432: 箱を 28 角にして外へ当たりを広げた作りでは、ここを押しても開かなかった。
    /// 横（隣の絵との間）を押したときの結果は、決まりにせず記録だけ残す（システム次第のため）
    func testHeaderIconHitAreaReachesBeyondTheDrawnBox() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 30), "起動画面が出ない（落ちている可能性）")
        agree.tap()

        let bell = app.buttons["header.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20), "見出しのお知らせが無い")
        XCTAssertGreaterThanOrEqual(bell.frame.height, 44, "当たりの高さが 44 に足りない")
        let close = app.buttons["notifications.close"]
        let center = bell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        // 横: 箱の右の端から 5pt 外（隣のメニューとの間）。記録だけ
        center.withOffset(CGVector(dx: bell.frame.width / 2 + 5, dy: 0)).tap()
        let sideOpened = close.waitForExistence(timeout: 5)
        let note = XCTAttachment(string: "箱: \(bell.frame) / 横に 5pt 外を押して開いたか: \(sideOpened)")
        note.name = "見出しの絵の横の当たり"
        note.lifetime = .keepAlways
        add(note)
        if sideOpened {
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 10), "お知らせが閉じない")
        }

        // 縦: 絵の中心から 19pt 下（44 の高さの中）
        center.withOffset(CGVector(dx: 0, dy: 19)).tap()
        XCTAssertTrue(close.waitForExistence(timeout: 15),
                      "絵の外（44pt の高さの中）を押してもお知らせが開かない")
    }

    /// 見出しの「メニュー（≡）」でメニューが出て、「撮影地マップ」でシートが閉じて
    /// マップの札へ移る（板 01d・2026-09-26）
    func testHeaderMenuOpensAndRoutesToMap() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 30), "起動画面が出ない（落ちている可能性）")
        agree.tap()

        let menu = app.buttons["header.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "見出しにメニューが無い")
        menu.tap()

        let map = app.buttons["menu.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15), "メニューが開かない")
        map.tap()

        XCTAssertTrue(map.waitForNonExistence(timeout: 10), "撮影地マップを押してもメニューが閉じない")
        // マップの札が選ばれている（下の札の4つ目）
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 3).isSelected, "マップの札へ移っていない")
    }
}
