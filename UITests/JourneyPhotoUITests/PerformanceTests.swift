import XCTest

/// アプリの重さを数で見る（2026-10-31 判断・札 #429 アプリ 1「測る仕組み」）。
///
/// **合否は付けない。** 数（`measure`）を試験のログ（`measured [...] average: …`）と結果（xcresult・
/// ワークフローの成果物 `build-logs`）に残すだけ。時間やメモリで落とすと、Mac の混み具合・通信で赤くなる。
/// 直す前と後は、同じ試験を同じ絞り方（`inputs[screens]=PerformanceTests`）で流して比べる。
///
/// 測るもの:
/// - 起動時間（`XCTApplicationLaunchMetric`・最初の画面が応答するまで）
/// - 起動とホームの読み込みの区間（アプリの `PerfSignpost` の印を `XCTOSSignpostMetric` で拾う）
/// - ホームを送ったときのメモリ（`XCTMemoryMetric`）
/// - ストーリーの輪のある画面（ホームの上の輪の列）のメモリ
/// - 写真の詳細を開いて戻るときのメモリ（大きな写真）
///
/// 🔴 **シミュレータの Debug ビルドの数。** 実機・Release とは違う。比べるのは同じ条件の前後だけ。
/// 写真は本物の公開の写真を通信で読む（見本の通信 `-JPPreviewLocalBackend` は API だけを端末の中で答える）ので、
/// 回によって少し揺れる
final class PerformanceTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// `ScreenshotTests.previewUserId` と同じ（公開 API が誰にでも返している値）
    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"

    /// アプリの `PerfSignpost` と同じ名前（変えるときは両方）
    private static let signpostSubsystem = "com.journeyphoto.JourneyPhoto"
    private static let signpostCategory = "Performance"

    /// 1本の時間を `Tools/xcode-test.sh` の上限（300秒）に収めるため、回数は少なめ
    private static func options(_ iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private func configuredApp(localBackend: Bool, stories: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if localBackend {
            app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
            app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
            app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
            app.launchArguments += ["-JPPreviewLocalBackend", "YES"]
        }
        if stories {
            app.launchArguments += ["-JPPreviewStories", "YES"]
        }
        return app
    }

    /// 同意 → タブまで進める
    private func passConsent(_ app: XCUIApplication) {
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "タブが出ない")
    }

    /// ホームの1枚目の写真が出るまで待つ（出なければ、何を測っても意味が無いので落とす）
    @discardableResult
    private func waitForHomePhoto(_ app: XCUIApplication) -> XCUIElement {
        let photo = app.buttons["feed.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "ホームに写真が出ない")
        // 見えている写真の読み込みが落ち着くまで
        Thread.sleep(forTimeInterval: 4)
        return photo
    }

    /// 積んだ画面から1つ戻る（`ScreenshotTests.goBack` と同じ順。見出しのベルを押さない）
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

    // MARK: - 起動

    /// 起動時間（押してから最初の画面が応答するまで）。同意の画面が最初の画面
    func testLaunchTime() {
        let app = configuredApp(localBackend: false)
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: Self.options(5)) {
            app.launch()
        }
    }

    /// 起動（`init` → 最初の画面）とホームの読み込み（`GalleryViewModel.load`）の区間。
    /// アプリの `PerfSignpost` の印を拾う
    func testLaunchAndHomeLoadSignposts() {
        let app = configuredApp(localBackend: true)
        let metrics: [XCTMetric] = [
            XCTOSSignpostMetric(subsystem: Self.signpostSubsystem, category: Self.signpostCategory, name: "Launch"),
            XCTOSSignpostMetric(subsystem: Self.signpostSubsystem, category: Self.signpostCategory, name: "HomeLoad"),
        ]
        measure(metrics: metrics, options: Self.options(3)) {
            app.launch()
            passConsent(app)
            waitForHomePhoto(app)
            app.terminate()
        }
    }

    // MARK: - メモリ

    /// ホームを下へ送って戻すときのメモリ（`Memory Peak Physical` が一番大きい所）
    func testHomeScrollMemory() {
        let app = configuredApp(localBackend: true)
        app.launch()
        passConsent(app)
        waitForHomePhoto(app)
        measure(metrics: [XCTMemoryMetric(application: app)], options: Self.options(3)) {
            for _ in 0..<5 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
            }
            for _ in 0..<5 {
                app.swipeDown()
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    /// ストーリーの輪のある画面（ホームの上の輪の列）のメモリ。輪の列を左右に送る。
    /// 見本のストーリー（`-JPPreviewStories`）は公開の新着の作者ごとに1本で、写真は公開の写真の原寸
    func testStoryRingsMemory() {
        let app = configuredApp(localBackend: true, stories: true)
        app.launch()
        passConsent(app)
        let mine = app.buttons["あなたのストーリー"].firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 30), "ストーリーの輪が出ない")
        // 輪の写真の読み込みが落ち着くまで
        Thread.sleep(forTimeInterval: 5)
        measure(metrics: [XCTMemoryMetric(application: app)], options: Self.options(3)) {
            // 輪の列の上（自分の輪の右）を横に送る
            let right = mine.coordinate(withNormalizedOffset: CGVector(dx: 4, dy: 0.5))
            let left = mine.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            for _ in 0..<2 {
                right.press(forDuration: 0.05, thenDragTo: left)
                Thread.sleep(forTimeInterval: 1)
            }
            for _ in 0..<2 {
                left.press(forDuration: 0.05, thenDragTo: right)
                Thread.sleep(forTimeInterval: 1)
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    /// 写真の詳細を開いて戻るときのメモリ（上の大きな写真）
    func testPhotoDetailMemory() {
        let app = configuredApp(localBackend: true)
        app.launch()
        passConsent(app)
        let photo = waitForHomePhoto(app)
        XCTAssertTrue(photo.isHittable, "ホームの1枚目の写真が押せない")
        measure(metrics: [XCTMemoryMetric(application: app)], options: Self.options(3)) {
            photo.tap()
            let author = app.buttons["photo.author"].firstMatch
            XCTAssertTrue(author.waitForExistence(timeout: 20), "写真の詳細が出ない")
            // 大きな写真の読み込みが落ち着くまで
            Thread.sleep(forTimeInterval: 4)
            goBack(app)
            XCTAssertTrue(photo.waitForExistence(timeout: 10), "ホームに戻らない")
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
