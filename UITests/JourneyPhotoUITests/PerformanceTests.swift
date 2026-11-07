import XCTest

/// アプリの重さを数で見る（2026-10-31 判断・札 #429 アプリ 1「測る仕組み」）。
///
/// **合否は付けない。** 数（`measure`）を試験のログ（`measured [...] average: …`）と結果（xcresult・
/// ワークフローの成果物 `build-logs`）に残すだけ。時間やメモリで落とすと、Mac の混み具合・通信で赤くなる。
/// 直す前と後は、同じ試験を同じ絞り方（`inputs[screens]=PerformanceTests`）で流して比べる。
/// **名指しした回だけ流れる**（`Tools/pick-ui-tests.py` の `ONLY_WHEN_NAMED`・5本で約9分・全部の回では飛ばす）。
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

    /// 🔴 **値を Mac のログに必ず残す**（2026-11-04・札 #429 の見直し）。
    /// `measure` の値（`measured [...] average: …`）は XCTest が自分で書く行で、試験からは読めない。
    /// 以前は `xcode-test.sh` が出力の最後の 400 行しか Actions のログに流しておらず（`| tail -n 400`・run 790 でも
    /// 5 本流れて見えたのは最後の 1 本だけ）、他の試験の値はログに出なかった。いまは全部流れるが、念のため、
    /// 試験が自分でも 1 行（`PERF test=<試験> key=value …`）を残す。
    /// `print` が Mac のログに出るかは確かめていないので、活動の名前（`XCTContext.runActivity`・ログに出る）にも書く。
    /// `Tools/perf-collect.py` が行ごとに拾う。値に空白は入れない
    func perf(_ fields: [(String, String)], test: String = #function) {
        let name = test.replacingOccurrences(of: "()", with: "")
        let line = "PERF test=\(name) " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }

    /// `measure` に、1回ごとの壁時計（ms）を足したもの。`measure` の値のほかに `PERF … metric=wall_ms values=…` を残す。
    /// 最初の1回は XCTest の慣らし（値に数えない）かもしれないので、全部並べる
    private func measureTimed(_ metrics: [XCTMetric], _ iterations: Int, test: String = #function, _ block: () -> Void) {
        var walls: [Int] = []
        measure(metrics: metrics, options: Self.options(iterations)) {
            let start = DispatchTime.now().uptimeNanoseconds
            block()
            walls.append(Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
        }
        perf([("metric", "wall_ms"), ("runs", "\(walls.count)"),
              ("values", walls.map(String.init).joined(separator: ","))], test: test)
    }

    /// 見えない要素 `perf.probe` を読む（0.5 秒ごとに更新されるので、少し待ってから）
    private func readProbe(_ app: XCUIApplication, label: String) -> PerfProbeReading {
        Thread.sleep(forTimeInterval: 1)
        return PerfProbeReading(notePerfProbe(app, label: label))
    }

    /// 記録の要点を `PERF` の1行にする（履歴は空白を `_` に替えて1語にする）
    private func perfProbeFields(_ stage: String, _ reading: PerfProbeReading) -> [(String, String)] {
        [("stage", stage),
         ("selCount", "\(reading.selections.count)"),
         ("sel", reading.selections.joined(separator: ";").replacingOccurrences(of: " ", with: "_")),
         ("task", reading.section("task").replacingOccurrences(of: " ", with: "_")),
         ("stallCount", "\(reading.stall.count)"),
         ("stallMaxMs", "\(reading.stall.maxMs)"),
         ("bodyHome", "\(reading.bodyCount("home"))"),
         ("bodyMyPage", "\(reading.bodyCount("myPage"))"),
         ("bodyPhotoDetail", "\(reading.bodyCount("photoDetail"))")]
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
        measureTimed([XCTApplicationLaunchMetric(waitUntilResponsive: true)], 5) {
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
            // 起動後の `.task(id: auth.state)` の同期の区間（2026-11-04・札 #435 / #429）。
            // LaunchSync は頭から保存・いいねの同期の終わりまで（待ちを含む。2026-11-07 から、ブロック・行きたい場所・購入の送り直しは区間に含めない）、LaunchSyncStores はその中の待たない部分、
            // SweepOrphans と DraftPrepare はその中の 2 つの同期の呼び出し。メインスレッドを占める時間を見る
            XCTOSSignpostMetric(subsystem: Self.signpostSubsystem, category: Self.signpostCategory, name: "LaunchSync"),
            XCTOSSignpostMetric(subsystem: Self.signpostSubsystem, category: Self.signpostCategory, name: "LaunchSyncStores"),
            XCTOSSignpostMetric(subsystem: Self.signpostSubsystem, category: Self.signpostCategory, name: "LaunchSyncSweepOrphans"),
            XCTOSSignpostMetric(subsystem: Self.signpostSubsystem, category: Self.signpostCategory, name: "LaunchSyncDraftPrepare"),
        ]
        measureTimed(metrics, 3) {
            app.launch()
            passConsent(app)
            waitForHomePhoto(app)
            app.terminate()
        }
    }

    // MARK: - 起動直後の記録（札 #435・#429）

    /// 起動して同意 → ホームの写真まで進み、アプリが残した記録（`perf.probe`）を読んで `PERF` に残す。
    /// 取るもの: `selection` を書いた履歴（どこで・何から何へ・起動から ms）・起動後の `.task` の始めと終わり・
    /// メインスレッドの停止（100ms を超えた回数と最大）。**合否は付けない**（要素が出ることだけ見る）
    func testLaunchProbe() {
        let app = configuredApp(localBackend: true)
        enablePerfProbe(app)
        app.launch()
        attachPerfProbeOnFailure(app)
        passConsent(app)
        let probe = app.descendants(matching: .any)[PerfProbeReading.identifier].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 20), "perf.probe が出ない（-JPPreviewPerfProbe が効いていない）")
        perf(perfProbeFields("afterConsent", readProbe(app, label: "afterConsent")))
        waitForHomePhoto(app)
        perf(perfProbeFields("afterHome", readProbe(app, label: "afterHome")))
    }

    /// 主要画面の body の評価回数（ホーム・マイページ・写真詳細）。各段の終わりの数を `PERF` に残す:
    /// ホームが出た後 → マイページへ → ホームへ戻る → 写真を開く → 戻る。**差が評価の回数**。合否は付けない
    func testBodyEvaluationCounts() {
        let app = configuredApp(localBackend: true)
        enablePerfProbe(app)
        app.launch()
        attachPerfProbeOnFailure(app)
        passConsent(app)
        let photo = waitForHomePhoto(app)
        perf(perfProbeFields("home", readProbe(app, label: "home")))

        let tabs = app.tabBars.firstMatch
        let myPage = tabs.buttons["マイページ"]
        XCTAssertTrue(myPage.waitForExistence(timeout: 10), "マイページのタブが無い")
        myPage.tap()
        Thread.sleep(forTimeInterval: 3)
        perf(perfProbeFields("myPage", readProbe(app, label: "myPage")))

        let home = tabs.buttons["ホーム"]
        home.tap()
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "ホームに戻らない")
        Thread.sleep(forTimeInterval: 2)
        perf(perfProbeFields("backHome", readProbe(app, label: "backHome")))

        XCTAssertTrue(photo.isHittable, "ホームの1枚目の写真が押せない")
        photo.tap()
        XCTAssertTrue(app.buttons["photo.author"].firstMatch.waitForExistence(timeout: 20), "写真の詳細が出ない")
        Thread.sleep(forTimeInterval: 4)
        perf(perfProbeFields("photoDetail", readProbe(app, label: "photoDetail")))

        goBack(app)
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "ホームに戻らない")
        Thread.sleep(forTimeInterval: 1)
        perf(perfProbeFields("backFromDetail", readProbe(app, label: "backFromDetail")))
    }

    // MARK: - メインタブ切り替え

    /// 下部タブの往復時間を記録する。初回構築と再訪問は混ぜず、ここでは再訪問を測る。
    /// タブの選択状態が反映されるまでを測るもので、写真のデコード完了時間ではない。
    /// 性能の合否閾値は設けない（CIの負荷による揺れを許容）。
    func testMainTabRevisitTime() {
        let app = configuredApp(localBackend: true)
        app.launch()
        passConsent(app)
        waitForHomePhoto(app)

        let tabs = app.tabBars.firstMatch
        let home = tabs.buttons["ホーム"]
        let search = tabs.buttons["探す"]
        let map = tabs.buttons["マップ"]
        let myPage = tabs.buttons["マイページ"]

        let sequence = [search, map, myPage, home]
        for tab in sequence {
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "測定対象のタブが見つからない: \(tab.label)")
            tab.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed,
                           "初回のタブ選択に失敗: \(tab.label)")
        }

        // タブを一度構築してから再訪問を計測する。
        // 画面の描画完了ではなく、UI操作と選択反映の往復時間である。
        measureTimed([XCTClockMetric()], 3) {
            for tab in sequence {
                tab.tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed,
                               "再訪問のタブ選択に失敗: \(tab.label)")
            }
        }
    }

    // MARK: - メモリ

    /// ホームを下へ送って戻すときのメモリ（`Memory Peak Physical` が一番大きい所）
    func testHomeScrollMemory() {
        let app = configuredApp(localBackend: true)
        app.launch()
        passConsent(app)
        waitForHomePhoto(app)
        measureTimed([XCTMemoryMetric(application: app)], 3) {
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
        measureTimed([XCTMemoryMetric(application: app)], 3) {
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

    /// **ストーリーを開いて人を替え、閉じる**までのメモリ（2026-10-31・札 #429 の見直し）。
    /// 隣の人の面（`StoryReelFace` → `StoryPoster`・全画面）を縮める／縮めないを、同じ回（Mac run 808）で比べて
    /// 縮めない方に決めた（山 226.1 → 217.6MB・閉じた後 191.0 → 139.6MB）。比べた一時の切り替えは消した
    func testStoryReelMemory() {
        let app = configuredApp(localBackend: true, stories: true)
        app.launch()
        passConsent(app)
        let mine = app.buttons["あなたのストーリー"].firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 30), "ストーリーの輪が出ない")
        // 人の輪（自分の輪でないもの）。読み上げは「<名前> のストーリー N本（…）」
        let others = app.buttons.matching(NSPredicate(format: "label CONTAINS 'のストーリー' AND NOT (label BEGINSWITH 'あなた')"))
        let ring = others.firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 20), "人の輪が無い")
        Thread.sleep(forTimeInterval: 4)
        let close = app.buttons["閉じる"].firstMatch
        var round = 0
        // 🔴 run 804: 払った後に「閉じる」が無く（もう閉じていた）、ホームで下へ払ったあと、3回目の輪を押せなかった。
        // 閉じていたかを毎回ログと添付に残し（`reelNote`）、ホームでは払わない。輪は毎回在って押せるまで待つ
        measureTimed([XCTMemoryMetric(application: app)], 3) {
            round += 1
            XCTAssertTrue(ring.waitForExistence(timeout: 20), "\(round) 回目: 人の輪が無い")
            ring.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 15), "\(round) 回目: ストーリーが開かない")
            // 開いた時点で、隣の人の面（`StoryReelFace`・全画面）も描かれている
            Thread.sleep(forTimeInterval: 2)
            // 人を替える（横に払う）。払う途中で隣の人の面が出る。
            // 🔴 run 807: 開いて 12 秒（払う2回）たって「閉じる」を押そうとした所で、ボタンが消えて押せなかった
            // （その間に閉じていた）。開いている時間を短くする（払うのは1回・開いて約5秒で閉じる）
            var openAfter: [Bool] = []
            app.swipeLeft()
            Thread.sleep(forTimeInterval: 2)
            openAfter.append(close.exists)
            let stillOpen = close.exists
            if stillOpen { close.tap() }
            reelNote("\(round) 回目: 払うたびに開いていたか \(openAfter)・閉じるを押したか \(stillOpen)")
            XCTAssertTrue(close.waitForNonExistence(timeout: 15), "\(round) 回目: 閉じない")
            XCTAssertTrue(mine.waitForExistence(timeout: 15), "\(round) 回目: 閉じてホームに戻らない")
            Thread.sleep(forTimeInterval: 2)
        }
    }

    /// 試験の途中の様子をログと結果に残す
    private func reelNote(_ text: String) {
        print("[PerformanceTests] \(text)")
        let note = XCTAttachment(string: text)
        note.name = "リールの様子"
        note.lifetime = .keepAlways
        add(note)
    }

    /// 写真の詳細を開いて戻るときのメモリ（上の大きな写真）
    func testPhotoDetailMemory() {
        let app = configuredApp(localBackend: true)
        app.launch()
        passConsent(app)
        let photo = waitForHomePhoto(app)
        XCTAssertTrue(photo.isHittable, "ホームの1枚目の写真が押せない")
        measureTimed([XCTMemoryMetric(application: app)], 3) {
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
