import XCTest

/// **「投稿」を押したらすぐ写真の一覧**（2026-11-18 owner 採用・案 B1「投稿の入口」）。
///
/// 下の「投稿」から開き、
/// 1. 許可の前（埋め込みの写真選びと「すべての写真をここに並べる」の1行・下に「投稿 | ストーリー」）
/// 2. 許可した後の一覧（4列・正方形・先頭がカメラ）
/// 3. 「ストーリー」に替える → 左から右へ払って投稿に戻す
/// 4. 1枚押した後の欄の段（押す回数: 投稿 → 写真 の2回で欄に届く）→ 外すと一覧に戻る
/// 5. 「選択」で2枚に印 →「次へ（2枚）」→ 1つの投稿で欄は1組（案 B3）→「写真ごとに書く ›」
/// を撮る。案の模型（https://claude.ai/artifact/MBEkPZ71qmZ8d3F9uWNec8 の B1）と比べる絵。
///
/// 🔴 **写真の許可は終わったら元に戻す**（`resetAuthorizationStatus`・`StoryLibraryFirstTests` と同じ理由）
final class CreateFlowLibraryTests: XCTestCase {

    /// 巡回（`ScreenshotTests`）と同じ、鍵を持たないログインの利用者
    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"

    override func setUp() {
        continueAfterFailure = true
        XCUIApplication().resetAuthorizationStatus(for: .photos)
        addTeardownBlock {
            XCUIApplication().resetAuthorizationStatus(for: .photos)
        }
    }

    func testPostTabOpensLibraryFirst() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewDrafts", "YES"]
        // 切り替えの段と「一覧を見ているか」の知らせの順（`createflow.probe`・2026-11-18 確かめ役の指摘の事実取り）
        app.launchArguments += ["-JPCreateFlowProbe", "YES"]
        app.launchArguments += ["-story.captionHintShown", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return unreached(app, "タブが出ない") }

        // 1回目: 下の「投稿」→ すぐ写真の一覧（選ぶシートを挟まない）
        tabBar.buttons.element(boundBy: 2).tap()
        let allow = app.buttons["post.library.allow"].firstMatch
        guard allow.waitForExistence(timeout: 15) else { return unreached(app, "「投稿」で写真の一覧の段が出ない（許可の1行が無い）") }
        let toStory = app.buttons["post.choice.story"].firstMatch
        let toPost = app.buttons["post.choice.photo"].firstMatch
        XCTAssertTrue(toStory.exists && toPost.exists, "下の「投稿 | ストーリー」が無い")
        XCTAssertFalse(app.buttons["post.choice.camera"].firstMatch.exists, "前の選ぶシートの行が残っている")
        XCTAssertTrue(app.buttons["post.choice.drafts"].firstMatch.exists, "一覧の上に「下書き」のチップが無い")
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "40d-投稿の入口（許可の前）")

        // 2. 許す → 一覧（4列・正方形・先頭がカメラ）
        allow.tap()
        guard allowFullPhotoAccess() else { return unreached(app, "写真の許可の札に答えられない") }
        let camera = app.buttons["post.library.camera"].firstMatch
        guard camera.waitForExistence(timeout: 15) else { return unreached(app, "許可したのに一覧（カメラのマス）が出ない") }
        let items = app.buttons.matching(identifier: "post.library.item")
        guard items.firstMatch.waitForExistence(timeout: 15) else { return unreached(app, "一覧に写真が並ばない") }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "40e-投稿の入口（写真の一覧）")
        let screen = app.windows.firstMatch.frame
        note("一覧の寸法", "camera=\(camera.frame) first=\(items.firstMatch.frame) screen=\(screen) items=\(items.count)")
        XCTAssertEqual(camera.frame.height, camera.frame.width, accuracy: 1, "マスが正方形でない")
        // 4列: マスの幅は（画面の幅 − 隙間 4×3）÷ 4
        XCTAssertEqual(camera.frame.width, (screen.width - 12) / 4, accuracy: 2, "4列でない")
        XCTAssertLessThan(camera.frame.minX, 1, "カメラのマスが左端に無い")
        // 構図のマスはカメラの隣（シミュレータはカメラが無いので押せない形で並ぶ）
        let composition = app.buttons["post.choice.composition"].firstMatch
        if composition.exists {
            XCTAssertEqual(composition.frame.minY, camera.frame.minY, accuracy: 1, "構図のマスがカメラの隣に無い")
        }
        // 切り替えはガラスのカプセル（幅 220・高さ 48）の中。下の端の近く
        XCTAssertGreaterThan(toPost.frame.minY, screen.height * 0.85, "切り替えが下に無い")
        XCTAssertGreaterThanOrEqual(toPost.frame.height, 39, "切り替えの的が小さすぎる")

        // 3. 「ストーリー」へ → 同じ一覧（題が替わる）→ 左から右へ払って投稿に戻る
        toStory.tap()
        let storyCamera = app.buttons["story.library.camera"].firstMatch
        guard storyCamera.waitForExistence(timeout: 15) else { return unreached(app, "「ストーリー」に替えても一覧が出ない") }
        XCTAssertTrue(app.staticTexts["新しいストーリー"].firstMatch.exists, "題が「新しいストーリー」でない")
        let storyProbe = app.descendants(matching: .any)["createflow.probe"].firstMatch
        note("切り替えの順（ストーリーに替えた後）", "switcher=\(toPost.exists) probe=\((storyProbe.value as? String) ?? "none")")
        XCTAssertTrue(toPost.exists, "ストーリーに替えたら、下の「投稿 | ストーリー」が消えた")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "40f-投稿の入口（ストーリーに替えた）")
        let storyFirst = app.buttons.matching(identifier: "story.library.item").firstMatch
        guard storyFirst.waitForExistence(timeout: 10) else { return unreached(app, "ストーリーの一覧に写真が並ばない") }
        storyFirst.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: storyFirst.coordinate(withNormalizedOffset: CGVector(dx: 3.5, dy: 0.5)))
        guard camera.waitForExistence(timeout: 10) else { return unreached(app, "右へ払っても投稿に戻らない") }
        XCTAssertTrue(app.staticTexts["新規投稿"].firstMatch.exists, "題が「新規投稿」に戻らない")
        // 🔴 ストーリーから投稿に戻したあとも、下の切り替えが残っているか（前の画面が離れた知らせで消えないか）。
        // 推定で直さず、知らせの順を数で残す（`createflow.probe`）
        Thread.sleep(forTimeInterval: 1.5)
        let probe = app.descendants(matching: .any)["createflow.probe"].firstMatch
        let backLog = (probe.value as? String) ?? "none"
        note("切り替えの順（投稿に戻した後）", "switcher=\(toStory.exists) probe=\(backLog)")
        XCTAssertTrue(toStory.exists && toPost.exists, "ストーリーから投稿に戻したら、下の「投稿 | ストーリー」が消えた")
        // 知らせに送り手（どの切り替えの画面か）が付いて記録される（run 1511 は送り手の無い `note:0` が最後に届いた）
        XCTAssertTrue(backLog.contains("select:post") && backLog.contains("note:post:1"),
                      "投稿に戻したあと、投稿の画面からの「一覧」の知らせが記録に無い: \(backLog)")

        // 4. 1枚押す → そのまま欄の段（投稿 → 写真 の2回）
        items.element(boundBy: 0).tap()
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        guard thumb.waitForExistence(timeout: 30) else { return unreached(app, "マスを押しても欄の段に進まない") }
        XCTAssertFalse(toStory.exists, "欄の段に切り替えが残っている（払うと書きかけを失う）")
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "40h-投稿の入口（1枚押して欄の段）")

        // 写真を外すと一覧の段に戻る
        let remove = app.buttons["1枚目を外す"].firstMatch
        guard remove.waitForExistence(timeout: 5) else { return unreached(app, "1枚目を外す丸が無い") }
        remove.tap()
        guard camera.waitForExistence(timeout: 10) else { return unreached(app, "写真を外しても一覧の段に戻らない") }

        // 5. 「選択」で2枚に印 →「次へ（2枚）」→ 1つの投稿（欄は1組・案 B3）
        let select = app.buttons["post.library.select"].firstMatch
        guard select.waitForExistence(timeout: 5) else { return unreached(app, "右上の「選択」が無い") }
        select.tap()
        guard items.count >= 2 else { return unreached(app, "写真が2枚未満") }
        items.element(boundBy: 0).tap()
        items.element(boundBy: 1).tap()
        let next = app.buttons["post.library.next"].firstMatch
        guard next.waitForExistence(timeout: 5) else { return unreached(app, "印を付けても「次へ」が出ない") }
        XCTAssertTrue(next.label.contains("2枚"), "「次へ（2枚）」でない（\(next.label)）")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "40g-投稿の入口（選択で2枚）")
        next.tap()
        guard app.buttons["upload.thumb.1"].firstMatch.waitForExistence(timeout: 30) else {
            return unreached(app, "「次へ（2枚）」で2枚の欄の段に進まない")
        }
        let perPhoto = app.buttons["upload.perPhoto"].firstMatch
        XCTAssertTrue(perPhoto.waitForExistence(timeout: 5), "1つの投稿なのに「写真ごとに書く」が無い（欄が写真の数だけ出ている）")
        XCTAssertEqual(app.textFields.matching(identifier: "upload.title").count, 1, "1つの投稿なのに題の欄が1組でない")
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "40i-何枚かの投稿（1つの投稿・欄は1組）")
        // 「写真ごとに書く ›」で写真ごとの欄（題の欄が2つ）
        app.swipeUp()
        if perPhoto.isHittable {
            perPhoto.tap()
            XCTAssertTrue(app.textFields.matching(identifier: "upload.title").element(boundBy: 1).waitForExistence(timeout: 5),
                          "「写真ごとに書く」を開いても2枚目の欄が出ない")
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "40j-何枚かの投稿（写真ごとに書く）")
        }

        // 6. 「投稿する」→ 画面がすぐ閉じ、ホームの自分の輪が満ちていく（案 B2）→「投稿しました　カードにする」
        let submit = app.buttons["upload.submit"].firstMatch
        guard submit.waitForExistence(timeout: 5) else { return unreached(app, "「投稿する」が無い") }
        submit.tap()
        // run 1465: 3秒の輪の待ちと絵のあとに「カードにする」を待つと見つからなかった（その回の要素の木には一度出ていた）。
        // 見本の通信は速く、知らせ（6秒）が待つ前に消えていたかを確かめるため、押した直後から 0.25 秒ごとに見て時刻を残す
        let ring = app.descendants(matching: .any)["stories.uploading"].firstMatch
        let makeCard = app.buttons["toast.action"].firstMatch
        let tapped = Date()
        var closedAt: Double?
        var ringAt: Double?
        var cardAt: Double?
        // run 1511: 押した 0.15 秒後の1回目の見回りで「投稿する」がまだ在り、同じ回で輪と知らせも見つかって
        // （ring=0.00 card=0.00）見回りが終わり、閉じた時刻を取り逃がしていた。閉じた時刻と知らせの両方がそろうまで見る
        while Date().timeIntervalSince(tapped) < 90, cardAt == nil || closedAt == nil {
            let t = Date().timeIntervalSince(tapped)
            if closedAt == nil, !submit.exists { closedAt = t }
            if ringAt == nil, ring.exists {
                ringAt = t
                shoot(app, "40k-投稿（送信中・ホームの輪）")
            }
            if cardAt == nil, makeCard.exists { cardAt = t }
            Thread.sleep(forTimeInterval: 0.25)
        }
        note("送ったあとの時刻", "closed=\(closedAt.map { String(format: "%.2f", $0) } ?? "none")"
             + " ring=\(ringAt.map { String(format: "%.2f", $0) } ?? "none")"
             + " card=\(cardAt.map { String(format: "%.2f", $0) } ?? "none")")
        XCTAssertNotNil(closedAt, "「投稿する」で画面が閉じない（送り終えるのを待っている）")
        XCTAssertNotNil(cardAt, "裏で送っても「投稿しました　カードにする」が出ない")
        shoot(app, "40l-投稿（投稿しました　カードにする）")
    }

    /// 写真の許可の札（SpringBoard）で「すべて許可」を押す（`StoryLibraryFirstTests` と同じ言葉）
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
        print("CREATEFLOW \(name): \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 届かなかったら落とす（黙って緑にしない）。その時の画面と要素の木を残す
    private func unreached(_ app: XCUIApplication, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        shoot(app, "40x-投稿の入口（届かない）")
        note("画面の木", app.debugDescription)
        XCTFail("[unreached] \(step)", file: file, line: line)
    }
}
