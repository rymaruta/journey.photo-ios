import XCTest

/// **投稿の画面で題の欄に打っている間、欄がキーボードと下の主ボタンの帯の上に見えているか**（札 #607・2026-11-14）。
///
/// 統合の枝の回 1317・1321 の `[uploadFieldProbe]` で、「秋の兼六園」と打つと題の欄が
/// 標準の文字で y=520 → 621（帯の裏）、大きい文字（AX5）で y=468.7 → 1214.7（画面の外）へ動いた。
/// スクロールの領域とキーボードの枠は同じだったので、欄より上に何かが差し込まれたと見て、
/// **打つ前と後で、欄より上の要素を全部（種類・識別子・字・枠）**書き出して見比べる（`UPLOADTITLE …` の行）。
///
/// 回 1324（直す前・main 7b95b3b）の答え: 打った後に欄より上で増えたのは「観光スポット「兼六園」に結ぶ」の札
/// （`upload.autoSpot`・題から撮影スポットの候補が出た）だけで、ほかの要素は1つも動いていない。
/// 札の高さは標準の文字で 71pt（欄 y=359→460）、大きい文字で 716pt（欄 y=176→922・キーボードの上端 655 の裏）。
/// 直し（`UploadView.form` の `onChange(of: autoSpotLayoutKey)`）を戻すと、大きい文字の試験が落ちる
/// （下の主ボタンの帯がある版では標準の文字も落ちる）。
///
/// 見本の1枚（`-JPPreviewUploadSample`）と端末の中の通信（`-JPPreviewLocalBackend`）で開く。
final class UploadTitleFieldTests: XCTestCase {

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    /// 打つ題。兼六園は撮影スポットの名前（題から撮影スポットを選ぶ道に当たる）
    private static let typedTitle = "秋の兼六園"

    override func setUp() {
        continueAfterFailure = true
    }

    /// 標準の文字
    func testTitleFieldStaysVisibleWhileTyping() {
        run(extra: [], tag: "std")
    }

    /// 大きい文字（AX5）
    func testTitleFieldStaysVisibleWhileTypingLargeText() {
        run(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], tag: "ax5")
    }

    // MARK: - 流れ

    private func run(extra: [String], tag: String) {
        guard let app = openUpload(extra: extra) else {
            return XCTFail("[\(tag)] 投稿の画面（見本の1枚）まで行けない")
        }
        let title = app.textFields["upload.title"].firstMatch
        let submit = app.buttons["upload.submit"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "[\(tag)] 題の欄が無い")
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "[\(tag)] 「投稿する」が無い")
        scrollAboveSubmitBar(app, title, submit: submit)
        log(tag, "scrolled " + frames(app, title, submit))

        title.tap()
        XCTAssertTrue(waitForFocus(title), "[\(tag)] 題の欄を押しても焦点が来ない")
        // キーボードが出きって、焦点の欄へ送る動きが終わるまで
        Thread.sleep(forTimeInterval: 1.5)
        log(tag, "tapped " + frames(app, title, submit))
        let before = above(app, title)
        dump(tag, "tapped", before)
        shoot(app, "\(tag)-打つ前")

        title.typeText(Self.typedTitle)
        var after: [Item] = []
        for wait in [0.0, 1.5, 4.0] {
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            log(tag, "typed+\(wait)s " + frames(app, title, submit))
            after = above(app, title)
            dump(tag, "typed+\(wait)s", after)
        }
        diff(tag, before, after)
        shoot(app, "\(tag)-打った後")

        // 打っている欄が、スクロールの領域の中で、キーボードと下の主ボタンの帯（主ボタンの上 12pt）より上に全部見えていること。
        // 「投稿する」が右上（ナビの帯）にある版では、下の帯は無い（main 7b95b3b・回 1324 で submit y=86）
        let field = title.frame
        let keyboard = app.keyboards.firstMatch
        let scroll = app.scrollViews.containing(.textField, identifier: "upload.title").firstMatch
        let window = app.windows.firstMatch.frame
        let top = scroll.exists ? scroll.frame.minY : window.minY
        var limit = keyboard.exists ? keyboard.frame.minY : window.maxY
        if submit.frame.minY > window.midY { limit = min(limit, barTop(app, submit) - 12) }
        XCTAssertEqual((title.value as? String) ?? "", Self.typedTitle, "[\(tag)] 打った字が欄に入っていない")
        XCTAssertTrue(waitForFocus(title, timeout: 1), "[\(tag)] 打った後に題の欄の焦点が外れた")
        XCTAssertLessThanOrEqual(field.maxY, limit + 0.5,
                                 "[\(tag)] 打った後の題の欄 \(field) がキーボード・下の帯の上端 \(limit) より下にある（見えない）")
        XCTAssertGreaterThanOrEqual(field.minY, top - 0.5,
                                    "[\(tag)] 打った後の題の欄 \(field) がスクロールの領域の上端 \(top) より上にある（見えない）")
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

    /// 欄が下の主ボタンの帯（主ボタンの上 12pt）より上に全部出るまで、短い引きで送る。
    /// `isHittable` は帯の裏の欄でも真を返すので、それに頼らない（回 1304/1317）
    private func scrollAboveSubmitBar(_ app: XCUIApplication, _ element: XCUIElement, submit: XCUIElement,
                                      limit: Int = 8) {
        var pushes = 0
        while element.exists, submit.exists, element.frame.maxY > barTop(app, submit) - 12, pushes < limit {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
    }

    /// 下の帯の上端（2026-11-15 札 #409: 主ボタンの左か上に「プレビュー」が並ぶ。大きい文字では上に積むので、
    /// 帯の上端は2つのボタンの上の方）
    private func barTop(_ app: XCUIApplication, _ submit: XCUIElement) -> CGFloat {
        let preview = app.buttons["upload.preview"].firstMatch
        guard preview.exists, preview.frame.minY > app.windows.firstMatch.frame.midY else { return submit.frame.minY }
        return min(submit.frame.minY, preview.frame.minY)
    }

    /// 欄そのものの焦点（非公開の属性なので在るときだけ読む。読めない環境ではキーボードが出ているか）
    private func waitForFocus(_ field: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let app = XCUIApplication()
        func focused() -> Bool {
            if field.responds(to: NSSelectorFromString("hasKeyboardFocus")) {
                return (field.value(forKey: "hasKeyboardFocus") as? Bool) == true
            }
            return app.keyboards.firstMatch.exists
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !focused(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            if !focused(), field.isHittable { field.tap() }
        }
        return focused()
    }

    private func frames(_ app: XCUIApplication, _ field: XCUIElement, _ submit: XCUIElement) -> String {
        func f(_ e: XCUIElement) -> String { e.exists ? "\(e.frame)" : "none" }
        let scroll = app.scrollViews.containing(.textField, identifier: "upload.title").firstMatch
        return "field=\(f(field)) submit=\(f(submit)) scroll=\(f(scroll)) keyboard=\(f(app.keyboards.firstMatch))"
            + " window=\(f(app.windows.firstMatch)) value=\(field.exists ? "\(field.value ?? "nil")" : "none")"
    }

    /// 欄より上の要素（スクロールの領域の中）。種類・識別子・字（先頭 24 字）・枠
    private struct Item {
        let key: String
        let frame: CGRect
    }

    private func above(_ app: XCUIApplication, _ field: XCUIElement) -> [Item] {
        let scroll = app.scrollViews.containing(.textField, identifier: "upload.title").firstMatch
        guard scroll.exists, field.exists, let root = try? scroll.snapshot() else { return [] }
        let fieldTop = field.frame.minY
        var items: [Item] = []
        var seen: [String: Int] = [:]
        func walk(_ s: XCUIElementSnapshot) {
            let wanted: Set<XCUIElement.ElementType> = [.staticText, .button, .switch, .textField, .textView, .image]
            if (wanted.contains(s.elementType) || !s.identifier.isEmpty), s.frame.height > 0, s.frame.minY < fieldTop {
                let label = String(s.label.prefix(24)).replacingOccurrences(of: "\n", with: " ")
                var key = "\(s.elementType.rawValue)|\(s.identifier)|\(label)"
                // 同じ鍵が2つあれば番号で分ける
                let n = seen[key, default: 0]
                seen[key] = n + 1
                if n > 0 { key += "#\(n)" }
                items.append(Item(key: key, frame: s.frame))
            }
            s.children.forEach(walk)
        }
        walk(root)
        return items.sorted { $0.frame.minY < $1.frame.minY }
    }

    private func dump(_ tag: String, _ step: String, _ items: [Item]) {
        log(tag, "\(step) above.count=\(items.count)")
        for item in items { log(tag, "\(step) above \(item.key) \(item.frame)") }
    }

    /// 打つ前にだけ在る・打った後にだけ在る要素と、両方に在って動いた要素（dy）
    private func diff(_ tag: String, _ before: [Item], _ after: [Item]) {
        let b = Dictionary(before.map { ($0.key, $0.frame) }, uniquingKeysWith: { a, _ in a })
        let a = Dictionary(after.map { ($0.key, $0.frame) }, uniquingKeysWith: { a, _ in a })
        for item in after where b[item.key] == nil { log(tag, "diff added \(item.key) \(item.frame)") }
        for item in before where a[item.key] == nil { log(tag, "diff removed \(item.key) \(item.frame)") }
        for item in after {
            if let old = b[item.key], abs(old.minY - item.frame.minY) > 0.5 || abs(old.height - item.frame.height) > 0.5 {
                log(tag, "diff moved \(item.key) dy=\(item.frame.minY - old.minY) dh=\(item.frame.height - old.height)")
            }
        }
    }

    private func log(_ tag: String, _ line: String) {
        print("UPLOADTITLE [\(tag)] \(line)")
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "UPLOADTITLE-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
