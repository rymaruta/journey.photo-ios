import XCTest

/// **ストーリーで場所・文字などを入力した後、札を動かせるか**を数で測る（札 #499・2026-11-08）。
///
/// owner の報告（TestFlight 1.1.72 の実機）:「ストーリーで場所などを入力した後に、自由に場所（位置）を移動できない」。
/// 原因を推定で直さず（CLAUDE.md）、見えない要素 `story.probe`（`-JPPreviewStoryProbe YES`・`StoryComposeProbe`）の値と、
/// 札の画面上の枠（XCUI の `frame`）を、**動かす前と後に**読んで 1 行ずつ残す（`STORYMOVE …`）。
///
/// 測る相手（どれも 1 回の起動で 6 回ずつ、上下に交互に指で運ぶ）:
///  - `chip`: 右の「場所」の道具で入れた撮影地の札（写真の真ん中の左の、丸い札・`captionBlock` の中）
///  - `song`: 見本の曲の札（動かせる札の基準。ここが動かなければ操作の仕組みごと壊れている）
///  - `text` / `place`: 打ち終えた文字の札・スタンプのトレイから置いた「撮影地」の札（動かせる札）
///
/// 見本の写真と曲（`-JPPreviewStorySong`・通信しない）で開く。**作る画面まで行けなかった回は落とさない**
/// （`StoryCaptionTests` と同じ抜け方）。動かなかった相手があれば、全部測り終えてから 1 回だけ落とす。
final class StoryPlaceMoveTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    /// 動いたとみなす移動量（pt）。指で 90pt 運ぶ
    private static let movedThreshold: CGFloat = 20
    private static let trials = 6

    private var misses: [String] = []

    // MARK: - 道具

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func log(_ line: String) {
        print("STORYMOVE \(line)")
        XCTContext.runActivity(named: "STORYMOVE \(line)") { _ in }
        let a = XCTAttachment(string: line)
        a.name = "STORYMOVE"
        a.lifetime = .keepAlways
        add(a)
    }

    private func probe(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)["story.probe"].firstMatch
        guard element.exists else { return "story.probe が読めない" }
        return (element.value as? String) ?? "story.probe の値が空"
    }

    private func launch() -> XCUIApplication? {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewStorySong", "YES", "-story.songSticker.style", "glass"]
        app.launchArguments += ["-JPPreviewStoryProbe", "YES"]
        // 入口の案内・「指で動かす」の案内は出さない（押す所に被らないように）
        app.launchArguments += ["-story.captionHintShown", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return nil }
        tabBar.buttons.element(boundBy: 2).tap()
        let toStory = app.buttons["post.choice.story"].firstMatch
        guard toStory.waitForExistence(timeout: 5), toStory.isHittable else { return nil }
        toStory.tap()
        guard app.descendants(matching: .any)["story.songSticker"].firstMatch.waitForExistence(timeout: 20) else {
            shoot(app, "作る画面が開けない")
            return nil
        }
        Thread.sleep(forTimeInterval: 1)
        return app
    }

    private func tool(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// 打つ画面に文字を入れて「完了」。入れられなければ false
    private func typeAndDone(_ app: XCUIApplication, _ text: String) -> Bool {
        guard app.keyboards.firstMatch.waitForExistence(timeout: 8) else { return false }
        app.typeText(text)
        let done = app.buttons["story.typing.done"].firstMatch
        guard done.waitForExistence(timeout: 3) else { return false }
        done.tap()
        let gone = NSPredicate(format: "exists == false")
        let keyboardGone = expectation(for: gone, evaluatedWith: app.keyboards.firstMatch)
        wait(for: [keyboardGone], timeout: 6)
        Thread.sleep(forTimeInterval: 0.6)
        return true
    }

    private func element(_ app: XCUIApplication, label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// 相手を `trials` 回、上下に交互に運び、動いたかを 1 行ずつ残す
    private func dragTrials(_ app: XCUIApplication, name: String, find: () -> XCUIElement) {
        var moved = 0
        for i in 0..<Self.trials {
            let target = find()
            guard target.exists else {
                log("\(name) #\(i) 要素が見つからない probe=\(probe(app))")
                continue
            }
            let before = target.frame
            let dy: CGFloat = (i % 2 == 0) ? -90 : 90
            let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
            Thread.sleep(forTimeInterval: 0.7)
            let after = find().frame
            let delta = abs(after.midY - before.midY) + abs(after.midX - before.midX)
            let didMove = delta > Self.movedThreshold
            if didMove { moved += 1 }
            log("\(name) #\(i) dragDy=\(Int(dy)) before=\(Int(before.midX)),\(Int(before.midY)) after=\(Int(after.midX)),\(Int(after.midY)) moved=\(didMove) probe=\(probe(app))")
        }
        log("\(name) 動いた回=\(moved)/\(Self.trials)")
        if moved < Self.trials { misses.append("\(name) \(moved)/\(Self.trials)") }
    }

    private func finish(_ app: XCUIApplication) {
        shoot(app, "終わり")
        XCTAssertTrue(misses.isEmpty, "動かせなかった相手: \(misses.joined(separator: ", "))")
    }

    // MARK: - 試験

    /// 右の「場所」の道具で撮影地を入れた後、その札と、曲の札を動かす
    func testMovesAfterPlaceTool() {
        guard let app = launch() else { return }
        log("開いた probe=\(probe(app))")
        dragTrials(app, name: "song(場所の前)") { app.descendants(matching: .any)["story.songSticker"].firstMatch }

        let placeTool = tool(app, "場所")
        guard placeTool.waitForExistence(timeout: 5) else { log("場所の道具が無い"); return }
        placeTool.tap()
        let field = app.alerts.firstMatch.textFields.firstMatch
        guard field.waitForExistence(timeout: 5) else { log("撮影地の入力欄が出ない"); shoot(app, "入力欄なし"); return }
        field.tap()
        field.typeText("Capetest")
        app.alerts.firstMatch.buttons["決める"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        log("場所を入れた probe=\(probe(app))")
        shoot(app, "場所を入れた")

        dragTrials(app, name: "chip(場所の道具)") { self.element(app, label: "Capetest") }
        dragTrials(app, name: "song(場所の後)") { app.descendants(matching: .any)["story.songSticker"].firstMatch }
        finish(app)
    }

    /// 文字・撮影地の札を打ち終えた後、その札と曲の札を動かす
    func testMovesAfterTypedOverlays() {
        guard let app = launch() else { return }
        log("開いた probe=\(probe(app))")

        let textTool = tool(app, "文字")
        guard textTool.waitForExistence(timeout: 5) else { log("文字の道具が無い"); return }
        textTool.tap()
        if typeAndDone(app, "Texttest") {
            log("文字を打ち終えた probe=\(probe(app))")
            dragTrials(app, name: "text(打った後)") { self.element(app, label: "Texttest") }
        } else {
            log("文字を打てなかった"); shoot(app, "文字を打てない")
        }

        let stickerTool = tool(app, "スタンプ")
        if stickerTool.waitForExistence(timeout: 5) {
            stickerTool.tap()
            let place = app.buttons["story.add.place"].firstMatch
            if place.waitForExistence(timeout: 5) {
                place.tap()
                if typeAndDone(app, "Pintest") {
                    log("撮影地の札を打ち終えた probe=\(probe(app))")
                    dragTrials(app, name: "place札(打った後)") { self.element(app, label: "Pintest") }
                } else {
                    log("撮影地の札を打てなかった"); shoot(app, "撮影地の札を打てない")
                }
            } else {
                log("トレイに撮影地が無い"); shoot(app, "トレイ")
            }
        }
        dragTrials(app, name: "song(打った後)") { app.descendants(matching: .any)["story.songSticker"].firstMatch }
        finish(app)
    }
}
