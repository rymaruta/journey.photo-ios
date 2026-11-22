import XCTest

/// **ストーリーの「＋」は写真と動画の一覧を先に開く**（札 #627・2026-11-15 判断）。
///
/// owner「ストーリーを追加押すとカメラ起動しちゃう！」。今のインスタと同じ形: 一覧の最初のマスがカメラ、
/// マスを押すとそのまま作る段へ（「＋ → 選ぶ」の2回）。ここではホームの輪の「＋」から開き、
/// 1. 許可の前（前の写真選びと「すべての写真をここに並べる」の1行）
/// 2. 許可した後の一覧（先頭がカメラのマス・シミュレータの見本の写真）
/// 3. 1枚押した後の作る段（押す回数が2回で届く）
/// を標準の字と大きい字で撮る。
///
/// 🔴 **写真の許可は終わったら元に戻す**（`resetAuthorizationStatus`）。残すと、あとに流れる
/// `StoryPickerTests`（許可の無い埋め込みの写真選びを押す試験）が一覧の画面に当たって押せなくなる
final class StoryLibraryFirstTests: JPUITestCase {

    /// 巡回（`ScreenshotTests`）と同じ、鍵を持たないログインの利用者
    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"

    /// 自分の輪の「＋」の真ん中（輪の左上から）。`StoriesRow.plusCenter` と同じ計算
    /// （外径 64 −（「＋」の丸 22 の半分 ＋ すき間 3）＋ 2）
    private static let plusCenter: CGFloat = 64 - (22 / 2 + 3) + 2

    override func setUp() {
        continueAfterFailure = true
        // 前の回が許可を残していても、許可の前から始める
        XCUIApplication.jp().resetAuthorizationStatus(for: .photos)
        addTeardownBlock {
            XCUIApplication.jp().resetAuthorizationStatus(for: .photos)
        }
    }

    func testStoryPlusOpensLibraryFirst() {
        run(extra: [], tag: "標準の字")
    }

    func testStoryPlusOpensLibraryFirstLargeText() {
        run(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"], tag: "大きい字")
    }

    // MARK: - 流れ

    private func run(extra: [String], tag: String) {
        let app = XCUIApplication.jp()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewStories", "YES"]
        // 入口の案内「写真を押してひとこと」（端末に1回だけ）は撮らない（作る段の絵に被る）
        app.launchArguments += ["-story.captionHintShown", "YES"]
        app.launchArguments += extra
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else {
            return unreached(app, "タブが出ない", tag: tag)
        }

        // ホームの輪の「＋」（自分の輪の右下）。輪が無い形でも同じ所が「ストーリーを追加」になる
        let mine = app.buttons["あなたのストーリー"].firstMatch
        guard mine.waitForExistence(timeout: 20) else { return unreached(app, "自分の輪が出ない", tag: tag) }
        Thread.sleep(forTimeInterval: 2)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: mine.frame.minX + Self.plusCenter, dy: mine.frame.minY + Self.plusCenter)).tap()

        // 1. 許可の前: 前の写真選び（許可が要らない）と「すべての写真をここに並べる」の1行
        let allow = app.buttons["story.library.allow"].firstMatch
        guard allow.waitForExistence(timeout: 15) else {
            return unreached(app, "「＋」で作る画面の写真を選ぶ段が出ない（許可を求める1行が無い）", tag: tag)
        }
        XCTAssertFalse(app.buttons["story.library.camera"].firstMatch.exists, "許可の前に一覧が出ている")
        XCTAssertGreaterThanOrEqual(allow.frame.height, 43.9, "許可の1行の的が 44pt 未満")
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "41c-ストーリーの＋（許可の前）\(tag)")

        // 2. 許す → 一覧（先頭がカメラのマス）
        allow.tap()
        guard allowFullPhotoAccess() else { return unreached(app, "写真の許可の札に答えられない", tag: tag) }
        let camera = app.buttons["story.library.camera"].firstMatch
        guard camera.waitForExistence(timeout: 15) else {
            return unreached(app, "許可したのに一覧（カメラのマス）が出ない", tag: tag)
        }
        let items = app.buttons.matching(identifier: "story.library.item")
        let firstItem = items.firstMatch
        guard firstItem.waitForExistence(timeout: 15) else {
            return unreached(app, "一覧に写真が並ばない（シミュレータの見本の写真）", tag: tag)
        }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "41d-ストーリーの＋（写真と動画の一覧）\(tag)")
        note("一覧の数", "items=\(items.count) camera=\(camera.frame) first=\(firstItem.frame)")
        // カメラが最初のマス（左上）。次のマスは同じ行の右
        XCTAssertLessThan(camera.frame.minX, firstItem.frame.minX, "カメラのマスが先頭でない")
        XCTAssertEqual(camera.frame.minY, firstItem.frame.minY, accuracy: 1, "カメラのマスと最初の写真が同じ行に無い")
        // 2026-11-18（案 B1・owner 採用）: 投稿と共通の一覧にして、模型どおり正方形・4列（前は縦長 2:3・3列）
        XCTAssertEqual(camera.frame.height, camera.frame.width, accuracy: 1, "マスが正方形でない")
        XCTAssertGreaterThanOrEqual(camera.frame.width, 44, "マスの的が 44pt 未満")
        XCTAssertFalse(app.buttons["story.library.allow"].firstMatch.exists, "許可した後も許可の1行が残る")
        XCTAssertTrue(app.buttons["story.library.select"].firstMatch.exists, "右上の「選択」が無い")
        XCTAssertTrue(app.buttons["story.library.albums"].firstMatch.exists, "右上のアルバムが無い")

        // 3. 1枚押す → そのまま作る段（「＋ → 選ぶ」の2回）
        firstItem.tap()
        let share = app.buttons["シェアする"].firstMatch
        let canvas = app.descendants(matching: .any)["story.canvas"].firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !(canvas.exists || share.exists) {
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard canvas.exists || share.exists else {
            return unreached(app, "マスを押しても作る段に進まない", tag: tag)
        }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "41e-ストーリーの＋（1枚押して作る段）\(tag)")
    }

    /// 写真の許可の札（SpringBoard）で「すべて許可」を押す。シミュレータの言葉（英語・日本語）と
    /// iOS の版で文言が違うので、知っている言葉を順に探す。iOS 18 で確かめの札が続いたらそれも押す
    private func allowFullPhotoAccess() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["フルアクセスを許可", "すべての写真へのアクセスを許可", "Allow Full Access", "Allow Access to All Photos"]
        var answered = false
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: answered ? 3 : 10) else { break }
            guard let label = labels.first(where: { alert.buttons[$0].exists }) else {
                let seen = (0..<alert.buttons.count).map { alert.buttons.element(boundBy: $0).label }
                note("許可の札の言葉", seen.joined(separator: " / "))
                return false
            }
            alert.buttons[label].tap()
            answered = true
            Thread.sleep(forTimeInterval: 1)
        }
        return answered
    }

    // MARK: - 記録

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func note(_ name: String, _ text: String) {
        print("STORYLIBRARY \(name): \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 届かなかったら落とす（黙って緑にしない・札 #531）。その時の画面と要素の木を残す
    private func unreached(_ app: XCUIApplication, _ step: String, tag: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        shoot(app, "41x-ストーリーの＋（届かない）\(tag)")
        note("画面の木", app.debugDescription)
        XCTFail("[unreached] \(tag) \(step)", file: file, line: line)
    }
}
