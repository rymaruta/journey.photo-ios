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

    /// 絵を撮るときに「この人」として見る利用者。
    ///
    /// **公開 API が誰にでも返している値**（写真の行の `userId`）で、
    /// 資格情報ではない。この人の公開写真が本物のデータで並ぶので、
    /// マイページが**空の枠ではなく実物**で撮れる。
    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"

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
        // **写真の出どころだけ本番に向ける。** テストは Debug＝staging 設定で
        // 走るが、staging には写真が1枚も無い（本番の写真はコピーしない方針）。
        // そのまま撮ると「No photos found.」ばかりで、人が見る画面の確認に
        // ならない。API とログインは staging のまま（ここでは誰もログインしない）
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        // **日本語の端末として撮る。** CI のシミュレータは英語で、
        // そのまま撮ると「戻る」「キャンセル」など OS 側の文字まで英語になり、
        // 実際に人が見る画面と違う絵になる（アプリ自身の文字は日本語で固定）
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        // **マイページを撮るための、鍵を持たないログイン**（Debug のみ・
        // owner 承認済み・`AuthStore.restore()`）。トークンは1つも作らないので
        // 鍵の要る口は 401 になり、画面はその「取れなかった」側を出す
        // ——**嘘の中身は出ない**。渡す値は公開 API が返している `userId`
        // そのもので、資格情報ではない。
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
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

        let names = ["ホーム", "探す", "投稿", "マップ", "マイページ"]
        // 中央（投稿）はシートが出るので、一巡の中では触らない
        for (index, name) in names.enumerated() where index < tabBar.buttons.count && index != 2 {
            tabBar.buttons.element(boundBy: index).tap()
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
            // **少し待ってから撮る。** 写真は通信で来るので、描いた直後は
            // 枠だけの絵になる（それを「表示が壊れている」と読み違える）
            Thread.sleep(forTimeInterval: 3)
            // **出ているものを名前に書く。** マイページはログインしていない
            // 回に**ログイン画面**が出るので、そのまま「14-マイページ」と
            // 名付けると、見た人が「マイページはこういう画面だ」と誤読する
            // （run 55 までそうなっていた）
            // **種別を決め打ちしない。** `Form` は OS の版で `table` にも
            // `collectionView` にもなる（run 57 はここを外して、名前に
            // 何も付かなかった）。**どの種別でも拾う**
            let signedOut = app.descendants(matching: .any)
                .matching(identifier: "signin.form").firstMatch.exists
            shoot(app, "1\(index)-\(name)\(signedOut ? "（未ログイン＝ログイン画面）" : "")")
        }

        // **マイページの下半分**（モック2）。ハイライトの輪・作品の格子・
        // 行きたい場所は1画面に収まらないので、送ってもう1枚撮る
        if tabBar.buttons.count > 4 {
            tabBar.buttons.element(boundBy: 4).tap()
            Thread.sleep(forTimeInterval: 3)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "15-マイページ（下）")
        }

        // **旅を1冊開く。** 表紙・ページ・足取りは、開かないと絵にならない
        // （タブから外したので、マイページの「旅の記録」から入る）
        if tabBar.buttons.count > 4 {
            tabBar.buttons.element(boundBy: 4).tap()
            Thread.sleep(forTimeInterval: 2)
            let tripsEntry = app.buttons.matching(identifier: "旅の記録").firstMatch
            if tripsEntry.waitForExistence(timeout: 8) { tripsEntry.tap() }
            Thread.sleep(forTimeInterval: 4)
            let firstTrip = app.scrollViews.buttons.firstMatch
            if firstTrip.waitForExistence(timeout: 10) {
                firstTrip.tap()
                Thread.sleep(forTimeInterval: 4)
                shoot(app, "30-旅の一冊")
                // 下まで流して、足取りのところも撮る
                app.swipeUp()
                app.swipeUp()
                Thread.sleep(forTimeInterval: 2)
                shoot(app, "31-旅の足取り")
                if app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                }
            }
        }

        // ギャラリーに戻って、1枚目の写真を開いたところ
        tabBar.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 2)
        // **写真そのものを名指しで押す**（`feed.photo`）。
        // 位置で探していたときは、今日のテーマの「参加する」に当たって
        // **ログイン画面を「写真の詳細」として撮って**いた（run 49）。
        // 絵の名前と中身が食い違うと、見た人が「直っている」と誤読する。
        let firstPhoto = app.buttons["feed.photo"].firstMatch
        if firstPhoto.waitForExistence(timeout: 10), firstPhoto.isHittable {
            firstPhoto.tap()
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "20-写真の詳細")

            // **人のページ**（モック2 と同じ部品で組んである）。
            // マイページそのものは CI では撮れない——巡回はログインしない。
            // だが**ハイライトの輪・写真の格子・数え**は人のページにも
            // 同じものが出るので、少なくともそこは実機で見られる。
            // 「マイページを撮った」とは書かない（撮っていない）
            let toAuthor = app.buttons["photo.author"].firstMatch
            if toAuthor.waitForExistence(timeout: 5), toAuthor.isHittable {
                toAuthor.tap()
                Thread.sleep(forTimeInterval: 4)
                shoot(app, "21-人のページ（マイページと同じ部品）")
            }
        }

        // **撮影スポットの画面**（モック5）。
        //
        // 🔴 **写真の詳細からは撮れない。** run 54 で試して撮れなかった
        // ——導線（`photo.spotLink`）が出るのは「開いた写真の撮影地に
        // 2枚以上ある」ときだけで、いちばん新しい写真の撮影地
        // （三条市, 日本）は1枚だった。**データ次第で出たり出なかったり
        // する入口では、絵は撮れない。**
        //
        // 「探す」の**注目スポットの札**は、写真の多い地点から順に並ぶ
        // （`DiscoverySections.popularSpots`）。先頭は必ず最多の地点なので、
        // 写真が2枚以上ある地点が1つでもあれば必ず出る。
        tabBar.buttons.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 4)
        let toSpot = app.buttons["search.spot"].firstMatch
        if toSpot.waitForExistence(timeout: 10), toSpot.isHittable {
            toSpot.tap()
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "60-撮影スポット")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "61-撮影スポット（下）")
        }
        // **投稿の2択と、ストーリー作成**（モック4）。**巡回の最後に置く。**
        //
        // 🔴 run 58 はこれを途中に置いて落ちた——ストーリー作成は**札（sheet）**で
        // 出るので、閉じないまま次の手に進むと**タブの帯が覆われて**押せない
        // （`kAXErrorCannotComplete`。runs 46・47 と同じ形）。
        // 閉じる手を足すより、**後ろに何も無い場所に置く**方が確実。
        // 中央のタブは画面ではなく入口で、押すと2択の札が出る。
        // ログインしていない回に何が出るかも**そのまま撮る**
        // ——出ているものを名前に書く（「撮れなかった」を隠さない）
        if tabBar.buttons.count > 2 {
            tabBar.buttons.element(boundBy: 2).tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "40-投稿の2択")
            let toStory = app.buttons["post.choice.story"].firstMatch
            if toStory.waitForExistence(timeout: 5), toStory.isHittable {
                toStory.tap()
                Thread.sleep(forTimeInterval: 4)
                let signedOut = app.descendants(matching: .any)
                    .matching(identifier: "signin.form").firstMatch.exists
                shoot(app, "41-ストーリー作成\(signedOut ? "（未ログイン＝ログイン画面）" : "")")
            }
        }
    }
}
