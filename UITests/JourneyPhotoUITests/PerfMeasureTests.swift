import XCTest

/// **重い表示の直しの前後を測る**（2026-10-28・計測用の枝 `claude/perf-measure*` だけ。main に入れない）。
///
/// 普段の回（PR の検証・TestFlight・`screens` 空）では流さない（`Tools/pick-ui-tests.py` の `ONLY_WHEN_NAMED`）。
/// 流すのは `ios-testflight.yml` を `submit=false`・`screens=PerfMeasure` で呼んだときだけ。
///
/// - 値は Mac の CI の**シミュレーター**のもの（実機ではない）
/// - 書き込みは端末の中だけ（`-JPPreviewLocalBackend`）。読むのは公開の写真の一覧と画像（`ScreenshotTests` と同じ本番の静的サイト）。
///   ユーザー API は既定（staging）のまま向けない
/// - 結果は xcodebuild のログの `measured [...]` の行と、この試験が出す `PERF:` の行
final class PerfMeasureTests: XCTestCase {

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    private static let iterations = 5

    override func setUp() {
        continueAfterFailure = false
        // 起動し直す場面は 1 回 1 分ほどかかる（5 回 + 1 回）。上限は xcode-test.sh の最大（1200 秒）
        executionTimeAllowance = 1200
    }

    // MARK: - 道具

    private func makeApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES"]
        app.launchArguments += extra
        return app
    }

    /// 起動して同意を済ませ、タブまで出す
    private func launch(_ app: XCUIApplication) {
        app.launch()
        let agree = app.buttons["legal.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 60), "同意の画面が出ない")
        var taps = 0
        while agree.exists, taps < 3 {
            if agree.isHittable { agree.tap() } else { agree.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            taps += 1
            _ = agree.waitForNonExistence(timeout: 5)
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "タブが出ない")
    }

    private func tab(_ app: XCUIApplication, _ index: Int) {
        let button = app.tabBars.firstMatch.buttons.element(boundBy: index)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "タブ \(index) が無い")
        button.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, _ what: String, pushes: Int = 10) {
        var n = 0
        while !(element.exists && element.isHittable), n < pushes {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            Thread.sleep(forTimeInterval: 1)
            n += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(what) まで送っても押せない")
    }

    private func wait(_ element: XCUIElement, _ predicate: String, _ args: [Any] = [], timeout: TimeInterval = 15) -> Bool {
        let p = NSPredicate(format: predicate, argumentArray: args)
        return XCTWaiter().wait(for: [expectation(for: p, evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func appMetrics(_ app: XCUIApplication) -> [XCTMetric] {
        [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]
    }

    private func manualOptions() -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = Self.iterations
        o.invocationOptions = [.manuallyStart, .manuallyStop]
        return o
    }

    /// 速い指で上へ送る（画面の真ん中の縦の線で）
    private func flingUp(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                   withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func flingDown(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
                   withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func toTop(_ app: XCUIApplication, _ times: Int = 14) {
        for _ in 0..<times { flingDown(app) }
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// 探すの「おすすめ」の「すべて見る」から、カテゴリの集約の一覧（`PhotoGrid`）を開く
    private func openCollection(_ app: XCUIApplication) {
        tab(app, 1)
        // 一覧の読み込みを待ってから、「すべて見る」が木に出るまで送る（Lazy なので画面の外は木に無い・run 717）
        XCTAssertTrue(app.descendants(matching: .any)["search.field"].firstMatch.waitForExistence(timeout: 30), "探すが出ない")
        Thread.sleep(forTimeInterval: 6)
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'すべて見る'")).firstMatch
        var pushes = 0
        while !(more.exists && more.isHittable), pushes < 20 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
        }
        XCTAssertTrue(more.exists && more.isHittable, "探すに「すべて見る」が出ない（送った回数 \(pushes)）")
        note("「すべて見る」まで送った回数=\(pushes) ラベル=\(more.label)")
        more.tap()
        XCTAssertTrue(more.waitForNonExistence(timeout: 15), "集約の一覧が開かない")
        Thread.sleep(forTimeInterval: 4)
    }

    /// ホームの1枚目を開く（並び＝ホームの一覧が、大きく見る画面のサムネイルの列になる）
    private func openFirstFeedPhoto(_ app: XCUIApplication) {
        tab(app, 0)
        let recommended = app.buttons["おすすめ"].firstMatch
        if recommended.waitForExistence(timeout: 5), recommended.isHittable { recommended.tap() }
        let photo = app.buttons["feed.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 40), "ホームに写真が出ない")
        reveal(photo, in: app, "ホームの1枚目")
        photo.tap()
        XCTAssertTrue(app.buttons["photo.like"].firstMatch.waitForExistence(timeout: 20), "写真の詳細が開かない")
        Thread.sleep(forTimeInterval: 2)
    }

    private func note(_ text: String) {
        print("PERF: \(name) \(text)")
        let a = XCTAttachment(string: text)
        a.lifetime = .keepAlways
        add(a)
    }

    // MARK: - 1. 写真の格子（集約の一覧）を下まで速く送る

    func testPerfGridScroll() {
        let app = makeApp()
        launch(app)
        openCollection(app)
        measure(metrics: appMetrics(app), options: manualOptions()) {
            startMeasuring()
            for _ in 0..<12 { flingUp(app) }
            Thread.sleep(forTimeInterval: 1.5)
            stopMeasuring()
            toTop(app)
        }
    }

    /// 同じ送りのヒッチ（止まりかけのコマ）の割合
    func testPerfGridScrollHitches() {
        let app = makeApp()
        launch(app)
        openCollection(app)
        let o = XCTMeasureOptions()
        o.iterationCount = Self.iterations
        o.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: o) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            toTop(app, 4)
        }
    }

    // MARK: - 2. 検索で10文字を1字ずつ打つ

    func testPerfSearchTyping() {
        let app = makeApp()
        launch(app)
        tab(app, 1)
        let field = app.descendants(matching: .any)["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30), "検索の欄が無い")
        // 一覧の読み込みを待つ（件数の行が出る）
        Thread.sleep(forTimeInterval: 6)
        field.tap()
        Thread.sleep(forTimeInterval: 1)
        let word = "kyotoshrin"
        measure(metrics: appMetrics(app), options: manualOptions()) {
            startMeasuring()
            for ch in word { app.typeText(String(ch)) }
            // 最後の打鍵の描き直しまで
            Thread.sleep(forTimeInterval: 1)
            stopMeasuring()
            let clear = app.buttons["search.clear"].firstMatch
            if clear.exists { clear.tap() } else {
                app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: word.count))
            }
            Thread.sleep(forTimeInterval: 1.5)
            if app.keyboards.count == 0 { field.tap() }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // MARK: - 3. 写真を大きく見る画面を開いて、サムネイルの列を送る

    func testPerfViewerThumbnails() {
        let app = makeApp()
        launch(app)
        // ホームの札の詳細は並びが同じ投稿の写真だけ（多くは1枚＝列が出ない・run 717）。
        // 集約の一覧から開くと、並びが一覧の全部になる（`CollectionPhotosScreen` の context）
        openCollection(app)
        var opened = false
        for y in [0.5, 0.65, 0.8, 0.4] where !opened {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: y)).tap()
            opened = app.buttons["photo.like"].firstMatch.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(opened, "集約の一覧から写真の詳細が開かない")
        Thread.sleep(forTimeInterval: 2)
        let close = app.buttons["閉じる"].firstMatch
        var counted = false
        measure(metrics: appMetrics(app), options: manualOptions()) {
            startMeasuring()
            // 写真詳細の上の写真を押すと開く
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap()
            let second = app.buttons["2枚目"].firstMatch
            XCTAssertTrue(second.waitForExistence(timeout: 15), "大きく見る画面のサムネイルの列が出ない")
            let y = second.frame.midY
            let w = app.frame.width
            let row = app.coordinate(withNormalizedOffset: .zero)
            for _ in 0..<8 {
                row.withOffset(CGVector(dx: w * 0.9, dy: y))
                    .press(forDuration: 0.01, thenDragTo: row.withOffset(CGVector(dx: w * 0.05, dy: y)),
                           withVelocity: .fast, thenHoldForDuration: 0)
            }
            Thread.sleep(forTimeInterval: 1)
            stopMeasuring()
            if !counted {
                counted = true
                let n = app.buttons.matching(NSPredicate(format: "label ENDSWITH '枚目'")).count
                note("サムネイルの札（木に出ている数）=\(n)")
            }
            XCTAssertTrue(close.waitForExistence(timeout: 5), "閉じるが無い")
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 10), "閉じない")
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: - 4. ホームを上から下まで送る・札のいいねを押す

    func testPerfHomeScroll() {
        let app = makeApp()
        launch(app)
        tab(app, 0)
        XCTAssertTrue(app.buttons["feed.photo"].firstMatch.waitForExistence(timeout: 40), "ホームに写真が出ない")
        Thread.sleep(forTimeInterval: 3)
        measure(metrics: appMetrics(app), options: manualOptions()) {
            startMeasuring()
            for _ in 0..<12 { flingUp(app) }
            Thread.sleep(forTimeInterval: 1.5)
            stopMeasuring()
            toTop(app)
        }
    }

    func testPerfHomeScrollHitches() {
        let app = makeApp()
        launch(app)
        tab(app, 0)
        XCTAssertTrue(app.buttons["feed.photo"].firstMatch.waitForExistence(timeout: 40), "ホームに写真が出ない")
        Thread.sleep(forTimeInterval: 3)
        let o = XCTMeasureOptions()
        o.iterationCount = Self.iterations
        o.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: o) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            toTop(app, 4)
        }
    }

    /// 札のいいねを押して灯る → もう一度押して戻る（1 回の計測で 2 回押す）
    func testPerfHomeLike() {
        let app = makeApp()
        launch(app)
        tab(app, 0)
        XCTAssertTrue(app.buttons["feed.photo"].firstMatch.waitForExistence(timeout: 40), "ホームに写真が出ない")
        Thread.sleep(forTimeInterval: 3)
        let like = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'いいね '")).firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 20), "札のいいねが無い")
        reveal(like, in: app, "札のいいね")
        measure(metrics: appMetrics(app), options: manualOptions()) {
            let before = like.isSelected
            startMeasuring()
            like.tap()
            XCTAssertTrue(wait(like, "selected == %@", [!before], timeout: 10), "いいねが灯らない")
            like.tap()
            XCTAssertTrue(wait(like, "selected == %@", [before], timeout: 10), "いいねが戻らない")
            stopMeasuring()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: - 5. 地図を開いて動かす

    func testPerfMapPan() {
        let app = makeApp()
        launch(app)
        tab(app, 3)
        let mapMode = app.buttons["map.mode.map"].firstMatch
        if mapMode.waitForExistence(timeout: 10), mapMode.isHittable { mapMode.tap() }
        _ = app.descendants(matching: .any).matching(identifier: "map.photoPin").firstMatch.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 3)
        let pins = app.descendants(matching: .any).matching(identifier: "map.photoPin").count
            + app.descendants(matching: .any).matching(identifier: "map.photoCluster").count
        note("地図のピン（はじめ）=\(pins)")
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        func drag(_ dx: CGFloat, _ dy: CGFloat) {
            center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: dx, dy: dy)),
                         withVelocity: .default, thenHoldForDuration: 0.05)
        }
        measure(metrics: appMetrics(app), options: manualOptions()) {
            startMeasuring()
            drag(-150, 0); drag(0, -150); drag(150, 0); drag(0, 150)
            if app.maps.firstMatch.exists {
                app.maps.firstMatch.pinch(withScale: 2.0, velocity: 2)
                app.maps.firstMatch.pinch(withScale: 0.5, velocity: -2)
            }
            Thread.sleep(forTimeInterval: 1)
            stopMeasuring()
        }
    }

    // MARK: - 6. とおまわり号の中に入る・模様替えの見本を開く（毎回起動し直す＝控えの無い最初の1回）

    private func openCamperEntrance(_ app: XCUIApplication) -> XCUIElement {
        tab(app, 4)
        let tripsTab = app.buttons["profile.tab.trips"].firstMatch
        XCTAssertTrue(tripsTab.waitForExistence(timeout: 30), "旅の記録のタブが無い")
        Thread.sleep(forTimeInterval: 3)
        reveal(tripsTab, in: app, "旅の記録のタブ", pushes: 4)
        tripsTab.tap()
        let camper = app.buttons["trips.camper"].firstMatch
        XCTAssertTrue(camper.waitForExistence(timeout: 20), "キャンピングカーの行が無い")
        reveal(camper, in: app, "キャンピングカーの行")
        camper.tap()
        let enter = app.buttons["camper.room.enter"].firstMatch
        XCTAssertTrue(enter.waitForExistence(timeout: 30), "「中に入る」が無い")
        reveal(enter, in: app, "中に入る")
        Thread.sleep(forTimeInterval: 2)
        return enter
    }

    /// 部屋の読み上げの `ms=` （組み始めから組み終えるまで・アプリ自身が測る）
    private func readyMs(_ scene: XCUIElement) -> String {
        let value = scene.value as? String ?? ""
        guard let r = value.range(of: "ms=") else { return "?" }
        return String(value[r.upperBound...].prefix { $0.isNumber })
    }

    func testPerfCamperEnterRoom() {
        let app = makeApp(["-JPPreviewCamperRoomReset", "YES"])
        var ms: [String] = []
        measure(metrics: appMetrics(app), options: manualOptions()) {
            launch(app)
            let enter = openCamperEntrance(app)
            let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
            startMeasuring()
            enter.tap()
            XCTAssertTrue(scene.waitForExistence(timeout: 30), "部屋に入れない")
            XCTAssertTrue(wait(scene, "value CONTAINS 'camper-room-ready'", timeout: 90), "部屋を組み終えない")
            stopMeasuring()
            ms.append(readyMs(scene))
            app.terminate()
        }
        note("部屋の組み上げ ms（アプリの読み上げ）=\(ms.joined(separator: ","))")
    }

    func testPerfCamperStyleSwatches() {
        let app = makeApp(["-JPPreviewCamperRoomReset", "YES"])
        measure(metrics: appMetrics(app), options: manualOptions()) {
            launch(app)
            let enter = openCamperEntrance(app)
            enter.tap()
            let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
            XCTAssertTrue(wait(scene, "value CONTAINS 'camper-room-ready'", timeout: 90), "部屋を組み終えない")
            Thread.sleep(forTimeInterval: 3)
            let style = app.buttons["camper.room.tool.style"].firstMatch
            XCTAssertTrue(style.waitForExistence(timeout: 10), "模様替えの札が無い")
            let swatch = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camper.room.style.'")).firstMatch
            startMeasuring()
            style.tap()
            XCTAssertTrue(swatch.waitForExistence(timeout: 20), "模様替えの見本が出ない")
            // 見本の絵が描き上がるまで（前は開くときに画面の処理の中で描いていた・後は外で描いて差し替える）
            Thread.sleep(forTimeInterval: 2)
            stopMeasuring()
            app.terminate()
        }
    }
}
