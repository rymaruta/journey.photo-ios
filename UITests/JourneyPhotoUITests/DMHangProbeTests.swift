import XCTest

/// **DM の会話が、下へ払った直後から固まる件の事実取り**（2026-11-12・統合の枝 1.1.84 の run 1164・1171・次の版 1.1.85 で直す）。
///
/// `ScreenshotTests.testCapturesDirectMessages` の「送信の取り消し」の段（86m5a）と同じ道をたどり、
/// 会話「夕焼けの人」を下へ払う。そのとき**払い1回にかかった秒**を測る（固まると、XCTest がアプリの手すきを
/// 60 秒待って諦めるので 60 秒を超える。固まらない回は数秒）。
///
/// 疑う箇所を1つずつ外す・固定する印（アプリの `DMHangProbe`・`-JPDM<名前> YES`）を付けた版を、印の無い版と
/// **1回の Mac の回に並べて**流す。**どの印で固まらなくなるか**を、1行（`DMHANG …`）でログと活動の名前に残す。
/// 固まった版は試験を赤にする（印の無い版は赤になるのが今の事実）。
///
/// **名指しした回だけ流れる**（`Tools/pick-ui-tests.py` の `ONLY_WHEN_NAMED`・`inputs[screens]=DMHangProbeTests`）。
/// 原因が決まって直したら、この試験と印は外す。
final class DMHangProbeTests: XCTestCase {

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    /// 払い1回がこれより長ければ「固まった」（固まらない回は 1〜5 秒・固まった回は 60 秒あまり）
    private static let hungSeconds: TimeInterval = 20

    override func setUp() {
        continueAfterFailure = true
        executionTimeAllowance = 300
    }

    // 印の無い版（固まるのが今の事実）。最初と最後に1回ずつ（同じ回の中で再現するかを見る）
    func test00Baseline() { probe([]) }
    func test99BaselineAgain() { probe([]) }
    /// 1回目の訪問（URL を送って断られる 86m5）を飛ばし、いきなり取り消しの段の道で払う
    func test01BaselineNoFirstVisit() { probe([], firstVisit: false) }

    // sns-more が会話に足した物
    func test10NoSpotMessages() { probe(["NoSpotMessages"]) }
    func test11NoSpotCard() { probe(["NoSpotCard"]) }
    func test12SpotCardFixed() { probe(["SpotCardFixed"]) }
    func test13SpotCardStatic() { probe(["SpotCardStatic"]) }

    // 会話の並びの仕組み
    func test20NoWidthRead() { probe(["NoWidthRead"]) }
    func test21NoTripBand() { probe(["NoTripBand"]) }
    func test22PlainText() { probe(["PlainText"]) }
    func test23NoInnerIds() { probe(["NoInnerIds"]) }
    func test24NoAutoScroll() { probe(["NoAutoScroll"]) }
    func test25EagerStack() { probe(["EagerStack"]) }

    // MARK: -

    private func probe(_ flags: [String], firstVisit: Bool = true) {
        let app = XCUIApplication()
        let label = (flags.isEmpty ? "なし" : flags.joined(separator: "+")) + (firstVisit ? "" : "（1回目の訪問なし）")
        let samplePath = ScreenshotTests.mainSamplePath("dmhang-\(flags.joined(separator: "-"))\(firstVisit ? "" : "-nofirst")")
        // `testCapturesDirectMessages` と同じ起動の引数（主スレッドの見張りも同じく付ける）
        app.launchArguments += ["-JPPreviewPerfProbe", "YES", "-JPMainSampleFile", samplePath]
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewDM", "YES"]
        for flag in flags { app.launchArguments += ["-JPDM\(flag)", "YES"] }
        app.launch()

        func note(_ line: String) {
            let full = "DMHANG flags=\(label) \(line)"
            print(full)
            XCTContext.runActivity(named: full) { _ in }
        }

        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else {
            note("result=未到達 step=tabBar"); XCTFail("タブが出ない"); return
        }
        let header = app.buttons["header.messages"].firstMatch
        guard header.waitForExistence(timeout: 20) else {
            note("result=未到達 step=header"); XCTFail("見出しの吹き出しが出ない"); return
        }
        Thread.sleep(forTimeInterval: 2)
        header.tap()
        guard app.descendants(matching: .any)["dm.inbox"].firstMatch.waitForExistence(timeout: 15) else {
            note("result=未到達 step=inbox"); XCTFail("受信箱が出ない"); return
        }
        Thread.sleep(forTimeInterval: 2)

        if firstVisit {
            // 86m2・86m3 と同じ: リクエスト → リクエストの会話 → 戻る
            let entry = app.buttons["dm.requests.entry"].firstMatch
            if entry.waitForExistence(timeout: 5), entry.isHittable {
                entry.tap()
                if app.descendants(matching: .any)["dm.requests"].firstMatch.waitForExistence(timeout: 10) {
                    Thread.sleep(forTimeInterval: 2)
                    let name = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "桜の便り")).firstMatch
                    if name.waitForExistence(timeout: 5), name.isHittable {
                        name.tap()
                        _ = app.descendants(matching: .any)["dm.requestBand"].firstMatch.waitForExistence(timeout: 10)
                        Thread.sleep(forTimeInterval: 2)
                        app.navigationBars.buttons.element(boundBy: 0).tap()
                        Thread.sleep(forTimeInterval: 1)
                    }
                }
                app.navigationBars.buttons.element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 1)
            }
            // 86m4・86m5 と同じ: 会話を開き、URL を送って断られる → 戻る
            if openThread(app, named: "夕焼けの人") {
                let field = app.descendants(matching: .any)["dm.field"].firstMatch
                if field.waitForExistence(timeout: 5), field.isHittable {
                    field.tap()
                    field.typeText("ここで撮りました https://example.com/spot")
                    let send = app.buttons["dm.send"].firstMatch
                    if send.isHittable { send.tap() }
                    _ = app.descendants(matching: .any)["dm.fieldError"].firstMatch.waitForExistence(timeout: 10)
                    Thread.sleep(forTimeInterval: 1)
                }
                app.navigationBars.buttons.element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }

        // 86m5a と同じ: 会話を開き、自分の文の吹き出しが押せる所まで下へ払う
        guard openThread(app, named: "夕焼けの人") else {
            note("result=未到達 step=thread"); XCTFail("会話が開けない"); return
        }
        let probeValue = app.descendants(matching: .any)["dm.probe"].firstMatch.value as? String ?? "読めない"
        note("probe=\(probeValue)")
        let mineText = "ありがとうございます。伊豆の海沿いです。"
        let bubble = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", mineText)).firstMatch
        let thread = app.descendants(matching: .any)["dm.conversation"].firstMatch
        var durations: [String] = []
        var hung = false
        var swipes = 0
        while bubble.waitForExistence(timeout: 5), !bubble.isHittable, swipes < 4 {
            let start = Date()
            thread.swipeDown()
            let seconds = Date().timeIntervalSince(start)
            swipes += 1
            durations.append(String(format: "%.1f", seconds))
            if seconds > Self.hungSeconds {
                hung = true
                ScreenshotTests.logMainSamples(samplePath, label: "DMHANG \(label) 払い \(swipes) 回目")
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        // 固まった回は画面の木を読まない（読むと長く止まる）
        let hittable = hung ? false : (bubble.exists && bubble.isHittable)
        note("result=\(hung ? "固まった" : "固まらない") swipes=\(swipes) seconds=[\(durations.joined(separator: ","))] hittable=\(hittable)")
        XCTAssertFalse(hung, "DMHANG flags=\(label): 払い1回が \(Self.hungSeconds) 秒を超えた（固まった）")
    }

    /// 受信箱の行を名前で開き、会話が出るまで待つ（`ScreenshotTests.openThread` と同じ）
    private func openThread(_ app: XCUIApplication, named name: String) -> Bool {
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'dm.thread' AND label CONTAINS %@", name)).firstMatch
        guard row.waitForExistence(timeout: 10) else { return false }
        if !row.isHittable { app.swipeUp() }
        guard row.isHittable else { return false }
        row.tap()
        guard app.descendants(matching: .any)["dm.conversation"].firstMatch.waitForExistence(timeout: 10) else { return false }
        Thread.sleep(forTimeInterval: 2)
        return true
    }
}
