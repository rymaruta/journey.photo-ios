import XCTest

/// **投稿の題・説明・タグの候補（端末の AI）**（札 #622・2026-11-15）。
///
/// - 絵: 標準の文字・大きい文字（AX5）。題の欄の下の題の候補、説明の欄の下の説明の候補、先頭に並んだタグの候補
/// - 札を押すと題に入り、題の候補が消える（押す回数は1回）。欄は押すまで空のまま（勝手に書き換えない）
/// - 端末の AI が使えない機種と同じ（`-JPOnDeviceAI off`）では、候補の札が1つも出ない
///
/// Mac のシミュレーターは端末の AI を持たないことがあるので、絵の回は決まった候補（`-JPOnDeviceAI sample`・
/// Debug のみ・AI は呼ばない）で見る。**AI の出来はここでは見ない**（`OnDeviceAIProbeTests` の数で見る）。
/// 見本の1枚（`-JPPreviewUploadSample`）と端末の中の通信（`-JPPreviewLocalBackend`）で開く。出なければ落とす
final class UploadSuggestTests: XCTestCase {

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    /// 決まった候補（`PostSuggest.sample`）の1つ目の題
    private static let firstTitle = "秋の兼六園"

    override func setUp() {
        continueAfterFailure = true
    }

    func testCapturesUploadSuggestions() {
        capture(extra: [], tag: "標準")
    }

    func testCapturesUploadSuggestionsLargeText() {
        capture(extra: Self.largeText, tag: "大きい文字")
    }

    /// 端末の AI が使えない機種・OS と同じ: 候補の札は1つも出ない（今と同じ見え方）
    func testNoSuggestionsWhenOnDeviceAIUnavailable() {
        guard let app = openUpload(mode: "off", extra: []) else { return fail(nil, "投稿の画面（見本の1枚）まで行けない") }
        let title = app.textFields["upload.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "題の欄が無い")
        // 候補を作り始めるまでの待ち（0.8 秒）より十分に長く待つ
        Thread.sleep(forTimeInterval: 4)
        XCTAssertFalse(app.buttons["upload.suggest.title.0"].firstMatch.exists, "使えない機種で題の候補が出た")
        XCTAssertFalse(app.buttons["upload.suggest.caption"].firstMatch.exists, "使えない機種で説明の候補が出た")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'AI の候補'")).firstMatch.exists,
                       "使えない機種でタグの候補の印が出た")
        shoot(app, "622c-投稿（端末の AI が使えない機種、候補なし）")
    }

    // MARK: - 流れ

    private func capture(extra: [String], tag: String) {
        guard let app = openUpload(mode: "sample", extra: extra) else { return fail(nil, "[\(tag)] 投稿の画面（見本の1枚）まで行けない") }
        let chip = app.buttons["upload.suggest.title.0"].firstMatch
        guard chip.waitForExistence(timeout: 15) else { return fail(app, "[\(tag)] 題の候補が出ない") }
        let title = app.textFields["upload.title"].firstMatch
        XCTAssertTrue(title.exists, "[\(tag)] 題の欄が無い")
        XCTAssertNotEqual((title.value as? String) ?? "", Self.firstTitle, "[\(tag)] 押す前に題の欄が書き換わっている")
        scrollIntoView(app, chip)
        Thread.sleep(forTimeInterval: 1)
        print("[uploadSuggest] \(tag) title=\(title.frame) chip=\(chip.frame) label=\(chip.label)")
        shoot(app, "622a-投稿（AI の題と説明の候補、\(tag)）")

        // タグの候補（先頭に並ぶ・印つき）まで送って撮る
        let tagIdea = app.buttons.matching(NSPredicate(format: "label CONTAINS 'AI の候補'")).firstMatch
        if tagIdea.waitForExistence(timeout: 5) {
            scrollIntoView(app, tagIdea)
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "622b-投稿（AI のタグの候補、\(tag)）")
        } else {
            XCTFail("[\(tag)] タグの候補（AI の候補の印）が無い")
        }

        // 題の候補を押す → 題に入り、題の候補は消える（押す回数 1）
        scrollIntoView(app, chip)
        chip.tap()
        let filled = NSPredicate(format: "value == %@", Self.firstTitle)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: filled, evaluatedWith: title)], timeout: 5), .completed,
                       "[\(tag)] 題の候補を押しても題に入らない（\(title.value ?? "nil")）")
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: chip)], timeout: 5), .completed,
                       "[\(tag)] 題が入ったのに題の候補が残っている")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "622d-投稿（題の候補を押したあと、\(tag)）")
    }

    // MARK: - 道具

    private func openUpload(mode: String, extra: [String]) -> XCUIApplication? {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewUploadSample", "YES"]
        app.launchArguments += ["-JPOnDeviceAI", mode]
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
        return app
    }

    /// 要素が下の主ボタンの帯（主ボタンの上 12pt）より上に出るまで、短い引きで送る（`UploadTitleFieldTests` と同じ形）
    private func scrollIntoView(_ app: XCUIApplication, _ element: XCUIElement, limit: Int = 12) {
        let submit = app.buttons["upload.submit"].firstMatch
        let window = app.windows.firstMatch.frame
        func barTop() -> CGFloat {
            guard submit.exists, submit.frame.minY > window.midY else { return window.maxY }
            let preview = app.buttons["upload.preview"].firstMatch
            guard preview.exists, preview.frame.minY > window.midY else { return submit.frame.minY }
            return min(submit.frame.minY, preview.frame.minY)
        }
        var pushes = 0
        while element.exists, element.frame.maxY > barTop() - 12, pushes < limit {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        // 上へ行きすぎた（見出しの帯の裏）なら少し戻す
        if element.exists, element.frame.minY < window.minY + 120 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
        }
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
        XCTFail(step, file: file, line: line)
    }
}
