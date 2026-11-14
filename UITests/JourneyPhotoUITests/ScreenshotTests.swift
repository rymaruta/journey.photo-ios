import XCTest
import CoreLocation
import UIKit

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
    ///
    /// #417（2026-10-30）: 段は写真の大1→2→2 の後ろへ移った。送る回数の上限を増やした。
    /// 札 #595（2026-11-13）: ホームは切り替えの無い1本の並び。下へ送った所でも**切り替えの札が出ない**ことと、
    /// 写真が続いていることを確かめる（前は「切り替えが見出しの下に留まる」を確かめていた）
    private func shootSpotShelf(_ app: XCUIApplication) {
        // 🔴 段は画面の下（約 1000pt）なので、**在って押せるまで送る**（先に待って見つからず黙って抜けていた・PR #422 の確かめ）。
        // 「行きたい」（札の下端）が在ればそれを、無ければ札を待つ
        let photo = app.buttons["home.spotShelf.card"].firstMatch
        let wish = app.buttons["home.spotShelf.wish"].firstMatch
        func shelfReady() -> Bool {
            let target = wish.exists ? wish : photo
            return target.exists && target.isHittable
        }
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        var pushes = 0
        while !shelfReady(), pushes < Self.shelfPushLimit {
            low.press(forDuration: 0.05, thenDragTo: high)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        if shelfReady() {
            Thread.sleep(forTimeInterval: 4)
            shoot(app, "10d-ホーム（いまの季節のスポット・作例）")
        }
        // 下へ送った後も、写真が続き、切り替えの札は出ない。**段の無い日も確かめる**（数回は必ず送る）
        while pushes < Self.pinCheckPushes {
            low.press(forDuration: 0.05, thenDragTo: high)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        XCTAssertFalse(app.buttons["home.feed.latest"].firstMatch.exists, "ホームに切り替えの札（新着）が出ている（札 #595 でやめた）")
        XCTAssertTrue(app.buttons["feed.photo"].firstMatch.exists, "下へ送ったら写真が無い")
        shoot(app, "10f-ホーム（下へ送った後・1本の並び）")
        for _ in 0..<pushes {
            high.press(forDuration: 0.05, thenDragTo: low)
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// 下へ送った所の確かめで、段が無い日でも必ず送る回数（1画面ぶんより下へ）
    private static let pinCheckPushes = 4

    /// 季節の段まで送る回数の上限（短い引き＝画面の 35%）。#417 で段が写真の5枚の後ろへ移ったので 3 から増やした
    private static let shelfPushLimit = 10

    /// **ホームの右上の見出し（探す・お知らせ・メニューのガラスの帯）を寄りで撮る**（2026-10-14）。
    /// 「デカすぎる」（owner）を 22pt → 19pt にしたので、前後の回で帯の高さ・絵の大きさを
    /// 見比べられるように、上のバーだけを切り出す。3つの押せる範囲（frame）も文で残す
    /// （帯の高さは絵より数字の方が比べやすい）。出なければ撮らない
    private func shootHeaderBand(_ app: XCUIApplication, tab: String = "10e-ホーム") {
        let bar = app.navigationBars.firstMatch
        guard bar.exists else { return }
        let shot = XCTAttachment(screenshot: bar.screenshot())
        shot.name = "\(tab)（右上の見出しの帯・寄り）"
        shot.lifetime = .keepAlways
        add(shot)
        let ids = ["header.messages", "header.notifications", "header.menu"]
        let lines = ids.map { id -> String in
            let button = app.buttons[id].firstMatch
            return button.exists ? "\(id): \(button.frame)" : "\(id): 無し"
        }
        let note = XCTAttachment(string: (["バー: \(bar.frame)"] + lines).joined(separator: "\n"))
        note.name = "\(tab)（見出しの寸法）"
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
    /// 揃ったら、札の行に「旅行プランに入れる」「経路」、その下に「地図で見る」があり、シェアは右上の1つだけ（違えば落とす）。
    /// 「地図で見る」を押して**アプリの中の地図**が出ることも見て撮り、頁へ戻す。
    /// 一覧の行（`map.spotRow`）から開くスポットは地図のピン＝座標があるので、2つの札は必ず出る
    private func shootSpotTop(_ app: XCUIApplication) {
        let wish = app.buttons["spot.official.wish"].firstMatch
        guard wish.waitForExistence(timeout: 5) else { return }
        shoot(app, "13e-撮影スポット（上・行動の札）")
        let toMap = app.buttons["spot.official.map"].firstMatch
        XCTAssertTrue(toMap.exists, "スポットの頁に「地図で見る」が無い")
        XCTAssertTrue(app.buttons["spot.official.directions"].firstMatch.exists, "スポットの頁に「経路」が無い")
        // 2026-11-10（札 #521）: 「旅行プランに入れる」が札の行にある（地図で見るは札の行の下の1行）
        XCTAssertTrue(app.buttons["spot.official.trip"].firstMatch.exists, "スポットの頁に「旅行プランに入れる」が無い")
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
        // 出典の1行の当たりは 44pt 以上（押せるものの最小・2026-10-03）。
        // 端数（43.99999）は 44 と見る（同じファイルの 44pt の確かめと同じ決まり。
        // 2026-11-09 PR #509 の Mac で 43.999999999999886 が 44 未満として落ちた）
        XCTAssertGreaterThanOrEqual(credit.frame.height, 43.9, "作例の出典の当たりが 44pt 未満（\(credit.frame.height)）")
        XCTAssertGreaterThanOrEqual(credit.frame.width, 43.9, "作例の出典の当たりが 44pt 未満（\(credit.frame.width)）")
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
        // ストーリー作成の入口の案内（端末に1回だけ・#404）は撮らない
        app.launchArguments += ["-story.captionHintShown", "YES"]
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
            // 見出しの帯はどのタブも同じ中身（2026-10-21）。探す・マップも寸法を残して見比べる
            if name == "ホーム" || name == "探す" || name == "マップ" { shootHeaderBand(app, tab: "1\(index)e-\(name)") }
            if name == "ホーム" {
                // 札 #595（2026-11-13 owner 決定）: 「おすすめ・フォロー中・新着」の切り替えはやめ、1本の並びにした。
                // 前は「新着」を押した直後（10b）と「フォロー中」が空の回（10c）を撮っていた。いまは札が無いことを確かめ、
                // フォロー中の人の新しい写真の段（`home.following`）が出ている日はそれを撮る。空の知らせは出た日だけ撮る
                for id in ["home.feed.recommended", "home.feed.following", "home.feed.latest"] {
                    XCTAssertFalse(app.buttons[id].firstMatch.exists, "ホームに切り替えの札（\(id)）が出ている")
                }
                XCTAssertFalse(app.buttons["home.exploreMap"].firstMatch.exists, "消したはずの「撮影地を探す」の札が出ている")
                if app.descendants(matching: .any)["home.following"].firstMatch.exists {
                    shoot(app, "10b-ホーム（フォロー中の人の新しい写真）")
                }
                if app.buttons["home.emptyAction"].firstMatch.exists {
                    shoot(app, "10c-ホーム（写真が無い日の次の行動）")
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
        // 🔴 run 58 はこれを途中に置いて落ちた——ストーリー作成は**覆う画面**で出る（当時はシート、
        // 2026-10-30 #406 から画面いっぱい）ので、閉じないまま次の手に進むと**タブの帯が覆われて**押せない
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
            // 2026-11-12: 写真がまだ無いときの「写真を選ぶ」の大きな枠（`upload.add`）は、押すとすぐ選ぶ画面を開く。
            // 帯の「追加」（メニュー）のときだけ「ライブラリから選ぶ」を押す
            let library = app.buttons["ライブラリから選ぶ"].firstMatch
            if library.waitForExistence(timeout: 3) { library.tap() }
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

    /// **ストーリーとそこから作った写真の関係**（2026-11-11・owner「関係を明確にして」）。
    ///
    /// `-JPPreviewKeptStory YES` で、写真の詳細はどの写真も「本人のストーリーから作った」ものとして開く
    /// （口を呼ばない見本・`PreviewSession.keptStorySample`）。写真の詳細の「ストーリーから作った写真 ›」（20k）、
    /// 押して開いたストーリーの「写真にしました ›」（20l）、「…」→ 削除の2つから選ぶ確認（20m）を撮る。
    /// 🔴 **確認のボタンは押さない**（見本のストーリーで本番の写真を消しにいかない）。出なければ撮らずに抜ける
    func testCapturesKeptStoryRelation() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewKeptStory", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }

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

        let row = app.buttons["photo.storySource"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return }
        var rowPushes = 0
        while !row.isHittable, rowPushes < 4 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            rowPushes += 1
        }
        guard row.isHittable else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "20k-写真の詳細（ストーリーから作った写真）")

        row.tap()
        let kept = app.buttons["story.viewer.keptPhoto"].firstMatch
        guard kept.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "20l-ストーリー（写真にしました）")

        let more = app.buttons["story.viewer.more"].firstMatch
        guard more.waitForExistence(timeout: 5), more.isHittable else { return }
        more.tap()
        let delete = app.buttons["story.menu.delete"].firstMatch
        guard delete.waitForExistence(timeout: 5), delete.isHittable else { return }
        delete.tap()
        guard app.buttons["story.delete.withPhoto"].firstMatch.waitForExistence(timeout: 5) else { return }
        // 写真のいいね・コメントの数を読む間を置く
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "20m-写真にしたストーリーの消す確認")
    }

    /// **写真を撮影スポットに自動で結ぶ（写真の詳細）**（2026-10-31・journey.photo-ios#425）。
    ///
    /// 見本の利用者の写真（マイページの格子）を頭から開き、自動で結ばれた1枚を探す。見つかったら
    /// 写真の裾の「撮影スポット · ◯◯」の札（20g）と、題の下の本人だけの「外す」の札（20h）を撮る。
    /// 🔴 **「違う場所なので外す」は押さない**（本番の写真の行に外した印を書いてしまう）。
    /// 自動で結ばれた写真が無い・表が読めない回は**撮らずに抜ける**（この試験の決まり）
    func testCapturesSpotAutoNotice() {
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

        let photos = app.buttons.matching(identifier: "mypage.photo")
        guard photos.firstMatch.waitForExistence(timeout: 15) else { return }
        let notice = app.descendants(matching: .any).matching(identifier: "photo.spotAuto").firstMatch
        // 頭から 9 枚まで（格子の1画面ぶん）。押せない枚は飛ばす
        for index in 0..<9 {
            let photo = photos.element(boundBy: index)
            guard photo.exists else { break }
            guard photo.isHittable else { continue }
            photo.tap()
            if notice.waitForExistence(timeout: 8) {
                // 写真の裾の札（自動で結んだ撮影スポット）。札の名前と台帳を読み終えるのを少し待つ
                Thread.sleep(forTimeInterval: 3)
                shoot(app, "20g-写真の詳細（自動で結んだ撮影スポットの札）")
                for _ in 0..<3 where !notice.isHittable {
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                    from.press(forDuration: 0.05, thenDragTo: to)
                    Thread.sleep(forTimeInterval: 1)
                }
                shoot(app, "20h-写真の詳細（外すの札・本人だけ）")
                return
            }
            // この1枚は結ばれていない。マイページへ戻って次へ
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { return }
            back.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    /// **投稿の「撮影スポット「◯◯」に結ぶ」**（2026-10-31・journey.photo-ios#425・板 UploadIOS）。
    ///
    /// 見本の1枚（位置なし）の撮影地に「蔵王キツネ村」と打ち、撮影地の欄の下に切り替えが出たら撮る（45e）。
    /// 候補の索引（`spot-match.json`）は本番を読む。**投稿は押さない**。切り替えが出ない回は撮らずに抜ける
    func testCapturesUploadSpotAutoToggle() {
        let app = XCUIApplication()
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
        guard app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 15) else { return }

        let place = app.textFields["upload.place"].firstMatch
        guard place.waitForExistence(timeout: 10) else { return }
        for _ in 0..<3 where !place.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        guard place.isHittable else { return }
        place.tap()
        // 焦点が来てから打つ（来ないまま打つと失敗として記録される・`shootSearchedSpot` と同じ）
        guard waitForKeyboardFocus(place) else { return }
        place.typeText("蔵王キツネ村\n")

        let toggle = app.switches["upload.autoSpot"].firstMatch
        // 索引（約 400KB・圧縮して配られる）を読み終えるまで待つ
        guard toggle.waitForExistence(timeout: 20) else { return }
        for _ in 0..<3 where !toggle.isHittable {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "45e-投稿（撮影スポットに結ぶ）")
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

    /// **自分の写真の ⋯ のピン留め**（資料「説明なしで分かるアプリ」項目9・1.1.85 束H・2026-11-12）。
    /// マイページの長押しだけだったピン留めを ⋯ にも置いた。行は写真の主のプロフィールを読んでから出る。
    /// 押さない（押すと見本の利用者のピンが変わる）。
    ///
    /// 2026-11-12（確かめ役の指摘）: 前は途中の確かめが `guard … else { return }` で、自分の写真が出ない・⋯ に行が無い
    /// 回も緑のまま抜けていた（何も守っていない）。**途中で欠けたら XCTFail で落とす**。プロフィールを読み終えるのを
    /// 固定の3秒で待っていたのもやめ、⋯ を開いて行が出るのを待つ（出なければ閉じて開き直す・合わせて 30 秒まで）
    func testCapturesPhotoMenuPin() {
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
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else {
            return XCTFail("下のタブが出ない（\(tabBar.exists ? tabBar.buttons.count : 0) 個）")
        }
        tabBar.buttons.element(boundBy: 4).tap()

        let myPhoto = app.buttons["mypage.photo"].firstMatch
        guard myPhoto.waitForExistence(timeout: 15) else { return XCTFail("マイページに自分の写真が出ない") }
        if !myPhoto.isHittable {
            app.swipeUp()
            _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: myPhoto)],
                                 timeout: 3)
        }
        guard myPhoto.isHittable else { return XCTFail("自分の写真が押せる所に無い") }
        myPhoto.tap()

        let menu = app.buttons["photo.menu"].firstMatch
        guard menu.waitForExistence(timeout: 10) else { return XCTFail("写真の詳細に ⋯ が無い") }
        // ⋯ を開き、ピン留めの行が出るのを待つ。行は写真の主のプロフィールを読み終えてから出る作りなので、
        // 開いた時にまだ無ければ閉じて開き直す（固定の秒数は待たない）
        let pin = app.buttons["photo.pin"].firstMatch
        let edit = app.buttons["photo.edit"].firstMatch
        let deadline = Date().addingTimeInterval(30)
        var opens = 0
        while Date() < deadline {
            guard menu.isHittable else { return XCTFail("⋯ が押せない") }
            menu.tap()
            opens += 1
            XCTAssertTrue(edit.waitForExistence(timeout: 5), "⋯ を開いても「編集」が無い（自分の写真の ⋯ でない）")
            if pin.waitForExistence(timeout: 5) { break }
            // 行が無いまま開いている ⋯ を閉じる（押さずに外を押す）
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            _ = edit.waitForNonExistence(timeout: 5)
        }
        guard pin.exists else {
            return XCTFail("⋯ を \(opens) 回開いても、30 秒のうちにピン留めの行が出ない（写真の主のプロフィールが読めていない）")
        }
        XCTAssertTrue(pin.label.contains("ピン留め"), "⋯ のピン留めの行の字が違う: \(pin.label)")
        shoot(app, "22d-自分の写真の ⋯（プロフィールの先頭にピン留め）")
    }

    /// **旅をストーリーに**（第9章・1.1.83・`TravelStorySheet`）。自分の写真の ⋯ →「SNS に載せる」→ 上の「ストーリー」
    /// （⋯ の行は増やさない・2026-11-12 秘書室の判断・`SocialShareSheet`）。
    /// 型を払って選ぶ1枚（はじめは切手と消印）と、払った次の型（フィルムの帯）、ステッカーの形を撮る。
    /// 見本の利用者の写真が全体に公開でない・読めないなど、出なければ撮らない（この試験の決まり）
    func testCapturesTravelStory() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        // 前に選んだ型を残さない（はじめの既定＝切手と消印・写真に重ねる から撮る）
        for key in ["kind", "mode", "place", "date"] {
            app.launchArguments += ["-travelStory.\(key)", ""]
        }
        // 「SNS に載せる」の画面ははじめ投稿（4:5）から
        app.launchArguments += ["-socialShare.mode", ""]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()

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
        let social = app.buttons["photo.socialShare"].firstMatch
        guard social.waitForExistence(timeout: 5), social.isHittable else { return }
        social.tap()
        // 写真を読み終えると開く（はじめは投稿）。上の切り替えでストーリーへ
        let story = app.buttons["socialShare.mode.story"].firstMatch
        guard story.waitForExistence(timeout: 20) else { return }
        XCTAssertTrue(app.buttons["signatureShare.share"].firstMatch.exists, "はじめが投稿（今のカードの画面）でない")
        story.tap()

        let share = app.buttons["travelStory.share"].firstMatch
        guard share.waitForExistence(timeout: 15) else { return }
        // 写真を読んで描き終える（主ボタンが押せるようになる）まで待つ
        let ready = NSPredicate(format: "isEnabled == true")
        _ = XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: share)], timeout: 20)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "22c-旅をストーリーに（切手と消印・写真に重ねる）")
        XCTAssertTrue(app.buttons["閉じる"].firstMatch.exists, "ストーリーにの左上に閉じるが無い")

        // 払って次の型（フィルムの帯）へ。払うのが効かなければ › で
        let stage = app.descendants(matching: .any)["travelStory.stage"].firstMatch
        if stage.exists { stage.swipeLeft() }
        Thread.sleep(forTimeInterval: 2)
        let name = app.staticTexts["travelStory.name"].firstMatch
        if name.exists, !(name.label.contains("フィルム")) {
            let next = app.buttons["travelStory.next"].firstMatch
            if next.exists, next.isHittable { next.tap() }
            Thread.sleep(forTimeInterval: 2)
        }
        _ = XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: share)], timeout: 20)
        shoot(app, "22d-旅をストーリーに（フィルムの帯）")

        // 搭乗券のステッカー
        let prev = app.buttons["travelStory.prev"].firstMatch
        for _ in 0..<2 where prev.exists && prev.isEnabled {
            prev.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        let sticker = app.buttons["travelStory.mode.sticker"].firstMatch
        guard sticker.exists, sticker.isHittable else { return }
        sticker.tap()
        _ = XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: share)], timeout: 20)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "22e-旅をストーリーに（搭乗券・ステッカー）")
        XCTAssertTrue(share.label.contains("コピー"), "ステッカーの主ボタンがコピーでない: \(share.label)")
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

    /// **意見を送る**（2026-11-11 札 #546・`FeedbackSheet`）。設定の「意見を送る」の行から開き、
    /// 開いた姿（欄にすぐ書ける・任意の2つは控えめ）と、書いたあと（「送る」が押せる）を撮る。**送りはしない**
    func testCapturesFeedbackSheet() {
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
        let row = app.buttons["settings.feedback"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return }
        var pushes = 0
        while !row.isHittable, pushes < 8 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard row.isHittable else { return }
        row.tap()
        let send = app.buttons["feedback.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "設定の「意見を送る」から、意見のシートが開かない")
        guard send.exists else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "02g-意見を送る")
        let field = app.textViews["feedback.text"].firstMatch.exists
            ? app.textViews["feedback.text"].firstMatch : app.textFields["feedback.text"].firstMatch
        if field.exists {
            field.typeText("地図の画面がとても使いやすいです。")
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "02h-意見を送る（書いたあと）")
        }
    }

    /// **設定から開いた「新しくなったこと」の履歴**（2026-10-18・`WhatsNewView(mode: .history)`）。
    ///
    /// 入口は設定の「新しくなったこと」の行（`settings.whatsNew`）。設定は全部の版を `mode: .history` で渡すので、
    /// 2枚目（「これまでのお知らせ」と版の区切りの見出し）まで撮れる。シートが開いたのに履歴が無ければ落とす
    /// プロフィールの QR（札 #545・2026-11-12）: マイページの名前の横の印 → 1枚の画面で「自分の QR」と「読み取る」。
    /// 「QR コードを更新」→ 確かめ → 新しい QR と知らせも撮る（見本の通信 `PreviewBackend` が合図を替える）。
    /// シミュレータにはカメラが無いので、読み取るは「この端末ではカメラを使えません」の状態を撮る
    func testCapturesProfileQR() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        // QR の中身はサーバーの口（GET /user/qr・POST /user/qr/rotate）が作る。見本の通信（`PreviewBackend`）で答える。
        // 無いと鍵が無く `notAuthenticated` で QR が出ない（run 1144 で事実を取った・2026-11-12）
        app.launchArguments += ["-JPPreviewLocalBackend", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return XCTFail("下の札が出ない") }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15) else { return }
        let entry = app.buttons["mypage.qr"].firstMatch
        guard entry.waitForExistence(timeout: 5) else { return XCTFail("マイページの名前の横に QR の印が無い") }
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44, "QR の印の当たりが 44pt 未満")
        XCTAssertGreaterThanOrEqual(entry.frame.width, 44, "QR の印の当たりが 44pt 未満")
        shoot(app, "120-マイページ（名前の横の QR）")
        entry.tap()
        let code = app.descendants(matching: .any)["profileQR.code"].firstMatch
        guard code.waitForExistence(timeout: 10) else {
            // 事実を取る（2026-11-12）: 読み込み中のままか、作れなかったか（作れなかった理由は読み上げの値）
            let failed = app.descendants(matching: .any)["profileQR.failed"].firstMatch
            let loading = app.descendants(matching: .any)["profileQR.loading"].firstMatch
            // 入れ物に付けた識別子は中の要素に移る（run 1138 で理由の要素が見つからなかった）ので、同じ識別子の全部の字を読む
            let labels = app.descendants(matching: .any).matching(identifier: "profileQR.failed")
                .allElementsBoundByIndex.map(\.label)
            let reasons = app.descendants(matching: .any).matching(identifier: "profileQR.failureReason")
                .allElementsBoundByIndex.map(\.label)
            return XCTFail("QR の画面に自分の QR が出ない（読み込み中: \(loading.exists)・失敗: \(failed.exists)"
                           + "・字: \(labels)・理由: \(reasons)）")
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "120a-プロフィールの QR（自分の QR）")
        // QR の下の「QR コードを更新」→ 確かめ → 新しい QR と知らせ（2026-11-12 札 #545・見本の通信が合図を替える）
        let renew = app.buttons["profileQR.renew"].firstMatch
        guard renew.waitForExistence(timeout: 5) else { return XCTFail("QR の下に「QR コードを更新」が無い") }
        XCTAssertGreaterThanOrEqual(renew.frame.height, 44, "「QR コードを更新」が 44pt 未満")
        renew.tap()
        let confirm = app.buttons["更新する"].firstMatch
        guard confirm.waitForExistence(timeout: 5) else { return XCTFail("更新の確かめが出ない") }
        Thread.sleep(forTimeInterval: 0.5)
        shoot(app, "120c-プロフィールの QR（更新の確かめ）")
        confirm.tap()
        let toast = app.descendants(matching: .any)["toast"].firstMatch
        guard toast.waitForExistence(timeout: 10) else { return XCTFail("更新したのに知らせが出ない") }
        XCTAssertTrue(toast.label.contains("新しい QR コードにしました") || app.staticTexts["新しい QR コードにしました"].exists,
                      "知らせの言葉が違う: \(toast.label)")
        shoot(app, "120d-プロフィールの QR（新しい QR）")
        let scan = app.buttons["profileQR.mode.scan"].firstMatch
        guard scan.waitForExistence(timeout: 5) else { return XCTFail("読み取るへの切り替えが無い") }
        XCTAssertGreaterThanOrEqual(scan.frame.height, 44, "切り替えが 44pt 未満")
        scan.tap()
        guard app.descendants(matching: .any)["profileQR.camera"].firstMatch.waitForExistence(timeout: 10) else {
            return XCTFail("読み取るに切り替えてもカメラの枠が出ない")
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "120b-プロフィールの QR（読み取る）")
    }

    /// **名前の横のバッジの入口**（2026-11-12 owner 案 A「メダル案 A だな」）: メダルを持っていて名前の横に何も
    /// 飾っていない人だけ、名前の横に点線の丸（見た目 22・当たり 44）。押すと名前の横の画面（選ぶ画面）。
    /// 並びは 名前 → 印 → 丸 → QR → 編集。**長い名前・大きい文字でも1行に収める**（名前を「…」で切り、ほかは縮めない）。
    ///
    /// 見本の利用者の持ち物は `-JPPreviewBadges`、飾っていないことは `-JPPreviewDisplayBadge none`（持っていない鍵＝出ない）、
    /// メダルが無いことは `-JPPreviewBadges none:1`（絵の無い鍵だけ）、長い名前は `-JPPreviewDisplayName` で渡す
    func testCapturesMyPageNameSlot() {
        let medals = ["-JPPreviewBadges", "prefectures:2,earlyUser:1"]
        let notShown = ["-JPPreviewDisplayBadge", "none"]
        let longName = ["-JPPreviewDisplayName", "とても長い名前の旅人さんのアカウント名です"]
        struct Case { let extra: [String]; let tag: String; let slot: Bool; let shot: String? }
        let cases = [
            Case(extra: medals + notShown, tag: "飾っていない人", slot: true,
                 shot: "121-マイページ（名前の横の点線の丸）"),
            Case(extra: medals + notShown + longName + ["-JPPreviewPro", "YES"], tag: "長い名前・Pro", slot: true,
                 shot: "121a-マイページ（名前の横の点線の丸・長い名前と Pro）"),
            Case(extra: medals + notShown + longName + Self.largeText, tag: "長い名前・大きい文字", slot: true,
                 shot: "121b-マイページ（名前の横の点線の丸・長い名前と大きい文字）"),
            Case(extra: medals + ["-JPPreviewDisplayBadge", "prefectures"], tag: "飾っている人", slot: false, shot: nil),
            Case(extra: ["-JPPreviewBadges", "none:1"] + notShown, tag: "メダルの無い人", slot: false, shot: nil),
        ]
        for c in cases {
            // 名前の行の当たりの張り出しを値で出す（`mypage.name.probe`・2026-11-13 確かめ役）
            let app = launchProfileLooks(c.extra + ["-JPPreviewLayoutProbe", "YES"])
            defer { app.terminate() }
            let tabBar = app.tabBars.firstMatch
            guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return XCTFail("\(c.tag): 下の札が出ない") }
            tabBar.buttons.element(boundBy: 4).tap()
            let edit = app.buttons["mypage.edit"].firstMatch
            guard edit.waitForExistence(timeout: 20) else { return XCTFail("\(c.tag): マイページの見出しが出ない") }
            // 名前の横の印の絵は画面の処理の外で縮めて作る
            Thread.sleep(forTimeInterval: 3)
            let slot = app.buttons["mypage.nameSlot"].firstMatch
            guard c.slot else {
                XCTAssertFalse(slot.exists, "\(c.tag): 点線の丸を出さないはずが出ている")
                continue
            }
            guard slot.exists else { return XCTFail("\(c.tag): 名前の横に点線の丸が無い") }
            XCTAssertEqual(slot.label, "名前の横にバッジを飾る", "\(c.tag): 読み上げが違う")
            // 位置が端数の所に来ると、44 が 43.99999999999997 と返る（Mac run 1166 の「長い名前・Pro」で事実を取った）。
            // 小数の誤差だけ許す
            XCTAssertGreaterThanOrEqual(slot.frame.width, 44 - 0.01, "\(c.tag): 丸の当たりが 44pt 未満")
            XCTAssertGreaterThanOrEqual(slot.frame.height, 44 - 0.01, "\(c.tag): 丸の当たりが 44pt 未満")
            // 1行に収まる: 名前の行 → 丸 → QR → 編集が横に並び、重ならず、右端（16）から出ない
            let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
            let qr = app.buttons["mypage.qr"].firstMatch
            let width = app.windows.firstMatch.frame.width
            let rows = "name=\(nameLine.frame) slot=\(slot.frame) qr=\(qr.frame) edit=\(edit.frame) width=\(width)"
            let note = XCTAttachment(string: rows)
            note.name = "121-名前の段の並び（\(c.tag)）"
            note.lifetime = .keepAlways
            add(note)
            // 名前の行と下の「@ユーザー名」の行の frame、当たりの張り出し（2026-11-13 確かめ役: 名前が折り返したとき重なるか）
            let handle = app.descendants(matching: .any)["mypage.handleLine"].firstMatch
            let nameProbe = app.descendants(matching: .any)["mypage.name.probe"].firstMatch
            print("measured mypageName tag=\(c.tag) name=\(nameLine.frame) handle=\(handle.exists ? "\(handle.frame)" : "none") "
                  + "probe=\(nameProbe.exists ? (nameProbe.value as? String ?? "") : "none")")
            // 名前の行の frame は当たりの範囲（Mac run 1213: 1行で高さ 44＝1行 36＋上下の張り出し 4）。
            // 折り返しても、下の「@ユーザー名」の行に掛からない（run 1213: 3件とも名前の下端＝下の行の上端）
            if handle.exists {
                XCTAssertLessThanOrEqual(nameLine.frame.maxY, handle.frame.minY + 0.5,
                                         "\(c.tag): 名前の当たりが下の行に重なる（\(rows)・handle=\(handle.frame)）")
            }
            XCTAssertTrue(qr.exists, "\(c.tag): QR の印が無い")
            XCTAssertGreaterThan(nameLine.frame.width, 0, "\(c.tag): 名前の行が潰れた（\(rows)）")
            XCTAssertLessThan(abs(slot.frame.midY - nameLine.frame.midY), 12, "\(c.tag): 丸が名前の段にない（\(rows)）")
            XCTAssertLessThan(abs(qr.frame.midY - nameLine.frame.midY), 12, "\(c.tag): QR が名前の段にない（\(rows)）")
            XCTAssertGreaterThan(slot.frame.minX, nameLine.frame.minX, "\(c.tag): 丸が名前の右でない（\(rows)）")
            XCTAssertLessThanOrEqual(slot.frame.maxX, qr.frame.minX + 1, "\(c.tag): 丸と QR の当たりが重なる（\(rows)）")
            XCTAssertLessThanOrEqual(qr.frame.maxX, edit.frame.minX + 1, "\(c.tag): QR と編集が重なる（\(rows)）")
            XCTAssertLessThanOrEqual(edit.frame.maxX, width - 16 + 1, "\(c.tag): 編集が右端から出た（\(rows)）")
            if let shot = c.shot { shoot(app, shot) }
            // 押すと名前の行と同じ選ぶ画面（決めずに閉じる）
            guard slot.isHittable else { return XCTFail("\(c.tag): 丸が押せない（\(rows)）") }
            slot.tap()
            XCTAssertTrue(app.descendants(matching: .any)["nameSide.save"].firstMatch.waitForExistence(timeout: 10),
                          "\(c.tag): 丸を押しても選ぶ画面が出ない")
        }
    }

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
        // 2026-11-10 判断: 待ちを 5 → 15 秒。分けて流した run 42838160142（組 2）で、押したあと「説明が残っているか」を
        // 1 回調べるだけで 4.07 秒かかり（t=24.73→28.80）、5 秒の待ちが切れた。同じ枝の run 42856953207 では 0.32 秒で閉じていた。
        // 調べる速さは Mac によって 10 倍以上違うので、実測の遅い方の約 3.7 倍にする
        let closed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: allow)], timeout: 15)
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

    /// **すれちがいの設定の「届き方」**（2026-11-10 owner「すれちがったら即時交換されて欲しい」）: 既定はすぐ届く。
    /// 「夕方にまとめて受け取る」の行が出て、既定でオフになっているかを撮る。画面まで行けなければ撮らずに抜ける。
    /// **出たのに行がオンのまま・44pt 未満なら落とす**
    func testCapturesPassSettingsDelivery() throws {
        guard let (app, _) = openPassPick(stopAtSettings: true) else { return }
        let toggle = app.switches["pass.settings.evening"].firstMatch
        guard toggle.waitForExistence(timeout: 10) else { return }
        var pushes = 0
        while !toggle.isHittable, pushes < 4 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44, "「夕方にまとめて受け取る」の行が 44pt 未満")
        XCTAssertEqual(toggle.value as? String, "0", "既定が「夕方にまとめて」になっている（既定はすぐ届く）")
        shoot(app, "85-すれちがいの設定（届き方）")
    }

    /// **すれちがい帳の頭の行と空の状態**（札 #519・提案「旅の道具の置き場」第5版）。入口は「新しくなったこと」の
    /// 1.1.79 の帳の項目（題で探す・行き先 passBook）——シートを閉じてホームに帳を積む道も同時に見る。
    ///
    /// 1. 帳（オフ・0 枚）: 頭の行が「すれちがい乗車券はオフです」、主ボタン「説明を読んでオンにする」（`passBook.emptyTurnOn`）
    /// 2. 主ボタン → 設定を積み、はじめから「オンにする」前の説明（`pass.intro.confirm`）が出る
    /// 3. 「オンにする」→ 乗車券を選ぶ画面から帳へ戻ると、頭の行が「オンです · 乗車券を選ぶまで…」、主ボタンは出ない
    ///
    /// 「新しくなったこと」が出なければ撮らずに抜ける。**出たのに帳が積まれない・下の札がホームでない・頭の行が
    /// オフと言わない・主ボタンが無い／44pt 未満・説明が出なければ落とす**（仕様の「確かめていない」2つをここで見る）
    func testCapturesPassBookStatus() {
        let app = XCUIApplication()
        // 更新した人として起動する（規約に同意済み・前に見た版が古い。`testCapturesWhatsNew` と同じ）
        app.launchArguments += ["-legal.consent.version", "1"]
        app.launchArguments += ["-whatsNew.seenVersion", "0.0.1"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 5) { agree.tap() }
        // 2026-11-10 判断: 項目は位置（`whatsNew.item.0`）ではなく題で探す。1.1.79 の先頭に DM の項目を足したら、
        // 位置で探していたこの試験が run 42872738853（3 回目）で「先頭の項目が帳の項目でない」と落ちた
        let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'whatsNew.item.' AND label CONTAINS %@",
                                                    "すれちがい帳で、乗車券の状態が分かる")).firstMatch
        guard item.waitForExistence(timeout: 20) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "83a-新しくなったこと（1.1.79）")
        item.tap()

        let status = app.buttons["passBook.status"].firstMatch
        guard status.waitForExistence(timeout: 10) else {
            return XCTFail("「新しくなったこと」の帳の項目を押しても、ホームにすれちがい帳が積まれない")
        }
        XCTAssertFalse(app.buttons["whatsNew.close"].firstMatch.exists, "シートが閉じきっていない")
        let home = app.tabBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(home.isSelected, "帳を積んだあと、下の札がホームでない")
        XCTAssertEqual(status.label, "すれちがい乗車券はオフです")
        XCTAssertEqual(status.value as? String, "オンにすると、近くにいたアプリの人と乗車券のカードを交換します")
        XCTAssertGreaterThanOrEqual(status.frame.height, 43.9, "頭の行が 44pt 未満")
        let turnOn = app.buttons["passBook.emptyTurnOn"].firstMatch
        XCTAssertTrue(turnOn.waitForExistence(timeout: 10), "オフで 0 枚なのに「説明を読んでオンにする」が無い")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "83b-すれちがい帳（オフ・まだ空）")
        guard turnOn.exists, turnOn.isHittable else { return XCTFail("「説明を読んでオンにする」を押せない") }
        XCTAssertEqual(turnOn.label, "説明を読んでオンにする")
        XCTAssertGreaterThanOrEqual(turnOn.frame.height, 43.9, "「説明を読んでオンにする」が 44pt 未満")
        turnOn.tap()

        let confirm = app.buttons["pass.intro.confirm"].firstMatch
        guard confirm.waitForExistence(timeout: 10) else {
            return XCTFail("帳の主ボタンで設定を積んでも、「オンにする」前の説明が出ない")
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "83c-すれちがい帳 → オンにする前の説明")
        guard confirm.isHittable else { return }
        confirm.tap()
        // Bluetooth の許可の確認が出たら許す（シミュレータでは出ないこともある）
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["許可", "OK", "Allow"] {
            let button = springboard.alerts.buttons[title].firstMatch
            if button.waitForExistence(timeout: 2) { button.tap(); break }
        }
        // 乗車券を選んでいないので、選ぶ画面へ進む。帳まで戻る（設定 → 帳）
        Thread.sleep(forTimeInterval: 2)
        var backs = 0
        while !(status.exists && status.isHittable), backs < 3 {
            goBack(app)
            Thread.sleep(forTimeInterval: 1)
            backs += 1
        }
        guard status.exists, status.isHittable else { return }
        XCTAssertEqual(status.label, "すれちがい乗車券はオンです")
        XCTAssertEqual(status.value as? String, "乗車券を選ぶまで、交換は止まっています")
        XCTAssertFalse(app.buttons["passBook.emptyTurnOn"].firstMatch.exists, "オンで 0 枚なのに主ボタンが出る")
        shoot(app, "83d-すれちがい帳（オン・乗車券を選んでいない）")
    }

    /// **設定から積まれたすれちがい帳の頭の行は、積まずに戻る**（札 #519・`PassBookView.fromSettings`）。
    /// 設定 → すれちがい → 帳 → 頭の行で、設定（`pass.settings.toggle`）に戻り、帳が残っていないこと。
    /// 画面まで行けなければ抜ける。**戻らずに設定を積み直したら落とす**
    func testCapturesPassBookStatusFromSettings() {
        guard let (app, _) = openPassPick(stopAtSettings: true) else { return }
        let toggle = app.switches["pass.settings.toggle"].firstMatch
        guard toggle.waitForExistence(timeout: 10) else { return }
        let bookRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "すれちがい帳")).firstMatch
        var pushes = 0
        while !(bookRow.exists && bookRow.isHittable), pushes < 6 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard bookRow.exists, bookRow.isHittable else { return }
        bookRow.tap()
        let status = app.buttons["passBook.status"].firstMatch
        guard status.waitForExistence(timeout: 10) else { return XCTFail("設定から開いた帳に頭の行が無い") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "83e-すれちがい帳（設定から）")
        status.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "設定から来た帳の頭の行で、設定に戻らない")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(status.exists, "設定から来た帳の頭の行で、設定を積み直した（帳が残っている）")
    }

    /// **大きい文字で、行動の札（行きたい・旅行プランに入れる・経路）の名前が切れないか**（2026-11-13 確かめ役の指摘）。
    ///
    /// 字の大きさを1段上（XL）とアクセシビリティの大きさ（AccessibilityXL）にして、観光スポットの頁（マップ →「スポット」の
    /// 一覧の先頭）と写真の詳細（ホームの先頭の写真・行き先の段）を撮る。字の切れは画面の木から取れないので、見えない要素
    /// （`spot.official.fit`・`photo.trip.fit`・`ActionRowFitProbe`）の「名前の要る幅・札1つの幅・入るか」をログに出す
    /// （`measured tripActions` の行）。**入らなければ落とす**。画面が出なければ撮らずに抜ける（この試験の決まり）
    func testCapturesTripActionsLargeText() {
        for (category, tag) in [("UICTContentSizeCategoryXL", "XL"), ("UICTContentSizeCategoryAccessibilityXL", "AXL")] {
            let app = XCUIApplication()
            app.launchArguments += ["-legal.consent.version", "0"]
            app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
            app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category, "-JPPreviewLayoutProbe", "YES"]
            app.launch()
            defer { app.terminate() }
            let agree = app.buttons["legal.agree"]
            if agree.waitForExistence(timeout: 30) { agree.tap() }
            let tabBar = app.tabBars.firstMatch
            guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 3 else { continue }

            // 観光スポットの頁
            tabBar.buttons.element(boundBy: 3).tap()
            let spots = app.buttons["map.mode.spots"].firstMatch
            if spots.waitForExistence(timeout: 15) {
                spots.tap()
                let row = app.buttons.matching(identifier: "map.spotRow").firstMatch
                if row.waitForExistence(timeout: 15), row.isHittable {
                    row.tap()
                    let fit = app.descendants(matching: .any).matching(identifier: "spot.official.fit").firstMatch
                    if fit.waitForExistence(timeout: 10) {
                        Thread.sleep(forTimeInterval: 2)
                        let value = fit.value as? String ?? ""
                        let trip = app.buttons["spot.official.trip"].firstMatch
                        print("measured tripActions screen=spot size=\(tag) \(value) tripButton=\(trip.frame)")
                        shoot(app, "13x-撮影スポット（行動の札・大きい文字 \(tag)）")
                        XCTAssertTrue(value.hasSuffix("fits=yes"), "観光スポットの頁の札に名前が入らない（\(tag)）: \(value)")
                    }
                    goBack(app)
                }
            }

            // 写真の詳細（ホームの先頭の写真。行き先の段の無い写真なら撮らない）
            tabBar.buttons.element(boundBy: 0).tap()
            let photo = app.buttons["feed.photo"].firstMatch
            var pushes = 0
            while !(photo.waitForExistence(timeout: 2) && photo.isHittable), pushes < 8 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
                pushes += 1
            }
            guard photo.exists, photo.isHittable else { continue }
            photo.tap()
            let wish = app.buttons["photo.trip.wish"].firstMatch
            guard wish.waitForExistence(timeout: 10) else { continue }
            var tripPushes = 0
            while !wish.isHittable, tripPushes < 6 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
                Thread.sleep(forTimeInterval: 1)
                tripPushes += 1
            }
            let fit = app.descendants(matching: .any).matching(identifier: "photo.trip.fit").firstMatch
            guard wish.isHittable, fit.exists else { continue }
            Thread.sleep(forTimeInterval: 1)
            let value = fit.value as? String ?? ""
            let add = app.buttons["photo.trip.add"].firstMatch
            print("measured tripActions screen=photo size=\(tag) \(value) tripButton=\(add.frame)")
            shoot(app, "20x-写真の詳細（行き先の札・大きい文字 \(tag)）")
            XCTAssertTrue(value.hasSuffix("fits=yes"), "写真の詳細の札に名前が入らない（\(tag)）: \(value)")
        }
    }

    /// **撮影スポットの頁の「構図一覧を見る ›」**（札 #519）。マップ →「スポット」の一覧の行から撮影スポットを開き、
    /// 構図のヒントの下のリンク（`spot.compositionCatalog`）が出るまで送って撮る。押して構図一覧が積まれ、戻れることも見る。
    /// 先頭から 3 件までの撮影スポットで探し、ヒントのある所が無ければ撮らずに抜ける。
    /// **出たのに 44pt 未満・押しても構図一覧が出なければ落とす**
    func testCapturesSpotCompositionLink() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 3 else { return }
        tabBar.buttons.element(boundBy: 3).tap()
        let spots = app.buttons["map.mode.spots"].firstMatch
        guard spots.waitForExistence(timeout: 15) else { return }
        spots.tap()
        let rows = app.buttons.matching(identifier: "map.spotRow")
        guard rows.firstMatch.waitForExistence(timeout: 15) else { return }
        for index in 0..<min(3, rows.count) {
            let row = rows.element(boundBy: index)
            guard row.exists, row.isHittable else { continue }
            row.tap()
            Thread.sleep(forTimeInterval: 3)
            let link = app.buttons["spot.compositionCatalog"].firstMatch
            var swipes = 0
            while !(link.exists && link.isHittable), swipes < 8 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                swipes += 1
            }
            guard link.exists, link.isHittable else {
                goBack(app)
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            XCTAssertEqual(link.label, "構図一覧を見る")
            XCTAssertGreaterThanOrEqual(link.frame.height, 43.9, "「構図一覧を見る ›」の当たりが 44pt 未満")
            shoot(app, "13h-撮影スポット（構図一覧を見る）")
            link.tap()
            let catalog = app.buttons["composition.catalog.thirds"].firstMatch
            XCTAssertTrue(catalog.waitForExistence(timeout: 10), "「構図一覧を見る ›」を押しても構図一覧が出ない")
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "13i-撮影スポット → 構図一覧")
            goBack(app)
            XCTAssertTrue(link.waitForExistence(timeout: 5), "構図一覧から撮影スポットに戻れない")
            return
        }
    }

    /// わたしの乗車券（マイページ → 設定 → すれちがい → わたしの乗車券）まで進めて、回る見本を返す。
    /// 画面まで行けなければ nil（撮らずに抜ける）。`pro` は見本の利用者を Pro の姿にする（`-JPPreviewPro`）
    /// `stopAtSettings` なら、すれちがいの設定を開いたところで返す（2つ目は乗車券の行）
    private func openPassPick(pro: Bool = false, extra: [String] = [],
                              stopAtSettings: Bool = false) -> (XCUIApplication, XCUIElement)? {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewPass", "YES"]
        if pro { app.launchArguments += ["-JPPreviewPro", "YES"] }
        app.launchArguments += extra
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
        if stopAtSettings { return (app, app.buttons["pass.settings.card"].firstMatch) }
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

    /// **自分のカード（乗車券の見本）を回す**（2026-10-16 owner の頼み）: マイページ → 設定 → すれちがい →
    /// わたしの乗車券。見本は届いたカードと同じ回る部品（`PassSpinCard`）。起動の鍵（`-JPPreviewPass`）で区間を
    /// 「東京 → フランス」・ひとことつきにしてあるので、表（字数の違う発・着がそろうか）と裏を撮る。
    ///
    /// 画面まで行けなければ撮らずに抜ける。**出たのに「裏を見る」が無い・44pt 未満・押しても裏にならない・
    /// 横に回しても裏にならなければ落とす**
    func testCapturesPassOwnCard() {
        guard let (app, card) = openPassPick() else { return }
        Thread.sleep(forTimeInterval: 3)
        // 呼び名は「わたしの乗車券」（2026-10-17 owner）
        XCTAssertTrue(app.navigationBars["わたしの乗車券"].firstMatch.exists, "選ぶ画面の題が「わたしの乗車券」でない")
        // 表はマルス券（2026-10-17）: 「東京発、フランス着」と読む・「乗車券」の名
        XCTAssertTrue(card.label.contains("発、") && card.label.contains("着"),
                      "見本の区間が「〇〇発、〇〇着」と読めない（\(card.label)）")
        XCTAssertTrue(card.label.contains("乗車券"), "見本の表に「乗車券」が無い（\(card.label)）")
        // 見本の日付・区間・回数は空。**空の欄は出さない**（2026-10-21・前は「—」を出し、読み上げは「なし」）
        XCTAssertFalse(card.label.contains("日付 なし"), "空の欄を出している（\(card.label)）")
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

    /// **探すの「機材から探す」の札3枚**（2026-10-30 owner 採用・#419）。発見の顔のいちばん下の段なので、
    /// 札（`search.gear.wide` など）が押せる所まで少しずつ送ってから撮る。色の丸の段も同じ絵に入ることが多い。
    /// **別の試験にしてある**（一巡の「11-探す」は上のままの絵）。出なければ撮らない（この試験の決まり）
    func testCapturesSearchGearCards() {
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

        // 写真の無い区分は札にしないので、どれか1枚が出ればよい
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.gear.'")).firstMatch
        guard card.waitForExistence(timeout: 20) else { return }
        var swipes = 0
        while !card.isHittable, swipes < 10 {
            app.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard card.isHittable else { return }
        // 札の下に余白が出るまでもう少し送る（段の下端で切れた絵にしない）
        app.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 2)
        guard card.isHittable else { return }
        shoot(app, "11e-探す（機材の札・色の丸）")
    }

    /// **画面の状態とそろえ**（デザインの案 第2章・1.1.83・2026-11-12）。
    ///
    /// 1. 電波なし（`-JPPreviewOffline YES`・Debug のみ。**通信は止めない**ので、読めた写真を「前に見た写真」として
    ///    出した形）: ホームの上の帯・探すの上の帯・地図の上のガラスの帯
    /// 2. タグ・色・機材の写真の格子（TagPhotos v2: 3 列・すき間 2・正方形・先頭 300）——探すの機材の札から開く
    ///
    /// 帯の有無は道しるべ（`home.offline.band`・`search.offline.retry`・`map.stateBand`）で数え、ログに出す。
    /// **別の試験にしてある**（一巡の絵に電波なしを混ぜない）。出なければ撮らない（この試験の決まり）
    func testCapturesStatesOfflineBandsAndTagGrid() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewOffline", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 3 else { return }

        // 1a. ホーム: 前に見た写真の上に帯
        let homeBand = app.descendants(matching: .any)["home.offline.band"].firstMatch
        let homeFound = homeBand.waitForExistence(timeout: 30)
        print("states.offline home.band=\(homeFound)")
        if homeFound {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "11s-ホーム（電波なし・前に見た写真の上に帯）")
        }

        // 1b. 探す: 上に帯
        tabBar.buttons.element(boundBy: 1).tap()
        let searchRetry = app.buttons["search.offline.retry"].firstMatch
        let searchFound = searchRetry.waitForExistence(timeout: 20)
        print("states.offline search.band=\(searchFound)")
        if searchFound {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "11t-探す（電波なし・上に帯）")
        }

        // 2. 機材の札 → タグ・色・機材の写真の格子（v2）
        let gear = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.gear.'")).firstMatch
        if gear.waitForExistence(timeout: 20) {
            var swipes = 0
            while !gear.isHittable, swipes < 10 {
                app.swipeUp(velocity: .slow)
                Thread.sleep(forTimeInterval: 1)
                swipes += 1
            }
            if gear.isHittable {
                gear.tap()
                // 写真が描かれるのを待つ（枠だけの絵を「壊れている」と読み違えない）
                Thread.sleep(forTimeInterval: 4)
                shoot(app, "11u-機材の写真（TagPhotos v2 の格子）")
                goBack(app)
            }
        }

        // 1c. 地図: ガラスの帯。いま出している帯・札の種類を `map.stateProbe` の値で記録する
        // （2026-11-12: run 1117 で帯が出なかった訳を数で取る）。時間を追って5回読む
        tabBar.buttons.element(boundBy: 3).tap()
        let probe = app.descendants(matching: .any)["map.stateProbe"].firstMatch
        let mapBand = app.descendants(matching: .any)["map.stateBand"].firstMatch
        _ = probe.waitForExistence(timeout: 15)
        for i in 0..<5 {
            Thread.sleep(forTimeInterval: i == 0 ? 1 : 4)
            print("states.offline map.probe[\(i)] band=\(mapBand.exists) \((probe.value as? String) ?? "-")")
        }
        let mapFound = mapBand.waitForExistence(timeout: 10)
        print("states.offline map.band=\(mapFound)")
        let probeNote = XCTAttachment(string: (probe.value as? String) ?? "-")
        probeNote.name = "13h-地図の帯の記録"
        probeNote.lifetime = .keepAlways
        add(probeNote)
        Thread.sleep(forTimeInterval: 2)
        shoot(app, mapFound ? "13h-マップ（電波なし・ガラスの帯）" : "13h-マップ（電波なし・帯の無い回）")
    }

    /// **探すの「撮影スポット」の段と、そこから開く一覧**（札 #524・2026-11-11）。
    ///
    /// 1. 段（地方のチップ＋県の札の横1列）を撮り、**段の高さを数で取る**（`search.spotIndex` の枠）
    /// 2. 別の地方のチップを押して撮り、**高さが変わらないこと**を確かめる（owner「縦長になる」への答え）
    /// 3. 県の札を押した先（県の一覧・上に探す欄）を撮る
    /// 4. 戻って「すべて見る」の先（全国の一覧・探す欄と地方へ跳ぶチップ）を撮り、欄に字を入れて絞った絵も撮る
    ///
    /// 高さはログに `spotIndex.height before=… after=…` で出す。**別の試験にしてある**（一巡の「11-探す」は上のまま）。
    /// 段が出なければ撮らない（この試験の決まり）——ただし段が出て高さが違えば落とす
    func testCapturesSearchSpotIndex() {
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

        // 段（地方のチップと県の札の入れ物）。索引が届くまで待つ
        let strip = app.otherElements["search.spotIndex"].firstMatch
        guard strip.waitForExistence(timeout: 30) else { return }
        let firstCard = app.buttons.matching(identifier: "search.spotIndex.prefecture").firstMatch
        var swipes = 0
        while !firstCard.isHittable, swipes < 6 {
            app.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard firstCard.isHittable else { return }
        // 札の写真が描かれるのを待つ（枠だけの絵を「壊れている」と読み違えない）
        Thread.sleep(forTimeInterval: 3)
        let before = strip.frame.height
        shoot(app, "11f-探す（撮影スポットの段）")

        // 選んでいない地方のチップで、いま押せるもの
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.spotIndex.region.'"))
        var other: XCUIElement?
        for i in 0..<chips.count {
            let chip = chips.element(boundBy: i)
            if chip.isHittable, !chip.isSelected { other = chip; break }
        }
        guard let other else { return }
        other.tap()
        Thread.sleep(forTimeInterval: 3)
        let after = strip.frame.height
        print("spotIndex.height before=\(before) after=\(after)")
        XCTAssertEqual(before, after, accuracy: 0.5, "地方を替えたら段の高さが変わった（\(before) → \(after)）")
        shoot(app, "11g-探す（撮影スポットの段・地方を替えた）")

        // 県の札 → 県の一覧（上に探す欄）
        let card = app.buttons.matching(identifier: "search.spotIndex.prefecture").firstMatch
        guard card.waitForExistence(timeout: 5), card.isHittable else { return }
        card.tap()
        guard app.textFields["spotIndex.field"].waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "11h-撮影スポットの一覧（県）")
        goBack(app)

        // 「すべて見る」→ 全国の一覧（探す欄・地方へ跳ぶチップ）
        let all = app.buttons["search.spotIndex.all"].firstMatch
        guard all.waitForExistence(timeout: 10) else { return }
        if !all.isHittable { app.swipeDown(velocity: .slow); Thread.sleep(forTimeInterval: 1) }
        guard all.isHittable else { return }
        all.tap()
        let field = app.textFields["spotIndex.field"].firstMatch
        guard field.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "11i-撮影スポットの一覧（全国）")

        // 地方へ跳ぶ。**まだ描いていない県**へ届くかを見るため、押せるチップのうちいちばん後ろ（南）を押す。
        // チップの値は跳ぶ先の見出しの字（`SpotPrefectureIndex.Jump.targetTitle`）。着いたら見出しが画面に出ている
        let jumps = app.buttons.matching(identifier: "spotIndex.jump")
        if jumps.count > 1 {
            jumps.element(boundBy: 0).swipeLeft()
            Thread.sleep(forTimeInterval: 1)
            var jump: XCUIElement?
            for i in stride(from: jumps.count - 1, through: 1, by: -1) where jumps.element(boundBy: i).isHittable {
                jump = jumps.element(boundBy: i)
                break
            }
            if let jump, let target = jump.value as? String, !target.isEmpty {
                let heading = app.scrollViews["spotIndex.list"].staticTexts[target].firstMatch
                print("spotIndex.jump target=\(target) visibleBefore=\(heading.exists && heading.isHittable)")
                jump.tap()
                Thread.sleep(forTimeInterval: 2)
                XCTAssertTrue(heading.waitForExistence(timeout: 5) && heading.isHittable,
                              "地方のチップで「\(target)」の見出しへ跳べていない")
                shoot(app, "11j-撮影スポットの一覧（全国・地方へ跳んだ）")
            }
        }

        // 探す欄で絞る（名前・別名に当てる）
        field.tap()
        field.typeText("寺")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "11k-撮影スポットの一覧（全国・「寺」で絞った）")
    }

    /// **探すの「撮影スポット」の段の地図**（2026-11-11 owner「iOS 側にもこの機能欲しい」）。
    ///
    /// 1. 「写真」の段ぜんたい（`search.spotIndex.block`）の高さを取り、「地図」に替えて**同じ高さか**を数で確かめる
    /// 2. 地図の右上（北海道）をひと押しして、右の札が北海道になったことを確かめて撮る
    /// 3. 長押し（0.6 秒）してから南西へなぞって離し、別の地方に替わったことを撮る
    /// 4. 札の「すべて見る」→ その地方の撮影スポットの一覧を撮る
    ///
    /// 高さはログに `spotMap.height photos=… map=…`。段が出なければ撮らない（この試験の決まり）
    func testCapturesSearchSpotMap() {
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

        let block = app.otherElements["search.spotIndex.block"].firstMatch
        guard block.waitForExistence(timeout: 30) else { return }
        let mapTab = app.buttons["search.spotIndex.mode.map"].firstMatch
        guard mapTab.waitForExistence(timeout: 5) else { return }
        // 段の下の端まで見えるように送る（札の行が押せるまで）
        let firstCard = app.buttons.matching(identifier: "search.spotIndex.prefecture").firstMatch
        var swipes = 0
        while !(mapTab.isHittable && firstCard.isHittable), swipes < 6 {
            app.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard mapTab.isHittable, firstCard.isHittable else { return }
        Thread.sleep(forTimeInterval: 2)
        let photosHeight = block.frame.height

        mapTab.tap()
        // 型を問わずに探す（run 1032 で Other では見つからなかった。この回で足したのは読み上げの既定の操作。型はログに出す）
        let map = app.descendants(matching: .any).matching(identifier: "search.spotIndex.map").firstMatch
        if map.waitForExistence(timeout: 5) { print("spotMap.elementType \(map.elementType.rawValue)") }
        XCTAssertTrue(map.waitForExistence(timeout: 5), "「地図」に替えても地図が出ない")
        Thread.sleep(forTimeInterval: 1)
        let mapHeight = block.frame.height
        print("spotMap.height photos=\(photosHeight) map=\(mapHeight)")
        XCTAssertEqual(photosHeight, mapHeight, accuracy: 0.5, "「写真｜地図」で段の高さが変わった（\(photosHeight) → \(mapHeight)）")
        shoot(app, "11l-探す（撮影スポットの段・地図）")

        // 右上（北海道）をひと押し
        let card = app.otherElements["search.spotIndex.regionCard"].firstMatch
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.14)).tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(card.staticTexts["北海道"].waitForExistence(timeout: 3), "地図で北海道を押しても札が替わらない")
        shoot(app, "11m-探す（撮影スポットの段・地図で北海道）")

        // 長押ししてから南西（九州の辺り）へなぞって離す。**なぞる間は画面が流れない**（地図の y が前後で同じ）
        let mapTop = map.frame.minY
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.62))
            .press(forDuration: 0.6, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.85)))
        Thread.sleep(forTimeInterval: 1)
        print("spotMap.trace mapTop before=\(mapTop) after=\(map.frame.minY)")
        XCTAssertEqual(map.frame.minY, mapTop, accuracy: 0.5, "なぞっている間に画面が流れた")
        XCTAssertFalse(card.staticTexts["北海道"].exists, "なぞって離しても地方が替わらない")
        shoot(app, "11n-探す（撮影スポットの段・地図をなぞった）")

        let seeAll = app.buttons["search.spotIndex.mapSeeAll"].firstMatch
        guard seeAll.waitForExistence(timeout: 5), seeAll.isHittable else { return }
        seeAll.tap()
        guard app.textFields["spotIndex.field"].waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "11o-撮影スポットの一覧（地方）")

        // 戻って、地図の上から払うと段（画面）が流れる（長押しをしない指はスクロールに渡す）
        goBack(app)
        guard map.waitForExistence(timeout: 5), map.isHittable else { return }
        // 地図の上から払っても流れなかった件（run 1009〜1018）は、SwiftUI の「長押し → 引く」が指を取っていた（run 1022）
        let before = map.frame.minY
        map.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        print("spotMap.swipe mapTop before=\(before) after=\(map.frame.minY)")
        XCTAssertLessThan(map.frame.minY, before - 20, "地図の上から払っても画面が流れない")
    }

    /// **開いたときは何も選んでいない**（2026-11-12 owner「なんも押してないのに県を選ぶというのわかりづらいな。ガイドもないし」）。
    ///
    /// 1. 「写真」: チップは先頭の「全国」だけが選ばれた形（地方のチップは選ばれていない）
    /// 2. 「地図」: 右の札は「全国」と「地方を押すと、ここに出ます」・「〇〇をすべて見る」は無い。撮る
    /// 3. 地図の上の名前の札「近畿 ›」を1回押すと、札が近畿になり「近畿をすべて見る」が出る。撮る
    ///
    /// 直しを戻す（件数のいちばん多い地方を選んでおく）と、1 で地方のチップが選ばれ、2 で一言が無く「すべて見る」が出て落ちる。
    /// 段が出なければ撮らない（この試験の決まり）
    func testSearchSpotMapStartsWithNothingSelected() {
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

        let block = app.otherElements["search.spotIndex.block"].firstMatch
        guard block.waitForExistence(timeout: 30) else { return }
        let mapTab = app.buttons["search.spotIndex.mode.map"].firstMatch
        guard mapTab.waitForExistence(timeout: 5) else { return }
        let firstCard = app.buttons.matching(identifier: "search.spotIndex.prefecture").firstMatch
        var swipes = 0
        while !(mapTab.isHittable && firstCard.isHittable), swipes < 6 {
            app.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 1)
            swipes += 1
        }
        guard mapTab.isHittable, firstCard.isHittable else { return }

        // 1. 写真: 「全国」だけが選ばれている
        let all = app.buttons["search.spotIndex.region.all"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5), "先頭の「全国」のチップが無い")
        print("spotIndex.allChip selected=\(all.isSelected)")
        XCTAssertTrue(all.isSelected, "開いたときに「全国」が選ばれていない")
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.spotIndex.region.' AND identifier != 'search.spotIndex.region.all'"))
        let picked = (0..<chips.count).map { chips.element(boundBy: $0) }.filter(\.isSelected).map(\.identifier)
        print("spotIndex.selectedChips \(picked)")
        XCTAssertTrue(picked.isEmpty, "何も押していないのに地方のチップが選ばれている: \(picked)")

        // 2. 地図: 何も塗らず、右の札は「全国」と一言
        mapTab.tap()
        let map = app.descendants(matching: .any).matching(identifier: "search.spotIndex.map").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5), "「地図」に替えても地図が出ない")
        Thread.sleep(forTimeInterval: 1)
        let hint = app.staticTexts["search.spotIndex.mapHint"].firstMatch
        let seeAll = app.buttons["search.spotIndex.mapSeeAll"].firstMatch
        print("spotMap.idle hint=\(hint.exists) seeAll=\(seeAll.exists) mapFrame=\(map.frame)")
        XCTAssertTrue(hint.waitForExistence(timeout: 3), "何も選んでいないときの一言（地方を押すと、ここに出ます）が無い")
        XCTAssertFalse(seeAll.exists, "何も押していないのに地方の「すべて見る」が出ている（地方を選んでいる）")
        shoot(app, "11p-探す（撮影スポットの段・地図・何も選んでいない）")

        // 3. 名前の札「近畿 ›」（地図の枠 189×212 の (78, 151)）を1回押す
        map.coordinate(withNormalizedOffset: CGVector(dx: 78.0 / 189, dy: 151.0 / 212)).tap()
        Thread.sleep(forTimeInterval: 1)
        let card = app.otherElements["search.spotIndex.regionCard"].firstMatch
        XCTAssertTrue(card.staticTexts["近畿"].waitForExistence(timeout: 3), "「近畿 ›」の札を押しても近畿にならない")
        XCTAssertTrue(seeAll.waitForExistence(timeout: 3), "地方を押しても「すべて見る」が出ない")
        XCTAssertFalse(hint.exists, "地方を選んだのに一言が残っている")
        shoot(app, "11q-探す（撮影スポットの段・地図・名前の札で近畿）")
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
        // 旅行プランの見本（Debug のときだけ・サーバーへは送らない・`TripPlanFixture`）。「旅行プランに入れる」のシートに出る
        app.launchArguments += ["-JPTripPlanFixture", "YES"]
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

        // マイページの行には「旅行プランに入れる」を置かない（2026-11-10 owner「マイページはかえなくていい」・札 #519）
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

        // 旅行プランを作る流れ（2026-11-10 札 #521）: 地図から押すと日付の段から始まる。
        // **日付と下書きを撮るだけで「保存」は押さない**（押すとプランを作りに行く）。出なければ撮らずに抜ける
        create.tap()
        let toDraft = app.buttons["tripCreate.toDraft"].firstMatch
        guard toDraft.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "64b-旅行プランを作る・日付（いつ行く？）")
        // 翌月の 10 日と 11 日（今日より前は押せないので、翌月にする）
        let next = app.buttons["tripCreate.nextMonth"].firstMatch
        guard next.waitForExistence(timeout: 5), next.isHittable else { return }
        next.tap()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        guard let month = calendar.date(byAdding: .month, value: 1, to: Date()) else { return }
        let parts = calendar.dateComponents([.year, .month], from: month)
        let prefix = String(format: "tripCreate.day.%04d-%02d-", parts.year ?? 0, parts.month ?? 0)
        for day in ["10", "11"] {
            let cell = app.buttons[prefix + day].firstMatch
            guard cell.waitForExistence(timeout: 5), cell.isHittable else { return }
            cell.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        Thread.sleep(forTimeInterval: 0.5)
        shoot(app, "64c-旅行プランを作る・日付を選んだ（1 泊 2 日）")
        guard toDraft.isHittable else { return }
        toDraft.tap()
        let save = app.buttons["tripCreate.save"].firstMatch
        guard save.waitForExistence(timeout: 10) else { return }
        // 日の出・日の入りと写真の縮小版が描かれるのを待つ
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "64d-旅行プランを作る・下書き（時間帯の順・日の出と日の入り）")
    }

    // MARK: - ホームの旅行プランの札の「⋯」（2026-11-12）

    /// **ホームの上の札（出発が近い旅行プラン）の「⋯」と、削除の「元に戻す」**（owner「削除するときは旅行プランの
    /// ページに行かないといけないのめんどくさい」）。見本のプラン（`-JPTripPlanFixture`・Debug のときだけ・サーバーへは
    /// 送らない）に、出発が2日後の「週末の鎌倉」を足して札を出す（`-JPTripPlanFixtureSoon`）。
    /// 削除は押すだけで聞かずに札から消え、「元に戻す」で戻る（6秒の間はどこへも送らない）。出なければ撮らずに抜ける
    func testCapturesHomeTripCardMenu() {
        let app = launchTrunk(["-JPTripPlanFixture", "YES", "-JPTripPlanFixtureSoon", "YES"])
        let more = app.buttons["home.tripMenu"].firstMatch
        guard more.waitForExistence(timeout: 30) else {
            note(app, "旅行プランの札", "30 秒で札の「⋯」が出ない")
            return
        }
        // 札の光の時刻・季節の札の写真が描かれるのを待つ
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "10g-ホーム（旅行プランの札の⋯）")
        guard more.isHittable else {
            note(app, "旅行プランの札", "「⋯」が押せない")
            return
        }
        more.tap()
        let delete = app.buttons["旅行プランを削除"].firstMatch
        guard delete.waitForExistence(timeout: 5) else {
            note(app, "旅行プランの札", "メニューに「旅行プランを削除」が無い")
            return
        }
        XCTAssertTrue(app.buttons["この旅をホームに出さない"].firstMatch.exists, "メニューに「この旅をホームに出さない」が無い")
        Thread.sleep(forTimeInterval: 0.5)
        shoot(app, "10h-ホーム（旅行プランの札のメニュー）")

        // 削除: 確かめを出さずに札から消え、「元に戻す」が出る
        delete.tap()
        let undo = app.buttons["home.tripMenu.undo"].firstMatch
        guard undo.waitForExistence(timeout: 5) else {
            note(app, "旅行プランの札", "削除のあとに「元に戻す」が出ない")
            return
        }
        // 🔴 「元に戻す」は6秒で閉じる。run 1167 では出てから押すまでに検査と撮影で 4.2 秒かかり（t=38.57→42.74、
        // 削除を押したのは t=35.28〜37.52）、押しに行った時には閉じていた。出たらすぐ撮って押し、検査はその後
        shoot(app, "10i-ホーム（旅行プランの札を削除・元に戻す）")
        let cardGone = !more.exists
        undo.tap()
        XCTAssertTrue(cardGone, "削除したのに札が残っている")
        XCTAssertFalse(app.alerts.firstMatch.exists, "削除で確かめのダイアログが出た")
        XCTAssertFalse(app.sheets.firstMatch.exists, "削除で確かめのダイアログが出た")
        XCTAssertTrue(app.buttons["home.tripMenu"].firstMatch.waitForExistence(timeout: 5), "「元に戻す」で札が戻らない")
    }

    // MARK: - 旅行プランの日程（見本のプラン・2026-11-10 札 #521）

    /// 見本のプラン（`-JPTripPlanFixture`・Debug のときだけ・サーバーへは送らない）で旅行プランの日程を開く。開けたら true
    private func openFixturePlan(_ app: XCUIApplication) -> Bool {
        guard openTripsRow(app, "trips.plans") else { return false }
        let plan = app.descendants(matching: .any).matching(identifier: "trips.plan").firstMatch
        guard plan.waitForExistence(timeout: 15), plan.isHittable else { return false }
        plan.tap()
        return app.descendants(matching: .any)["tripPlan.fixtureSends"].firstMatch.waitForExistence(timeout: 15)
    }

    /// 送った回数（見本のときだけ画面に出す `tripPlan.fixtureSends` の値）。ログにも残す
    private func fixtureSends(_ app: XCUIApplication, _ when: String) -> String? {
        let label = app.descendants(matching: .any)["tripPlan.fixtureSends"].firstMatch
        let value = label.value as? String
        let line = "TRIPFIXTURE when=\(when) sends=\(value ?? "nil")"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        return value
    }

    /// 出発の日付を消す・入れるを交互に押す（画面の上にあって動かない2つ・1回ごとに日程が変わる）
    private func toggleStartDate(_ app: XCUIApplication, times: Int) -> Bool {
        let began = Date()
        for i in 0..<times {
            let label = i % 2 == 0 ? "出発の日付を消す" : "出発の日付を入れる"
            let button = app.buttons[label].firstMatch
            guard button.waitForExistence(timeout: 3), button.isHittable else {
                _ = fixtureSends(app, "tap\(i)-missing-\(label)")
                return false
            }
            button.tap()
            // 押した時刻（始めからの秒）と、その時点の送った回数を残す（押す間が 2 秒を越えていないかを数で見る）
            _ = fixtureSends(app, String(format: "tap%d-t+%.1fs", i, Date().timeIntervalSince(began)))
        }
        return true
    }

    /// **撮影スポットを払う**（2026-11-11 owner の要望の①・`SpotSwipeView`）。**未ログイン**で、ホームの上の札の
    /// 1枚目から開く → 1枚目を「行きたい」・4枚を「見送る」→ 山に挟む札 → 「ログインして見る」でログインの板。
    /// 「行きたい」は未ログインなので端末の共有の鍵に入るだけ（サーバーへは送らない）。出なければ撮らずに抜ける
    func testCapturesSpotSwipe() {
        let app = XCUIApplication()
        // 一巡と同じ立ち上げ方（意味は `testCapturesEveryScreen` の注記）。**`-JPPreviewUserId` を渡さない**＝未ログイン
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        // 前の回の続き（見た札・開いた印）を残さない
        app.launchArguments += ["-journey-photo-spot-swipe-started", "NO", "-journey-photo-spot-swipe-seen", "()"]
        // 札の出典の行の幅と札の背を値で出す（`home.topCard.probe`・2026-11-14 出典の頭が切れる件）
        app.launchArguments += ["-JPPreviewLayoutProbe", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let entry = app.buttons["home.spotSwipe"].firstMatch
        guard entry.waitForExistence(timeout: 30) else { return }
        // 入口の札の写真（撮影スポットの詳細）が描かれるのを待つ
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "66-撮影スポットを払う（ホームの札の1枚目・未ログイン）")
        recordTopCardProbe(app, entry: entry)
        guard entry.isHittable else { return }
        entry.tap()

        let card = app.descendants(matching: .any).matching(identifier: "tripPicker.card").firstMatch
        guard card.waitForExistence(timeout: 20) else { return }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "66b-撮影スポットを払う（全画面・未ログイン）")

        let want = app.buttons["tripPicker.want"].firstMatch
        let pass = app.buttons["tripPicker.pass"].firstMatch
        guard want.waitForExistence(timeout: 5), want.isHittable else { return }
        want.tap()
        Thread.sleep(forTimeInterval: 1)
        for _ in 0..<4 {
            guard pass.waitForExistence(timeout: 5), pass.isHittable else { return }
            pass.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        let pause = app.descendants(matching: .any).matching(identifier: "tripPicker.pause").firstMatch
        guard pause.waitForExistence(timeout: 10) else { return }
        shoot(app, "66c-撮影スポットを払う（5枚で挟む札・未ログイン）")

        let action = app.buttons["tripPicker.pause.action"].firstMatch
        guard action.waitForExistence(timeout: 5), action.isHittable else { return }
        action.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "66d-撮影スポットを払う（ログインの板）")
    }

    /// ホームの上の札の出典の行の幅（渡された幅・全文の要る幅）と札の背を書き出す（`home.topCard.probe`・2026-11-14）。
    /// 字が切れたかは画面の木から取れないので、`TopCardProbe` が札の中で測った値を読む
    private func recordTopCardProbe(_ app: XCUIApplication, entry: XCUIElement) {
        let probe = app.descendants(matching: .any)["home.topCard.probe"].firstMatch
        let value = probe.exists ? (probe.value as? String ?? "nil") : "無し"
        let line = "TOPCARD entry=\(entry.frame) width=\(app.windows.firstMatch.frame.width) probe=\(value)"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        let note = XCTAttachment(string: value.replacingOccurrences(of: " | ", with: "\n"))
        note.name = "66-撮影スポットを払う（札の出典の寸法）"
        note.lifetime = .keepAlways
        add(note)
        // 2026-11-14 判断（`TopCardCredit`）: 札の背（116）と1行のまま、出典の頭（「写真: 作者」の頭）を必ず見せる。
        // 直す前（Mac run 1274）は「福岡県　久留米市　写…rio / CC BY-SA 4.0」（幅 222.0 に 307.0 要る字を真ん中で切った）
        guard probe.exists else { return XCTFail("札の寸法の要素（home.topCard.probe）が無い") }
        let parts = value.components(separatedBy: " | ")
        let credits = parts.filter { $0.hasPrefix("credit ") }
        XCTAssertFalse(credits.isEmpty, "写真のある札に出典の行（creditLine）が無い: \(value)")
        for credit in credits {
            XCTAssertTrue(credit.contains(" headVisible=yes"), "出典の頭が切れている: \(credit)")
            // 長い作者の見本（最後の形・作者の後ろを切る）でも頭が残る（本物の写真は日によって替わるので見本で確かめる）
            XCTAssertTrue(credit.contains("sampleHeadVisible=yes"), "長い作者で出典の頭が切れる: \(credit)")
        }
        XCTAssertFalse(parts.contains { $0.hasPrefix("detail ") && $0.contains("写真: ") },
                       "出典を1本の字（真ん中で切る小さい行）で出している: \(value)")
        for card in parts where card.hasPrefix("card ") {
            let height = card.components(separatedBy: "height=").last.flatMap { Double($0) } ?? 0
            XCTAssertEqual(height, 116, accuracy: 0.5, "札の背が 116 から変わった: \(card)")
        }
    }

    /// **旅行プランの日程**（自動保存・運ぶ・移動の見込み・区間のシート）。
    /// 自動保存は**手を止めてから 2 秒待ってまとめて送る**——続けて 5 回直しても送るのは 1 回（数で確かめる）。
    /// 出なければ撮らずに抜ける
    func testCapturesTripPlanDays() {
        // 自動保存の待ちを 10 秒に（見本のときだけ効く）。UI テストは押す間が 2.4〜4.9 秒あり（run 969）、
        // 2 秒の待ちでは「続けて直す」を作れない。まとめて送る仕組みは同じ
        let app = launchTrunk(["-JPTripPlanFixture", "YES", "-JPTripPlanAutosaveDelay", "10"])
        guard openFixturePlan(app) else { return }
        // 移動の見込み（Apple のサーバー）と日の出・日の入りを待つ
        Thread.sleep(forTimeInterval: 8)
        shoot(app, "65-旅行プランの日程（自動保存・移動の見込み）")
        XCTAssertEqual(fixtureSends(app, "open"), "0", "開いただけで送っている")
        // 日をまたぐ区間（2026-11-11 owner の実機「バスとか出てこないよ」）: 2 日目の最初の上に「前の日の千里浜…から」
        let crossDay = app.descendants(matching: .any).matching(identifier: "trip.leg")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "前の日の")).firstMatch
        var crossPushes = 0
        while !crossDay.exists, crossPushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            crossPushes += 1
        }
        let crossLine = "TRIPLEG crossDay exists=\(crossDay.exists) label=\(crossDay.exists ? crossDay.label : "-")"
        print(crossLine)
        XCTContext.runActivity(named: crossLine) { _ in }
        XCTAssertTrue(crossDay.exists, "日をまたぐ区間が出ていない")
        if crossDay.exists {
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "65f-旅行プランの日程（前の日の最後の場所からの移動の目安）")
        }
        for _ in 0..<crossPushes { app.swipeDown(); Thread.sleep(forTimeInterval: 0.5) }

        // 運ぶ: 1 日目の最後（千里浜）を 2 日目の最初の行へ（日をまたぐ）。運んだら待って 1 回送る。
        // 千里浜の「…」の位置（「1 日目・3 番目」）を前後で見る。1 回目は止めずに離す。入らなければ 2 回目は行き先で止まってから離す。
        // **「止めずに離して 1 回目で入る」で縛らない理由**（札 #521・run 1031）: 試しの運びのあと 1.2 秒でも 7 回中 2 回入らなかった
        // （持ち上がったが drop が呼ばれない・落とす先から出た知らせも来ない）。各回の 1 回目の数と出来事の並びはログに残す
        let handles = app.descendants(matching: .any).matching(identifier: "tripPlan.dragHandle")
        let menu = app.buttons["「千里浜なぎさドライブウェイ」の操作"].firstMatch
        func order() -> String { (menu.value as? String) ?? "nil" }
        _ = fixtureSends(app, "dragHandles-count\(handles.count)")
        if handles.count >= 4 {
            let from = handles.element(boundBy: 2)
            let to = handles.element(boundBy: 3)
            var pushes = 0
            while !(from.isHittable && to.isHittable), pushes < 3 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                pushes += 1
            }
            _ = fixtureSends(app, "dragHittable-from\(from.isHittable)-to\(to.isHittable)")
            if from.isHittable, to.isHittable {
                let before = order()
                _ = fixtureSends(app, "orderBefore[\(before)]")
                from.press(forDuration: 1.2, thenDragTo: to)
                Thread.sleep(forTimeInterval: 2)
                var after = order()
                _ = fixtureSends(app, "orderAfterPress[\(after)] drag[\(dragCounts(app))]")
                if after == before {
                    let again = handles.element(boundBy: 2)
                    again.press(forDuration: 1.2, thenDragTo: handles.element(boundBy: 3),
                                withVelocity: .slow, thenHoldForDuration: 1.0)
                    Thread.sleep(forTimeInterval: 2)
                    after = order()
                    _ = fixtureSends(app, "orderAfterHold[\(after)] drag[\(dragCounts(app))]")
                }
                Thread.sleep(forTimeInterval: 11)
                shoot(app, "65b-旅行プランの日程（運んだ・日をまたいで2日目へ）")
                let sent = fixtureSends(app, "afterDrag")
                XCTAssertNotEqual(after, before, "運んでも並びが変わらない")
                if after != before { XCTAssertEqual(sent, "1", "運んだあとに 1 回送っていない") }
            }
        }

        // 区間の行を押すと Apple のマップ（2026-11-12）。見本では地図のアプリへ出ず、開いた手段を数えに残す（`TripLegMaps`）
        //
        // 🔴 **押すのは、上の帯（ナビゲーションバー）と下のタブの間に丸ごと見えている行だけ**（run 1208・1212）。
        // `firstMatch` の行（1 日目の最初の区間）は運んだあと {16, 37.7, 364×44} で、上の帯（y 62〜116）の下に隠れていた。
        // それでも `isHittable` は真で、押した点（y 約 60）は画面の上の端に落ち、行のボタンは呼ばれなかった
        // （段の印 `LT` が 1 つも無い・同じ所にある「i」も開かなかった）。見えている枠を数で見て選ぶ
        let legs = app.descendants(matching: .any).matching(identifier: "trip.leg")
        let mores = app.buttons.matching(identifier: "trip.leg.more")
        let window = app.windows.firstMatch.frame
        func visibleBand() -> (top: CGFloat, bottom: CGFloat) {
            let bar = app.navigationBars.firstMatch
            let tabs = app.tabBars.firstMatch
            return (bar.exists ? bar.frame.maxY : window.minY, tabs.exists ? tabs.frame.minY : window.maxY)
        }
        func fullyVisible(_ query: XCUIElementQuery) -> XCUIElement? {
            let band = visibleBand()
            for i in 0..<query.count {
                let element = query.element(boundBy: i)
                let frame = element.frame
                if frame.minY >= band.top, frame.maxY <= band.bottom { return element }
            }
            return nil
        }
        var shown = fullyVisible(legs)
        var pushes = 0
        while shown == nil, legs.count > 0, pushes < 6 {
            // 上に隠れているなら下へ（swipeDown で上の方が出る）。先に 3 回、だめなら逆へ 3 回
            if pushes < 3 { app.swipeDown() } else { app.swipeUp() }
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
            shown = fullyVisible(legs)
        }
        let band = visibleBand()
        let pickLine = "TRIPLEG pick band=\(Int(band.top))-\(Int(band.bottom)) legs=\(legs.count) pushes=\(pushes) "
            + "frame=\(shown.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "nil")"
        print(pickLine)
        XCTContext.runActivity(named: pickLine) { _ in }
        XCTAssertNotNil(shown, "区間の行が画面の見える所に出ない")
        if let leg = shown {
            let legLine = "TRIPLEG row label=\(leg.label) before[\(dragCounts(app))]"
            print(legLine)
            XCTContext.runActivity(named: legLine) { _ in }
            let tapped = Date()
            leg.tap()
            // 名前で探し直す（最大で数秒）のを待つ。少しずつ読んで、段の印（LT=・LM=・LR=・LX=・開いた M:）をその都度残す（run 1208）
            var trail = dragCounts(app)
            while !trail.contains("M:"), Date().timeIntervalSince(tapped) < 6 {
                Thread.sleep(forTimeInterval: 0.5)
                trail = dragCounts(app)
                let pollLine = String(format: "TRIPLEG poll t+%.1fs trail[%@]", Date().timeIntervalSince(tapped), trail)
                print(pollLine)
                XCTContext.runActivity(named: pollLine) { _ in }
            }
            let mapsLine = "TRIPLEG maps trail[\(trail)]"
            print(mapsLine)
            XCTContext.runActivity(named: mapsLine) { _ in }
            XCTAssertTrue(trail.contains("LT="), "区間の行を押しても行のボタンが呼ばれていない: \(trail)")
            XCTAssertTrue(trail.contains("M:"), "区間の行を押しても Apple のマップを開いていない: \(trail)")
        }
        // 区間のシート（行の右端の「i」・出る時刻の目安と Google マップ）。同じく見えている「i」だけを押す
        if let more = fullyVisible(mores) {
            more.tap()
            let apple = app.buttons["trip.leg.apple"].firstMatch
            if apple.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 1)
                shoot(app, "65c-区間のシート（Apple のマップ／Google マップで乗り換えを見る）")
                XCTAssertTrue(app.buttons["trip.leg.google"].firstMatch.exists, "区間のシートに Google マップが無い")
                let close = app.buttons["閉じる"].firstMatch
                if close.exists { close.tap() }
                Thread.sleep(forTimeInterval: 1)
            }
        }

        // 続けて 5 回直す → 手を止めて 2 秒より長く待つ → 送ったのは 1 回だけ増える
        for _ in 0..<4 where !app.buttons["出発の日付を消す"].firstMatch.isHittable {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 1)
        }
        // 直す前の回数は画面から読む（前の段の結果に頼らない）
        let sentBefore = Int(fixtureSends(app, "before5edits") ?? "") ?? -1
        guard toggleStartDate(app, times: 5) else { return }
        Thread.sleep(forTimeInterval: 13)
        XCTAssertEqual(fixtureSends(app, "after5edits"), "\(sentBefore + 1)",
                       "続けて 5 回直したのに、まとめて 1 回で送っていない")
    }

    /// 運ぶ操作の数（見本のときだけ画面に出す `tripPlan.fixtureDrag`）と出来事の並び（`tripPlan.fixtureDragTrail`）
    private func dragCounts(_ app: XCUIApplication) -> String {
        let counts = (app.descendants(matching: .any)["tripPlan.fixtureDrag"].firstMatch.value as? String) ?? "nil"
        let trail = (app.descendants(matching: .any)["tripPlan.fixtureDragTrail"].firstMatch.value as? String) ?? "nil"
        return "\(counts)] trail[\(trail)"
    }

    /// **数えない試しの運び**: 押さえて自分の行の上で離す（並びは変わらない）。テストの最初の起動の 1 回目は
    /// 持ち上がらないことがある（run 1016/1020/1025/1030 で 4/4）ので、測る運びの前に 1 回入れる。
    /// run 1031: 動かさずに離すこの形では 2 回とも持ち上がらなかった（lift=0）。試しとして効いているかは確かめていない
    private func warmUpDrag(_ app: XCUIApplication, _ source: XCUIElement) {
        source.press(forDuration: 1.2, thenDragTo: source)
        Thread.sleep(forTimeInterval: 2)
        let line = "TRIPDRAG warm-up after[\(dragCounts(app))]"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }

    /// 見本の旅を開き、運ぶ元（1 日目の 3 番目）と行き先（2 日目の「越前海岸 呼鳥門」の「…」）が押せる所まで上げる
    private func dragStage(_ app: XCUIApplication) -> (XCUIElement, XCUIElement, Int)? {
        guard openFixturePlan(app) else { return nil }
        Thread.sleep(forTimeInterval: 3)
        let source = app.descendants(matching: .any).matching(identifier: "tripPlan.dragHandle").element(boundBy: 2)
        let target = app.buttons["「越前海岸 呼鳥門」の操作"].firstMatch
        var pushes = 0
        while !(source.isHittable && target.isHittable), pushes < 4 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard source.isHittable, target.isHittable else { return nil }
        return (source, target, pushes)
    }

    /// **(b)「持ち上がったが落ちない」をどの部品で止まったかで分ける**（札 #521・2026-11-11）。
    /// run 1025 で押さえる時間 0.8 秒のとき 2/5 出た。0.8 秒で 6 起動 × 4 回運び、1 回ごとに出来事の並び
    /// （持ち上がった・落とす先に入った／出た・drop が呼ばれた・断った・preview が消えた）を残す。合否は無い。
    /// 名指しのときだけ（`screens=testMeasuresTripPlanDragTrail`）。1 起動 80 秒ほど × 6 で 20 分の上限に入れる
    func testMeasuresTripPlanDragTrail() {
        executionTimeAllowance = 1200
        for launch in 0..<6 {
            let app = launchTrunk(["-JPTripPlanFixture", "YES"])
            defer { app.terminate() }
            guard let stage = dragStage(app) else {
                let line = "TRIPDRAG trail launch=\(launch) not-ready"
                print(line); XCTContext.runActivity(named: line) { _ in }
                continue
            }
            let (source, target, pushes) = stage
            for drag in 1...4 {
                guard source.isHittable, target.isHittable else { break }
                source.press(forDuration: 0.8, thenDragTo: target)
                Thread.sleep(forTimeInterval: 2)
                let line = "TRIPDRAG trail launch=\(launch) drag=\(drag) hold=0.8 pushes=\(pushes) after[\(dragCounts(app))]"
                print(line)
                XCTContext.runActivity(named: line) { _ in }
            }
        }
    }

    /// **試しの運びを 1 回入れたあと、押さえて 1.2 秒・止めずに離して 1 回目で入るか**を続けて数える
    /// （`testCapturesTripPlanDays` を縛る前の裏づけ・札 #521）。7 起動。合否は無く、入ったかを位置で残す。
    /// 名指しのときだけ（`screens=testMeasuresTripPlanDragFirstTry`）。テストの最初の起動を含める
    func testMeasuresTripPlanDragFirstTry() {
        executionTimeAllowance = 1200
        for launch in 0..<7 {
            let app = launchTrunk(["-JPTripPlanFixture", "YES"])
            defer { app.terminate() }
            guard let stage = dragStage(app) else {
                let line = "TRIPDRAG first launch=\(launch) not-ready"
                print(line); XCTContext.runActivity(named: line) { _ in }
                continue
            }
            let (source, target, pushes) = stage
            let position = app.buttons["「千里浜なぎさドライブウェイ」の操作"].firstMatch
            let posBefore = (position.value as? String) ?? "nil"
            warmUpDrag(app, source)
            let posWarm = (position.value as? String) ?? "nil"
            source.press(forDuration: 1.2, thenDragTo: target)
            Thread.sleep(forTimeInterval: 2)
            let posAfter = (position.value as? String) ?? "nil"
            let line = "TRIPDRAG first launch=\(launch) pushes=\(pushes) entered=\(posAfter != posWarm) "
                + "pos[\(posBefore) -> \(posWarm) -> \(posAfter)] after[\(dragCounts(app))]"
            print(line)
            XCTContext.runActivity(named: line) { _ in }
        }
    }

    /// **動かす速さで (b)「持ち上がったが落ちない」の率を比べる**（札 #521・2026-11-11）。(b) は起動の最初の運びでだけ出た
    /// （4/27、2 回目以降 0/33）ので、1 起動 1 回だけ運ぶ。押さえて 1.2 秒・止めずに離す（`thenHoldForDuration: 0`）。
    /// 9 起動（テストの最初の起動は (a) が出るので数えない）。離して 2 秒後と 5 秒後に、真鍮の落とす先の線
    /// （`tripPlan.dropLine`・見本のときだけ数えられる）が残っているかも数える。合否は無い。1 本 10 分ほど
    private func measureDragVelocity(_ velocity: XCUIGestureVelocity, _ label: String) {
        executionTimeAllowance = 1200
        for launch in 0..<9 {
            let app = launchTrunk(["-JPTripPlanFixture", "YES"])
            defer { app.terminate() }
            guard let stage = dragStage(app) else {
                let line = "TRIPDRAG velocity=\(label) launch=\(launch) not-ready"
                print(line); XCTContext.runActivity(named: line) { _ in }
                continue
            }
            let (source, target, pushes) = stage
            let lines = app.descendants(matching: .any).matching(identifier: "tripPlan.dropLine")
            let linesBefore = lines.count
            source.press(forDuration: 1.2, thenDragTo: target, withVelocity: velocity, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 2)
            let at2 = lines.count
            let counts = dragCounts(app)
            Thread.sleep(forTimeInterval: 3)
            let at5 = lines.count
            let where5 = at5 > 0 ? lines.firstMatch.label : "-"
            let line = "TRIPDRAG velocity=\(label) launch=\(launch) pushes=\(pushes) "
                + "dropLine[before=\(linesBefore) 2s=\(at2) 5s=\(at5) at=\(where5)] after[\(counts)]"
            print(line)
            XCTContext.runActivity(named: line) { _ in }
        }
    }

    /// 名指しのときだけ（`screens=testMeasuresTripPlanDragVelocitySlow`）
    func testMeasuresTripPlanDragVelocitySlow() { measureDragVelocity(.slow, "slow") }
    /// 名指しのときだけ（`screens=testMeasuresTripPlanDragVelocityDefault`）
    func testMeasuresTripPlanDragVelocityDefault() { measureDragVelocity(.default, "default") }
    /// 名指しのときだけ（`screens=testMeasuresTripPlanDragVelocityFast`）
    func testMeasuresTripPlanDragVelocityFast() { measureDragVelocity(.fast, "fast") }

    /// **持ち手 ≡・「2日目へ移す」・外して戻す・場所を探して足す**（2026-11-12・1.1.85・札 #570・資料「みんなで埋める旅行プラン」
    /// の場面5〜7）。見本の「金沢・福井の旅」で:
    /// 1. 持ち手 ≡ が出ている。「…」の上へ → 1 番目へ、下へ → 2 番目へ戻る（持ち手の読み上げの上下と同じ `perform`。
    ///    iOS の XCUIElement には `increment()` が無く、読み上げの調整の操作は UI テストから押せない）
    /// 2. 「…」に日を選ぶ段を挟まず「2日目へ移す」（日が2つ）→ 2 日目の末尾へ
    /// 3. 「…」の「この日程から外す」→ 日の下に「戻す」→ 押すと戻る
    /// 4. 1 日目の「追加」→ 探す欄に「東尋坊」→ 観光スポットの結果を押す → 「入れました」→ 閉じると日程にある
    func testCapturesTripPlanSearchAndHandle() {
        let app = launchTrunk(["-JPTripPlanFixture", "YES"])
        guard openFixturePlan(app) else { return }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "65g-旅行プランの日程（持ち手 ≡）")

        // 1. 持ち手を上へ・下へ（読み上げの上下のスワイプと同じ操作）
        let castleMenu = app.buttons["「金沢城公園」の操作"].firstMatch
        func castleHandle() -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "tripPlan.dragHandle")
                .matching(NSPredicate(format: "label == %@", "「金沢城公園」を運ぶ")).firstMatch
        }
        XCTAssertTrue(castleHandle().waitForExistence(timeout: 10), "持ち手 ≡ が出ていない")
        XCTAssertEqual(castleMenu.value as? String, "1 日目、2 番目")
        XCTAssertEqual(castleHandle().value as? String, "1 日目、2 番目", "持ち手の読み上げの位置")
        func menuPick(_ title: String) {
            castleMenu.tap()
            let item = app.buttons[title].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "「…」に「\(title)」が無い")
            item.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        menuPick("上へ")
        XCTAssertEqual(castleMenu.value as? String, "1 日目、1 番目", "「上へ」で動かない")
        menuPick("下へ")
        XCTAssertEqual(castleMenu.value as? String, "1 日目、2 番目", "「下へ」で動かない")

        // 2. 「2日目へ移す」（日を選ぶ段を挟まない）
        castleMenu.tap()
        let direct = app.buttons["2日目へ移す"].firstMatch
        XCTAssertTrue(direct.waitForExistence(timeout: 5), "「…」に「2日目へ移す」が直接出ない")
        shoot(app, "65h-旅行プランの日程（…の2日目へ移す）")
        direct.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.buttons["「金沢城公園」の操作"].firstMatch.value as? String, "2 日目、3 番目")

        // 3. 外して戻す
        let capeMenu = app.buttons["「越前岬」の操作"].firstMatch
        var pushes = 0
        while !capeMenu.isHittable, pushes < 3 { app.swipeUp(); Thread.sleep(forTimeInterval: 1); pushes += 1 }
        capeMenu.tap()
        let remove = app.buttons["この日程から外す"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let restore = app.buttons.matching(identifier: "tripPlan.restore")
            .matching(NSPredicate(format: "label == %@", "「越前岬」を戻す")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "外したあとに「戻す」が出ない")
        XCTAssertFalse(app.buttons["「越前岬」の操作"].firstMatch.exists, "外したのに日程に残っている")
        shoot(app, "65i-旅行プランの日程（外して戻す）")
        restore.tap()
        XCTAssertTrue(app.buttons["「越前岬」の操作"].firstMatch.waitForExistence(timeout: 5), "「戻す」で戻らない")
        XCTAssertEqual(app.buttons["「越前岬」の操作"].firstMatch.value as? String, "2 日目、2 番目", "外したときの位置へ戻らない")

        // 4. 場所を探して足す
        for _ in 0..<pushes { app.swipeDown(); Thread.sleep(forTimeInterval: 0.5) }
        let add = app.buttons["tripPlan.addRow.0"].firstMatch
        pushes = 0
        while !(add.exists && add.isHittable), pushes < 3 { app.swipeUp(); Thread.sleep(forTimeInterval: 1); pushes += 1 }
        XCTAssertTrue(add.isHittable, "1 日目の追加の行が押せない")
        add.tap()
        let field = app.textFields["trips.pick.search"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "場所を足すシートに探す欄が無い")
        field.tap()
        field.typeText("東尋坊")
        let result = app.buttons.matching(identifier: "trips.pick.row")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "東尋坊")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "「東尋坊」が観光スポットの結果に出ない")
        result.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(((result.value as? String) ?? "").hasPrefix("入れました"), "押しても入らない（\(result.value as? String ?? "nil")）")
        XCTAssertTrue(field.exists, "押したらシートが閉じた（続けて足せない）")
        shoot(app, "65j-場所を足す（探して入れた）")
        let close = app.buttons["閉じる"].firstMatch
        if close.exists { close.tap() }
        XCTAssertTrue(app.buttons["「東尋坊」の操作"].firstMatch.waitForExistence(timeout: 5), "入れた場所が日程に無い")
        XCTAssertEqual(app.buttons["「東尋坊」の操作"].firstMatch.value as? String, "1 日目、3 番目")
    }

    /// **日をまたぐ区間と長い移動**（2026-11-11 owner の実機「バスとか出てこないよ」「日本からブラジルとか無理じゃん」）。
    /// 見本の「京都とブラジルの旅」（1 日 1 か所・空の日・サンパウロ）を開き、前の日からの区間と、海を越える区間の
    /// 「飛行機などの長い移動」・そのシート（Google フライト）を撮る。出なければ撮らずに抜ける
    func testCapturesTripPlanLongLegs() {
        let app = launchTrunk(["-JPTripPlanFixture", "YES"])
        guard openTripsRow(app, "trips.plans") else { return }
        let plan = app.descendants(matching: .any).matching(identifier: "trips.plan")
            .matching(NSPredicate(format: "label CONTAINS %@", "京都とブラジル")).firstMatch
        var pushes = 0
        while plan.waitForExistence(timeout: 10), !plan.isHittable, pushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard plan.exists, plan.isHittable else { return }
        plan.tap()
        guard app.descendants(matching: .any)["tripPlan.fixtureSends"].firstMatch.waitForExistence(timeout: 15) else { return }
        // 移動の見込み（Apple のサーバー）を待つ
        Thread.sleep(forTimeInterval: 8)
        shoot(app, "66-旅行プランの日程（1日1か所・前の日からの移動・空の日）")
        let legs = app.descendants(matching: .any).matching(identifier: "trip.leg")
        let cross = legs.matching(NSPredicate(format: "label BEGINSWITH %@", "前の日の伏見稲荷大社から")).firstMatch
        let long = legs.matching(NSPredicate(format: "label CONTAINS %@", "飛行機などの長い移動")).firstMatch
        let line = "TRIPLEG legs=\(legs.count) cross=\(cross.exists) long=\(long.exists)"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertTrue(cross.exists, "1 日 1 か所のプランで、前の日からの区間が出ない")
        // 縦の線は行の高さいっぱい（見本のときだけ値に「line=… row=…」が出る・確かめ役の指摘）
        if cross.exists, let value = cross.value as? String {
            let nums = value.split(separator: " ").compactMap { Double($0.split(separator: "=").last ?? "") }
            let measured = "TRIPLEG connector \(value)"
            print(measured)
            XCTContext.runActivity(named: measured) { _ in }
            if nums.count == 2 {
                XCTAssertGreaterThanOrEqual(nums[0], nums[1] - 1, "縦の線が行の高さまで伸びていない: \(value)")
                XCTAssertGreaterThanOrEqual(nums[1], 44 - 0.5, "区間の行が 44pt より低い: \(value)")
            } else {
                XCTFail("線の高さが読めない: \(value)")
            }
        }
        XCTAssertTrue(long.exists, "日本 → ブラジルの区間が長い移動の形で出ない")
        pushes = 0
        while long.exists, !long.isHittable, pushes < 4 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard long.exists, long.isHittable else { return }
        shoot(app, "66b-旅行プランの日程（飛行機などの長い移動・空の日の追加）")
        long.tap()
        let flights = app.buttons["trip.leg.flights"].firstMatch
        XCTAssertTrue(flights.waitForExistence(timeout: 10), "長い移動のシートに Google フライトが無い")
        XCTAssertFalse(app.buttons["trip.leg.apple"].firstMatch.exists, "長い移動のシートに Apple のマップがある（経路が無い）")
        guard flights.exists else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "66c-長い移動のシート（Google フライトで探す）")
    }

    /// 旅行プランを仲間と共有（2026-11-12・札 #553・資料「SNS をもっと SNS に」2b）。見本は金沢のプランを「あお」と共有した形
    /// （`-JPTripShareFixture`）: 題・日付の下に「2人」と顔の段・「仲間を誘う」・「日程 | 会話」、あおが足した場所に
    /// 「あお が足しました」。会話に切り替えると吹き出しと「日程に足しました」の札・入力欄。誘うとリンクのシート
    func testCapturesTripShare() {
        let app = launchTrunk(["-JPTripPlanFixture", "YES", "-JPTripShareFixture", "YES"])
        guard openTripsRow(app, "trips.plans") else { return }
        let plan = app.descendants(matching: .any).matching(identifier: "trips.plan")
            .matching(NSPredicate(format: "label CONTAINS %@", "金沢")).firstMatch
        guard plan.waitForExistence(timeout: 10) else { return }
        plan.tap()
        let strip = app.descendants(matching: .any)["tripShare.strip"].firstMatch
        guard strip.waitForExistence(timeout: 15) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "66c-旅行プラン（仲間と共有・日程）")
        XCTAssertTrue(app.descendants(matching: .any)["tripPlan.addedBy"].firstMatch.exists, "仲間が足した場所に「足しました」が出ない")
        let chatTab = app.buttons["tripShare.tab.chat"].firstMatch
        guard chatTab.waitForExistence(timeout: 5) else { return }
        chatTab.tap()
        guard app.descendants(matching: .any)["tripShare.event"].firstMatch.waitForExistence(timeout: 10) else { return }
        shoot(app, "66d-旅行プラン（仲間と共有・会話）")
        let invite = app.buttons["tripShare.invite"].firstMatch
        guard invite.waitForExistence(timeout: 5) else { return }
        invite.tap()
        guard app.descendants(matching: .any)["tripShare.line"].firstMatch.waitForExistence(timeout: 10) else { return }
        shoot(app, "66e-旅行プラン（仲間を誘う）")
    }

    /// **送れていないとき**（圏外・断られた）。直しは画面に残り、「まだ送れていません」と「もう一度試す」が出る
    func testCapturesTripPlanDaysUnsent() {
        for (extra, name) in [(["-JPTripPlanFixtureOffline", "YES"], "65d-旅行プランの日程（圏外・まだ送れていません）"),
                              (["-JPTripPlanFixtureFail", "YES"], "65e-旅行プランの日程（断られた・もう一度試す）")] {
            let app = launchTrunk(["-JPTripPlanFixture", "YES"] + extra)
            defer { app.terminate() }
            guard openFixturePlan(app) else { continue }
            guard toggleStartDate(app, times: 1) else { continue }
            Thread.sleep(forTimeInterval: 4)
            let banner = app.descendants(matching: .any)["tripPlan.unsent"].firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 5), "\(name): 送れていない直しの札が出ない")
            if extra.first == "-JPTripPlanFixtureOffline" {
                XCTAssertEqual(fixtureSends(app, "offline"), "0", "圏外なのに送っている")
            }
            shoot(app, name)
        }
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

    // MARK: - 行った県マップ（2026-11-08・札 #503）

    /// 行った県マップ。マイページの「旅の記録」の下の札から入り、地図・一覧・県の札を撮る。
    /// `-JPPreviewVisitedMap YES`（Debug のみ・`PreviewSession.visitedMapSeed`）で、1〜5 回の段が並んだ見本の記録を入れる。
    /// **出なければ撮らずに抜ける**（札が見つからない・地図が出ない）。サーバーには何も送らない
    func testCapturesVisitedMap() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewVisitedMap", "YES"]
        // 帯は 5 秒で消えるが、要素を探すのに 1 回 0.5〜2 秒かかり、確かめの途中で消える（Mac 948）。UI テストだけ長くする
        app.launchArguments += ["-JPVisitedQuickBarSeconds", "30"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let entry = app.descendants(matching: .any)["profile.visitedMap"].firstMatch
        guard entry.waitForExistence(timeout: 20) else { return }
        var swipes = 0
        while !entry.isHittable, swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        guard entry.isHittable else { return }
        shoot(app, "86a-マイページの札「行った県」")
        entry.tap()

        let map = app.descendants(matching: .any)["visitedMap.map"].firstMatch
        guard map.waitForExistence(timeout: 15) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "86b-行った県の地図（回数の段）")

        // 案 A（札 #510・2026-11-10）: 県を押すたびに 1 回足し、下に小さな帯「東京都 6 回 ［−］［＋］［詳しく］」。
        // 🔴 ここから先は**本物の動きを守る**ので、出なければ落とす（レビュー 2026-11-10 の 4）。
        // 見本の東京都は 5 回。長押し（0.6 秒）→ 5 のまま帯だけ、押す 2 回 → 7、帯の［＋］→ 8、［−］→ 7
        XCTAssertFalse(app.switches["visitedMap.switch"].exists, "スイッチ「タップで回数を足す」が残っている")
        let tokyo = app.descendants(matching: .any)["visitedMap.pref.東京都"].firstMatch
        XCTAssertTrue(tokyo.waitForExistence(timeout: 5), "地図に東京都が無い")
        XCTAssertTrue(tokyo.isHittable, "地図の東京都が押せない")
        let count = app.descendants(matching: .any)["visitedMap.quick.count"].firstMatch

        tokyo.press(forDuration: 0.6)
        XCTAssertTrue(count.waitForExistence(timeout: 5), "長押しで帯が出ない")
        XCTAssertTrue(waitForLabel(count, "東京都、5 回"), "長押しで回数が変わった: \(count.label)")
        XCTAssertFalse(app.descendants(matching: .any)["visitedMap.card"].firstMatch.exists, "長押しで札が開いた")

        tokyo.tap()
        XCTAssertTrue(waitForLabel(count, "東京都、6 回"), "押して 1 回足していない: \(count.label)")
        tokyo.tap()
        XCTAssertTrue(waitForLabel(count, "東京都、7 回"), "2 回押して 2 回にならない: \(count.label)")
        XCTAssertFalse(app.descendants(matching: .any)["visitedMap.card"].firstMatch.exists, "押して札が開いた")

        let plus = app.buttons["visitedMap.quick.plus"].firstMatch
        let minus = app.buttons["visitedMap.quick.minus"].firstMatch
        XCTAssertTrue(plus.isHittable, "帯の［＋］が押せない")
        XCTAssertTrue(minus.isHittable, "帯の［−］が押せない")
        // ［−］と［＋］は同じ大きさ（44pt）
        XCTAssertEqual(plus.frame.size.width, minus.frame.size.width, accuracy: 0.5)
        XCTAssertEqual(plus.frame.size.height, minus.frame.size.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(minus.frame.size.height, 43.99)
        plus.tap()
        XCTAssertTrue(waitForLabel(count, "東京都、8 回"), "帯の［＋］で足せない: \(count.label)")
        minus.tap()
        XCTAssertTrue(waitForLabel(count, "東京都、7 回"), "帯の［−］で減らせない: \(count.label)")
        // 絵は［−］［＋］を確かめたあとに撮る
        shoot(app, "86e-行った県の帯（東京都を押した）")

        let details = app.buttons["visitedMap.quick.details"].firstMatch
        XCTAssertTrue(details.isHittable, "帯の［詳しく］が押せない")
        details.tap()
        XCTAssertTrue(app.descendants(matching: .any)["visitedMap.card"].firstMatch.waitForExistence(timeout: 5),
                      "［詳しく］で札が開かない")
        shoot(app, "86c-行った県の札（東京都）")
        let close = app.buttons["visitedMap.card.close"].firstMatch
        XCTAssertTrue(close.isHittable)
        close.tap()

        let list = app.buttons["visitedMap.mode.list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "一覧の切り替えが無い")
        list.tap()
        XCTAssertTrue(app.descendants(matching: .any)["visitedMap.list"].firstMatch.waitForExistence(timeout: 5))
        shoot(app, "86d-行った県の一覧")

        // 一覧の行（レビュー 2026-11-10 の 3）: 長押し 0.6 秒では足さず帯だけ・そのあと押すと 1 回足す
        // （長押しのあとの押下を飲み込みすぎない）・行から上へスワイプすると一覧が動き、足さない。見本の北海道は 2 回
        let row = app.descendants(matching: .any)["visitedMap.row.北海道"].firstMatch
        if !row.waitForExistence(timeout: 5) {
            // 調べ（Mac 945 で行の識別子が見つからなかった）: 要素の木のうち北海道・visitedMap の行をログに出す
            for line in app.debugDescription.components(separatedBy: "\n")
            where line.contains("北海道") || line.contains("visitedMap.list") || line.contains("visitedMap.row") {
                print("VISITED-TREE: \(line)")
            }
        }
        XCTAssertTrue(row.exists, "一覧に北海道の行が無い")
        var listSwipes = 0
        while !row.isHittable, listSwipes < 3 {
            app.swipeUp()
            listSwipes += 1
        }
        XCTAssertTrue(row.isHittable, "北海道の行が押せない")
        XCTAssertEqual(row.label, "北海道、2 回")
        row.press(forDuration: 0.6)
        XCTAssertTrue(waitForLabel(count, "北海道、2 回"), "一覧の長押しで帯が出ない／回数が変わった: \(count.label)")
        XCTAssertTrue(waitForLabel(row, "北海道、2 回"), "一覧の長押しで回数が変わった: \(row.label)")
        row.tap()
        XCTAssertTrue(waitForLabel(row, "北海道、3 回"), "長押しのあとに押して足せない: \(row.label)")
        let before = row.frame.minY
        row.swipeUp()
        XCTAssertLessThan(row.frame.minY, before - 20, "行から上へスワイプしても一覧が動かない")
        // 待ちは 10 秒（Mac 1113 で調べた: スワイプのあと名前は 0〜3 秒ずっと「3 回」のままだが、行が画面の外
        // （minY -136）に出たあとは要素を1回読むのに 3〜5 秒かかった。1101 は 3 秒の待ちの中で1回も読み終わらずに落ちた）
        XCTAssertTrue(waitForLabel(row, "北海道、3 回", timeout: 10), "スワイプで回数が変わった: \(row.label)")
    }

    /// 要素の読み上げの名前が `text` になるまで待つ（帯の数は押したあとに描き直される）。
    ///
    /// 2026-11-13 判断（値取り・待ち時間は変えない）: run 1203 で「一覧の長押しで帯が出ない／回数が変わった: 北海道、2 回」と落ちた。
    /// 3 秒の待ちの中で読めたのは 1 回（探すのに 2.2 秒）で、その値はログに残らず、直後に読み直した値は正しかった。
    /// 原因（アプリの描き直しが遅いのか・読んだ値が古いのか）を決めるため、0.3 秒ごとに読み、読み始めの時刻・
    /// 読むのにかかった秒・在るか・値を `[labelWait]` で記録する（ログの行と XCTest の活動の両方）
    private func waitForLabel(_ element: XCUIElement, _ text: String, timeout: TimeInterval = 3) -> Bool {
        let start = Date()
        var reads: [String] = []
        var matched = false
        while true {
            let readStart = Date().timeIntervalSince(start)
            // 無い要素の `label` を読むと試験が落ちるので、先に在るかを見る
            let exists = element.exists
            let label = exists ? element.label : "-"
            let took = Date().timeIntervalSince(start) - readStart
            reads.append(String(format: "t=%.2f took=%.2f exists=%@ got=%@", readStart, took, exists ? "1" : "0", label))
            if exists, label == text { matched = true; break }
            if Date().timeIntervalSince(start) >= timeout { break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        let line = "[labelWait] want=\(text) ok=\(matched) timeout=\(timeout) reads=\(reads.count): "
            + reads.joined(separator: " | ")
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        return matched
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
        let launched = Date()
        app.launch()
        agreeToTerms(app, since: launched)
        return app
    }

    /// 規約の同意を押し、**同意の画面が消えるまで**確かめる（2026-10-22 run 686: 部屋の試験で、落ちた時の画面の木が
    /// 同意の画面のままだった。30 秒で出なかった・押しても消えなかった、のどちらでも黙って先へ進み、20 秒後に
    /// 「キャンピングカーの画面が開かない」と別の所で落ちていた）。何秒で出て何回押したかを注記に残す
    private func agreeToTerms(_ app: XCUIApplication, since launched: Date = Date(), timeout: TimeInterval = 60) {
        let agree = app.buttons["legal.agree"]
        guard agree.waitForExistence(timeout: timeout) else {
            note(app, "規約の同意", "起動から \(Int(Date().timeIntervalSince(launched))) 秒で同意の画面が出ない")
            return
        }
        let shown = Date().timeIntervalSince(launched)
        var taps = 0
        while agree.exists, taps < 3 {
            if agree.isHittable { agree.tap() } else { agree.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            taps += 1
            let gone = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: agree)], timeout: 5)
            if gone == .completed { break }
        }
        if agree.exists || taps > 1 || shown > 20 {
            note(app, "規約の同意", "同意の画面が出るまで \(String(format: "%.1f", shown)) 秒・押した回数 \(taps)・まだ出ている \(agree.exists)")
        }
        XCTAssertFalse(agree.exists, "規約の同意を押しても同意の画面が消えない（押した回数 \(taps)）")
    }

    /// 道をたどれなかった時の手がかり（画面の絵と画面の木）を残す
    private func note(_ app: XCUIApplication, _ title: String, _ text: String) {
        print("UINOTE \(title): \(text)")
        let line = XCTAttachment(string: text + "\n\n" + app.debugDescription)
        line.name = "注記（\(title)）"
        line.lifetime = .keepAlways
        add(line)
        shoot(app, "注記（\(title)）の画面")
    }

    /// マイページ → 旅の記録のタブ → 「旅のトランク」の行。開けたら true
    private func openTrunk(_ app: XCUIApplication) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return false }
        tabBar.buttons.element(boundBy: 4).tap()
        guard selectTripsTab(app) else { return false }
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

    /// マイページの「旅の記録」のタブを選ぶ。選べたら true。
    ///
    /// 2026-10-21（PR #354 の Mac・録画で確認）: マイページは開いた直後に見出し（カバー・名前・数）が後から読み込まれて
    /// 下へ伸び、タブの列が 150pt ほど動く。動いている最中に押すと空振りし、「旅の記録」が選ばれないまま
    /// 「旅のトランク」の行を待って落ちていた（`testCapturesTrunkOpen` の「旅のトランクを開けない」）。
    /// **位置が止まってから押し、選ばれたかを確かめ、選ばれなければ押し直す**（3回まで）
    private func selectTripsTab(_ app: XCUIApplication) -> Bool {
        let tripsTab = app.buttons["profile.tab.trips"].firstMatch
        guard tripsTab.waitForExistence(timeout: 15) else { return false }
        for _ in 0..<3 {
            // 位置が 1 秒止まるまで待つ（見出しの読み込みで動く間は押さない・最長 10 秒）
            var last = tripsTab.frame
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 1)
                let now = tripsTab.frame
                if now == last { break }
                last = now
            }
            var pushes = 0
            while !tripsTab.isHittable, pushes < 4 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                pushes += 1
            }
            guard tripsTab.isHittable else { return false }
            tripsTab.tap()
            let selected = NSPredicate(format: "selected == true")
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: tripsTab)], timeout: 3) == .completed {
                return true
            }
        }
        return false
    }

    // MARK: - 写真で作るキャンピングカー（2026-10-18・札 #307）

    /// マイページ → 旅の記録のタブ → 「写真で作るキャンピングカー」の行。開けたら true
    private func openCamper(_ app: XCUIApplication) -> Bool {
        guard openTripsRow(app, "trips.camper") else { return false }
        return app.descendants(matching: .any)["camper.scene"].firstMatch.waitForExistence(timeout: 15)
    }

    /// マイページ → 旅の記録のタブ → 行 `id` を押す。押せたら true
    private func openTripsRow(_ app: XCUIApplication, _ id: String) -> Bool {
        // 同意の画面がまだ（また）出ていたら、ここで押して記録する（run 686 は同意の画面のまま 20 秒待って落ちた）
        if app.buttons["legal.agree"].exists {
            note(app, "規約の同意", "旅の記録を開く時に同意の画面が出ている")
            agreeToTerms(app, timeout: 5)
        }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else {
            note(app, "旅の記録の行 \(id)", "下の札（タブ）が出ない")
            return false
        }
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
        // SwiftUI の NavigationLink は iOS/Xcode の組み合わせによって buttons ではなく
        // otherElements として公開されることがある。識別子を付けた行そのものを型に依存せず探す。
        let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
        // 🔴 旅の記録のタブが「読み込み中」のまま 15 秒を越えることがある（PR #390 の検証 run 728・2026-10-28）。
        // 長めに待ち、出なければタブを押し直してもう一度待つ（`TripsTabWait`・`CriticalFlowTests` と共通）
        let shown = TripsTabWait.waitForRow(row, tripsTab: tripsTab) {
            note(app, "旅の記録の行 \(id)", "\(Int(TripsTabWait.firstWait)) 秒待っても \(id) が出ない。タブを押し直す")
        }
        guard shown else {
            note(app, "旅の記録の行 \(id)", "旅の記録のタブに \(id) が出ない")
            return false
        }
        // 行の上の旅の棚・端末の一冊・旅のトランクの行は、読み終えた順に後から出て行を押し下げる（2026-10-22 run 672・684:
        // 5 回送っても行に届かなかった）。行が画面の下の帯より上で、0.5 秒動かなくなるまで送る（10 回まで）
        let bottom = app.windows.firstMatch.frame.maxY - 100
        pushes = 0
        while pushes < 10 {
            // 🔴 送っている間に、行の上の札（旅の一冊など）が押されて別の画面へ移ることがある（PR #390 の検証 2026-10-28:
            // 大きい文字で「山中湖の旅」の頁に移り、`row.frame` が「見つからない」で落ちた。10/27 run 40520085031 も同じ）。
            // 行が消えて戻るボタンがあれば、戻ってから探し直す（消えたまま frame を読まない）
            if !row.exists {
                let back = app.navigationBars.buttons["BackButton"].firstMatch
                guard back.exists else { break }
                note(app, "旅の記録の行 \(id)", "送っている間に別の画面へ移った。戻って探し直す")
                back.tap()
                guard row.waitForExistence(timeout: 10) else { break }
                pushes += 1
                continue
            }
            let before = row.frame
            Thread.sleep(forTimeInterval: 0.5)
            guard row.exists else { continue }
            if row.isHittable, row.frame == before, row.frame.maxY < bottom, row.frame.minY > 80 { break }
            if row.frame.minY <= 80 { app.swipeDown() } else if row.frame.maxY >= bottom || !row.isHittable { app.swipeUp() }
            Thread.sleep(forTimeInterval: 0.8)
            pushes += 1
        }
        guard row.exists, row.isHittable else {
            note(app, "旅の記録の行 \(id)", "\(pushes) 回送っても \(id) を押せない（\(row.exists ? "\(row.frame)" : "行が無い")）")
            return false
        }
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

    /// **とおまわり号の灯り**（2026-10-19 owner「テールランプとかの灯りが不自然すぎる」）: 夜の後ろ斜め（尾灯が見える・
    /// 分類「横・後ろ」の寄り）と、夜の前の寄り（分類「前照灯」の寄り）、昼の後ろ斜め。**必ず撮る**（開けなければ落とす）
    func testCapturesCamperLamps() {
        let app = launchTrunk([])
        XCTAssertTrue(openCamper(app), "キャンピングカーの画面が開かない")
        guard waitCamper(app, "camper-ready") else { return XCTFail("キャンピングカーを組み終えない") }
        // 分類のボタンを押すと、その部品へ寄る（`CamperFraming.focus`）。下の欄を送ってから押すので、寄りは押した後に決まる
        // 分類の行は横に並び、画面の外に隠れる（Mac run 563: 前照灯が右の外にあり押せなかった）。縦に送ってから、
        // 行のうち見えているボタンの上で左へ少しずつ引いて探す
        func aim(_ ids: [String]) -> Bool {
            for id in ids {
                let b = app.buttons[id].firstMatch
                guard b.waitForExistence(timeout: 5) else { return false }
                scrollTo(b, in: app)
                var drags = 0
                while !b.isHittable, drags < 8 {
                    let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camper.category.'"))
                    guard let visible = (0..<row.count).map({ row.element(boundBy: $0) }).first(where: { $0.isHittable }) else { break }
                    let start = visible.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -140, dy: 0)))
                    Thread.sleep(forTimeInterval: 1)
                    drags += 1
                }
                guard b.isHittable else { return false }
                b.tap()
            }
            Thread.sleep(forTimeInterval: 2)
            return true
        }
        let night = app.buttons["camper.mood.night"].firstMatch
        guard night.waitForExistence(timeout: 5) else { return XCTFail("夜のボタンが無い") }
        night.tap()
        waitCamper(app, "night")
        guard aim(["camper.group.side"]) else { return XCTFail("横・後ろの分類が押せない") }
        shoot(app, "95k-キャンピングカー（夜・後ろ斜め・尾灯）")
        guard aim(["camper.group.ext", "camper.category.headlight"]) else { return XCTFail("前照灯の分類が押せない") }
        shoot(app, "95l-キャンピングカー（夜・前の寄り）")
        // 下の欄を上へ戻す（車の絵の上で引くと向きが回るので、画面の下の方で引く）
        let day = app.buttons["camper.mood.day"].firstMatch
        var pulls = 0
        while !(day.exists && day.isHittable), pulls < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            Thread.sleep(forTimeInterval: 1)
            pulls += 1
        }
        guard day.isHittable else { return XCTFail("昼のボタンに戻れない") }
        day.tap()
        waitCamper(app, "day")
        guard aim(["camper.group.side"]) else { return XCTFail("横・後ろの分類が押せない（昼）") }
        shoot(app, "95m-キャンピングカー（昼・後ろ斜め・尾灯）")
        // バン（段 1）とトレーラーつきの夜（2026-10-21: 前照灯を消したので、外の置き物が無いと車体が沈まないかを見る）。
        // 段のボタンは見本の段で、押すと初めの向きへ戻る
        pulls = 0
        while !(night.exists && night.isHittable), pulls < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            Thread.sleep(forTimeInterval: 1)
            pulls += 1
        }
        guard night.isHittable else { return XCTFail("夜のボタンに戻れない") }
        night.tap()
        waitCamper(app, "night")
        for (id, name) in [("van", "95n-キャンピングカー（バン・夜）"), ("trailer", "95o-キャンピングカー（トレーラーつき・夜）")] {
            let b = app.buttons["camper.stage.\(id)"].firstMatch
            guard b.waitForExistence(timeout: 5) else { return XCTFail("\(id) の段のボタンが無い") }
            scrollTo(b, in: app)
            guard b.isHittable else { return XCTFail("\(id) の段のボタンが押せない") }
            b.tap()
            guard waitCamper(app, "camper-ready \(id) night") else { return XCTFail("\(id) の夜を組み終えない") }
            shoot(app, name)
        }
        // 雪（2026-10-21: 夜の作り直しで共に使う部品を変えたので、雪の見た目が変わっていないかを見る）
        let snow = app.buttons["camper.mood.snow"].firstMatch
        pulls = 0
        while !(snow.exists && snow.isHittable), pulls < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            Thread.sleep(forTimeInterval: 1)
            pulls += 1
        }
        guard snow.isHittable else { return XCTFail("雪のボタンに戻れない") }
        snow.tap()
        waitCamper(app, "snow")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "95r-キャンピングカー（トレーラーつき・雪）")
    }

    /// 画面写真の縦の帯（0〜1）の平均の明るさ（0〜255・16×16 に縮めて測る）。暗い画面を見分ける
    static func meanBrightness(_ image: UIImage, band: ClosedRange<Double>) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let h = Double(cg.height)
        let rect = CGRect(x: 0, y: h * band.lowerBound, width: Double(cg.width), height: h * (band.upperBound - band.lowerBound))
        guard let part = cg.cropping(to: rect) else { return 0 }
        let side = 16
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            sum += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
        }
        return sum / Double(side * side)
    }

    /// **外から中に入るときの光**（2026-10-21 owner「中に入るボタン押した時に扉開くけど中の光で眩しすぎてほんとにダメ」
    /// 「外から中に入る時の光もほんとにダメ」）: 夜と昼に「中に入る」を押し、扉が開く途中・開いた所・口へ寄っている途中・
    /// 部屋に切り替わる直前と直後を**必ず撮る**（開けない・入れないなら落とす）。動きは見本の起動で 6 倍ゆっくり
    /// （`-JPPreviewCamperEnterSlow 6`: 扉 3.6 秒・寄り 2.7 秒から 3.6 秒・切り替え 6.3 秒）
    func testCapturesCamperEntering() {
        executionTimeAllowance = 600
        let app = launchTrunk(["-JPPreviewCamperEnterSlow", "6", "-JPPreviewCamperRoomReset", "YES"])
        XCTAssertTrue(openCamper(app), "キャンピングカーの画面が開かない")
        guard waitCamper(app, "camper-ready") else { return XCTFail("キャンピングカーを組み終えない") }
        for (mood, label) in [("night", "夜"), ("day", "昼")] {
            let moodButton = app.buttons["camper.mood.\(mood)"].firstMatch
            guard moodButton.waitForExistence(timeout: 5) else { return XCTFail("\(label)のボタンが無い") }
            if !moodButton.isHittable { scrollTo(moodButton, in: app) }
            moodButton.tap()
            waitCamper(app, mood)
            Thread.sleep(forTimeInterval: 1)
            let enter = app.buttons["camper.room.enter"].firstMatch
            guard enter.waitForExistence(timeout: 5), enter.isHittable else { return XCTFail("「中に入る」が押せない（\(label)）") }
            let start = Date()
            enter.tap()
            // 押してからの秒で撮る（撮るのに 0.3〜0.6 秒かかるので、少し前に合わせる）
            func shoot(at seconds: Double, _ name: String) {
                let wait = seconds - Date().timeIntervalSince(start)
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                self.shoot(app, name)
            }
            let n = mood == "night" ? "p" : "q"
            shoot(at: 0.9, "95\(n)1-キャンピングカー（\(label)・中に入る・扉が開く途中）")
            shoot(at: 2.5, "95\(n)2-キャンピングカー（\(label)・中に入る・扉が開いた）")
            shoot(at: 4.3, "95\(n)3-キャンピングカー（\(label)・中に入る・口へ寄る途中）")
            shoot(at: 5.8, "95\(n)4-キャンピングカー（\(label)・中に入る・切り替わる直前）")
            let room = app.descendants(matching: .any)["camper.room.scene"].firstMatch
            guard room.waitForExistence(timeout: 15) else { return XCTFail("部屋に切り替わらない（\(label)）") }
            // 切り替わった直後: 部屋が組み上がるまで、寄った口の絵が覆う（暗い画面にしない・確かめ役 2026-10-21）
            let cover = app.descendants(matching: .any)["camper.room.entryCover"].firstMatch
            let covered = cover.exists
            // SwiftUI が部屋の画面をアクセシビリティ階層へ公開した直後は、最初のフレームが
            // まだ合成されておらず、遷移中の黒い一枚を取得することがある。覆いの表示を
            // 最大 2 秒だけ待ってから撮る（長い待ちで本物の暗転を隠さない）。
            var first = app.screenshot()
            let coverDeadline = Date().addingTimeInterval(2)
            while Self.meanBrightness(first.image, band: 0.2...0.55) <= 20, Date() < coverDeadline {
                Thread.sleep(forTimeInterval: 0.2)
                first = app.screenshot()
            }
            self.shoot(app, "95\(n)5-キャンピングカー（\(label)・中に入る・部屋に切り替わった直後）")
            XCTAssertGreaterThan(Self.meanBrightness(first.image, band: 0.2...0.55), 20,
                                 "部屋に切り替わった直後が暗い画面（\(label)・寄った口の絵の覆い: \(covered ? "あり" : "無し")・2 秒待機後）")
            XCTAssertTrue(waitRoom(app, "camper.room.scene", "camper-room-ready"), "部屋を組み終えない（\(label)）")
            // 組み上がった合図は SceneKit に載せた時点で、描くのはその後（`CamperRoomSceneView.onDrawn`）。
            // 部屋が描かれて明るくなるまで最長 30 秒待って撮る。2026-10-22 PR #369 の検証（run 39773377293）: 込んだ Mac で、部屋の
            // 画面が出るまで 11 秒・アプリの応答が 16 秒止まり、覆いの 20 秒の待ちが切れた直後の、まだ描かれていない暗い地を
            // 合図の直後に撮っていた（部屋の家具の網は main と同じ・`CamperRoomScenePlan.make` の三角形 82,130 で同じ）
            var settled = app.screenshot()
            let drawnBy = Date().addingTimeInterval(30)
            while Self.meanBrightness(settled.image, band: 0.2...0.55) <= 20, Date() < drawnBy {
                Thread.sleep(forTimeInterval: 1)
                settled = app.screenshot()
            }
            self.shoot(app, "95\(n)6-キャンピングカー（\(label)・中に入る・部屋が組み上がった）")
            XCTAssertGreaterThan(Self.meanBrightness(settled.image, band: 0.2...0.55), 20, "部屋が組み上がっても暗い画面（\(label)）")
            // 外へ戻り、扉を閉じて（初めの向きへ戻る）次の時刻へ
            let back = app.buttons["camper.room.back"].firstMatch
            guard back.waitForExistence(timeout: 10) else { return XCTFail("部屋から外へ戻れない") }
            back.tap()
            let door = app.buttons["camper.door"].firstMatch
            // main の run（39739874666）で 10 秒待っても外の車に戻らなかった。押しが届かなかった時は 1 回だけ押し直し、
            // それでも戻らなければ画面の木を残して落とす
            if !door.waitForExistence(timeout: 10), back.exists {
                note(app, "外へ戻る", "「外へ」を押して 10 秒たっても外の車に戻らない。押し直す")
                back.tap()
            }
            guard door.waitForExistence(timeout: 10) else {
                note(app, "外へ戻る", "外の車に戻らない")
                return XCTFail("外の車に戻らない")
            }
            // 戻ったら口の真正面の寄りではなく、扉の口を斜めに見る向き（確かめ役 2026-10-21）
            Thread.sleep(forTimeInterval: 4)
            self.shoot(app, "95\(n)7-キャンピングカー（\(label)・部屋から戻った）")
            door.tap()
            Thread.sleep(forTimeInterval: 4)
        }
    }

    /// 旅のトランクの入口は ≡ メニューの「旅の楽しみ」（2026-11-12・案 第10章。前は設定の「旅の道具」）。
    /// 古い UI の期待値（mypage.trunk・settings.trunk）を復活させず、現行の入口が操作可能なことを確認する。
    func testCapturesTrunkEntry() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewTrunkCoins", "3"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return XCTFail("下の札が出ない") }
        tabBar.buttons.element(boundBy: 4).tap()

        let obsoleteCard = app.buttons["mypage.trunk"].firstMatch
        XCTAssertFalse(obsoleteCard.waitForExistence(timeout: 3), "マイページに削除済みの旅のトランク札が残っている")

        // ≡ は見出し（`AppHeaderItems`・ホーム・探す・地図）にある。ログイン中のマイページは上のバーを出さない
        // （`MyPageView` の `.toolbar(.hidden)`）ので、ホームへ戻ってから押す（Mac run 1162 でマイページの上に ≡ が無く落ちた・
        // `CriticalFlowTests.testSignOutThenSignInReturnsToMyPage` と同じ道）
        tabBar.buttons.element(boundBy: 0).tap()
        let menu = app.buttons["header.menu"].firstMatch
        guard menu.waitForExistence(timeout: 10) else { return XCTFail("見出しにメニューが無い") }
        menu.tap()
        let row = app.buttons["menu.trunk"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return XCTFail("メニューに旅のトランクの行が無い") }
        scrollTo(row, in: app)
        guard row.isHittable else { return XCTFail("メニューの旅のトランクの行に届かない") }
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "メニューの旅のトランクの行が 44pt 未満")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "90a-メニュー（旅のトランク入口）")
        row.tap()
        guard app.descendants(matching: .any)["trunk.spin"].firstMatch.waitForExistence(timeout: 15) else {
            return XCTFail("メニューの旅のトランクの行を押してもトランクが開かない")
        }
    }

    /// **≡ メニューの置き場**（2026-11-12・デザインの案 第10章「どこに何を置くか」）: 旅の準備・旅の楽しみ・ほか。
    /// タブと重なる行（撮影地マップ・マイページ・保存）は無い。見本（`-JPPreviewTrunk`）ではトランクの行が必ず出るので、
    /// 出なければ落とす。とおまわり号の行を押すと車の画面が開く
    func testCapturesSiteMenuTools() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewTrunkCoins", "3", "-JPPreviewPass", "YES"])
        let menu = app.buttons["header.menu"].firstMatch
        guard menu.waitForExistence(timeout: 20) else { return XCTFail("見出しにメニューが無い") }
        menu.tap()
        let plans = app.buttons["menu.tripPlans"].firstMatch
        guard plans.waitForExistence(timeout: 10) else { return XCTFail("メニューに旅行プランの行が無い") }
        for id in ["menu.map", "menu.saved"] {
            XCTAssertFalse(app.buttons[id].firstMatch.exists, "タブと重なる \(id) が残っている")
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "102m-メニュー（旅の準備）")
        let camper = app.buttons["menu.camper"].firstMatch
        guard camper.waitForExistence(timeout: 10) else { return XCTFail("メニューにとおまわり号の行が無い") }
        scrollTo(camper, in: app)
        for id in ["menu.tripPlans", "menu.albums", "menu.lightForecast", "menu.pass", "menu.trunk", "menu.camper"] {
            let row = app.buttons[id].firstMatch
            XCTAssertTrue(row.exists, "メニューに \(id) が無い")
            if row.exists { XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(id) が 44pt 未満") }
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "102n-メニュー（旅の楽しみ）")
        if camper.isHittable {
            camper.tap()
            XCTAssertTrue(app.descendants(matching: .any)["camper.scene"].firstMatch.waitForExistence(timeout: 15),
                          "メニューのとおまわり号の行を押しても車の画面が開かない")
        }
    }

    /// **設定の並び**（2026-10-18 owner「設定の項目多くなってるのでわかりやすいように整理して」）: いちばん上・
    /// 公開範囲とプライバシー（すれちがい乗車券）・最後の危ない操作・下の画面（データとストレージ・トランクを見せる）。
    /// 2026-11-12: 旅の道具は ≡ メニューへ（`testCapturesSiteMenuTools`）。押せる行が 44pt 未満なら落とす
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
        let push = app.descendants(matching: .any)["settings.push"].firstMatch
        guard push.waitForExistence(timeout: 10) else { return XCTFail("設定が開かない") }
        // 2026-11-12（案 第10章）: 「旅の道具」の節は ≡ メニューへ移した。設定に残っていないこと
        for id in ["settings.trunk", "settings.camper", "settings.passBook", "settings.albums", "settings.plans"] {
            XCTAssertFalse(app.buttons[id].firstMatch.exists, "設定に \(id) が残っている（≡ へ移した）")
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "102-設定（いちばん上）")

        // すれちがい乗車券の入り切りは「公開範囲とプライバシー」
        let pass = app.buttons["settings.pass"].firstMatch
        guard pass.waitForExistence(timeout: 5) else { return XCTFail("設定にすれちがい乗車券の行が無い") }
        scrollTo(pass, in: app)
        XCTAssertGreaterThanOrEqual(pass.frame.height, 44, "settings.pass が 44pt 未満")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "102a-設定（公開範囲とプライバシー）")

        // 公開範囲とプライバシー: 「検索エンジンにプロフィールを表示しない」（2026-11-11 owner 承認・#526）。
        // 自分のプロフィールが読めているときだけ出る行なので、出なければ撮らずに先へ（撮れないのを失敗にしない）
        let searchHidden = app.descendants(matching: .any)["settings.searchHidden"].firstMatch
        if searchHidden.waitForExistence(timeout: 5) {
            scrollTo(searchHidden, in: app)
            XCTAssertGreaterThanOrEqual(searchHidden.frame.height, 44, "検索エンジンの入切が 44pt 未満")
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "102g-設定（公開範囲とプライバシー）")
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
        Thread.sleep(forTimeInterval: 1)

        // ヘルプと規約のいちばん上の「使い方」（2026-11-12 札 #517）。行は必ずある——無ければ落とす。
        // 押すとアプリの中の Safari で /help が開く。開いた窓は撮るだけ（試験の機械から本番のサイトが読めるとは限らない）
        let help = app.buttons["settings.help"].firstMatch
        guard help.waitForExistence(timeout: 5) else { return XCTFail("設定に「使い方」の行が無い") }
        var toHelp = 0
        while !help.isHittable || help.frame.maxY > app.windows.firstMatch.frame.maxY - 60, toHelp < 10 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            toHelp += 1
        }
        guard help.isHittable else { return XCTFail("「使い方」の行に届かない") }
        XCTAssertGreaterThanOrEqual(help.frame.height, 44, "「使い方」の行が 44pt 未満")
        let whatsNew = app.buttons["settings.whatsNew"].firstMatch
        if whatsNew.exists { XCTAssertLessThan(help.frame.minY, whatsNew.frame.minY, "「使い方」がヘルプと規約のいちばん上に無い") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "102h-設定（使い方）")
        help.tap()
        Thread.sleep(forTimeInterval: 4)
        shoot(app, "102i-使い方（アプリの中の Safari）")
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
    /// 出たのに3つの手が無い・44pt 未満・「あとで貼る（手持ちへ）」で閉じなければ落とす
    func testCapturesTrunkArrived() {
        let app = launchTrunk(["-JPPreviewTrunkArrived", "YES"])
        let stick = app.buttons["trunk.arrived.stick"].firstMatch
        guard stick.waitForExistence(timeout: 30) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "96-ラベルが届いた")
        // 静かな祝い（2026-11-08・案 A）: 動きのあと、事実の一文が出ている（見本は「京都、はじめての1枚です」）
        let fact = app.staticTexts["trunk.arrived.fact"].firstMatch
        XCTAssertTrue(fact.exists, "ラベルが届いた画面に、事実の一文が出ていない")
        XCTAssertTrue(fact.label.contains("はじめて") || fact.label.lowercased().contains("first"), "一文が「はじめて」を言っていない: \(fact.label)")
        let keep = app.buttons["trunk.arrived.keep"].firstMatch
        let reroll = app.buttons["trunk.arrived.reroll"].firstMatch
        let close = app.buttons["trunk.arrived.close"].firstMatch
        for (button, name) in [(stick, "トランクに貼る"), (keep, "あとで貼る（手持ちへ）"), (reroll, "図柄を作り直す"), (close, "閉じる")] {
            XCTAssertTrue(button.exists, "「\(name)」が無い")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "「\(name)」が 44pt 未満")
        }
        guard keep.isHittable else { return XCTFail("「あとで貼る（手持ちへ）」を押せない") }
        keep.tap()
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: stick)], timeout: 5)
        XCTAssertEqual(closed, .completed, "「あとで貼る（手持ちへ）」で閉じない")
        // 閉じたあとに、また出てこない（見本は起動から1回だけ・`TrunkArrivals.claimPreviewOffer`・2026-10-21）
        Thread.sleep(forTimeInterval: 4)
        XCTAssertFalse(stick.exists, "「あとで貼る（手持ちへ）」で閉じたあと、届いた画面がまた出た")
    }

    /// **ラベルが3枚届いた**（`-JPPreviewTrunkArrived 3`・2026-11-12 判断・1.1.83 の案）: 主ボタンは「3 枚まとめて貼る」1回。
    /// 押すと閉じ、知らせに「取り消す」が出る。出なければ撮らずに抜けるが、出たのに主ボタンが「まとめて」でない・
    /// 取り消しが出ないなら落とす
    func testCapturesTrunkArrivedMany() {
        let app = launchTrunk(["-JPPreviewTrunkArrived", "3"])
        let stick = app.buttons["trunk.arrived.stick"].firstMatch
        guard stick.waitForExistence(timeout: 30) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "96f-ラベルが届いた（3 枚まとめて）")
        XCTAssertTrue(stick.label.contains("3"), "主ボタンが「3 枚まとめて貼る」でない: \(stick.label)")
        XCTAssertGreaterThanOrEqual(stick.frame.height, 44)
        guard stick.isHittable else { return XCTFail("「まとめて貼る」を押せない") }
        stick.tap()
        let undo = app.buttons["toast.undo"].firstMatch
        guard undo.waitForExistence(timeout: 10) else { return XCTFail("まとめて貼ったあとに「取り消す」が出ない") }
        shoot(app, "96g-まとめて貼った（取り消す）")
        XCTAssertGreaterThanOrEqual(undo.frame.height, 44, "「取り消す」が 44pt 未満")
        undo.tap()
    }

    /// **近くの写真**（2026-11-12 判断・1.1.83 の案）: 系統の List をやめ、写真の 3 列の格子・範囲の丸チップ・白の「閉じる」。
    /// 現在地（パリ）を渡してマップを開き、「近くの写真」が出なければ撮らずに抜ける（現在地が取れない回がある）。
    /// 出たのに範囲のチップ・閉じるが無い・44pt 未満なら落とす
    func testCapturesNearbyPhotos() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 3 else { return }
        simulateLocation()
        tabBar.buttons.element(boundBy: 3).tap()
        let nearby = app.buttons["map.nearby"].firstMatch
        guard nearby.waitForExistence(timeout: 20), nearby.isHittable else { return }
        nearby.tap()
        let close = app.buttons["nearby.close"].firstMatch
        guard close.waitForExistence(timeout: 10) else { return XCTFail("近くの写真の「閉じる」が無い") }
        // 写真の絵が描かれるのを待つ（枠だけの絵を「壊れている」と読み違えない）
        Thread.sleep(forTimeInterval: 4)
        shoot(app, "13i-近くの写真（格子）")
        XCTAssertGreaterThanOrEqual(close.frame.height, 44, "「閉じる」が 44pt 未満")
        for km in [5, 10, 50] {
            let chip = app.buttons["nearby.radius.\(km)"].firstMatch
            XCTAssertTrue(chip.exists, "範囲のチップ「約\(km)km」が無い")
            XCTAssertGreaterThanOrEqual(chip.frame.height, 43.99, "範囲のチップ「約\(km)km」の当たりが 44pt 未満")
        }
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "灰のセグメントが残っている")
        close.tap()
    }

    /// **はじめてのいいね**（お知らせ・`-JPPreviewFirstReaction`・2026-11-08・案 A）。見本の行は必ず出るが、
    /// お知らせが開けなければ撮らずに抜ける。出たのに「はじめて」の一言が無いなら落とす
    func testCapturesFirstReaction() {
        let app = launchTrunk(["-JPPreviewFirstReaction", "YES"])
        let bell = app.buttons["header.notifications"].firstMatch
        guard bell.waitForExistence(timeout: 30), bell.isHittable else { return }
        bell.tap()
        let mark = app.descendants(matching: .any)["notifications.firstReaction"].firstMatch
        guard mark.waitForExistence(timeout: 20) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "96e-はじめてのいいね（お知らせ）")
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'はじめて'")).firstMatch
        XCTAssertTrue(note.exists, "「はじめて」の一言が出ていない")
        let close = app.buttons["notifications.close"].firstMatch
        if close.exists, close.isHittable { close.tap() }
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

    /// **貼り替えた後のトランク**（2026-10-19 の直し・owner「取って付け替えたときに、空洞のところが空洞になっていない」）:
    /// 見本（`-JPPreviewTrunk`・Debug のみ）の置き場なし9枚の真ん中（並びの5番目＝おまかせの置き場 0）を選んで
    /// はがす → はがした所が空いたまま（ほかはずれない）→ 手持ちから同じ所へ運んで貼り直す。見本は必ず出るので、
    /// 出なければ落とす（必ず撮る）
    func testCapturesTrunkStickSwap() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewPro", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.stick.open") else { return XCTFail("「ラベルを貼る」の入口が無い") }
        let done = app.buttons["trunk.stick.done"].firstMatch
        guard done.waitForExistence(timeout: 10) else { return XCTFail("貼る画面が開かない") }
        let trunk = app.descendants(matching: .any)["trunk.stick.trunk"].firstMatch
        guard trunk.waitForExistence(timeout: 5) else { return XCTFail("トランクが無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "97d-ラベルを貼る（貼り替える前）")
        // おまかせの置き場 0（胴の 150,120 から 108×72）の真ん中。絵は 360×300 で、胴は上から 32
        let hole = trunk.coordinate(withNormalizedOffset: CGVector(dx: 204.0 / 360, dy: (32 + 156.0) / 300))
        hole.tap()
        Thread.sleep(forTimeInterval: 1)
        let peel = app.buttons["trunk.stick.peel"].firstMatch
        guard peel.isHittable else { return XCTFail("「はがして手持ちに戻す」が押せない") }
        peel.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "97e-ラベルを貼る（はがした所が空いた）")
        // はがした1枚は手持ちのいちばん上。持ち上げは指の 18pt 上に出るので、その分下へ運ぶ
        let cell = app.buttons.matching(identifier: "trunk.stick.tray").firstMatch
        guard cell.waitForExistence(timeout: 5) else { return XCTFail("手持ちの札が無い") }
        let from = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.3, thenDragTo: hole.withOffset(CGVector(dx: 0, dy: 18)))
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "97f-ラベルを貼る（貼り替えた後のトランク）")
        XCTAssertTrue(app.buttons["trunk.stick.undo"].firstMatch.isEnabled, "貼り替えたのに「ひとつ戻す」が押せない")
        done.tap()
    }

    /// **カプセルの機械**: 「硬貨を入れて回す」1つでハンドルが自分で1周 → カプセルを開ける → 中身と確率
    /// （2026-11-12 判断・1.1.83 の案: 入れる → 回す → 開ける → 付けるの 4 回が 3 回に）
    func testCapturesTrunkGacha() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.gacha.open") else { return XCTFail("カプセルの機械の入口が無い") }
        let insert = app.buttons["trunk.gacha.insert"].firstMatch
        guard insert.waitForExistence(timeout: 10) else { return XCTFail("「硬貨を入れる」が無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "98-カプセルの機械")
        XCTAssertGreaterThanOrEqual(insert.frame.height, 44, "「硬貨を入れて回す」が 44pt 未満")
        let crank = app.buttons["trunk.gacha.crank"].firstMatch
        XCTAssertTrue(crank.exists, "ハンドルが無い（指で回しても出る）")
        XCTAssertGreaterThanOrEqual(crank.frame.height, 44, "ハンドルが 44pt 未満")
        insert.tap()
        Thread.sleep(forTimeInterval: 0.4)
        shoot(app, "98-カプセルの機械（回している）")
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

    /// **カプセルの機械（硬貨がありません）**: `-JPPreviewTrunkCoins 0`。回すボタンの代わりに「写真を投稿する」の一手
    /// （2026-11-12 判断・埋め方の一手）。回すボタンが出ていたら落とす
    func testCapturesTrunkGachaNoCoins() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewTrunkCoins", "0"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.gacha.open") else { return XCTFail("カプセルの機械の入口が無い") }
        let post = app.buttons["trunk.gacha.post"].firstMatch
        guard post.waitForExistence(timeout: 10) else { return XCTFail("硬貨 0 で「写真を投稿する」が無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "98c-カプセルの機械（硬貨がありません）")
        XCTAssertGreaterThanOrEqual(post.frame.height, 44, "「写真を投稿する」が 44pt 未満")
        XCTAssertFalse(app.buttons["trunk.gacha.insert"].firstMatch.exists, "硬貨 0 で回すボタンが出ている")
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
        // 小数の誤差まで許す（Mac 1101 の実測 43.99999999999997・タブは minHeight 44 で組む）
        XCTAssertGreaterThanOrEqual(lockTab.frame.height, 43.99, "種類のタブが 44pt 未満")
        lockTab.tap()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "99-部品箱（錠前）")
        // 持っている部品を押すとシートで見て「トランクに付ける」（2026-11-12 判断・付け替えの画面へ行かない）
        let owned = app.buttons.matching(identifier: "trunk.parts.owned").firstMatch
        if owned.exists, owned.isHittable {
            owned.tap()
            let sheetEquip = app.buttons["trunk.partSheet.equip"].firstMatch
            guard sheetEquip.waitForExistence(timeout: 10) else { return XCTFail("持っている部品を押してもシートが出ない") }
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "99j-部品のシート")
            XCTAssertGreaterThanOrEqual(sheetEquip.frame.height, 43.99, "シートの主ボタンが 44pt 未満")
            let close = app.buttons["trunk.partSheet.close"].firstMatch
            if close.exists, close.isHittable { close.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
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
            // 押すたびに保存し、右上の「ひとつ戻す」で戻せる（2026-11-12 判断・保存の確かめはなくした）
            let undo = app.buttons["trunk.equip.undo"].firstMatch
            XCTAssertTrue(undo.waitForExistence(timeout: 5) && undo.isEnabled, "付け替えたのに「ひとつ戻す」が押せない")
            undo.tap()
        }
    }

    /// **手荷物タグを自分で選ぶ**（2026-11-08・札 #501）: トランクの行 → 枠の一覧 → ラベルを選ぶシート → 完了 → タグを外す。
    /// 入口が無ければ落とす
    func testCapturesTrunkTags() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.tags.open") else { return XCTFail("「手荷物タグ」の入口が無い") }
        // 見本の投稿は 42 件＝吊るせるタグは1枚（50 件で2枚目）。1枠目だけが押せる行で、2枠目以降は押せない行（Button ではない）
        let slot = app.buttons["trunk.tags.slot.0"].firstMatch
        guard slot.waitForExistence(timeout: 10) else { return XCTFail("手荷物タグの画面が開かない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "99t-手荷物タグ")
        XCTAssertTrue(app.descendants(matching: .any)["trunk.tags.slot.1"].firstMatch.exists, "まだ吊るせない枠の行が無い")
        XCTAssertFalse(app.buttons["trunk.tags.slot.1"].firstMatch.exists, "まだ吊るせない枠が押せる")
        XCTAssertGreaterThanOrEqual(slot.frame.height, 44, "枠の行が 44pt 未満")
        slot.tap()
        let done = app.buttons["trunk.tags.done"].firstMatch
        guard done.waitForExistence(timeout: 10) else { return XCTFail("載せるラベルを選ぶシートが開かない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "99u-手荷物タグ（載せるラベルを選ぶ）")
        for id in ["trunk.tags.auto", "trunk.tags.remove", "trunk.tags.done"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].firstMatch.frame.height, 44, "\(id) が 44pt 未満")
        }
        // 押せる行（使用中・地名なしは押せない）の最初の1つを選ぶ
        let picks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trunk.tags.pick.' AND enabled == true"))
        if picks.count > 0 {
            let pick = picks.element(boundBy: picks.count - 1)
            XCTAssertGreaterThanOrEqual(pick.frame.height, 44, "ラベルの行が 44pt 未満")
            pick.tap()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "99v-手荷物タグ（ラベルを選んだ）")
        }
        done.tap()
        guard slot.waitForExistence(timeout: 10) else { return XCTFail("完了のあとに枠の一覧へ戻らない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "99w-手荷物タグ（選んだあと）")
        slot.tap()
        let remove = app.buttons["trunk.tags.remove"].firstMatch
        guard remove.waitForExistence(timeout: 10) else { return XCTFail("シートが開き直せない") }
        remove.tap()
        guard slot.waitForExistence(timeout: 10) else { return XCTFail("タグを外したあとに枠の一覧へ戻らない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "99x-手荷物タグ（タグを外した）")
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
            // 「硬貨を入れて回す」1つでハンドルが自分で1周する（2026-11-12 判断）
            insert.tap()
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
    /// トランクの中身を押して手に取る（持ち上がって出口「trunk.hold.go」が出るまで）。
    ///
    /// 🔴 2026-10-31 Mac run 41158764882 の `testCapturesTheirTrunk`: ふたが開き切って 10 秒たった会員証を押した記録は
    /// あるのに、録画でも画面の木でも何も持ち上がらず「会員証を押しても持ち上がらない」で落ちた（同じアプリの
    /// 3b1103c の回は通っている）。舞台にはふたを引く指（`LidDragPriority` の `highPriorityGesture`）が重なっていて、
    /// 押しがそちらに取られて中のボタンに届かない回があると見られる（根は確かめきれていない）。
    /// **前の出口が消えるのを待ってから押し**（戻した直後の消えかけの出口を「持ち上がった」と見ない）、
    /// 4 秒で持ち上がらず押せる所に残っていれば、押し直したことを記録に残してもう一度だけ押す。それでも出なければ false
    private func pickUp(_ item: XCUIElement, go: XCUIElement, in app: XCUIApplication) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: go)], timeout: 3)
        // 札 #424: 押す直前の見えない要素 `trunk.open.debug` の値（押し直しが要った回の原因を数で見る）
        let pre = trunkDebugValue(app)
        let began = Date()
        item.tap()
        if go.waitForExistence(timeout: 4) {
            notePick(app, item: item, outcome: "ok", pre: pre, since: began)
            return true
        }
        guard item.exists, item.isHittable else {
            let ok = go.waitForExistence(timeout: 6)
            notePick(app, item: item, outcome: ok ? "late" : "failed-unhittable", pre: pre, since: began)
            return ok
        }
        // 🔴 押し直す前の値（この回が「持ち上がらなかった回」）
        notePick(app, item: item, outcome: "missed", pre: pre, since: began)
        XCTContext.runActivity(named: "押しても持ち上がらなかったので押し直す（\(item.identifier)）") { activity in
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "押し直す前（\(item.identifier)）"
            shot.lifetime = .keepAlways
            activity.add(shot)
        }
        item.tap()
        let ok = go.waitForExistence(timeout: 10)
        notePick(app, item: item, outcome: ok ? "retry-ok" : "retry-failed", pre: pre, since: began)
        return ok
    }

    /// 見えない要素 `trunk.open.debug`（`TrunkPickProbe`・`-JPPreviewPerfProbe YES` のときだけ在る）の今の値
    private func trunkDebugValue(_ app: XCUIApplication) -> String {
        guard app.state == .runningForeground else { return "debug が読めない（アプリが前に居ない）" }
        let probe = app.descendants(matching: .any)["trunk.open.debug"].firstMatch
        guard probe.exists else { return "debug が読めない（要素が無い）" }
        return (probe.value as? String) ?? "debug が読めない（値が無い）"
    }

    /// 押した結果を1行で残す（ログ・活動の名前・添付）。`PERF-TRUNK` で引く
    private func notePick(_ app: XCUIApplication, item: XCUIElement, outcome: String, pre: String, since: Date) {
        let ms = Int(Date().timeIntervalSince(since) * 1000)
        if outcome != "ok" { pickMisses += 1 }
        let post = trunkDebugValue(app)
        let line = "PERF-TRUNK test=\(perfTestName) item=\(item.identifier) outcome=\(outcome) afterMs=\(ms)"
            + " hittable=\(item.exists && item.isHittable) PRE{\(pre)} POST{\(post)}"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        if outcome != "ok" {
            let att = XCTAttachment(string: line)
            att.name = "trunk.open.debug \(outcome)（\(item.identifier)）"
            att.lifetime = .keepAlways
            add(att)
        }
    }

    /// 押して持ち上がらなかった回の数（`notePick`・`testTrunkPickRepeat` が最後に見る）
    private var pickMisses = 0

    /// **札 #424 の測り**: 開いたふたの中身を押す。新しく起動して → 開けて → 会員証・メダル・「ほか N」を戻しながら押す、を
    /// `rounds` 回。押す前の待ちは回ごとに替える（2 秒・10 秒）。押しが届かなかった回（`PERF-TRUNK … outcome=missed`）の
    /// `trunk.open.debug` の値で、A（引く指が押しを奪う）・B（`dragStart`/`lidSettled` が残る）・C（`held` が残る）を見分ける。
    /// 一度でも押し直しが要ったら最後に落とす（押し直しの仕組みが無くても通ることを数で示すため）
    func testTrunkPickRepeat() { trunkPickRounds([0, 1]) }
    func testTrunkPickRepeat2() { trunkPickRounds([2, 3]) }
    func testTrunkPickRepeat3() { trunkPickRounds([4, 5]) }
    func testTrunkPickRepeat4() { trunkPickRounds([6, 7]) }

    /// 1 回の起動で、会員証・メダル・「ほか N」・乗車券を 2 巡押す（1 つの試験は 5 分の上限に収まるよう 2 回の起動まで）
    private func trunkPickRounds(_ rounds: [Int]) {
        // 2026-11-10 判断: 既定の 300 秒では足りない。4 本とも 1 本で 2 回ずつ起動して回し、run 42765477592 で
        // 208〜221 秒（上限の 7 割）、PR #514 の run 42787091389 では回全体が平均 1.19 倍遅く、
        // 2 本目以降が 227〜262 秒、1 本目が 300 秒を越えて止められた（手順は同じで、どの手順も一様に遅い）。
        // `Tools/xcode-test.sh` の決まりどおり、既定は上げずにこの 4 本だけ実測の約 2.7 倍にする
        executionTimeAllowance = 600
        pickMisses = 0
        for round in rounds {
            let app = launchTrunk(Self.trunkInsideArgs + ["-JPPreviewPerfProbe", "YES"])
            defer { app.terminate() }
            guard openTrunk(app) else { return XCTFail("旅のトランクを開けない（\(round) 回目）") }
            guard openTrunkRow(app, "trunk.open") else { return XCTFail("「ふたを開ける」の入口が無い（\(round) 回目）") }
            // 開くとふたが自分で開く（2026-11-12 判断・前は「ふたを開ける」を押していた）
            let medal = app.buttons["trunk.inside.medal"].firstMatch
            guard medal.waitForExistence(timeout: 15) else { return XCTFail("開けたふたの裏にメダルが無い（\(round) 回目）") }
            Thread.sleep(forTimeInterval: round % 2 == 0 ? 2 : 10)
            let go = app.buttons["trunk.hold.go"].firstMatch
            let putBack = app.buttons["trunk.hold.putBack"].firstMatch
            for _ in 0..<2 {
                for id in ["trunk.inside.card", "trunk.inside.medal", "trunk.inside.more", "trunk.inside.tickets"] {
                    let item = app.buttons[id].firstMatch
                    guard item.waitForExistence(timeout: 10), item.isHittable else {
                        XCTContext.runActivity(named: "PERF-TRUNK round=\(round) item=\(id) 押せる所に無い \(trunkDebugValue(app))") { _ in }
                        continue
                    }
                    guard pickUp(item, go: go, in: app) else { XCTFail("\(id) を押しても持ち上がらない（\(round) 回目）"); return }
                    Thread.sleep(forTimeInterval: 0.5)
                    putBack.tap()
                }
            }
        }
        XCTAssertEqual(pickMisses, 0, "押しても持ち上がらなかった回が \(pickMisses) 回（PERF-TRUNK の行を見る）")
    }

    func testCapturesTrunkOpen() {
        let app = launchTrunk(Self.trunkInsideArgs + ["-JPPreviewPerfProbe", "YES"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        guard openTrunkRow(app, "trunk.open") else { return XCTFail("「ふたを開ける」の入口が無い") }
        // 開くとふたが自分で開く（2026-11-12 判断）。「ふたを開ける」「中身を手に取る」のボタンは無い
        XCTAssertFalse(app.buttons["trunk.open.toggle"].firstMatch.exists, "「ふたを開ける」のボタンが残っている")
        let medal = app.buttons["trunk.inside.medal"].firstMatch
        guard medal.waitForExistence(timeout: 15) else { return XCTFail("開けたふたの裏にメダルが無い") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "100a-ふたを開けた")
        XCTAssertTrue(app.buttons["trunk.inside.card"].firstMatch.exists, "Pro の人の内ポケットに会員証が無い")
        XCTAssertTrue(app.buttons["trunk.inside.more"].firstMatch.exists, "メダル 10 枚なのに「ほか N」が無い")
        let go = app.buttons["trunk.hold.go"].firstMatch
        guard pickUp(medal, go: go, in: app) else { return XCTFail("メダルを押しても持ち上がらない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "100b-中身を手に取った（メダル）")
        let putBack = app.buttons["trunk.hold.putBack"].firstMatch
        XCTAssertGreaterThanOrEqual(go.frame.height, 44, "出口のボタンが 44pt 未満")
        XCTAssertGreaterThanOrEqual(putBack.frame.height, 44, "「トランクに戻す」が 44pt 未満")
        putBack.tap()
        let more = app.buttons["trunk.inside.more"].firstMatch
        guard more.waitForExistence(timeout: 10), more.isHittable else { return XCTFail("戻したあと「ほか N」を押せない") }
        guard pickUp(more, go: go, in: app) else { return XCTFail("「ほか N」を押しても持ち上がらない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "100c-中身を手に取った（ほかのメダル）")
        putBack.tap()
        let card = app.buttons["trunk.inside.card"].firstMatch
        guard card.waitForExistence(timeout: 5), card.isHittable else { return XCTFail("戻したあと会員証を押せない") }
        guard pickUp(card, go: go, in: app) else { return XCTFail("会員証を押しても持ち上がらない") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "100d-中身を手に取った（会員証）")
        putBack.tap()
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

    // MARK: - 旅のトランクの重さを測る（2026-11-11・owner「旅のトランク重すぎるな」「重いのはトランクを回したり、Pro で使える
    // トランクの一覧を見たとき」）
    //
    // アプリ側の `TrunkPerfMeter`（`-JPPreviewTrunkPerf YES`・見えない要素 `trunk.perf`）の数を操作の前後で読み、差をログの
    // `TRUNKPERF:` の行に出す。主スレッドが止まった時刻と、止まっている最中の積み（`perf.probe` の `stalls=`・`samples=`）は
    // 最後に `PERF-PROBE` の行で残す。普段の回では流さない（`Tools/pick-ui-tests.py` の `ONLY_WHEN_NAMED`）。
    // 名指しは `screens=testMeasuresTrunk`。値は Mac の CI のシミュレーターのもの（実機ではない）。
    // `…Before` は 2026-11-11 の直しの前の作り（`-JPPreviewTrunkDiag spincont,spinlazy,spinlink`）で、同じ回の前後を比べる

    private static let trunkPerfArgs = ["-JPPreviewTrunk", "YES", "-JPPreviewPro", "YES", "-JPPreviewTrunkPerf", "YES",
                                        "-JPPreviewPerfProbe", "YES"]

    /// `trunk.perf` の値を「名前 → 欄=値」に分ける（`Process` の欄も同じ形）
    private func trunkPerf(_ app: XCUIApplication) -> [String: [String: String]] {
        let probe = app.descendants(matching: .any)["trunk.perf"].firstMatch
        guard probe.waitForExistence(timeout: 5) else { return [:] }
        // 読み上げの値は 0.5 秒ごとに読み直される。いちばん新しい値を読む
        Thread.sleep(forTimeInterval: 0.6)
        var out: [String: [String: String]] = [:]
        for entry in ((probe.value as? String) ?? "").split(separator: ";") {
            let words = entry.split(separator: " ")
            guard let name = words.first else { continue }
            var fields: [String: String] = ["_raw": words.dropFirst().joined(separator: " ")]
            for w in words.dropFirst() {
                let kv = w.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
            }
            out[String(name)] = fields
        }
        return out
    }

    /// 1 つの操作の前後の差を行にする（回数・時間は差、コマの間隔は差、注記とメモリはそのまま）。
    /// 返す値は「名前.欄 → 差」（`GapMain.over100` など。試験の合否に使う）
    @discardableResult
    private func trunkPhase(_ app: XCUIApplication, _ label: String, lines: inout [String], _ body: () -> Void) -> [String: Double] {
        let before = trunkPerf(app)
        let start = Date()
        body()
        let secs = Date().timeIntervalSince(start)
        let after = trunkPerf(app)
        var deltas: [String: Double] = [:]
        if after.isEmpty { lines.append("\(label) | 数が読めない（trunk.perf が無い）"); return deltas }
        func d(_ k: String, _ f: String) -> Double {
            let v = (Double(after[k]?[f] ?? "") ?? 0) - (Double(before[k]?[f] ?? "") ?? 0)
            deltas["\(k).\(f)"] = v
            return v
        }
        if let a = after["Process"] {
            let cpu = d("Process", "cpu_ms")
            deltas["Process.mem_mb"] = Double(a["mem_mb"] ?? "") ?? 0
            lines.append(String(format: "%@ | Process secs=%.1f cpu_ms=%.0f cpu_pct=%.1f mem_mb_before=%@ mem_mb_after=%@ dev_mb_after=%@",
                                label, secs, cpu, cpu / max(secs, 0.001) / 10,
                                before["Process"]?["mem_mb"] ?? "-", a["mem_mb"] ?? "-", a["dev_mb"] ?? "-"))
        }
        for key in after.keys.sorted() where key != "Process" {
            let a = after[key]!
            if key.hasPrefix("Gap") {
                let frames = d(key, "frames")
                guard frames > 0 else { continue }
                // max は全体の最長（差は取れない）
                lines.append(String(format: "%@ | %@ frames=%.0f over25=%.0f over50=%.0f over100=%.0f dropped=%.0f excess_ms=%.1f avg_ms=%.2f max_all_ms=%@",
                                    label, key, frames, d(key, "over25"), d(key, "over50"), d(key, "over100"), d(key, "dropped"),
                                    d(key, "excess"), d(key, "sum") / max(frames, 1), a["max"] ?? "-"))
            } else if a["n"] != nil {
                let n = d(key, "n")
                guard n > 0 else { continue }
                let ms = d(key, "ms")
                lines.append(String(format: "%@ | %@ n=%.0f total_ms=%.1f avg_ms=%.2f slow=%.0f max_all_ms=%@",
                                    label, key, n, ms, ms / max(n, 1), d(key, "slow"), a["max"] ?? "-"))
            } else if before[key]?["_raw"] != a["_raw"] {
                // 生きている数・注記・途中のメモリは、変わったものだけ原文で
                lines.append("\(label) | \(key) \(a["_raw"] ?? "")")
            }
        }
        return deltas
    }

    private func trunkPerfReport(_ title: String, _ app: XCUIApplication, _ lines: [String]) {
        for line in lines { print("TRUNKPERF: \(perfTestName) \(line)") }
        let text = XCTAttachment(string: lines.joined(separator: "\n"))
        text.name = "計測（旅のトランク・\(title)）"
        text.lifetime = .keepAlways
        add(text)
        // 主スレッドの停止の起点と、止まっている最中の積み（`perf.probe`）
        notePerfProbe(app, label: title)
    }

    /// **回す**（owner「トランクを回したとき重い」）: 開く（面を描き終えるまで）→ 止まっている → 指で横・縦に払う →
    /// 止まり際の後 → 向きのボタン → 閉じる → もう一度開く。回している間の 1 コマ（`GapMain`・`GapSpin`・`SpinFrame`）・
    /// 主スレッドの停止・前後のメモリ。**直しの合否**（直しを戻すと落ちる）: 止まっている間に箱を描かない（2026-11-11 の
    /// 「動いている間だけ描く」）・2 回目に開くと絵を使い回す
    func testMeasuresTrunkSpin() { measureTrunkSpin(diag: nil) }
    /// 直しの前の作り（描き続ける・絵を塗り切らず使い回さない）。同じ回で前後を比べる。合否は付けない
    func testMeasuresTrunkSpinBefore() { measureTrunkSpin(diag: "spincont,spinlazy,spinlink") }
    /// 止まっている間も表示の刻みを止めない作り（2026-11-11 の `isPaused` の前）。止まっている間の CPU を比べる。合否は付けない
    func testMeasuresTrunkSpinLinkRunning() { measureTrunkSpin(diag: "spinlink") }

    private func measureTrunkSpin(diag: String?) {
        executionTimeAllowance = 600
        let app = launchTrunk(Self.trunkPerfArgs + (diag.map { ["-JPPreviewTrunkDiag", $0] } ?? []))
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        var lines: [String] = []
        trunkPhase(app, "トランクの画面・止まっている", lines: &lines) { Thread.sleep(forTimeInterval: 3) }
        let spin = app.buttons["trunk.spin"].firstMatch
        let box = app.descendants(matching: .any)["trunk.spin.box"].firstMatch
        let close = app.buttons["trunk.spin.close"].firstMatch
        for round in 1...2 {
            guard spin.waitForExistence(timeout: 10), spin.isHittable else { return XCTFail("トランクを押せない（\(round) 回目）") }
            var marker = ""
            var wall = 0.0
            let opened = trunkPhase(app, "回す画面を開く\(round)（面を描き終えるまで）", lines: &lines) {
                let began = Date()
                spin.tap()
                let ready = NSPredicate(format: "value BEGINSWITH %@", "faces-ready")
                if XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: box)], timeout: 20) == .completed {
                    marker = (box.value as? String) ?? ""
                    wall = Date().timeIntervalSince(began)
                } else {
                    XCTFail("回す画面の面を描き終えない（\(round) 回目）")
                }
            }
            lines.append(String(format: "回す画面を開く%d | %@ test_wall_to_ready_s=%.2f（XCUITest の待ちを含む）", round, marker, wall))
            if diag == nil, round == 2 {
                XCTAssertGreaterThanOrEqual(opened["SpinReuse.n"] ?? 0, 1, "2 回目に開いても絵を使い回していない")
            }
            let still = trunkPhase(app, "回す画面・止まっている\(round)", lines: &lines) { Thread.sleep(forTimeInterval: 4) }
            if diag == nil {
                // 止まっている 4 秒（前の作りは 240 コマ）に描くのは、出した直後の数コマまで
                XCTAssertLessThanOrEqual(still["SpinFrame.n"] ?? 0, 12, "止まっている間も箱を描き続けている（\(round) 回目）")
            }
            trunkPhase(app, "回す画面・指で払う\(round)", lines: &lines) {
                for i in 0..<2 {
                    let top = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                    let bottom = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                    let (from, to) = i % 2 == 0 ? (top, bottom) : (bottom, top)
                    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0)
                }
                // 最後は横に払って離す（惰性で回る）
                for i in 0..<6 {
                    let left = box.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
                    let right = box.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
                    let (from, to) = i % 2 == 0 ? (right, left) : (left, right)
                    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
                }
            }
            // 惰性で回り終える間（止まり際まで描く）と、止まりきった後
            let coasting = trunkPhase(app, "回す画面・離した後の惰性\(round)", lines: &lines) { Thread.sleep(forTimeInterval: 6) }
            let settled = trunkPhase(app, "回す画面・止まりきった後\(round)", lines: &lines) { Thread.sleep(forTimeInterval: 4) }
            let perf = trunkPerf(app)
            let applied = perf["SpinApplied"]?["_raw"] ?? "-", drawn = perf["SpinDrawn"]?["_raw"] ?? "-"
            lines.append("回す画面・止まりきった後\(round) | 書いた向き \(applied) | 描いた向き \(drawn)")
            if diag == nil {
                XCTAssertGreaterThanOrEqual(Int(perf["SpinLinkPaused"]?["n"] ?? "") ?? 0, 1, "止まっても表示の刻みを止めていない（\(round) 回目）")
                XCTAssertGreaterThan(coasting["SpinFrame.n"] ?? 0, 0, "離した後の惰性を描いていない（\(round) 回目）")
                XCTAssertLessThanOrEqual(settled["SpinFrame.n"] ?? 0, 12, "止まりきった後も箱を描き続けている（\(round) 回目）")
                XCTAssertEqual(applied, drawn, "止まり際の向きを描いていない（\(round) 回目）")
            }
            trunkPhase(app, "回す画面・向きのボタン\(round)", lines: &lines) {
                for id in ["side", "topBack", "bottom", "front"] {
                    let button = app.buttons["trunk.spin.view.\(id)"].firstMatch
                    if button.waitForExistence(timeout: 5) { button.tap() }
                    Thread.sleep(forTimeInterval: 1.5)
                }
            }
            trunkPhase(app, "回す画面を閉じた後\(round)", lines: &lines) {
                close.tap()
                Thread.sleep(forTimeInterval: 4)
            }
        }
        trunkPerfReport("回す" + (diag.map { "・\($0)" } ?? ""), app, lines)
    }

    /// **メモリの内訳**（2026-11-11・run 1014 / 1019 で、回す画面の絵をトランクの画面で先に作るとメモリが戻らないと分かった）。
    /// トランクの画面 → 回す画面 → 閉じた後で、アプリの段ごとの印（`SpinReady`・`SpinGone`・`SpinGoneLater`）の
    /// phys_footprint と user_tag 別をログの `TRUNKMEM:` に出す。
    /// 今の作りと直しの前（`spincont,spinlazy,spinlink`）を、それぞれ起動し直して比べる
    func testMeasuresTrunkMemory() { measureTrunkMemory(diag: nil) }
    func testMeasuresTrunkMemoryBefore() { measureTrunkMemory(diag: "spincont,spinlazy,spinlink") }
    /// **回す箱の絵を塗る時間の内訳**（2026-11-11・測るだけ）: `-JPPreviewTrunkDiag rastercost` でトランクの画面を開くと、アプリが
    /// 回す箱の正面・背面と同じ絵を部品を 1 つずつ外して描き、組む時間と塗る時間を `RasterCost…` に残す。ログの `TRUNKRASTER:` に出す
    func testMeasuresTrunkRasterCost() {
        executionTimeAllowance = 300
        let app = launchTrunk(Self.trunkPerfArgs + ["-JPPreviewTrunkDiag", "rastercost"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        let until = Date().addingTimeInterval(150)
        var perf: [String: [String: String]] = [:]
        while Date() < until {
            perf = trunkPerf(app)
            if perf["RasterCostDone"] != nil { break }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertNotNil(perf["RasterCostDone"], "塗る時間の内訳を測り終えない")
        for key in perf.keys.sorted() where key.hasPrefix("RasterCost") && key != "RasterCostDone" {
            print("TRUNKRASTER: \(perf[key]?["_raw"] ?? "")")
        }
    }

    /// **文字を太くする設定が回す箱の正面の絵に効くか**（2026-11-11・確かめ役の指摘）: 正面と同じ絵を
    /// `legibilityWeight` なし・regular・bold で描き、違う画素の割合を残す（効くなら端末の絵の合図に入れておく必要がある）
    func testMeasuresTrunkBoldText() {
        executionTimeAllowance = 300
        let app = launchTrunk(Self.trunkPerfArgs + ["-JPPreviewTrunkDiag", "boldcheck"])
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        let until = Date().addingTimeInterval(120)
        var perf: [String: [String: String]] = [:]
        while Date() < until {
            perf = trunkPerf(app)
            if perf["BoldCheckDone"] != nil { break }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertNotNil(perf["BoldCheckDone"], "文字の太さの比べを終えない")
        print("TRUNKBOLD: \(perf["BoldCheck"]?["_raw"] ?? "")")
    }

    /// **1 回目に開く間の止まり**（2026-11-11）: 前の作りと今の作りを交互に 3 回ずつ起動し、回す画面を初めて開く間の
    /// 主スレッドの止まりを同じ回で比べる（run 1019: 今 5.25 秒・前 3.41 秒が揺れか悪化かを見る）。止まっている最中の積みも残す
    func testMeasuresTrunkSpinFirstOpen() {
        // 4 つの作り × 3 回の起動で 10 分を超えた（run 1057・時間切れで数が出なかった）
        executionTimeAllowance = 1200  // UI テストの上限（`Tools/xcode-test.sh` の UI_TIME_MAXIMUM）
        var lines: [String] = []
        for pair in 1...3 {
            // 前の作り → 今（端末の正面の絵を消してから＝トランクが変わった後の 1 回目）→ 今（その次＝端末の絵を使う）
            for diag in ["spincont,spinlazy,spinlink", "spindiskclear", "spindiskfront", "now"] {
                let app = launchTrunk(Self.trunkPerfArgs + (diag == "now" ? [] : ["-JPPreviewTrunkDiag", diag]))
                defer { app.terminate() }
                guard openTrunk(app) else { XCTFail("旅のトランクを開けない"); continue }
                Thread.sleep(forTimeInterval: 3)
                let box = app.descendants(matching: .any)["trunk.spin.box"].firstMatch
                trunkPhase(app, "\(diag) \(pair) 回目・回す画面を初めて開く（面を描き終えて 3 秒）", lines: &lines) {
                    app.buttons["trunk.spin"].firstMatch.tap()
                    let ready = NSPredicate(format: "value BEGINSWITH %@", "faces-ready")
                    _ = XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: box)], timeout: 20)
                    Thread.sleep(forTimeInterval: 3)
                }
                noteSpinDisk(app, diag: diag == "now" ? nil : diag)
                notePerfProbe(app, label: "初めて開く・\(diag)・\(pair)")
            }
        }
        for line in lines where line.contains("GapMain") || line.contains("| Spin") || line.contains("| TexL") || line.contains("| Process") {
            print("TRUNKPERF: \(perfTestName) \(line)")
        }
    }

    private func measureTrunkMemory(diag: String?) {
        executionTimeAllowance = 400
        let app = launchTrunk(Self.trunkPerfArgs + (diag.map { ["-JPPreviewTrunkDiag", $0] } ?? []))
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        let tag = diag ?? "now"
        func dump(_ label: String) {
            let perf = trunkPerf(app)
            print("TRUNKMEM: \(tag) \(label) | Process mem_mb=\(perf["Process"]?["mem_mb"] ?? "-") int_mb=\(perf["Process"]?["int_mb"] ?? "-") cmp_mb=\(perf["Process"]?["cmp_mb"] ?? "-")")
            for key in perf.keys.sorted() where key.hasPrefix("Mem") || key.hasPrefix("VM") || key == "WarmPx" || key == "SpinScene" {
                print("TRUNKMEM: \(tag) \(label) | \(key) \(perf[key]?["_raw"] ?? "")")
            }
        }
        Thread.sleep(forTimeInterval: 9)
        dump("トランクの画面（9秒後）")
        app.buttons["trunk.spin"].firstMatch.tap()
        let box = app.descendants(matching: .any)["trunk.spin.box"].firstMatch
        let ready = NSPredicate(format: "value BEGINSWITH %@", "faces-ready")
        guard XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: box)], timeout: 20) == .completed else {
            return XCTFail("回す画面の面を描き終えない")
        }
        Thread.sleep(forTimeInterval: 4)
        dump("回す画面（4秒後）")
        app.buttons["trunk.spin.close"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 6)
        dump("閉じた後（6秒後）")
    }

    /// **Pro で使えるトランクの一覧**（owner「Pro で使えるトランクの一覧を見たとき重い」）: 型の画面 → 特別なトランク（6 型）を開く
    /// （開くまで）→ 縦に送る（measure・送りのコマ落ち）→ 戻る、を 2 回。札を作った回数・作られているトランクの絵の数・
    /// メモリの増え方と戻り方
    func testMeasuresTrunkProModels() { measureTrunkPro(diag: nil) }

    private func measureTrunkPro(diag: String?) {
        executionTimeAllowance = 600
        let app = launchTrunk(Self.trunkPerfArgs + (diag.map { ["-JPPreviewTrunkDiag", $0] } ?? []))
        guard openTrunk(app) else { return XCTFail("旅のトランクを開けない") }
        var lines: [String] = []
        trunkPhase(app, "トランクの画面・止まっている", lines: &lines) { Thread.sleep(forTimeInterval: 3) }
        trunkPhase(app, "型の画面を開く", lines: &lines) {
            guard openTrunkRow(app, "trunk.models") else { return XCTFail("型の行が無い") }
            _ = app.buttons["trunk.models.pro"].firstMatch.waitForExistence(timeout: 10)
            Thread.sleep(forTimeInterval: 2)
        }
        let proRow = app.buttons["trunk.models.pro"].firstMatch
        let card = app.buttons["trunk.proModels.card"].firstMatch
        for round in 1...2 {
            scrollTo(proRow, in: app)
            guard proRow.isHittable else { return XCTFail("特別なトランクの行を押せない（\(round) 回目）") }
            var opened = 0.0
            trunkPhase(app, "特別なトランクを開く\(round)（札が出るまで＋2秒）", lines: &lines) {
                let began = Date()
                proRow.tap()
                _ = card.waitForExistence(timeout: 15)
                opened = Date().timeIntervalSince(began)
                Thread.sleep(forTimeInterval: 2)
            }
            lines.append(String(format: "特別なトランクを開く%d | test_wall_to_card_s=%.2f（XCUITest の待ちを含む）", round, opened))
            trunkPhase(app, "特別なトランク・止まっている\(round)", lines: &lines) { Thread.sleep(forTimeInterval: 3) }
            trunkPhase(app, "特別なトランク・縦に送る\(round)", lines: &lines) {
                if round == 1 {
                    let options = XCTMeasureOptions()
                    options.iterationCount = 3
                    measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTCPUMetric(application: app),
                                      XCTMemoryMetric(application: app)], options: options) {
                        app.swipeUp(velocity: .fast)
                        app.swipeUp(velocity: .fast)
                        app.swipeDown(velocity: .fast)
                        app.swipeDown(velocity: .fast)
                    }
                } else {
                    for _ in 0..<3 {
                        app.swipeUp(velocity: .fast)
                        app.swipeUp(velocity: .fast)
                        app.swipeDown(velocity: .fast)
                        app.swipeDown(velocity: .fast)
                    }
                }
            }
            trunkPhase(app, "特別なトランクから戻った後\(round)", lines: &lines) {
                goBack(app)
                Thread.sleep(forTimeInterval: 4)
            }
        }
        trunkPerfReport("特別なトランク" + (diag.map { "・\($0)" } ?? ""), app, lines)
    }

    // MARK: - 直しの前後で絵が同じか（2026-11-11・画素の差。owner はトランクの見た目を妥協しない）
    //
    // 同じ見本で、前の作り（`-JPPreviewTrunkDiag`）と今の作りを起動し直して同じ所を撮り、画素の差をログの `TRUNKPIXEL:` に出す。
    // 公開リポジトリでは絵が残らないので、数で比べる。差のある画素（どれかの色が 2 より大きく違う）が 0.1% を越えたら落とす

    struct TrunkPixelDiff {
        var width = 0
        var height = 0
        var meanAbs = 0.0
        var maxAbs = 0
        /// どれかの色が 2 より大きく違う画素の割合（%）
        var over2Pct = 0.0
        var over16Pct = 0.0
        var sizeMismatch = false

        var line: String {
            sizeMismatch ? "size-mismatch"
                : String(format: "w=%d h=%d mean_abs=%.4f max_abs=%d over2_pct=%.4f over16_pct=%.4f",
                         width, height, meanAbs, maxAbs, over2Pct, over16Pct)
        }
    }

    /// 2 枚の絵の画素の差（RGBA 8 ビット・sRGB に並べ直して比べる）
    private func pixelDiff(_ a: UIImage, _ b: UIImage) -> TrunkPixelDiff {
        func rgba(_ image: UIImage) -> (Int, Int, [UInt8])? {
            guard let cg = image.cgImage else { return nil }
            let w = cg.width, h = cg.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ok = data.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            return ok ? (w, h, data) : nil
        }
        var out = TrunkPixelDiff()
        guard let ra = rgba(a), let rb = rgba(b), ra.0 == rb.0, ra.1 == rb.1 else {
            out.sizeMismatch = true
            return out
        }
        let wa = ra.0, ha = ra.1, da = ra.2, db = rb.2
        out.width = wa
        out.height = ha
        var sum = 0, maxAbs = 0, over2 = 0, over16 = 0
        for p in 0..<(wa * ha) {
            var pixelMax = 0
            for c in 0..<3 {
                let diff = abs(Int(da[p * 4 + c]) - Int(db[p * 4 + c]))
                sum += diff
                pixelMax = max(pixelMax, diff)
            }
            maxAbs = max(maxAbs, pixelMax)
            if pixelMax > 2 { over2 += 1 }
            if pixelMax > 16 { over16 += 1 }
        }
        let pixels = Double(wa * ha)
        out.meanAbs = Double(sum) / (pixels * 3)
        out.maxAbs = maxAbs
        out.over2Pct = Double(over2) / pixels * 100
        out.over16Pct = Double(over16) / pixels * 100
        return out
    }

    private func notePixel(_ label: String, _ diff: TrunkPixelDiff, _ a: UIImage, _ b: UIImage) {
        let line = "TRUNKPIXEL: \(perfTestName) \(label) | \(diff.line)"
        print(line)
        XCTContext.runActivity(named: line) { activity in
            for (name, image) in [("前", a), ("今", b)] {
                let shot = XCTAttachment(image: image)
                shot.name = "\(label)（\(name)）"
                shot.lifetime = .keepAlways
                activity.add(shot)
            }
        }
        XCTAssertFalse(diff.sizeMismatch, "\(label): 前と今で絵の大きさが違う")
        XCTAssertLessThanOrEqual(diff.over2Pct, 0.1, "\(label): 前と今で絵が違う（\(diff.line)）")
    }

    /// 端末の正面の絵: 消してから開いた回は書き終えるまで待ち（次の起動で読めるように）、今の作りの回は読んだかを確かめる
    private func noteSpinDisk(_ app: XCUIApplication, diag: String?) {
        if diag == "spindiskclear" {
            let until = Date().addingTimeInterval(20)
            while Date() < until, trunkPerf(app)["SpinDiskSaved"] == nil { Thread.sleep(forTimeInterval: 1) }
            XCTAssertNotNil(trunkPerf(app)["SpinDiskSaved"], "正面の絵を端末に書き終えない")
            print("TRUNKPERF: \(perfTestName) 端末に置いた絵 | SpinDiskBytes \(trunkPerf(app)["SpinDiskBytes"]?["_raw"] ?? "-")")
        } else if diag == nil {
            let perf = trunkPerf(app)
            XCTAssertNotNil(perf["SpinDiskHit"], "端末に置いた正面の絵を使っていない")
            XCTAssertNotNil(perf["SpinDiskSidesHit"], "端末に置いた側面などの絵を使っていない")
        } else if diag == "spindiskfront" {
            XCTAssertNotNil(trunkPerf(app)["SpinDiskHit"], "端末に置いた正面の絵を使っていない")
        }
    }

    /// 回す箱を、開いた直後・向きのボタンで止めた所（側面・上と背面・底・正面）で撮る
    private func shootSpinFaces(diag: String?) -> [(String, UIImage)] {
        let app = launchTrunk(Self.trunkPerfArgs + (diag.map { ["-JPPreviewTrunkDiag", $0] } ?? []))
        defer { app.terminate() }
        guard openTrunk(app) else { XCTFail("旅のトランクを開けない"); return [] }
        app.buttons["trunk.spin"].firstMatch.tap()
        let box = app.descendants(matching: .any)["trunk.spin.box"].firstMatch
        let ready = NSPredicate(format: "value BEGINSWITH %@", "faces-ready")
        guard XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: box)], timeout: 20) == .completed else {
            XCTFail("回す画面の面を描き終えない")
            return []
        }
        Thread.sleep(forTimeInterval: 3)
        noteSpinDisk(app, diag: diag)
        var shots = [("開いた直後", box.screenshot().image)]
        for id in ["side", "topBack", "bottom", "front"] {
            let button = app.buttons["trunk.spin.view.\(id)"].firstMatch
            guard button.waitForExistence(timeout: 5) else { XCTFail("向きのボタン \(id) が無い"); return shots }
            button.tap()
            // 寄せ終えて止まるまで（止まり際まで描かれているか）
            Thread.sleep(forTimeInterval: 3)
            shots.append(("向き \(id)", box.screenshot().image))
        }
        return shots
    }

    /// **回す箱**: 前の作り（描き続ける・後で塗る絵）と今の作り（動く間だけ描く・塗り切った絵）で、止まった絵が同じか
    func testTrunkSpinMatchesBefore() {
        executionTimeAllowance = 500
        let before = shootSpinFaces(diag: "spincont,spinlazy,spinlink")
        // 同じ作りを 2 回起動した差（撮り方の揺れ）。今と前の差がこれと同じ程度なら、直しによる差ではない
        let again = shootSpinFaces(diag: "spincont,spinlazy,spinlink")
        // 今の作り: 端末の正面の絵を消してから（その場で塗る）と、その次（端末に置いた PNG を読む）の両方
        let cold = shootSpinFaces(diag: "spindiskclear")
        let now = shootSpinFaces(diag: nil)
        guard before.count == now.count, again.count == now.count, cold.count == now.count, !now.isEmpty else {
            return XCTFail("撮れた数が前と今で違う")
        }
        for (b, c) in zip(before, cold) {
            notePixel("回す箱（端末の絵なし）・\(c.0)", pixelDiff(b.1, c.1), b.1, c.1)
        }
        for (b, a) in zip(before, again) {
            let line = "TRUNKPIXEL: \(perfTestName) 揺れ（前と前）・\(a.0) | \(pixelDiff(b.1, a.1).line)"
            print(line)
            XCTContext.runActivity(named: line) { _ in }
        }
        for (b, n) in zip(before, now) {
            notePixel("回す箱（端末の絵あり）・\(n.0)", pixelDiff(b.1, n.1), b.1, n.1)
        }
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
        enablePerfProbe(app) // 札 #424: 見えない要素 `trunk.open.debug`
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
        guard pickUp(insideCard, go: go, in: app) else { return XCTFail("会員証を押しても持ち上がらない") }
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
        guard pickUp(tickets, go: go, in: app) else { return XCTFail("乗車券を押しても持ち上がらない") }
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
        if agree.waitForExistence(timeout: 30) { agreeUntilGone(agree) }
        return app
    }

    /// 同意の画面を押して、閉じたことを確かめる。**押しが届かない回がある**（2026-10-31 Mac run 772 の
    /// `testCapturesCoverOffer`: 「同意して…」を押した記録はあるのに、アプリの画面の木は 45 秒後も同意の画面のまま
    /// ＝差し出しが出るはずのホームへ進まず「差し出しが出ない」で落ちた）。消えなければもう一度押し、
    /// それでも残れば**ここで落とす**（後の段で別の理由に見せない）
    private func agreeUntilGone(_ agree: XCUIElement) {
        let gone = NSPredicate(format: "exists == false")
        for _ in 0..<2 {
            agree.tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: agree)], timeout: 5) == .completed { return }
            guard agree.exists, agree.isHittable else { break }
        }
        XCTAssertFalse(agree.exists, "同意の画面が閉じない（「同意して…」を押しても進まない）")
    }

    /// **マイページの曲の行と旅の記録**（2026-10-24 owner の要望）。曲の行（ジャケット・曲名・歌手名・再生）と、
    /// 旅の記録の国の並び（区切りは「/」）を、日本語と英語で1枚ずつ撮る。見本の利用者は公開プロフィールに
    /// 曲が入っていて、公開写真に国名の入った撮影地がある。出なければ撮らない（この試験の決まり）。
    /// 曲の行が 44pt 未満なら落とす
    func testCapturesMyPageSongAndCountries() {
        for (lang, locale, suffix) in [("ja", "ja_JP", "日本語"), ("en", "en_US", "英語")] {
            let app = XCUIApplication()
            app.launchArguments += ["-legal.consent.version", "0"]
            app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
            app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
            app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
            app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
            app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
            app.launch()

            let agree = app.buttons["legal.agree"]
            if agree.waitForExistence(timeout: 30) { agree.tap() }
            let tabBar = app.tabBars.firstMatch
            guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
            tabBar.buttons.element(boundBy: 4).tap()
            guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20) else { return }
            let song = app.descendants(matching: .any)["mypage.bgm"].firstMatch
            guard song.waitForExistence(timeout: 20) else {
                app.terminate()
                continue
            }
            XCTAssertGreaterThanOrEqual(song.frame.height, 44, "曲の行の押せる高さが 44pt 未満")
            // 国の並びが画面の下に隠れていたら少し送る（上限あり）
            let countries = app.descendants(matching: .any)["profile.travelRecord.countries"].firstMatch
            var pushes = 0
            while countries.exists, !countries.isHittable, pushes < 2 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                pushes += 1
            }
            // ジャケットは通信で来るので少し待つ
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "14m-マイページ（曲の行と旅の記録・\(suffix)）")
            app.terminate()
        }
    }

    /// **格子の上を普通の速さで払っても札が替わる**（2026-10-28 owner の実機「投稿からマップにスライドしようと
    /// すると、うまくタブの切り替えができない」）。`testSwipesMyPageTabs` は札の行を勢いの無い送りで払うだけで、
    /// 指を写真の上に置いて勢いよく払う（`swipeLeft`）回を見ていなかった。写真を押すと詳細が開くこと・
    /// 格子の上で縦に送れることも続けて見る（払いが写真の押しや縦のスクロールを奪わない）。
    /// 写真が出なければ撮らない（この試験の決まり）。払って替わらなければ落とす
    func testSwipesMyPageGridQuickly() {
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
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20) else { return }
        let posts = app.buttons["profile.tab.posts"].firstMatch
        let trips = app.buttons["profile.tab.trips"].firstMatch
        guard posts.waitForExistence(timeout: 10) else { return }
        let photo = app.buttons["mypage.photo"].firstMatch
        guard photo.waitForExistence(timeout: 15) else { return }
        // 格子の写真が画面の真ん中あたりに来るまで、勢いを付けずに引き上げる
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let height = app.frame.height
        let width = app.frame.width
        let lift = photo.frame.midY - height * 0.55
        if lift > 0 {
            origin.withOffset(CGVector(dx: width * 0.5, dy: height * 0.8))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: width * 0.5, dy: height * 0.8 - lift)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            Thread.sleep(forTimeInterval: 1)
        }
        guard photo.isHittable else { return }
        // 写真の高さは先に控える（旅の記録へ替わると、投稿の格子は読み上げから外れて引けない）
        let photoY = photo.frame.midY
        let spot = origin.withOffset(CGVector(dx: width * 0.5, dy: photoY))

        // 写真の上で、勢いのある払い（指を離すまで止めない）
        photo.swipeLeft()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(trips.isSelected, "格子の上を勢いよく左へ払っても「旅の記録」に替わらない")
        shoot(app, "14q-マイページ（格子の上を払って旅の記録へ）")

        // 同じ所を右へ速く払って戻る
        origin.withOffset(CGVector(dx: width * 0.2, dy: photoY))
            .press(forDuration: 0.01, thenDragTo: origin.withOffset(CGVector(dx: width * 0.85, dy: photoY)),
                   withVelocity: .fast, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(posts.isSelected, "旅の記録の中身を右へ速く払っても「投稿」に戻らない")

        // 縦に送れる（払いが縦のスクロールを奪わない）
        let rowY = posts.frame.minY
        spot.press(forDuration: 0.05, thenDragTo: spot.withOffset(CGVector(dx: 0, dy: -height * 0.2)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertLessThan(posts.frame.minY, rowY - 40, "格子の上で縦に送れない")
        XCTAssertTrue(posts.isSelected, "縦に送っただけで札が替わった")

        // 写真を押すと詳細が開く（払いが押しを奪わない）
        let tapPhoto = app.buttons["mypage.photo"].firstMatch
        guard tapPhoto.isHittable else { return }
        tapPhoto.tap()
        XCTAssertTrue(app.buttons["photo.menu"].firstMatch.waitForExistence(timeout: 10), "格子の写真を押しても詳細が開かない")
    }

    /// **マイページの BGM の枠と再生の輪**（2026-10-28 owner の決定・モック A）。止まっているとき（真鍮の輪と ▶）と、
    /// 押して試聴が進んだとき（⏸ と満ちていく輪）を1枚ずつ撮る。曲の行が出なければ撮らない（この試験の決まり）。
    /// 枠の中の行が 44pt 未満なら落とす
    func testCapturesMyPageBgmRing() {
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
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20) else { return }
        let song = app.descendants(matching: .any)["mypage.bgm"].firstMatch
        guard song.waitForExistence(timeout: 20) else { return }
        XCTAssertGreaterThanOrEqual(song.frame.height, 44, "曲の行の押せる高さが 44pt 未満")
        // ジャケットは通信で来るので少し待つ
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "14n-マイページ（BGM の枠と再生の輪・止まっているとき）")
        song.tap()
        // 試聴の読み込みと進みを待つ（輪が数割満ちたところ）
        Thread.sleep(forTimeInterval: 8)
        shoot(app, "14n-マイページ（BGM の枠と再生の輪・再生中）")
        song.tap()
        app.terminate()
    }

    /// **全体の再生器を指で動かす**（2026-10-28 owner「再生中の音楽自由に動かせるといいね」・`MiniPlayerPlacement`）。
    /// マイページの BGM を鳴らしてホームへ移り、「いまの季節のスポット」の説明文の上に再生器が重なった所を1枚
    /// （地は透けるガラスで、それでも曲名・歌手名が読めること）。次に**長押しせずに**左上へ引いて離し、
    /// 左の端へ寄った所を1枚撮る（2026-10-28 owner 実機で動かせなかった: 長押しが要る形だった）。
    /// 曲の行・再生器・段が出なければ撮らない（この試験の決まり）。左の端へ寄らなければ落とす
    func testCapturesMiniPlayerDrag() {
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

        // 🔴 **先にホームで「いまの季節のスポット」の段まで送り、それから鳴らす**（PR #422 の Mac・run 41122249837）。
        // #417 ④で段が写真の5枚の後ろ（画面の下）へ移り、鳴らしてから送ると最大10回の引きの間に試聴（30 秒）が
        // 終わって再生器が消え、測る所で落ちた。タブを替えてもホームの送った位置は残る
        let card = app.buttons["home.spotShelf.card"].firstMatch
        _ = app.buttons["feed.photo"].firstMatch.waitForExistence(timeout: 20)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        func pushToShelf() {
            var pushes = 0
            while !(card.exists && card.isHittable), pushes < Self.shelfPushLimit {
                low.press(forDuration: 0.05, thenDragTo: high)
                Thread.sleep(forTimeInterval: 1)
                pushes += 1
            }
        }
        pushToShelf()
        // 届かなかった回も黙って抜けない（どこで止まったかを絵で残す）
        guard card.exists, card.isHittable else {
            shoot(app, "10m-ホーム（季節の段まで届かない）")
            return
        }

        // マイページで鳴らして、すぐホームへ戻る（鳴らしてから測るまでを短く）
        let song = app.descendants(matching: .any)["mypage.bgm"].firstMatch
        let bar = app.descendants(matching: .any)["mini.player"].firstMatch
        /// 鳴らし直してホームへ戻る（鳴っていたら一度止めてから）。再生器が出なければ false
        func playAndReturnHome() -> Bool {
            tabBar.buttons.element(boundBy: 4).tap()
            guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20),
                  song.waitForExistence(timeout: 20) else { return false }
            if bar.exists {
                song.tap()  // 鳴っていたら一度止める（押すと止まる）
                Thread.sleep(forTimeInterval: 1)
            }
            song.tap()
            guard bar.waitForExistence(timeout: 15) else { return false }
            tabBar.buttons.element(boundBy: 0).tap()
            // 送った位置が残っていなければ、段まで送り直す
            pushToShelf()
            return true
        }
        guard playAndReturnHome(), card.exists, card.isHittable else { return }
        // 札の説明文が再生器の高さに来るよう、もう一引き（札の下端が再生器より上に抜けない範囲で）
        if card.frame.maxY < bar.frame.minY {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            Thread.sleep(forTimeInterval: 1)
        }
        guard bar.exists else { return }
        // 作例の写真とジャケットは通信で来るので少し待つ
        Thread.sleep(forTimeInterval: 4)
        XCTAssertLessThan(bar.frame.width, app.frame.width - 24, "全幅のまま（左右へ寄せられない）")
        shoot(app, "10m-ホーム（再生器・説明文に重なった所）")
        // 引く直前に、試聴が終わって再生器が消えていたら鳴らし直す（測る所で消えていて落ちない）
        if !bar.exists {
            guard playAndReturnHome(), bar.exists else { return }
        }

        // 曲名の辺り（停止ボタンでない所）に触れてすぐ（長押しせずに）左上へ引き、止めてから離す → 左の端へ寄る。
        // 触れてから動き出すまでは 0.05 秒（長押しが要る形なら、ここで動かずに落ちる）
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: target, withVelocity: .fast, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        guard bar.exists else {
            XCTFail("引いただけで再生器が消えた")
            return
        }
        XCTAssertEqual(bar.frame.minX, app.frame.minX + 12, accuracy: 3, "左の端へ寄っていない")
        XCTAssertLessThan(bar.frame.midY, app.frame.height * 0.6, "離した高さに残っていない")
        shoot(app, "10m-ホーム（再生器・左の端へ寄せた）")

        // 探すの札で、いちばん上まで引き上げる → 見出しの下の入力欄にかぶらない（`MiniPlayerPlacement.topReserved`）。
        // 試聴は 30 秒で終わり再生器が消える（run 734 はここで消えて落ちた）。マイページで鳴らし直してから行く
        tabBar.buttons.element(boundBy: 4).tap()
        guard song.waitForExistence(timeout: 10) else { return }
        if bar.exists {
            song.tap()  // 鳴っていたら一度止める（押すと止まる）
            Thread.sleep(forTimeInterval: 1)
        }
        song.tap()
        guard bar.waitForExistence(timeout: 15) else { return }
        tabBar.buttons.element(boundBy: 1).tap()
        let field = app.textFields["search.field"].firstMatch
        _ = field.waitForExistence(timeout: 10)
        guard bar.exists else { return }
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.02)),
                   withVelocity: .fast, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        guard bar.exists else {
            XCTFail("上へ引いただけで再生器が消えた")
            return
        }
        if field.exists {
            XCTAssertGreaterThanOrEqual(bar.frame.minY, field.frame.maxY, "いちばん上で探すの入力欄にかぶる")
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "10m-探す（再生器・いちばん上）")

        // 停止ボタンのタップは引きとぶつからない（引きの始まりは 12pt 動いてから・`MiniPlayerBar.dragStartDistance`）
        let stop = bar.buttons["止める"].firstMatch
        if bar.exists, stop.exists {
            stop.tap()
            XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "停止ボタンを押しても止まらない（引きとぶつかる）")
        }
        app.terminate()
    }

    /// **全体の再生器の透け方**（2026-10-29 owner「背景透過させて、後ろの画像とかが見えるようにしたい」#402）。
    /// 地をぼかし無しの薄い黒にしたので、白い写真・模様の多い写真（白い字つき）・黒い写真の上で、曲名・歌手名・
    /// 停止ボタンが読めて、後ろの色と形が見えるかを撮る。後ろは見本の地（`-JPPreviewMiniPlayerBackdrop`・
    /// `MiniPlayerBackdrop`: 上から白 40%・模様 30%・黒 30%）。最初の置き場所（右下）が黒、真ん中が模様、
    /// いちばん上が白。曲の行・再生器が出なければ撮らない（この試験の決まり）
    func testCapturesMiniPlayerSeeThrough() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewMiniPlayerBackdrop", "YES"]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20) else { return }
        let song = app.descendants(matching: .any)["mypage.bgm"].firstMatch
        guard song.waitForExistence(timeout: 20) else { return }
        song.tap()
        let bar = app.descendants(matching: .any)["mini.player"].firstMatch
        guard bar.waitForExistence(timeout: 15) else { return }
        // ジャケットは通信で来るので少し待つ
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "10m-再生器の透け方（黒い写真の上）")

        // 真ん中（模様の段）へ。長押しせずに引いて止めてから離す
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.55)),
                   withVelocity: .fast, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        guard bar.exists else { return }
        shoot(app, "10m-再生器の透け方（模様の多い写真の上）")

        // いちばん上（白の段）へ
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.02)),
                   withVelocity: .fast, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        guard bar.exists else { return }
        shoot(app, "10m-再生器の透け方（白い写真の上）")
        app.terminate()
    }

    /// **マイページの札を横に払って切り替える**（2026-10-24 owner「切り替えスムーズに」・`ProfileTabPager`）。
    /// 札の行を左へ払うと「旅の記録」、右へ払うと「投稿」に戻る。戻ったとき「投稿」の格子が残っている
    /// （作り直さない）ことも見る。札が出なければ撮らない（この試験の決まり）。払って切り替わらなければ落とす
    func testSwipesMyPageTabs() {
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
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20) else { return }
        let posts = app.buttons["profile.tab.posts"].firstMatch
        let trips = app.buttons["profile.tab.trips"].firstMatch
        guard posts.waitForExistence(timeout: 10) else { return }
        // 札の行を画面の上のほう（高さの 35%）まで、勢いを付けずに引き上げる。`swipeUp` は勢いで
        // 札の行を画面の外まで飛ばすことがあり、run 702 はそれで何も撮らずに抜けた
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let height = app.frame.height
        let lift = posts.frame.minY - height * 0.35
        if lift > 0 {
            let from = origin.withOffset(CGVector(dx: app.frame.width * 0.5, dy: height * 0.8))
            let to = origin.withOffset(CGVector(dx: app.frame.width * 0.5, dy: height * 0.8 - lift))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(posts.isHittable, "札の行が見えるところまで送れない")
        guard posts.isHittable else { return }
        let rowY = posts.frame.minY
        let hadPhoto = app.buttons["mypage.photo"].firstMatch.waitForExistence(timeout: 10)

        // 札の行の高さで、画面の横幅の半分ほどを払う（小さな札1つの上の `swipeLeft` だと距離が足りないことがある）
        func swipeRow(left: Bool) {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let y = posts.frame.midY
            let width = app.frame.width
            let from = origin.withOffset(CGVector(dx: left ? width * 0.8 : width * 0.2, dy: y))
            let to = origin.withOffset(CGVector(dx: left ? width * 0.2 : width * 0.8, dy: y))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
        }
        swipeRow(left: true)
        XCTAssertTrue(trips.isSelected, "札の行を左へ払っても「旅の記録」に替わらない")
        XCTAssertEqual(posts.frame.minY, rowY, accuracy: 2, "切り替えで札の行の位置が跳んだ")
        shoot(app, "14n-マイページ（払って旅の記録へ）")

        swipeRow(left: false)
        XCTAssertTrue(posts.isSelected, "札の行を右へ払っても「投稿」に戻らない")
        XCTAssertEqual(posts.frame.minY, rowY, accuracy: 2, "戻ったときに札の行の位置が跳んだ")
        if hadPhoto {
            // 作り直していなければ、待たずに格子がある
            XCTAssertTrue(app.buttons["mypage.photo"].firstMatch.exists, "戻ったときに投稿の格子が消えている")
        }
        shoot(app, "14o-マイページ（払って投稿へ戻る）")

        // **深く送ってから替えたら、新しい札は頭から**（札の行が上端へ戻る・2026-10-24 確かめ役の見直し）。
        // 格子の写真が無い回（読めなかった回）は深く送れないので見ない
        guard hadPhoto else { return }
        for _ in 0..<3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        // 2026-10-30（#418）から札の行は上に留まる——深く送ったかは見出しの「編集」が見えないことで見る
        // （以前の「札の行が画面の外」は、留まるようになって成り立たず、黙って抜けていた）
        let edit = app.buttons["mypage.edit"].firstMatch
        XCTAssertFalse(edit.exists && edit.isHittable, "3回送っても見出しが見えている（深く送れていない）")
        guard !(edit.exists && edit.isHittable) else { return }
        // 格子の上で横に払う（札の行は上に留まっている）
        let gridY = height * 0.5
        origin.withOffset(CGVector(dx: app.frame.width * 0.8, dy: gridY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.2, dy: gridY)))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(trips.isSelected, "格子の上を左へ払っても「旅の記録」に替わらない")
        shoot(app, "14p-マイページ（深く送ってから替えると頭から）")
        // 札の行は上に留まるので、札の位置では「頭から」を言えない（いつも上端に居る）。
        // 投稿へ戻し、格子の1枚目が札の行のすぐ下に来ていれば、替えたときに頭へ送れている
        // （送れていなければ、投稿の格子は深く送ったまま＝1枚目は札の行より上）
        posts.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(posts.isSelected, "「投稿」に戻らない")
        let first = app.buttons["mypage.photo"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "投稿へ戻ったら格子が消えた")
        let gap = first.frame.minY - posts.frame.maxY
        XCTAssertTrue(gap >= 0 && gap < 240, "深く送ってから替えても頭から出ない（札の行と格子の1枚目の間 \(gap)）")
    }

    /// **ホームはタブの無い1本の並び**（札 #595・2026-11-13 owner 決定）。前の `testSwipesHomeFeedTabs`
    /// （札の行・中身を払って「おすすめ・フォロー中・新着」を替える・留まる札の行）を置き換えた。
    /// 切り替えの札が無い・下へ送ると写真が続き、読めた新着を使い切ったら続きのページを読む（読んだページの数が増える）・
    /// 「ホーム」をもう一度押すと頭へ戻る、を確かめる。
    /// 🔴 写真が出ない・送れない・続きを読まない・頭へ戻らないときは**落とす**（黙って通らない）
    func testScrollsHomeSingleFeed() {
        scrollsHomeSingleFeed(noLift: false)
    }

    /// 事実取り（2026-11-12・run 1171）: 写真の札の「手に取って運ぶ」の身振り（`HomeMosaic.liftGesture`）を外した版。
    /// 外した版だけ送れれば、身振りが ScrollView の送りを奪っている（`-JPPreviewNoLift`・UI テストのときだけ）。
    /// 前の `testSwipesHomeFeedTabsWithoutLift` を置き換えた
    func testScrollsHomeSingleFeedWithoutLift() {
        scrollsHomeSingleFeed(noLift: true)
    }

    private func scrollsHomeSingleFeed(noLift: Bool) {
        let app = XCUIApplication()
        if noLift { app.launchArguments += ["-JPPreviewNoLift", "YES"] }
        XCTContext.runActivity(named: "ホームの1本の並びを送る: noLift=\(noLift)") { _ in }
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        // 1本の並びの数（読んだページ・並びの数・続きの目印）を見えない要素に出す
        app.launchArguments += ["-JPPreviewFeedProbe", "YES"]
        app.launch()
        defer { app.terminate() }

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let photo = app.buttons["feed.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "ホームに写真が出ない")
        guard photo.exists else { return }
        for id in ["home.feed.recommended", "home.feed.following", "home.feed.latest", "home.feed.pinned"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists, "ホームに切り替えの札（\(id)）が出ている")
        }

        /// 1本の並びの数をログに残し、値を返す（`home.feed.probe`・UI テストのときだけ出る）
        let probe = app.descendants(matching: .any)["home.feed.probe"].firstMatch
        func readProbe(_ step: String) -> [String: String] {
            let value = probe.exists ? ((probe.value as? String) ?? "-") : "probe missing"
            let line = "[feedProbe] \(step): \(value)"
            print(line)
            XCTContext.runActivity(named: line) { _ in }
            let note = XCTAttachment(string: line)
            note.name = "feedProbe \(step)"
            note.lifetime = .keepAlways
            add(note)
            var fields: [String: String] = [:]
            for pair in value.split(separator: " ") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
            }
            return fields
        }
        let start = readProbe("0-start")
        // 送る前は1ページだけ（続きの目印が画面の外で読んでいない・#426）
        let startPages = Int(start["pages"] ?? "") ?? -1
        XCTAssertTrue((0...1).contains(startPages), "送る前に続きのページを読んだ（pages=\(startPages)・目印が画面の外で動いた）")
        shoot(app, "10g-ホーム（1本の並び・開いたところ）")

        // 下へ送る。勢いを付けない短い引きで、続きの目印に届くまで（上限あり）
        let firstY = photo.frame.minY
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        var pages = startPages
        var more = start["more"] == "true"
        for push in 0..<Self.singleFeedPushLimit {
            low.press(forDuration: 0.05, thenDragTo: high)
            Thread.sleep(forTimeInterval: 0.6)
            if push == 2 {
                XCTAssertLessThan(photo.frame.minY, firstY, "下へ送れない（1枚目の写真が動かない）")
                shoot(app, "10h-ホーム（1本の並びを下へ送った）")
            }
            let now = readProbe("1-push\(push)")
            pages = Int(now["pages"] ?? "") ?? pages
            more = now["more"] == "true"
            if pages > startPages || !more { break }
        }
        _ = readProbe("2-after-push")
        if start["more"] == "true" {
            XCTAssertGreaterThan(pages, startPages, "下まで送っても続きのページを読まない")
        }
        XCTAssertFalse(app.descendants(matching: .any)["home.feed.latest"].firstMatch.exists, "送った先に切り替えの札が出ている")

        // 「ホーム」をもう一度押すと頭へ戻る（`TabRouter.homeTopRequests`）。中身の上端（probe の `top`）も開いたときと同じ
        app.tabBars.firstMatch.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1.5)
        let back = readProbe("3-home-again")
        XCTContext.runActivity(named: "頭へ戻った: photoY=\(photo.frame.minY) firstY=\(firstY) top=\(back["top"] ?? "-") startTop=\(start["top"] ?? "-")") { _ in }
        XCTAssertEqual(photo.frame.minY, firstY, accuracy: 4, "「ホーム」を押しても頭へ戻らない")
        if let top = Double(back["top"] ?? ""), let startTop = Double(start["top"] ?? "") {
            XCTAssertEqual(top, startTop, accuracy: 1, "「ホーム」を押した後の中身の上端が、開いたときと違う")
        }
        shoot(app, "10i-ホーム（「ホーム」を押して頭へ）")
    }

    /// 1本の並びを下へ送る上限（画面の 60% の引き）。1ページ（30 枚）で並びはおよそ 120 個ぶんになる
    private static let singleFeedPushLimit = 60

    /// 1本の並び（札 #595）で、**新着の作者（自分以外でいちばん新しく載せた人）の写真の札**を画面に出して返す。
    /// 前は「新着」の札を押して1枚目を開いていた。札は `home.feed.probe` の `newestOther`（無ければ `firstLatest`）。
    /// 見本のストーリーは自分以外の新着の作者に付けてある（`PreviewBackend.previewStories`）。
    /// 2026-11-14（Mac の回 1239）: 新着の1枚目が見本の利用者自身の写真の日があり、`firstLatest` だと自分の写真を開いて
    /// 紹介のストーリーに届かなかった。出せなければ nil
    private func revealNewestFeedTile(_ app: XCUIApplication) -> XCUIElement? {
        let probe = app.descendants(matching: .any)["home.feed.probe"].firstMatch
        _ = app.buttons["feed.photo"].firstMatch.waitForExistence(timeout: 20)
        var index = 0
        if probe.waitForExistence(timeout: 10), let value = probe.value as? String {
            var fields: [String: Int] = [:]
            for pair in value.split(separator: " ") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, let n = Int(kv[1]) { fields[String(kv[0])] = n }
            }
            if let other = fields["newestOther"], other >= 0 {
                index = other
            } else if let first = fields["firstLatest"], first >= 0 {
                index = first
            }
            XCTContext.runActivity(named: "新着の札: index=\(index) probe=\(value)") { _ in }
        }
        let photo = app.buttons.matching(identifier: "feed.photo").element(boundBy: index)
        let lowPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let highPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        var pushes = 0
        while !(photo.waitForExistence(timeout: 3) && photo.isHittable), pushes < Self.shelfPushLimit {
            lowPoint.press(forDuration: 0.05, thenDragTo: highPoint)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        // 事実取り（2026-11-14 Mac の回 1246）: 開く札の読み上げ（題・作者）と位置を残す
        let picked = "[newestTile] index=\(index) label=\(photo.exists ? photo.label : "-") frame=\(photo.exists ? String(describing: photo.frame) : "-")"
        print(picked)
        XCTContext.runActivity(named: picked) { _ in }
        return photo.exists && photo.isHittable ? photo : nil
    }

    /// **区分の札は送ると上に留まる**（2026-10-30 owner 採用 #418・板「マイページ」の状態「区分の札が上に留まった」）。
    /// 下へ送っても札の行が時計の帯の下に残り、見出し（「編集」）は流れて見えない。留まった札を押すと替わり、
    /// 替えた札は頭から見せる（投稿へ戻すと格子の1枚目が札の行のすぐ下）。
    /// 🔴 段が見つからない・送れない・留まらないときは**落とす**（黙って通らない）
    func testPinsMyPageTabs() {
        // カバーのある回（時計の裏まで伸ばす）と、カバーの無い回（安全域の内側）で、留まり方が違う
        for (extra, suffix) in [([String](), "カバーあり"), (["-JPPreviewNoCover", "YES"], "カバーなし")] {
            checkPinnedTabs(extra, suffix)
        }
    }

    private func checkPinnedTabs(_ extra: [String], _ suffix: String) {
        let app = launchProfileLooks(extra)
        defer { app.terminate() }
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20) && tabBar.buttons.count > 4, "\(suffix): 下のタブが出ない")
        guard tabBar.exists, tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let edit = app.buttons["mypage.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "\(suffix): マイページの見出しが出ない")
        let posts = app.buttons["profile.tab.posts"].firstMatch
        let trips = app.buttons["profile.tab.trips"].firstMatch
        XCTAssertTrue(posts.waitForExistence(timeout: 10), "\(suffix): 区分の札（投稿）が見つからない")
        let photo = app.buttons["mypage.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20), "\(suffix): 投稿の格子が出ない（深く送れない）")
        guard posts.exists, photo.exists else { return }
        // カバーは通信で来る（来てから測る）
        Thread.sleep(forTimeInterval: 3)
        let restY = posts.frame.minY
        let pinnedRow = app.descendants(matching: .any)["mypage.tabs.pinned"].firstMatch
        XCTAssertFalse(pinnedRow.exists, "\(suffix): 送る前から留まった札が出ている")

        // 下へ送る（見出しが流れて見えなくなるまで）
        for _ in 0..<3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        let height = app.frame.height
        XCTAssertFalse(edit.exists && edit.isHittable, "\(suffix): 送っても見出しが見えている（深く送れていない）")
        // 留まった札: 重ねた札が出ていて、押せて、時計の帯のすぐ下（画面の上 15% の中）に居る。送る前より上
        XCTAssertTrue(pinnedRow.exists, "\(suffix): 下へ送っても区分の札が上に留まらない")
        XCTAssertTrue(posts.exists && posts.isHittable, "\(suffix): 下へ送ると区分の札が押せない")
        XCTAssertLessThan(posts.frame.minY, height * 0.15, "\(suffix): 区分の札が上に留まっていない（minY \(posts.frame.minY)）")
        XCTAssertGreaterThan(posts.frame.minY, 20, "\(suffix): 区分の札が時計の帯の裏に入った（minY \(posts.frame.minY)）")
        XCTAssertLessThan(posts.frame.minY, restY, "\(suffix): 送る前と同じ位置のまま（送れていない）")
        guard posts.isHittable, posts.frame.minY < height * 0.15 else { return }
        // 留まった札の地は黒（格子の写真が透けない）: 札の行の右端の空き（字の無い所）の色を見る
        let luma = Self.luma(app.screenshot().image, at: CGPoint(x: app.frame.width - 6, y: posts.frame.midY))
        XCTAssertNotNil(luma, "\(suffix): 画面の絵を読めない")
        if let luma { XCTAssertLessThan(luma, 16, "\(suffix): 留まった札の地が黒でない（明るさ \(luma)）") }
        let pinnedY = posts.frame.minY
        shoot(app, "14x-マイページ（区分の札が留まる・\(suffix)）")

        // 留まった札を押すと替わる。札の行は同じ位置
        XCTAssertTrue(trips.isHittable, "\(suffix): 留まった「旅の記録」の札が押せない")
        trips.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(trips.isSelected, "\(suffix): 留まった「旅の記録」の札を押しても替わらない")
        XCTAssertEqual(posts.frame.minY, pinnedY, accuracy: 2, "\(suffix): 替えたら札の行が留まった位置から動いた")

        // 投稿へ戻すと頭から（格子の1枚目が札の行のすぐ下）
        posts.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(posts.isSelected, "\(suffix): 留まった「投稿」の札を押しても戻らない")
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "\(suffix): 投稿へ戻ったら格子が消えた")
        let gap = photo.frame.minY - posts.frame.maxY
        XCTAssertTrue(gap >= 0 && gap < 240, "\(suffix): 替えた札が頭から出ない（札の行と格子の1枚目の間 \(gap)）")
    }

    /// **とても大きい字で、留まった札の行を横に払う**（#187 案 B「絵と字」の確かめ役の指摘・2026-11-13）。
    /// 札の行は2行に折っても4列に入らないと、横に送る並び（`ProfileTabColumnRow` の `ScrollView(.horizontal)`）に替わる。
    /// 留まった札の払い（`ProfileTabOverlaySwipe` の `simultaneousGesture`）と、横に送る並びの指がぶつかるかは
    /// コードから読んだだけでは分からない——**推定で直さず、数を取る**（CLAUDE.md「推定で直さない」）。
    /// 字の大きさ（AX1・AX3・AX5）ごとに、留まったときと払った後の「選んでいる札・札の位置・横に送る並びか・中身の位置」を
    /// `[tabsAX]` の行でログ（と注記）に出す。合否: 選んでいる札がちょうど1つ・左へ払えば「旅の記録」、右へ払えば「投稿」に
    /// 替わる（2026-11-14 Mac run 1233 の記録で原因を確かめてから足した・`ProfileTabSwipe.yieldsToHorizontalScrollers`）・
    /// 中身が選んでいる札のもので、横にずれて止まっていない。
    /// 名指し: `screens=testPinsMyPageTabs`（既存の `testPinsMyPageTabs` と一緒に選ばれる）
    ///
    /// **字の大きさごとに1本ずつ・1本で1回だけ起動する**（ほかの大きい文字の試験 `testCapturesCamperLargeText` などと同じ）。
    /// 1本で3つの大きさを続けて起動すると、AX3 の途中で XCTest の1本 5 分の持ち時間を越え、止める途中で
    /// 「Failed to terminate」で落ちた（Mac run 1227・AX1 と AX3 で 300 秒。1 回の値の書き出しに 4〜5 秒かかる）
    func testPinsMyPageTabsAtLargeTextAX1() {
        probePinnedTabsSwipe(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityMedium"], "AX1")
    }

    func testPinsMyPageTabsAtLargeTextAX3() {
        probePinnedTabsSwipe(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"], "AX3")
    }

    func testPinsMyPageTabsAtLargeTextAX5() {
        probePinnedTabsSwipe(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], "AX5")
    }

    private func probePinnedTabsSwipe(_ extra: [String], _ tag: String) {
        // どの指の操作が受けたかの記録（`mypage.tabs.probe`・`ProfileTabSwipeLog`・Debug のみ）
        let app = launchProfileLooks(extra + ["-JPPreviewTabSwipeProbe", "YES"])
        defer { app.terminate() }
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20) && tabBar.buttons.count > 4, "\(tag): 下のタブが出ない")
        guard tabBar.exists, tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let edit = app.buttons["mypage.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "\(tag): マイページの見出しが出ない")
        // マイページの札の並び（`ProfileTab.tabs(isMe: true)`）
        let ids = ["posts", "trips", "wishlist", "favorites"]
        let tabs = ids.map { app.buttons["profile.tab.\($0)"].firstMatch }
        XCTAssertTrue(tabs[0].waitForExistence(timeout: 10), "\(tag): 区分の札（投稿）が見つからない")
        let photo = app.buttons["mypage.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20), "\(tag): 投稿の格子が出ない（深く送れない）")
        guard tabs[0].exists, photo.exists else { return }
        // カバーは通信で来る（来てから測る）
        Thread.sleep(forTimeInterval: 3)
        let pinnedRow = app.descendants(matching: .any)["mypage.tabs.pinned"].firstMatch
        let swipeProbe = app.descendants(matching: .any)["mypage.tabs.probe"].firstMatch
        let width = app.frame.width
        // 旅の記録の中身の目印（見本の利用者で出るものから、在る最初の1つ）
        let tripMarks = ["trips.trunk", "trips.camper", "trips.albums", "trips.plans", "trips.passBook"]
            .map { app.descendants(matching: .any)[$0].firstMatch }

        /// 画面と交わっているか。**画面の外の要素に `isHittable` を聞かない**——横に送る並びで画面の外へ出た札に聞くと、
        /// XCTest が「押す点を決められない」で落ちる（Mac run 1222・AX3 の favorites x457.7-567.7・画面幅 440）
        func onScreen(_ e: XCUIElement) -> Bool {
            e.exists && !e.frame.isEmpty && e.frame.intersects(app.frame)
        }
        func frame(_ e: XCUIElement) -> String {
            guard e.exists else { return "-" }
            let f = e.frame
            let text = String(format: "x%.1f-%.1f,y%.1f-%.1f", f.minX, f.maxX, f.minY, f.maxY)
            guard onScreen(e) else { return text + ",off" }
            return text + (e.isHittable ? ",hit" : "")
        }
        func selected() -> [String] { zip(ids, tabs).filter { $0.1.exists && $0.1.isSelected }.map(\.0) }
        func tripMark() -> XCUIElement? { tripMarks.first { $0.exists } }
        func log(_ step: String) {
            let row = zip(ids, tabs).map { "\($0.0)(\(frame($0.1)))" }.joined(separator: " ")
            let scrolls = pinnedRow.exists ? "\(pinnedRow.scrollViews.count)" : "-"
            // 縦の送りの位置の目安: 見出し（「編集」）の位置・縦の送りの枠・旅の記録の目印の全部（中身の長さの目安）
            let marks = tripMarks.filter(\.exists).map { "\($0.identifier)(\(frame($0)))" }.joined(separator: " ")
            let scrollViews = (0..<min(app.scrollViews.count, 3))
                .map { frame(app.scrollViews.element(boundBy: $0)) }.joined(separator: " ")
            let line = "[tabsAX] \(tag) \(step): width=\(width) height=\(app.frame.height) sel=\(selected().joined(separator: "+")) "
                + "pinned=\(pinnedRow.exists) pinnedFrame=\(frame(pinnedRow)) rowScrollViews=\(scrolls) "
                + "tabs=[\(row)] photo=\(frame(photo)) edit=\(frame(edit)) trips=[\(marks)] scrollViews=[\(scrollViews)]"
                // どの指の操作が受けたか（UIKit のパン pan[row|content]・留まった札 overlay・横の送り hx・選んだ札 sel）
                + " probe={\(swipeProbe.exists ? ((swipeProbe.value as? String) ?? "-") : "missing")}"
            print(line)
            XCTContext.runActivity(named: line) { _ in }
            let note = XCTAttachment(string: line)
            note.name = "tabsAX \(tag) \(step)"
            note.lifetime = .keepAlways
            add(note)
        }
        /// 札の行の上を、画面の横幅の 6 割だけ払う（左へ払うと右隣の札）。留まった札が無ければ流れている元の行の上
        func swipeRow(left: Bool) {
            let y = pinnedRow.exists ? pinnedRow.frame.midY : tabs[0].frame.midY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: left ? width * 0.8 : width * 0.2, dy: y))
            let to = origin.withOffset(CGVector(dx: left ? width * 0.2 : width * 0.8, dy: y))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1.5)
        }
        /// どちらに転んでも崩れてはいけない所: 選んでいる札は1つ・`allowed` の中・中身がその札のもので横にずれていない
        func checkSettled(_ step: String, allowed: [String], photoX: CGFloat) {
            let sel = selected()
            XCTAssertEqual(sel.count, 1, "\(tag) \(step): 選んでいる札が1つでない（\(sel)）")
            guard let now = sel.first else { return }
            XCTAssertTrue(allowed.contains(now), "\(tag) \(step): 1回の払いで \(now) へ替わった（期待 \(allowed) のどれか）")
            switch now {
            case "posts":
                XCTAssertTrue(photo.exists, "\(tag) \(step): 投稿を選んでいるのに格子が見えない")
                if photo.exists {
                    XCTAssertEqual(photo.frame.minX, photoX, accuracy: 2, "\(tag) \(step): 投稿の中身が横にずれて止まった")
                }
            case "trips":
                // 選んでいない札は読み上げから外す（`ProfileTabPager`）——投稿の格子が押せれば中身が替わっていない
                XCTAssertFalse(onScreen(photo) && photo.isHittable, "\(tag) \(step): 旅の記録を選んでいるのに投稿の格子が押せる")
                if let mark = tripMark() {
                    XCTAssertTrue(mark.frame.minX >= -2 && mark.frame.minX < width * 0.5,
                                  "\(tag) \(step): 旅の記録の中身が横にずれて止まった（\(frame(mark))）")
                }
            default:
                break
            }
        }

        log("rest")
        // 下へ送る（重ねた札が出るまで。大きい字は見出しが長い）
        var pushes = 0
        while !pinnedRow.exists, pushes < 10 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        XCTAssertTrue(pinnedRow.exists, "\(tag): 下へ送っても区分の札が上に留まらない（\(pushes) 回送った）")
        guard pinnedRow.exists else { return }
        log("pinned(pushes=\(pushes))")
        XCTAssertEqual(selected(), ["posts"], "\(tag): 留まった時に「投稿」を選んでいない")
        let photoX = photo.exists ? photo.frame.minX : 0
        shoot(app, "14y-マイページ（大きい字で札が留まる・\(tag)）")

        // 1. 留まった札の行を左へ払う（投稿 → 旅の記録のはず。替わらなくても数は残す）
        swipeRow(left: true)
        log("after-left")
        shoot(app, "14y-マイページ（大きい字で留まった札を左へ払う・\(tag)）")
        checkSettled("左へ払った後", allowed: ["trips"], photoX: photoX)

        // 2. 右へ払って戻す（替えた札は頭から見せるので、留まりが外れていれば元の行の上で払う。どちらかはログの pinned=）
        swipeRow(left: false)
        log("after-right")
        // 2026-11-14（Mac run 1233）: AX3・AX5 で横に送る並びの札の行の上を右へ払っても「旅の記録」のままだった
        // （`pan[row] receive -> no(hscroll)`）。直した後は、どの字の大きさでも払いで「投稿」に戻る
        checkSettled("右へ払った後", allowed: ["posts"], photoX: photoX)
    }

    /// 画面の絵の1点（ポイント）の明るさ（0〜255）。読めなければ nil
    private static func luma(_ image: UIImage, at point: CGPoint) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let scale = image.scale
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height,
              let one = cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return 0.299 * Double(px[0]) + 0.587 * Double(px[1]) + 0.114 * Double(px[2])
    }

    /// **カバーの下端のフェード**（2026-10-28 owner が案A を選んだ・`ProfileCoverFade`）。マイページの上を1枚と、
    /// カバーの下端と黒の継ぎ目を切り出した1枚を撮る。前の絵は main の回の `14-マイページ`。
    /// 見本の利用者にカバーが無い（額縁が出る・見出しが上に詰まる）回は撮らない（この試験の決まり）
    func testCapturesProfileCoverFade() {
        let app = launchProfileLooks()
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let edit = app.buttons["mypage.edit"].firstMatch
        guard edit.waitForExistence(timeout: 20) else { return }
        // カバーは通信で来る。「編集」はカバーの有無にかかわらず名前の段にある（#415）ので、
        // カバーが出たかは名前の段の高さで見る: カバー（240）の下端に顔（88）を 44 重ねた下＝200pt より下。
        // 無い人は設定の丸の高さから 72pt の顔の下（約 150pt）
        Thread.sleep(forTimeInterval: 4)
        let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
        guard nameLine.exists, !app.descendants(matching: .any)["mypage.coverFrame"].firstMatch.exists,
              nameLine.frame.minY > 200 else { return }
        shoot(app, "106-マイページ（カバーの下端のフェード）")

        // 継ぎ目の寄り: 帯の下の方（60% の透明 → 下端の黒）と、その下の黒い地。
        // 帯の下端はアイコン（88pt を 44pt 重ねる）の真ん中あたり＝名前の少し上
        let screen = app.screenshot().image
        let scale = screen.scale
        let seam = CGRect(x: 0, y: max(0, nameLine.frame.minY - 280), width: screen.size.width, height: 300)
        guard let cg = screen.cgImage?.cropping(to: CGRect(x: seam.minX * scale, y: seam.minY * scale,
                                                           width: seam.width * scale, height: seam.height * scale))
        else { return }
        let crop = XCTAttachment(image: UIImage(cgImage: cg, scale: scale, orientation: .up))
        crop.name = "106a-マイページ（カバーの継ぎ目の寄り）"
        crop.lifetime = .keepAlways
        add(crop)
    }

    /// **マイページの見出しの並び**（2026-10-30 owner #415・案 ①②）。数（投稿・フォロワー・フォロー中）は
    /// 顔の右（名前の段より上）、「編集」は名前の段の右端。見本の利用者のまま（カバーが出ればカバーの回）と、
    /// カバーの無い回（額縁が出る）の2回で撮り、並びが違えば落とす。出なければ撮らない（この試験の決まり）
    func testCapturesMyPageHeaderRows() {
        for (extra, suffix) in [([String](), "見本の利用者"), (["-JPPreviewNoCover", "YES"], "カバーなし"),
                                (["-JPPreviewBareHeader", "YES"], "カバーも額縁もなし")] {
            let app = launchProfileLooks(extra)
            let tabBar = app.tabBars.firstMatch
            guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
            tabBar.buttons.element(boundBy: 4).tap()
            let edit = app.buttons["mypage.edit"].firstMatch
            guard edit.waitForExistence(timeout: 20) else { return }
            // カバー・数は通信で来る
            Thread.sleep(forTimeInterval: 4)
            let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
            let stats = app.descendants(matching: .any)["mypage.stats"].firstMatch
            guard nameLine.exists else { return }
            XCTAssertTrue(stats.exists, "\(suffix): 数の並びが無い")
            let width = app.frame.width
            // ① 数は顔の右（顔 72 か 88 ＋左の端 16 より右）で、名前の段より上
            XCTAssertGreaterThanOrEqual(stats.frame.minX, 16 + 72, "\(suffix): 数が顔の右にない（minX \(stats.frame.minX)）")
            XCTAssertLessThanOrEqual(stats.frame.maxY, nameLine.frame.minY + 1,
                                     "\(suffix): 数が名前の段より下にある（BGM の下に戻っている）")
            // ② 「編集」は名前の段の右端（縦の真ん中がそろい、名前より右・右の端 16 に寄る）
            XCTAssertLessThan(abs(edit.frame.midY - nameLine.frame.midY), 12,
                              "\(suffix): 「編集」が名前の段にない（\(edit.frame.midY) / \(nameLine.frame.midY)）")
            XCTAssertGreaterThanOrEqual(edit.frame.minX, nameLine.frame.maxX, "\(suffix): 「編集」が名前の右でない")
            XCTAssertGreaterThanOrEqual(edit.frame.maxX, width - 16 - 2, "\(suffix): 「編集」が右端にない")
            XCTAssertGreaterThanOrEqual(edit.frame.height, 44, "\(suffix): 「編集」の当たりが 44pt 未満")
            XCTAssertEqual(edit.label, "プロフィールを編集", "\(suffix): 読み上げが変わった")
            // 額縁も無い回: 顔の段が右上の設定の丸と同じ高さ。数は丸の下に潜らない
            if extra.contains("-JPPreviewBareHeader") {
                XCTAssertFalse(app.descendants(matching: .any)["mypage.coverFrame"].firstMatch.exists,
                               "\(suffix): 額縁が出ている")
                let gear = app.buttons["設定"].firstMatch
                if gear.exists {
                    XCTAssertLessThanOrEqual(stats.frame.maxX, gear.frame.minX + 1,
                                             "\(suffix): 数が設定の丸の下に潜っている（\(stats.frame.maxX) / \(gear.frame.minX)）")
                }
            }
            shoot(app, "108-マイページ（見出しの並び・\(suffix)）")
            app.terminate()
        }
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
                // 選んだ直後にカバーの位置を合わせる画面（owner 2026-10-28）。出なければ撮らずに先へ
                let done = app.buttons["coverCrop.done"].firstMatch
                if done.waitForExistence(timeout: 20) {
                    Thread.sleep(forTimeInterval: 2)
                    shoot(app, "104a2-カバーの位置を調整")
                    // 「完了」「キャンセル」は上のバーの系統の部品（iOS 26 は見た目 36 で報告し、当たりは系統が広げる）。
                    // 高さではなく、出ていることを確かめる
                    XCTAssertTrue(app.buttons["coverCrop.cancel"].firstMatch.exists, "「キャンセル」が無い")
                    done.tap()
                }
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
        // 閉じたかは「カバーにする」が無くなった・押せなくなったで見る。2026-10-30 Mac run（41139085964）では、録画で
        // 札は 0.5 秒で下へ閉じてホームが出ているのに、`exists` だけで見た待ちが 5 秒で切れて落ちた（閉じた札の
        // 要素が読み上げの木にしばらく残ると見られる。確かめきれてはいない）。押せる所に残っていれば閉じていないので落とす
        let gone = NSPredicate(format: "exists == false OR hittable == false")
        let closed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: apply)], timeout: 10)
        XCTAssertEqual(closed, .completed, "「あとで」で閉じない")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5) && app.tabBars.firstMatch.isHittable,
                      "「あとで」のあと下のタブに戻らない")
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
    /// 接写の一覧の頁を 1 つ進める。押した後、いまの頁の合図（`from`）が消える（次の頁を描き始める）のを確かめ、
    /// 消えなければ 2 回まで押し直す。2026-10-23 PR #371 の検証（run 39843960624）: 込んだ Mac で 16 → 17 頁の押しが
    /// 届かず（アプリの応答が 1 回 2 秒以上止まっていた）、試験の数える頁がアプリより 1 つ先へずれ、17〜27 頁を全部
    /// 「描き終えない」と落ちていた（アプリは 17〜26 頁を描いていた）
    private func turnContactPage(_ app: XCUIApplication, _ next: XCUIElement, from marker: String) {
        let sheet = app.descendants(matching: .any)["camper.room.contact"].firstMatch
        let moved = NSPredicate(format: "NOT (value CONTAINS %@)", marker)
        for attempt in 1...3 {
            next.tap()
            if XCTWaiter().wait(for: [expectation(for: moved, evaluatedWith: sheet)], timeout: 10) == .completed { return }
            print("UINOTE 接写の頁: 進むを押しても「\(marker)」のまま（\(attempt) 回目）")
        }
    }

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
        // 寄り 8 点は部屋を組み直す。既定の 300 秒で切らない（図鑑が 2,000 点を超えていた頃に決めた枠。2026-11-11 に 85 点へ減らした後もそのまま）
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

    /// **額に写真を飾る**（2026-10-21 owner の実機: 写真を選んで飾ったのに額の中が真っ白）。見本の写真は staging の本物の URL から、
    /// 本番と同じ読み込み（`CamperRoomPhotoImages`）で読む。読み上げの値の `photos=絵の入った印画/額 rect=…`（`CamperRoomScene.photoProbe`）
    /// で絵が額に入ったことを、その四角の画素が一色でないことで「見える」ことを確かめる（白い硝子が印画を覆っても数だけは合う）
    func testCapturesCamperRoomHangPhoto() throws {
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        guard waitRoom(app, "camper.room.scene", "camper-room-ready") else { return XCTFail("部屋を組み終えない") }
        app.buttons["camper.room.tool.photos"].firstMatch.tap()
        let frame = app.buttons["camper.room.frame"].firstMatch
        guard frame.waitForExistence(timeout: 10) else { return XCTFail("飾る額の一覧が出ない") }
        frame.tap()
        let photo = app.buttons["camper.room.photo"].firstMatch
        guard photo.waitForExistence(timeout: 30) else { return XCTFail("飾る写真の一覧が出ない（見本の写真が無い）") }
        photo.tap()
        let hang = app.buttons["camper.room.hang"].firstMatch
        XCTAssertTrue(hang.waitForExistence(timeout: 5), "「この額に飾る」が無い")
        hang.tap()
        let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
        let shown = NSPredicate(format: "value MATCHES %@", ".*photos=[1-9][0-9]*/[0-9]+ uvOut=[0-9.]+ rect=[0-9]+,[0-9]+,[0-9]+,[0-9]+.*")
        let waited = XCTWaiter().wait(for: [expectation(for: shown, evaluatedWith: scene)], timeout: 45)
        let value = (scene.value as? String) ?? ""
        print("CAMPERPHOTO 値: \(value)")
        if app.buttons["camper.room.photo.retry"].firstMatch.exists { print("CAMPERPHOTO 読み込めませんでしたが出ている") }
        guard waited == .completed else {
            shoot(app, "96h-額に写真を飾った（入らない）")
            return XCTFail("額に写真が入らない（読み上げの値: \(value)）")
        }
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "96h-額に写真を飾った")
        // 写真の外を読まない（読むと端の画素が伸びて縦の筋になる・2026-10-22 楕円の額）
        XCTAssertTrue(value.contains("uvOut=0.00"), "印画が写真の外を読む: \(value)")
        // 印画の四角（SCNView の点）の内側 6 割の画素が一色でないこと
        let numbers = value.components(separatedBy: "rect=").last?.split(separator: " ").first?.split(separator: ",").compactMap { Double($0) } ?? []
        guard numbers.count == 4 else { return XCTFail("印画の四角を読めない: \(value)") }
        let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]).insetBy(dx: numbers[2] * 0.2, dy: numbers[3] * 0.2)
        let shot = scene.screenshot()
        let crop = XCTAttachment(screenshot: shot)
        crop.name = "96h-額に写真を飾った（箱庭だけ）"
        crop.lifetime = .keepAlways
        add(crop)
        let stats = try XCTUnwrap(Self.lumaStats(shot.image, in: rect), "印画の四角が箱庭の外: \(rect)")
        print("CAMPERPHOTO 印画の四角 \(rect) 明るさの平均 \(stats.mean) ばらつき \(stats.deviation)")
        XCTAssertGreaterThan(stats.deviation, 12, "額の中が一色（平均 \(Int(stats.mean))）。飾った写真が見えていない")
    }

    /// 絵の四角（点）の中の明るさの平均とばらつき（0〜255）
    private static func lumaStats(_ image: UIImage, in rect: CGRect) -> (mean: Double, deviation: Double)? {
        guard let cg = image.cgImage else { return nil }
        let scale = image.scale
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height)).integral
        guard px.width >= 4, px.height >= 4, let part = cg.cropping(to: px) else { return nil }
        let w = part.width, h = part.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0, sq = 0.0
        let n = Double(w * h)
        for k in 0..<(w * h) {
            let l = 0.299 * Double(bytes[k * 4]) + 0.587 * Double(bytes[k * 4 + 1]) + 0.114 * Double(bytes[k * 4 + 2])
            sum += l
            sq += l * l
        }
        let mean = sum / n
        return (mean, max(0, sq / n - mean * mean).squareRoot())
    }

    /// **部屋の寄り**（`-JPPreviewCamperRoomCamera`・2026-10-21 owner の実機の寄りの絵と同じ所）: 手前の右の角（切った壁の天端・
    /// 角の継ぎ目・敷居）と、窓の脇のカーテン（窓台・留め紐）を昼に撮る
    func testCapturesCamperRoomCloseUps() {
        for (preset, name) in [("corner", "96i-部屋の寄り（手前の右の角）"), ("curtain", "96j-部屋の寄り（窓の脇のカーテン）")] {
            let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomCamera", preset])
            XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない（\(preset)）")
            guard waitRoom(app, "camper.room.scene", "camper-room-ready") else { XCTFail("部屋を組み終えない（\(preset)）"); continue }
            shoot(app, name)
            app.terminate()
        }
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
    /// 図鑑の寄りと同じ小部屋に描き、4 点ずつの頁を昼と夜で**必ず撮る**（全家具の出来を本物の絵で見る。ソフトラスタでは素材・光が見えない）
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
                turnContactPage(app, next, from: "contact-ready \(mood) \(page)/")
                page += 1
            }
            // 頁を初めに戻して、昼と夜を替える
            while prev.exists, prev.isEnabled { prev.tap() }
            if mood == "day" { app.buttons["camper.room.contact.mood"].firstMatch.tap() }
        }
    }

    /// **家具の脚の接写**（`-JPPreviewCamperRoomLegs`・Debug のみ・2026-10-22 owner「椅子とかは家具によって足が壊れてたりする」）:
    /// 脚のある家具を 1 頁に 1 つ、正面・斜め・横・低い所の 4 方向から本物の SceneKit で描き、昼の全頁を**必ず撮る**
    /// （脚が床に着いているか・座面や天板に届いているか・貫の位置を、1 つずつ目で見る）。
    /// **名指しした回だけ流す**（`Tools/pick-ui-tests.py` の ONLY_WHEN_NAMED。全部を回す PR の検証・TestFlight では飛ばす・約5分）
    func testCapturesCamperFurnitureLegs() {
        executionTimeAllowance = 1500
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomLegs", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        let sheet = app.descendants(matching: .any)["camper.room.contact"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "脚の接写の一覧が出ない")
        let next = app.buttons["camper.room.contact.next"].firstMatch
        var page = 1
        while page <= 80 {
            XCTAssertTrue(waitRoom(app, "camper.room.contact", "legs-ready \(page)/", timeout: 90), "脚の接写の \(page) 頁を描き終えない")
            let grid = app.descendants(matching: .any)["camper.room.contact.grid"].firstMatch
            let shot = XCTAttachment(screenshot: grid.exists ? grid.screenshot() : app.screenshot())
            shot.name = String(format: "96f-家具の脚（%02d）", page)
            shot.lifetime = .keepAlways
            add(shot)
            guard next.exists, next.isEnabled else { break }
            turnContactPage(app, next, from: "legs-ready \(page)/")
            page += 1
        }
    }

    /// **額の頁**（`-JPPreviewCamperRoomFrames`・2026-10-22 owner の実機: 楕円の額で写真が縦の筋に崩れた）: 写真を入れられる
    /// 全部の額に、自分の本物の写真（横長・縦長の 1 枚ずつ。飾る時と同じ読み込み）を入れた接写を昼に**必ず撮る**。
    /// どの頁でも印画が写真の外を読まないこと（`uvOut=0.00`）、横長と縦長の写真が選べたことを確かめる
    /// **名指しした回だけ流す**（`Tools/pick-ui-tests.py` の ONLY_WHEN_NAMED・約6〜7分。印画の UV は単体テストが毎回見る）
    func testCapturesCamperRoomFrameSheet() {
        executionTimeAllowance = 3000
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomFrames", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        let sheet = app.descendants(matching: .any)["camper.room.contact"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "額の頁が出ない")
        let next = app.buttons["camper.room.contact.next"].firstMatch
        var page = 1
        while page <= 90 {
            let ready = waitRoom(app, "camper.room.contact", "contact-ready day \(page)/", timeout: 90)
            let value = (sheet.value as? String) ?? ""
            print("CAMPERFRAMES \(page): \(value)")
            XCTAssertTrue(ready, "額の頁 \(page) を描き終えない（\(value)）")
            XCTAssertTrue(value.contains("uvOut=0.00"), "額の頁 \(page): 印画が写真の外を読む（端の画素が伸びて筋になる）: \(value)")
            if page == 1 {
                XCTAssertFalse(value.contains("wide=-") || value.contains("tall=-"), "写真が読めない: \(value)")
            }
            let grid = app.descendants(matching: .any)["camper.room.contact.grid"].firstMatch
            let shot = XCTAttachment(screenshot: grid.exists ? grid.screenshot() : app.screenshot())
            shot.name = String(format: "96k-写真を入れた額（%02d）", page)
            shot.lifetime = .keepAlways
            add(shot)
            guard next.exists, next.isEnabled else { break }
            turnContactPage(app, next, from: "contact-ready day \(page)/")
            page += 1
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

    // MARK: - 部屋の下の板（2026-10-22 owner の実機 1.1.37「操作感も悪い」）

    /// **部屋の下の板を全部**（家・置く・模様替えの 4 札・写真・図鑑・家具を持ち上げる・回す）を、既定の文字と大きい文字で撮り、
    /// **重なる・切れる・押せる範囲が小さい**を要素の枠で、**部屋の絵が上へ押し出されて切れる**を画素で確かめる。
    /// owner の実機で、模様替えの見本の名前が下の説明と重なり、札がタブの下線にかぶり、部屋の絵の上が切れていた
    func testCapturesCamperRoomPanels() {
        executionTimeAllowance = 1500
        for (extra, tag) in [([String](), ""), (Self.largeText, "・大きい文字")] {
            let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES"] + extra)
            XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない\(tag)")
            guard waitRoom(app, "camper.room.scene", "camper-room-ready") else { XCTFail("部屋を組み終えない\(tag)"); continue }
            tourRoomPanels(app, tag: tag)
            app.terminate()
        }
        // 家具を持ち上げた途中（置く場面）
        let lift = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomLift", "YES"])
        XCTAssertTrue(openCamperRoom(lift), "とおまわり号の中に入れない（持ち上げ）")
        if waitRoom(lift, "camper.room.scene", "camper-room-ready", timeout: 90) {
            shoot(lift, "96p-部屋の下の板（家具を持ち上げた途中）")
            checkRoomPanel(lift, "持ち上げ", ids: ["camper.room.undo", "camper.room.redo", "camper.room.done", "camper.room.tab.floor",
                                                    "camper.room.tab.wall", "camper.room.tab.ceiling"],
                           groups: ["camper.room.tray.cat.@camper.room.trayCats"])
        } else {
            XCTFail("部屋を組み終えない（持ち上げ）")
        }
        lift.terminate()
        // 家具を選んだ時の「回す・しまう」（`-JPPreviewCamperRoomSelect`）
        let select = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperRoomSelect", "YES"])
        XCTAssertTrue(openCamperRoom(select), "とおまわり号の中に入れない（選ぶ）")
        guard waitRoom(select, "camper.room.scene", "camper-room-ready") else { return XCTFail("部屋を組み終えない（選ぶ）") }
        let rotate = select.buttons["camper.room.rotate"].firstMatch
        XCTAssertTrue(rotate.waitForExistence(timeout: 5), "家具を選んでも「回す」が出ない")
        shoot(select, "96q-部屋の下の板（家具を選んだ・回す・しまう）")
        let scene = select.descendants(matching: .any)["camper.room.scene"].firstMatch.frame
        var floating: [(String, CGRect)] = []
        for id in ["camper.room.rotate", "camper.room.stow", "camper.room.resetView"] {
            let b = select.buttons[id].firstMatch
            guard b.exists else { continue }
            floating.append((id, b.frame))
            XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(id) が 44pt 未満")
            XCTAssertGreaterThanOrEqual(b.frame.width, 44, "\(id) の幅が 44pt 未満")
            XCTAssertTrue(scene.insetBy(dx: -1, dy: -1).contains(b.frame), "\(id) が部屋の絵の外へはみ出す（\(b.frame) / \(scene)）")
        }
        assertNoOverlap(floating, "回す・しまう")
        if rotate.exists, rotate.isHittable {
            rotate.tap()
            Thread.sleep(forTimeInterval: 1.5)
            shoot(select, "96r-部屋の下の板（回した後）")
            XCTAssertTrue(select.buttons["camper.room.rotate"].firstMatch.exists, "回したら「回す」が消えた（続けて回せない）")
        }
    }

    /// 家 → 模様替え（4 札）→ 写真 → 置く → 図鑑 の順に撮って確かめる
    private func tourRoomPanels(_ app: XCUIApplication, tag: String) {
        shoot(app, "96k-部屋の下の板（家\(tag)）")
        checkRoomPanel(app, "家\(tag)", ids: ["camper.room.counts", "camper.room.tool.place", "camper.room.tool.style",
                                               "camper.room.tool.photos", "camper.room.tool.dex", "camper.room.hint"])
        checkRoomPicture(app, "家\(tag)")

        // 模様替え
        app.buttons["camper.room.tool.style"].firstMatch.tap()
        let done = app.buttons["camper.room.styleDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "模様替えにならない\(tag)")
        for (tab, name) in [("wall", "壁紙"), ("floor", "床"), ("curtain", "カーテン"), ("light", "灯り")] {
            let t = app.buttons["camper.room.tab.\(tab)"].firstMatch
            guard t.exists else { XCTFail("模様替えの「\(name)」の札が無い\(tag)"); continue }
            revealInPanel(app, t)
            t.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "96l-部屋の下の板（模様替え・\(name)\(tag)）")
            let label = "模様替え・\(name)\(tag)"
            checkRoomPanel(app, label, ids: ["camper.room.tab.wall", "camper.room.tab.floor", "camper.room.tab.curtain",
                                             "camper.room.tab.light", "camper.room.styleDone"],
                           groups: ["camper.room.style."])
            // 見本の札は、タブの下線より下・説明より上（owner の実機で札が下線にかぶり、名前が説明と重なった）
            let tabBottom = app.buttons["camper.room.tab.\(tab)"].firstMatch.frame.maxY
            let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "camper.room.style."))
            XCTAssertGreaterThan(swatches.count, 1, "\(label): 見本が 1 つ以下")
            let note = app.staticTexts["camper.room.styleNote"].firstMatch
            for i in 0..<min(swatches.count, 8) {
                let s = swatches.element(boundBy: i)
                guard s.exists, s.isHittable else { continue }
                XCTAssertGreaterThanOrEqual(s.frame.minY, tabBottom - 0.5, "\(label): 見本 \(s.identifier) がタブの下線にかぶる")
                // 見本の四角（64）と名前の行が札の枠に収まっている（枠が潰れると名前が下へはみ出して重なる）
                XCTAssertGreaterThanOrEqual(s.frame.height, 84, "\(label): 見本 \(s.identifier) の枠が低い（名前がはみ出す・\(s.frame.height)pt）")
                if note.exists { XCTAssertLessThanOrEqual(s.frame.maxY, note.frame.minY + 0.5, "\(label): 見本 \(s.identifier) が説明と重なる") }
            }
            // 灯りの札は夜にして見せる（暗いので画素の明るさでは部屋の枠を測れない）
            if tab != "light" { checkRoomPicture(app, label) }
        }
        // 何も変えていない時に「これにする」を光らせない（2026-10-22 owner）
        XCTAssertFalse(done.label.contains("これにする"), "模様替えで何も変えていないのに「これにする」（今は「\(done.label)」）")
        // 持っていない柄は鍵の札。押すと部屋で見本を試せ、どうすれば届くかと外まわりの図鑑への道が出る
        let wallTab = app.buttons["camper.room.tab.wall"].firstMatch
        revealInPanel(app, wallTab)
        wallTab.tap()
        let locked = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                      "camper.room.style.", "まだ持っていません")).firstMatch
        if locked.waitForExistence(timeout: 3) {
            revealInPanel(app, locked)
            locked.tap()
            let card = app.descendants(matching: .any)["camper.room.styleTrial"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 3), "持っていない柄を押しても見本の札が出ない\(tag)")
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "96l-部屋の下の板（模様替え・持っていない柄を試す\(tag)）")
            checkRoomPanel(app, "模様替え・見本\(tag)", ids: ["camper.room.styleTrialEnd", "camper.room.styleCollect", "camper.room.styleDone"])
            let end = app.buttons["camper.room.styleTrialEnd"].firstMatch
            revealInPanel(app, end)
            end.tap()
            XCTAssertFalse(card.waitForExistence(timeout: 2), "「見本をやめる」で見本の札が消えない\(tag)")
        } else {
            XCTFail("壁紙に持っていない柄の札（鍵）が無い\(tag)")
        }
        // 持っている柄に変えたら「元に戻す」と「これにする」。戻したら「閉じる」
        let curtainTab = app.buttons["camper.room.tab.curtain"].firstMatch
        revealInPanel(app, curtainTab)
        curtainTab.tap()
        let indigo = app.buttons["camper.room.style.indigo"].firstMatch
        revealInPanel(app, indigo)
        indigo.tap()
        let revert = app.buttons["camper.room.styleRevert"].firstMatch
        XCTAssertTrue(revert.waitForExistence(timeout: 3), "柄を変えても「元に戻す」が出ない\(tag)")
        XCTAssertTrue(done.label.contains("これにする"), "柄を変えたのに主ボタンが「これにする」でない（今は「\(done.label)」）")
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "96l-部屋の下の板（模様替え・変えた後\(tag)）")
        checkRoomPanel(app, "模様替え・変えた後\(tag)", ids: ["camper.room.styleRevert", "camper.room.styleDone"])
        revealInPanel(app, revert)
        revert.tap()
        XCTAssertFalse(revert.waitForExistence(timeout: 2), "「元に戻す」で戻らない\(tag)")
        XCTAssertFalse(done.label.contains("これにする"), "戻したのに「これにする」のまま\(tag)")
        // 部屋のタブを替えたら、前の部屋の柄・見本を持ち越さない（確かめ役 2026-10-22: 部屋 B で何も触らないのに
        // 「これにする／元に戻す」が光り、「元に戻す」で部屋 A の柄が B に書かれた）
        let rooms = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "camper.room.room."))
        if rooms.count > 1, rooms.element(boundBy: 1).isHittable {
            revealInPanel(app, indigo)
            indigo.tap()
            XCTAssertTrue(revert.waitForExistence(timeout: 3), "柄を変えても「元に戻す」が出ない（部屋を替える前）\(tag)")
            // 大きい文字では横に送る部屋のタブが、画面に見えていても XCUI が「押せない」と言うことがある（run 679）。
            // 札の真ん中の点を押す
            rooms.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            waitRoom(app, "camper.room.scene", "camper-room-ready")
            XCTAssertTrue(rooms.element(boundBy: 1).isSelected, "部屋のタブを押しても部屋が替わらない\(tag)")
            XCTAssertFalse(revert.exists, "部屋を替えたのに「元に戻す」が残る\(tag)")
            XCTAssertFalse(done.label.contains("これにする"), "部屋を替えて何も触らないのに「これにする」（今は「\(done.label)」）\(tag)")
            XCTAssertFalse(app.descendants(matching: .any)["camper.room.styleTrial"].firstMatch.exists, "前の部屋の見本が残る\(tag)")
            shoot(app, "96l-部屋の下の板（模様替え・部屋を替えた後\(tag)）")
            rooms.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            waitRoom(app, "camper.room.scene", "camper-room-ready")
        } else {
            XCTFail("部屋のタブが 2 つ以上無い・押せない\(tag)")
        }
        revealInPanel(app, done)
        done.tap()
        XCTAssertTrue(app.buttons["camper.room.tool.photos"].firstMatch.waitForExistence(timeout: 5), "模様替えを閉じられない\(tag)")

        // 写真を飾る
        app.buttons["camper.room.tool.photos"].firstMatch.tap()
        if app.buttons["camper.room.frame"].firstMatch.waitForExistence(timeout: 10) {
            _ = app.buttons["camper.room.photo"].firstMatch.waitForExistence(timeout: 20)
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "96m-部屋の下の板（写真\(tag)）")
            checkRoomPanel(app, "写真\(tag)", ids: ["camper.room.hang"],
                           groups: ["camper.room.frame@camper.room.frames", "camper.room.photo@camper.room.photoGrid"])
        } else {
            XCTFail("飾る額の一覧が出ない\(tag)")
        }
        app.buttons["camper.room.back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["camper.room.tool.place"].firstMatch.waitForExistence(timeout: 5), "写真から部屋に戻れない\(tag)")

        // 置く
        app.buttons["camper.room.tool.place"].firstMatch.tap()
        XCTAssertTrue(app.buttons["camper.room.done"].firstMatch.waitForExistence(timeout: 5), "置く場面にならない\(tag)")
        // 押した直後から部屋が描かれている（置くの場面だけ立体を作り直し、組み上がるまで部屋が消えていた・run 666）
        Thread.sleep(forTimeInterval: 0.3)
        assertRoomDrawn(app, "置くを押した直後\(tag)")
        Thread.sleep(forTimeInterval: 1.7)
        shoot(app, "96n-部屋の下の板（置く\(tag)）")
        checkRoomPanel(app, "置く\(tag)", ids: ["camper.room.undo", "camper.room.redo", "camper.room.done", "camper.room.tab.floor",
                                                 "camper.room.tab.wall", "camper.room.tab.ceiling"],
                       groups: ["camper.room.tray.cat.@camper.room.trayCats", "camper.room.tray.@camper.room.trayGrid"])
        checkRoomPicture(app, "置く\(tag)")
        app.buttons["camper.room.done"].firstMatch.tap()

        // 図鑑
        let dex = app.buttons["camper.room.tool.dex"].firstMatch
        XCTAssertTrue(dex.waitForExistence(timeout: 5), "置くから部屋に戻れない\(tag)")
        dex.tap()
        let close = app.buttons["camper.room.dex.close"].firstMatch
        if close.waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 3)
            shoot(app, "96o-部屋の下の板（図鑑\(tag)）")
            XCTAssertGreaterThanOrEqual(close.frame.height, 44, "図鑑の「閉じる」が 44pt 未満\(tag)")
            XCTAssertTrue(close.isHittable, "図鑑の「閉じる」を押せない\(tag)")
            // 置き場所のタブの数が 1 字ずつ折れない（大きい文字で「474/1,19」「2」と折れた・run 666）
            var tabBoxes: [(String, CGRect)] = []
            for p in ["floor", "wall", "ceiling"] {
                let t = app.buttons["camper.room.dex.tab.\(p)"].firstMatch
                guard t.exists, t.isHittable else { continue }
                tabBoxes.append((p, t.frame))
                XCTAssertGreaterThanOrEqual(t.frame.height, 44, "図鑑のタブ \(p) が 44pt 未満\(tag)")
                XCTAssertLessThan(t.frame.height, 90, "図鑑のタブ \(p) の字が折れて縦に伸びた（\(t.frame.height)pt）\(tag)")
            }
            XCTAssertFalse(tabBoxes.isEmpty, "図鑑の置き場所のタブが見えない\(tag)")
            assertNoOverlap(tabBoxes, "図鑑のタブ\(tag)")
            close.tap()
        } else {
            XCTFail("家具の図鑑が開かない\(tag)")
        }
    }

    /// 下の板の要素が、画面の中・部屋の絵の下にあり、押せる物は 44pt 以上で、互いに重ならない。
    /// `groups` は識別子の頭で集める（いま押せる物だけ）。「頭@入れ物の識別子」なら、送る一覧（入れ物）の中に丸ごと見えている物だけ
    /// （一覧の端で切れて見えている升は、入れ物が切っているので重なり・はみ出しに数えない）
    private func checkRoomPanel(_ app: XCUIApplication, _ label: String, ids: [String], groups: [String] = []) {
        let window = app.windows.firstMatch.frame
        let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
        // 大きい文字では板を送る。1 つずつ見える所まで送って、見えて押せるか・44pt かを見る（切れて届かないなら落とす）
        for id in ids {
            let e = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(e.exists, "\(label): \(id) が無い")
            guard e.exists else { continue }
            revealInPanel(app, e)
            XCTAssertTrue(e.isHittable, "\(label): \(id) が見えない・届かない（板の外へ切れる・\(e.frame)）")
            if e.elementType == .button { checkTarget(e, id, label) }
        }
        // いま見えている物どうしで、画面の外・部屋の絵に掛かる・重なるを見る
        var boxes: [(String, CGRect)] = []
        var lines: [String] = ["窓 \(window)", "部屋の絵 \(scene.exists ? "\(scene.frame)" : "無し")"]
        for id in ids {
            let e = app.descendants(matching: .any)[id].firstMatch
            guard e.exists, e.isHittable else { continue }
            boxes.append((id, e.frame))
            lines.append("\(id) \(e.frame)")
        }
        for group in groups {
            let parts = group.split(separator: "@").map(String.init)
            let prefix = parts[0]
            let box = parts.count > 1 ? app.descendants(matching: .any)[parts[1]].firstMatch : nil
            if let box { XCTAssertTrue(box.exists, "\(label): 一覧 \(parts[1]) が無い") }
            let q = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            for i in 0..<min(q.count, 16) {
                let e = q.element(boundBy: i)
                guard e.exists, e.isHittable else { continue }
                if let box, box.exists, !box.frame.insetBy(dx: -1, dy: -1).contains(e.frame) { continue }
                let id = "\(e.identifier)#\(i)"
                boxes.append((id, e.frame))
                lines.append("\(id) \(e.frame)")
                checkTarget(e, id, label)
            }
        }
        let note = XCTAttachment(string: lines.joined(separator: "\n"))
        note.name = "96-部屋の下の板の枠（\(label)）"
        note.lifetime = .keepAlways
        add(note)
        for (id, f) in boxes {
            XCTAssertTrue(window.insetBy(dx: -0.5, dy: -0.5).contains(f), "\(label): \(id) が画面の外へ切れる（\(f)）")
            if scene.exists {
                XCTAssertGreaterThanOrEqual(f.minY, scene.frame.maxY - 0.5, "\(label): \(id) が部屋の絵に掛かる（\(f) / \(scene.frame)）")
            }
        }
        assertNoOverlap(boxes, label)
    }

    /// 下の板を送って `element` を見える所へ出す（送れない板・もう見えている時は何もしない）。板の左の縁を引く（部屋の絵は回さない）
    private func revealInPanel(_ app: XCUIApplication, _ element: XCUIElement) {
        let window = app.windows.firstMatch
        let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
        var pushes = 0
        // 少しでも見えていると押せる扱いになる。丸ごと画面に入るまで送る（大きい文字で下端が切れた・run 672）
        while element.exists, !(element.isHittable && window.frame.contains(element.frame)), pushes < 6 {
            let above = scene.exists && element.frame.minY < scene.frame.maxY
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: above ? 0.74 : 0.94))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: above ? 0.9 : 0.78))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
            Thread.sleep(forTimeInterval: 0.6)
            pushes += 1
        }
    }

    private func checkTarget(_ e: XCUIElement, _ id: String, _ label: String) {
        // 端数（43.99999）は 44 と見る
        XCTAssertGreaterThanOrEqual(e.frame.height, 43.9, "\(label): \(id) の高さが 44pt 未満（\(e.frame.height)）")
        XCTAssertGreaterThanOrEqual(e.frame.width, 43.9, "\(label): \(id) の幅が 44pt 未満（\(e.frame.width)）")
    }

    /// 枠どうしが重ならない（片方がもう片方を丸ごと含むのは、札の中の印なので除く）
    private func assertNoOverlap(_ boxes: [(String, CGRect)], _ label: String) {
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                let a = boxes[i].1, b = boxes[j].1
                let x = a.intersection(b)
                guard !x.isNull, x.width > 1, x.height > 1, !a.contains(b), !b.contains(a) else { continue }
                XCTFail("\(label): \(boxes[i].0) と \(boxes[j].0) が重なる（\(a) / \(b)）")
            }
        }
    }

    /// 部屋の絵（箱庭）が十分な高さで、上下どちらにも切れず、上下の空きが釣り合っている（画素で見る）。
    /// owner の実機（2026-10-22）で、絵が上へ押し出されて切れ、下に大きな黒い空きがあった
    private func checkRoomPicture(_ app: XCUIApplication, _ label: String) {
        let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
        guard scene.exists else { return XCTFail("\(label): 部屋の絵が無い") }
        XCTAssertGreaterThanOrEqual(scene.frame.height, 220, "\(label): 部屋の絵が低い（\(scene.frame.height)pt）")
        guard let rows = Self.litRows(scene.screenshot().image) else { return XCTFail("\(label): 部屋の絵を読めない") }
        guard let top = rows.firstIndex(where: { $0 }), let bottom = rows.lastIndex(where: { $0 }) else {
            return XCTFail("\(label): 部屋が描かれていない（明るい画素が無い）")
        }
        let n = Double(rows.count)
        let above = Double(top) / n, below = Double(rows.count - 1 - bottom) / n
        print("CAMPERROOM \(label) 絵 \(scene.frame) 上の空き \(above) 下の空き \(below)")
        XCTAssertGreaterThan(above, 0.005, "\(label): 部屋の絵の上が切れている")
        XCTAssertGreaterThan(below, 0.005, "\(label): 部屋の絵の下が切れている")
        XCTAssertLessThan(abs(above - below), 0.3, "\(label): 部屋が上か下へ寄っている（上の空き \(above)・下の空き \(below)）")
    }

    /// 部屋の絵に部屋が描かれている（明るい行が絵の 1 割以上）。組み直しの途中の暗い地だけなら落とす
    private func assertRoomDrawn(_ app: XCUIApplication, _ label: String) {
        let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
        guard scene.exists, let rows = Self.litRows(scene.screenshot().image) else { return XCTFail("\(label): 部屋の絵を読めない") }
        let lit = rows.filter { $0 }.count
        XCTAssertGreaterThan(Double(lit), Double(rows.count) * 0.1, "\(label): 部屋が描かれていない（明るい行 \(lit) / \(rows.count)）")
    }

    /// 行ごとに「部屋が写っているか」（明るさ 60 を超える画素が幅の 3% 以上）。暗い地（0x1D1B14 から黒）は数えない
    private static func litRows(_ image: UIImage) -> [Bool]? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 8, h > 8 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (0..<h).map { y in
            var lit = 0
            for x in stride(from: 0, to: w, by: 2) {
                let k = (y * w + x) * 4
                let l = 0.299 * Double(bytes[k]) + 0.587 * Double(bytes[k + 1]) + 0.114 * Double(bytes[k + 2])
                if l > 60 { lit += 1 }
            }
            return Double(lit) > Double(w / 2) * 0.03
        }
    }

    // MARK: - 大きい文字（Dynamic Type・2026-10-21）

    /// 文字の大きさの設定をアクセシビリティの XL にして起動する鍵（シミュレータの設定を変えずに、このアプリだけ）
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]

    /// 決まった所（画面の割合 `x`・`from` → `to`）から指で上へ送り、`element` の下端が下の帯（タブ）より上に来たら止める
    /// （12回まで）。送り過ぎると上の立体の車の下へ隠れるので、押せるかでは続けない（Mac run 631）。
    /// `swipeUp` は画面の真ん中から払うので、真ん中に回す物（立体の車・きっぷ）がある画面では送れない
    private func dragUp(_ app: XCUIApplication, until element: XCUIElement, x: CGFloat = 0.5, from: CGFloat, to: CGFloat) {
        let window = app.windows.firstMatch
        let bottom = window.frame.maxY - 120
        var pushes = 0
        while element.exists, element.frame.maxY > bottom, pushes < 12 {
            // ゆっくり引いて、離す前に止める（勢いが残ると目当てを越えて上の車の下へ隠れる・Mac run 647）
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: from))
                .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: to)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
    }

    // MARK: - とおまわり号の描画を測る（2026-10-31・#430「キャンピングカーの描画を軽くする」）
    //
    // 外観（昼）・灯り（外の夜）・部屋（昼・夜）を開いて数秒動かし、次を取る。見本の起動（`-JPPreviewCamperPerf YES`）だけ数える。
    // - XCTest の measure: アプリの CPU（`XCTCPUMetric`）・メモリ（`XCTMemoryMetric`）・1 コマと値渡しの印の時間
    //   （`XCTOSSignpostMetric`・アプリの `CamperRenderMark`）。ログの `measured [` の行に出る
    // - アプリの数（`CamperRenderProbe` の読み上げの値）の前後の差: 1 コマの回数・毎秒のコマ・平均・16.7 ms を越えたコマ・
    //   値渡しの回数。ログの `CAMPERPERF:` の行と、注記（`計測（とおまわり号の描画・…）`・screenshots の枝の .txt）に残す
    // 普段の回（PR の検証・TestFlight）では流さない（`Tools/pick-ui-tests.py` の `ONLY_WHEN_NAMED`）。
    // 名指しは `screens=testMeasuresCamperRender`。値は Mac の CI のシミュレーターのもの（実機ではない）

    /// アプリの `CamperRenderMeter.subsystem`・`category` と同じ字
    private static let camperRenderSubsystem = "com.journeyphoto.camper"
    private static let camperRenderCategory = "CamperRender"
    /// measure の回数（1 回 4〜6 秒）
    private static let camperRenderIterations = 3

    struct CamperRenderTally {
        var count = 0
        var ms = 0.0
        var max = 0.0
        var slow = 0
        /// アプリ全体（`Process`）の CPU の時間の合計（ms）とメモリ（MB）
        var cpuMs = 0.0
        var memMB = 0.0
        /// メモリの内訳（`task_vm_info` の internal・compressed・device・MB・2026-11-07）
        var intMB = 0.0
        var cmpMB = 0.0
        var devMB = 0.0
        /// 場面の中身の数（`SceneExterior`・`SceneRoom`・`CamperSceneStats`）の「欄=値」の原文（2026-11-06・メモリの内訳）
        var raw = ""
    }

    /// アプリの数を読む（`CamperRenderMeter.summary` の「名前 n= ms= max= slow=;」）
    private func camperMeter(_ app: XCUIApplication, _ id: String) -> [String: CamperRenderTally] {
        let probe = app.descendants(matching: .any)[id].firstMatch
        guard probe.waitForExistence(timeout: 5) else { return [:] }
        // 読み上げの値は 0.5 秒ごとに読み直される。いちばん新しい値を読む
        Thread.sleep(forTimeInterval: 0.6)
        var out: [String: CamperRenderTally] = [:]
        for entry in ((probe.value as? String) ?? "").split(separator: ";") {
            let words = entry.split(separator: " ")
            guard let name = words.first else { continue }
            var t = CamperRenderTally()
            t.raw = words.dropFirst().joined(separator: " ")
            for w in words.dropFirst() {
                let kv = w.split(separator: "=")
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "n": t.count = Int(kv[1]) ?? 0
                case "ms": t.ms = Double(kv[1]) ?? 0
                case "max": t.max = Double(kv[1]) ?? 0
                case "slow": t.slow = Int(kv[1]) ?? 0
                case "cpu_ms": t.cpuMs = Double(kv[1]) ?? 0
                case "mem_mb": t.memMB = Double(kv[1]) ?? 0
                case "int_mb": t.intMB = Double(kv[1]) ?? 0
                case "cmp_mb": t.cmpMB = Double(kv[1]) ?? 0
                case "dev_mb": t.devMB = Double(kv[1]) ?? 0
                default: break
                }
            }
            out[String(name)] = t
        }
        return out
    }

    /// 1 つの場面の前後の差を行にする（ログの `CAMPERPERF:` と注記の両方へ）
    private func camperPhase(_ app: XCUIApplication, probe id: String, _ label: String, lines: inout [String], _ body: () -> Void) {
        let before = camperMeter(app, id)
        let start = Date()
        body()
        let seconds = Date().timeIntervalSince(start)
        let after = camperMeter(app, id)
        if after.isEmpty { lines.append("\(label): 数が読めない（\(id) が無い）") }
        if let a = after["Process"] {
            let b = before["Process"] ?? a
            let cpu = a.cpuMs - b.cpuMs
            // アプリの CPU（1 コア＝100%）とメモリ（前 → 後）
            lines.append(String(format: "%@ | Process cpu_ms=%.0f cpu_pct=%.1f mem_mb_before=%.1f mem_mb_after=%.1f secs=%.1f",
                                label, cpu, cpu / max(seconds, 0.001) / 10, b.memMB, a.memMB, seconds))
        }
        for key in after.keys.sorted() where key != "Process" {
            // 場面の中身の数（回数・時間ではない）は、欄の原文をそのまま残す（メモリの内訳・#430）
            if key.hasPrefix("Scene") {
                lines.append("\(label) | \(key) \(after[key]!.raw)")
                continue
            }
            let a = after[key]!, b = before[key] ?? CamperRenderTally()
            let n = a.count - b.count
            let ms = a.ms - b.ms
            let avg = n > 0 ? ms / Double(n) : 0
            lines.append(String(format: "%@ | %@ n=%d per_s=%.1f avg_ms=%.2f total_ms=%.1f slow=%d max_all_ms=%.2f secs=%.1f",
                                label, key, n, Double(n) / max(seconds, 0.001), avg, ms, a.slow - b.slow, a.max, seconds))
        }
    }

    private func camperRenderMetrics(_ app: XCUIApplication, _ names: [String]) -> [XCTMetric] {
        var metrics: [XCTMetric] = [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]
        for n in names {
            metrics.append(XCTOSSignpostMetric(subsystem: Self.camperRenderSubsystem, category: Self.camperRenderCategory, name: n))
        }
        return metrics
    }

    private func camperRenderOptions() -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = Self.camperRenderIterations
        return o
    }

    /// 指 1 本で横に引いて回す（行って戻る。ゆっくりの指で 1 回 2 秒ほど）
    private func camperSpin(_ scene: XCUIElement, times: Int = 2) {
        for i in 0..<times {
            let left = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            let right = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            let (from, to) = i % 2 == 0 ? (right, left) : (left, right)
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.05)
        }
    }

    /// 測った行をログと注記に残す
    private func camperReport(_ title: String, _ lines: [String]) {
        for line in lines { print("CAMPERPERF: \(name) \(line)") }
        let text = XCTAttachment(string: lines.joined(separator: "\n"))
        text.name = "計測（とおまわり号の描画・\(title)）"
        text.lifetime = .keepAlways
        add(text)
    }

    /// **外観（昼）**: 止まっている 3 秒・指で回す（measure）・回した後の 3 秒
    func testMeasuresCamperRenderExterior() {
        executionTimeAllowance = 600
        let app = launchTrunk(["-JPPreviewCamperPerf", "YES"])
        XCTAssertTrue(openCamper(app), "キャンピングカーの画面が開かない")
        guard waitCamper(app, "camper-ready") else { return XCTFail("キャンピングカーを組み終えない") }
        let scene = app.descendants(matching: .any)["camper.scene"].firstMatch
        let probe = "camper.perf.exterior"
        var lines: [String] = []
        camperPhase(app, probe: probe, "外観・昼・止まっている", lines: &lines) { Thread.sleep(forTimeInterval: 3) }
        camperPhase(app, probe: probe, "外観・昼・回す（measure 全回）", lines: &lines) {
            measure(metrics: camperRenderMetrics(app, ["CamperExteriorFrame", "CamperExteriorUpdate"]), options: camperRenderOptions()) {
                self.camperSpin(scene)
            }
        }
        camperPhase(app, probe: probe, "外観・昼・回した後に止まっている", lines: &lines) { Thread.sleep(forTimeInterval: 3) }
        shoot(app, "95x1-計測（外観・昼）")
        camperReport("外観・昼", lines)
    }

    /// **灯り（外の夜）**: 炎が揺れている夜の外を止めたまま（measure）・回す・中に入っている間の外（描き続けていないか）
    func testMeasuresCamperRenderNight() {
        executionTimeAllowance = 600
        let app = launchTrunk(["-JPPreviewCamperPerf", "YES"])
        XCTAssertTrue(openCamper(app), "キャンピングカーの画面が開かない")
        guard waitCamper(app, "camper-ready") else { return XCTFail("キャンピングカーを組み終えない") }
        let night = app.buttons["camper.mood.night"].firstMatch
        guard night.waitForExistence(timeout: 5) else { return XCTFail("夜のボタンが無い") }
        night.tap()
        waitCamper(app, "night")
        let scene = app.descendants(matching: .any)["camper.scene"].firstMatch
        var lines: [String] = []
        camperPhase(app, probe: "camper.perf.exterior", "外の夜・止まっている（measure 全回）", lines: &lines) {
            measure(metrics: camperRenderMetrics(app, ["CamperExteriorFrame", "CamperExteriorUpdate"]), options: camperRenderOptions()) {
                Thread.sleep(forTimeInterval: 4)
            }
        }
        camperPhase(app, probe: "camper.perf.exterior", "外の夜・回す", lines: &lines) { camperSpin(scene) }
        shoot(app, "95x2-計測（外の夜）")
        // 中に入る（外の車は画面から外れる）。部屋を組み終えてから、外が描き続けていないかを見る
        let enter = app.buttons["camper.room.enter"].firstMatch
        guard enter.waitForExistence(timeout: 10) else { return XCTFail("「中に入る」が無い") }
        if !enter.isHittable { scrollTo(enter, in: app) }
        enter.tap()
        XCTAssertTrue(waitRoom(app, "camper.room.scene", "camper-room-ready"), "部屋を組み終えない")
        camperPhase(app, probe: "camper.perf.room", "外の夜から入った部屋・止まっている（外の車のコマを見る）", lines: &lines) {
            Thread.sleep(forTimeInterval: 4)
        }
        shoot(app, "95x3-計測（外の夜から入った部屋）")
        camperReport("外の夜", lines)
    }

    /// **部屋（昼）**: 止まっている 3 秒・指で回す（measure）
    func testMeasuresCamperRenderRoom() {
        measureCamperRoom(night: false)
    }

    /// **部屋（夜の灯り）**: 夜にして、止まっている 3 秒・指で回す（measure）
    func testMeasuresCamperRenderRoomNight() {
        measureCamperRoom(night: true)
    }

    private func measureCamperRoom(night: Bool) {
        executionTimeAllowance = 600
        let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperPerf", "YES"])
        XCTAssertTrue(openCamperRoom(app), "とおまわり号の中に入れない")
        guard waitRoom(app, "camper.room.scene", "camper-room-ready") else { return XCTFail("部屋を組み終えない") }
        let label = night ? "部屋・夜" : "部屋・昼"
        if night {
            app.buttons["camper.room.night"].firstMatch.tap()
            XCTAssertTrue(waitRoom(app, "camper.room.scene", "night"), "夜にならない")
        }
        let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
        let probe = "camper.perf.room"
        var lines: [String] = []
        camperPhase(app, probe: probe, "\(label)・止まっている", lines: &lines) { Thread.sleep(forTimeInterval: 3) }
        camperPhase(app, probe: probe, "\(label)・回す（measure 全回）", lines: &lines) {
            measure(metrics: camperRenderMetrics(app, ["CamperRoomFrame", "CamperRoomUpdate", "CamperRoomPhotoImages", "CamperRoomPhotosMode",
                                                        "CamperRoomShow"]),
                    options: camperRenderOptions()) {
                self.camperSpin(scene)
            }
        }
        camperPhase(app, probe: probe, "\(label)・回した後に止まっている", lines: &lines) { Thread.sleep(forTimeInterval: 3) }
        shoot(app, night ? "95x5-計測（部屋・夜）" : "95x4-計測（部屋・昼）")
        camperReport(label, lines)
    }

    // MARK: - とおまわり号のメモリの内訳（2026-11-07・札 #430・測るだけ）
    //
    // 外観を開いて組み終えた後 → 「中に入る」で部屋を組み終えた後のアプリ全体のメモリ（phys_footprint）を、
    // SCNView の輪郭のなめらかさ（`-JPPreviewCamperAA none|2x|4x`・外観と部屋の両方）を替えて、各 3 回測る。
    // 毎回アプリを起動し直す。ログの `CAMPERMEM:` の行（値は MB・シミュレータ）。名指しは `screens=testMeasuresCamperMemory`

    private func measureCamperMemory(aa: String, runs: Int = 3) {
        executionTimeAllowance = 1100
        var lines: [String] = []
        for run in 1...runs {
            let app = launchTrunk(["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperPerf", "YES", "-JPPreviewCamperAA", aa])
            defer { app.terminate() }
            guard openCamper(app), waitCamper(app, "camper-ready") else { XCTFail("外観を組み終えない（\(aa) \(run) 回目）"); continue }
            let ext = camperMeter(app, "camper.perf.exterior")
            let enter = app.buttons["camper.room.enter"].firstMatch
            guard enter.waitForExistence(timeout: 15) else { XCTFail("「中に入る」が無い"); continue }
            if !enter.isHittable { scrollTo(enter, in: app) }
            enter.tap()
            guard waitRoom(app, "camper.room.scene", "camper-room-ready") else { XCTFail("部屋を組み終えない（\(aa) \(run) 回目）"); continue }
            Thread.sleep(forTimeInterval: 3)
            let room = camperMeter(app, "camper.perf.room")
            Thread.sleep(forTimeInterval: 5)
            let late = camperMeter(app, "camper.perf.room")
            let e = ext["Process"] ?? CamperRenderTally(), r = room["Process"] ?? CamperRenderTally(), l = late["Process"] ?? CamperRenderTally()
            lines.append(String(format: "CAMPERMEM aa=%@ run=%d ext_mb=%.1f room_mb=%.1f delta_mb=%.1f room_late_mb=%.1f | ext int=%.1f cmp=%.1f dev=%.1f | room int=%.1f cmp=%.1f dev=%.1f | SceneExterior %@ | SceneRoom %@",
                                aa, run, e.memMB, r.memMB, r.memMB - e.memMB, l.memMB, e.intMB, e.cmpMB, e.devMB, r.intMB, r.cmpMB, r.devMB,
                                ext["SceneExterior"]?.raw ?? "-", room["SceneRoom"]?.raw ?? "-"))
        }
        for line in lines { print("CAMPERMEM: \(line)") }
        let text = XCTAttachment(string: lines.joined(separator: "\n"))
        text.name = "計測（とおまわり号のメモリ・\(aa)）"
        text.lifetime = .keepAlways
        add(text)
        XCTAssertEqual(lines.count, runs, "測れなかった回がある")
    }

    func testMeasuresCamperMemoryAA4x() { measureCamperMemory(aa: "4x") }
    func testMeasuresCamperMemoryAA2x() { measureCamperMemory(aa: "2x") }
    func testMeasuresCamperMemoryAANone() { measureCamperMemory(aa: "none") }

    // MARK: - とおまわり号のメモリ: 途中の段・user_tag 別・差し替え（2026-11-07・札 #430・測るだけ）
    //
    // アプリ側の `CamperRenderMeter.mark`（組む途中の段）と `vmTagSummary`（user_tag 別）を、段ごとに読んでログ（`CAMPERSTAGE:`）に出す。
    // 差し替え（`-JPPreviewCamperDiag lightbed|lightfurniture|halftex`）は測定専用。名指しは `screens=testMeasuresCamperStages`

    /// 読み上げの値から、段・家具・殻・場面の数の行を 1 本ずつ出す
    private func camperStageDump(_ app: XCUIApplication, probe id: String, _ label: String) {
        let probeElement = app.descendants(matching: .any)[id].firstMatch
        guard probeElement.waitForExistence(timeout: 5) else { print("CAMPERSTAGE: \(label) | 数が読めない（\(id) が無い）"); return }
        Thread.sleep(forTimeInterval: 0.6)
        let value = (probeElement.value as? String) ?? ""
        for entry in value.split(separator: ";") {
            let t = entry.trimmingCharacters(in: .whitespaces)
            guard let name = t.split(separator: " ").first else { continue }
            if name.hasPrefix("Scene") || name == "Process" { print("CAMPERSTAGE: \(label) | \(t)") }
        }
    }

    private func enterCamperRoom(_ app: XCUIApplication) -> Bool {
        let enter = app.buttons["camper.room.enter"].firstMatch
        guard enter.waitForExistence(timeout: 15) else { return false }
        if !enter.isHittable { scrollTo(enter, in: app) }
        enter.tap()
        return waitRoom(app, "camper.room.scene", "camper-room-ready")
    }

    private func measureCamperStages(diag: String?, aa: String? = nil, runs: Int, full: Bool) {
        executionTimeAllowance = 1150
        let d = diag ?? (aa.map { "aa-\($0)" } ?? "none")
        for run in 1...runs {
            var args = ["-JPPreviewCamperRoomReset", "YES", "-JPPreviewCamperPerf", "YES"]
            if let diag { args += ["-JPPreviewCamperDiag", diag] }
            if let aa { args += ["-JPPreviewCamperAA", aa] }
            let app = launchTrunk(args)
            defer { app.terminate() }
            let tag = "diag=\(d) run=\(run)"
            guard openCamper(app), waitCamper(app, "camper-ready") else { XCTFail("外観を組み終えない（\(tag)）"); continue }
            camperStageDump(app, probe: "camper.perf.exterior", "\(tag) 外観")
            guard enterCamperRoom(app) else { XCTFail("部屋を組み終えない（\(tag)）"); continue }
            Thread.sleep(forTimeInterval: 3)
            camperStageDump(app, probe: "camper.perf.room", "\(tag) 部屋・昼")
            // 軽くする前後の絵の突き合わせ用（screenshots の枝の `95z1-…`）
            if run == 1 { shoot(app, "95z1-計測（部屋・昼・\(d)）") }
            guard full else { continue }
            let night = app.buttons["camper.room.night"].firstMatch
            night.tap()
            XCTAssertTrue(waitRoom(app, "camper.room.scene", "night"), "夜にならない")
            Thread.sleep(forTimeInterval: 3)
            camperStageDump(app, probe: "camper.perf.room", "\(tag) 部屋・夜")
            night.tap()
            XCTAssertTrue(waitRoom(app, "camper.room.scene", "day"), "昼に戻らない")
            Thread.sleep(forTimeInterval: 3)
            camperStageDump(app, probe: "camper.perf.room", "\(tag) 部屋・昼に戻した")
            // 外へ出て、5 秒おいて外の数を読む（部屋の分が戻るか）。もう一度入って出る
            for cycle in 1...2 {
                let back = app.buttons["camper.room.back"].firstMatch
                guard back.waitForExistence(timeout: 10) else { return XCTFail("外へ戻れない") }
                back.tap()
                XCTAssertTrue(app.buttons["camper.room.enter"].firstMatch.waitForExistence(timeout: 15), "外の車に戻らない")
                Thread.sleep(forTimeInterval: 5)
                camperStageDump(app, probe: "camper.perf.exterior", "\(tag) 外へ出た後 \(cycle) 回目")
                if cycle == 1 {
                    guard enterCamperRoom(app) else { return XCTFail("部屋に入り直せない") }
                    Thread.sleep(forTimeInterval: 3)
                    camperStageDump(app, probe: "camper.perf.room", "\(tag) 入り直した部屋")
                }
            }
        }
    }

    /// 軽くした後（既定）と、軽くする前（`keepmesh`）を各 3 回: 段・user_tag・昼夜・外へ出た後。
    /// 輪郭のなめらかさ（AA）は none と 4x（外観と部屋の両方）で入るところまで 3 回ずつ
    func testMeasuresCamperStages() { measureCamperStages(diag: nil, runs: 3, full: true) }
    func testMeasuresCamperStagesKeepMesh() { measureCamperStages(diag: "keepmesh", runs: 3, full: true) }
    func testMeasuresCamperStagesAANone() { measureCamperStages(diag: nil, aa: "none", runs: 3, full: false) }
    func testMeasuresCamperStagesAA4x() { measureCamperStages(diag: nil, aa: "4x", runs: 3, full: false) }

    /// **キャンピングカー（大きい文字）**: 数の札・段が縦に積まれ、字が切れずに押せるか。開けなければ撮らずに抜ける。
    /// **出たのに段のボタンが 44pt 未満・横 3 つのまま（幅が画面の半分に満たない）なら落とす**
    func testCapturesCamperLargeText() {
        let app = launchTrunk(Self.largeText)
        guard openCamper(app) else { return }
        guard waitCamper(app, "camper-ready") else { return XCTFail("キャンピングカーを組み終えない") }
        shoot(app, "95x-大きい文字（キャンピングカー）")
        let stage = app.buttons["camper.stage.van"].firstMatch
        guard stage.exists else { return XCTFail("段のボタンが無い") }
        // 送るのは下の札の所から（上半分は立体の車で、払うと車が回る・Mac run 628 で `swipeUp` が車を回した）
        dragUp(app, until: stage, from: 0.85, to: 0.76)
        XCTAssertTrue(stage.isHittable, "大きい文字で段のボタンまで送れない")
        shoot(app, "95y-大きい文字（キャンピングカー・数と段）")
        let width = app.windows.firstMatch.frame.width
        for id in ["camper.stage.van", "camper.stage.camper", "camper.stage.trailer"] {
            let b = app.buttons[id].firstMatch
            XCTAssertTrue(b.exists, "\(id) が無い")
            guard b.exists else { continue }
            XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(id) が 44pt 未満")
            XCTAssertGreaterThan(b.frame.width, width / 2, "大きい文字なのに段が横に並んだまま（\(id) の幅 \(b.frame.width)）")
        }
    }

    /// **旅のトランク（大きい文字）**: 上と、手持ちのラベルの下のボタン（貼る・作り直す・削除）。開けなければ撮らずに抜ける。
    /// **出たのにボタンが 44pt 未満・押せなければ落とす**
    func testCapturesTrunkLargeText() {
        let app = launchTrunk(["-JPPreviewTrunk", "YES", "-JPPreviewPro", "YES"] + Self.largeText)
        guard openTrunk(app) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "90x-大きい文字（旅のトランク）")
        let pocketRow = app.buttons["trunk.pocket"].firstMatch
        scrollTo(pocketRow, in: app)
        guard pocketRow.isHittable else { return }
        pocketRow.tap()
        let cell = app.buttons["trunk.pocket.cell"].firstMatch
        guard cell.waitForExistence(timeout: 10) else { return }
        cell.tap()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "92x-大きい文字（手持ちのラベル）")
        for id in ["trunk.pocket.stick", "trunk.pocket.reroll", "trunk.pocket.delete"] {
            let button = app.buttons[id].firstMatch
            XCTAssertTrue(button.exists, "\(id) が無い")
            guard button.exists else { continue }
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(id) が 44pt 未満")
            XCTAssertTrue(button.isHittable, "\(id) を押せない")
        }
        // 3つは縦に積まれる（横並びに戻すと上端がそろって落ちる）
        let ys = ["trunk.pocket.stick", "trunk.pocket.reroll", "trunk.pocket.delete"].map { app.buttons[$0].firstMatch.frame.minY }
        XCTAssertTrue(ys[0] < ys[1] && ys[1] < ys[2], "大きい文字なのに手持ちのボタンが縦に積まれていない（上端 \(ys)）")
    }

    /// **すれちがいの束（大きい文字）**: 束の画面は送らないので字の伸びを xxxLarge で止めている（`PassViewerView.typeLimit`）。
    /// 文字をアクセシビリティの XL にしても、下のボタン（ありがとう・帳に入れる）と × が画面の中で押せるか。
    /// 「ありがとう」を押した後（「ありがとうを返しました」・見本の束ではサーバーに送らない）も見る。
    /// 札が出なければ撮らずに抜ける。**出たのにボタンが画面の外・44pt 未満・押せなければ落とす**
    func testCapturesPassViewerLargeText() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewPass", "YES"]
        app.launchArguments += Self.largeText
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let open = app.buttons["pass.home.open"].firstMatch
        guard open.waitForExistence(timeout: 45) else { return }
        scrollTo(open, in: app)
        guard open.isHittable else { return }
        open.tap()
        let card = app.descendants(matching: .any)["pass.viewer.card"].firstMatch
        guard card.waitForExistence(timeout: 10) else { return XCTFail("札を押しても束が開かない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "81x-大きい文字（すれちがいの束）")
        let window = app.windows.firstMatch.frame
        func checkButtons(_ when: String) {
            for (id, name) in [("pass.viewer.close", "閉じる"), ("pass.viewer.thanks", "ありがとう"), ("pass.viewer.file", "帳に入れる")] {
                let b = app.buttons[id].firstMatch
                XCTAssertTrue(b.exists, "\(when)「\(name)」が無い")
                guard b.exists else { continue }
                XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(when)「\(name)」が 44pt 未満")
                XCTAssertTrue(window.contains(b.frame), "\(when)「\(name)」が画面の外（\(b.frame)）")
                XCTAssertTrue(b.isHittable, "\(when)「\(name)」を押せない")
            }
        }
        checkButtons("大きい文字で")
        let thanks = app.buttons["pass.viewer.thanks"].firstMatch
        guard thanks.isHittable else { return }
        thanks.tap()
        let sent = app.buttons["pass.viewer.thanks"].firstMatch
        let done = NSPredicate(format: "label CONTAINS %@", "返しました")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: done, evaluatedWith: sent)], timeout: 5), .completed,
                       "「ありがとう」を押しても「ありがとうを返しました」にならない")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "81y-大きい文字（すれちがいの束・ありがとうを返した）")
        checkButtons("ありがとうの後に")
    }

    /// サポーター証（マイページ → 設定 → サポーター証）まで進める。行が無い（サポーターでない・読めない）なら false
    private func openSupporterCard(_ app: XCUIApplication) -> Bool {
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return false }
        tabBar.buttons.element(boundBy: 4).tap()
        guard app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 15) else { return false }
        let gear = app.buttons["設定"].firstMatch
        guard gear.waitForExistence(timeout: 5), gear.isHittable else { return false }
        gear.tap()
        let row = app.buttons["settings.supporterCard"].firstMatch
        guard row.waitForExistence(timeout: 15) else { return false }
        scrollTo(row, in: app)
        guard row.isHittable else { return false }
        row.tap()
        return app.buttons["supporter.card"].firstMatch.waitForExistence(timeout: 10)
    }

    /// **サポーター証**（既定の文字と、大きい文字）: 見本の利用者がサポーターのときだけ。行が無ければ撮らずに抜ける
    func testCapturesSupporterCard() {
        for (extra, name) in [([String](), "88-サポーター証"), (Self.largeText, "88x-大きい文字（サポーター証）")] {
            let app = XCUIApplication()
            app.launchArguments += ["-legal.consent.version", "0"]
            app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
            app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
            app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
            app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
            app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
            app.launchArguments += extra
            app.launch()
            guard openSupporterCard(app) else { return }
            Thread.sleep(forTimeInterval: 2)
            shoot(app, name)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, name + "（下）")
            app.terminate()
        }
    }

    /// **わたしの乗車券（大きい文字）**: きっぷ（決まった大きさ）の下の「裏を見る」が手がかりの下へ回り、押せるか。
    /// 開けなければ撮らずに抜ける。**出たのに「裏を見る」が 44pt 未満・押せなければ落とす**
    func testCapturesPassOwnCardLargeText() {
        guard let (app, _) = openPassPick(extra: Self.largeText) else { return }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "85x-大きい文字（自分のカード）")
        let flip = app.buttons["pass.pick.flip"].firstMatch
        XCTAssertTrue(flip.exists, "「裏を見る」が無い")
        XCTAssertGreaterThanOrEqual(flip.frame.height, 44, "「裏を見る」が 44pt 未満")
        // 送るのはきっぷの横の余白から（画面の真ん中はきっぷで、指を置くと回す側が受ける・Mac run 628 で
        // `swipeUp` では一度も送れなかった）
        dragUp(app, until: flip, x: 0.04, from: 0.75, to: 0.45)
        shoot(app, "85y-大きい文字（自分のカード・裏を見る）")
        XCTAssertTrue(flip.isHittable, "大きい文字で「裏を見る」を押せない")
    }

    /// **ストーリーを顔から開く・返信欄の絵文字の列**（2026-10-22・「インスタみたいに」第1弾）。
    ///
    /// 見本の通信（`-JPPreviewLocalBackend`）に `-JPPreviewStories` を足すと、`GET /stories` を端末の中で答える
    /// （公開の新着の作者ごとに1本・自分にも1本。写真は公開の写真をそのまま使う・`PreviewBackend.previewStories`）。
    /// ホームの輪（自分の輪の「＋」）→ 写真の詳細の作者の顔の輪 → 人のページの顔の輪 → 輪を押して開く →
    /// 返信欄に入って入力欄の上の絵文字の列、の順に撮る。**出なければ撮らずに抜ける**
    func testCapturesStoryRingsOnFaces() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewStories", "YES"]
        // 新着の札を探す目印（`revealNewestFeedTile`・札 #595）
        app.launchArguments += ["-JPPreviewFeedProbe", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return }

        // ホームの輪（自分にストーリーがあっても右下の「＋」）。**輪が出なくても撮る**（どこで止まったかを絵で残す）。
        // 「＋」は読み上げでは輪の操作にしてある（要素として隠す）ので、自分の輪の名前で待つ
        let mine = app.buttons["あなたのストーリー"].firstMatch
        let mineShown = mine.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 3)
        shoot(app, mineShown ? "60a-ストーリーの輪（自分の＋）" : "60a-ストーリーの輪（自分の輪が出ない）")

        // マイページの顔（見本の利用者はカバーがある。カバーの上の輪のすき間に写真が透けないか）
        let tabs = app.tabBars.firstMatch
        let myPage = tabs.buttons.element(boundBy: 4)
        if myPage.exists {
            myPage.tap()
            let myRing = app.buttons["story.avatar.ring"].firstMatch
            let myShown = myRing.waitForExistence(timeout: 15)
            Thread.sleep(forTimeInterval: 3)
            shoot(app, myShown ? "60f-ストーリーの輪（マイページの顔・カバーの上）" : "60f-ストーリーの輪（マイページの顔に輪が無い）")
            tabs.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 2)
        }

        // 写真の詳細の作者の顔。**新しく載った写真から開く**（見本のストーリーは新着の作者に付けてある・
        // `PreviewBackend.previewStories`）。札 #595 で「新着」の札は無くなり、新着は1本の並びに混ざる（`revealNewestFeedTile`）
        guard let photo = revealNewestFeedTile(app) else {
            shoot(app, "60b-ストーリーの輪（ホームに写真が出ない）")
            return
        }
        photo.tap()
        let author = app.buttons["photo.author"].firstMatch
        var pushes = 0
        while author.waitForExistence(timeout: 5), !author.isHittable, pushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        let detailRing = app.buttons["story.avatar.ring"].firstMatch
        let detailShown = detailRing.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        shoot(app, detailShown ? "60b-ストーリーの輪（写真の作者の顔）" : "60b-ストーリーの輪（作者の顔に輪が無い）")
        if detailShown {
            XCTAssertGreaterThanOrEqual(detailRing.frame.height, 44, "作者の顔の輪が 44pt 未満")
        }
        guard author.exists, author.isHittable else { return }

        // 人のページの顔
        author.tap()
        Thread.sleep(forTimeInterval: 4)
        // 積んだ下の写真の詳細にも同じ名前の輪が残っているので、**押せる方**を選ぶ
        let rings = app.buttons.matching(identifier: "story.avatar.ring")
        let profileRing = (0..<rings.count).map({ rings.element(boundBy: $0) }).first(where: { $0.isHittable })
        shoot(app, profileRing != nil ? "60c-ストーリーの輪（人のページの顔）" : "60c-ストーリーの輪（人のページの顔に輪が無い）")
        guard let profileRing else { return }

        // 輪を押すとその人のストーリーから開く → 返信欄に入ると入力欄の上に絵文字の列
        profileRing.tap()
        Thread.sleep(forTimeInterval: 3)
        let reply = app.textFields.firstMatch
        let replyShown = reply.waitForExistence(timeout: 15)
        shoot(app, replyShown ? "60d-ストーリー（顔から開いた）" : "60d-ストーリー（顔から開いた・返信欄が無い）")
        guard replyShown, reply.isHittable else { return }
        reply.tap()
        let row = app.descendants(matching: .any)["story.reply.reactions"].firstMatch
        let rowShown = row.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, rowShown ? "60e-ストーリーの返信欄（絵文字の列）" : "60e-ストーリーの返信欄（絵文字の列が無い）")
        let heart = app.buttons["いいね"].firstMatch
        if rowShown, heart.exists {
            XCTAssertGreaterThanOrEqual(heart.frame.height, 44, "絵文字の列の的が 44pt 未満")
        }
    }

    // MARK: - SNS の輪（札 #541・2026-11-11）

    /// 見本の通信で起動する（紹介のストーリーつき）に、引数を足して起動する。開けなければ nil
    private func launchSNSPreviewWith(_ extra: [String]) -> XCUIApplication? {
        launchSNSPreview(sharedStory: true, extra: extra)
    }

    /// 見本の通信で起動する（ストーリー・紹介の見本つき）。開けなければ nil
    private func launchSNSPreview(sharedStory: Bool, extra: [String] = []) -> XCUIApplication? {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewStories", "YES"]
        // 新着の札を探す目印（`revealNewestFeedTile`・札 #595）
        app.launchArguments += ["-JPPreviewFeedProbe", "YES"]
        if sharedStory { app.launchArguments += ["-JPPreviewSharedStory", "YES"] }
        // 入口の案内「写真を押してひとこと」（端末に1回だけ）は撮らない（札の絵に被る）
        app.launchArguments += ["-story.captionHintShown", "YES"]
        app.launchArguments += extra
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return nil }
        return app
    }

    /// 新しく載った写真の詳細を開く（見本のストーリーは新着の作者に付けてある・札 #595 で「新着」の札は無くなった）。
    /// 開けなければ false
    private func openFirstLatestPhoto(_ app: XCUIApplication) -> Bool {
        guard let photo = revealNewestFeedTile(app) else { return false }
        photo.tap()
        return true
    }

    /// 要素が押せるまで短い引きで送る（上限あり）
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement, limit: Int = 8) {
        var pushes = 0
        while element.waitForExistence(timeout: 3), !element.isHittable, pushes < limit {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
    }

    /// マイページの自分の写真の詳細を開く（「ストーリーに載せる」は自分の写真だけ・#577）。開けなければ false
    private func openFirstMyPhoto(_ app: XCUIApplication) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return false }
        tabBar.buttons.element(boundBy: 4).tap()
        let myPhoto = app.buttons["mypage.photo"].firstMatch
        guard myPhoto.waitForExistence(timeout: 20) else { return false }
        scrollUntilHittable(app, myPhoto, limit: 3)
        guard myPhoto.isHittable else { return false }
        myPhoto.tap()
        return true
    }

    /// **写真の「共有」→ 送るシート → ストーリーに載せる**（札 #541 の ①・案の模型 1-C / 1-D）。
    /// 送るシート（63a）と、写真の札が置かれた作る画面（63b）を撮る。投稿はしない。**出なければ撮らずに抜ける**。
    /// 2026-11-12（#577）: ストーリーに載せられるのは自分の写真だけなので、マイページの自分の写真から開く
    func testCapturesSendSheetToStory() {
        guard let app = launchSNSPreview(sharedStory: false), openFirstMyPhoto(app) else { return }
        let share = app.buttons["photo.share"].firstMatch
        scrollUntilHittable(app, share)
        guard share.exists, share.isHittable else {
            shoot(app, "63a-送るシート（共有の印が出ない）")
            return
        }
        share.tap()
        // 🔴 顔の段があるシートでは、行動の丸の道しるべが入れ物の「sendSheet」になる（Mac run 1127 の画面の木・
        // 120d と同じ）。自分の写真はフォロー中の顔が出るので、**名前**で探す（run 1156 で道しるべでは見つからなかった）
        let story = app.buttons.matching(NSPredicate(format: "label == %@", "ストーリーに載せる")).firstMatch
        let shown = story.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 1)
        XCTContext.runActivity(named: "63a の状態: story=\(shown) storyId=\(app.buttons["sendSheet.story"].firstMatch.exists)"
            + " buttons=\(app.buttons.allElementsBoundByIndex.suffix(10).map { $0.identifier + ":" + $0.label })") { _ in }
        shoot(app, shown ? "63a-送るシート" : "63a-送るシート（ストーリーに載せるが無い）")
        guard shown else { return XCTFail("自分の写真の送るシートに「ストーリーに載せる」が無い") }
        XCTAssertGreaterThanOrEqual(story.frame.height, 44, "「ストーリーに載せる」の的が 44pt 未満")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "ほかのアプリ")).firstMatch.exists,
                      "「ほかのアプリ」が無い（外への共有の口が消えた）")
        story.tap()
        let canvas = app.descendants(matching: .any)["story.canvas"].firstMatch
        let opened = canvas.waitForExistence(timeout: 30)
        Thread.sleep(forTimeInterval: 3)
        shoot(app, opened ? "63b-ストーリーに載せる（写真の札）" : "63b-ストーリーに載せる（作る画面が開かない）")
        XCTAssertTrue(opened, "「ストーリーに載せる」で作る画面が開かない")
    }

    /// 🔴 **人の写真の送るシートに「ストーリーに載せる」が無い**（2026-11-12 owner の原則・#577）。
    /// 新着の1枚目（人の写真）の「共有」を開き、リンクのコピーと「ほかのアプリ」だけが並ぶのを撮る（63a2）。
    /// 1枚目が自分の写真だった回（作者の横に「フォロー」が無い）は確かめずに抜ける
    func testCapturesSendSheetOthersPhotoHasNoStory() {
        guard let app = launchSNSPreview(sharedStory: false), openFirstLatestPhoto(app) else { return }
        // 人の写真か: 作者の横の「フォロー」「フォロー中」は人の写真にだけ出る（`PhotoDetailRules.showsFollow`）。
        // run 1159: ⋯ を開いて「編集」の有無で見ていた回は、閉じた後も共有の印が押せなかった（frame は画面の中・
        // isHittable=false・送っても動かない）。⋯ を開かずに見る
        let follow = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "フォロー", "フォロー中")).firstMatch
        guard follow.waitForExistence(timeout: 15) else {
            shoot(app, "63a2-送るシート（新着の1枚目が自分の写真か、フォローが読めない）")
            return
        }
        let share = app.buttons["photo.share"].firstMatch
        scrollUntilHittable(app, share)
        guard share.exists, share.isHittable else {
            XCTContext.runActivity(named: "63a2 の状態（送った後）: share.exists=\(share.exists)"
                + " frame=\(share.exists ? String(describing: share.frame) : "-")"
                + " buttons=\(app.buttons.allElementsBoundByIndex.suffix(12).map { $0.identifier + ":" + $0.label })") { _ in }
            shoot(app, "63a2-送るシート（人の写真・共有の印が出ない）")
            return
        }
        share.tap()
        // 顔の段があると丸の道しるべが入れ物の「sendSheet」になる（run 1127）ので、名前で探す
        func labeled(_ label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        let shown = labeled("リンクをコピー").waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, shown ? "63a2-送るシート（人の写真）" : "63a2-送るシート（人の写真・開かない）")
        guard shown else { return XCTFail("人の写真の「共有」で送るシートが開かない") }
        XCTAssertFalse(labeled("ストーリーに載せる").exists || app.buttons["sendSheet.story"].firstMatch.exists,
                       "人の写真の送るシートに「ストーリーに載せる」が出ている（#577）")
        XCTAssertTrue(labeled("ほかのアプリ").exists, "「ほかのアプリ」（リンクの共有）が消えた")
    }

    /// **コメントに返信**（札 #541 の ②・案の模型 2-B）。見本の通信でコメントを1件書き、「返信」→
    /// 「〇〇さんに返信中」（63c）→ 送ると相手の下に1段下げて並ぶ（63d）。**出なければ撮らずに抜ける**
    func testCapturesCommentReply() {
        guard let app = launchSNSPreview(sharedStory: false), openFirstLatestPhoto(app) else { return }
        let field = app.textFields["photo.commentField"].firstMatch
        let fieldAny = field.exists ? field : app.descendants(matching: .any)["photo.commentField"].firstMatch
        guard fieldAny.waitForExistence(timeout: 15), fieldAny.isHittable else {
            shoot(app, "63c-コメントに返信（欄が無い）")
            return
        }
        fieldAny.tap()
        fieldAny.typeText("どこから撮りましたか？")
        let send = app.buttons["photo.commentSend"].firstMatch
        guard send.waitForExistence(timeout: 5) else { return }
        send.tap()
        let reply = app.buttons["photo.commentReply"].firstMatch
        scrollUntilHittable(app, reply)
        guard reply.exists, reply.isHittable else {
            shoot(app, "63c-コメントに返信（返信の印が無い）")
            return
        }
        XCTAssertGreaterThanOrEqual(reply.frame.height, 44, "「返信」の的が 44pt 未満")
        reply.tap()
        let replying = app.descendants(matching: .any)["photo.commentReplying"].firstMatch
        let replyingShown = replying.waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, replyingShown ? "63c-コメントに返信中" : "63c-コメントに返信中（返信中の行が出ない）")
        guard replyingShown else { return XCTFail("「返信」を押しても「〇〇さんに返信中」が出ない") }
        fieldAny.typeText("坂の上からです")
        send.tap()
        Thread.sleep(forTimeInterval: 3)
        // キーボードを閉じて並びを見る
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "63d-コメントの返信（1段下げて並ぶ）")
        XCTAssertFalse(replying.exists, "送ったのに「返信中」が残っている")
    }

    /// **ストーリーで紹介された写真を見る**（札 #541 の ①・案の模型 1-E）。見本の通信の `-JPPreviewSharedStory` で、
    /// 新着の1人目の2本目のストーリーに紹介の写真を付ける（`PreviewBackend.previewStories`）。作者の顔の輪から開き、
    /// 2本目へ送って「写真を見る」（63e）→ 写真の詳細（63f）を撮る。**出なければ撮らずに抜ける**
    func testCapturesSharedPhotoStory() {
        guard let app = launchSNSPreview(sharedStory: true), openFirstLatestPhoto(app) else { return }
        /// 事実取り（2026-11-14 Mac の回 1246）: どの写真の詳細で、どの輪を押し、ストーリーの何本目が出ていたかを残す
        func note(_ step: String) {
            let author = app.buttons["photo.author"].firstMatch
            let rings = app.buttons.matching(identifier: "story.avatar.ring").allElementsBoundByIndex
                .map { "\($0.label)@\(Int($0.frame.minY))\($0.isHittable ? "" : "(hidden)")" }
            let probe = app.descendants(matching: .any)["story.viewer.probe"].firstMatch
            let line = "[sharedStory] \(step): author=\(author.exists ? author.label : "-") rings=\(rings)"
                + " viewer=\(probe.exists ? ((probe.value as? String) ?? "-") : "-")"
            print(line)
            XCTContext.runActivity(named: line) { _ in }
            let attachment = XCTAttachment(string: line)
            attachment.name = "sharedStory \(step)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        note("1-detail")
        let ring = app.buttons["story.avatar.ring"].firstMatch
        scrollUntilHittable(app, ring, limit: 3)
        guard ring.exists, ring.isHittable else {
            shoot(app, "63e-ストーリー（作者の顔に輪が無い）")
            return
        }
        note("2-before-ring (押す輪: \(ring.label))")
        ring.tap()
        Thread.sleep(forTimeInterval: 3)
        note("3-opened")
        let viewPhoto = app.buttons["story.viewer.sharedPhoto"].firstMatch
        // 1本目には付いていない。**叩かずに、2本目へ自分で送られるのを待つ**（写真の秒数は 3〜15・読み込みも待つ）。
        // 2026-11-14 判断（回 1246 が落ち・1249 が通った値から）: 1249 では輪を押してから約6秒で 1本目（preview-story-1・
        // 紹介なし）→ 2本目（preview-story-1b・紹介あり）へ自分で送られた。1246 は押してから8秒たっても2本目が出ず、
        // 約10秒の所で決まった時間のあとに右を叩いていた。叩いた時に2本目へ送られていれば、叩きで2本目を飛ばして
        // 束が閉じる（その後10秒「写真を見る」が出ないのと合う）。決まった時間で叩くのは、この飛ばしと競うのでやめた
        let shown = viewPhoto.waitForExistence(timeout: 25)
        if !shown { note("4-not-advanced") }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, shown ? "63e-ストーリー（写真を見る）" : "63e-ストーリー（写真を見るが出ない）")
        if !shown {
            note("5-failed")
            // 失敗した回は画面の木も残す（ログで読めるように、ストーリーと写真の詳細の行だけ）
            let tree = app.debugDescription
            let lines = tree.components(separatedBy: "\n").filter { $0.contains("story") || $0.contains("photo.") }
            print("[sharedStory] tree:\n" + lines.prefix(60).joined(separator: "\n"))
            let attachment = XCTAttachment(string: tree)
            attachment.name = "sharedStory tree"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        guard shown else { return XCTFail("紹介のストーリーに「写真を見る」が出ない") }
        XCTAssertGreaterThanOrEqual(viewPhoto.frame.height, 44, "「写真を見る」の的が 44pt 未満")
        viewPhoto.tap()
        let detail = app.buttons["photo.like"].firstMatch
        let opened = detail.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 2)
        shoot(app, opened ? "63f-写真を見る（写真の詳細）" : "63f-写真を見る（詳細が開かない）")
        XCTAssertTrue(opened, "「写真を見る」で写真の詳細が開かない")
    }

    /// **ストーリーの曲の札の6つの形**（2026-10-28・owner「押して替える めっちゃいいね！」）。
    ///
    /// `-JPPreviewStorySong YES` で、見本の写真と見本の曲（同梱の画像をジャケットに使う・通信しない）を付けて
    /// ストーリー作成を開く（`PreviewStorySample`・Debug のみ）。曲の札を押すたびに A→F と替わるのを1枚ずつ撮る。
    /// 覚えた形は起動の引数で A に戻す（引数の値が端末の覚えより先に読まれる）。**出なければ撮らずに抜ける**
    func testCapturesStorySongStickerStyles() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewStorySong", "YES", "-story.songSticker.style", "glass"]
        // 入口の案内「写真を押してひとこと」（端末に1回だけ・#404）は撮らない（札の絵に被る）
        app.launchArguments += ["-story.captionHintShown", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let toStory = app.buttons["post.choice.story"].firstMatch
        guard toStory.waitForExistence(timeout: 5), toStory.isHittable else { return }
        toStory.tap()
        let sticker = app.descendants(matching: .any)["story.songSticker"].firstMatch
        guard sticker.waitForExistence(timeout: 20) else {
            shoot(app, "62-ストーリーの曲の札（札が出ない）")
            return
        }
        Thread.sleep(forTimeInterval: 2)
        // 🔴 2026-10-30 判断 #406: **作る画面は窓の上の端から始まる**（画面いっぱい・`fullScreenCover`）。
        // シートのカードで出していた間は、上の隙間（時計の帯〜✕ の上）に下の画面（ホーム）が透けた。
        // 写真の枠（`story.canvas`）の上の端が窓の上の端にあり、下の画面のタブの帯が押せないことを見る
        let canvas = app.descendants(matching: .any)["story.canvas"].firstMatch
        if canvas.waitForExistence(timeout: 5) {
            let window = app.windows.firstMatch.frame
            XCTAssertLessThanOrEqual(canvas.frame.minY, window.minY + 1,
                                     "作る画面の写真の枠が窓の上の端から始まっていない（上に下の画面が透ける・#406）: "
                                     + "\(canvas.frame) / \(window)")
            XCTAssertEqual(canvas.frame.width, window.width, accuracy: 1, "作る画面が窓の幅いっぱいでない")
        } else {
            XCTFail("作る画面の写真の枠（story.canvas）が見つからない")
        }
        XCTAssertFalse(tabBar.exists && tabBar.isHittable, "作る画面の下からタブの帯が押せる（下の画面が見えている）")
        let names = ["A ガラスの札", "B 白い札", "C 小さな帯", "D ジャケット大", "E レコード", "F 明朝の題字"]
        for (i, name) in names.enumerated() {
            shoot(app, "62\(["a", "b", "c", "d", "e", "f"][i])-ストーリーの曲の札（\(name)）")
            guard i < names.count - 1, sticker.isHittable else { break }
            sticker.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    /// **曲の流し始め**（2026-11-12・設計の案「ストーリーのデザイン 残り」03）: 曲の絵を大きく・30 秒の帯と白い枠・
    /// 下の「この位置にする」。`-JPPreviewStorySong YES` の見本の曲（通信しない）で作る画面を開き、道具の「曲」の
    /// メニューから「流し始め」を開く。試聴の URL は見本なので、鳴らない回は「流せない」の段で撮れる。**出なければ撮らずに抜ける**
    func testCapturesStorySongStart() {
        let app = launchTrunk(["-JPPreviewStorySong", "YES", "-story.captionHintShown", "YES"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let toStory = app.buttons["post.choice.story"].firstMatch
        guard toStory.waitForExistence(timeout: 5), toStory.isHittable else { return }
        toStory.tap()
        let songTool = app.buttons["曲・入れてあります"].firstMatch
        guard songTool.waitForExistence(timeout: 20), songTool.isHittable else { return }
        songTool.tap()
        let startItem = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "流し始め")).firstMatch
        guard startItem.waitForExistence(timeout: 5) else { return }
        startItem.tap()
        let done = app.buttons["songStart.done"].firstMatch
        guard done.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 3)
        let failed = app.descendants(matching: .any)["songStart.failed"].firstMatch.exists
        shoot(app, failed ? "62g-ストーリーの曲の流し始め（流せない）" : "62g-ストーリーの曲の流し始め")
        XCTAssertGreaterThanOrEqual(done.frame.height, 44, "「この位置にする」の当たりが 44pt 未満")
    }

    /// **ハイライトを作る**（2026-11-12・設計の案 04）: マイページのハイライトの「新規」から開き、輪・名前・残したストーリーの
    /// 3 列の格子（見本に残したストーリーが無ければ空の状態「ストーリーを作る」・読めなければ失敗の状態）を撮る。
    /// **出なければ撮らずに抜ける**
    func testCapturesHighlightEditor() {
        let app = launchTrunk(["-JPPreviewLocalBackend", "YES", "-JPPreviewStories", "YES"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let create = app.buttons["ハイライトを作る"].firstMatch
        var pushes = 0
        while !(create.waitForExistence(timeout: 5) && create.isHittable), pushes < 3 {
            app.swipeUp()
            pushes += 1
        }
        guard create.exists, create.isHittable else { return }
        create.tap()
        let ring = app.buttons["highlightEditor.ring"].firstMatch
        guard ring.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 3)
        let empty = app.buttons["highlightEditor.makeStory"].firstMatch.exists
        shoot(app, empty ? "63a-ハイライトを作る（空・ストーリーを作る）" : "63a-ハイライトを作る")
        // 名前の欄の当たり: 欄そのものは字の高さ（run 1093 で 27pt）。44pt の行の、欄より上の所を押しても入れること
        let name = app.textFields["highlightEditor.name"].firstMatch
        if name.exists, name.isHittable {
            let gap = max(0, (44 - name.frame.height) / 2)
            if gap >= 4 {
                name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -(gap - 2))).tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                              "名前の欄の上（44pt の行の中）を押しても欄に入れない")
            }
        }
    }

    /// **下書きの一覧**（2026-10-29・#400「下書きを複数持つ」・モック 9JzQWmYxF14BmUiZ9yWbe8）: マイページの格子の
    /// 先頭の「下書き」の札 → 3列の格子（投稿・ストーリー・自動の書きかけ・あと n 日・読めない写真の「!」）→
    /// 「選ぶ」で2件 → 行の一覧 → 全部消した空の状態（「元に戻す」）。見本（`-JPPreviewDrafts YES`・端末の中だけ）で
    /// 起動する。出なければ撮らずに抜ける（この試験の決まり）
    func testCapturesDrafts() {
        let app = launchTrunk(["-JPPreviewDrafts", "YES"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return }
        tabBar.buttons.element(boundBy: 4).tap()
        let tile = app.buttons["mypage.drafts"].firstMatch
        guard tile.waitForExistence(timeout: 15) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "107a-マイページ（下書きの入口）")
        guard tile.isHittable else { return }
        // 枠の長押し（#408）: 浮く絵は最新の下書き、メニューは 続きから編集／下書きの一覧を開く／この下書きを削除／
        // 最近の下書き。撮ったらメニューの外を押して閉じる（何も選ばない）
        tile.press(forDuration: 1.2)
        let openList = app.buttons["下書きの一覧を開く"].firstMatch
        if openList.waitForExistence(timeout: 5) {
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "107a2-マイページ（下書きの枠を長押し）")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            Thread.sleep(forTimeInterval: 1)
        } else {
            shoot(app, "107a2-マイページ（下書きの枠を長押し・メニューが出ない）")
        }
        guard tile.waitForExistence(timeout: 5), tile.isHittable else { return }
        tile.tap()
        let cell = app.buttons["drafts.cell"].firstMatch
        guard cell.waitForExistence(timeout: 10) else { return }
        // 縮図は後ろで読むので少し待つ
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "107b-下書きの一覧（格子）")

        let select = app.buttons["drafts.select"].firstMatch
        guard select.waitForExistence(timeout: 5), select.isHittable else { return }
        select.tap()
        let cells = app.buttons.matching(identifier: "drafts.cell")
        if cells.count > 2 {
            cells.element(boundBy: 1).tap()
            cells.element(boundBy: 2).tap()
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "107c-下書きの一覧（選ぶ）")
        let cancel = app.buttons["drafts.cancel"].firstMatch
        guard cancel.waitForExistence(timeout: 5) else { return }
        // 🔴 上のバーの「キャンセル」「すべて」が切れずに1行で出る（107c で「ャンセ」と切れていた）。
        // 17pt の5字は約 85pt——押し込まれると 44 の丸になる。44pt 以上も確かめる
        let selectAllButton = app.buttons["drafts.selectAll"].firstMatch
        XCTAssertGreaterThanOrEqual(cancel.frame.width, 80, "「キャンセル」が丸に押し込まれて切れている")
        // 高さ: iOS 26 のナビバーの項目は系統が描く丸い札（目で測ると約 44pt・PR #401 run の 107c）で、
        // 読み上げの枠は中の字の高さ（36pt）を返す。押せる範囲は系統が 44pt 以上にする（系統の部品）ので、
        // ここでは字の枠が潰れていない（36pt 以上）ことを見る（2026-10-29 判断）
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 36, "「キャンセル」の字が潰れている")
        if selectAllButton.exists {
            XCTAssertGreaterThanOrEqual(selectAllButton.frame.width, 56, "「すべて」が押し込まれて切れている")
            XCTAssertLessThan(cancel.frame.maxX, selectAllButton.frame.minX)
        }
        cancel.tap()

        let rows = app.buttons["drafts.layout.rows"].firstMatch
        if rows.waitForExistence(timeout: 5), rows.isHittable {
            rows.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "107d-下書きの一覧（行）")
            // 一番下までずらすと、最後の行が下のタブの帯に隠れずに押せる（下の余白）
            for _ in 0..<3 { app.swipeUp() }
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "107d2-下書きの一覧（行・一番下）")
            let lastRow = app.buttons.matching(identifier: "drafts.row").allElementsBoundByIndex.last
            if let lastRow, tabBar.exists {
                XCTAssertLessThanOrEqual(lastRow.frame.maxY, tabBar.frame.minY + 1,
                                         "一番下の行が下のタブの帯に隠れる")
            }
            for _ in 0..<3 { app.swipeDown() }
            // 覚えた表示を格子に戻しておく（次の起動の絵を変えない）
            let grid = app.buttons["drafts.layout.grid"].firstMatch
            if grid.isHittable { grid.tap() }
        }

        // 長押しの詳細と操作（浮く縮図・続きから編集／複製／削除）
        if cell.waitForExistence(timeout: 5), cell.isHittable {
            cell.press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: 1.5)
            shoot(app, "107e-下書きの一覧（長押し）")
            // 閉じる（メニューの外を押す）
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 全部を選んで削除 → 空の状態（「元に戻す」が出ている間）
        guard select.waitForExistence(timeout: 5), select.isHittable else { return }
        select.tap()
        let all = app.navigationBars.buttons["すべて"].firstMatch
        guard all.waitForExistence(timeout: 5) else { return }
        all.tap()
        let delete = app.buttons["drafts.deleteSelected"].firstMatch
        guard delete.waitForExistence(timeout: 5), delete.isHittable else { return }
        delete.tap()
        let confirm = app.sheets.buttons["削除"].firstMatch.exists
            ? app.sheets.buttons["削除"].firstMatch : app.buttons["削除"].firstMatch
        guard confirm.waitForExistence(timeout: 5) else { return }
        confirm.tap()
        guard app.descendants(matching: .any)["drafts.empty"].firstMatch.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "107f-下書きの一覧（空・元に戻す）")
    }

    /// **投稿のシートの「下書き n ›」**（2026-11-12・1.1.83 案「投稿まわりのデザイン」01）: 下書きの見本
    /// （`-JPPreviewDrafts YES`）で起動し、下の「投稿」→ カメラの2つが1段の4行と下書きの行 → 押して下書きの一覧。
    /// 出なければ撮らずに抜ける（この試験の決まり）
    func testCapturesPostSheetDrafts() {
        let app = launchTrunk(["-JPPreviewDrafts", "YES"])
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let drafts = app.buttons["post.choice.drafts"].firstMatch
        guard drafts.waitForExistence(timeout: 8) else { return }
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "40c-投稿の選択（カメラの段と下書きの行）")
        guard drafts.isHittable else { return }
        drafts.tap()
        guard app.descendants(matching: .any)["drafts.list"].firstMatch.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "107g-下書きの一覧（投稿のシートから）")
    }

    /// **メッセージ（DM・第1段・札 #505・2026-11-10）**。見本の通信（`-JPPreviewLocalBackend`）に `-JPPreviewDM` を足すと、
    /// `/dm` を端末の中で答える（`PreviewBackend.dmReply`: 受信箱・リクエスト2件・退会した相手・3通を使い切った会話）。
    /// 見出しの吹き出し → 受信箱 → リクエスト → リクエストの会話 → 会話（URL を断られた）→ 3通の上限 → 退会、の順に撮る。
    /// **出なければ撮らずに抜ける**
    func testCapturesDirectMessages() {
        let app = XCUIApplication()
        // 2026-11-12（run 1164）: 会話を下へ払った直後から主スレッドが戻らず、画面の木も取れずに 5 分で落ちた。
        // 止まっている所を取るため、主スレッドの積みを 0.3 秒ごとにファイルへ書かせる（`PerfMainSampler`・Debug のみ）
        let samplePath = Self.mainSamplePath("dm")
        app.launchArguments += ["-JPPreviewPerfProbe", "YES", "-JPMainSampleFile", samplePath]
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewDM", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return }

        // 見出しの吹き出し（未読の点つき）。帯の寸法も文で残す
        let bubble = app.buttons["header.messages"].firstMatch
        guard bubble.waitForExistence(timeout: 20) else { return }
        Thread.sleep(forTimeInterval: 2)
        shootHeaderBand(app, tab: "86m-メッセージ（見出しの吹き出し）")
        XCTAssertGreaterThanOrEqual(bubble.frame.height, 44, "吹き出しの当たりが 44pt 未満")
        bubble.tap()

        let inbox = app.descendants(matching: .any)["dm.inbox"].firstMatch
        guard inbox.waitForExistence(timeout: 15) else {
            shoot(app, "86m1-メッセージ（受信箱が出ない）")
            return
        }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "86m1-メッセージ（受信箱）")

        // リクエスト
        let entry = app.buttons["dm.requests.entry"].firstMatch
        if entry.waitForExistence(timeout: 5), entry.isHittable {
            entry.tap()
            if app.descendants(matching: .any)["dm.requests"].firstMatch.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 2)
                shoot(app, "86m2-メッセージ（リクエスト）")
                // 札を押す → リクエストの会話（案内の帯）
                // 札の名前の行（顔・名前・@ユーザー名を1つのボタンにまとめてある）
                let name = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "桜の便り")).firstMatch
                if name.waitForExistence(timeout: 5), name.isHittable {
                    name.tap()
                    if app.descendants(matching: .any)["dm.requestBand"].firstMatch.waitForExistence(timeout: 10) {
                        Thread.sleep(forTimeInterval: 2)
                        shoot(app, "86m3-メッセージ（リクエストの会話）")
                    }
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 会話（ストーリーへの返信から始まった・未読あり）→ URL を送って断られる
        if openThread(app, named: "夕焼けの人") {
            shoot(app, "86m4-メッセージ（会話）")
            let field = app.descendants(matching: .any)["dm.field"].firstMatch
            if field.waitForExistence(timeout: 5), field.isHittable {
                field.tap()
                field.typeText("ここで撮りました https://example.com/spot")
                let send = app.buttons["dm.send"].firstMatch
                if send.isHittable { send.tap() }
                let refusal = app.descendants(matching: .any)["dm.fieldError"].firstMatch
                let shown = refusal.waitForExistence(timeout: 10)
                Thread.sleep(forTimeInterval: 1)
                // 出なかった回も撮る（どこで止まったかを絵で残す）。欄の中身と送信の丸の状態も文で残す
                shoot(app, shown ? "86m5-メッセージ（URLを断られた）" : "86m5-メッセージ（URLの断りが出ない）")
                let state = XCTAttachment(string: [
                    "fieldError: \(shown)",
                    "field.value: \(String(describing: field.value))",
                    "send.enabled: \(send.exists ? String(send.isEnabled) : "無し")",
                    "retry: \(app.buttons["dm.retry"].firstMatch.exists)",
                ].joined(separator: "\n"))
                state.name = "86m5-メッセージ（URLを送ったあとの状態）"
                state.lifetime = .keepAlways
                add(state)
                // 公開リポジトリの回は絵も添付も取り出せない（`スクリーンショットを保存` が無効）。**ログに出る行**で残す
                XCTContext.runActivity(named: "86m5 の状態: " + (state.name ?? "") + " / fieldError=\(shown)"
                    + " / field.value=\(String(describing: field.value))"
                    + " / send.enabled=\(send.exists ? String(send.isEnabled) : "無し")"
                    + " / retry=\(app.buttons["dm.retry"].firstMatch.exists)"
                    + " / probe=\(String(describing: app.descendants(matching: .any)["dm.probe"].firstMatch.value))"
                    + " / staticTexts=\(app.staticTexts.allElementsBoundByIndex.suffix(8).map(\.label))") { _ in }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 送信の取り消し（2026-11-12・owner の要望）: 自分の吹き出しを長押し → 「送信を取り消す」→ 跡を残さず消え、文が欄に戻る。
        // 確かめのダイアログは出さない。**出なければ撮らずに抜ける**
        if openThread(app, named: "夕焼けの人") {
            let mineText = "ありがとうございます。伊豆の海沿いです。"
            let bubble = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", mineText)).firstMatch
            // 見本の会話は下（新しい方）まで送られて開く。自分の文の吹き出しは上にあるので、届くまで戻す
            // （run 1121: 吹き出しは在るが押せない位置で、長押しまで行かなかった）
            let thread = app.descendants(matching: .any)["dm.conversation"].firstMatch
            var swipes = 0
            Self.logMainSamples(samplePath, label: "86m5a の払う前")
            while bubble.waitForExistence(timeout: 5), !bubble.isHittable, swipes < 4 {
                thread.swipeDown()
                swipes += 1
                Thread.sleep(forTimeInterval: 0.5)
                // 払ったあとは画面の木を読む前にファイルを読む（主スレッドが忙しいと木の読み取りで止まる）
                Self.logMainSamples(samplePath, label: "86m5a の払い \(swipes) 回目のあと")
            }
            XCTContext.runActivity(named: "86m5a の手前: exists=\(bubble.exists) / hittable=\(bubble.exists && bubble.isHittable) / swipes=\(swipes)") { _ in }
            if bubble.exists, bubble.isHittable {
                bubble.press(forDuration: 1.0)
                let unsend = app.buttons["dm.unsend"].exists ? app.buttons["dm.unsend"].firstMatch
                    : app.buttons.matching(NSPredicate(format: "label == %@", "送信を取り消す")).firstMatch
                if unsend.waitForExistence(timeout: 5) {
                    Thread.sleep(forTimeInterval: 1)
                    shoot(app, "86m5a-メッセージ（長押しの送信を取り消す）")
                    unsend.tap()
                    Thread.sleep(forTimeInterval: 1.5)
                    let field = app.descendants(matching: .any)["dm.field"].firstMatch
                    let gone = !app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", mineText))
                        .allElementsBoundByIndex.contains { $0.frame.minY < field.frame.minY }
                    shoot(app, gone ? "86m5b-メッセージ（取り消した文が欄に戻る）" : "86m5b-メッセージ（取り消した吹き出しが残る）")
                    XCTContext.runActivity(named: "86m5b の状態: gone=\(gone) / field.value=\(String(describing: field.value))") { _ in }
                    XCTAssertTrue(gone, "取り消した吹き出しが会話に残っている")
                    XCTAssertTrue(String(describing: field.value).contains(mineText), "取り消した文が入力欄に戻らない")
                }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 承認前の3通を使い切った会話（欄は止まり、理由を欄の上に）
        if openThread(app, named: "雪の駅") {
            if app.descendants(matching: .any)["dm.requestNote"].firstMatch.waitForExistence(timeout: 5) {
                shoot(app, "86m6-メッセージ（承認前の3通の上限）")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 相手が退会（送信欄の代わりに理由と「会話を削除」）
        if openThread(app, named: "退会したユーザー") {
            if app.buttons["dm.deleted.remove"].firstMatch.waitForExistence(timeout: 5) {
                shoot(app, "86m7-メッセージ（相手が退会）")
            }
        }
    }

    // MARK: - 資料「SNS をもっと SNS に」（1.1.83・2026-11-12）

    /// **④ 誰もフォローしていない人のホームの「おすすめの人」**。見本の通信に `-JPPreviewFollowNone` を足すと、
    /// 誰もフォローしていないことにする（`PreviewBackend`）。札 #595 で「フォロー中」の札は無くなり、おすすめの人は
    /// 1本の並びの中（写真のひと回りと季節の段の後ろ）に出る。送って並び（120a）→ 1人をフォローして
    /// 「フォロー中の写真を見る」が出た所（120b）→ 押して並びの頭へ戻った所（120c）を撮る。**出なければ撮らずに抜ける**
    func testCapturesSuggestedPeople() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewFollowNone", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return }
        _ = app.buttons["feed.photo"].firstMatch.waitForExistence(timeout: 20)
        let follow = app.buttons["home.suggested.follow"].firstMatch
        scrollUntilHittable(app, follow)
        let shown = follow.exists && follow.isHittable
        Thread.sleep(forTimeInterval: 2)
        shoot(app, shown ? "120a-ホーム（誰もフォローしていない・おすすめの人）" : "120a-ホーム（おすすめの人が出ない）")
        guard shown else { return }
        XCTAssertGreaterThanOrEqual(follow.frame.height, 44, "「フォロー」の的が 44pt 未満")
        follow.tap()
        let see = app.buttons["home.suggested.seeFeed"].firstMatch
        scrollUntilHittable(app, see)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, see.exists ? "120b-ホーム（おすすめの人をフォローした）" : "120b-ホーム（フォロー中の写真を見るが出ない）")
        XCTAssertTrue(see.exists, "フォローしても「フォロー中の写真を見る」が出ない")
        guard see.exists, see.isHittable else { return }
        see.tap()
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "120c-ホーム（フォロー中の写真を見る→並びの頭へ）")
    }

    /// **⑤ 撮影スポットを DM で送る**。見本の会話（夕焼けの人）に撮影スポットの頁のリンクの1通を置いてある
    /// （`PreviewBackend.dmReply`）。会話の札（120c）→ 札から撮影スポットの頁 → 右上の「送る」シート（120d）を撮る。
    /// **出なければ撮らずに抜ける**
    func testCapturesSpotSend() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewDM", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return }
        let bubble = app.buttons["header.messages"].firstMatch
        guard bubble.waitForExistence(timeout: 20) else { return }
        bubble.tap()
        guard app.descendants(matching: .any)["dm.inbox"].firstMatch.waitForExistence(timeout: 15),
              openThread(app, named: "夕焼けの人") else { return }
        let card = app.descendants(matching: .any)["dm.spotCard"].firstMatch
        let cardShown = card.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 2)
        shoot(app, cardShown ? "120c-メッセージ（撮影スポットの札）" : "120c-メッセージ（撮影スポットの札が出ない）")
        guard cardShown else { return }
        let wish = app.buttons["dm.spotCard.wish"].firstMatch
        if wish.exists { XCTAssertGreaterThanOrEqual(wish.frame.height, 44, "「行きたい場所に入れる」の的が 44pt 未満") }
        let open = app.buttons["dm.spotCard.open"].firstMatch
        guard open.exists, open.isHittable else {
            XCTContext.runActivity(named: "120d: 札の「撮影スポットの頁を開く」が押せない exists=\(open.exists)") { _ in }
            return
        }
        open.tap()
        let share = app.buttons["spot.official.share"].firstMatch
        guard share.waitForExistence(timeout: 15), share.isHittable else { return }
        share.tap()
        let sheet = app.descendants(matching: .any)["sendSheet"].firstMatch
        let sheetShown = sheet.waitForExistence(timeout: 10)
        _ = app.buttons["dm.face"].firstMatch.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, sheetShown ? "120d-撮影スポット（送るシート）" : "120d-撮影スポット（送るシートが出ない）")
        XCTAssertTrue(sheetShown, "撮影スポットの右上を押しても送るシートが出ない")
        // 🔴 顔の段があるシートでは、行動の丸の道しるべが入れ物の「sendSheet」になる（Mac run 1127 の画面の木:
        // `Button, identifier: 'sendSheet', label: 'ほかのアプリ'`・`label: 'リンクをコピー'`。顔の段の無い写真のシート（63a）では
        // `sendSheet.otherApps` で見つかる）。丸そのものは出ているので、ここは**名前**で確かめる
        for label in ["リンクをコピー", "ほかのアプリ"] {
            let button = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(button.exists, "送るシートに「\(label)」が無い")
            if button.exists { XCTAssertGreaterThanOrEqual(button.frame.height, 44, "「\(label)」の的が 44pt 未満") }
        }
    }

    /// **① 投稿したら共有カード**。見本の1枚を選んだ投稿画面（`-JPPreviewUploadSample`）で、見本の通信に投稿し、
    /// 上がった直後のカードの画面（120e）を撮る。**出なければ撮らずに抜ける**
    func testCapturesPostedShareCard() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewUploadSample", "YES"]
        // 閉じた回数に関係なくカードを出す（`CriticalFlowTests.postedCardHabitKey`・同じ模擬機で3回目の投稿から出なくなる道）
        app.launchArguments += ["-\(CriticalFlowTests.postedCardHabitKey)", "0"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        guard toPhoto.waitForExistence(timeout: 5), toPhoto.isHittable else { return }
        toPhoto.tap()
        guard app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 20) else { return }
        let title = app.textFields["upload.title"].firstMatch
        scrollUntilHittable(app, title)
        if title.exists, title.isHittable {
            title.tap()
            title.typeText("秋の兼六園")
        }
        let place = app.textFields["upload.place"].firstMatch
        scrollUntilHittable(app, place)
        if place.exists, place.isHittable {
            place.tap()
            place.typeText("Kanazawa")
        }
        let submit = app.buttons["upload.submit"].firstMatch
        guard submit.waitForExistence(timeout: 5) else { return }
        let enabled = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: submit)],
                                       timeout: 15)
        guard enabled == .completed else { return }
        submit.tap()
        let header = app.descendants(matching: .any)["postedCard.header"].firstMatch
        let shown = header.waitForExistence(timeout: 60)
        // カードの絵ができるまで待つ（「カードを共有」が押せるようになる）
        let share = app.buttons["signatureShare.share"].firstMatch
        _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: share)],
                             timeout: 20)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, shown ? "120e-投稿の完了（共有カード）" : "120e-投稿の完了（共有カードが出ない）")
        XCTAssertTrue(shown, "投稿しても共有カードが出ない")
        guard shown else { return }
        for id in ["postedCard.story", "postedCard.copyLink", "postedCard.close"] {
            let button = app.buttons[id].firstMatch
            XCTAssertTrue(button.exists, "\(id) が無い")
            if button.exists { XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(id) の的が 44pt 未満") }
        }
    }

    /// **DM の会話から旅行プランを作る（2026-11-12・資料「SNS をもっと SNS に」2a の段①と段②）**。
    /// 見本の会話「夕焼けの人」には公開の新着の1枚目を送った通がある（撮影地つきなら帯が出る）。
    /// 帯 → 下書き → 日付（休みの組を押す）と、吹き出しの長押しのメニューを撮る。**出なければ撮らずに抜ける**
    func testCapturesDirectMessageTripPlan() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewDM", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return }
        let bubble = app.buttons["header.messages"].firstMatch
        guard bubble.waitForExistence(timeout: 20) else { return }
        bubble.tap()
        guard app.descendants(matching: .any)["dm.inbox"].firstMatch.waitForExistence(timeout: 15),
              openThread(app, named: "夕焼けの人") else { return }

        // 吹き出しの長押し（段②）: 「旅行プランに入れる」「コピー」
        let said = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "行ってみたい")).firstMatch
        if said.waitForExistence(timeout: 5), said.isHittable {
            said.press(forDuration: 1.0)
            let add = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "旅行プランに入れる")).firstMatch
            if add.waitForExistence(timeout: 5) {
                Thread.sleep(forTimeInterval: 1)
                shoot(app, "86p1-メッセージ（吹き出しの長押し・旅行プランに入れる）")
            }
            // メニューを閉じる（押さずに外を押す）
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 帯（段①）
        let band = app.buttons["dm.tripBand"].firstMatch
        let hasBand = band.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 1)
        shoot(app, hasBand ? "86p2-メッセージ（旅行プランの帯）" : "86p2-メッセージ（旅行プランの帯が出ない）")
        XCTContext.runActivity(named: "86p2 の状態: band=\(hasBand)"
            + " / label=\(band.exists ? band.label : "無し")"
            + " / photoLive=\(app.buttons["dm.photoCard.live"].firstMatch.exists)") { _ in }
        guard hasBand, band.isHittable else { return }
        XCTAssertGreaterThanOrEqual(band.frame.height, 44, "帯の当たりが 44pt 未満")
        band.tap()
        let next = app.buttons["dmTrip.next"].firstMatch
        guard next.waitForExistence(timeout: 10) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "86p3-メッセージ（旅行プランの下書き）")
        next.tap()
        let finish = app.buttons["tripCreate.finish"].firstMatch
        guard finish.waitForExistence(timeout: 10) else { return }
        let pair = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tripCreate.holiday.'")).firstMatch
        if pair.waitForExistence(timeout: 5), pair.isHittable {
            XCTAssertGreaterThanOrEqual(pair.frame.height, 44, "休みの組の当たりが 44pt 未満")
            pair.tap()
        }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "86p4-メッセージ（旅行プランの日付・休みの組）")
    }

    /// 主スレッドの積みを書かせるファイルの道（同じシミュレーターのアプリと試験の両方から見える所）
    static func mainSamplePath(_ name: String) -> String {
        let base = ProcessInfo.processInfo.environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"] ?? NSTemporaryDirectory()
        let path = (base as NSString).appendingPathComponent("jp-main-samples-\(name).txt")
        try? FileManager.default.removeItem(atPath: path)
        return path
    }

    /// ファイルの積みをログに出す（画面の木は読まない）。主スレッドの返事が遅い行（pending・200ms 以上）の数と、
    /// その行に多く出るこのアプリの段の上位、最後の 4 行
    static func logMainSamples(_ path: String, label: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            XCTContext.runActivity(named: "主スレッドの積み（\(label)）: ファイルが読めない \(path)") { _ in }
            return
        }
        let lines = text.split(separator: "\n").map(String.init)
        let slow = lines.filter { line in
            guard let ping = line.components(separatedBy: "ping=").dropFirst().first?.split(separator: " ").first else { return false }
            return ping == "pending" || (Int(ping) ?? 0) >= 200
        }
        var counts: [String: Int] = [:]
        for line in slow {
            let frames = (line.components(separatedBy: " | ").dropFirst().first ?? "").components(separatedBy: " ; ")
            for frame in Set(frames) where frame.hasPrefix("JourneyPhoto") { counts[frame, default: 0] += 1 }
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(12).map { "\($0.value)x \($0.key)" }
        XCTContext.runActivity(named: "主スレッドの積み（\(label)）: 行 \(lines.count) / 遅い行 \(slow.count)") { _ in }
        for (i, frame) in top.enumerated() {
            XCTContext.runActivity(named: "主スレッドの積み（\(label)）上位 \(i + 1): \(frame)") { _ in }
        }
        for line in lines.suffix(4) {
            XCTContext.runActivity(named: "主スレッドの積み（\(label)）最後: \(String(line.prefix(900)))") { _ in }
        }
    }

    /// 受信箱の行を名前で開き、会話が出るまで待つ（出なければ false）
    private func openThread(_ app: XCUIApplication, named name: String) -> Bool {
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'dm.thread' AND label CONTAINS %@", name)).firstMatch
        guard row.waitForExistence(timeout: 10) else { return false }
        if !row.isHittable { app.swipeUp() }
        guard row.isHittable else { return false }
        row.tap()
        guard app.descendants(matching: .any)["dm.conversation"].firstMatch.waitForExistence(timeout: 10) else { return false }
        Thread.sleep(forTimeInterval: 2)
        return true
    }

    /// **メッセージを始める（2026-11-10 owner「普通にDMできる機能がいい」）**。見本の通信に `-JPPreviewDM` を足すと、
    /// フォロー中（公開の新着の作者＋見本の会話の相手・`PreviewBackend.dmFollowing`）も端末の中で答える。
    /// 受信箱の鉛筆 → 新しいメッセージ → まだ会話の無い人 → 1通目の前の画面、と
    /// ホームの新着の1枚目 → 作者のページ（フォロー中なので「メッセージ」）→ 会話、の順に撮る。**出なければ撮らずに抜ける**
    func testCapturesDirectMessageStart() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewDM", "YES"]
        // 新着の札を探す目印（`revealNewestFeedTile`・札 #595）
        app.launchArguments += ["-JPPreviewFeedProbe", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return }

        // 受信箱の鉛筆 → 新しいメッセージ（フォロー中の人の一覧）
        let bubble = app.buttons["header.messages"].firstMatch
        if bubble.waitForExistence(timeout: 20) {
            bubble.tap()
            let open = app.buttons["dm.new.open"].firstMatch
            if open.waitForExistence(timeout: 15) {
                // 鉛筆は上のバーの系統の部品（iOS 26 は見た目 36 で報告し、当たりは系統が広げる・この試験の
                // 「カバーの位置を調整」の「完了」「キャンセル」と同じ）。run 42814992712 で 36.0 と報告された。高さではなく、押せることを確かめる
                XCTAssertTrue(open.isHittable, "鉛筆が押せない")
                open.tap()
                let person = app.buttons["dm.new.person"].firstMatch
                if person.waitForExistence(timeout: 15) {
                    Thread.sleep(forTimeInterval: 2)
                    shoot(app, "86n1-メッセージ（新しいメッセージ）")
                    XCTAssertGreaterThanOrEqual(person.frame.height, 44, "人の行の当たりが 44pt 未満")
                    // 1人目（公開の新着の作者＝まだ会話が無い）→ 空の会話と1通目の前の一言
                    person.tap()
                    let note = app.descendants(matching: .any)["dm.firstNote"].firstMatch
                    let shown = note.waitForExistence(timeout: 15)
                    Thread.sleep(forTimeInterval: 2)
                    shoot(app, shown ? "86n2-メッセージ（1通目の前）" : "86n2-メッセージ（1通目の前の一言が出ない）")
                    XCTContext.runActivity(named: "86n2 の状態: firstNote=\(shown)"
                        + " / newIntro=\(app.descendants(matching: .any)["dm.newIntro"].firstMatch.exists)"
                        + " / field=\(app.descendants(matching: .any)["dm.field"].firstMatch.exists)"
                        + " / staticTexts=\(app.staticTexts.allElementsBoundByIndex.suffix(8).map(\.label))") { _ in }
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                    Thread.sleep(forTimeInterval: 1)
                } else {
                    shoot(app, "86n1-メッセージ（新しいメッセージの一覧が出ない）")
                }
            }
            let close = app.buttons["messages.close"].firstMatch
            if close.waitForExistence(timeout: 5), close.isHittable { close.tap() }
            Thread.sleep(forTimeInterval: 1)
        }

        // ホームの新しく載った写真 → 作者のページ（見本ではフォロー中）→「メッセージ」（札 #595 で「新着」の札は無くなった）
        guard let photo = revealNewestFeedTile(app) else { return }
        photo.tap()
        let author = app.buttons["photo.author"].firstMatch
        var pushes = 0
        while author.waitForExistence(timeout: 5), !author.isHittable, pushes < 3 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard author.exists, author.isHittable else { return }
        author.tap()
        let message = app.buttons["profile.message"].firstMatch
        let hasButton = message.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 2)
        shoot(app, hasButton ? "86n3-メッセージ（プロフィールのボタン）" : "86n3-メッセージ（プロフィールにボタンが無い）")
        guard hasButton, message.isHittable else { return }
        XCTAssertGreaterThanOrEqual(message.frame.height, 44, "「メッセージ」の当たりが 44pt 未満")
        message.tap()
        let conversation = app.descendants(matching: .any)["dm.conversation"].firstMatch
        guard conversation.waitForExistence(timeout: 15) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "86n4-メッセージ（プロフィールから開いた会話）")

        // 会話 → 見出し → 相手のプロフィール →「メッセージ」は、同じ会話を積まずに戻る（2026-11-10・確かめ役の指摘）。
        // 積み重ねは「写真 → プロフィール → 会話」のまま: 2回戻ると写真で、会話は残っていない
        let header = app.buttons["dm.header"].firstMatch
        guard header.waitForExistence(timeout: 5), header.isHittable else { return }
        header.tap()
        guard message.waitForExistence(timeout: 15), message.isHittable else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "86n5-メッセージ（会話から開いたプロフィール）")
        message.tap()
        XCTAssertTrue(conversation.waitForExistence(timeout: 10), "会話から開いたプロフィールの「メッセージ」で会話に戻らない")
        Thread.sleep(forTimeInterval: 1)
        goBack(app)
        XCTAssertTrue(message.waitForExistence(timeout: 10), "会話から1つ戻ってもプロフィールでない")
        Thread.sleep(forTimeInterval: 1)
        goBack(app)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(conversation.exists, "会話から開いたプロフィールの「メッセージ」で、同じ会話がもう1枚積まれた")
    }

    /// 第6章の絵の試験の歯止め: 出るはずのものが出なければ**落とす**（黙って抜けない・2026-11-12 確かめ役）
    private func expect(_ ok: Bool, _ what: String, _ app: XCUIApplication) -> Bool {
        if !ok {
            XCTFail("\(what) が出ない")
            print("UINOTE \(what) が出ない（画面の木）:\n\(app.debugDescription)")
        }
        return ok
    }

    /// **①現像・②「1年前」**（2026-11-12 札 #543）。見本の旅（`-JPPreviewDevelop`・同梱の絵）で、
    /// ホームの「現像前の旅」の札 → 払う画面（はじめ・右へ払った後）→ 払い終えた表紙、
    /// ストーリーの列の「1年前」の輪 → 閲覧、の順に撮る。見本で必ず出るので、**出なければ落とす**
    func testCapturesDevelopAndYearAgo() {
        let app = launchTrunk(["-JPPreviewDevelop", "YES", "-JPPreviewLayoutProbe", "YES"] + Self.freshDevelop)
        let card = app.buttons["home.develop"].firstMatch
        guard expect(card.waitForExistence(timeout: 25), "ホームの現像前の旅の札", app) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "120a-ホーム（現像前の旅の札・1年前の輪）")
        guard expect(card.isHittable, "押せる現像前の旅の札", app) else { return }
        card.tap()
        let keep = app.buttons["develop.keep"].firstMatch
        guard expect(keep.waitForExistence(timeout: 10), "現像の払う画面", app) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "120b-現像（はじめのコマ）")
        // 上の札と × は状態バーの下（2026-11-13 デザインの点検: 状態バーの中に入っていた・`DevelopView.deckScreen`）。
        // 機種の状態バーの高さに頼らず、アプリの安全な範囲の上端（見えない要素 `develop.safeTop`・画面の座標）と比べる
        let counter = app.descendants(matching: .any).matching(identifier: "develop.counter").firstMatch
        let topClose = app.buttons["develop.close"].firstMatch
        let safeProbe = app.descendants(matching: .any).matching(identifier: "develop.safeTop").firstMatch
        if expect(counter.exists && topClose.exists && safeProbe.exists, "現像の上の札と × と安全な範囲の値", app) {
            // 値は「top=<安全な範囲の上端> inset=<そこで読める上の幅>」（`DevelopView`）。比べるのは上端
            let probeValue = safeProbe.value as? String ?? ""
            let safeTop = probeValue.split(separator: " ").first
                .flatMap { $0.hasPrefix("top=") ? Double($0.dropFirst(4)) : nil } ?? -1
            print("measured developTopBar \(probeValue) counterMinY=\(counter.frame.minY) closeMinY=\(topClose.frame.minY)")
            // 状態バーの無い機種は無いので、上端は 0 より下（0 なら測り方が違う）
            XCTAssertGreaterThan(safeTop, 0, "安全な範囲の上端が取れない: \(probeValue)")
            XCTAssertGreaterThanOrEqual(Double(counter.frame.minY), safeTop - 0.5, "現像の上の札が状態バーに重なる")
            XCTAssertGreaterThanOrEqual(Double(topClose.frame.minY), safeTop - 0.5, "現像の × が状態バーに重なる")
        }
        // 右へ払う（載せる）。払いの判定は 110pt 以上
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.42)))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "120c-現像（右へ払った後・2コマ目）")
        // 残りはボタンで（載せる・外すを交互に）
        for k in 0..<12 {
            guard keep.exists, keep.isHittable else { break }
            if k % 3 == 2 { app.buttons["develop.skip"].firstMatch.tap() } else { keep.tap() }
            Thread.sleep(forTimeInterval: 0.6)
        }
        let post = app.buttons["develop.post"].firstMatch
        guard expect(post.waitForExistence(timeout: 5), "現像の表紙の「投稿する」", app) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "120d-現像（表紙・投稿する）")
        XCTAssertGreaterThanOrEqual(post.frame.height, 44, "「投稿する」が 44pt 未満")
        // 公開範囲は非公開で始まり、1回押すと公開に替わる（2026-11-12 確かめ役）
        let audience = app.buttons["develop.audience"].firstMatch
        if expect(audience.exists, "公開範囲の行", app) {
            XCTAssertEqual(audience.value as? String, "自分だけ（非公開）", "現像の投稿が非公開で始まらない")
            audience.tap()
            XCTAssertEqual(audience.value as? String, "みんなに公開", "公開範囲が1回で替わらない")
        }
        let close = app.buttons["develop.close"].firstMatch
        guard expect(close.waitForExistence(timeout: 5), "現像の閉じる", app) else { return }
        close.tap()
        let ring = app.buttons["stories.yearAgo"].firstMatch
        guard expect(ring.waitForExistence(timeout: 10) && ring.isHittable, "「1年前」の輪", app) else { return }
        ring.tap()
        guard expect(app.buttons["yearAgo.share"].firstMatch.waitForExistence(timeout: 10), "1年前の閲覧", app) else { return }
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "120e-1年前（閲覧）")
        // **途中で閉じた続き**（章「途中で閉じた」）: 控えを空にしない起動で札を押すと、払った続き（ここでは払い終えた表紙）から
        app.terminate()
        let again = launchTrunk(["-JPPreviewDevelop", "YES"])
        let againCard = again.buttons["home.develop"].firstMatch
        guard expect(againCard.waitForExistence(timeout: 25) && againCard.isHittable, "現像の途中の札", again) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(again, "120j-ホーム（現像の途中の札）")
        againCard.tap()
        guard expect(again.buttons["develop.post"].firstMatch.waitForExistence(timeout: 10),
                     "途中で閉じた続き（表紙から）", again) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(again, "120k-現像（途中で閉じた続き・表紙から）")
    }

    /// ①現像の払った控え（`DevelopProgressStore`・端末の中）を、その起動の間だけ空として読ませる引数。
    /// **前の試験で払い終えた控えが残ると、札を押しても払う画面ではなく表紙から始まる**（Mac run 1129: 前の試験の後の
    /// 起動で「develop.keep」「develop.addMore」が出なかった）。引数の値は文字なので `data(forKey:)` は nil＝控え無し
    private static var freshDevelop: [String] { ["-develop.progress.v1.\(previewUserId)", ""] }

    /// **①②の状態**（2026-11-12 札 #543・章「状態」）。一部の写真だけ許可（札の一言・払う画面の追加の口）と、
    /// 圏外（表紙の一言と押せない「投稿する」・1年前の閲覧の一言）。見本で必ず出るので、**出なければ落とす**
    func testCapturesDevelopStates() {
        let limited = launchTrunk(["-JPPreviewDevelop", "YES", "-JPPreviewDevelopState", "limited"] + Self.freshDevelop)
        let card = limited.buttons["home.develop"].firstMatch
        guard expect(card.waitForExistence(timeout: 25), "一部の写真だけ許可の札", limited) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(limited, "120f-ホーム（現像前の旅・一部の写真だけ許可）")
        guard expect(card.isHittable, "押せる札", limited) else { return }
        card.tap()
        let addMore = limited.buttons["develop.addMore"].firstMatch
        guard expect(addMore.waitForExistence(timeout: 10), "「ほかの写真も選べるようにする」", limited) else { return }
        Thread.sleep(forTimeInterval: 1.5)
        shoot(limited, "120g-現像（一部の写真だけ許可・ほかの写真も選べるようにする）")
        XCTAssertGreaterThanOrEqual(addMore.frame.height, 44, "「ほかの写真も選べるようにする」が 44pt 未満")
        limited.terminate()

        let offline = launchTrunk(["-JPPreviewDevelop", "YES", "-JPPreviewDevelopState", "offline"] + Self.freshDevelop)
        let offlineCard = offline.buttons["home.develop"].firstMatch
        guard expect(offlineCard.waitForExistence(timeout: 25) && offlineCard.isHittable, "圏外の札", offline) else { return }
        offlineCard.tap()
        let keep = offline.buttons["develop.keep"].firstMatch
        guard expect(keep.waitForExistence(timeout: 10), "圏外の払う画面", offline) else { return }
        for _ in 0..<12 {
            guard keep.exists, keep.isHittable else { break }
            keep.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        let post = offline.buttons["develop.post"].firstMatch
        guard expect(post.waitForExistence(timeout: 5) && offline.staticTexts["develop.offline"].firstMatch.exists,
                     "圏外の表紙の一言", offline) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(offline, "120h-現像（圏外の表紙・投稿は通信できる所で）")
        XCTAssertFalse(post.isEnabled, "圏外で「投稿する」を押せる")
        let close = offline.buttons["develop.close"].firstMatch
        guard expect(close.waitForExistence(timeout: 5), "現像の閉じる", offline) else { return }
        close.tap()
        let ring = offline.buttons["stories.yearAgo"].firstMatch
        guard expect(ring.waitForExistence(timeout: 10) && ring.isHittable, "「1年前」の輪", offline) else { return }
        ring.tap()
        guard expect(offline.staticTexts["通信できないので、送るのはあとで"].firstMatch.waitForExistence(timeout: 10),
                     "1年前の圏外の一言", offline) else { return }
        Thread.sleep(forTimeInterval: 1)
        shoot(offline, "120i-1年前（圏外・送るのはあとで）")
    }

    /// **つまむと地図**（2026-11-12 札 #543・章 段1）。ホームの写真を開き、写真の詳細の写真をつまんで縮め、
    /// 地図（「この近くで撮られた写真」）を撮る。**出なければ落とす**
    ///
    /// 2026-11-13 判断: 前の `testCapturesLiftAndPinch` から「手に取って運ぶ」の段（右の半円へ運んで「取り消す」を撮る）を消した。
    /// 1.1.84 からホームの札の身振りを使わない（`PhotoLift.homeGestureEnabled = false`・fb5c8d3c3）ので、
    /// その段は毎回落ちていた（run 1201「運んだ後の「取り消す」 が出ない」）。身振りを戻すときは、消した段も戻す
    /// （`YubiReviewTests.testHomeLiftIsOffIn1184` の注記）
    func testCapturesPinchToMap() {
        let app = launchTrunk([])
        let photo = app.buttons["feed.photo"].firstMatch
        var pushes = 0
        while !(photo.waitForExistence(timeout: 2) && photo.isHittable), pushes < 8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard expect(photo.exists && photo.isHittable, "ホームの写真", app) else { return }
        photo.tap()
        let hero = app.buttons["detail.hero"].firstMatch
        guard expect(hero.waitForExistence(timeout: 10) && hero.isHittable, "写真の詳細の写真", app) else { return }
        Thread.sleep(forTimeInterval: 2)
        hero.pinch(withScale: 0.4, velocity: -1)
        let map = app.navigationBars["この近くで撮られた写真"].firstMatch
        guard expect(map.waitForExistence(timeout: 8), "つまんだ後の地図", app) else { return }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "121b-写真の詳細（つまんで地図）")
    }

    /// **写真の詳細で、上で写真を下に引くと前の画面に戻る・上に払うと閉じない**（2026-11-13 owner 決定・札 #592・`PhotoDetailPull`）。
    /// 絵は撮らない。**閉じなければ・上へ払って閉じたら落とす**
    ///
    /// 1. 写真の上で上へ払う → 説明へ流れる（写真の上端が上へ動く）・写真の詳細のまま
    /// 2. 写真の下（説明）で下へ戻して、いちばん上へ戻す（写真の外の指なので閉じない）
    /// 3. 写真の上で少し（90pt）ゆっくり引いて止め、離す → 閉じずに元の位置へ戻る。
    ///    その間に写真の詳細の body が描き直されないこと（`perf.probe` の `photoDetail` の数・2026-11-13 確かめ役）
    /// 4. 写真の上で下へ引く → 前の画面（ホーム）に戻る
    func testDetailPullDownGoesBack() {
        // 2026-11-13 Mac の回 1228: 手順3（少し引いて離す）で閉じた。どの値で閉じたかを `detail.pull.probe` で取る
        let app = launchTrunk(["-JPPreviewPerfProbe", "YES", "-JPPreviewPullProbe", "YES"])
        defer { app.terminate() }
        let recommended = app.buttons["おすすめ"].firstMatch
        if recommended.waitForExistence(timeout: 15), recommended.isHittable { recommended.tap() }
        let photo = app.buttons["feed.photo"].firstMatch
        var pushes = 0
        while !(photo.waitForExistence(timeout: 2) && photo.isHittable), pushes < 8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard expect(photo.exists && photo.isHittable, "ホームの写真", app) else { return }
        photo.tap()
        let hero = app.buttons["detail.hero"].firstMatch
        let menu = app.buttons["photo.menu"].firstMatch
        guard expect(hero.waitForExistence(timeout: 10) && hero.isHittable, "写真の詳細の写真", app) else { return }
        guard expect(menu.waitForExistence(timeout: 5), "写真の詳細の「…」", app) else { return }
        Thread.sleep(forTimeInterval: 2)
        let topAtOpen = hero.frame.minY

        // 1. 写真の上で上へ払う（ゆっくり・止めてから離す＝勢いで流れ過ぎない）
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        let topAfterUp = hero.exists ? hero.frame.minY : .nan
        XCTContext.runActivity(named: "[detailPull] 上へ払う: 写真の上端 \(topAtOpen) → \(topAfterUp)・…=\(menu.exists)") { _ in }
        XCTAssertTrue(menu.exists && hero.exists, "上へ払ったら写真の詳細が閉じた")
        XCTAssertLessThan(topAfterUp, topAtOpen - 40, "上へ払っても説明へ流れない（送りを奪っている）")

        // 2. 写真の下（説明）で下へ戻す。写真の外の指なので、上に着いても閉じない
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        XCTContext.runActivity(named: "[detailPull] 下へ戻す: 写真の上端 \(hero.exists ? hero.frame.minY : .nan)・…=\(menu.exists)") { _ in }
        guard expect(menu.exists && hero.exists, "説明の上で下へ戻した後の写真の詳細", app) else { return }
        guard expect(abs(hero.frame.minY - topAtOpen) < 2, "いちばん上へ戻った写真の詳細", app) else { return }

        // 3. 少しだけゆっくり引いて止め、離す（120pt に届かない・止めてから離すので勢いも無い）→ 戻る・閉じない
        Thread.sleep(forTimeInterval: 2)
        let bodyBefore = perfProbeValue(app).map { PerfProbeReading($0).bodyCount("photoDetail") }
        let small = hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        small.press(forDuration: 0.05, thenDragTo: small.withOffset(CGVector(dx: 0, dy: 90)),
                    withVelocity: .slow, thenHoldForDuration: 1.5)
        Thread.sleep(forTimeInterval: 1.5)
        let bodyAfter = perfProbeValue(app).map { PerfProbeReading($0).bodyCount("photoDetail") }
        let topAfterSmall = hero.exists ? hero.frame.minY : .nan
        XCTContext.runActivity(named: "[detailPull] 少し引いて離す: 写真の上端 \(topAtOpen) → \(topAfterSmall)・…=\(menu.exists)"
            + "・photoDetail の body \(bodyBefore.map(String.init) ?? "-") → \(bodyAfter.map(String.init) ?? "-")"
            + "・probe=\(pullProbeValue(app))") { _ in }
        guard expect(menu.exists && hero.exists, "少し引いて離した後の写真の詳細（閉じた）", app) else { return }
        XCTAssertLessThan(abs(topAfterSmall - topAtOpen), 2, "少し引いて離した写真が元の位置へ戻らない")
        if let bodyBefore, let bodyAfter {
            // ゆっくり 90pt 引いて 1.5 秒止める間は 100 フレームを越える。引く量で画面ぜんぶを描き直していれば
            // その数だけ増える。読み込みの答えなどで数回は増えうるので、10 回未満を合格にする（数はログに残す）
            XCTAssertLessThan(bodyAfter - bodyBefore, 10, "写真を引いている間に写真の詳細の body が描き直された")
        } else {
            XCTFail("perf.probe が読めない（-JPPreviewPerfProbe）")
        }

        // 4. 写真の上で下へ引く → 前の画面へ
        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        let gone = XCTWaiter().wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: menu)], timeout: 5) == .completed
        XCTContext.runActivity(named: "[detailPull] 下へ引く: 閉じた=\(gone)・ホームの写真=\(photo.exists)・probe=\(pullProbeValue(app))") { _ in }
        guard expect(gone, "写真を下に引いた後に前の画面へ戻る", app) else { return }
        XCTAssertTrue(photo.waitForExistence(timeout: 5) && photo.isHittable, "下に引いて戻った先にホームの写真が無い")
    }

    /// 新着の写真を順に開き、作者の輪が「2本」（紹介の写真の付いた見本のストーリーの人）の写真の詳細で止まる。
    /// その輪（押せる）を返す。見つからなければ落として nil。
    /// 2026-11-14 判断（統合 1.1.87）: 札 #595 で「新着」の札（`home.feed.latest`）が無くなったので、先に1本の並びの
    /// 新着の作者の札（`revealNewestFeedTile`・自分以外でいちばん新しく載せた人）を開き、違えば画面の写真を順に開く
    private func openSharedStoryAuthorPhoto(_ app: XCUIApplication) -> XCUIElement? {
        let newest = revealNewestFeedTile(app)
        _ = app.buttons["feed.photo"].firstMatch.waitForExistence(timeout: 15)
        for attempt in -1..<6 {
            if attempt < 0 {
                guard let newest else { continue }
                newest.tap()
            } else {
                let photos = app.buttons.matching(identifier: "feed.photo").allElementsBoundByIndex.filter { $0.isHittable }
                guard attempt < photos.count else { break }
                photos[attempt].tap()
            }
            let ring = app.buttons["story.avatar.ring"].firstMatch
            _ = ring.waitForExistence(timeout: 15)
            scrollUntilHittable(app, ring, limit: 3)
            let ready = XCTWaiter().wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true"), object: ring)], timeout: 10) == .completed
            let label = ring.exists ? ring.label : "-"
            XCTContext.runActivity(named: "[detailPull.sheet] \(attempt < 0 ? "新着の作者の札" : "画面の \(attempt + 1) 枚目"): 輪 押せる=\(ready)・「\(label)」"
                + "・枠=\(ring.exists ? "\(ring.frame)" : "-")") { _ in }
            if ready, label.contains("2本") { return ring }
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            guard back.waitForExistence(timeout: 5) else { break }
            back.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        _ = expect(false, "紹介のストーリーの人（輪が「2本」）の写真", app)
        return nil
    }

    /// 「下に引いて戻る」の値（`detail.pull.probe`・`-JPPreviewPullProbe YES`）。写真の詳細の中とアプリの根の両方に在る
    /// （同じ1つの記録）。読めなければ「-」
    private func pullProbeValue(_ app: XCUIApplication) -> String {
        let probe = app.descendants(matching: .any)["detail.pull.probe"].firstMatch
        return (probe.exists ? probe.value as? String : nil) ?? "-"
    }

    /// **コメントを打っている間は、写真を下に引いても閉じない**（札 #592・`PhotoDetailView.pullCatcher`）。
    /// 下へ払う指はキーボードをしまいたい指で、書きかけのまま画面を閉じない。**閉じたら落とす**
    func testDetailPullKeepsWhileTyping() {
        guard let app = launchSNSPreview(sharedStory: false), openFirstLatestPhoto(app) else {
            return XCTFail("見本の写真の詳細が開かない")
        }
        defer { app.terminate() }
        let hero = app.buttons["detail.hero"].firstMatch
        let menu = app.buttons["photo.menu"].firstMatch
        guard expect(hero.waitForExistence(timeout: 10) && hero.isHittable, "写真の詳細の写真", app) else { return }
        let field = app.textFields["photo.commentField"].firstMatch
        let fieldAny = field.exists ? field : app.descendants(matching: .any)["photo.commentField"].firstMatch
        guard expect(fieldAny.waitForExistence(timeout: 15) && fieldAny.isHittable, "コメントの欄", app) else { return }
        fieldAny.tap()
        fieldAny.typeText("書きかけ")
        guard expect(app.keyboards.firstMatch.waitForExistence(timeout: 5), "コメントを打つキーボード", app) else { return }
        Thread.sleep(forTimeInterval: 1)
        let topAtOpen = hero.frame.minY
        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        Thread.sleep(forTimeInterval: 2)
        XCTContext.runActivity(named: "[detailPull] 打っている間に下へ引く: …=\(menu.exists)・写真の上端 \(topAtOpen) → "
            + "\(hero.exists ? hero.frame.minY : .nan)・キーボード=\(app.keyboards.firstMatch.exists)") { _ in }
        XCTAssertTrue(menu.exists && hero.exists, "コメントを打っている間に写真を下に引いたら写真の詳細が閉じた")
    }

    /// **ストーリーの「写真を見る」のシートの根で写真を下に引く**（札 #592・2026-11-13 確かめ役）。
    /// シート（UIKit）の「下へ引いて閉じる」と写真を引く動きが二重になるかを**値で取る**（`detail.pull.probe`・`DetailPullProbe`）。
    /// 正しい姿は「写真の詳細が閉じて元のストーリーに戻る1つの動き」。
    /// 落とすのは、戻らない・写真を引いている間にシートも下がった（二重）とき。値はどの回もログと添付に残す
    func testDetailPullInStorySheet() {
        guard let app = launchSNSPreviewWith(["-JPPreviewPullProbe", "YES"]) else {
            return XCTFail("見本の通信で起動できない")
        }
        defer { app.terminate() }
        // 紹介の写真が付くのは「新着で自分以外の1人目」の2本目（`PreviewBackend.previewStories`）。その人の輪だけ「2本」と読む。
        // 2026-11-14 Mac の回 1232: 新着の1枚目が自分の写真で（輪は「あなたのストーリー」）、自分のストーリーを開いて
        // 「写真を見る」が無いまま落ちた（回 1228 は1枚目が人の写真だった）。新着の写真を順に開き、輪が「2本」の写真を探す
        // 2026-11-13 回 1228: 輪の存在を確かめた直後の1回きりの「押せるか」で落ちた（落ちた時の木には輪が在った）ので、押せるまで待つ
        guard let ring = openSharedStoryAuthorPhoto(app) else { return }
        ring.tap()
        Thread.sleep(forTimeInterval: 3)
        let viewPhoto = app.buttons["story.viewer.sharedPhoto"].firstMatch
        if !viewPhoto.waitForExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
        }
        guard expect(viewPhoto.waitForExistence(timeout: 10), "紹介のストーリーの「写真を見る」", app) else { return }
        viewPhoto.tap()
        guard expect(app.buttons["photo.like"].firstMatch.waitForExistence(timeout: 20), "シートの写真の詳細", app) else { return }
        Thread.sleep(forTimeInterval: 2)
        // シートの写真の詳細の写真（下に積んだ詳細は閲覧画面の裏で押せない）
        let hero = app.buttons.matching(identifier: "detail.hero").allElementsBoundByIndex.first { $0.isHittable }
        guard let hero else { return XCTFail("シートの写真の詳細の写真が押せない") }
        let probe = app.descendants(matching: .any)["detail.pull.probe"].firstMatch
        guard expect(probe.waitForExistence(timeout: 5), "下に引く動きの目印（detail.pull.probe）", app) else { return }

        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        // 離した直後（シートが閉じきる前）に1回読む。閉じた後は、シートの目印が消えて読めないことがある
        // （下に積んだ詳細にも同じ1つの記録の目印があるが、閲覧画面の裏で UI テストの木に出るかは確かめていない）
        let rawNow = probe.exists ? probe.value as? String : nil
        // シートが閉じて、閲覧画面の「写真を見る」がまた押せるまで
        let back = XCTWaiter().wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: viewPhoto)], timeout: 6) == .completed
        Thread.sleep(forTimeInterval: 0.5)
        let rawLater = probe.exists ? probe.value as? String : nil
        let raw = rawLater ?? rawNow ?? "読めない"
        func field(_ key: String) -> Int? {
            raw.split(separator: ";").compactMap { part -> Int? in
                let kv = part.split(separator: "=")
                return kv.count == 2 && kv[0] == key ? Int(kv[1]) : nil
            }.first
        }
        let line = "[detailPull.sheet] 戻った=\(back) 離した直後=\(rawNow ?? "-") 閉じた後=\(rawLater ?? "-")"
            + " 根の目印=\(pullProbeValue(app))"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        let note = XCTAttachment(string: line)
        note.name = "detail.pull.probe sheet"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(back, "シートの根で写真を下に引いても、元のストーリーに戻らない")
        if let pulled = field("pullMax"), let both = field("dropWhilePull") {
            XCTAssertFalse(pulled > 0 && both > 2, "写真を引いている間にシートも下がった（二重）: \(raw)")
        } else {
            XCTFail("下に引く動きの目印が読めない: \(raw)")
        }
    }

    /// **写真を大きく見る画面で、1回押すと上下の情報が消え、もう1回で戻る**（2026-11-12 owner の要望・`ViewerChrome`）。
    /// 2回押し（拡大中なので倍率を戻す側・いいねは送らない）では消えないことも見る。**出なければ落とす**
    func testViewerTapHidesChrome() {
        // 上下の情報を出しているかは見えない要素の値で見る（`viewer.chrome.probe`・`PreviewSession.viewerProbe`）
        let app = launchTrunk(["-JPPreviewViewerProbe", "YES"])
        defer { app.terminate() }
        let photo = app.buttons["feed.photo"].firstMatch
        var pushes = 0
        while !(photo.waitForExistence(timeout: 2) && photo.isHittable), pushes < 8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard expect(photo.exists && photo.isHittable, "ホームの写真", app) else { return }
        photo.tap()
        let hero = app.buttons["detail.hero"].firstMatch
        guard expect(hero.waitForExistence(timeout: 10) && hero.isHittable, "写真の詳細の写真", app) else { return }
        hero.tap()
        let close = app.buttons["viewer.close"].firstMatch
        // 下の情報は題・撮影情報の段で見る（`viewer.caption`・どの写真にもある）。**サムネイルの帯は2枚以上の投稿だけ**
        // （`PhotoViewerView.thumbnailStrip`）——run 1182 は1枚の写真（「夢の中」・送りの頁 1）を開き、帯を待って落ちた
        let caption = app.descendants(matching: .any)["viewer.caption"].firstMatch
        let strip = app.scrollViews["viewer.strip"].firstMatch
        let probe = app.descendants(matching: .any)["viewer.chrome.probe"].firstMatch
        guard expect(close.waitForExistence(timeout: 10), "大きく見る画面の ✕", app) else { return }
        guard expect(caption.waitForExistence(timeout: 5), "大きく見る画面の下の情報（題・撮影情報）", app) else { return }
        guard expect(probe.waitForExistence(timeout: 5), "上下の情報の状態の目印", app) else { return }
        let hasStrip = strip.exists
        XCTContext.runActivity(named: "大きく見る画面: サムネイルの帯=\(hasStrip)（2枚以上の投稿だけ）") { _ in }

        /// 上下の情報の状態（目印の値）が `want` になるまで待つ。✕ と下の情報が UI テストの木に在るか・押せるかも記録する
        /// （run 1193: 隠した後の絵では消えていたが、`exists` は真のままだった）
        func waitChrome(_ want: String, _ step: String) -> Bool {
            let ok = XCTWaiter().wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", want), object: probe)], timeout: 3) == .completed
            XCTContext.runActivity(named: "[viewerChrome] \(step): probe=\((probe.value as? String) ?? "-")"
                + " close.exists=\(close.exists) close.hittable=\(close.exists && close.isHittable)"
                + " caption.exists=\(caption.exists) strip.exists=\(strip.exists)") { _ in }
            return ok
        }

        XCTAssertTrue(waitChrome("shown", "0-open"), "開いたときに上下の情報が出ていない")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "122a-写真を大きく見る（情報あり）")
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        // 1回押す → 消える
        center.tap()
        XCTAssertTrue(waitChrome("hidden", "1-tap"), "1回押しても上下の情報が消えない")
        Thread.sleep(forTimeInterval: 0.5)
        shoot(app, "122b-写真を大きく見る（1回押して写真だけ）")
        // もう1回 → 戻る
        center.tap()
        XCTAssertTrue(waitChrome("shown", "2-tap-again"), "もう1回押しても上下の情報が戻らない")
        if hasStrip { XCTAssertTrue(strip.exists, "もう1回押してもサムネイルの帯が戻らない") }
        // 拡大してから2回押す（倍率を戻す側）→ 消えも出もしない
        // （広げられなかった回も、2回押しは見本の利用者のいいね＝鍵が無く届かないだけで、消える・出るは同じく見られる）
        app.windows.firstMatch.pinch(withScale: 2.5, velocity: 2)
        Thread.sleep(forTimeInterval: 0.5)
        center.doubleTap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(waitChrome("shown", "3-double-tap"), "2回押しで上下の情報が消えた（1回押しとぶつかっている）")
    }
}
