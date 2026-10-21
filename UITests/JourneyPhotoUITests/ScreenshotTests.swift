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

    /// **ホームの「いまの季節のスポット」の段を撮る**（2026-10-03・`HomeSpotShelfView`）。
    /// 札が画面の下に隠れていたら少しずつ送る（上限あり）。作例の写真は本文と Commons から来るので
    /// 少し待つ。段が出なければ撮らない（索引が取れない回・その季節の候補が無い回）。
    ///
    /// 🔴 **`swipeUp` は使わない・撮ったら上へ戻す。** 勢いで流れると、後の `20`・`21` が探す
    /// 1枚目の写真の位置が変わる（`feedPushes` の注記）。同じ短い引き（画面の 35%）で送り、
    /// 送った回数だけ逆に引いて戻す
    ///
    /// 2026-10-18: 札の下端の「行きたい」（`home.spotShelf.wish`）まで画面に入れて撮る
    /// （ボタンの位置・余白を写真で確かめる）。ボタンが無い版では札だけを待つ
    private func shootSpotShelf(_ app: XCUIApplication) {
        let photo = app.buttons["home.spotShelf.card"].firstMatch
        guard photo.waitForExistence(timeout: 10) else { return }
        let wish = app.buttons["home.spotShelf.wish"].firstMatch
        let card = wish.exists ? wish : photo
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        var pushes = 0
        while !card.isHittable, pushes < 3 {
            low.press(forDuration: 0.05, thenDragTo: high)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        if card.isHittable {
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "10d-ホーム（いまの季節のスポット・作例）")
        }
        for _ in 0..<pushes {
            high.press(forDuration: 0.05, thenDragTo: low)
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// **ホームの右上の見出し（探す・お知らせ・メニューのガラスの帯）を寄りで撮る**（2026-10-14）。
    /// 「デカすぎる」（owner）を 22pt → 19pt にしたので、前後の回で帯の高さ・絵の大きさを
    /// 見比べられるように、上のバーだけを切り出す。3つの押せる範囲（frame）も文で残す
    /// （帯の高さは絵より数字の方が比べやすい）。出なければ撮らない
    private func shootHeaderBand(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        guard bar.exists else { return }
        let shot = XCTAttachment(screenshot: bar.screenshot())
        shot.name = "10e-ホーム（右上の見出しの帯・寄り）"
        shot.lifetime = .keepAlways
        add(shot)
        let ids = ["header.search", "header.notifications", "header.menu"]
        let lines = ids.map { id -> String in
            let button = app.buttons[id].firstMatch
            return button.exists ? "\(id): \(button.frame)" : "\(id): 無し"
        }
        let note = XCTAttachment(string: (["バー: \(bar.frame)"] + lines).joined(separator: "\n"))
        note.name = "10e-ホーム（見出しの寸法）"
        note.lifetime = .keepAlways
        add(note)
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
        shootSpotTop(app)
        guard scrollToSpotLight(app) else { return }
        shoot(app, "13f-撮影スポット（光の時刻）")
        shootSpotSamples(app)
        shootSpotBottom(app)
    }

    /// **撮影スポットを下まで送ったとき、「このスポットの写真を投稿」がタブバーの上に出ているか**（2026-10-11）。
    ///
    /// 13g・13g2 は途中まで送った絵で、ボタンと「この場所の写真（0）」がタブバーの下に透けて見える
    /// （iOS 26 の浮いたタブバーは、送っている途中の中身を下に透かす）。下まで送り切ったときに
    /// ボタンの下端がタブバーの上端より上にあることを確かめ、その絵を撮る。
    /// ボタン・タブバーが見つからなければ撮らない（この試験の決まり）
    private func shootSpotBottom(_ app: XCUIApplication) {
        let post = app.buttons["spot.official.post"].firstMatch
        let tabBar = app.tabBars.firstMatch
        guard post.waitForExistence(timeout: 5), tabBar.exists else { return }
        // 送り切る（上限あり）。最後の1行（印の1行・無ければボタン）が動かなくなるまで
        var lastY = CGFloat.greatestFiniteMagnitude
        for _ in 0..<10 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            let y = post.frame.minY
            if abs(y - lastY) < 1 { break }
            lastY = y
        }
        guard post.exists else { return }
        XCTAssertLessThanOrEqual(post.frame.maxY, tabBar.frame.minY,
                                 "下まで送っても「このスポットの写真を投稿」がタブバーに掛かる: \(post.frame) / \(tabBar.frame)")
        shoot(app, "13g3-撮影スポット（下まで送った）")
    }

    /// **撮影スポットの頁の上（行動の札・2026-10-11）**。前提: 頁が開いて「行きたい」が出ている。
    /// 揃ったら、札の行に「地図で見る」「経路」があり、シェアは右上の1つだけ（違えば落とす）。
    /// 「地図で見る」を押して**アプリの中の地図**が出ることも見て撮り、頁へ戻す。
    /// 一覧の行（`map.spotRow`）から開くスポットは地図のピン＝座標があるので、2つの札は必ず出る
    private func shootSpotTop(_ app: XCUIApplication) {
        let wish = app.buttons["spot.official.wish"].firstMatch
        guard wish.waitForExistence(timeout: 5) else { return }
        shoot(app, "13e-撮影スポット（上・行動の札）")
        let toMap = app.buttons["spot.official.map"].firstMatch
        XCTAssertTrue(toMap.exists, "スポットの頁に「地図で見る」が無い")
        XCTAssertTrue(app.buttons["spot.official.directions"].firstMatch.exists, "スポットの頁に「経路」が無い")
        let shares = app.buttons.matching(NSPredicate(format: "label == %@", "シェア"))
        XCTAssertEqual(shares.count, 1, "スポットの頁にシェアが2つある")
        guard toMap.exists, toMap.isHittable else { return }
        toMap.tap()
        let screen = app.descendants(matching: .any).matching(identifier: "spot.official.mapScreen").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "「地図で見る」がアプリの中の地図を開かない")
        XCTAssertEqual(app.state, .runningForeground, "「地図で見る」でアプリの外へ出た")
        guard screen.exists else { return }
        XCTAssertTrue(app.buttons["spot.official.mapScreen.directions"].firstMatch.exists, "地図の画面に「経路」が無い")
        // 地図のタイルとピンの写真を待つ
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "13g-撮影スポット（アプリの中の地図）")
        goBack(app)
        Thread.sleep(forTimeInterval: 1)
    }

    /// 撮影スポットの画面で、光の時刻の日付の帯を画面の上の方へ寄せる（朝・夕の段と注記まで1枚に入れる）。
    /// 帯が出なければ `false`（撮らない）
    private func scrollToSpotLight(_ app: XCUIApplication) -> Bool {
        let date = app.descendants(matching: .any).matching(identifier: "spot.official.light.date").firstMatch
        var swipes = 0
        while swipes < 6, !(date.exists && date.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard date.exists, date.isHittable else { return false }
        date.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        Thread.sleep(forTimeInterval: 1)
        return true
    }

    /// **App Store 用の、日本の撮影スポットの絵**（2026-10-07・`Tools/store-screenshots.py` の材料）。
    /// 地図の札（鍋ヶ滝）から撮影スポットの画面を開き、上（70）と光の時刻（71）を撮って戻る。
    /// 一覧の先頭はシミュレータの現在地（パリ）に近いスポットになるので、ストアには使えない。
    /// 開けなければ撮らない（この試験の決まり）
    private func shootStoreSpot(_ app: XCUIApplication) {
        // **地図の札の「スポットを見る」からは開けなかった**（PR #171 の Mac の回で2回とも
        // 70・71 が欠けた）。13f が撮れている道——「スポット」の一覧の行（`map.spotRow`）——を使う。
        // 呼ぶのは「鍋ヶ滝」で絞っている間なので、一覧の先頭は鍋ヶ滝になる
        let spots = app.buttons["map.mode.spots"].firstMatch
        guard spots.waitForExistence(timeout: 5) else { return }
        spots.tap()
        defer {
            let map = app.buttons["map.mode.map"].firstMatch
            if map.exists { map.tap() }
        }
        let row = app.buttons["map.spotRow"].firstMatch
        guard row.waitForExistence(timeout: 10), row.isHittable else { return }
        row.tap()
        defer {
            goBack(app)
            Thread.sleep(forTimeInterval: 1)
        }
        // 表紙の写真（作例）が読み込まれるのを待つ
        Thread.sleep(forTimeInterval: 5)
        // 開いたのが鍋ヶ滝でなければ撮らない（名前と中身が食い違う絵は、無い絵より悪い）
        let named = NSPredicate(format: "label CONTAINS %@", "鍋ヶ滝")
        guard app.staticTexts.matching(named).firstMatch.waitForExistence(timeout: 5) else { return }
        shoot(app, "70-ストア・撮影スポット（鍋ヶ滝）")
        if scrollToSpotLight(app) {
            shoot(app, "71-ストア・光の時刻（鍋ヶ滝）")
        }
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
        // 出典の1行の当たりは 44pt 以上（押せるものの最小・2026-10-03）
        XCTAssertGreaterThanOrEqual(credit.frame.height, 44, "作例の出典の当たりが 44pt 未満")
        XCTAssertGreaterThanOrEqual(credit.frame.width, 44, "作例の出典の当たりが 44pt 未満")
        // 写真が読み込まれるのを待つ（Commons の縮小版）
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "13g-撮影スポット（作例）")
        shootComposeGuide(app)
    }

    /// **作例を重ねて撮る**（2026-10-09・2026-10-17 から全員無料）。作例の帯の下の入口を押し、撮る画面を撮って閉じる。
    /// 開くのに鍵は要らない。起動の鍵（`-JPComposeGuidePreview`）は線を出すためだけ。シミュレータにカメラは無いので
    /// 映像の枠は「カメラを使えません」になる（下の黒い面・上の札・出典の行は板どおりに出る）。
    /// 2026-10-18: 鍵があるときは作例もその上に重ねる——横長の作例が開いたときから 90° 回って
    /// 縦の枠に収まっているか（`ComposeControls.autoRotation`）を、この絵で見る。
    /// 入口・画面が出なければ撮らない（この試験の決まり）
    private func shootComposeGuide(_ app: XCUIApplication) {
        let entry = app.buttons["spot.official.composeGuide"].firstMatch
        var swipes = 0
        while swipes < 2, !(entry.exists && entry.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard entry.exists, entry.isHittable else { return }
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44, "作例を重ねて撮るの入口が 44pt 未満")
        shoot(app, "13g2-撮影スポット（作例を重ねて撮るの入口）")
        entry.tap()
        // 🔴 **開いたら必ず閉じる。** 閉じられないと全画面のまま残り、あとの 14〜61 がこの画面の絵に
        // なる・消える（PR #195 の1回目: 閉じるボタンが見つからず、14 がこの画面だった）
        let close = app.buttons["composeGuide.close"].firstMatch
        let shutter = app.buttons["composeGuide.shutter"].firstMatch
        guard close.waitForExistence(timeout: 10) || shutter.exists else { return }
        // 作例のサムネが読み込まれるのを待つ
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "13h-作例を重ねて撮る")
        shootLandscapeSample(app)
        if close.exists, close.isHittable {
            close.tap()
        } else {
            // 板の閉じるの位置（左上 12pt・上 52pt・44pt の丸）を直に押す
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.08)).tap()
        }
        Thread.sleep(forTimeInterval: 1)
        shootComposeGuideFromSecondSample(app)
    }

    /// **横長の作例が開いたときから 90° 回って縦の枠に収まる絵**（2026-10-18 owner「縦空くのは嫌」）。
    /// 右下の「作例を切り替える」で送り、回すボタンの値が「90度」になった作例で撮る
    /// （回す角度は作例の縦横から自動で決まる・`ComposeControls.autoRotation`）。
    /// 横長の作例が無い・切り替えが押せないスポットでは撮らない（この試験の決まり）
    private func shootLandscapeSample(_ app: XCUIApplication) {
        let rotate = app.buttons["composeGuide.rotate"].firstMatch
        let next = app.buttons["composeGuide.switch"].firstMatch
        func turned() -> Bool {
            guard rotate.exists, let value = rotate.value as? String else { return false }
            return value.hasPrefix("90")
        }
        var switches = 0
        while !turned(), switches < 6, next.exists, next.isHittable, next.isEnabled {
            next.tap()
            Thread.sleep(forTimeInterval: 1)
            switches += 1
        }
        guard turned() else { return }
        // 作例の写真が読み込まれるのを待つ（Commons の縮小版）
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "13h3-作例を重ねて撮る（横長の作例を回して収める）")
    }

    /// **作例の帯の2枚目を押して、その作例から撮る画面を開く**（2026-10-10・owner の報告「作例の1枚目しか
    /// 重ねられない」）。上の札が「作例 2 / N」になっていることを確かめて撮り、閉じる。
    /// 2枚目が無い・押せる所に無いスポットでは撮らない（この試験の決まり）
    private func shootComposeGuideFromSecondSample(_ app: XCUIApplication) {
        let cards = app.buttons.matching(identifier: "spot.official.sampleCard")
        guard cards.count >= 2 else { return }
        let second = cards.element(boundBy: 1)
        guard second.exists, second.isHittable else { return }
        second.tap()
        let close = app.buttons["composeGuide.close"].firstMatch
        guard close.waitForExistence(timeout: 10) else { return }
        // 札は必ず出る（作例が2枚以上ある）。出ているのに「作例 2」でなければ落とす
        let counter = app.descendants(matching: .any).matching(identifier: "composeGuide.counter").firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5), "撮る画面の上の札（作例の番号）が出ない")
        if counter.exists {
            XCTAssertTrue(counter.label.contains("作例 2 枚目") || counter.label.contains("example 2 of"),
                          "2枚目の作例から開いていない: \(counter.label)")
        }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "13h2-作例を重ねて撮る（2枚目から）")
        if close.isHittable {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.08)).tap()
        }
        Thread.sleep(forTimeInterval: 1)
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
            shootStoreSpot(app)
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
        // 2026-10-18 判断: この1本だけ時間の上限を 1200秒に上げる（実測 362〜462秒の約2.6倍）。
        // ほかの UI テストの既定は 300秒（`Tools/xcode-test.sh` の注記・上限の頭打ちも 1200秒）
        executionTimeAllowance = 1200
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
        // 初期ユーザー章の贈り物（`FoundingGiftGate`・全画面）は「受け取り済み」にして出さない。
        // 見本の利用者は章を持っていて、まだ名前の横に飾っていないと、新しいシミュレータの
        // 最初の3回の起動で全画面が上に被さり、タブも名前の行も押せなくなる（run 403）
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        // **「作例を重ねて撮る」の線を、カメラの無いシミュレータでも出す鍵**（Debug のみ・`ComposeGuideAccess`）。
        // 撮る画面の絵（13h）を撮るため。2026-10-17 から全員無料なので、開くのに鍵は要らない
        app.launchArguments += ["-JPComposeGuidePreview", "YES"]
        // 撮る画面の構図は端末に覚える（`CompositionPreferences`）。前の試験で選んだ構図を引きずらないよう、
        // 13h は既定の三分割で撮る（2026-10-10）
        app.launchArguments += ["-journey-photo-composition-last", "thirds"]
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
            // **「新着」を選んだ直後**（2026-10-11）。切り替えのすぐ下に新着の写真が並ぶ
            // （前は「撮影地を探す／写真から探す」の札と、おすすめの横並びが挟まり、結果がずっと下だった）。
            // 切り替えが出ていなければ撮らない。押せたのに横並び・札が出ていたら落とす
            if name == "ホーム" { shootHeaderBand(app) }
            if name == "ホーム" {
                let latest = app.buttons["新着"].firstMatch
                if latest.waitForExistence(timeout: 5), latest.isHittable {
                    latest.tap()
                    Thread.sleep(forTimeInterval: 3)
                    shoot(app, "10b-ホーム（新着を選んだ直後）")
                    XCTAssertFalse(app.descendants(matching: .any)["home.featured"].firstMatch.exists,
                                   "「新着」なのに、おすすめの横並びが切り替えの下に挟まっている")
                    XCTAssertFalse(app.buttons["home.exploreMap"].firstMatch.exists,
                                   "消したはずの「撮影地を探す」の札が出ている")
                }
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
            if name == "ホーム" { shootSpotShelf(app) }
            if name == "探す" {
                let field = app.textFields["search.field"].firstMatch
                if field.exists, field.isHittable {
                    field.tap()
                    field.typeText("zzzz-no-photo-result")
                    Thread.sleep(forTimeInterval: 2)
                    if app.buttons["search.emptyMap"].firstMatch.exists {
                        shoot(app, "11b-探す（0件から地図へ）")
                    }
                    // 🔴 **キーボードを閉じてから先へ進む**（2026-10-03・run 337 の絵 13・14 で確かめた）。
                    // 出たままだとタブの帯を覆い、「マップ」を押してもキーボードに当たり（13 が探す画面の
                    // まま）、右下の「マイページ」は🎤（音声入力）キーに当たって「Enable Dictation?」の札が
                    // 開いた。以降の操作が全部札に当たり、15・20・21・30・31・60・41 が黙って欠けていた。
                    // 焦点のあるうちに改行で確定する（焦点の無い `typeText` は失敗として記録される）
                    field.typeText("\n")
                    // 消すボタンは入力欄の外にある自前のボタン（`search.clear`）。OS の「Clear text」は無い。
                    // 見つからなくても落とさない（この試験の決まり: 出なければ撮らないだけ）
                    let clear = app.buttons["search.clear"].firstMatch
                    if clear.waitForExistence(timeout: 3), clear.isHittable { clear.tap() }
                    // 閉じたのを確かめてからタブへ（閉じなければ待つだけ・落とさない）
                    let keyboardGone = NSPredicate(format: "count == 0")
                    _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardGone, object: app.keyboards)],
                                       timeout: 5)
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
                // **旅の記録の下の、共同アルバムと旅行プランの入口**（2026-10-07）。
                // 名前の付いた行（`trips.albums`）だけを探し、画面に収まるまで送る。
                // 旅の一冊から戻れなかった回（詳細のまま）は在っても押せないので撮らない
                Thread.sleep(forTimeInterval: 2)
                let albumsRow = app.buttons["trips.albums"].firstMatch
                let rowBottom = app.windows.firstMatch.frame.maxY - 100
                var rowPushes = 0
                while albumsRow.exists, albumsRow.frame.maxY > rowBottom, rowPushes < 4 {
                    app.swipeUp()
                    Thread.sleep(forTimeInterval: 1)
                    rowPushes += 1
                }
                if albumsRow.waitForExistence(timeout: 5), albumsRow.isHittable {
                    shoot(app, "32-旅の記録の入口")
                }
                // **端末の写真の一冊の説明の札**（2026-10-16・写真の許可がまだのときだけ出る）。
                // 札は入口の行より上にあるので、押せる所まで戻して撮る。**許可のボタンは押さない**
                // （iOS の許可のダイアログが出て、後の節を覆う）。出なければ撮らない
                let deviceAllow = app.buttons["trips.deviceAllow"].firstMatch
                var allowPulls = 0
                while deviceAllow.exists, !deviceAllow.isHittable, allowPulls < 4 {
                    app.swipeDown()
                    Thread.sleep(forTimeInterval: 1)
                    allowPulls += 1
                }
                if deviceAllow.exists, deviceAllow.isHittable {
                    shoot(app, "33-端末の写真の一冊の説明")
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
        // **フィードを「おすすめ」へ戻す。** 一巡の `10c` が「フォロー中」に切り替えることがある
        // （鍵なしログインのフォロー一覧は空＝`feed.photo` が出ない）。
        let recommended = app.buttons["おすすめ"].firstMatch
        if recommended.waitForExistence(timeout: 5), recommended.isHittable {
            recommended.tap()
            Thread.sleep(forTimeInterval: 2)
        }
        // **写真そのものを名指しで押す**（`feed.photo`）。
        // 位置で探していたときは、今日のテーマの「参加する」に当たって
        // **ログイン画面を「写真の詳細」として撮って**いた（run 49）。
        let firstPhoto = app.buttons["feed.photo"].firstMatch
        // **画面の下（タブバーの裏）に隠れていたら送る（上限あり・`21` と同じ考え）。**
        // ホームは写真の前に今日のテーマ・発見の節が並ぶので、1枚目がタブバーの裏に
        // 掛かって `isHittable == false` になり、`20` と `21` が**黙って欠けて**いた。
        // `swipeUp` は勢いで1枚目ごと画面の上へ流しうるので、勢いの付かない短い引き
        // （画面の 35% ぶん）で少しずつ送る
        //
        // **まだ作られていない間も送る**（2026-10-03）。写真の一覧は
        // `LazyVStack` の下の方（季節の段・入口・おすすめの横並びの下）にあり、画面の外では**要素が
        // まだ無い**ことがある。前は「在る・押せない」間だけ送っていたので、無いと送らずに抜けた。
        // 上限を広げ、在って押せるまで送る（run 316〜337 で欠けていた主な原因は 11b のキーボード）
        var feedPushes = 0
        while !(firstPhoto.waitForExistence(timeout: 2) && firstPhoto.isHittable), feedPushes < 8 {
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

            // **写真から、次の旅へ**（2026-10-14）: 行き先の段（行きたい・経路・いつ）。
            // 撮影地の無い写真では出ない——**出なければ撮らない**（この試験の決まり）。
            // 少しずつ送って見える位置まで出す（上限あり）
            let trip = app.descendants(matching: .any).matching(identifier: "photo.trip").firstMatch
            if trip.waitForExistence(timeout: 3) {
                var tripPushes = 0
                while !app.buttons["photo.trip.wish"].firstMatch.isHittable, tripPushes < 3 {
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                    from.press(forDuration: 0.05, thenDragTo: to)
                    Thread.sleep(forTimeInterval: 1)
                    tripPushes += 1
                }
                let hasSpot = app.buttons["photo.trip.directions"].firstMatch.exists
                shoot(app, "20c-写真の詳細（行き先\(hasSpot ? "・撮影スポット" : "")）")
                // 撮影スポットの付いた写真なら、題の上の「撮影スポット」の行からスポットの頁へ（本番にまだ少ない・出なければ撮らない）
                let guide = app.buttons["photo.spotGuide"].firstMatch
                if guide.exists {
                    app.swipeDown()
                    Thread.sleep(forTimeInterval: 1)
                    if guide.isHittable {
                        guide.tap()
                        if app.buttons["spot.official.wish"].firstMatch.waitForExistence(timeout: 10) {
                            Thread.sleep(forTimeInterval: 2)
                            shoot(app, "20d-写真から撮影スポットへ")
                        }
                        app.navigationBars.buttons.firstMatch.tap()
                        Thread.sleep(forTimeInterval: 2)
                    }
                }
            }

            // 「この写真を見て撮影」の行（2026-10-14）。元の写真が付いた写真はまだ少なく、口は本番に
            // まだ無いこともある——**出なければ撮らない**（この試験の決まり）。押して元の写真へ移るのも撮る
            let inspiredLine = app.buttons["photo.inspiredBy"].firstMatch
            // 送らない（このあとの作者の行を画面の外へ押し出さないため）。見えていなければ撮らない
            if inspiredLine.waitForExistence(timeout: 3) {
                if inspiredLine.isHittable {
                    shoot(app, "20e-写真の詳細（この写真を見て撮影）")
                    inspiredLine.tap()
                    Thread.sleep(forTimeInterval: 4)
                    shoot(app, "20f-元の写真へ")
                    app.navigationBars.buttons.firstMatch.tap()
                    Thread.sleep(forTimeInterval: 2)
                }
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
                // 見出しのフォロー一覧の丸は消した（2026-10-09）。一覧へは数の札から開く。
                // 未ログイン・0人のときは押せない札なので、出なければ撮らない
                let followers = app.descendants(matching: .any)["profile.count.followers"].firstMatch
                if followers.waitForExistence(timeout: 3), followers.isHittable {
                    followers.tap()
                    Thread.sleep(forTimeInterval: 3)
                    shoot(app, "21b-人のページの数の札からフォロワー一覧")
                    app.navigationBars.buttons.firstMatch.tap()
                    Thread.sleep(forTimeInterval: 1)
                }
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
            if app.descendants(matching: .any).matching(identifier: "spot.official.journeyCue").firstMatch.exists {
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
    /// 🔴 **写真は見本の1枚を選んだ状態で開く**（`-JPPreviewUploadSample YES`・Debug のみ・2026-10-14）。
    /// 選ぶ画面（PHPicker）は別プロセスで、中の写真に触れない回が続き、run 428 まで 42〜45c が
    /// 1枚も撮れていなかった。見本が入らなかった回だけ、前の道（ライブラリから1枚選ぶ）を試す。
    /// どちらでも**出なければ撮らない**（この試験の決まり）
    func testCapturesUploadEditEntry() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewUploadSample", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        guard toPhoto.waitForExistence(timeout: 5), toPhoto.isHittable else { return }
        toPhoto.tap()

        // 見本の1枚が帯に入れば、選ぶ画面を通らない
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        if !thumb.waitForExistence(timeout: 15) {
            pickFirstLibraryPhoto(app)
        }
        captureUploadScreens(app, thumb: thumb)
    }

    /// 前の道: 帯の「追加」→「ライブラリから選ぶ」→ 1枚目（見本が入らなかった回だけ）
    private func pickFirstLibraryPhoto(_ app: XCUIApplication) {
        // 2026-10-03: 投稿画面は**開くと写真を選ぶ画面が自動で出る**（`UploadDetails.autoOpensLibrary`）。
        // 出るのを待ち、出なかった回（帯の「追加」がまだ押せる）だけ「追加」→「ライブラリから選ぶ」。
        // 未ログインの回はログイン画面で「追加」が無いので、ここで抜ける
        let add = app.descendants(matching: .any).matching(identifier: "upload.add").firstMatch
        guard add.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 2)
        if add.isHittable {
            add.tap()
            let library = app.buttons["ライブラリから選ぶ"].firstMatch
            guard library.waitForExistence(timeout: 5) else { return }
            library.tap()
        }

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
    }

    /// 42b・42c: 「撮影地の位置を付ける」のオンとオフ（2026-10-18）。撮ったらオンに戻す
    private func captureLocationToggle(_ app: XCUIApplication) {
        let toggle = app.switches["upload.attachLocation"].firstMatch
        for _ in 0..<2 where !(toggle.exists && toggle.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        guard toggle.exists, toggle.isHittable else { return }
        // 撮る前の値を確かめる（前の回のオフが残っていたら、まずオンに戻す）
        guard setLocationToggle(toggle, on: true) else {
            XCTFail("「撮影地の位置を付ける」をオンにできない（値: \(String(describing: toggle.value))）")
            return
        }
        shoot(app, "42b-投稿（撮影地の位置を付ける・オン）")
        if setLocationToggle(toggle, on: false) {
            shoot(app, "42c-投稿（撮影地の位置を付ける・オフ）")
        } else {
            XCTFail("押しても「撮影地の位置を付ける」がオフにならない（値: \(String(describing: toggle.value))）")
        }
        // 🔴 **最後は必ずオンに戻す**（値は人ごとに端末に残る。あとの絵・試験をオフのまま撮らない）
        XCTAssertTrue(setLocationToggle(toggle, on: true),
                      "「撮影地の位置を付ける」をオンに戻せなかった（値: \(String(describing: toggle.value))）")
        // 下の絵（43〜）は上から探すので、元の位置へ戻す
        app.swipeDown()
        Thread.sleep(forTimeInterval: 1)
    }

    /// 切り替えを `on` にする（押して値を確かめる・3回まで）。なれたら true
    private func setLocationToggle(_ toggle: XCUIElement, on: Bool) -> Bool {
        let want = on ? "1" : "0"
        for _ in 0..<3 {
            if (toggle.value as? String) == want { return true }
            // つまみは行の右端（文字の上を押しても切り替わらない版がある）
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1)
        }
        return (toggle.value as? String) == want
    }

    /// 投稿画面の 42〜45c（帯に写真が1枚入った状態から）
    private func captureUploadScreens(_ app: XCUIApplication, thumb: XCUIElement) {
        // 帯のサムネと「写真を編集」が出たら撮る（読み込みに数秒かかる）
        guard thumb.waitForExistence(timeout: 15) else { return }
        let editButton = app.buttons["upload.editButton"].firstMatch
        guard editButton.waitForExistence(timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "42-投稿（写真の編集の入口）")

        // 2026-10-18: 「撮影地の位置を付ける」の切り替え（撮影地の欄の上）。オンとオフの両方を撮り、
        // **オンに戻す**（選んだ値は人ごとに端末に残る・あとの絵をオフのまま撮らない）。出なければ撮らない
        captureLocationToggle(app)

        // 2026-10-03: 撮影地・作例の一言と、畳んだ「詳しい設定」（計画9）。下へ送って撮り、
        // 開いた絵も撮る。出なければ撮らない（この試験の決まり）
        let details = app.buttons["upload.details"].firstMatch
        for _ in 0..<3 where !(details.exists && details.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        guard details.exists, details.isHittable else { return }
        shoot(app, "43-投稿（撮影地と詳しい設定・畳んだ）")
        details.tap()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "44-投稿（詳しい設定・開いた）")

        // 2026-10-14: 「この写真を見て撮影」の欄と、元の写真を選ぶ画面（保存した写真・行きたい場所）。
        // 選ぶ画面は閉じるだけ（選ぶと書きかけが増える）。出なければ撮らない（この試験の決まり）
        let inspired = app.buttons["upload.inspired"].firstMatch
        // 欄は「詳しい設定」の上にある。開いた設定の下に隠れていたら下へ送って探す（上限あり）
        for _ in 0..<3 where !(inspired.exists && inspired.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        guard inspired.exists, inspired.isHittable else { return }
        shoot(app, "45-投稿（この写真を見て撮影の欄）")
        inspired.tap()
        let savedShelf = app.buttons["inspiredPicker.shelf.saved"].firstMatch
        guard savedShelf.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "45b-元の写真を選ぶ")
        let wishShelf = app.buttons["inspiredPicker.shelf.wishlist"].firstMatch
        if wishShelf.exists, wishShelf.isHittable {
            wishShelf.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "45c-元の写真を選ぶ（行きたい場所）")
        }
        let close = app.buttons["inspiredPicker.close"].firstMatch
        if close.exists, close.isHittable { close.tap() }
    }

    /// **「この写真を見て撮影」の見本**（2026-10-14・`-JPPreviewInspired YES`・Debug のみ）。
    /// 元の写真の付いた写真も `GET /user/inspired` も本番にまだ無いので、見本の鍵で
    /// 写真の詳細の行（20e）・元の写真へ（20f）・元の写真を選んだ投稿の欄（45d）を撮る。
    /// 見本は画面の状態だけ（サーバー・端末の控えには書かない）。**出なければ撮らない**
    func testCapturesInspiredBy() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewUploadSample", "YES", "-JPPreviewInspired", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }

        // 写真の詳細（ホームの写真を名指しで押す・一巡と同じく短い引きで少しずつ送る）
        let firstPhoto = app.buttons["feed.photo"].firstMatch
        var pushes = 0
        while !(firstPhoto.waitForExistence(timeout: 2) && firstPhoto.isHittable), pushes < 8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            pushes += 1
        }
        if firstPhoto.exists, firstPhoto.isHittable {
            firstPhoto.tap()
            let line = app.buttons["photo.inspiredBy"].firstMatch
            if line.waitForExistence(timeout: 10) {
                // 作者の行の下にある。見えるまで短い引きで送る（上限あり）
                var linePushes = 0
                while !line.isHittable, linePushes < 4 {
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                    from.press(forDuration: 0.05, thenDragTo: to)
                    Thread.sleep(forTimeInterval: 1)
                    linePushes += 1
                }
                if line.isHittable {
                    Thread.sleep(forTimeInterval: 2)
                    shoot(app, "20e-写真の詳細（この写真を見て撮影）")
                    line.tap()
                    Thread.sleep(forTimeInterval: 4)
                    shoot(app, "20f-元の写真へ")
                }
            }
        }

        // 投稿画面（見本の1枚・見本の元の写真を選んだ状態）。開いた詳細は戻ってから（下のタブを出す）
        for _ in 0..<2 where !(tabBar.exists && tabBar.isHittable) {
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
            Thread.sleep(forTimeInterval: 2)
        }
        guard tabBar.exists, tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        guard toPhoto.waitForExistence(timeout: 5), toPhoto.isHittable else { return }
        toPhoto.tap()
        let inspired = app.buttons["upload.inspired"].firstMatch
        guard app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 15),
              inspired.waitForExistence(timeout: 10) else { return }
        for _ in 0..<3 where !inspired.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        guard inspired.isHittable else { return }
        // 見本の元の写真が欄に入る（公開一覧を読むので少し待つ）
        Thread.sleep(forTimeInterval: 4)
        shoot(app, "45d-投稿（元の写真を選んだ欄）")
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
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
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

        // 2026-10-11: 前提（写真を編集が開いた）が揃ったら、保存は右上・撮影日は日付ピッカーか
        // 「日付を入れる」（手打ちの欄ではない）。違えば落とす
        XCTAssertTrue(app.navigationBars.buttons["editPhoto.save"].firstMatch.exists, "写真を編集の保存が右上に無い")
        let datePicker = app.descendants(matching: .any).matching(identifier: "editPhoto.date").firstMatch
        let dateSet = app.buttons["editPhoto.date.set"].firstMatch
        for _ in 0..<3 where !(datePicker.exists && datePicker.isHittable) && !(dateSet.exists && dateSet.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(datePicker.exists || dateSet.exists, "撮影日が日付ピッカーでない")
        // 撮影地は撮影日より下。一覧は画面の外の行を作らないので、見えるまで送ってから確かめる（run 407）
        let placeLabel = app.descendants(matching: .any).matching(identifier: "editPhoto.placeLabel").firstMatch
        for _ in 0..<3 where !placeLabel.exists {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(placeLabel.exists, "撮影地の欄に名前が無い")
        shoot(app, "22b-写真を編集（欄の名前・撮影日）")
    }

    /// **「新しくなったこと」**（2026-10-04・`WhatsNewView`）。更新して初めて開いた人に出るシート。
    ///
    /// 更新した人を起動の引数で作る: 規約に同意済み（`-legal.consent.version 1`）・前に見た版が古い
    /// （`-whatsNew.seenVersion 0.0.1`）。どちらも UserDefaults の引数の領域で、端末には書かない。
    /// 出たら撮って、主ボタン「はじめる」で閉じられることも見る。出なければ撮らない（この試験の決まり）
    func testCapturesWhatsNew() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "1"]
        app.launchArguments += ["-whatsNew.seenVersion", "0.0.1"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        // 見出しの文字で待つ（目印が部品の作りで変わっても、出たかどうかは見分けられる）
        let title = app.staticTexts["新しくなったこと"].firstMatch
        guard title.waitForExistence(timeout: 20) else { return }
        let close = app.buttons["whatsNew.close"].firstMatch
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "02b-新しくなったこと")
        if close.exists { close.tap() } else { app.buttons["はじめる"].firstMatch.tap() }
        // 閉じたあとはホームが見える（主ボタンで閉じられる）
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 5)
    }

    /// **設定から開いた「新しくなったこと」の履歴**（2026-10-18・`WhatsNewView(mode: .history)`）。
    ///
    /// 入口は設定の「新しくなったこと」の行（`settings.whatsNew`）。設定は全部の版を `mode: .history` で渡すので、
    /// 2枚目（「これまでのお知らせ」と版の区切りの見出し）まで撮れる。シートが開いたのに履歴が無ければ落とす
    func testCapturesWhatsNewHistory() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15) else { return }
        let gear = app.buttons["設定"].firstMatch
        guard gear.waitForExistence(timeout: 5), gear.isHittable else { return }
        gear.tap()
        let row = app.buttons["settings.whatsNew"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return }
        var pushes = 0
        while !row.isHittable, pushes < 8 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard row.isHittable else { return }
        row.tap()
        // シートの主ボタンで待つ——見出しの文字「新しくなったこと」は設定の行にもあり、開く前に通ってしまう
        let close = app.buttons["whatsNew.close"].firstMatch
        guard close.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "02e-新しくなったこと（設定から）")

        // 履歴の形のときだけ: 「これまでのお知らせ」と版の区切りが見えるまで送って撮る
        let history = app.descendants(matching: .any)["whatsNew.history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5), "設定から開いた「新しくなったこと」が履歴の形でない")
        if history.exists {
            // 見えているだけでは送らない——「これまでのお知らせ」が画面の上半分に来るまで送る（画面の下の端に
            // 見出しだけ覗いた姿は 02e と同じ絵になる）
            var down = 0
            while !history.isHittable || history.frame.minY > app.frame.height * 0.45, down < 4 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                down += 1
            }
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "02f-新しくなったこと（これまでのお知らせ）")
        }
        if close.exists, close.isHittable { close.tap() }
    }

    /// **Pro の画面**（第2段階・2026-10-09）: 設定の「Pro」の節（板 43）と、
    /// マイページの名前の行 → 名前の横の画面の「PRO 限定」（板 BadgePicker）。
    ///
    /// 鍵を持たないログイン（`-JPPreviewUserId`）なので、自分のプロフィールは読めない。名前の横の画面は
    /// 公開プロフィールで開き、見本の利用者は**公開プロフィールでは Pro**＝「Pro で集める」は出ない
    /// （2026-10-10・run 387 で 82・81 が撮れなかった理由）。82 は「PRO 限定」の眉ラベルで見つける。
    /// Pro の案内（81）は `testCapturesProPaywall` で撮る。**何も買わない**。出なければ撮らない（この試験の決まり）
    func testCapturesProScreens() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15) else { return }

        // 名前の横の画面（PRO 限定の段まで送って撮る）。名前の行はプロフィールが読めてから出る
        // （`testCapturesNameSideBadge` と同じく 20 秒待つ）
        let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
        if nameLine.waitForExistence(timeout: 20), nameLine.isHittable {
            nameLine.tap()
            if app.descendants(matching: .any)["nameSide.save"].firstMatch.waitForExistence(timeout: 10) {
                // Pro でない人には「Pro で集める」、Pro の人には眉ラベルだけが出る
                let collect = app.buttons["nameSide.proCollect"].firstMatch
                let label = app.staticTexts["PRO 限定"].firstMatch
                let section = collect.exists ? collect : label
                if section.waitForExistence(timeout: 5) {
                    var pushes = 0
                    while !section.isHittable, pushes < 3 {
                        app.swipeUp()
                        Thread.sleep(forTimeInterval: 1)
                        pushes += 1
                    }
                    Thread.sleep(forTimeInterval: 2)
                    shoot(app, "82-名前の横（PRO 限定）")
                }
            }
            // シートを下ろす
            let close = app.buttons["閉じる"].firstMatch
            if close.waitForExistence(timeout: 3), close.isHittable { close.tap() }
            Thread.sleep(forTimeInterval: 1)
        }

        // 設定の Pro の節。鍵を持たないログインでは Pro かどうか分からず、Pro の行は
        // 「App Store で管理」を開く（ProStatusText.settingsAction）ので押さない
        let gear = app.buttons["設定"].firstMatch
        guard gear.waitForExistence(timeout: 5), gear.isHittable else { return }
        gear.tap()
        let proRow = app.buttons["settings.pro"].firstMatch
        guard proRow.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "80-設定（Pro の節）")
        shootCompositionCatalog(app)

        // **「前の晩に知らせる」の「通知がオフのため届きません」**（2026-10-11・`LightAlertPushNotice`）。
        // 見本の利用者は公開プロフィールで Pro なので入切の行が出る。CI のシミュレータは通知を許可して
        // いない（どの試験も通知の許可を押さない）ので、入切が「入」なら知らせも出るはず——出なければ落とす。
        // 入切の行が出ない（プロフィールが読めない）・「切」の回は撮らない（この試験の決まり）
        let lightAlert = app.switches["settings.lightAlert"].firstMatch
        guard lightAlert.waitForExistence(timeout: 10) else { return }
        var pushes = 0
        while !lightAlert.isHittable, pushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard lightAlert.isHittable, (lightAlert.value as? String) == "1" else { return }
        let notice = app.buttons["settings.lightAlert.pushOff"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5),
                      "通知を許可していない端末で「前の晩に知らせる」が入なのに、届かないことを知らせていない")
        guard notice.exists else { return }
        if !notice.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 1) }
        XCTAssertGreaterThanOrEqual(notice.frame.height, 44, "「通知がオフのため届きません」の行が 44pt 未満")
        shoot(app, "80b-設定（Pro の節・通知がオフ）")
    }

    /// 設定の構図一覧と三分割の解説。撮影画面のガイドと同じデータを表示する。
    /// 開けない回はほかのスクリーンショットに影響させない。
    private func shootCompositionCatalog(_ app: XCUIApplication) {
        let entry = app.buttons["settings.compositionCatalog"].firstMatch
        var pushes = 0
        while !entry.isHittable, pushes < 6 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard entry.exists, entry.isHittable else { return }
        entry.tap()
        let third = app.buttons["composition.catalog.thirds"].firstMatch
        guard third.waitForExistence(timeout: 5) else {
            goBack(app)
            return
        }
        shoot(app, "83-設定（構図一覧）")
        if third.isHittable {
            third.tap()
            if app.staticTexts["どんな構図？"].firstMatch.waitForExistence(timeout: 5) {
                shoot(app, "84-構図の解説（三分割）")
            }
            goBack(app)
        }
        goBack(app)
    }

    /// **通知の説明**（2026-10-11・`PushPrimerView`）。ふだんは初めての投稿が上がったときに1回だけ出る。
    /// 鍵を持たない入り方では投稿できないので、起動の鍵（`-JPPreviewPushPrimer`・Debug のみ）で起動のときに出す。
    ///
    /// 出なければ撮らずに抜ける（この試験の決まり）。**出たのに「通知を受け取る」「あとで」が無い・44pt 未満・
    /// 「あとで」で閉じなければ落とす**。「通知を受け取る」は押さない（シミュレータに許可を残さない）
    func testCapturesPushPrimer() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        // 初期ユーザー章の贈り物（全画面）が説明の上に被さらないように止める（ほかの試験と同じ・run 403）
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewPushPrimer", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let allow = app.buttons["push.primer.allow"].firstMatch
        guard allow.waitForExistence(timeout: 20) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "02c-通知の説明")
        let later = app.buttons["push.primer.later"].firstMatch
        XCTAssertTrue(later.exists, "「あとで」が無い（断る口が無い）")
        XCTAssertGreaterThanOrEqual(allow.frame.height, 44, "「通知を受け取る」が 44pt 未満")
        XCTAssertGreaterThanOrEqual(later.frame.height, 44, "「あとで」が 44pt 未満")
        guard later.exists, later.isHittable else { return XCTFail("「あとで」を押せない") }
        later.tap()
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: allow)], timeout: 5)
        XCTAssertEqual(closed, .completed, "「あとで」で説明が閉じない")
    }

    /// **すれちがい**（板「10 すれちがい」・きっぷは案C・2026-10-16）: ホームの「カードが届きました」の札 →
    /// 束を開く（表）→ 写真を押して全面 → 閉じる → 下を押して裏返す（裏）→「帳に入れる」→ すれちがい帳。起動の鍵（`-JPPreviewPass`・Debug のみ）で、公開一覧の
    /// 写真から見本のカードを7枚入れる（シミュレータには Bluetooth が無く、本物のカードは届かない）。
    ///
    /// **札が出なければ落とす**（ほかの試験の「出なければ抜ける」とは違う・2026-10-16 の読み直し）。
    /// 束が開かない・閉じる／ありがとう／帳に入れるが 44pt 未満・帳が開かなければ落とす
    func testCapturesPass() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewPass", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let open = app.buttons["pass.home.open"].firstMatch
        // 札が出なければ落とす（2026-10-16 の読み直し: 出ないまま抜けると、札の .task が走らない回を見逃した）
        guard open.waitForExistence(timeout: 45) else {
            return XCTFail("見本のカードを入れたのに、ホームに「カードが届きました」の札が出ない")
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "80-すれちがいの束")
        open.tap()

        let card = app.descendants(matching: .any)["pass.viewer.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "札を押しても束が開かない")
        Thread.sleep(forTimeInterval: 2)
        // 表はマルス券（2026-10-17 owner「マルス券いいね」）: 「〇〇発 → 〇〇着」と「ずっと有効」
        XCTAssertTrue(card.label.contains("着"), "表の区間が「〇〇発、〇〇着」と読めない（\(card.label)）")
        XCTAssertTrue(card.label.contains("ずっと有効"), "表に「すれちがいの日から ずっと有効」が無い（\(card.label)）")
        shoot(app, "81-すれちがいのカード（表）")
        // 写真（きっぷの上 214/430・マルス券）を押すと全面で見る
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let photoClose = app.buttons["pass.photo.close"].firstMatch
        XCTAssertTrue(photoClose.waitForExistence(timeout: 5), "写真を押しても全面で見られない")
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "84-すれちがいの写真（全面）")
        XCTAssertGreaterThanOrEqual(photoClose.frame.height, 44, "全面の × が 44pt 未満")
        photoClose.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // きっぷの下（写真ではない所）を押すと裏返る
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(card.label.contains("ご案内"), "裏に「ご案内」の帯が無い（\(card.label)）")
        XCTAssertTrue(card.label.contains("届きました"), "裏の裾に由来の一行が無い（\(card.label)）")
        shoot(app, "82-すれちがいのカード（裏）")

        let close = app.buttons["pass.viewer.close"].firstMatch
        let thanks = app.buttons["pass.viewer.thanks"].firstMatch
        let file = app.buttons["pass.viewer.file"].firstMatch
        for (button, name) in [(close, "閉じる"), (thanks, "ありがとう"), (file, "帳に入れる")] {
            XCTAssertTrue(button.exists, "「\(name)」が無い")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "「\(name)」が 44pt 未満")
        }
        guard file.exists, file.isHittable else { return XCTFail("「帳に入れる」を押せない") }
        file.tap()
        let book = app.staticTexts["すれちがい帳"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10), "「帳に入れる」で帳が開かない")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "83-すれちがい帳")
    }

    /// **自分のカード（乗車券の見本）を回す**（2026-10-16 owner の頼み）: マイページ → 設定 → すれちがい →
    /// わたしの乗車券。見本は届いたカードと同じ回る部品（`PassSpinCard`）。起動の鍵（`-JPPreviewPass`）で区間を
    /// 「東京 → フランス」・ひとことつきにしてあるので、表（字数の違う発・着がそろうか）と裏を撮る。
    ///
    /// 画面まで行けなければ撮らずに抜ける。**出たのに「裏を見る」が無い・44pt 未満・押しても裏にならない・
    /// 横に回しても裏にならなければ落とす**
    /// わたしの乗車券（マイページ → 設定 → すれちがい → わたしの乗車券）まで進めて、回る見本を返す。
    /// 画面まで行けなければ nil（撮らずに抜ける）。`pro` は見本の利用者を Pro の姿にする（`-JPPreviewPro`）
    private func openPassPick(pro: Bool = false) -> (XCUIApplication, XCUIElement)? {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewPass", "YES"]
        if pro { app.launchArguments += ["-JPPreviewPro", "YES"] }
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return nil }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15) else { return nil }
        let gear = app.buttons["設定"].firstMatch
        guard gear.waitForExistence(timeout: 5), gear.isHittable else { return nil }
        gear.tap()
        let row = app.buttons["settings.pass"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return nil }
        var pushes = 0
        while !row.isHittable, pushes < 6 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard row.isHittable else { return nil }
        row.tap()
        let cardRow = app.buttons["pass.settings.card"].firstMatch
        guard cardRow.waitForExistence(timeout: 10), cardRow.isHittable else { return nil }
        cardRow.tap()
        let card = app.descendants(matching: .any)["pass.pick.card"].firstMatch
        guard card.waitForExistence(timeout: 15) else {
            XCTFail("乗車券の画面に回る見本が無い")
            return nil
        }
        return (app, card)
    }

    /// **特別な券面**（Pro・2026-10-17 owner が確定）: わたしの乗車券で、券面を選ぶ欄の5つを順に押し、見本の表を撮る。
    /// 見本の利用者を Pro の姿（`-JPPreviewPro`）にして選べるようにする。最後に選ぶ欄を撮る。
    ///
    /// 画面まで行けなければ撮らずに抜ける。**欄が出たのに券面のボタンが無い・44pt 未満・押しても読み上げが
    /// 券面の名前を言わなければ落とす**
    func testCapturesPassFaces() {
        guard let (app, card) = openPassPick(pro: true) else { return }
        Thread.sleep(forTimeInterval: 3)
        let faces: [(id: Int, name: String, shot: String)] = [
            (1, "真鍮の金属板", "88a-券面 01 真鍮の金属板"), (2, "大圏航路", "88b-券面 06 大圏航路"),
            (3, "箔押しの硬券", "88c-券面 10 箔押しの硬券"), (4, "漆と蒔絵", "88d-券面 21 漆と蒔絵"),
            (5, "型押しの革", "88e-券面 26 型押しの革"),
        ]
        for face in faces {
            let button = app.buttons["pass.pick.face.\(face.id)"].firstMatch
            guard button.waitForExistence(timeout: 10) else { return XCTFail("券面「\(face.name)」のボタンが無い") }
            // 券面の欄は横に並ぶ。右に隠れていたら一つ前の券面の上で左へ払う・下に隠れていたら送る
            var pushes = 0
            while !button.isHittable, pushes < 4 {
                let previous = app.buttons["pass.pick.face.\(face.id - 1)"].firstMatch
                if button.frame.minX > app.frame.maxX - 40, previous.exists {
                    previous.swipeLeft()
                } else {
                    app.swipeUp()
                }
                Thread.sleep(forTimeInterval: 1)
                pushes += 1
            }
            guard button.isHittable else { return XCTFail("券面「\(face.name)」を押せない") }
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "券面「\(face.name)」のボタンが 44pt 未満")
            button.tap()
            Thread.sleep(forTimeInterval: 1)
            // 見本が画面の上に隠れていたら戻す
            pushes = 0
            while card.frame.minY < 60, pushes < 4 {
                app.swipeDown()
                Thread.sleep(forTimeInterval: 1)
                pushes += 1
            }
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(card.label.contains(face.name), "見本の読み上げが券面「\(face.name)」を言わない（\(card.label)）")
            shoot(app, face.shot)
        }
        // 選ぶ欄を左端に戻して撮る
        let last = app.buttons["pass.pick.face.5"].firstMatch
        if last.exists, last.isHittable {
            last.swipeRight()
            Thread.sleep(forTimeInterval: 1.5)
            shoot(app, "88f-券面を選ぶ")
        }
    }

    /// **券面ごとの裏**（2026-10-18 札 #306・板「すれちがい乗車券の裏面」）: わたしの乗車券で、マルス券と特別な券面の5つを
    /// 順に選び、「裏を見る」で裏返して撮り、表に戻す。見本の利用者は Pro の姿（`-JPPreviewPro`・Debug のみ）。
    ///
    /// 画面まで行けなければ撮らずに抜ける。**券面のボタンが無い・押せない・裏返らない・裏に「ご案内」が無い・
    /// 特別な券面の裏が券面の名前を言わない（＝裏がマルス券のまま）なら落とす**
    func testCapturesPassFaceBacks() {
        guard let (app, card) = openPassPick(pro: true) else { return }
        Thread.sleep(forTimeInterval: 3)
        let backs: [(id: Int, name: String, shot: String)] = [
            (0, "マルス券", "89a-裏 00 マルス券"), (1, "真鍮の金属板", "89b-裏 01 真鍮の金属板"),
            (2, "大圏航路", "89c-裏 06 大圏航路"), (3, "箔押しの硬券", "89d-裏 10 箔押しの硬券"),
            (4, "漆と蒔絵", "89e-裏 21 漆と蒔絵"), (5, "型押しの革", "89f-裏 26 型押しの革"),
        ]
        let flip = app.buttons["pass.pick.flip"].firstMatch
        let side = { (card.value as? String) ?? "" }
        for back in backs {
            let button = app.buttons["pass.pick.face.\(back.id)"].firstMatch
            guard button.waitForExistence(timeout: 10) else { return XCTFail("券面「\(back.name)」のボタンが無い") }
            // 券面の欄は横に並ぶ。右に隠れていたら一つ前の券面の上で左へ払う・下に隠れていたら送る（testCapturesPassFaces と同じ）
            var swipes = 0
            while !button.isHittable, swipes < 4 {
                let previous = app.buttons["pass.pick.face.\(back.id - 1)"].firstMatch
                if button.frame.minX > app.frame.maxX - 40, previous.exists {
                    previous.swipeLeft()
                } else {
                    app.swipeUp()
                }
                Thread.sleep(forTimeInterval: 1)
                swipes += 1
            }
            guard button.isHittable else { return XCTFail("券面「\(back.name)」を押せない") }
            button.tap()
            Thread.sleep(forTimeInterval: 1)
            // 見本が画面の上に隠れていたら戻す
            var pulls = 0
            while card.frame.minY < 60, pulls < 4 {
                app.swipeDown()
                Thread.sleep(forTimeInterval: 1)
                pulls += 1
            }
            guard flip.waitForExistence(timeout: 5), flip.isHittable else { return XCTFail("「裏を見る」を押せない") }
            flip.tap()
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(side().hasSuffix("裏"), "「裏を見る」で裏返らない（\(back.name)・\(side())）")
            XCTAssertTrue(card.label.contains("ご案内"), "裏に「ご案内」の帯が無い（\(back.name)・\(card.label)）")
            if back.id != 0 {
                XCTAssertTrue(card.label.contains(back.name), "裏が券面「\(back.name)」を言わない＝マルス券の裏のまま（\(card.label)）")
            }
            shoot(app, back.shot)
            // 表に戻す（次の券面を選ぶ）
            flip.tap()
            Thread.sleep(forTimeInterval: 1.5)
            XCTAssertTrue(side().hasSuffix("表"), "「表を見る」で表に戻らない（\(back.name)・\(side())）")
        }
    }

    func testCapturesPassOwnCard() {
        guard let (app, card) = openPassPick() else { return }
        Thread.sleep(forTimeInterval: 3)
        // 呼び名は「わたしの乗車券」（2026-10-17 owner）
        XCTAssertTrue(app.navigationBars["わたしの乗車券"].firstMatch.exists, "選ぶ画面の題が「わたしの乗車券」でない")
        // 表はマルス券（2026-10-17）: 「東京発、フランス着」と読む・「乗車券」の名
        XCTAssertTrue(card.label.contains("発、") && card.label.contains("着"),
                      "見本の区間が「〇〇発、〇〇着」と読めない（\(card.label)）")
        XCTAssertTrue(card.label.contains("乗車券"), "見本の表に「乗車券」が無い（\(card.label)）")
        // 見本の日付・区間・回数は空（「—」）。読み上げは「ダッシュ」でなく「なし」（2026-10-17）
        XCTAssertTrue(card.label.contains("日付 なし"), "空の欄が「なし」と読めない（\(card.label)）")
        XCTAssertFalse(card.label.contains("—"), "空の欄の「—」をそのまま読ませている（\(card.label)）")
        shoot(app, "85-自分のカード（表・東京→フランス）")
        let flip = app.buttons["pass.pick.flip"].firstMatch
        XCTAssertTrue(flip.exists, "回さずに裏を見る口（「裏を見る」）が無い")
        XCTAssertGreaterThanOrEqual(flip.frame.height, 44, "「裏を見る」が 44pt 未満")
        let value = { (card.value as? String) ?? "" }
        XCTAssertTrue(value().hasSuffix("表"), "読み上げで表と言わない（\(value())）")
        guard flip.isHittable else { return XCTFail("「裏を見る」を押せない") }
        flip.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(value().hasSuffix("裏"), "「裏を見る」で裏にならない（\(value())）")
        XCTAssertTrue(card.label.contains("届きます"), "見本の裏の裾が自分向け（「届きます」）でない（\(card.label)）")
        shoot(app, "86-自分のカード（裏）")
        // 表に戻してから、指を置いて横に回す（ScrollView の中でも回る・離すと近い面＝裏に吸い付く）
        flip.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let from = card.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75))
        let to = card.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.75))
        from.press(forDuration: 0.4, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(value().hasSuffix("裏"), "見本を指で横に回しても裏にならない（\(value())）")
        shoot(app, "87-自分のカード（指で回した後）")
    }

    /// **構図を重ねて撮る**（2026-10-10・2026-10-17 から全員無料）: 投稿のシートの4つ目の入口 → 作例なしの撮る画面 →
    /// 構図のシート → 黄金螺旋を選んで重ねた撮る画面。シミュレータにカメラは無いので映像の枠は「カメラを使えません」で、
    /// 線は起動の鍵（`-JPComposeGuidePreview`・Debug のみ）があるときだけ重なる。
    ///
    /// 入口・画面が出なければ撮らずに抜ける（この試験の決まり）。**出たのに中身が違えば落とす**
    /// （作例なしなのに上の札がある・構図の行が無い・選んだ構図にならない）。
    /// 終わったら三分割に戻す（構図は端末に覚えるので、あとの試験の絵に残さない）
    func testCapturesCompositionGuide() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPComposeGuidePreview", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let entry = app.buttons["post.choice.composition"].firstMatch
        guard entry.waitForExistence(timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "40b-投稿の選択（構図を重ねて撮るの入口）")
        guard entry.isHittable else { return }
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44, "構図を重ねて撮るの入口が 44pt 未満")
        entry.tap()

        // 前提はそろった（入口が出て押せた・Pro の確かめは起動の鍵で飛ばす）。アプリは投稿のシートが
        // 閉じきってから撮る画面を開く（`RootView.openCompositionAfterPostSheet`）ので、出なければ落とす
        let close = app.buttons["composeGuide.close"].firstMatch
        guard close.waitForExistence(timeout: 15) else {
            shoot(app, "13i-構図を重ねて撮る（出なかった）")
            XCTFail("投稿のシートの「構図を重ねて撮る」を押したのに撮る画面が出ない")
            return
        }
        // 作例なし: 構図の行はある・上の札（作例の番号）と作例の切り替えは無い
        let row = app.buttons["composeGuide.composition"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "撮る画面に構図の行が無い")
        XCTAssertFalse(app.descendants(matching: .any)["composeGuide.counter"].firstMatch.exists,
                       "作例なしなのに作例の番号の札が出ている")
        XCTAssertFalse(app.buttons["composeGuide.switch"].firstMatch.exists, "作例なしなのに作例の切り替えが出ている")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "13i-構図を重ねて撮る（作例なし）")
        defer {
            if close.exists, close.isHittable { close.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        guard row.isHittable else { return }
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "構図の行が 44pt 未満")
        row.tap()

        // 構図のシート。黄金比の段へ飛んでから黄金螺旋を選ぶ
        let golden = app.buttons["composition.chip.golden"].firstMatch
        guard golden.waitForExistence(timeout: 8) else {
            XCTFail("構図の行を押したのに構図のシートが出ない")
            return
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "13j-構図のシート")
        if golden.isHittable { golden.tap() }
        Thread.sleep(forTimeInterval: 1)
        let spiral = app.buttons["composition.card.goldenSpiral"].firstMatch
        var swipes = 0
        while swipes < 4, !(spiral.exists && spiral.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard spiral.exists, spiral.isHittable else { return }
        spiral.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("黄金螺旋"), "選んだ構図にならない: \(row.label)")
        shoot(app, "13k-黄金螺旋を重ねた撮る画面")

        // 三分割に戻す（あとの試験・次の回の絵に残さない）
        guard row.isHittable else { return }
        row.tap()
        let thirds = app.buttons["composition.card.thirds"].firstMatch
        let chip = app.buttons["composition.chip.classic"].firstMatch
        if chip.waitForExistence(timeout: 5), chip.isHittable { chip.tap() }
        Thread.sleep(forTimeInterval: 1)
        if thirds.waitForExistence(timeout: 5), thirds.isHittable { thirds.tap() }
        Thread.sleep(forTimeInterval: 1)
    }

    /// **Pro の案内**（板 63・審査に出す画面写真）。見本の利用者には Pro の案内へ行く口が無い
    /// （公開プロフィールでは Pro・設定の行は「App Store で管理」）ので、`-JPPreviewPaywall YES`
    /// （Debug のみ・見本の利用者で入っているときだけ・`PreviewSession.opensPaywall`）でマイページを
    /// 開いたときに1度だけ出す。**主ボタン（購入）は押さない**。出なければ撮らない（この試験の決まり）
    func testCapturesProPaywall() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewPaywall", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["paywall.purchase"].firstMatch.waitForExistence(timeout: 20) else { return }
        // 上の写真（朝の公開写真・写真の一覧を読んでから選ぶ）と値段が届くのを待つ。
        // run 389 は 4 秒で撮り、上の写真がまだ黒かった
        Thread.sleep(forTimeInterval: 10)
        shoot(app, "81-Pro の案内")
        // **送れたときだけ下を撮る**（1画面に収まる端末では 81 と同じ絵になる・「15-マイページ（下）」と同じ決まり）
        let restore = app.buttons["paywall.restore"].firstMatch
        let before = restore.exists ? restore.frame.origin.y : nil
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        let after = restore.exists ? restore.frame.origin.y : nil
        if let before, let after, abs(before - after) > 1 {
            shoot(app, "81b-Pro の案内（下・注記と復元）")
        }
        let close = app.buttons["paywall.close"].firstMatch
        if close.waitForExistence(timeout: 5), close.isHittable { close.tap() }
    }

    /// **光と天気の知らせ**（Pro・板 LightAlert・2026-10-09）: 設定の Pro の節の「光と天気の知らせ」→
    /// 一覧「行きたい場所の光（今週）」。見本（`-JPLightForecastPreview sample`・DEBUG だけ・本物の予報ではない）と
    /// 空の姿（`empty`）を1枚ずつ。出なければ撮らない（この試験の決まり）
    func testCapturesLightForecast() {
        for (mode, name) in [("sample", "84-光と天気の知らせ"), ("empty", "84b-光と天気の知らせ（空）")] {
            let app = XCUIApplication()
            app.launchArguments += ["-legal.consent.version", "0"]
            app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
            app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
            app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
            app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
            app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
            app.launchArguments += ["-JPLightForecastPreview", mode]
            app.launch()

            let agree = app.buttons["legal.agree"]
            if agree.waitForExistence(timeout: 30) { agree.tap() }
            let tabBar = app.tabBars.firstMatch
            guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
            tabBar.buttons.element(boundBy: 4).tap()
            guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15) else { return }
            let gear = app.buttons["設定"].firstMatch
            guard gear.waitForExistence(timeout: 5), gear.isHittable else { return }
            gear.tap()
            let row = app.buttons["settings.lightForecast"].firstMatch
            guard row.waitForExistence(timeout: 10) else { return }
            if !row.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 1) }
            guard row.isHittable else { return }
            row.tap()
            let ready = mode == "sample"
                ? app.buttons["lightForecast.card"].firstMatch
                : app.links["lightForecast.attribution"].firstMatch
            _ = ready.waitForExistence(timeout: 10)
            // 見本は索引の本物のスポットで組むので、札の写真が読み込まれるのを待つ
            Thread.sleep(forTimeInterval: mode == "sample" ? 4 : 1)
            shoot(app, name)
            if mode == "sample", ready.exists, ready.isHittable {
                // Apple Weather の出典は一覧に必ず出す（Apple の求め）
                XCTAssertTrue(app.links["lightForecast.attribution"].firstMatch.exists, "天気の出典が無い")
                // 札を開いた姿（その場所の7日と「スポットを見る」「経路」）
                let closedValue = ready.value as? String
                ready.tap()
                Thread.sleep(forTimeInterval: 1)
                // 前提（札が開閉の値を持つ）が揃ったら、開いた値に変わる（印と読み上げ・2026-10-11）
                if let closedValue, !closedValue.isEmpty {
                    XCTAssertNotEqual(ready.value as? String, closedValue, "札を押しても開いた値にならない")
                }
                shoot(app, "84a-光と天気の知らせ（札を開いた）")
                let openSpot = app.buttons["lightForecast.openSpot"].firstMatch
                if openSpot.waitForExistence(timeout: 5) {
                    XCTAssertTrue(app.buttons["lightForecast.directions"].firstMatch.exists, "開いた札に「経路」が無い")
                    if openSpot.isHittable {
                        openSpot.tap()
                        XCTAssertTrue(app.buttons["spot.official.wish"].firstMatch.waitForExistence(timeout: 10),
                                      "「スポットを見る」でスポットの頁が開かない")
                        Thread.sleep(forTimeInterval: 2)
                        shoot(app, "84c-光と天気の知らせ（スポットを見る）")
                    }
                }
            }
            app.terminate()
        }
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
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
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
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
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

    /// **名前の横のバッジ**（大きいメダルの絵をそのまま縮める・案 C・2026-10-09 owner「そのままがいい」）。
    ///
    /// 見本の利用者は鍵を持たず、バッジも選んでいないので、持ち物は `-JPPreviewBadges`、
    /// 名前の横に出す鍵は `-JPPreviewDisplayBadge`（どちらも Debug のみ・`PreviewSession`）で渡す。
    /// 後光のある初期ユーザーと、段のあるメダル（都道府県 · 銀）を撮る。**保存は押さない**。
    /// 出なければ撮らない（この試験の決まり）
    func testCapturesNameSideBadge() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewBadges", "earlyUser:1,prefectures:2"]
        app.launchArguments += ["-JPPreviewDisplayBadge", "earlyUser"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
        guard nameLine.waitForExistence(timeout: 20) else { return }
        // 縮めた絵ができるのを待つ（画面の処理の外で作る）
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "83-マイページ（名前の横のバッジ・初期ユーザー）")

        guard nameLine.isHittable else { return }
        nameLine.tap()
        guard app.descendants(matching: .any)["nameSide.save"].firstMatch.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "83b-名前の横（下見・初期ユーザー）")

        let plain = app.descendants(matching: .any)["nameSide.badge.prefectures"].firstMatch
        guard plain.waitForExistence(timeout: 5), plain.isHittable else { return }
        plain.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "83c-名前の横（下見・都道府県 · 銀）")
    }

    /// **名前の横の画面（Pro の人）**（2026-10-09）: 「PRO 限定」の段の説明の一行と、まだ届いていない章を
    /// 押したときの届く時期の知らせ。格子の絵は大きい絵を表示の画素ちょうどに縮めたもの。
    ///
    /// 見本の利用者は Pro を買っていないので `-JPPreviewPro YES`（Debug のみ・`PreviewSession.isPro`）で
    /// 本人のプロフィールにだけ Pro を重ねる。持ち物は 83 と同じ見本。**保存は押さない**。
    /// 出なければ撮らない（この試験の決まり）
    func testCapturesProNameSide() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewBadges", "earlyUser:1,prefectures:2"]
        app.launchArguments += ["-JPPreviewDisplayBadge", "earlyUser"]
        app.launchArguments += ["-JPPreviewPro", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
        guard nameLine.waitForExistence(timeout: 20), nameLine.isHittable else { return }
        nameLine.tap()
        guard app.descendants(matching: .any)["nameSide.save"].firstMatch.waitForExistence(timeout: 10) else { return }
        // 縮めた絵ができるのを待つ（画面の処理の外で作る）
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "83d-名前の横（Pro の人・持っているバッジ）")

        let note = app.descendants(matching: .any)["nameSide.proNote"].firstMatch
        guard note.waitForExistence(timeout: 5) else { return }
        var pushes = 0
        while !note.isHittable, pushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "83e-名前の横（Pro の人・PRO 限定の説明）")

        // まだ届いていない季節の章（無ければ機能の章）を押すと、届く時期が下に出る
        let season = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nameSide.pro.proWinter'")).firstMatch
        let target = season.exists ? season : app.buttons["nameSide.pro.dawn"].firstMatch
        guard target.waitForExistence(timeout: 3), target.isHittable else { return }
        target.tap()
        guard app.descendants(matching: .any)["toast"].firstMatch.waitForExistence(timeout: 3) else { return }
        shoot(app, "83f-名前の横（Pro の人・届く時期の知らせ）")
    }

    /// **メダルの浮き彫りと面取り**（2026-10-14 owner「回転した時に表と裏があまりにも凹凸感なさすぎて…
    /// ほんの少しだけ凹凸感欲しい」）。メダルを回す全画面の硬貨を、決まった角度で止めて撮る。
    ///
    /// 硬貨はふだん勝手に回るので、`-JPPreviewMedalPoses`（Debug のみ・`PreviewSession.medalPoses`）で
    /// 最初の向きに止め、硬貨を押すたびに次の向きへ進める。並びは「横の回り:浮き彫りの強さ」:
    /// 既定の強さ（2.5・owner が選んだ）で少し傾けた（約26°）・正面・大きく傾けた（約63°）、
    /// 比べる用に少し傾けたまま強さ 0（前の作り）。メダルは段のある都道府県（銀）。
    ///
    /// 🔴 **浮き彫りを貼り終えた印を待ってから撮る**（run 427: 強さを変えた直後に撮り、2 と 0 が同じ絵だった）。
    /// 硬貨の読み上げの値が「pose-<番号>-ready」になるまで待つ。来なければ撮らない（この試験の決まり）
    func testCapturesMedalRelief() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewBadges", "prefectures:2,earlyUser:1"]
        app.launchArguments += ["-JPPreviewMedalPoses", "0.45:2.5,0:2.5,1.1:2.5,0.45:0"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
        guard nameLine.waitForExistence(timeout: 20), nameLine.isHittable else { return }
        nameLine.tap()
        guard app.descendants(matching: .any)["nameSide.save"].firstMatch.waitForExistence(timeout: 10) else { return }
        // 名前の横の画面でメダルを長押しすると全画面で手に取れる（`MedalViewerTests` と同じ道）
        let badge = app.descendants(matching: .any)["nameSide.badge.prefectures"].firstMatch
        guard badge.waitForExistence(timeout: 15), badge.isHittable else { return }
        badge.press(forDuration: 1.0)
        let coin = app.descendants(matching: .any)["medalViewer.coin"].firstMatch
        guard coin.waitForExistence(timeout: 15) else { return }

        let names = ["85a-メダルの浮き彫り（少し傾けた・既定の強さ2.5）",
                     "85b-メダルの浮き彫り（正面・既定の強さ2.5）",
                     "85c-メダルの浮き彫り（大きく傾けた・既定の強さ2.5）",
                     "85f-メダルの浮き彫り（少し傾けた・強さ0＝前の作り）"]
        for (index, name) in names.enumerated() {
            if index > 0 {
                guard coin.exists, coin.isHittable else { return }
                coin.tap()
            }
            // 法線の絵は画面の処理の外で作る（強さを変えた回は作り直す）。貼り終えた印を待つ
            let ready = NSPredicate(format: "value == %@", "pose-\(index)-ready")
            let waited = XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: coin)], timeout: 30)
            guard waited == .completed else { return }
            // 貼った絵が次のコマで描かれるまで
            Thread.sleep(forTimeInterval: 1)
            shoot(app, name)
        }
    }

    // MARK: - 旅のトランク（2026-10-17・モック「旅のトランク」）

    /// 旅のトランクの見本で起動する（`-JPPreviewTrunk`・Debug のみ。サーバーには何も送らない）
    private func launchTrunk(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += extra
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        return app
    }

    /// マイページ → 旅の記録のタブ → 「旅のトランク」の行。開けたら true
    private func openTrunk(_ app: XCUIApplication) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return false }
        tabBar.buttons.element(boundBy: 4).tap()
        let tripsTab = app.buttons["profile.tab.trips"].firstMatch
        guard tripsTab.waitForExistence(timeout: 15) else { return false }
        var pushes = 0
        while !tripsTab.isHittable, pushes < 4 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard tripsTab.isHittable else { return false }
        tripsTab.tap()
        let row = app.buttons["trips.trunk"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return false }
        var rowPushes = 0
        let bottom = app.windows.firstMatch.frame.maxY - 100
        while row.exists, row.frame.maxY > bottom || !row.isHittable, rowPushes < 6 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            rowPushes += 1
        }
        guard row.isHittable else { return false }
        row.tap()
        return app.descendants(matching: .any)["trunk.spin"].firstMatch.waitForExistence(timeout: 15)
    }

    // MARK: - 写真で作るキャンピングカー（2026-10-18・札 #307）

    /// マイページ → 旅の記録のタブ → 「写真で作るキャンピングカー」の行。開けたら true
    private func openCamper(_ app: XCUIApplication) -> Bool {
        guard openTripsRow(app, "trips.camper") else { return false }
        return app.descendants(matching: .any)["camper.scene"].firstMatch.waitForExistence(timeout: 15)
    }

    /// マイページ → 旅の記録のタブ → 行 `id` を押す。押せたら true
    private func openTripsRow(_ app: XCUIApplication, _ id: String) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return false }
        tabBar.buttons.element(boundBy: 4).tap()
        let tripsTab = app.buttons["profile.tab.trips"].firstMatch
        guard tripsTab.waitForExistence(timeout: 15) else { return false }
        var pushes = 0
        while !tripsTab.isHittable, pushes < 4 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard tripsTab.isHittable else { return false }
        tripsTab.tap()
        let row = app.buttons[id].firstMatch
        guard row.waitForExistence(timeout: 15) else { return false }
        scrollTo(row, in: app)
        guard row.isHittable else { return false }
        row.tap()
        return true
    }

    /// 立体の車を組み終えるまで待つ（読み上げの値に「camper-ready 段 時刻」が出る・見本の起動のときだけ）
    @discardableResult
    private func waitCamper(_ app: XCUIApplication, _ marker: String, scene id: String = "camper.scene") -> Bool {
        let scene = app.descendants(matching: .any)[id].firstMatch
        let ready = NSPredicate(format: "value CONTAINS %@", marker)
        let done = XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: scene)], timeout: 40) == .completed
        // 組んだ形が次のコマで描かれ、向きの動き（0.6 秒）が止まるまで
        Thread.sleep(forTimeInterval: 2)
        return done
    }

    /// **写真で作るキャンピングカー**: 昼・夜・扉を開けた室内・3 段（バン・キャンピングカー・トレーラーつき）。
    /// 出なければ撮らずに抜ける。**出たのに押せる所が 44pt 未満なら落とす**
    func testCapturesCamper() {
        let app = launchTrunk([])
        guard openCamper(app) else { return }
        guard waitCamper(app, "camper-ready") else { return XCTFail("キャンピングカーを組み終えない") }
        shoot(app, "95-写真で作るキャンピングカー（昼）")
        for id in ["camper.door", "camper.reset", "camper.mood.night", "camper.stage.van"] {
            let b = app.buttons[id].firstMatch
            XCTAssertTrue(b.exists, "\(id) が無い")
            if b.exists { XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(id) が 44pt 未満") }
        }
        // 扉を開けた室内
        app.buttons["camper.door"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "95a-写真で作るキャンピングカー（扉を開けた室内）")
        app.buttons["camper.door"].firstMatch.tap()
        // 夜
        app.buttons["camper.mood.night"].firstMatch.tap()
        waitCamper(app, "night")
        // 夜の光の切り替えが絵に出るまで（95a と同じく少し待つ。合図は値が替わった時で、描き直しの後ではない）
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "95b-写真で作るキャンピングカー（夜）")
        // 夜に扉を開けた所（室内の灯りと、扉の口から地面へこぼれる灯り）
        app.buttons["camper.door"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "95f-写真で作るキャンピングカー（夜・扉を開けた）")
        app.buttons["camper.door"].firstMatch.tap()
        app.buttons["camper.mood.day"].firstMatch.tap()
        waitCamper(app, "day")
        // 3 段
        for (id, name) in [("van", "95c-キャンピングカー（バン）"), ("camper", "95d-キャンピングカー（キャンピングカー）"),
                           ("trailer", "95e-キャンピングカー（トレーラーつき）")] {
            let b = app.buttons["camper.stage.\(id)"].firstMatch
            guard b.exists else { continue }
            if !b.isHittable { scrollTo(b, in: app) }
            b.tap()
            waitCamper(app, "camper-ready \(id)")
            shoot(app, name)
        }
    }

    /// **とおまわり号の第2段**（2026-10-19・`-JPPreviewCamper`。サーバーには何も送らない見本）: 要サーバーの部品が
    /// 届いた画面（一度に 3 個まで・贈り物の名前）と、分母 131 の車の画面。開けなければ撮らずに抜ける。
    /// **届いた画面が出たのに押せる所が 44pt 未満なら落とす**。車の画面で分母が 131 でなければ落とす
    func testCapturesCamperServer() {
        let app = launchTrunk(["-JPPreviewCamper", "YES", "-JPPreviewCamperArrival", "YES"])
        guard openCamper(app) else { return }
        // 届いた画面は「いま車に付ける」のボタンで見分ける（画面の親に識別子を付けると子のボタンの識別子を覆う）
        let arrival = app.buttons["camper.arrival.equip"].firstMatch
        if arrival.waitForExistence(timeout: 15) {
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "95g-キャンピングカー（部品が届いた）")
            for id in ["camper.arrival.equip", "camper.arrival.close"] {
                let b = app.buttons[id].firstMatch
                XCTAssertTrue(b.exists, "\(id) が無い")
                if b.exists { XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(id) が 44pt 未満") }
            }
            let others = app.buttons.matching(identifier: "camper.arrival.part")
            for i in 0..<others.count {
                XCTAssertGreaterThanOrEqual(others.element(boundBy: i).frame.height, 44, "一緒に届いた部品の札が 44pt 未満")
            }
            app.buttons["camper.arrival.close"].firstMatch.tap()
        }
        guard waitCamper(app, "camper-ready") else { return XCTFail("キャンピングカーを組み終えない") }
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/ 131")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10), "サーバーが読めたのに分母が 131 でない")
        shoot(app, "95h-キャンピングカー（要サーバーの部品）")
    }

    /// **友達の車を訪ねる**（2026-10-19・板 CamperVisit）: 見本（`-JPPreviewCamperVisit`・Debug のみ。サーバーには何も送らない）の
    /// マイページの行から見本の友達の車へ直接入り、95i・95j を**必ず撮る**（出なければ落とす）。本物の入口（人のプロフィールの
    /// 「とおまわり号を訪ねる」・フォローしている人の頁だけ）はホームの写真の並びとフォローの関係次第なので、ここでは通らない。
    /// 押せる所は 44pt 以上
    func testCapturesCamperVisit() {
        let app = launchTrunk(["-JPPreviewCamperVisit", "YES"])
        XCTAssertTrue(openTripsRow(app, "trips.camperVisitSample"), "マイページに見本の友達の車の行が無い")

        let gift = app.buttons["camper.visit.gift"].firstMatch
        guard gift.waitForExistence(timeout: 15) else { return XCTFail("友達の車の画面が開かない") }
        // 描き終わり（読み上げの値に「camper-ready」）まで待ってから撮る（自分の車の `waitCamper` と同じ）
        guard waitCamper(app, "camper-ready", scene: "camper.visit.scene") else { return XCTFail("友達の車を組み終えない") }
        XCTAssertTrue(app.descendants(matching: .any)["camper.visit.counted"].firstMatch.exists, "訪ねた記録の一行が無い")
        shoot(app, "95i-友達の車を訪ねる")
        for id in ["camper.visit.gift", "camper.visit.firewood"] {
            let b = app.buttons[id].firstMatch
            XCTAssertTrue(b.exists, "\(id) が無い")
            if b.exists { XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(id) が 44pt 未満") }
        }
        scrollTo(gift, in: app)
        gift.tap()
        let message = app.descendants(matching: .any)["camper.visit.message"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), "贈った結果の一行が出ない")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "95j-友達の車（部品を贈った）")
    }

    /// 押したい行が画面に収まるまで送る
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let bottom = app.windows.firstMatch.frame.maxY - 60
        var pushes = 0
        while element.exists, element.frame.maxY > bottom || !element.isHittable, pushes < 5 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
    }

    /// **旅のトランクの入口**（2026-10-18 owner「入口がわかりずらい」）: マイページの見出しの下の札
    /// （硬貨の枚数・貼っていないラベルの真鍮の点）と、設定の「旅のトランク」の行。見本（`-JPPreviewTrunk`）で撮る。
    /// **見本では入口が必ず出るので、出なければ落とす**（commit 66d7f872 の方針）。44pt 未満・読み上げに硬貨が無いときも落とす
    func testCapturesTrunkEntry() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewTrunkCoins", "3"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return XCTFail("下の札が出ない") }
        tabBar.buttons.element(boundBy: 4).tap()
        let card = app.buttons["mypage.trunk"].firstMatch
        guard card.waitForExistence(timeout: 15) else { return XCTFail("マイページの上に旅のトランクの札が無い") }
        // タブを切り替えずに見える（カバーの高い人・小さい画面では少し送る）
        scrollTo(card, in: app)
        XCTAssertTrue(card.isHittable, "マイページの上の札に届かない")
        XCTAssertGreaterThanOrEqual(card.frame.height, 44, "旅のトランクの札が 44pt 未満")
        let spoken = (card.value as? String) ?? ""
        XCTAssertTrue(spoken.contains("硬貨 3枚"), "読み上げに硬貨の枚数が無い: \(spoken)")
        XCTAssertTrue(spoken.contains("貼っていないラベル"), "読み上げに貼っていないラベルの有無が無い: \(spoken)")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "90a-マイページ（旅のトランクの札）")
        // 押すとトランクへ
        card.tap()
        guard app.descendants(matching: .any)["trunk.spin"].firstMatch.waitForExistence(timeout: 15) else {
            return XCTFail("札を押してもトランクが開かない")
        }
        goBack(app)
        Thread.sleep(forTimeInterval: 1)
        // 設定の行
        let gear = app.buttons["設定"].firstMatch
        guard gear.waitForExistence(timeout: 5) else { return XCTFail("設定の丸が無い") }
        scrollTo(gear, in: app)
        gear.tap()
        let row = app.buttons["settings.trunk"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return XCTFail("設定に旅のトランクの行が無い") }
        scrollTo(row, in: app)
        guard row.isHittable else { return XCTFail("設定の旅のトランクの行に届かない") }
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "設定の旅のトランクの行が 44pt 未満")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "90b-設定（旅のトランク）")
    }

    /// **設定の並び**（2026-10-18 owner「設定の項目多くなってるのでわかりやすいように整理して」）: いちばん上・
    /// 旅の道具（トランク・写真で作るキャンピングカー）・最後の危ない操作・下の画面（データとストレージ・トランクを見せる）。
    /// 見本（`-JPPreviewTrunk`）ではトランクの行が必ず出るので、出なければ落とす。押せる行が 44pt 未満でも落とす
    func testCapturesSettingsOutline() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewTrunkCoins", "3"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return XCTFail("下の札が出ない") }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15) else { return }
        let gear = app.buttons["設定"].firstMatch
        guard gear.waitForExistence(timeout: 5) else { return XCTFail("設定の丸が無い") }
        scrollTo(gear, in: app)
        gear.tap()
        let trunk = app.buttons["settings.trunk"].firstMatch
        guard trunk.waitForExistence(timeout: 10) else { return XCTFail("設定の旅の道具に旅のトランクの行が無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "102-設定（いちばん上）")

        // 旅の道具: キャンピングカーの行まで送って撮り、押すと車の画面が開く
        let camper = app.buttons["settings.camper"].firstMatch
        guard camper.waitForExistence(timeout: 5) else { return XCTFail("設定にキャンピングカーの行が無い") }
        scrollTo(camper, in: app)
        XCTAssertTrue(camper.isHittable, "設定のキャンピングカーの行に届かない")
        for id in ["settings.trunk", "settings.camper", "settings.pass", "settings.passBook", "settings.albums",
                   "settings.plans"] {
            let row = app.buttons[id].firstMatch
            XCTAssertTrue(row.exists, "旅の道具に \(id) が無い")
            if row.exists { XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(id) が 44pt 未満") }
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "102a-設定（旅の道具）")
        if camper.isHittable {
            camper.tap()
            XCTAssertTrue(app.descendants(matching: .any)["camper.scene"].firstMatch.waitForExistence(timeout: 15),
                          "設定のキャンピングカーの行を押しても車の画面が開かない")
            goBack(app)
            Thread.sleep(forTimeInterval: 1)
        }

        // 最後の危ない操作（ログアウト・アカウントの削除は別々の札）
        let delete = app.buttons["settings.deleteAccount"].firstMatch
        guard delete.waitForExistence(timeout: 5) else { return XCTFail("設定にアカウントの削除が無い") }
        var pushes = 0
        while !delete.isHittable || delete.frame.maxY > app.windows.firstMatch.frame.maxY - 60, pushes < 10 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        for id in ["settings.logout", "settings.deleteAccount", "settings.storage", "settings.whatsNew"] {
            let row = app.buttons[id].firstMatch
            if row.exists { XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(id) が 44pt 未満") }
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "102b-設定（ヘルプと危ない操作）")

        // 下の画面: データとストレージ。**押せないときは黙って飛ばさず落とす**
        let storage = app.buttons["settings.storage"].firstMatch
        guard storage.waitForExistence(timeout: 5) else { return XCTFail("設定にデータとストレージの行が無い") }
        var down = 0
        while !storage.isHittable, down < 6 {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 1)
            down += 1
        }
        guard storage.isHittable else { return XCTFail("データとストレージの行に届かない") }
        storage.tap()
        let clear = app.buttons["settings.clearCache"].firstMatch
        guard clear.waitForExistence(timeout: 5) else { return XCTFail("データとストレージに「控えを空にする」が無い") }
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44, "「控えを空にする」が 44pt 未満")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "102c-設定（データとストレージ）")
        goBack(app)
        Thread.sleep(forTimeInterval: 1)

        // 下の画面: トランクを見せる。見本（`-JPPreviewTrunk`）はサーバーが対応している形なので必ず出る——出なければ落とす
        let show = app.buttons["settings.trunkPrivacy"].firstMatch
        guard show.waitForExistence(timeout: 5) else { return XCTFail("設定に「トランクを見せる」の行が無い") }
        var up = 0
        while !show.isHittable, up < 6 {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 1)
            up += 1
        }
        guard show.isHittable else { return XCTFail("「トランクを見せる」の行に届かない") }
        show.tap()
        guard app.descendants(matching: .any)["settings.showTrunk"].firstMatch.waitForExistence(timeout: 5) else {
            return XCTFail("「トランクを見せる」の画面に入切が無い")
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "102d-設定（トランクを見せる）")
        goBack(app)
    }

    /// **旅のトランク**（Pro の見本）: トランク → 手に取って回す → 手持ち（選んだ）→ 作り直し →
    /// 型 → 特別なトランク。出なければ撮らずに抜ける。**出たのに押せる所が 44pt 未満なら落とす**
    func testCapturesTrunk() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewPro", "YES"])
        guard openTrunk(app) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "90-旅のトランク")

        let spin = app.buttons["trunk.spin"].firstMatch
        if spin.isHittable {
            spin.tap()
            let close = app.buttons["trunk.spin.close"].firstMatch
            if close.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 3)
                shoot(app, "91-トランクを手に取って回す")
                XCTAssertGreaterThanOrEqual(close.frame.height, 44, "回す画面の × が 44pt 未満")
                close.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }

        let pocketRow = app.buttons["trunk.pocket"].firstMatch
        scrollTo(pocketRow, in: app)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "90a-旅のトランク（下・最近貼ったラベルと札）")
        guard pocketRow.isHittable else { return }
        XCTAssertGreaterThanOrEqual(pocketRow.frame.height, 44, "手持ちの行が 44pt 未満")
        pocketRow.tap()
        let cell = app.buttons["trunk.pocket.cell"].firstMatch
        guard cell.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "92-手持ちのラベル")
        cell.tap()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "92a-手持ちのラベル（選んでいる）")
        for id in ["trunk.pocket.stick", "trunk.pocket.reroll", "trunk.pocket.delete"] {
            let button = app.buttons[id].firstMatch
            XCTAssertTrue(button.exists, "\(id) が無い")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(id) が 44pt 未満")
        }
        let reroll = app.buttons["trunk.pocket.reroll"].firstMatch
        if reroll.isHittable {
            reroll.tap()
            let close = app.buttons["trunk.reroll.close"].firstMatch
            if close.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 2)
                shoot(app, "93-図柄を作り直す（押す前）")
                // 押す前は「この図柄にする」を出さない（開いただけでは回数を使わない・2026-10-17）
                XCTAssertFalse(app.buttons["trunk.reroll.choose"].firstMatch.exists, "押す前なのに「この図柄にする」が出ている")
                let start = app.buttons["trunk.reroll.start"].firstMatch
                if start.exists, start.isHittable {
                    XCTAssertGreaterThanOrEqual(start.frame.height, 44, "「作り直す」が 44pt 未満")
                    start.tap()
                    let options = app.buttons.matching(identifier: "trunk.reroll.option")
                    _ = options.firstMatch.waitForExistence(timeout: 10)
                    Thread.sleep(forTimeInterval: 1)
                    shoot(app, "93a-図柄を作り直す（候補）")
                    if options.count > 2 {
                        options.element(boundBy: 2).tap()
                        Thread.sleep(forTimeInterval: 1)
                        shoot(app, "93b-図柄を作り直す（案2を選んだ）")
                    }
                    XCTAssertGreaterThanOrEqual(app.buttons["trunk.reroll.choose"].firstMatch.frame.height, 44)
                }
                close.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }
        goBack(app)
        Thread.sleep(forTimeInterval: 1)

        let modelsRow = app.buttons["trunk.models"].firstMatch
        scrollTo(modelsRow, in: app)
        guard modelsRow.waitForExistence(timeout: 5), modelsRow.isHittable else { return }
        modelsRow.tap()
        let proRow = app.buttons["trunk.models.pro"].firstMatch
        guard proRow.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "94-トランクの型")
        scrollTo(proRow, in: app)
        guard proRow.isHittable else { return }
        proRow.tap()
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "95-特別なトランク（Pro）")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "95a-特別なトランク（下）")
    }

    /// **旅のトランク（届いたラベルが1枚も無い人）**: 空の状態（「写真を投稿」の一手）と、空の手持ち
    func testCapturesTrunkEmpty() {
        let app = launchTrunk(["-JPPreviewTrunk", "empty"])
        guard openTrunk(app) else { return }
        let empty = app.buttons["trunk.emptyPost"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "ラベルの無い人に空の状態が出ない")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "90b-旅のトランク（まだラベルが無い）")
        let pocketRow = app.buttons["trunk.pocket"].firstMatch
        scrollTo(pocketRow, in: app)
        guard pocketRow.isHittable else { return }
        pocketRow.tap()
        if app.descendants(matching: .any)["trunk.pocket.empty"].firstMatch.waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "92b-手持ちのラベル（空・Pro の案内）")
        }
    }

    /// **トランクから開いた Pro の案内**（2026-10-18 判断）: Pro でない見本（`-JPPreviewTrunk empty`）の手持ち →
    /// 「Pro なら 150 枚まで持てます」→ 案内。トランクの利点がいちばん上に来ていなければ落とす。**何も買わない**。
    /// 2026-10-18 判断（見直し）: 見本の起動なので、途中で進めなければ黙って抜けずに落とす
    /// （トランクの入口のテストと同じ方針。何も確かめずに緑にしない）
    func testCapturesProPaywallFromTrunk() {
        let app = launchTrunk(["-JPPreviewTrunk", "empty"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        let pocketRow = app.buttons["trunk.pocket"].firstMatch
        scrollTo(pocketRow, in: app)
        guard pocketRow.isHittable else { return XCTFail("手持ちの行を押せない") }
        pocketRow.tap()
        let proLink = app.buttons["trunk.pocket.pro"].firstMatch
        guard proLink.waitForExistence(timeout: 10) else { return XCTFail("Pro でない見本の手持ちに「Pro なら…」が無い") }
        scrollTo(proLink, in: app)
        guard proLink.isHittable else { return XCTFail("「Pro なら…」を押せない") }
        proLink.tap()
        guard app.buttons["paywall.purchase"].firstMatch.waitForExistence(timeout: 20) else {
            return XCTFail("トランクから Pro の案内が開かない")
        }
        let trunk = app.descendants(matching: .any)["paywall.benefit.trunk"].firstMatch
        let light = app.descendants(matching: .any)["paywall.benefit.light"].firstMatch
        guard trunk.waitForExistence(timeout: 5) else { return XCTFail("トランクから開いたのにトランクの利点が無い") }
        guard light.exists else { return XCTFail("案内に光と天気の知らせの利点が無い") }
        XCTAssertLessThan(trunk.frame.minY, light.frame.minY, "トランクから開いたのにトランクの利点が上に無い")
        // 上の写真と値段が届くのを待つ（`testCapturesProPaywall` と同じ）
        Thread.sleep(forTimeInterval: 10)
        shoot(app, "92c-Pro の案内（トランクから）")
        let close = app.buttons["paywall.close"].firstMatch
        if close.waitForExistence(timeout: 5), close.isHittable { close.tap() }
    }

    /// **ラベルが届いた**（投稿のお礼・`-JPPreviewTrunkArrived`）。出なければ撮らずに抜ける。
    /// 出たのに3つの手が無い・44pt 未満・「手持ちに入れておく」で閉じなければ落とす
    func testCapturesTrunkArrived() {
        let app = launchTrunk(["-JPPreviewTrunkArrived", "YES"])
        let stick = app.buttons["trunk.arrived.stick"].firstMatch
        guard stick.waitForExistence(timeout: 30) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "96-ラベルが届いた")
        let keep = app.buttons["trunk.arrived.keep"].firstMatch
        let reroll = app.buttons["trunk.arrived.reroll"].firstMatch
        let close = app.buttons["trunk.arrived.close"].firstMatch
        for (button, name) in [(stick, "トランクに貼る"), (keep, "手持ちに入れておく"), (reroll, "図柄を作り直す"), (close, "閉じる")] {
            XCTAssertTrue(button.exists, "「\(name)」が無い")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "「\(name)」が 44pt 未満")
        }
        guard keep.isHittable else { return XCTFail("「手持ちに入れておく」を押せない") }
        keep.tap()
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: stick)], timeout: 5)
        XCTAssertEqual(closed, .completed, "「手持ちに入れておく」で閉じない")
    }

    // MARK: - はじめての硬貨（2026-10-18 owner 承認）

    /// **はじめての硬貨**（`-JPPreviewTrunkWelcome YES`・サーバーには何も送らない）。見本は必ず出るので、
    /// **出ない・「カプセルを回す」「あとで」「閉じる」が無い・44pt 未満なら落とす**。
    /// 「カプセルを回す」でカプセルの機械へ進み、戻って「あとで」で閉じる
    func testCapturesTrunkWelcome() {
        let app = launchTrunk(["-JPPreviewTrunkWelcome", "YES", "-JPPreviewTrunk", "YES"])
        let turn = app.buttons["trunk.welcome.turn"].firstMatch
        guard turn.waitForExistence(timeout: 45) else { return XCTFail("はじめての硬貨の案内が出ない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "96c-はじめての硬貨")
        let later = app.buttons["trunk.welcome.later"].firstMatch
        let close = app.buttons["trunk.welcome.close"].firstMatch
        for (button, name) in [(turn, "カプセルを回す"), (later, "あとで"), (close, "閉じる")] {
            XCTAssertTrue(button.exists, "「\(name)」が無い")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "「\(name)」が 44pt 未満")
        }
        XCTAssertTrue(app.descendants(matching: .any)["trunk.welcome.added"].firstMatch.exists, "「硬貨 +10 枚」が無い")
        XCTAssertFalse(app.descendants(matching: .any)["trunk.welcome.capped"].firstMatch.exists, "10 枚の回に上限の一言が出ている")
        guard turn.isHittable else { return XCTFail("「カプセルを回す」を押せない") }
        turn.tap()
        let insert = app.buttons["trunk.gacha.insert"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 10), "「カプセルを回す」でカプセルの機械へ進まない")
        Thread.sleep(forTimeInterval: 1)
        // 機械の手持ちは案内と同じ「配ったあとの数」（見本は 2 + 10 = 12 枚）。2 枚に戻って見えたら落とす
        let coins = app.descendants(matching: .any)["trunk.gacha.coins"].firstMatch
        XCTAssertTrue(coins.waitForExistence(timeout: 5), "カプセルの機械に硬貨の数が無い")
        XCTAssertTrue(coins.label.contains("12"), "カプセルの機械の硬貨が案内の数（12）と違う: \(coins.label)")
        shoot(app, "96d-はじめての硬貨（カプセルの機械へ）")
        goBack(app)
        guard later.waitForExistence(timeout: 10), later.isHittable else { return XCTFail("機械から案内へ戻れない") }
        later.tap()
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: turn)], timeout: 5)
        XCTAssertEqual(closed, .completed, "「あとで」で閉じない")
    }

    /// **はじめての硬貨（上限に当たって 3 枚だけ）**: 実際の枚数と上限の一言
    func testCapturesTrunkWelcomeCapped() {
        let app = launchTrunk(["-JPPreviewTrunkWelcome", "3"])
        let turn = app.buttons["trunk.welcome.turn"].firstMatch
        guard turn.waitForExistence(timeout: 45) else { return XCTFail("はじめての硬貨の案内が出ない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "96e-はじめての硬貨（上限に当たった）")
        XCTAssertTrue(app.descendants(matching: .any)["trunk.welcome.capped"].firstMatch.exists, "上限の一言が無い")
    }

    // MARK: - 旅のトランクの次の版（2026-10-17・自分の手で貼る・カプセルの機械・部品箱）

    /// トランクの画面の入口（`trunk.stick.open`・`trunk.partsBox`・`trunk.gacha.open`）を押す。押せたら true
    private func openTrunkRow(_ app: XCUIApplication, _ id: String) -> Bool {
        let row = app.buttons[id].firstMatch
        guard row.waitForExistence(timeout: 10) else { return false }
        scrollTo(row, in: app)
        guard row.isHittable else { return false }
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(id) の行が 44pt 未満")
        row.tap()
        return true
    }

    /// **自分の手で貼る**: 手持ちのラベルを押さえてトランクへ運ぶ → 貼った → 右に回す。出なければ撮らずに抜ける
    func testCapturesTrunkStick() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.stick.open") else { return XCTFail("「ラベルを貼る」の入口が無い") }
        let done = app.buttons["trunk.stick.done"].firstMatch
        guard done.waitForExistence(timeout: 10) else { return XCTFail("貼る画面が開かない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "97-ラベルを貼る")
        for id in ["trunk.stick.done", "trunk.stick.undo", "trunk.stick.auto", "trunk.stick.peel"] {
            let button = app.buttons[id].firstMatch
            XCTAssertTrue(button.exists, "\(id) が無い")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(id) が 44pt 未満")
        }
        let cell = app.buttons.matching(identifier: "trunk.stick.tray").firstMatch
        let trunk = app.descendants(matching: .any)["trunk.stick.trunk"].firstMatch
        guard cell.waitForExistence(timeout: 5), trunk.exists else { return XCTFail("手持ちの札かトランクが無い") }
        do {
            cell.press(forDuration: 0.3, thenDragTo: trunk)
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "97a-ラベルを貼る（運んで貼った）")
            let right = app.buttons["trunk.stick.rotateRight"].firstMatch
            if right.waitForExistence(timeout: 5) {
                XCTAssertGreaterThanOrEqual(right.frame.height, 44, "回すボタンが 44pt 未満")
                right.tap()
                right.tap()
                Thread.sleep(forTimeInterval: 2)
                shoot(app, "97b-ラベルを貼る（回した）")
            }
        }
        let auto = app.buttons["trunk.stick.auto"].firstMatch
        if auto.isHittable {
            auto.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "97c-ラベルを貼る（おまかせで並べた）")
        }
        done.tap()
    }

    /// **カプセルの機械**: 硬貨を入れる → ハンドルを4回押して1周 → カプセルを開ける → 中身と確率
    func testCapturesTrunkGacha() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.gacha.open") else { return XCTFail("カプセルの機械の入口が無い") }
        let insert = app.buttons["trunk.gacha.insert"].firstMatch
        guard insert.waitForExistence(timeout: 10) else { return XCTFail("「硬貨を入れる」が無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "98-カプセルの機械")
        XCTAssertGreaterThanOrEqual(insert.frame.height, 44, "「硬貨を入れる」が 44pt 未満")
        insert.tap()
        let crank = app.buttons["trunk.gacha.crank"].firstMatch
        guard crank.waitForExistence(timeout: 5) else { return XCTFail("ハンドルが無い") }
        XCTAssertGreaterThanOrEqual(crank.frame.height, 44, "ハンドルが 44pt 未満")
        crank.tap()
        Thread.sleep(forTimeInterval: 0.5)
        shoot(app, "98-カプセルの機械（回している）")
        for _ in 0..<3 {
            crank.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        let open = app.buttons["trunk.gacha.openCapsule"].firstMatch
        guard open.waitForExistence(timeout: 10) else { return XCTFail("1周してもカプセルが出ない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "98-カプセルの機械（出てきた）")
        open.tap()
        let equip = app.buttons["trunk.gachaOpen.equip"].firstMatch
        guard equip.waitForExistence(timeout: 10) else { return XCTFail("開けた画面が出ない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "98a-カプセルを開けた")
        for id in ["trunk.gachaOpen.equip", "trunk.gachaOpen.keep", "trunk.gachaOpen.close"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].firstMatch.frame.height, 44, "\(id) が 44pt 未満")
        }
        app.buttons["trunk.gachaOpen.keep"].firstMatch.tap()
        let odds = app.buttons["trunk.gacha.odds"].firstMatch
        guard odds.waitForExistence(timeout: 10) else { return XCTFail("「中身と確率」が無い") }
        odds.tap()
        guard app.descendants(matching: .any)["trunk.odds.perPart"].firstMatch.waitForExistence(timeout: 10) else {
            return XCTFail("中身と確率に1点あたりの確率が無い")
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "98b-中身と確率")
    }

    /// **カプセルの機械（硬貨がありません）**: `-JPPreviewTrunkCoins 0`。入れ口のボタンが押せないこと
    func testCapturesTrunkGachaNoCoins() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewTrunkCoins", "0"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.gacha.open") else { return XCTFail("カプセルの機械の入口が無い") }
        let insert = app.buttons["trunk.gacha.insert"].firstMatch
        guard insert.waitForExistence(timeout: 10) else { return XCTFail("「硬貨がありません」のボタンが無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "98c-カプセルの機械（硬貨がありません）")
        XCTAssertFalse(insert.isEnabled, "硬貨 0 で硬貨を入れられる")
    }

    /// **部品箱 → 付け替える**: 種類のタブ（錠前）・ピンバッジの付け替え
    func testCapturesTrunkPartsBox() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.partsBox") else { return XCTFail("部品箱の入口が無い") }
        let lockTab = app.buttons["trunk.parts.tab.lock"].firstMatch
        guard lockTab.waitForExistence(timeout: 10) else { return XCTFail("部品箱の種類のタブが無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "99-部品箱")
        XCTAssertGreaterThanOrEqual(lockTab.frame.height, 44, "種類のタブが 44pt 未満")
        lockTab.tap()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "99-部品箱（錠前）")
        let equip = app.buttons["trunk.parts.equip"].firstMatch
        guard equip.waitForExistence(timeout: 5), equip.isHittable else { return XCTFail("「付け替える」が無い") }
        equip.tap()
        let pinTab = app.buttons["trunk.equip.tab.pin"].firstMatch
        guard pinTab.waitForExistence(timeout: 10) else { return XCTFail("付け替えの場所のタブが無い") }
        pinTab.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "99a-部品を付け替える")
        let part = app.buttons.matching(identifier: "trunk.equip.part").element(boundBy: 2)
        if part.exists, part.isHittable {
            XCTAssertGreaterThanOrEqual(part.frame.height, 44)
            part.tap()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "99b-部品を付け替える（ピンを足した）")
            let save = app.buttons["trunk.equip.save"].firstMatch
            XCTAssertTrue(save.isEnabled, "付け替えたのに保存できない")
            save.tap()
        }
    }

    /// **部品箱の種類ごとの絵**（#305・2026-10-18）: 角金具・内張り・タグ・ワッペン・チャーム・鍵のタブの部品1点の絵（96pt）。
    /// 付け替えの画面で錠前を替え、トランクに付けた錠前の形も撮る。タブが無ければ落とす
    func testCapturesTrunkPartsKinds() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.partsBox") else { return XCTFail("部品箱の入口が無い") }
        let kinds = [("corner", "99c-部品箱（角金具）"), ("lining", "99d-部品箱（内張り）"), ("tag", "99e-部品箱（タグ）"),
                     ("patch", "99f-部品箱（ワッペン）"), ("charm", "99g-部品箱（チャーム）"), ("key", "99h-部品箱（鍵）")]
        for (kind, name) in kinds {
            let tab = app.buttons["trunk.parts.tab.\(kind)"].firstMatch
            guard tab.waitForExistence(timeout: 10) else { return XCTFail("部品箱に \(kind) のタブが無い") }
            revealTab(tab, in: app, toLeft: true)
            guard tab.frame.maxX <= app.windows.firstMatch.frame.width, tab.isHittable else { return XCTFail("部品箱の \(kind) のタブに届かない") }
            tab.tap()
            Thread.sleep(forTimeInterval: 1.5)
            shoot(app, name)
        }
        // 錠前を替えて、トランクに付けた錠前の形（丸い桜の紋）を撮る
        let lockTab = app.buttons["trunk.parts.tab.lock"].firstMatch
        revealTab(lockTab, in: app, toLeft: false)
        guard lockTab.frame.minX >= 0, lockTab.isHittable else { return XCTFail("錠前のタブに戻れない") }
        lockTab.tap()
        let equip = app.buttons["trunk.parts.equip"].firstMatch
        guard equip.waitForExistence(timeout: 5), equip.isHittable else { return XCTFail("「付け替える」が無い") }
        equip.tap()
        let equipLock = app.buttons["trunk.equip.tab.lock"].firstMatch
        guard equipLock.waitForExistence(timeout: 10) else { return XCTFail("付け替えの錠前のタブが無い") }
        equipLock.tap()
        Thread.sleep(forTimeInterval: 1)
        let roundLock = app.buttons.matching(identifier: "trunk.equip.part").element(boundBy: 2)
        if roundLock.exists, roundLock.isHittable {
            roundLock.tap()
            Thread.sleep(forTimeInterval: 1.5)
            shoot(app, "99i-部品を付け替える（錠前を替えた）")
        }
    }

    /// 横に並んだタブの列を、`tab` が画面に入りきるまで送る（右のタブは左へ・左のタブは右へ。6回まで）。
    /// 画面の外のタブに `isHittable` を聞くと「押す点が決まらない」で落ちるので、枠で見る（Mac run 525）
    private func revealTab(_ tab: XCUIElement, in app: XCUIApplication, toLeft: Bool) {
        let width = app.windows.firstMatch.frame.width
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func onScreen() -> Bool {
            let f = tab.frame
            return !f.isEmpty && f.minX >= 0 && f.maxX <= width
        }
        var slides = 0
        while !onScreen(), slides < 6 {
            let y = tab.frame.midY
            let start = origin.withOffset(CGVector(dx: width * (toLeft ? 0.8 : 0.2), dy: y))
            let end = origin.withOffset(CGVector(dx: width * (toLeft ? 0.3 : 0.7), dy: y))
            start.press(forDuration: 0.05, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.6)
            slides += 1
        }
    }

    /// **カプセルから錠前以外が出た**（#305）: 見本の1回目は錠前、2回目は金の星のチャーム（`TrunkSample.gachaOrder`）。
    /// 1回目（錠前）をしまって、もう1回回す。出なければ落とす
    func testCapturesTrunkGachaSecondDraw() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.gacha.open") else { return XCTFail("カプセルの機械の入口が無い") }
        for draw in 0..<2 {
            let insert = app.buttons["trunk.gacha.insert"].firstMatch
            guard insert.waitForExistence(timeout: 10), insert.isEnabled else { return XCTFail("\(draw + 1) 回目の硬貨を入れられない") }
            insert.tap()
            let crank = app.buttons["trunk.gacha.crank"].firstMatch
            guard crank.waitForExistence(timeout: 5) else { return XCTFail("ハンドルが無い") }
            for _ in 0..<4 {
                crank.tap()
                Thread.sleep(forTimeInterval: 0.4)
            }
            let capsule = app.buttons["trunk.gacha.openCapsule"].firstMatch
            guard capsule.waitForExistence(timeout: 10) else { return XCTFail("1周してもカプセルが出ない") }
            capsule.tap()
            let keep = app.buttons["trunk.gachaOpen.keep"].firstMatch
            guard keep.waitForExistence(timeout: 10) else { return XCTFail("開けた画面が出ない") }
            Thread.sleep(forTimeInterval: 2)
            if draw == 1 { shoot(app, "98d-カプセルを開けた（チャーム）") }
            keep.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: - 旅のトランクの中身と回したときの面（2026-10-18・板「旅のトランク」）

    /// 見本のメダル 10 枚（8 枠に 7 枚と「ほか 3」）・Pro とサポーターの番号（会員証）・すれちがいの見本（乗車券）
    private static let trunkInsideArgs = ["-JPPreviewTrunk", "YES", "-JPPreviewPro", "YES", "-JPPreviewSupporter", "7",
                                          "-JPPreviewPass", "YES",
                                          "-JPPreviewBadges",
                                          "earlyUser:1,first:1,prefectures:2,countries:1,seasons:1,morning:1,night:1,books:1,wish:1,supporter:1"]

    /// **ふたを開ける → 中身を手に取る**: 閉じた姿・開けた姿（胴に会員証と乗車券・ふたの裏にメダル）・
    /// メダルを持ち上げた・「ほか N」を持ち上げた。目印が無ければ落とす。押せる所は 44pt 以上
    func testCapturesTrunkOpen() {
        let app = launchTrunk(Self.trunkInsideArgs)
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.open") else { return XCTFail("「ふたを開ける」の入口が無い") }
        let toggle = app.buttons["trunk.open.toggle"].firstMatch
        guard toggle.waitForExistence(timeout: 15) else { return XCTFail("「ふたを開ける」のボタンが無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "100-ふたを開ける（閉じている）")
        for id in ["trunk.open.toggle", "trunk.open.take"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].firstMatch.frame.height, 44, "\(id) が 44pt 未満")
        }
        toggle.tap()
        let medal = app.buttons["trunk.inside.medal"].firstMatch
        guard medal.waitForExistence(timeout: 15) else { return XCTFail("開けたふたの裏にメダルが無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "100a-ふたを開けた")
        XCTAssertTrue(app.buttons["trunk.inside.card"].firstMatch.exists, "Pro の人の内ポケットに会員証が無い")
        XCTAssertTrue(app.buttons["trunk.inside.more"].firstMatch.exists, "メダル 10 枚なのに「ほか N」が無い")
        medal.tap()
        let go = app.buttons["trunk.hold.go"].firstMatch
        guard go.waitForExistence(timeout: 10) else { return XCTFail("メダルを押しても持ち上がらない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "100b-中身を手に取った（メダル）")
        let putBack = app.buttons["trunk.hold.putBack"].firstMatch
        XCTAssertGreaterThanOrEqual(go.frame.height, 44, "出口のボタンが 44pt 未満")
        XCTAssertGreaterThanOrEqual(putBack.frame.height, 44, "「トランクに戻す」が 44pt 未満")
        putBack.tap()
        let more = app.buttons["trunk.inside.more"].firstMatch
        guard more.waitForExistence(timeout: 10), more.isHittable else { return XCTFail("戻したあと「ほか N」を押せない") }
        more.tap()
        guard go.waitForExistence(timeout: 10) else { return XCTFail("「ほか N」を押しても持ち上がらない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "100c-中身を手に取った（ほかのメダル）")
        putBack.tap()
        let card = app.buttons["trunk.inside.card"].firstMatch
        if card.waitForExistence(timeout: 5), card.isHittable {
            card.tap()
            if go.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 1)
                shoot(app, "100d-中身を手に取った（会員証）")
                putBack.tap()
            }
        }
    }

    /// **空のトランク**（メダルも会員証も乗車券も無い人・`-JPPreviewTrunk empty`）: 手に入れ方の3行と「写真を投稿する」
    func testCapturesTrunkOpenEmpty() {
        let app = launchTrunk(["-JPPreviewTrunk", "empty"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.open") else { return XCTFail("「ふたを開ける」の入口が無い") }
        let post = app.buttons["trunk.open.emptyPost"].firstMatch
        guard post.waitForExistence(timeout: 15) else { return XCTFail("空のトランクに「写真を投稿する」が無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "100e-空のトランク")
        XCTAssertGreaterThanOrEqual(post.frame.height, 44, "「写真を投稿する」が 44pt 未満")
    }

    /// **回したときの面**: 手に取って回す → 側面 → 上と背面 → 底（板 TrunkFaces）。向きのボタンが無ければ落とす
    func testCapturesTrunkSpinFaces() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewPro", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        let spin = app.buttons["trunk.spin"].firstMatch
        guard spin.isHittable else { return XCTFail("トランクを押せない") }
        spin.tap()
        let close = app.buttons["trunk.spin.close"].firstMatch
        guard close.waitForExistence(timeout: 10) else { return XCTFail("回す画面が開かない") }
        // 面を描き終えるのを待ち、描いた時間を記録する（表を先に・残りを後で描く。引っかかりの見張り）
        let box = app.descendants(matching: .any)["trunk.spin.box"].firstMatch
        let ready = NSPredicate(format: "value BEGINSWITH %@", "faces-ready")
        if XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: box)], timeout: 20) == .completed {
            let took = (box.value as? String) ?? ""
            XCTContext.runActivity(named: "回す画面の面を描いた時間: \(took)") { _ in }
        } else {
            XCTFail("回す画面の面を描き終えない")
        }
        // 正面（吊るすタグ・チャーム・鍵が回しても消えない・#305）→ 側面 → 上と背面（上の面と持ち手・紐）→ 底
        for (id, name) in [("front", "91d-回した正面（吊るす部品）"), ("side", "91a-回した側面"), ("topBack", "91b-回した上と背面"),
                           ("bottom", "91c-回した底（蝶番と足）")] {
            let button = app.buttons["trunk.spin.view.\(id)"].firstMatch
            guard button.waitForExistence(timeout: 5) else { return XCTFail("向きのボタン \(id) が無い") }
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "向きのボタン \(id) が 44pt 未満")
            button.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, name)
        }
        close.tap()
    }

    // MARK: - 人のトランク（2026-10-18・板 TheirTrunk・TheirInside・ProfileTrunk）

    /// **人のトランク**（`-JPPreviewTheirTrunk`・Debug のみ。サーバーには何も送らない見本）: ホームの写真 → 作者の
    /// プロフィールのトランクの段 → 人のトランク（ラベルを選ぶ・地名の無いラベル）→ 回す → ふたを開ける。
    /// 作者の行が出ない（写真の並び次第）なら撮らずに抜ける。**プロフィールが出たのに段が無ければ落とす**。押せる所は 44pt 以上
    func testCapturesTheirTrunk() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        // 人のページの見出し（公開プロフィール）は本番から読む（staging にこの人は居ない・一巡と同じ）
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewTheirTrunk", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20) else { return XCTFail("タブが出ない") }

        let firstPhoto = app.buttons["feed.photo"].firstMatch
        var pushes = 0
        while !(firstPhoto.waitForExistence(timeout: 2) && firstPhoto.isHittable), pushes < 8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            pushes += 1
        }
        guard firstPhoto.exists, firstPhoto.isHittable else { return }
        firstPhoto.tap()
        let toAuthor = app.buttons["photo.author"].firstMatch
        var authorPushes = 0
        while toAuthor.waitForExistence(timeout: 5), !toAuthor.isHittable, authorPushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            authorPushes += 1
        }
        guard toAuthor.exists, toAuthor.isHittable else { return }
        toAuthor.tap()

        let card = app.buttons["profile.trunk"].firstMatch
        guard card.waitForExistence(timeout: 15) else { return XCTFail("人のプロフィールにトランクの段が無い") }
        scrollTo(card, in: app)
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "101-人のプロフィールのトランク")
        XCTAssertGreaterThanOrEqual(card.frame.height, 44, "トランクの段が 44pt 未満")
        card.tap()

        let open = app.buttons["trunk.their.open"].firstMatch
        guard open.waitForExistence(timeout: 15) else { return XCTFail("人のトランクの画面が開かない") }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "101a-人のトランク")
        for id in ["trunk.their.open", "trunk.their.spin"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].firstMatch.frame.height, 44, "\(id) が 44pt 未満")
        }
        let labels = app.buttons.matching(identifier: "trunk.their.label")
        XCTAssertGreaterThan(labels.count, 0, "トランクのラベルが押せない")
        for i in 0..<labels.count {
            let frame = labels.element(boundBy: i).frame
            XCTAssertGreaterThanOrEqual(min(frame.width, frame.height), 44 - 0.5, "ラベルの押せる所が 44pt 未満")
        }
        // 地名の無いラベル（地名なしの形）を選ぶ
        let sealed = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@",
                                                      "trunk.their.label", "旅の記録")).firstMatch
        if sealed.exists, sealed.isHittable {
            sealed.tap()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "101b-人のトランク（地名の無いラベル）")
        } else {
            XCTFail("見本の地名の無いラベルが押せない")
        }

        app.buttons["trunk.their.spin"].firstMatch.tap()
        let close = app.buttons["trunk.spin.close"].firstMatch
        if close.waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "101d-人のトランクを回した")
            close.tap()
        } else {
            XCTFail("人のトランクを回す画面が開かない")
        }

        guard open.waitForExistence(timeout: 10), open.isHittable else { return XCTFail("「ふたを開ける」が押せない") }
        open.tap()
        let medal = app.buttons["trunk.inside.medal"].firstMatch
        guard medal.waitForExistence(timeout: 15) else { return XCTFail("人のトランクのふたが開かない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "101c-人のトランクの中")
        XCTAssertFalse(app.buttons["trunk.open.emptyPost"].firstMatch.exists, "人のトランクに「写真を投稿する」が出る")
        XCTAssertFalse(app.buttons["trunk.open.toggle"].firstMatch.exists, "人のトランクに開け閉めのボタンが出る")

        // 会員証を手に取って回す（番号と始めた年月を出さない）
        let go = app.buttons["trunk.hold.go"].firstMatch
        let putBack = app.buttons["trunk.hold.putBack"].firstMatch
        let insideCard = app.buttons["trunk.inside.card"].firstMatch
        guard insideCard.waitForExistence(timeout: 5), insideCard.isHittable else { return XCTFail("人のトランクの内ポケットに会員証が無い") }
        insideCard.tap()
        guard go.waitForExistence(timeout: 10) else { return XCTFail("会員証を押しても持ち上がらない") }
        go.tap()
        let viewerClose = app.buttons["supporter.viewer.close"].firstMatch
        guard viewerClose.waitForExistence(timeout: 10) else { return XCTFail("会員証を回す画面が開かない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "101e-人の会員証を回す（番号なし）")
        XCTAssertFalse(app.staticTexts["supporter.viewer.number"].firstMatch.exists, "人の会員証を回す画面に番号が出る")
        let numbered = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No.")).firstMatch
        XCTAssertFalse(numbered.exists, "人の会員証を回す画面に番号が出る")
        viewerClose.tap()

        // わたしの乗車券を手に取って回す
        let tickets = app.buttons["trunk.inside.tickets"].firstMatch
        guard tickets.waitForExistence(timeout: 10), tickets.isHittable else { return XCTFail("人のトランクに乗車券が無い") }
        tickets.tap()
        guard go.waitForExistence(timeout: 10) else { return XCTFail("乗車券を押しても持ち上がらない") }
        XCTAssertGreaterThanOrEqual(putBack.frame.height, 44, "「トランクに戻す」が 44pt 未満")
        go.tap()
        guard app.descendants(matching: .any)["trunk.their.ticket"].firstMatch.waitForExistence(timeout: 10) else {
            return XCTFail("乗車券を回す画面が開かない")
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "101f-人の乗車券を回す")
    }

    // MARK: - アイコンとカバー（#304・2026-10-18・板「12 アイコンとカバー」）

    /// 起動（見本の利用者・`-JPPreviewNoCover` でカバーが無い姿）してマイページを開く
    private func launchProfileLooks(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += extra
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        return app
    }

    /// **マイページの額縁 → プロフィールの編集（カバーの候補）→ 候補を押す → アイコンの切り抜き → ほかの人からの見え方**
    /// （板 52・50・50b・50c）。サーバーには何も送らない（保存は押さない）。出なければ撮らない（この試験の決まり）。
    /// 額縁・候補・「決める」が 44pt 未満なら落とす
    func testCapturesProfileCoverPick() {
        let app = launchProfileLooks(["-JPPreviewNoCover", "YES"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20) else { return }
        let frame = app.descendants(matching: .any)["mypage.coverFrame"].firstMatch
        guard frame.waitForExistence(timeout: 10) else { return XCTFail("カバーが無いのに額縁が出ない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "104-マイページ（カバーの額縁）")
        XCTAssertGreaterThanOrEqual(frame.frame.height, 44, "額縁が 44pt 未満")
        guard frame.isHittable else { return }
        frame.tap()

        let pick = app.descendants(matching: .any)["profileEdit.coverPick"].firstMatch
        guard pick.waitForExistence(timeout: 15) else { return XCTFail("額縁からカバーの候補へ進まない") }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "104a-プロフィールの編集（カバーの候補）")
        let first = app.buttons["profileEdit.coverPick.0"].firstMatch
        if first.waitForExistence(timeout: 10) {
            XCTAssertGreaterThanOrEqual(first.frame.height, 44, "候補が 44pt 未満")
            let recent = app.buttons["profileEdit.coverSort.recent"].firstMatch
            XCTAssertGreaterThanOrEqual(recent.frame.height, 44, "「最近」が 44pt 未満")
            if first.isHittable {
                first.tap()
                Thread.sleep(forTimeInterval: 4)
                shoot(app, "104b-プロフィールの編集（候補を選んだ）")
            }
        }

        let avatar = app.buttons["profileEdit.avatar"].firstMatch
        if avatar.waitForExistence(timeout: 5), avatar.isHittable {
            avatar.tap()
            let done = app.buttons["avatarCrop.done"].firstMatch
            if done.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 4)
                shoot(app, "104c-アイコンを選ぶ（丸く切り抜く）")
                XCTAssertGreaterThanOrEqual(app.buttons["avatarCrop.device"].firstMatch.frame.height, 44, "「端末の写真から」が 44pt 未満")
                goBack(app)
            }
        }

        let looks = app.buttons["profileEdit.looks"].firstMatch
        guard looks.waitForExistence(timeout: 10) else { return }
        scrollTo(looks, in: app)
        guard looks.isHittable else { return }
        looks.tap()
        guard app.descendants(matching: .any)["profileLooks"].firstMatch.waitForExistence(timeout: 10) else {
            return XCTFail("ほかの人からの見え方が開かない")
        }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "104d-ほかの人からの見え方")
    }

    /// **初めての投稿のあと「この1枚をカバーに」**（板 51・`-JPPreviewCoverOffer first`・サーバーには何も送らない）。
    /// 見本は必ず出るので、出ない・「カバーにする」「あとで」「もう聞かないで」が無い・44pt 未満なら落とす。「あとで」で閉じる
    func testCapturesCoverOffer() {
        let app = launchProfileLooks(["-JPPreviewCoverOffer", "first"])
        let apply = app.buttons["coverOffer.apply"].firstMatch
        guard apply.waitForExistence(timeout: 45) else { return XCTFail("差し出しが出ない") }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "105-この1枚をカバーに（初めての投稿）")
        let later = app.buttons["coverOffer.later"].firstMatch
        let never = app.buttons["coverOffer.never"].firstMatch
        for (button, name) in [(apply, "カバーにする"), (later, "あとで"), (never, "もう聞かないで")] {
            XCTAssertTrue(button.exists, "「\(name)」が無い")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "「\(name)」が 44pt 未満")
        }
        XCTAssertTrue(app.descendants(matching: .any)["coverOffer.coins"].firstMatch.exists, "硬貨の行が無い")
        guard later.isHittable else { return XCTFail("「あとで」を押せない") }
        later.tap()
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: apply)], timeout: 5)
        XCTAssertEqual(closed, .completed, "「あとで」で閉じない")
    }

    /// **いいねが集まった1枚をカバーに**（板 51b・カバーあり・`-JPPreviewCoverOffer liked`）。「今のままにする」で閉じる
    func testCapturesCoverOfferLiked() {
        let app = launchProfileLooks(["-JPPreviewCoverOffer", "liked"])
        let apply = app.buttons["coverOffer.apply"].firstMatch
        guard apply.waitForExistence(timeout: 45) else { return XCTFail("差し出しが出ない") }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "105a-この1枚をカバーに（いいねが集まった）")
        XCTAssertFalse(app.descendants(matching: .any)["coverOffer.coins"].firstMatch.exists, "カバーがあるのに硬貨を約束している")
        let keep = app.buttons["coverOffer.later"].firstMatch
        XCTAssertGreaterThanOrEqual(keep.frame.height, 44, "「今のままにする」が 44pt 未満")
        guard keep.isHittable else { return XCTFail("「今のままにする」を押せない") }
        keep.tap()
    }

    /// **アイコン・カバーのお礼**（板 53・`-JPPreviewCoinReward`）。1つ（アイコン）と、設定済みの人に両方まとめた +6。
    /// 見本は必ず出るので、出ない・「カプセルを回す」「あとで」「閉じる」が無い・44pt 未満なら落とす
    func testCapturesCoinReward() {
        for (arg, name) in [("avatar", "106-アイコンを設定したお礼"), ("both", "106a-アイコンとカバーのお礼（設定済みの人）")] {
            let app = launchProfileLooks(["-JPPreviewCoinReward", arg])
            let turn = app.buttons["coinReward.turn"].firstMatch
            guard turn.waitForExistence(timeout: 45) else { return XCTFail("お礼の知らせが出ない（\(arg)）") }
            Thread.sleep(forTimeInterval: 2)
            shoot(app, name)
            for id in ["coinReward.turn", "coinReward.later", "coinReward.close"] {
                let button = app.buttons[id].firstMatch
                XCTAssertTrue(button.exists, "\(id) が無い")
                XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(id) が 44pt 未満")
            }
            XCTAssertEqual(app.descendants(matching: .any)["coinReward.breakdown"].firstMatch.exists, arg == "both",
                           "内訳（アイコン +3 · カバー +3）の出し分けが違う")
            app.terminate()
        }
    }

    // MARK: - とおまわり号の中（2026-10-19・板 CamperRoomMain・CamperFurniture）

    /// 外の車の「中に入る」から室内へ。入れたら true
    private func openCamperRoom(_ app: XCUIApplication) -> Bool {
        guard openCamper(app) else { return false }
        let enter = app.buttons["camper.room.enter"].firstMatch
        guard enter.waitForExistence(timeout: 15) else { return false }
        if !enter.isHittable { scrollTo(enter, in: app) }
        enter.tap()
        return app.descendants(matching: .any)["camper.room.scene"].firstMatch.waitForExistence(timeout: 15)
    }

    /// 立体を組み終えるまで待つ（読み上げの値に「camper-room-ready 部屋 時刻」が出る・見本の起動のときだけ）
    @discardableResult
    private func waitRoom(_ app: XCUIApplication, _ id: String, _ marker: String, timeout: TimeInterval = 40) -> Bool {
        let scene = app.descendants(matching: .any)[id].firstMatch
        let ready = NSPredicate(format: "value CONTAINS %@", marker)
        let done = XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: scene)], timeout: timeout) == .completed
        // 組んだ形が次のコマで描かれ、カメラの動き（0.6 秒）が止まるまで
        Thread.sleep(forTimeInterval: 2)
        return done
    }

    /// **とおまわり号の中**（`-JPPreviewCamperRoomReset`・Debug のみ。毎回最初の並び・保存しない）: 室内の昼・夜・家具の図鑑・
    /// 家具の寄り 8 点（昼と夜）を**必ず撮る**（入れない・組み終えないなら落とす）。押せる所は 44pt 以上
    func testCapturesCamperRoom() {
        // 寄り 8 点は部屋を組み直す。図鑑が 2,000 点を超えても、既定の 300 秒で切らない
        executionTimeAllowance = 1200
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        guard waitRoom(app, "camper.room.scene", "camper-room-ready") else { return XCTFail("部屋を組み終えない") }
        shoot(app, "96-とおまわり号の中（昼）")
        for id in ["camper.room.back", "camper.room.night", "camper.room.tool.place", "camper.room.tool.style", "camper.room.tool.photos",
                   "camper.room.tool.dex"] {
            let b = app.buttons[id].firstMatch
            XCTAssertTrue(b.exists, "\(id) が無い")
            if b.exists { XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(id) が 44pt 未満") }
        }
        // 「外へ」と「外へ出る」は同じ操作なので 1 つ（左上の「外へ」）にまとめた（2026-10-21）
        XCTAssertFalse(app.buttons["camper.room.out"].firstMatch.exists, "下の「外へ出る」が左上の「外へ」と重なっている")
        app.buttons["camper.room.night"].firstMatch.tap()
        XCTAssertTrue(waitRoom(app, "camper.room.scene", "night"), "夜にならない")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "96a-とおまわり号の中（夜）")
        app.buttons["camper.room.night"].firstMatch.tap()
        waitRoom(app, "camper.room.scene", "day")

        // 家具の図鑑
        app.buttons["camper.room.tool.dex"].firstMatch.tap()
        let count = app.descendants(matching: .any)["camper.room.dex.count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10), "家具の図鑑が開かない")
        // 家具の小さな絵（端末の中で描く）が出るまで
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "96b-とおまわり号の家具の図鑑")
        XCTAssertGreaterThanOrEqual(app.buttons["camper.room.dex.close"].firstMatch.frame.height, 44, "図鑑の「閉じる」が 44pt 未満")

        // 家具の寄り（代表 8 点・昼と夜）。owner「ホンモノに見えるか」を絵で確かめる
        let closeUps: [(tab: String, id: String, name: String)] = [
            ("floor", "bed.platform", "木の寝台"), ("floor", "heater.wood_stove", "薪ストーブ"), ("floor", "storage.trunk", "旅の鞄"),
            ("floor", "table.dinette_post", "一本脚の座卓"), ("floor", "seating.floor_cushion", "座布団"),
            ("floor", "floor_lamp.brass_stem", "真鍮の一本足"), ("wall", "photo_frame.landscape", "横長の額"),
            ("ceiling", "plant_hanger.macrame", "マクラメ"),
        ]
        let search = app.textFields["camper.room.dex.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "図鑑の探し欄が無い")
        for (i, c) in closeUps.enumerated() {
            let clear = app.buttons["camper.room.dex.search.clear"].firstMatch
            if clear.exists { clear.tap() }
            search.tap()
            search.typeText(c.id + "\n")
            let card = app.buttons["camper.room.dex.\(c.id)"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10), "図鑑に \(c.id) が無い")
            guard card.isHittable else { XCTFail("\(c.id) を押せない"); continue }
            card.tap()
            XCTAssertTrue(waitRoom(app, "camper.room.closeup", "camper-room-ready"), "\(c.id) の寄りを組み終えない")
            shoot(app, String(format: "96c%02d-家具の寄り（%@・昼）", i + 1, c.name))
            let night = app.buttons["camper.room.closeup.night"].firstMatch
            XCTAssertGreaterThanOrEqual(night.frame.height, 44, "寄りの昼夜の切り替えが 44pt 未満")
            night.tap()
            XCTAssertTrue(waitRoom(app, "camper.room.closeup", "night"), "\(c.id) の寄りが夜にならない")
            Thread.sleep(forTimeInterval: 1)
            shoot(app, String(format: "96c%02d-家具の寄り（%@・夜）", i + 1, c.name))
            app.buttons["camper.room.closeup.close"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        app.buttons["camper.room.dex.close"].firstMatch.tap()
    }

    /// **初めての手引きと押して置く**（`-JPPreviewCamperRoomCoach`・Debug のみ・2026-10-21）: 部屋に初めて入った時の 3 行の手引き、
    /// 「置く」の新しい家具の件数・棚の真鍮の点、棚の家具を押して置ける所が光った所を**必ず撮る**。押せる所は 44pt 以上
    func testCapturesCamperRoomGuide() {
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomCoach", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        guard waitRoom(app, "camper.room.scene", "camper-room-ready") else { return XCTFail("部屋を組み終えない") }
        let done = app.buttons["camper.room.coach.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "初めての手引きが出ない")
        shoot(app, "96f-とおまわり号の中（初めての手引き）")
        XCTAssertGreaterThanOrEqual(done.frame.height, 44, "手引きの「わかった」が 44pt 未満")
        done.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 2), "手引きが閉じない")
        app.buttons["camper.room.tool.place"].firstMatch.tap()
        XCTAssertTrue(app.buttons["camper.room.done"].firstMatch.waitForExistence(timeout: 5), "置く場面にならない")
        // 壁の額は何枚でも掛けられ、どの部屋にも置ける所がある（床の大きな寝台は置ける所が無いことがある・run 605）
        app.buttons["camper.room.tab.wall"].firstMatch.tap()
        // 棚は分類ごと（壁の最初は「壁の棚」）。額の分類に切り替える
        let frameChip = app.buttons["camper.room.tray.cat.photo_frame"].firstMatch
        XCTAssertTrue(frameChip.waitForExistence(timeout: 5), "壁の棚に額の分類が無い")
        if frameChip.exists, frameChip.isHittable { frameChip.tap() }
        let trayItems = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "camper.room.tray.photo_frame."))
        let first = trayItems.firstMatch
        guard first.waitForExistence(timeout: 5) else { return XCTFail("棚に家具が無い") }
        Thread.sleep(forTimeInterval: 2)
        first.tap()
        let banner = app.descendants(matching: .any)["camper.room.armed"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "棚の家具を押しても「置く所を押す」が出ない")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "96g-とおまわり号の中（押して置く・置ける所）")
        let cancel = app.buttons["camper.room.armed.cancel"].firstMatch
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44, "「やめる」が 44pt 未満")
        // 同じ家具をもう一度押すと空いた所へ置く（今までの置き方）
        first.tap()
        XCTAssertFalse(banner.waitForExistence(timeout: 2), "もう一度押しても置かれない")
        XCTAssertTrue(app.buttons["camper.room.undo"].firstMatch.isEnabled, "置いたのに元に戻せない")
        app.buttons["camper.room.undo"].firstMatch.tap()
        XCTAssertTrue(app.buttons["camper.room.redo"].firstMatch.isEnabled, "元に戻したのにやり直せない")
    }

    /// **家具の接写の一覧**（`-JPPreviewCamperRoomContact`・Debug のみ・2026-10-21）: 板と別種の家具全部を本物の SceneKit で
    /// 図鑑の寄りと同じ小部屋に描き、8 点ずつの頁を昼と夜で**必ず撮る**（全家具の出来を本物の絵で見る。ソフトラスタでは素材・光が見えない）
    func testCapturesCamperRoomContactSheet() {
        executionTimeAllowance = 1500
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomContact", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        let sheet = app.descendants(matching: .any)["camper.room.contact"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "接写の一覧が出ない")
        let next = app.buttons["camper.room.contact.next"].firstMatch
        let prev = app.buttons["camper.room.contact.prev"].firstMatch
        for (mood, moodName) in [("day", "昼"), ("night", "夜")] {
            var page = 1
            while page <= 40 {
                let ready = waitRoom(app, "camper.room.contact", "contact-ready \(mood) \(page)/", timeout: 90)
                XCTAssertTrue(ready, "接写の一覧の \(moodName) \(page) 頁を描き終えない")
                // 並びの所だけを撮る（画面全体だと長辺 700px に縮んで 1 点が小さい）
                let grid = app.descendants(matching: .any)["camper.room.contact.grid"].firstMatch
                let shot = XCTAttachment(screenshot: grid.exists ? grid.screenshot() : app.screenshot())
                shot.name = String(format: "96e-家具の接写（%@・%02d）", moodName, page)
                shot.lifetime = .keepAlways
                add(shot)
                guard next.exists, next.isEnabled else { break }
                next.tap()
                page += 1
            }
            // 頁を初めに戻して、昼と夜を替える
            while prev.exists, prev.isEnabled { prev.tap() }
            if mood == "day" { app.buttons["camper.room.contact.mood"].firstMatch.tap() }
        }
    }

    /// **置いている途中**（`-JPPreviewCamperRoomLift`・Debug のみ）: 旅の鞄を持ち上げて寝台の上へ動かした途中
    /// （マス目・赤いマス）を**必ず撮る**。「元に戻す」「閉じる」は 44pt 以上。升の枠は縦 96pt 以上
    func testCapturesCamperRoomPlacing() {
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomLift", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        guard waitRoom(app, "camper.room.scene", "camper-room-ready", timeout: 90) else { return XCTFail("部屋を組み終えない") }
        XCTAssertTrue(app.buttons["camper.room.done"].firstMatch.waitForExistence(timeout: 5), "置く場面にならない")
        shoot(app, "96d-とおまわり号の中（置いている途中）")
        for id in ["camper.room.undo", "camper.room.redo", "camper.room.done", "camper.room.tab.floor", "camper.room.tab.wall",
                   "camper.room.tab.ceiling"] {
            let b = app.buttons[id].firstMatch
            XCTAssertTrue(b.exists, "\(id) が無い")
            if b.exists { XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(id) が 44pt 未満") }
        }
        // 「元に戻す」が主ボタンに押しつぶされない（run 568 で幅 0 になった）
        XCTAssertGreaterThanOrEqual(app.buttons["camper.room.undo"].firstMatch.frame.width, 88, "「元に戻す」の幅が狭い")
        let done = app.buttons["camper.room.done"].firstMatch
        XCTAssertTrue(done.label.contains("閉じる"), "置くのを終える主ボタンは「閉じる」（今は「\(done.label)」）")
        let resize = app.descendants(matching: .any)["camper.room.panelResize"].firstMatch
        XCTAssertTrue(resize.exists, "棚の高さを変える境が無い")
        // 分類チップ（`camper.room.tray.cat.*`）は除く（チップは 44pt・run 605 でチップを家具の枠と取り違えた）
        let tray = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT (identifier BEGINSWITH %@)",
                                                    "camper.room.tray.", "camper.room.tray.cat.")).firstMatch
        if tray.exists { XCTAssertGreaterThanOrEqual(tray.frame.height, 96, "棚の家具の枠が縦に狭い") }
    }
}
