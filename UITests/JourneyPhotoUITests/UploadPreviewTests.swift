import XCTest

/// **投稿の前のプレビュー**（札 #409・案A・2026-11-15）。投稿の画面の下の帯の「プレビュー」から、投稿したあとの
/// 「詳細」「ホーム」「マイページ」を左右に払って見て、そのまま投稿できるか。
///
/// - 絵: 標準の文字・大きい文字（AX5）・非公開（ホームのページに「ホームには出ません」）
/// - 帯の2つのボタンが横に収まるか、収まらなければ縦に積んでいるかを数で確かめる（`[uploadPreviewBar]` の行）
/// - プレビューの中の「投稿する」で上がり、共有カードが出る
///
/// 見本の1枚（`-JPPreviewUploadSample`）と端末の中の通信（`-JPPreviewLocalBackend`）で開く。
/// **出なければ落とす**（撮る画面まで届かないまま黙って緑にしない・札 #531）
final class UploadPreviewTests: XCTestCase {

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    /// 投稿のあとのカードを閉じた回数の鍵（`CriticalFlowTests.postedCardHabitKey` と同じ）
    private static let postedCardHabitKey = "postedCard.closedWithoutSharing"
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: - 絵

    /// 標準の文字: 帯 → 詳細 → ホーム（札を押して）→ マイページ（左へ払って）
    func testCapturesUploadPreview() {
        capture(extra: [], tag: "標準", expectStacked: false)
    }

    /// 大きい文字（AX5）: 帯は縦に積む
    func testCapturesUploadPreviewLargeText() {
        capture(extra: Self.largeText, tag: "大きい文字", expectStacked: true)
    }

    // 英語の回は置かない（2026-11-15 Mac run 1341）: アプリは日本語に固定で（`Locale.preferredAppLanguage` が "ja"）、
    // `-AppleLanguages (en)` で起動しても帯の字は「プレビュー」「投稿する」のままだった。英語の字が画面に出る日が来たら、
    // 帯は `ViewThatFits` が横に入らなければ縦に積む（`UploadView.submitBar`）

    /// 非公開: ホームのページに「ホームには出ません」、マイページは「非公開」の札
    func testCapturesUploadPreviewPrivate() {
        guard let app = openUpload(extra: []) else { return fail(nil, "投稿の画面（見本の1枚）まで行けない") }
        guard choosePrivate(app) else { return fail(app, "公開範囲で非公開を選べない") }
        guard openPreview(app) else { return fail(app, "「プレビュー」を押してもシートが出ない") }
        let audience = app.descendants(matching: .any)["postPreview.audience"].firstMatch
        XCTAssertTrue(audience.waitForExistence(timeout: 5), "公開範囲の1行が無い")
        XCTAssertTrue(audience.label.contains("非公開"), "公開範囲の1行が非公開でない（\(audience.label)）")
        shoot(app, "409d-投稿のプレビュー（非公開、詳細）")
        tapTab(app, "home")
        let hidden = app.descendants(matching: .any)["postPreview.homeHidden"].firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 10), "非公開なのにホームのページに「ホームには出ません」が無い")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "409e-投稿のプレビュー（非公開、ホーム）")
        tapTab(app, "myPage")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "409f-投稿のプレビュー（非公開、マイページ）")
    }

    // MARK: - 投稿まで

    /// プレビューを開き、中の「投稿する」で上がる（共有カードが出て、閉じると投稿の画面も閉じる）
    func testPostsFromUploadPreview() {
        guard let app = openUpload(extra: []) else { return fail(nil, "投稿の画面（見本の1枚）まで行けない") }
        let title = "PV\(Int(Date().timeIntervalSince1970) % 1_000_000)"
        typeTitle(app, title)
        guard openPreview(app) else { return fail(app, "「プレビュー」を押してもシートが出ない") }
        // 詳細のページに打った題が出る（入力中のものを使う）
        let detail = app.descendants(matching: .any)["postPreview.page.detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "詳細のページが無い")
        let typed = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 15), "詳細のページに打った題「\(title)」が出ない")
        // 左へ払ってホームへ（払いで替わる）
        swipePage(app, left: true)
        XCTAssertTrue(waitSelected(app, "home"), "左へ払ってもホームのページにならない")
        let submit = app.buttons["postPreview.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "プレビューの中に「投稿する」が無い")
        XCTAssertGreaterThanOrEqual(submit.frame.height, 44, "プレビューの「投稿する」の的が 44pt 未満")
        submit.tap()
        let close = app.buttons["postedCard.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 60), "プレビューから投稿しても共有カードが出ない（上がっていない）")
        close.tap()
        XCTAssertTrue(app.buttons["upload.thumb.0"].firstMatch.waitForNonExistence(timeout: 30),
                      "カードを閉じても投稿の画面が閉じない")
    }

    // MARK: - 流れ

    private func capture(extra: [String], tag: String, expectStacked: Bool?) {
        guard let app = openUpload(extra: extra) else {
            return fail(nil, "[\(tag)] 投稿の画面（見本の1枚）まで行けない")
        }
        let preview = app.buttons["upload.preview"].firstMatch
        let submit = app.buttons["upload.submit"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "[\(tag)] 下の帯に「プレビュー」が無い")
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "[\(tag)] 下の帯に「投稿する」が無い")
        XCTAssertTrue(wait(preview, "enabled == true", timeout: 20), "[\(tag)] 写真を読み終えても「プレビュー」が押せない")
        let window = app.windows.firstMatch.frame
        let p = preview.frame, s = submit.frame
        let stacked = p.maxY <= s.minY + 0.5
        let sideBySide = abs(p.midY - s.midY) < 1 && p.maxX <= s.minX + 0.5
        let line = "[uploadPreviewBar] \(tag) preview=\(p) submit=\(s) window=\(window) stacked=\(stacked) sideBySide=\(sideBySide)"
            + " previewLabel=\(preview.label) submitLabel=\(submit.label)"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertTrue(stacked || sideBySide, "[\(tag)] 帯の2つのボタンが重なっている（\(line)）")
        XCTAssertGreaterThanOrEqual(p.height, 44, "[\(tag)] 「プレビュー」の的が 44pt 未満")
        XCTAssertGreaterThanOrEqual(s.height, 44, "[\(tag)] 「投稿する」の的が 44pt 未満")
        XCTAssertGreaterThanOrEqual(p.minX, window.minX - 0.5, "[\(tag)] 「プレビュー」が画面の左の外にはみ出す")
        XCTAssertLessThanOrEqual(s.maxX, window.maxX + 0.5, "[\(tag)] 「投稿する」が画面の右の外にはみ出す")
        if let expectStacked {
            XCTAssertEqual(stacked, expectStacked, "[\(tag)] 帯の積み方が違う（\(line)）")
        }
        shoot(app, "409a-投稿の帯（\(tag)）")

        guard openPreview(app) else { return fail(app, "[\(tag)] 「プレビュー」を押してもシートが出ない") }
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "409b-投稿のプレビュー（\(tag)、詳細）")
        tapTab(app, "home")
        XCTAssertTrue(app.descendants(matching: .any)["postPreview.page.home"].firstMatch.waitForExistence(timeout: 10),
                      "[\(tag)] ホームのページが無い")
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "409c-投稿のプレビュー（\(tag)、ホーム）")
        swipePage(app, left: true)
        XCTAssertTrue(waitSelected(app, "myPage"), "[\(tag)] 左へ払ってもマイページのページにならない")
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "409c2-投稿のプレビュー（\(tag)、マイページ）")
        // 閉じれば書きかけのまま投稿の画面へ戻る
        let close = app.navigationBars.buttons.matching(NSPredicate(format: "label == '閉じる' OR label == 'Close'")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "[\(tag)] プレビューに「閉じる」が無い")
        close.tap()
        XCTAssertTrue(app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 10),
                      "[\(tag)] 閉じても書きかけの投稿の画面に戻らない")
    }

    // MARK: - 道具

    private func openUpload(extra: [String]) -> XCUIApplication? {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewUploadSample", "YES"]
        app.launchArguments += ["-\(Self.postedCardHabitKey)", "0"]
        // 左右の払いの記録（`ProfileTabSwipeLog`・Debug のみ）。払っても替わらなかった回に値で残す
        app.launchArguments += ["-JPPreviewTabSwipeProbe", "YES"]
        app.launchArguments += extra
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 60) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return nil }
        tabBar.buttons.element(boundBy: 2).tap()
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        guard toPhoto.waitForExistence(timeout: 10), toPhoto.isHittable else { return nil }
        toPhoto.tap()
        guard app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 60) else { return nil }
        // 写真の位置から撮影地を引く・撮影スポットの索引を読む間を待つ
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    private func openPreview(_ app: XCUIApplication) -> Bool {
        let preview = app.buttons["upload.preview"].firstMatch
        guard preview.waitForExistence(timeout: 10), wait(preview, "enabled == true", timeout: 20) else { return false }
        // キーボードが出ていても、帯はその上に乗る
        preview.tap()
        return app.descendants(matching: .any)["postPreview.page.detail"].firstMatch.waitForExistence(timeout: 15)
    }

    private func typeTitle(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["upload.title"].firstMatch
        var pushes = 0
        while !(field.exists && field.isHittable), pushes < 8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        XCTAssertTrue(field.exists && field.isHittable, "題の欄まで送っても押せない")
        field.tap()
        if field.responds(to: NSSelectorFromString("hasKeyboardFocus")) {
            let deadline = Date().addingTimeInterval(8)
            while (field.value(forKey: "hasKeyboardFocus") as? Bool) != true, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.5)
                if field.isHittable { field.tap() }
            }
        }
        field.typeText(text)
        // キーボードはしまわない（下の帯はキーボードの上に乗る）。下へ払うと閉じる確かめが出るので払わない
        Thread.sleep(forTimeInterval: 1)
    }

    /// 「詳しい設定」を開いて、公開範囲で非公開を選ぶ
    private func choosePrivate(_ app: XCUIApplication) -> Bool {
        let row = app.buttons["upload.audience"].firstMatch
        let details = app.buttons["upload.details"].firstMatch
        var pushes = 0
        // `isHittable` は下の帯の裏でも真を返す（回 1341: 帯の裏の行を押して「プレビュー」が開いた）。帯の上端より上に出るまで送る
        func aboveBar() -> Bool { row.exists && row.isHittable && row.frame.maxY < barTop(app) - 12 }
        while !aboveBar(), pushes < 10 {
            if details.exists, details.isHittable, !row.exists {
                details.tap()
                Thread.sleep(forTimeInterval: 1)
                pushes += 1
                continue
            }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        guard aboveBar() else { return false }
        row.tap()
        let item = app.buttons.matching(NSPredicate(format: "label == '非公開'")).firstMatch
        guard item.waitForExistence(timeout: 5) else { return false }
        item.tap()
        Thread.sleep(forTimeInterval: 1)
        return true
    }

    /// 下の帯の上端（「プレビュー」と「投稿する」の上の方）
    private func barTop(_ app: XCUIApplication) -> CGFloat {
        [app.buttons["upload.preview"].firstMatch, app.buttons["upload.submit"].firstMatch]
            .filter(\.exists).map(\.frame.minY).min() ?? app.windows.firstMatch.frame.maxY
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.buttons["postPreview.tab.\(name)"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "プレビューの札「\(name)」が無い")
        tab.tap()
        XCTAssertTrue(waitSelected(app, name), "札「\(name)」を押しても選ばれない")
    }

    /// ページの真ん中を左右に払う（ページの中は押せない・払いは入れ物が受ける）
    private func swipePage(_ app: XCUIApplication, left: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
        Thread.sleep(forTimeInterval: 1)
    }

    private func waitSelected(_ app: XCUIApplication, _ name: String) -> Bool {
        let ok = wait(app.buttons["postPreview.tab.\(name)"].firstMatch, "isSelected == true", timeout: 5)
        if !ok {
            // 払い・押しの記録（`mypage.tabs.probe` の値）を残す
            let probe = app.descendants(matching: .any)["mypage.tabs.probe"].firstMatch
            let text = "[uploadPreviewSwipe] want=\(name) probe=\(probe.exists ? "\(probe.value ?? "nil")" : "none")"
            print(text)
            XCTContext.runActivity(named: text) { _ in }
        }
        return ok
    }

    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        let p = NSPredicate(format: predicate)
        return XCTWaiter().wait(for: [expectation(for: p, evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func fail(_ app: XCUIApplication?, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        if let app {
            shoot(app, "届かない（\(step)）")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "要素の木（\(step)）"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTFail("撮る画面まで届かない: \(step)", file: file, line: line)
    }
}
