import XCTest

/// **ストーリーで写真をライブラリから選んだら、「シェアする」が押せるようになる**（2026-10-09）。
///
/// owner の報告（TestFlight 1.0.72・1.0.73）: ストーリーを作り、ライブラリから写真を選ぶと、
/// 投稿のボタンが灰色（押せない）のまま戻らない。ここで実際にシミュレータの写真の見本を選び、
/// 各段を撮り、「シェアする」が決まった時間のうちに押せるようになるかを確かめる。
///
/// 写真を選ぶ画面（PHPicker）は別プロセスで、中が木（accessibility）に出ない回がある。
/// **選ぶ所まで行けなかった回は落とさない**（撮れる所まで撮り、何が見えたかを書き残して抜ける）。
/// 選べた後に押せないままなら落とす——それがこの試験の見張り。
final class StoryPickerTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    /// 巡回（`ScreenshotTests`）と同じ、鍵を持たないログインの利用者
    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"

    /// 「シェアする」が押せるようになるまで待つ上限（秒）。
    /// 読み込みの上限（1枚 60 秒）より短く——返らない読み込みを「待てば直る」と見逃さない
    private static let shareDeadline: TimeInterval = 30

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func note(_ name: String, _ text: String) {
        print("STORYREPRO \(name): \(text)")
        let a = XCTAttachment(string: text)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// 一巡と同じ立ち上げ方で、投稿の2択 →「ストーリー」まで。開けなければ nil
    private func openComposer() -> XCUIApplication? {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launch()

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return nil }
        tabBar.buttons.element(boundBy: 2).tap()
        let toStory = app.buttons["post.choice.story"].firstMatch
        guard toStory.waitForExistence(timeout: 5), toStory.isHittable else { return nil }
        toStory.tap()
        return app
    }

    /// 埋め込みの写真選びの初回に出る「写真へのプライベートアクセス」の「OK」
    private func dismissPrivacyNotice(_ app: XCUIApplication) {
        for label in ["OK", "了解"] {
            let ok = app.buttons[label].firstMatch
            if ok.waitForExistence(timeout: 3), ok.isHittable {
                ok.tap()
                Thread.sleep(forTimeInterval: 1)
                return
            }
        }
    }

    /// 写真の格子の、押せる写真（大きさで絞る——下の画面の札・アイコンを拾わない）
    private func pickerPhotos(_ app: XCUIApplication) -> [XCUIElement] {
        let all = app.images.allElementsBoundByIndex.prefix(60)
        return all.filter { el in
            guard el.exists, el.isHittable else { return false }
            let f = el.frame
            return f.width >= 60 && f.height >= 60
        }
    }

    /// 「シェアする」が押せるまで待つ。途中を撮る。押せたら秒数、押せなければ nil
    private func waitForShare(_ app: XCUIApplication, tag: String) -> TimeInterval? {
        let share = app.buttons["シェアする"].firstMatch
        let start = Date()
        var shotAt: Set<Int> = []
        var log: [String] = []
        while Date().timeIntervalSince(start) < Self.shareDeadline {
            let t = Date().timeIntervalSince(start)
            let exists = share.exists
            let enabled = exists && share.isEnabled
            let value = exists ? String(describing: share.value ?? "") : "-"
            log.append(String(format: "%.1fs exists=%@ enabled=%@ value=%@", t,
                              exists.description, enabled.description, value))
            for mark in [1, 5, 15] where t >= Double(mark) && !shotAt.contains(mark) {
                shotAt.insert(mark)
                shoot(app, "\(tag)-待ち\(mark)秒")
            }
            if enabled {
                note("\(tag)-待ちの記録", log.joined(separator: "\n"))
                return t
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        shoot(app, "\(tag)-押せないまま\(Int(Self.shareDeadline))秒")
        note("\(tag)-待ちの記録", log.joined(separator: "\n"))
        note("\(tag)-画面の木", app.debugDescription)
        return nil
    }

    /// 写真を選ぶ段（埋め込みの格子）で `count` 枚に印を付け、「次へ（N枚）」で仕上げる段へ
    private func pickOnPickStage(count: Int, tag: String) {
        guard let app = openComposer() else {
            note("\(tag)-開けなかった", "投稿の2択からストーリーを開けなかった")
            return
        }
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "\(tag)-1-開いた")
        dismissPrivacyNotice(app)

        let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '次へ' OR label BEGINSWITH 'Next'")).firstMatch
        var photos = pickerPhotos(app)
        if photos.count < count {
            Thread.sleep(forTimeInterval: 3)
            photos = pickerPhotos(app)
        }
        guard photos.count >= count else {
            shoot(app, "\(tag)-2-写真が木に出ない")
            note("\(tag)-画面の木", app.debugDescription)
            return
        }
        for (i, photo) in photos.prefix(count).enumerated() {
            photo.tap()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "\(tag)-2-印\(i + 1)枚目")
        }
        guard next.waitForExistence(timeout: 5) else {
            note("\(tag)-次へが無い", app.debugDescription)
            return
        }
        note("\(tag)-次へ", "label=\(next.label) enabled=\(next.isEnabled)")
        XCTAssertTrue(next.label.contains("\(count)"), "印の数が「次へ」に出ない: \(next.label)")
        guard next.isEnabled else {
            shoot(app, "\(tag)-3-次へが押せない")
            XCTFail("\(count)枚に印を付けたのに「次へ」が押せない（\(next.label)）")
            return
        }
        next.tap()
        shoot(app, "\(tag)-3-次へを押した直後")

        let took = waitForShare(app, tag: "\(tag)-4")
        shoot(app, "\(tag)-5-おわり")
        XCTAssertNotNil(took, "\(count)枚を選んで「次へ」の後、\(Int(Self.shareDeadline))秒たっても「シェアする」が押せない")
        if let took { note("\(tag)-押せるまで", String(format: "%.1f 秒", took)) }

        // 続けて、仕上げる段の「＋」→「ライブラリ」（シートの写真選び）から1枚足す
        guard took != nil else { return }
        addFromLibrarySheet(app, tag: "\(tag)-6")
    }

    /// 仕上げる段の並びの「＋」→「ライブラリ」で1枚足す。足した後も「シェアする」が押せること
    private func addFromLibrarySheet(_ app: XCUIApplication, tag: String) {
        let plus = app.buttons["写真を追加"].firstMatch
        guard plus.waitForExistence(timeout: 5), plus.isHittable else {
            note("\(tag)-＋が無い", app.debugDescription)
            return
        }
        plus.tap()
        let library = app.buttons["ライブラリ"].firstMatch
        guard library.waitForExistence(timeout: 5) else {
            shoot(app, "\(tag)-メニューが出ない")
            return
        }
        library.tap()
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "\(tag)-1-シートの写真選び")
        let photos = pickerPhotos(app)
        guard let photo = photos.last else {
            note("\(tag)-写真が木に出ない", app.debugDescription)
            return
        }
        photo.tap()
        Thread.sleep(forTimeInterval: 1)
        shoot(app, "\(tag)-2-印")
        var added = false
        for label in ["追加", "Add", "完了", "Done"] {
            let done = app.navigationBars.buttons[label].firstMatch
            if done.exists, done.isHittable {
                done.tap()
                added = true
                break
            }
            let any = app.buttons[label].firstMatch
            if any.exists, any.isHittable {
                any.tap()
                added = true
                break
            }
        }
        note("\(tag)-追加を押せた", added.description)
        shoot(app, "\(tag)-3-追加の直後")
        let took = waitForShare(app, tag: "\(tag)-4")
        XCTAssertNotNil(took, "＋から1枚足した後、「シェアする」が押せない")
    }

    func testPickOnePhotoEnablesShare() {
        pickOnPickStage(count: 1, tag: "90-ストーリー1枚")
    }

    func testPickThreePhotosEnablesShare() {
        pickOnPickStage(count: 3, tag: "91-ストーリー3枚")
    }
}
