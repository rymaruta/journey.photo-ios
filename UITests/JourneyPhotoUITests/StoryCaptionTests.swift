import XCTest

/// **ストーリー作成の「ひとこと」の入口**（#404・2026-10-29）。
///
/// owner「ひとことを書くに何も入力しなかった場合も残っちゃうの嫌だな」——空の欄（灰の帯＋明朝の案内）が
/// 写真の真ん中に出続けていた。いまは空で打っていない欄は描かず、**写真の何も無い所を押すと打ち始める**。
/// ここでは実際に、(1) 空の欄が見えない (2) 写真を押すとキーボードが出て欄が見える
/// (3)「完了」で空のまま閉じると欄がまた見えなくなる、を確かめる。
///
/// 見本の写真と曲（`-JPPreviewStorySong`・通信しない）で開く。**作る画面まで行けなかった回は落とさない**
/// （巡回の `testCapturesStorySongStickerStyles` と同じ抜け方）。開けた後の (1)〜(3) が見張り
final class StoryCaptionTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// 巡回（`ScreenshotTests`）と同じ、鍵を持たないログインの利用者
    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTappingThePhotoStartsTheCaptionAndEmptyCaptionHidesAgain() {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewStorySong", "YES", "-story.songSticker.style", "glass"]
        // 入口の案内は出さない（押す所に被らないように）
        app.launchArguments += ["-story.captionHintShown", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 30) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        let toStory = app.buttons["post.choice.story"].firstMatch
        guard toStory.waitForExistence(timeout: 5), toStory.isHittable else { return }
        toStory.tap()
        // 写真と曲の札が出たら、作る画面が描けている
        let sticker = app.descendants(matching: .any)["story.songSticker"].firstMatch
        guard sticker.waitForExistence(timeout: 20) else {
            shoot(app, "ひとこと（作る画面が開けない）")
            return
        }
        Thread.sleep(forTimeInterval: 1)

        // (1) 空で打っていない欄は見えない
        let caption = app.descendants(matching: .any)["story.caption"].firstMatch
        shoot(app, "ひとこと1（空の欄が見えない）")
        XCTAssertFalse(caption.exists && caption.isHittable, "空のひとことの欄が写真の上に残っている")

        // (2) 写真の何も無い所（上の ✕・「…」より下、真ん中の曲の札より上）を押すと打ち始める
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "写真を押してもキーボードが出ない")
        XCTAssertTrue(caption.waitForExistence(timeout: 3), "打ち始めたのにひとことの欄が出ない")
        shoot(app, "ひとこと2（写真を押して打ち始めた）")

        // (3) 何も書かずに「完了」→ 欄がまた見えなくなる
        let done = app.buttons["完了"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3), "打っている間の「完了」が無い")
        done.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.firstMatch)
        expectation(for: gone, evaluatedWith: caption)
        waitForExpectations(timeout: 5)
        shoot(app, "ひとこと3（空のまま閉じた）")
    }
}
