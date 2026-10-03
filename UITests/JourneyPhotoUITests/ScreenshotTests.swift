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
        // 検索が要る絵（13b・13c）と要らない絵（13d）を分ける。検索で撮れなかった回も
        // 13d は撮る（先に抜けると、撮れる絵まで黙って消えていた）
        shootSearchedSpot(app)
        // 「スポット」の札（板 04c 案A）。撮ったら地図へ戻す（あとの画面に持ち越さない）
        let spots = app.buttons["map.mode.spots"].firstMatch
        if spots.waitForExistence(timeout: 5) {
            spots.tap()
            if app.buttons["map.spotRow"].firstMatch.waitForExistence(timeout: 10) {
                shoot(app, "13d-マップ（スポットの一覧）")
                shootSpotLight(app)
            }
            let map = app.buttons["map.mode.map"].firstMatch
            if map.exists { map.tap() }
        }
    }

    /// **撮影スポットの「光の時刻」**（2026-10-03）。スポットの一覧の先頭の行から台帳の撮影スポットの画面
    /// （`OfficialSpotView`）を開き、日付の帯が画面の上の方に来るまで送って撮る。撮ったら一覧へ戻す。
    /// 「探す」の注目スポット（`search.spot`）は写真から導く撮影地の画面で、こちらの節は無い。
    /// 出なければ撮らない（この試験の決まり）
    private func shootSpotLight(_ app: XCUIApplication) {
        let row = app.buttons["map.spotRow"].firstMatch
        guard row.exists, row.isHittable else { return }
        row.tap()
        defer {
            // 一覧へ戻す（あとの画面に持ち越さない）
            goBack(app)
            Thread.sleep(forTimeInterval: 1)
        }
        // 画面の目印（`spot.official`）は ScrollView に付いていて中の要素に移ることがあるので、待つのは時間で
        Thread.sleep(forTimeInterval: 3)
        let date = app.descendants(matching: .any).matching(identifier: "spot.official.light.date").firstMatch
        var swipes = 0
        while swipes < 6, !(date.exists && date.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard date.exists, date.isHittable else { return }
        // 日付の帯を画面の上の方へ寄せ、朝・夕の段と注記まで1枚に入れる
        date.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "13f-撮影スポット（光の時刻）")
        shootSpotSamples(app)
    }

    /// **撮影スポットの作例**（Wikimedia Commons・2026-10-03）。光の時刻と同じ画面のまま下へ送り、
    /// 作例の帯（`spot.official.samples`）が出たら撮る。本文に `samples` の無いスポットでは出ないので撮らない
    /// （この試験の決まり）。戻るのは呼び出し元（`shootSpotLight` の defer）
    private func shootSpotSamples(_ app: XCUIApplication) {
        let credit = app.descendants(matching: .any).matching(identifier: "spot.official.sampleCredit").firstMatch
        var swipes = 0
        while swipes < 6, !(credit.exists && credit.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard credit.exists, credit.isHittable else { return }
        // 写真が読み込まれるのを待つ（Commons の縮小版）
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "13g-撮影スポット（作例）")
    }

    /// 積んだ画面から1つ戻る（2026-10-03）。
    ///
    /// 🔴 **`navigationBars.buttons.element(boundBy: 0)` で戻らない。** 積んだ画面の下には地図の
    /// バーも残っていて、両方のバーのボタンがまとめて数えられる——1番目が地図の見出しの
    /// **お知らせのベル**（`header.notifications`）になり、押すとお知らせの札が開いたまま残った。
    /// その札がマイページを覆い、`14-マイページ` がお知らせの絵になり、15・20・21・30・31・
    /// 41・60・61 が黙って消えた（#148 から。PR の検証 run 8〜10）。
    ///
    /// 標準の戻るボタン（`BackButton`）→ 見出しのボタン（`header.*`）を除いた最初のボタン →
    /// 左端から払う、の順で戻る
    private func goBack(_ app: XCUIApplication) {
        let standard = app.navigationBars.buttons["BackButton"].firstMatch
        if standard.exists, standard.isHittable {
            standard.tap()
            return
        }
        let notHeader = NSPredicate(format: "NOT (identifier BEGINSWITH 'header.')")
        let other = app.navigationBars.buttons.matching(notHeader).firstMatch
        if other.exists, other.isHittable {
            other.tap()
            return
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
    }

    /// **写真のピンが地図に出ているか**を数えて残す（2026-10-02）。
    ///
    /// 「13-マップ」（パリ）で写真のピンが消えたように見えた回があった——丸い印は Apple の
    /// 名所の挿絵で、それが描かれる前に撮っていたと見られる（絵だけでは写真のピンと見分けにくい）。
    /// 印の目印（`map.photoPin`・束は `map.photoCluster`）で数えて、ログと添付に本数を書く。
    /// 1本も無ければ縮小を3回まで押して探し、見つかったら「13e」を撮る。
    ///
    /// **落とさない**（この試験の決まり）。本数は本番のデータと位置で変わるので、
    /// 0本を失敗にすると見張りが読めなくなる。0本のときは添付の本数で気づく
    private func shootPhotoPins(_ app: XCUIApplication) {
        let map = app.buttons["map.mode.map"].firstMatch
        if map.exists { map.tap() }
        func count() -> Int {
            app.descendants(matching: .any).matching(identifier: "map.photoPin").count
                + app.descendants(matching: .any).matching(identifier: "map.photoCluster").count
        }
        let first = app.descendants(matching: .any).matching(identifier: "map.photoPin").firstMatch
        _ = first.waitForExistence(timeout: 5)
        var found = count()
        var zoomOuts = 0
        let zoomOut = app.buttons["縮小"].firstMatch
        while found == 0, zoomOuts < 3, zoomOut.exists, zoomOut.isHittable {
            zoomOut.tap()
            zoomOuts += 1
            Thread.sleep(forTimeInterval: 2)
            found = count()
        }
        print("ScreenshotTests: 写真のピン \(found) 本（縮小 \(zoomOuts) 回）")
        let note = XCTAttachment(string: "写真のピン（map.photoPin + map.photoCluster）: \(found) 本・縮小 \(zoomOuts) 回")
        note.name = "13e-写真のピンの本数"
        note.lifetime = .keepAlways
        add(note)
        if found > 0 {
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "13e-マップ（写真のピン）")
        }
    }

    /// 名前で絞って、ピン（13b）と押したときの札（13c）を撮る
    private func shootSearchedSpot(_ app: XCUIApplication) {
        let field = app.textFields["map.search"].firstMatch
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap()
        // 🔴 **焦点が来てから打つ。** 来ないまま `typeText` を呼ぶと XCTest は
        // 「keyboard focus が無い」を失敗として記録し、撮影ごと赤くなる（run 197・214。
        // 同じ木で緑の回もある）。来なければこのスポットの絵は撮らずに先へ進む
        guard waitForKeyboardFocus(field) else { return }
        field.typeText("鍋ヶ滝\n")
        Thread.sleep(forTimeInterval: 3)
        let pin = app.buttons["鍋ヶ滝"].firstMatch
        guard pin.waitForExistence(timeout: 10) else {
            // ピンが出なくても、絞りは解いてから戻る（13d・あとの画面に持ち越さない）
            let clear = app.buttons["消す"].firstMatch
            if clear.exists { clear.tap() }
            return
        }
        shoot(app, "13b-マップ（撮影スポットのピン）")
        pin.tap()
        if app.descendants(matching: .any).matching(identifier: "map.officialCard").firstMatch.waitForExistence(timeout: 5) {
            shoot(app, "13c-マップ（撮影スポットの札）")
        }
        // 絞りを解いて、あとの画面に持ち越さない
        let clear = app.buttons["消す"].firstMatch
        if clear.exists { clear.tap() }
    }

    /// 入力欄にキーボードの焦点が来るまで待つ。来なければ押し直す（最長 `timeout` 秒）。
    ///
    /// 焦点は2通りで見る。`hasKeyboardFocus` は非公開の属性なので、**在るときだけ**読む
    /// （無い名前を KVC で読むと ObjC の例外でプロセスごと落ち、あとの絵が全部消える）。
    /// もう1つは公開の「キーボードが出ている」——出ていれば焦点はどこかの欄にある
    /// （画面に入力欄はこの1つだけ）。
    /// 焦点を奪う札（位置の許可）が遅れて出ていれば、ここで答える
    private func waitForKeyboardFocus(_ field: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let app = XCUIApplication()
        func hasFocus() -> Bool {
            if field.responds(to: NSSelectorFromString("hasKeyboardFocus")),
               (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                return true
            }
            return app.keyboards.firstMatch.exists
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasFocus() { return true }
            Thread.sleep(forTimeInterval: 1)
            if hasFocus() { return true }
            if XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists {
                answerLocationPrompt()
            }
            if field.isHittable { field.tap() }
        }
        // 最後の押し直しで来た分も数える
        Thread.sleep(forTimeInterval: 1)
        if hasFocus() { return true }
        // 撮らずに進む回は、焦点の見え方をログに残す（毎回ここに来るなら、見方が CI で効いていない）
        print("ScreenshotTests: 焦点が見えない（hasKeyboardFocus の有無=\(field.responds(to: NSSelectorFromString("hasKeyboardFocus")))・キーボード=\(app.keyboards.firstMatch.exists)）")
        return false
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
            // **マイページは上のバーを出さない**（板 05c）。バーを待つと 15 秒空振りする。
            // 見出しの「プロフィールを編集」を待つ（タブは読み込み中にも出ている）
            if name == "マイページ" {
                _ = app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15)
            } else {
                _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
            }
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
            // ホームの「撮影地を探す / 写真から探す」が見える状態をPR確認用に残す
            if name == "ホーム", app.buttons["home.exploreMap"].firstMatch.exists {
                shoot(app, "10b-ホーム（撮影地への入口）")
                // フォロー中が0件の回は、行き止まりではなく発見へのCTAが出ることも残す
                let following = app.buttons["フォロー中"].firstMatch
                if following.exists, following.isHittable {
                    following.tap()
                    Thread.sleep(forTimeInterval: 2)
                    if app.buttons["home.emptyAction"].firstMatch.exists {
                        shoot(app, "10c-ホーム（空フィードの次の行動）")
                    }
                }
            }
            if name == "探す" {
                let field = app.textFields["search.field"].firstMatch
                if field.exists, field.isHittable {
                    field.tap()
                    field.typeText("zzzz-no-photo-result")
                    Thread.sleep(forTimeInterval: 2)
                    if app.buttons["search.emptyMap"].firstMatch.exists {
                        shoot(app, "11b-探す（0件から地図へ）")
                    }
                    // 消すボタンは入力欄の外にある自前のボタン（`search.clear`）。OS の「Clear text」は無い。
                    // 見つからなくても落とさない（この試験の決まり: 出なければ撮らないだけ）
                    let clear = app.buttons["search.clear"].firstMatch
                    if clear.waitForExistence(timeout: 3), clear.isHittable { clear.tap() }
                }
            }
            if name == "マップ" {
                shootSpotPin(app)
                shootPhotoPins(app)
            }
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
                    // **足取り（ルート図）が画面に収まるところまで送って撮る。**
                    // 板 03 に合わせてルート図は表紙のすぐ下へ移った（前は一番下）。
                    // 決め打ちで2回送ると通り過ぎて、名前と中身が食い違う。
                    // ルート図は2か所以上の旅にしか出ないので、無ければ数字の3枠で代える
                    let routeShown = app.descendants(matching: .any)["trips.route"].firstMatch
                    let target = routeShown.waitForExistence(timeout: 3)
                        ? routeShown
                        : app.descendants(matching: .any)["trips.stats"].firstMatch
                    // 下の余白はタブバーのぶん
                    let visibleBottom = app.windows.firstMatch.frame.maxY - 100
                    var pushes = 0
                    while target.exists, target.frame.maxY > visibleBottom, pushes < 3 {
                        app.swipeUp()
                        Thread.sleep(forTimeInterval: 1)
                        pushes += 1
                    }
                    Thread.sleep(forTimeInterval: 1)
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
        // **画面の下（タブバーの裏）に隠れていたら送る（上限あり・`21` と同じ考え）。**
        // ホームは写真の前に今日のテーマ・発見の節が並ぶので、1枚目がタブバーの裏に
        // 掛かって `isHittable == false` になり、`20` と `21` が**黙って欠けて**いた。
        // `swipeUp` は勢いで1枚目ごと画面の上へ流しうるので、勢いの付かない短い引き
        // （画面の 35% ぶん）で少しずつ送る
        var feedPushes = 0
        while firstPhoto.waitForExistence(timeout: 10), !firstPhoto.isHittable, feedPushes < 4 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            feedPushes += 1
        }
        if firstPhoto.waitForExistence(timeout: 10), firstPhoto.isHittable {
            firstPhoto.tap()
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "20-写真の詳細")

            // 撮影地は1枚しかない場所でも必ず入口を持つ。スポット化できる地点は
            // spotLink、1枚だけなら placeLink。どちらでも「写真→場所」の流れを実画面で残す。
            let spotLink = app.buttons["photo.spotLink"].firstMatch
            let placeLink = app.buttons["photo.placeLink"].firstMatch
            let locationLink = spotLink.exists ? spotLink : placeLink
            if locationLink.waitForExistence(timeout: 3), locationLink.isHittable {
                locationLink.tap()
                Thread.sleep(forTimeInterval: 4)
                shoot(app, "20b-写真から撮影地へ")
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 2)
            }

            // **人のページ**（モック2 と同じ部品で組んである）。
            //
            // **画面の下に隠れていたら送る（上限あり）。** 作者の行は説明の
            // 後ろにあるので、長い説明の写真では画面の外（ログイン中は入力欄の下）
            // に出て `isHittable == false` になり、`21` が**黙って欠ける**
            let toAuthor = app.buttons["photo.author"].firstMatch
            var pushUps = 0
            while toAuthor.waitForExistence(timeout: 5), !toAuthor.isHittable, pushUps < 3 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                pushUps += 1
            }
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
            if app.otherElements["spot.official.journeyCue"].firstMatch.exists {
                shoot(app, "60b-撮影スポット（撮影までの流れ）")
            }
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

    /// **投稿画面から写真の編集へ入る口**（2026-10-03 owner「写真編集の仕方がわからなかった。
    /// どこから入るのか」）。帯のサムネの「編集」の札と、帯の下の「写真を編集」が見える1枚。
    ///
    /// **別の試験にしてある。** 投稿画面は札（sheet）で、書きかけがあると閉じるのに確認が要る——
    /// 一巡（`testCapturesEveryScreen`）の途中に置くと、閉じ損ねたときにあとの絵が全部消える。
    /// 写真はシミュレータのライブラリの見本から1枚選ぶ。選ぶ画面（PHPicker）は別プロセスで、
    /// 中が触れない回もある——**出なければ撮らない**（この試験の決まり）
    func testCapturesUploadEditEntry() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        guard toPhoto.waitForExistence(timeout: 5), toPhoto.isHittable else { return }
        toPhoto.tap()

        // 「追加」→「ライブラリから選ぶ」（未ログインの回はログイン画面なので、ここで抜ける）
        let add = app.descendants(matching: .any).matching(identifier: "upload.add").firstMatch
        guard add.waitForExistence(timeout: 10), add.isHittable else { return }
        add.tap()
        let library = app.buttons["ライブラリから選ぶ"].firstMatch
        guard library.waitForExistence(timeout: 5) else { return }
        library.tap()

        // 選ぶ画面の1枚目を選んで「追加」
        //
        // 🔴 run 37093238090 はここで落ちた——選ぶ画面は別プロセスで、中の写真がこちらの
        // 木（accessibility）に出てこない回がある。そのとき `images.firstMatch` は
        // **選ぶ画面の下に隠れた投稿画面の「曲（任意）」の `music.note`** を拾い、
        // 押せない（`Not hittable`）まま tap して試験ごと落ちた。
        // 下の画面の絵が先に並ぶこともあるので、**押せる最初の1枚**を探す。
        // 押せる1枚が見つからなければ撮らずに抜ける（この試験の決まり）
        let images = app.scrollViews.otherElements.images
        guard images.firstMatch.waitForExistence(timeout: 10) else { return }
        let candidates = images.allElementsBoundByIndex.prefix(30)
        guard let photo = candidates.first(where: { $0.exists && $0.isHittable }) else { return }
        photo.tap()
        for label in ["追加", "Add"] {
            let done = app.navigationBars.buttons[label].firstMatch
            if done.waitForExistence(timeout: 3) {
                done.tap()
                break
            }
        }

        // 帯のサムネと「写真を編集」が出たら撮る（読み込みに数秒かかる）
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        guard thumb.waitForExistence(timeout: 15) else { return }
        let editButton = app.buttons["upload.editButton"].firstMatch
        guard editButton.waitForExistence(timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "42-投稿（写真の編集の入口）")
    }

    /// **投稿済みの写真の「色を編集」**（2026-10-03・段階1）。マイページ → 自分の写真 → 「…」→「編集」で、
    /// 写真の欄に「写真を差し替える」と並んだ「色を編集」が見える1枚。
    ///
    /// **別の試験にしてある**（「写真を編集」は札で、一巡の途中に置くと閉じ損ねたときにあとの絵が消える）。
    /// 鍵なしログインで自分の写真が出ない回・「…」に「編集」が無い回は**撮らずに抜ける**（この試験の決まり）。
    /// 「色を編集」は押さない——押すと公開中の画像を読みに行き、鍵の要らない GET でも撮る絵が通信次第になる
    func testCapturesEditPhotoRecolorEntry() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()

        // 自分の写真（名指し・位置で探さない）。タブの下に隠れていたら1回だけ送る
        let myPhoto = app.buttons["mypage.photo"].firstMatch
        guard myPhoto.waitForExistence(timeout: 15) else { return }
        if !myPhoto.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        guard myPhoto.isHittable else { return }
        myPhoto.tap()

        let menu = app.buttons["photo.menu"].firstMatch
        guard menu.waitForExistence(timeout: 10), menu.isHittable else { return }
        menu.tap()
        let edit = app.buttons["photo.edit"].firstMatch
        guard edit.waitForExistence(timeout: 5), edit.isHittable else { return }
        edit.tap()

        let recolor = app.buttons["editPhoto.recolor"].firstMatch
        guard recolor.waitForExistence(timeout: 10) else { return }
        // 見本の写真が描かれるのを少し待つ（枠だけの絵を「壊れている」と読み違えない）
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "22-写真を編集（色を編集の入口）")
    }

    /// **探すの「季節・時間帯で絞る」**（2026-10-03・戦略の計画6）。発見の顔の「季節・時間帯から探す」で
    /// 「秋」を押した1枚（秋の案内のある撮影スポットと、秋に撮った写真）と、続けて「夕」を重ねた1枚。
    ///
    /// 札は名指しで探す（`search.season.autumn`・`search.dayPart.evening`）。段が画面の下にあれば少しずつ送る。
    /// **別の試験にしてある**（一巡の「11-探す」の絵に絞った状態を持ち越さない）。出なければ撮らない（この試験の決まり）
    func testCapturesSearchSeasonTimeFilter() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 1 else { return }
        tabBar.buttons.element(boundBy: 1).tap()

        let autumn = app.buttons["search.season.autumn"].firstMatch
        guard autumn.waitForExistence(timeout: 20) else { return }
        var swipes = 0
        while !autumn.isHittable, swipes < 6 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard autumn.isHittable else { return }
        autumn.tap()
        // 撮影スポットの索引と写真の絵が描かれるのを待つ（枠だけの絵を「壊れている」と読み違えない）
        Thread.sleep(forTimeInterval: 4)
        shoot(app, "11c-探す（季節で絞る・秋）")

        let evening = app.buttons["search.dayPart.evening"].firstMatch
        guard evening.waitForExistence(timeout: 5), evening.isHittable else { return }
        evening.tap()
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "11d-探す（季節と時間帯で絞る・秋の夕方）")
    }

    /// **「行きたい場所」を地図で見る**（2026-10-03・3か月の計画の7の第一歩）。マイページの
    /// 「行きたい場所」のタブ（「地図で見る」が見える1枚）と、押した先の地図の1枚。
    ///
    /// 🔴 **鍵なしログインでは `/user/spots` が 401 で、行きたい場所は0件。** 撮るために
    /// **端末の控え（`WishlistStore` の鍵）へ公開済みの撮影スポットを3件、起動引数で入れる**
    /// （UserDefaults の引数の領域。端末には書き込まれず、サーバーにも送られない——同期は
    /// 401 で止まり、`replace` は呼ばれない）。絵の名前にもそう書く（中身と名前を食い違わせない）。
    /// スポットは索引（`app/data/spots.json`）の公開済み・座標ありの行。
    ///
    /// **別の試験にしてある**（一巡の絵に「入れた控え」を混ぜない）。出なければ撮らない（この試験の決まり）
    func testCapturesWishlistMap() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        // 京都・鎌倉・函館（離れた3か所＝枠が全部を囲むかが絵で分かる）
        app.launchArguments += ["-journey-photo-wishlist:\(Self.previewUserId)",
                                "(\"SPOT-fushimi-inari-taisha\",\"SPOT-kenchoji\",\"SPOT-goryokaku\")"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()

        // タブの札（名指し）。画面の下に隠れていたら少しずつ送る（上限あり）
        let wishTab = app.buttons["profile.tab.wishlist"].firstMatch
        guard wishTab.waitForExistence(timeout: 15) else { return }
        var pushes = 0
        while !wishTab.isHittable, pushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard wishTab.isHittable else { return }
        wishTab.tap()

        let mapLink = app.buttons["mypage.wishlistMap"].firstMatch
        guard mapLink.waitForExistence(timeout: 15) else { return }
        if !mapLink.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        guard mapLink.isHittable else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "62-行きたい場所（撮影用に端末の控えへ3件）")
        mapLink.tap()

        let pin = app.descendants(matching: .any).matching(identifier: "savedMap.pin").firstMatch
        guard pin.waitForExistence(timeout: 15) else { return }
        // ピンの写真と地図の絵が描かれるのを待つ
        Thread.sleep(forTimeInterval: 4)
        shoot(app, "63-行きたい場所の地図（撮影用に端末の控えへ3件）")

        // ピンを選ぶ（2026-10-03・地図から旅行プランを作る）。**選ぶだけで「作る」は押さない**
        // （押すとプランを作りに行く。選ぶのは画面の中の状態で、端末にもサーバーにも何も書かない）
        let pins = app.descendants(matching: .any).matching(identifier: "savedMap.pin")
        var tapped = 0
        for i in 0..<min(pins.count, 3) where pins.element(boundBy: i).isHittable {
            pins.element(boundBy: i).tap()
            tapped += 1
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard tapped > 0 else { return }
        let create = app.buttons["savedMap.createTrip"].firstMatch
        guard create.waitForExistence(timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "64-行きたい場所の地図で選んだ（この N か所で旅行プランを作る）")
    }
}
