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
/// - 探すで1字ずつ打ったときの、1字あたりの body の回数・撮影スポットを当てた回数と ms・止まった長さ（`testSearchTypingProbe`・札 #590）
/// - よく使う操作を一通り流したときの、段ごとの停止・body の回数・メモリ・積みの見本（`testUsageSurveyProbe`・札 #594）
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
         ("stalls", reading.stalls.joined(separator: ";").replacingOccurrences(of: " ", with: "_")),
         ("ev", reading.events.joined(separator: ";").replacingOccurrences(of: " ", with: "_")),
         ("samples", reading.samples.joined(separator: ";").replacingOccurrences(of: " ", with: "_")),
         ("bodyHome", "\(reading.bodyCount("home"))"),
         ("bodyMyPage", "\(reading.bodyCount("myPage"))"),
         ("bodyPhotoDetail", "\(reading.bodyCount("photoDetail"))"),
         // 探す（2026-11-13 札 #590）: body の評価回数と、撮影スポットを語で当てた 回数/合計/最大
         ("bodySearch", "\(reading.bodyCount("search"))"),
         ("spot", reading.section("spot"))]
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
    /// ホームの画面の中で押せる写真の札（`feed.photo`）のうち一番上（同じ高さなら左）。無ければ nil。
    /// 木の順の 1 つ目は画面の外のことがある（2026-11-14 Mac の回 1256・1 本の並び）ので、位置で選ぶ
    private func topmostHittableFeedPhoto(_ app: XCUIApplication) -> XCUIElement? {
        app.buttons.matching(identifier: "feed.photo").allElementsBoundByIndex
            .filter { $0.isHittable }
            .min { a, b in
                let fa = a.frame, fb = b.frame
                return fa.minY != fb.minY ? fa.minY < fb.minY : fa.minX < fb.minX
            }
    }

    /// ホームの写真が押せないときの事実（写真の位置・画面の大きさ・1本の並びの上端 `top`・並びの写真の札の位置と押せるか・
    /// 画面の木のホームの部分）をログに出し、画面の絵を残す（2026-11-14 Mac の回 1255・推定で直さないための記録）
    private func noteUnhittableHomePhoto(_ app: XCUIApplication, _ photo: XCUIElement, round: Int) {
        var lines: [String] = []
        let exists = photo.exists
        lines.append("[surveyPhoto] round=\(round) exists=\(exists) hittable=\(exists && photo.isHittable) "
                     + "frame=\(exists ? String(describing: photo.frame) : "-") label=\(exists ? photo.label : "-") "
                     + "window=\(String(describing: app.windows.firstMatch.frame))")
        let probe = app.descendants(matching: .any)["home.feed.probe"].firstMatch
        lines.append("[surveyPhoto] probe=\(probe.exists ? String(describing: probe.value ?? "-") : "(無い)")")
        let tabs = app.tabBars.firstMatch
        lines.append("[surveyPhoto] tabBar=\(tabs.exists ? String(describing: tabs.frame) : "(無い)") "
                     + "selected=\(tabs.exists ? tabs.buttons.matching(NSPredicate(format: "isSelected == true")).firstMatch.label : "-")")
        let tiles = app.buttons.matching(identifier: "feed.photo")
        let count = tiles.count
        lines.append("[surveyPhoto] feed.photo count=\(count)")
        for index in 0..<min(count, 8) {
            let tile = tiles.element(boundBy: index)
            lines.append("[surveyPhoto] tile[\(index)] frame=\(String(describing: tile.frame)) hittable=\(tile.isHittable) label=\(tile.label)")
        }
        // 画面の木のうち、ホームの札・写真・見出しの行だけ（全部は長すぎる）
        let tree = app.debugDescription.components(separatedBy: "\n")
            .filter { $0.contains("feed.") || $0.contains("home.") || $0.contains("header.") || $0.contains("NavigationBar") }
        for line in tree.prefix(60) { lines.append("[surveyPhoto] tree \(line.trimmingCharacters(in: .whitespaces))") }
        for line in lines {
            print(line)
            XCTContext.runActivity(named: String(line.prefix(900))) { _ in }
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "surveyPhoto round \(round)"
        shot.lifetime = .keepAlways
        add(shot)
    }

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

    // MARK: - 探す（2026-11-13 札 #590「探すの検索が重い」）

    /// 1字ずつ打つ語。「京」→「京都」→（消す）→「富」→「富士」→「富士山」→（消す）
    private static let searchWords = ["京都", "富士山"]

    /// 1字ごとの語（アプリの `srch=` の語と同じ）
    private static var searchPrefixes: [String] {
        searchWords.flatMap { word in (1...word.count).map { String(word.prefix($0)) } }
    }

    /// **探すで1字ずつ打ったときの重さ**（2026-11-13 札 #590・owner「探すの検索がめっちゃ重い」）。合否は付けない。
    ///
    /// 探すを開き、撮影スポットの索引（本番 約 3,900 件）を読み終えてから、「京」「京都」「富士山」を1字ずつ打つ（3回）。
    /// アプリの記録（`perf.probe` の `srch=`・`PerfRecorder.searchBody`）から、**1字あたり**の
    /// - body の評価回数（`SearchView`）
    /// - 撮影スポットを語で当てた回数（`SearchView.spotHits`）と合計・最大 ms
    /// - 画面の刻みの間隔の最大 ms（メインスレッドが止まった長さ）と、100ms を超えた回数
    ///
    /// を取り、`measured [Search 京 body, count] …` の行（`SearchProbeMetric`）と `PERF test=testSearchTypingProbe …` の行に残す。
    /// 当てる関数（`OfficialSpotIndex.matches`）の区間 `SpotMatch` も `XCTOSSignpostMetric` で取る。
    /// 止まっている最中の積み（`samples=`）は `PERF-PROBE` の行に残る
    func testSearchTypingProbe() {
        let app = configuredApp(localBackend: true)
        enablePerfProbe(app)
        // 主スレッドの積みを 0.3 秒ごとにファイルへ（画面の木を読まない・止まっている最中も撮れる）。
        // `samples=` は 16 枚で、探すを開くまでに使い切っていた（回 1229）。回ごとに遅い行を `PERF-MAINSAMPLE` で出す
        let samplePath = ScreenshotTests.mainSamplePath("search")
        app.launchArguments += ["-JPMainSampleFile", samplePath]
        var sampleLinesSeen = 0
        app.launch()
        attachPerfProbeOnFailure(app)
        passConsent(app)
        waitForHomePhoto(app)

        let searchTab = app.tabBars.firstMatch.buttons["探す"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10), "探すのタブが無い")
        searchTab.tap()
        let field = app.textFields["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "探す欄が出ない")
        // 撮影スポットの索引（約 1.5MB）を読み終えるまで待つ（読む前に打つと、当てる相手が空で軽く見える）
        Thread.sleep(forTimeInterval: 8)
        perf(perfProbeFields("searchOpen", readProbe(app, label: "searchOpen")))

        let box = SearchProbeBox(prefixes: Self.searchPrefixes)
        let metrics: [XCTMetric] = [
            XCTOSSignpostMetric(subsystem: Self.signpostSubsystem, category: Self.signpostCategory, name: "SpotMatch"),
            SearchProbeMetric(box: box),
        ]
        var round = 0
        measure(metrics: metrics, options: Self.options(3)) {
            round += 1
            let before = SearchWindowReading.all(readProbe(app, label: "search\(round)Before")).count
            for word in Self.searchWords {
                field.tap()
                XCTAssertTrue(waitForFocus(field, app), "\(round) 回目: 探す欄に焦点が来ない")
                for ch in word {
                    field.typeText(String(ch))
                    // 人の検索の待ち（300ms）と返事、見えない要素の更新（0.5 秒ごと）を待つ
                    Thread.sleep(forTimeInterval: 1.5)
                }
                let clear = app.buttons["search.clear"].firstMatch
                XCTAssertTrue(clear.waitForExistence(timeout: 10), "\(round) 回目: 消す「×」が無い")
                clear.tap()
                Thread.sleep(forTimeInterval: 1.5)
            }
            sampleLinesSeen = logSlowMainSamples(samplePath, round: round, from: sampleLinesSeen)
            let reading = readProbe(app, label: "search\(round)")
            let windows = Array(SearchWindowReading.all(reading).dropFirst(before))
            var rows: [SearchWindowReading] = []
            for prefix in Self.searchPrefixes {
                let w = windows.first { $0.query == prefix } ?? SearchWindowReading(query: prefix)
                rows.append(w)
                perf([("stage", "round\(round)"), ("q", prefix), ("found", windows.contains { $0.query == prefix } ? "1" : "0"),
                      ("body", "\(w.bodies)"), ("spotHits", "\(w.spotHits)"), ("spotTotalMs", "\(w.spotTotalMs)"),
                      ("spotMaxMs", "\(w.spotMaxMs)"), ("gapMaxMs", "\(w.gapMaxMs)"), ("stalls", "\(w.stalls)"),
                      ("spotsChanged", "\(w.spotsChanged)"), ("spotsChangedMs", "\(w.spotsChangedMs)")],
                     test: "testSearchTypingProbe")
            }
            box.push(rows)
        }
    }

    /// 積みのファイルの `from` 行目から後で、主スレッドの返事が遅い行（pending・100ms 以上）を
    /// `PERF-MAINSAMPLE round=N ms=… t=… wall=… ping=… | 積み` でログに出す（行頭の UTC の時刻と、UI テストの操作を突き合わせる）。
    /// 読んだ行の数を返す。行の前後の速い行も1つずつ出す（止まり始めと終わりが分かるように）
    private func logSlowMainSamples(_ path: String, round: Int, from: Int) -> Int {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("PERF-MAINSAMPLE round=\(round) unreadable path=\(path)")
            return from
        }
        let lines = text.split(separator: "\n").map(String.init)
        guard from < lines.count else { return lines.count }
        func slow(_ line: String) -> Bool {
            guard let ping = line.components(separatedBy: "ping=").dropFirst().first?.split(separator: " ").first else { return false }
            return ping == "pending" || (Int(ping) ?? 0) >= 100
        }
        var printed = Set<Int>()
        for i in from..<lines.count where slow(lines[i]) {
            for j in max(from, i - 1)...min(lines.count - 1, i + 1) where printed.insert(j).inserted {
                print("PERF-MAINSAMPLE round=\(round) \(String(lines[j].prefix(1200)))")
            }
        }
        print("PERF-MAINSAMPLE round=\(round) summary lines=\(lines.count - from) slow=\(lines[from...].filter(slow).count)")
        return lines.count
    }

    /// 欄に焦点が来るまで待つ（`ScreenshotTests.waitForKeyboardFocus` と同じ見方。来なければ false）
    private func waitForFocus(_ field: XCUIElement, _ app: XCUIApplication, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if field.responds(to: NSSelectorFromString("hasKeyboardFocus")),
               (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                return true
            }
            if app.keyboards.firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
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

    // MARK: - よく使う操作を一通り（札 #594「アプリ全体を軽くする」の下調べ・2026-11-13）

    /// 見えない要素 `perf.timeline` を読む（0.5 秒ごとに更新されるので、少し待ってから）
    private func readTimeline(_ app: XCUIApplication) -> PerfTimelineReading {
        Thread.sleep(forTimeInterval: 0.6)
        let element = app.descendants(matching: .any)[PerfTimelineReading.identifier].firstMatch
        return PerfTimelineReading((element.exists ? element.value as? String : nil) ?? "")
    }

    /// **よく使う操作を一通り流し、画面（段）ごとの重さを数で並べる**（札 #594・owner「アプリ全体を軽くしたい」）。合否は付けない。
    ///
    /// 段: 起動→ホーム・ホームを速く縦に送る・写真詳細を開いて戻る×3・マイページを開いて送る・地図を開いて動かす・
    /// DM の一覧を開く・投稿の札を開く・投稿の画面を開く（投稿の画面は閉じずに終える＝最後に置く）。
    /// 各段の始めと終わりにアプリの通しの記録（`perf.timeline`・`PerfTimeline`）を読み、その間の
    /// - 100ms を超えた主スレッドの停止の回数・最大 ms・合計 ms（`CADisplayLink` の刻みの間隔）
    /// - 画面ごとの body の評価回数（`body.home`・`home.tile.body`・`body.map` など）
    /// - アプリの使うメモリの山と終わり（MB・`phys_footprint`）
    /// - 止まっている最中の主スレッドの積みの見本（`PerfMainSampler`）
    ///
    /// を `PERF test=testUsageSurveyProbe stage=<段> …` と `measured [Survey <番号> <段> stall total, ms] …` に残す。
    /// 最後に停止の合計の大きい順の並び（`stage=ranking`）も残す。
    /// 🔴 シミュレータの Debug ビルドの数（実機・Release とは違う）。比べるのは同じ条件の前後だけ。
    /// **名指しした回だけ流す**（`screens=testUsageSurveyProbe`・`ONLY_WHEN_NAMED`）。1 本 5 分以内（`xcode-test.sh` の上限 300 秒）
    func testUsageSurveyProbe() {
        let app = configuredApp(localBackend: true)
        // DM の一覧を見本の通信で答える・投稿の画面を見本の 1 枚を選んだ状態で開く（写真の選び手を出さない）
        app.launchArguments += ["-JPPreviewDM", "YES", "-JPPreviewUploadSample", "YES"]
        enablePerfProbe(app)
        // 1本の並び（札 #595）の数と上端（`home.feed.probe` の `top`）。押せないときの事実取りに読む（2026-11-14 Mac の回 1255）
        app.launchArguments += ["-JPPreviewFeedProbe", "YES"]
        // 主スレッドの積みを 0.3 秒ごとにファイルへ（止まりの見張りは 650ms までしか撮らない。run 1244 の 5956ms の
        // 止まりの残りが、XCUITest の画面読みかアプリの描画か分けられなかった・2026-11-14 札 #594）
        let tracePath = ScreenshotTests.mainSamplePath("survey")
        app.launchArguments += ["-JPMainSampleFile", tracePath]

        var marks: [(name: String, start: PerfTimelineReading, end: PerfTimelineReading, wallMs: Int)] = []
        var pool: [(ms: Int, stack: String)] = []
        var last = PerfTimelineReading("t=0")
        var began = Date()
        func finish(_ name: String) {
            let wallMs = Int(Date().timeIntervalSince(began) * 1000)
            let reading = readTimeline(app)
            for sample in reading.samples where !pool.contains(where: { $0.ms == sample.ms && $0.stack == sample.stack }) {
                pool.append(sample)
            }
            marks.append((name, last, reading, wallMs))
            last = reading
            began = Date()
        }

        // 1. 起動 → ホームの 1 枚目（同意を含む）
        app.launch()
        attachPerfProbeOnFailure(app)
        passConsent(app)
        let photo = app.buttons["feed.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "ホームに写真が出ない")
        XCTAssertTrue(app.descendants(matching: .any)[PerfTimelineReading.identifier].firstMatch.waitForExistence(timeout: 10),
                      "perf.timeline が出ない（-JPPreviewPerfProbe が効いていない）")
        Thread.sleep(forTimeInterval: 2)
        finish("launchToHome")

        // 2. ホームを速く縦に送って戻す
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        for _ in 0..<7 { app.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1)
        finish("homeFastScroll")

        // 3. 写真詳細を開いて戻る × 3
        let tabs = app.tabBars.firstMatch
        for round in 1...3 {
            // 押すのは**画面の中で押せる写真の札のうち一番上**（`topmostHittableFeedPhoto`）。木の順の 1 つ目（`firstMatch`）ではない。
            // 2026-11-14 判断（Mac の回 1256 の `[surveyPhoto]`）: 統合 1.1.87（札 #595 の 1 本の並び）で、頭にいる（`top=0.00`）のに
            // `feed.photo` の木の順の 1 つ目が y=946.7（画面 956・タブの帯 873 より下＝画面の外・押せない）で、押せる札は
            // 2〜4 つ目（y=469・712・712）だった（`following=3`）。木の順は画面の上からの順と限らない
            _ = photo.waitForExistence(timeout: 10)
            let target = topmostHittableFeedPhoto(app)
            // 押せる札が無いときだけ事実を残す（回 1255 は位置・上端が記録に無かった）
            if target == nil { noteUnhittableHomePhoto(app, photo, round: round) }
            guard let target else {
                XCTFail("\(round) 回目: ホームの画面の中に押せる写真が無い")
                return
            }
            target.tap()
            XCTAssertTrue(app.buttons["photo.author"].firstMatch.waitForExistence(timeout: 20), "\(round) 回目: 写真の詳細が出ない")
            Thread.sleep(forTimeInterval: 1.5)
            goBack(app)
            XCTAssertTrue(photo.waitForExistence(timeout: 10), "\(round) 回目: ホームに戻らない")
            Thread.sleep(forTimeInterval: 1)
        }
        finish("photoDetailOpenBack3")

        // 4. マイページを開いて送る
        let myPage = tabs.buttons["マイページ"]
        XCTAssertTrue(myPage.waitForExistence(timeout: 10), "マイページのタブが無い")
        myPage.tap()
        _ = app.descendants(matching: .any)["mypage.nameLine"].firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<4 { app.swipeUp(velocity: .fast) }
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1)
        finish("myPageOpenScroll")

        // 5. 地図を開いて動かす（ずらす 4 回・寄る・引く）
        let mapTab = tabs.buttons["マップ"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 10), "マップのタブが無い")
        mapTab.tap()
        let map = app.maps.firstMatch
        _ = map.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 2)
        let surface = map.exists ? map : app
        let center = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        for offset in [CGVector(dx: 0.2, dy: 0.65), CGVector(dx: 0.8, dy: 0.45), CGVector(dx: 0.5, dy: 0.3), CGVector(dx: 0.5, dy: 0.75)] {
            center.press(forDuration: 0.05, thenDragTo: surface.coordinate(withNormalizedOffset: offset))
            Thread.sleep(forTimeInterval: 0.5)
        }
        if map.exists {
            map.pinch(withScale: 2.5, velocity: 2)
            Thread.sleep(forTimeInterval: 0.8)
            map.pinch(withScale: 0.4, velocity: -2)
        }
        Thread.sleep(forTimeInterval: 1.5)
        finish("mapOpenPan")

        // 6. DM の一覧を開く（ホームの見出しの吹き出しから）
        let home = tabs.buttons["ホーム"]
        home.tap()
        let bubble = app.buttons["header.messages"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 15), "見出しの吹き出しが無い")
        began = Date()   // 段はタブを替えた後から（ホームに戻るのは前の段の後片づけ）
        bubble.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dm.inbox"].firstMatch.waitForExistence(timeout: 15), "DM の一覧が出ない")
        Thread.sleep(forTimeInterval: 2)
        finish("dmInboxOpen")
        // DM の一覧はシート（`RootView` の `showMessages`）。左上の「閉じる」で閉じる
        let closeMessages = app.buttons["messages.close"].firstMatch
        if closeMessages.waitForExistence(timeout: 5) { closeMessages.tap() }
        XCTAssertTrue(closeMessages.waitForNonExistence(timeout: 10), "DM の一覧が閉じない")
        Thread.sleep(forTimeInterval: 1)

        // 7. 投稿の札を開く（下のタブの真ん中）
        began = Date()
        XCTAssertGreaterThan(tabs.buttons.count, 2, "投稿のタブが無い")
        tabs.buttons.element(boundBy: 2).tap()
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        XCTAssertTrue(toPhoto.waitForExistence(timeout: 10), "投稿の札が出ない")
        Thread.sleep(forTimeInterval: 1)
        finish("postSheetOpen")

        // 8. 投稿の画面を開く（見本の 1 枚を選んだ状態）。閉じずに終える
        toPhoto.tap()
        XCTAssertTrue(app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 20), "投稿の画面が出ない")
        Thread.sleep(forTimeInterval: 2)
        finish("composeOpen")

        // 最後の段の終わりにまだ止まっていた分も入るように、少し待って読み直す（停止とメモリはこの読み取りから数える）
        Thread.sleep(forTimeInterval: 1.5)
        let final = readTimeline(app)
        for sample in final.samples where !pool.contains(where: { $0.ms == sample.ms && $0.stack == sample.stack }) {
            pool.append(sample)
        }
        let stages = marks.map {
            PerfSurveyStage(name: $0.name, from: $0.start, to: $0.end, final: final, samplePool: pool, wallMs: $0.wallMs)
        }
        // 主スレッドの積みのファイル（`-JPMainSampleFile`）。止まりの最中の行を、止まりごとに全部ログに出す（2026-11-14）
        let traceText = (try? String(contentsOfFile: tracePath, encoding: .utf8)) ?? ""
        let trace = traceText.split(separator: "\n").compactMap { PerfMainTraceLine(String($0)) }
        print("PERF-MAIN test=testUsageSurveyProbe lines=\(trace.count) slow=\(trace.filter(\.isSlow).count) path=\(tracePath)")
        for stage in stages {
            for stall in stage.stalls where stall.gapMs >= 300 {
                for line in PerfMainTraceLine.during(trace, startMs: stall.startMs, gapMs: stall.gapMs) {
                    print("PERF-MAIN test=testUsageSurveyProbe stage=\(stage.name) stall=\(stall.startMs):\(stall.gapMs) "
                          + "kind=\(PerfSurveyStage.kind(of: [line.frames.joined(separator: "^")])) \(line.raw)")
                }
            }
        }
        let traceFile = XCTAttachment(string: traceText)
        traceFile.name = "main thread trace"
        traceFile.lifetime = .keepAlways
        add(traceFile)
        for stage in stages {
            var stallTexts: [String] = []
            for stall in stage.stalls {
                let kinds = PerfMainTraceLine.kinds(PerfMainTraceLine.during(trace, startMs: stall.startMs, gapMs: stall.gapMs))
                stallTexts.append("\(stall.startMs):\(stall.gapMs)" + (kinds.isEmpty ? "" : "[\(kinds)]"))
            }
            let stallsText = stallTexts.joined(separator: ",")
            perf([("stage", stage.name), ("startMs", "\(stage.startMs)"), ("endMs", "\(stage.endMs)"), ("wallMs", "\(stage.wallMs)"),
                  ("stallCount", "\(stage.stallCount)"), ("stallMaxMs", "\(stage.stallMaxMs)"), ("stallTotalMs", "\(stage.stallTotalMs)"),
                  // 止まりの全部（始め:長さ ms・アプリの時計）と、その最中の 0.3 秒ごとの積みの種類（2026-11-14）
                  ("stalls", stallsText),
                  ("memPeakMB", "\(stage.memPeakMB)"), ("memEndMB", "\(stage.memEndMB)"), ("bodyTotal", "\(stage.bodyTotal)"),
                  ("bodies", stage.bodies.map { "\($0.0):\($0.1)" }.joined(separator: ",")),
                  // 2026-11-14: 止まりの種類（XCUITest が画面を読む ax・ログ log・アプリ app）・評価し直した理由・処理の時間・控えの大きさ
                  ("stallKinds", stage.stallKinds.map { "\($0.0):\($0.1)x/\($0.2)ms" }.joined(separator: ",")),
                  ("changes", stage.changes.map { "\($0.0):\($0.1)" }.joined(separator: ",")),
                  ("durs", stage.durations.map { "\($0.0):\($0.1)x/\($0.2)ms" }.joined(separator: ",")),
                  ("gauges", stage.gauges.map { "\($0.0):\($0.1)" }.joined(separator: ",")),
                  ("samples", stage.samples.joined(separator: ";").replacingOccurrences(of: " ", with: "_"))])
        }
        // 停止の合計の大きい順（段:合計 ms/回数/最大 ms）
        let ranking = stages.sorted { $0.stallTotalMs > $1.stallTotalMs }
            .map { "\($0.name):\($0.stallTotalMs)ms/\($0.stallCount)x/max\($0.stallMaxMs)ms" }
        perf([("stage", "ranking"), ("byStallTotal", ranking.joined(separator: ",")),
              ("droppedStalls", "\(final.droppedStalls)")])
        let raw = XCTAttachment(string: final.raw)
        raw.name = "perf.timeline final"
        raw.lifetime = .keepAlways
        add(raw)
        // 起動の切り分けの記録（`ev=`・最初の 16 件の積み）も残す
        notePerfProbe(app, label: "surveyEnd")

        // 段ごとの数を `measured [...]` の行に出す（値は段を流し終えた後に決まっている。回数 1）
        measure(metrics: [PerfSurveyMetric(stages: stages)], options: Self.options(1)) {}
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

/// アプリの `srch=` の1語分（`+1234ms 京 b2 h2/400ms/300ms g450ms s1 c1/80ms`・`PerfRecorder.searchBody` の形。変えるときは両方。
/// 末尾の `c…` は 2026-11-14 に足した——古い形（6つ）も読む）
struct SearchWindowReading {
    let query: String
    var bodies = 0
    var spotHits = 0
    var spotTotalMs = 0
    var spotMaxMs = 0
    var gapMaxMs = 0
    var stalls = 0
    /// `officialSpots` が書き換わった回数と、束ね直した合計 ms
    var spotsChanged = 0
    var spotsChangedMs = 0

    init(query: String) {
        self.query = query
    }

    /// 1語分を読む。形が違えば nil（溢れた数 `+Ndropped` も nil）
    init?(_ entry: String) {
        let parts = entry.split(separator: " ").map(String.init)
        guard parts.count == 6 || parts.count == 7, parts[2].hasPrefix("b"), parts[3].hasPrefix("h"),
              parts[4].hasPrefix("g"), parts[5].hasPrefix("s") else { return nil }
        query = parts[1]
        bodies = Int(parts[2].dropFirst()) ?? 0
        let hits = parts[3].dropFirst().split(separator: "/").map { Int($0.replacingOccurrences(of: "ms", with: "")) ?? 0 }
        spotHits = hits.count > 0 ? hits[0] : 0
        spotTotalMs = hits.count > 1 ? hits[1] : 0
        spotMaxMs = hits.count > 2 ? hits[2] : 0
        gapMaxMs = Int(parts[4].dropFirst().replacingOccurrences(of: "ms", with: "")) ?? 0
        stalls = Int(parts[5].dropFirst()) ?? 0
        if parts.count == 7, parts[6].hasPrefix("c") {
            let changed = parts[6].dropFirst().split(separator: "/").map { Int($0.replacingOccurrences(of: "ms", with: "")) ?? 0 }
            spotsChanged = changed.first ?? 0
            spotsChangedMs = changed.count > 1 ? changed[1] : 0
        }
    }

    /// `srch=` の全部（起きた順）
    static func all(_ reading: PerfProbeReading) -> [SearchWindowReading] {
        reading.section("srch").split(separator: ";").compactMap { SearchWindowReading(String($0)) }
    }
}

/// 1回ごとの記録を、測った回の順に渡す置き場（`SearchProbeMetric` が取り出す）
final class SearchProbeBox: @unchecked Sendable {
    let prefixes: [String]
    private let lock = NSLock()
    private var rounds: [[SearchWindowReading]] = []

    init(prefixes: [String]) {
        self.prefixes = prefixes
    }

    func push(_ rows: [SearchWindowReading]) {
        lock.lock()
        rounds.append(rows)
        lock.unlock()
    }

    /// 先に入れた回から取り出す。無ければ 0 の並び（形をそろえる）
    func pop() -> [SearchWindowReading] {
        lock.lock()
        defer { lock.unlock() }
        guard !rounds.isEmpty else { return prefixes.map { SearchWindowReading(query: $0) } }
        return rounds.removeFirst()
    }
}

/// 探すの1字ごとの数を XCTest の `measured [...]` の行に出す（`Tools/perf-collect.py` が拾う）。
/// 中身は試験の本体が `SearchProbeBox` に入れた値（アプリの `perf.probe` から読んだもの）
final class SearchProbeMetric: NSObject, XCTMetric, @unchecked Sendable {
    let box: SearchProbeBox

    init(box: SearchProbeBox) {
        self.box = box
    }

    func copy(with zone: NSZone? = nil) -> Any {
        SearchProbeMetric(box: box)
    }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp,
                            to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        var out: [XCTPerformanceMeasurement] = []
        for (i, w) in box.pop().enumerated() {
            let id = "com.journeyphoto.search.c\(i + 1)"
            out.append(XCTPerformanceMeasurement(identifier: "\(id).body", displayName: "Search \(w.query) body",
                                                 doubleValue: Double(w.bodies), unitSymbol: "count"))
            out.append(XCTPerformanceMeasurement(identifier: "\(id).spotHits", displayName: "Search \(w.query) spotHits",
                                                 doubleValue: Double(w.spotHits), unitSymbol: "count"))
            out.append(XCTPerformanceMeasurement(identifier: "\(id).spotTotal", displayName: "Search \(w.query) spotHits total",
                                                 doubleValue: Double(w.spotTotalMs), unitSymbol: "ms"))
            out.append(XCTPerformanceMeasurement(identifier: "\(id).spotMax", displayName: "Search \(w.query) spotHits max",
                                                 doubleValue: Double(w.spotMaxMs), unitSymbol: "ms"))
            out.append(XCTPerformanceMeasurement(identifier: "\(id).gapMax", displayName: "Search \(w.query) frame gap max",
                                                 doubleValue: Double(w.gapMaxMs), unitSymbol: "ms"))
        }
        return out
    }
}
