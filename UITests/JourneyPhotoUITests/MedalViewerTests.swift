import XCTest

/// **メダルを回す全画面（`MedalViewerView`）を × で閉じると、元の画面に戻る**（2026-10-09）。
///
/// owner の報告（TestFlight 1.0.75 でも）: メダルを回す画面から戻れない。どこで起きたかは
/// 分かっていないので、開く経路3つ × 閉じ方3つを全部ここで流す。
///
/// 経路:
/// - shelf: マイページ → 名前の横（シート）→ バッジの棚 → メダルを押す
/// - nameSide: マイページ → 名前の横（シート）→ メダルを長押し
/// - profileEdit: プロフィールの編集 → 名前の横（シート）→ メダルを長押し
///
/// 閉じ方: 開いてすぐ × / 回した後（払って2秒待つ）に × / 回している最中（払った直後）に ×
///
/// 🔴 **owner の実機の絵（2026-10-09）: 初期ユーザー（earlyUser）のメダルで、右上の × が画面に無く、
/// 中身が右へずれ、説明の1行が右端で切れていた。** 初期ユーザーだけに敷く後光（硬貨の 1.3 倍）が
/// 画面の幅を超え、組み全体が画面より広くなって × が画面の外へ押し出されていた。
/// だから試すのは初期ユーザーのメダル。比べるために段のあるメダル（都道府県）も1つ流す。
///
/// 見本の利用者は鍵を持たないので、持ち物は `-JPPreviewBadges`（Debug のみ・`PreviewSession.badges`）で渡す。
/// **全画面まで行けなかった回は飛ばす（skip）**——通信の都合で開けないのを「直っていない」と取り違えない。
/// 開けたのに × で戻れなければ落とす——それがこの試験の見張り。
final class MedalViewerTests: XCTestCase {

    enum Route: String { case shelf, nameSide, profileEdit }
    enum Close: String { case immediately, afterSpin, whileSpinning }

    override func setUp() {
        continueAfterFailure = true
    }

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    /// 後光の出るメダル（owner の絵のもの）と、出ないメダル（比べる用）
    private static let haloKey = "earlyUser"
    private static let plainKey = "prefectures"
    /// 戻ったと見なすまで待つ上限（秒）。閉じる動きは 0.5 秒ほど
    private static let closeDeadline: TimeInterval = 8

    func testShelfCloseImmediately() throws { try run(.shelf, .immediately) }
    /// 比べる用: 後光の無いメダルは前から閉じられたか
    func testPlainMedalCloseImmediately() throws { try run(.nameSide, .immediately, key: Self.plainKey) }
    func testShelfCloseAfterSpin() throws { try run(.shelf, .afterSpin) }
    func testShelfCloseWhileSpinning() throws { try run(.shelf, .whileSpinning) }
    func testNameSideCloseImmediately() throws { try run(.nameSide, .immediately) }
    func testNameSideCloseAfterSpin() throws { try run(.nameSide, .afterSpin) }
    func testNameSideCloseWhileSpinning() throws { try run(.nameSide, .whileSpinning) }
    func testProfileEditCloseImmediately() throws { try run(.profileEdit, .immediately) }
    func testProfileEditCloseAfterSpin() throws { try run(.profileEdit, .afterSpin) }
    func testProfileEditCloseWhileSpinning() throws { try run(.profileEdit, .whileSpinning) }

    // MARK: - 流れ

    private func run(_ route: Route, _ close: Close, key: String = MedalViewerTests.haloKey) throws {
        let tag = "\(route.rawValue)-\(close.rawValue)-\(key)"
        let app = launch()
        let started = Date()
        guard open(route, key: key, in: app, tag: tag) else {
            shoot(app, "\(tag)-0-開けなかった")
            note("\(tag)-画面の木", app.debugDescription)
            throw XCTSkip("\(tag): メダルの全画面まで行けなかった（見本のデータ・通信）")
        }
        let closeButton = element(app, "medalViewer.close")
        guard closeButton.waitForExistence(timeout: 15) else {
            shoot(app, "\(tag)-1-全画面が出ない")
            note("\(tag)-画面の木", app.debugDescription)
            throw XCTSkip("\(tag): メダルを押したが全画面が出なかった")
        }
        note("\(tag)-開いた", String(format: "%.1fs hittable=%@ frame=%@", Date().timeIntervalSince(started),
                                   closeButton.isHittable.description, "\(closeButton.frame)"))
        shoot(app, "\(tag)-1-開いた")

        // × が画面（窓）の中にあり、押せること（owner の絵では画面の外へ押し出されていた）
        let window = app.windows.firstMatch.frame
        let frame = closeButton.frame
        let inside = window.contains(frame)
        note("\(tag)-×の位置", "window=\(window) close=\(frame) inside=\(inside) hittable=\(closeButton.isHittable)")
        XCTAssertTrue(inside, "\(tag): × が画面の外にある（\(frame) / 画面 \(window)）")
        XCTAssertTrue(closeButton.isHittable, "\(tag): × が押せない")
        // 説明の文が画面の幅の中に収まっている（折り返さず右端で切れていた）
        let hint = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '指で横に払うと'")).firstMatch
        if hint.exists {
            note("\(tag)-説明の位置", "hint=\(hint.frame)")
            XCTAssertTrue(window.contains(hint.frame), "\(tag): 説明の文が画面からはみ出している")
        }

        let coin = element(app, "medalViewer.coin")
        switch close {
        case .immediately:
            break
        case .afterSpin:
            if coin.exists { coin.swipeLeft() } else { app.swipeLeft() }
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "\(tag)-2-回した後")
        case .whileSpinning:
            if coin.exists { coin.swipeLeft(velocity: .fast) } else { app.swipeLeft(velocity: .fast) }
        }

        let tapStart = Date()
        closeButton.tap()
        let tapTook = Date().timeIntervalSince(tapStart)

        // 戻ったか: × が消え、元の画面の目印が見える
        let gone = NSPredicate(format: "exists == false")
        let waited = XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: closeButton)],
                                      timeout: Self.closeDeadline)
        let back = backMarker(route, key: key, in: app)
        let backVisible = back.waitForExistence(timeout: 3)
        note("\(tag)-閉じた結果", String(format: "tap=%.2fs closed=%@ back=%@", tapTook,
                                     (waited == .completed).description, backVisible.description))
        shoot(app, "\(tag)-3-閉じた後")
        if waited != .completed {
            // もう一度押して、押しても効かないのか・1回目が届かなかっただけかを書き残す
            let hittable = closeButton.isHittable
            if hittable { closeButton.tap() }
            Thread.sleep(forTimeInterval: 2)
            note("\(tag)-2回目", "hittable=\(hittable) stillOpen=\(closeButton.exists)")
            shoot(app, "\(tag)-4-2回目の後")
            note("\(tag)-画面の木", app.debugDescription)
        }
        XCTAssertEqual(waited, .completed, "\(tag): × を押してもメダルの全画面が閉じない")
        XCTAssertTrue(backVisible, "\(tag): 閉じた後に元の画面が見えない")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // 一巡（`ScreenshotTests`）と同じ立ち上げ方
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-JPPreviewBadges", "\(Self.plainKey):2,\(Self.haloKey):1"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        return app
    }

    /// 経路をたどってメダルの全画面を開く。途中で行き止まれば false
    private func open(_ route: Route, key: String, in app: XCUIApplication, tag: String) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 4 else { return false }
        tabBar.buttons.element(boundBy: 4).tap()

        switch route {
        case .shelf, .nameSide:
            let nameLine = element(app, "mypage.nameLine")
            guard nameLine.waitForExistence(timeout: 20) else { return false }
            nameLine.tap()
        case .profileEdit:
            let edit = element(app, "mypage.edit")
            guard edit.waitForExistence(timeout: 20) else { return false }
            edit.tap()
            // 編集の欄は BGM の下。一覧は画面の外の行を作らない（run 371: 送らずに待って行が無かった）。
            // 読み込みが済むのを待ってから、行が出て押せるまで送る
            _ = app.buttons["保存"].firstMatch.waitForExistence(timeout: 15)
            Thread.sleep(forTimeInterval: 2)
            let row = element(app, "profileEdit.nameSide")
            for _ in 0..<12 where !(row.exists && row.isHittable && row.isEnabled) {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.8)
            }
            guard row.exists, row.isHittable, row.isEnabled else { return false }
            row.tap()
        }

        guard element(app, "nameSide.save").waitForExistence(timeout: 10) else { return false }
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "\(tag)-0-名前の横")

        switch route {
        case .shelf:
            let link = element(app, "nameSide.shelf")
            guard link.waitForExistence(timeout: 5) else { return false }
            if !link.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 0.8) }
            guard link.isHittable else { return false }
            link.tap()
            let medal = element(app, "shelf.medal.\(key)")
            guard medal.waitForExistence(timeout: 15), medal.isHittable else { return false }
            shoot(app, "\(tag)-0-棚")
            medal.tap()
        case .nameSide, .profileEdit:
            let badge = element(app, "nameSide.badge.\(key)")
            guard badge.waitForExistence(timeout: 15), badge.isHittable else { return false }
            badge.press(forDuration: 1.0)
        }
        return true
    }

    /// 閉じた後に見えるはずの元の画面の目印
    private func backMarker(_ route: Route, key: String, in app: XCUIApplication) -> XCUIElement {
        switch route {
        case .shelf: return element(app, "shelf.medal.\(key)")
        case .nameSide, .profileEdit: return element(app, "nameSide.save")
        }
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "medal-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func note(_ name: String, _ text: String) {
        print("MEDALREPRO \(name): \(text)")
        let a = XCTAttachment(string: text)
        a.name = "medal-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }
}
