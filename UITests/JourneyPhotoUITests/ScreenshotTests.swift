import XCTest
import CoreLocation

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

    /// **撮影スポットのピンを撮る。** 公開済みのスポットは国内の4件だけで、
    /// 地図を開いた範囲（シミュレータの現在地＝パリ）には1本も出ない。名前で絞ると
    /// 地図がそのスポットへ寄るので、ピンと、押したときの札を撮る。
    /// 見つからなければ撮らない（名前と中身が食い違う絵は、無い絵より悪い）
    private func shootSpotPin(_ app: XCUIApplication) {
        let field = app.textFields["map.search"].firstMatch
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap()
        field.typeText("鍋ヶ滝\n")
        Thread.sleep(forTimeInterval: 3)
        let pin = app.buttons["鍋ヶ滝"].firstMatch
        guard pin.waitForExistence(timeout: 10) else { return }
        shoot(app, "13b-マップ（撮影スポットのピン）")
        pin.tap()
        if app.descendants(matching: .any).matching(identifier: "map.officialCard").firstMatch.waitForExistence(timeout: 5) {
            shoot(app, "13c-マップ（撮影スポットの札）")
        }
        // 絞りを解いて、あとの画面に持ち越さない
        let clear = app.buttons["消す"].firstMatch
        if clear.exists { clear.tap() }
    }

    /// **位置の許可の札に答える。** 地図は開いた最初の1回に現在地を取りにいく
    /// （2026-09-26〜）ので、初めて開くと iOS が許可を尋ねる。この札は
    /// アプリの外（SpringBoard）に出て、**残るとあとのタブが押せなくなる**。
    /// 「使用中は許可」を押す——既定の場所が現在地になる、いまの動きを撮るため
    private func answerLocationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        for label in ["アプリの使用中は許可", "Allow While Using App", "1度だけ許可", "Allow Once"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
        // 文言が変わっていても札は残さない（残すと以降が全部撮れない）
        alert.buttons.element(boundBy: 0).tap()
    }

    /// **シミュレータに現在地を持たせる。** 持たせないと CI のシミュレータは
    /// 位置を返さず、地図は「現在地を探しています…」のまま写真に合わせた
    /// 絵になる（run 100）——既定の場所が現在地になる動きが絵で確かめられない。
    /// 場所はパリ（本番の写真がある所。ピンと現在地が同じ絵に入る）
    private func simulateLocation() {
        if #available(iOS 16.4, *) {
            XCUIDevice.shared.location = XCUILocation(
                location: CLLocation(latitude: 48.8566, longitude: 2.3522))
        }
    }

    func testCapturesEveryScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        // **写真の出どころだけ本番に向ける。** テストは Debug＝staging 設定で
        // 走るが、staging には写真が1枚も無い（本番の写真はコピーしない方針）。
        // そのまま撮ると「No photos found.」ばかりで、人が見る画面の確認に
        // ならない。API とログインは staging のまま（ここでは誰もログインしない）
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        // **プロフィールも同じ本番から読む。** 巡回のビルドは Debug＝
        // `Config/Staging.xcconfig` なので、写真だけ本番・プロフィールは
        // staging という食い違った絵になっていた。staging にこの人は
        // 居ないので `/profile/{id}` が 404 になり、run 65 のマイページは
        // 本物の写真36枚の上に**「ユーザー」「名前を決めましょう」**が
        // 載っていた（この人の本当の名前は「丸田 竜平」）。
        //
        // **鍵は持たないままなので、叩けるのは公開の GET だけ**
        // （プロフィール・フォロー数・いいね数）。書き込む口は 401 で断られる。
        app.launchArguments += [
            "-JPUserApiBaseURL",
            "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com",
        ]
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
            if name == "マップ" { simulateLocation() }
            tabBar.buttons.element(boundBy: index).tap()
            if name == "マップ" { answerLocationPrompt() }
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
            if name == "マップ" { shootSpotPin(app) }
        }

        // **マイページの下半分**（モック2）。ハイライトの輪・作品の格子・
        // 行きたい場所は1画面に収まらないので、送ってもう1枚撮る。
        //
        // 🔴 **送れたときだけ撮る。** run 61 の `15-マイページ（下）` は
        // 14 と**同じ絵**だった——鍵なしログインでは作品の格子が出ないので
        // 中身が1画面に収まり、送っても動かない。「（下）」という名前で
        // 上と同じ絵を置くのは、名前と中身が食い違う絵の変種。
        //
        // 動いたかは**名前の付いた目印の位置**で見る（`profile.tab.trips`）。
        if tabBar.buttons.count > 4 {
            tabBar.buttons.element(boundBy: 4).tap()
            Thread.sleep(forTimeInterval: 3)
            let mark = app.buttons["profile.tab.trips"].firstMatch
            let before = mark.exists ? mark.frame.origin.y : nil
            app.swipeUp()
            Thread.sleep(forTimeInterval: 2)
            let after = mark.exists ? mark.frame.origin.y : nil
            if let before, let after, abs(before - after) > 1 {
                shoot(app, "15-マイページ（下）")
            }
        }

        // **旅を1冊開く。** 表紙・ページ・足取りは、開かないと絵にならない。
        //
        // 🔴 **位置で探さない。** run 60 はここで一覧の1つ目を位置で押して、
        // マイページの「投稿する」に当たり、**「30-旅の一冊」という名前で
        // 投稿の札を撮って**いた。同じ失敗は run 49（写真の詳細＝ログイン画面）・
        // run 55（マイページ＝ログイン画面）に続いて**3回目**。
        //
        // 名前の付いた入口だけを押し、**見つからなければ1枚も撮らない**
        // ——名前と中身が食い違う絵は、無い絵より悪い。
        if tabBar.buttons.count > 4 {
            tabBar.buttons.element(boundBy: 4).tap()
            Thread.sleep(forTimeInterval: 2)
            // 🔴 **上まで戻してから探す。** 1つ上の節（`15-マイページ（下）`）が
            // 画面を送りっぱなしにしていて、同じタブをもう一度押しても
            // **先頭には戻らない**（既に選ばれているタブの二度押しは
            // スクロールを戻すが、それは `List` / `ScrollView` の
            // `scrollToTop` が効く形のときだけ）。run 65 では `trips.entry` が
            // 画面の上に流れたままで `isHittable == false` になり、
            // **`30-旅の一冊` と `31-旅の足取り` が黙って消えた**
            // ——マイページに中身が出るようになった副作用で、run 64 までは
            // 送っても動かなかったので起きなかった。
            let tripsEntry = app.buttons["profile.tab.trips"].firstMatch
            var pullDowns = 0
            while tripsEntry.exists, !tripsEntry.isHittable, pullDowns < 4 {
                app.swipeDown()
                Thread.sleep(forTimeInterval: 1)
                pullDowns += 1
            }
            if tripsEntry.waitForExistence(timeout: 8), tripsEntry.isHittable {
                tripsEntry.tap()
                Thread.sleep(forTimeInterval: 4)
                let firstTrip = app.buttons["trips.book"].firstMatch
                // 旅の棚はタブの下に出る（整理案 05c でタブへ移した）。
                // **画面の下に隠れていたら1回だけ送る**
                if firstTrip.waitForExistence(timeout: 10), !firstTrip.isHittable {
                    app.swipeUp()
                    Thread.sleep(forTimeInterval: 2)
                }
                if firstTrip.waitForExistence(timeout: 10), firstTrip.isHittable {
                    firstTrip.tap()
                    Thread.sleep(forTimeInterval: 4)
                    shoot(app, "30-旅の一冊")
                    // 下まで流して、足取りのところも撮る
                    app.swipeUp()
                    app.swipeUp()
                    Thread.sleep(forTimeInterval: 2)
                    shoot(app, "31-旅の足取り")
                    // **押し込めた回だけ戻る。** 旅が無い回に押すと、戻るではなく
                    // マイページの歯車（設定）に当たる（旅の一覧をタブへ畳んだので、
                    // 押し込み先が必ずあるとは限らなくなった）
                    if app.navigationBars.buttons.firstMatch.exists {
                        app.navigationBars.buttons.firstMatch.tap()
                    }
                }
            }
        }

        // ギャラリーに戻って、1枚目の写真を開いたところ。
        //
        // 🔴 **この節を、旅の節を書き直したときに巻き添えで消していた**
        // （run 62 で `20-写真の詳細` と `21-人のページ` が丸ごと欠けた）。
        // 消えたことは**絵の枚数が減った**ことでしか分からない——
        // 巡回は「出なければ撮らない」ので、赤くもならない。
        tabBar.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 2)
        // **写真そのものを名指しで押す**（`feed.photo`）。
        // 位置で探していたときは、今日のテーマの「参加する」に当たって
        // **ログイン画面を「写真の詳細」として撮って**いた（run 49）。
        let firstPhoto = app.buttons["feed.photo"].firstMatch
        if firstPhoto.waitForExistence(timeout: 10), firstPhoto.isHittable {
            firstPhoto.tap()
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "20-写真の詳細")

            // **人のページ**（モック2 と同じ部品で組んである）。
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
