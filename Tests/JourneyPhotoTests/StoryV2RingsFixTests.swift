import XCTest
@testable import JourneyPhoto

/// v2 の板（StoryRings・Main・StoryInsights・StoryReplies・HighlightPlayer）に合わせた直し（2026-10-16）。
///
/// 画面の部品は Linux では描けないので、`StoryV2DesignTests` と同じく**値は数で**、**部品の作りは
/// 元のファイルを読んで**見張る。番号は直しの一覧（18・19・23〜25・27〜29・36〜42）。
final class StoryV2RingsFixTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `start` から `end` の手前までを切り出す（ほかの関数の同じ字に当たらないように）
    private func slice(_ text: String, from start: String, to end: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let s = text.range(of: start) else {
            XCTFail("「\(start)」が無い", file: file, line: line)
            return ""
        }
        guard let e = text.range(of: end, range: s.upperBound..<text.endIndex) else {
            XCTFail("「\(start)」の後に「\(end)」が無い", file: file, line: line)
            return ""
        }
        return String(text[s.lowerBound..<e.lowerBound])
    }

    /// `parts` がこの順に `text` に現れる
    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が無いか、順が違う", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    // MARK: - 18 戻すばねの間も時計を止める

    func testReelHoldsTheClockWhileSpringingBack() throws {
        let reel = try source("Features/Stories/StoryReelView.swift")
        XCTAssertTrue(reel.contains("holds: finger.axis != nil || turning || settling"),
                      "戻すばねの間に時計が進む")
        // 閉じずに戻る縮み・回らずに戻る横のどちらも `settle` を通す
        XCTAssertTrue(reel.contains("settle { settleY = 0 }"), "下へ払って戻すばねが止めていない")
        XCTAssertFalse(reel.contains("withAnimation(settleAnimation) { settleY = 0 }"))
        XCTAssertFalse(reel.contains("withAnimation(settleAnimation) { settleX = 0 }"))
        let settle = slice(reel, from: "private func settle(", to: "private func face<")
        assertInOrder(["settleRun += 1", "settling = true", "withAnimation(settleAnimation, change)",
                       "Task.sleep(for: .milliseconds(Int(Self.settleDuration * 1000)))",
                       "if run == settleRun { settling = false }"], in: settle, "戻すばね")
        // ばね（response 0.3）より先に解かない
        XCTAssertGreaterThanOrEqual(StoryReelView.settleDuration, 0.3)
    }

    // MARK: - 19 隣の面を本物の閲覧画面と同じ形に

    func testReelFaceMatchesTheViewerFrame() throws {
        XCTAssertEqual(StoryViewerMetrics.photoRadius, JPRadius.xl)
        XCTAssertEqual(StoryViewerMetrics.footerHeight, 60)
        let reel = try source("Features/Stories/StoryReelView.swift")
        let face = slice(reel, from: "private struct StoryReelFace", to: ".accessibilityHidden(true)")
        assertInOrder(["VStack(spacing: 0)", "StoryPoster(story: story)",
                       "UnevenRoundedRectangle(bottomLeadingRadius: StoryViewerMetrics.photoRadius",
                       "bottomTrailingRadius: StoryViewerMetrics.photoRadius",
                       ".ignoresSafeArea(edges: .top)",
                       "Color.black.frame(height: StoryViewerMetrics.footerHeight)"], in: face, "隣の面")
        // 閲覧画面も同じ値（片方だけ変えると、回りきった瞬間に跳ねる）
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("footerHeight: CGFloat = StoryViewerMetrics.footerHeight"))
        // ハイライトも同じ角丸（2026-10-16・板 HighlightPlayer）。隣の面と同じ値を読む
        XCTAssertTrue(viewer.contains("UnevenRoundedRectangle(bottomLeadingRadius: StoryViewerMetrics.photoRadius"),
                      "閲覧画面の写真の角が StoryViewerMetrics.photoRadius を読んでいない（隣の面と跳ねる）")
    }

    // MARK: - 23・24 反応の画面の印と読み上げ

    func testInsightsRowMarksMatchTheViewer() throws {
        XCTAssertEqual(StoryInsightsView.replySymbol, "message")
        XCTAssertEqual(StoryInsightsView.likedLabel, L("いいねしました", "Liked"))
        XCTAssertEqual(StoryInsightsView.repliedLabel, L("返信しました", "Replied"))
        let insights = try source("Features/Stories/StoryInsightsView.swift")
        XCTAssertFalse(insights.contains("bubble.left"), "角の吹き出しが残っている")
        XCTAssertTrue(insights.contains("Image(systemName: Self.replySymbol)"))
        XCTAssertTrue(insights.contains(".accessibilityLabel(Self.likedLabel)"))
        XCTAssertTrue(insights.contains(".accessibilityLabel(Self.repliedLabel)"))
        // 閲覧画面の自分の足元の返信の丸と同じ記号
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("ownCircle(symbol: \"\(StoryInsightsView.replySymbol)\")"))
    }

    // MARK: - 25 「閉じる」は見出しの行の右端

    func testInsightsCloseSitsInTheHeaderRow() throws {
        let insights = try source("Features/Stories/StoryInsightsView.swift")
        let header = slice(insights, from: "private var header: some View", to: "private var postedLine")
        assertInOrder(["HStack(alignment: .top", "StoryPoster(story: story)", "ストーリーの反応",
                       "Spacer(minLength: 0)", "SheetCloseButton()",
                       ".frame(minHeight: WebTheme.minTapTarget)"], in: header, "見出しの行")
        // 上のバーは隠す（呼び出し側のバーの「閉じる」と2つ出さない）
        let body = slice(insights, from: "var body: some View", to: "private var header: some View")
        XCTAssertTrue(body.contains(".toolbar(.hidden, for: .navigationBar)"), "上のバーに2つ目の「閉じる」が出る")
    }

    // MARK: - 27・28 返信の一覧のシート

    func testRepliesSheetStopsAtTheBoardTop() throws {
        XCTAssertEqual(StoryRepliesSheet.boardTop, 160)
        XCTAssertEqual(Double(StoryRepliesSheet.detentFraction), 1 - 160.0 / 844.0, accuracy: 0.0001)
        let sheet = try source("Features/Stories/StoryRepliesSheet.swift")
        XCTAssertTrue(sheet.contains(".presentationDetents([.fraction(Self.detentFraction)])"))
    }

    func testRepliesLockNoteSitsAtTheSheetBottom() throws {
        let sheet = try source("Features/Stories/StoryRepliesSheet.swift")
        let body = slice(sheet, from: "var body: some View", to: "private var heading")
        // 一覧の中（ForEach の後）に続けて置かない。シートの下端に留める
        let list = slice(body, from: "ScrollView {", to: ".refreshable")
        XCTAssertFalse(list.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "footnote" },
                       "錠の注記が一覧の終わりに続いている")
        assertInOrder([".refreshable", ".safeAreaInset(edge: .bottom", "footnote"], in: body, "錠の注記")
    }

    // MARK: - 29・36 ハイライトの再生

    func testHighlightHidesTheTabBar() throws {
        let player = try source("Features/Profile/HighlightPlayerView.swift")
        let body = slice(player, from: "var body: some View", to: "static func showsNavigationBar")
        XCTAssertTrue(body.contains(".toolbar(.hidden, for: .tabBar)"), "再生中に下のタブバーが残る")
    }

    func testHighlightBarDoesNotFlashWhileLoading() throws {
        // 読み込み中・中身があるときは出さない。札（空・失敗・もう無い）のときだけ出す
        XCTAssertFalse(HighlightPlayerView.showsNavigationBar(itemCount: nil, failed: false, gone: false),
                       "読み込み中にバーと題が出て、中身が出た瞬間に消える")
        XCTAssertFalse(HighlightPlayerView.showsNavigationBar(itemCount: 3, failed: false, gone: false))
        XCTAssertFalse(HighlightPlayerView.showsNavigationBar(itemCount: 3, failed: true, gone: false),
                       "中身を出したまま読み直しに失敗した回にバーが重なる")
        XCTAssertTrue(HighlightPlayerView.showsNavigationBar(itemCount: 0, failed: false, gone: false))
        XCTAssertTrue(HighlightPlayerView.showsNavigationBar(itemCount: nil, failed: true, gone: false))
        XCTAssertTrue(HighlightPlayerView.showsNavigationBar(itemCount: nil, failed: false, gone: true))
        let player = try source("Features/Profile/HighlightPlayerView.swift")
        let body = slice(player, from: "var body: some View", to: "static func showsNavigationBar")
        XCTAssertTrue(body.contains(".toolbar(Self.showsNavigationBar(itemCount:"))
        // 読み込み中も出口を置く（バーを隠すので戻るが無い）
        let loading = slice(body, from: "ProgressView()", to: ".webScreen()")
        XCTAssertTrue(loading.contains("loadingClose"), "読み込み中に出口が無い")
    }

    // MARK: - 37 自分のハイライトの「…」

    func testOwnHighlightAlwaysHasTheTopMenu() {
        XCTAssertTrue(StoryPlayback.showsTopMenu(isMine: true, inHighlight: true))
        // 「…」を開けば止められる（音が無くても中身が空にならない）
        let items = StoryPlayback.menuItems(isMine: true, isVideo: false, hasCaption: true, hasOwner: true,
                                            inHighlight: true)
        XCTAssertEqual(items, [.pause, .hideCaption])
        // ハイライト以外の自分の投稿は足元の「…」と2つ並べない（今まで通り）
        XCTAssertFalse(StoryPlayback.showsTopMenu(isMine: true, inHighlight: false))
    }

    // MARK: - 38・42 自分の輪の「＋」

    func testOwnRingHasNoPlusWhenThereIsAStory() throws {
        let row = try source("Features/Stories/StoriesRow.swift")
        let mine = slice(row, from: "private func mineRing(", to: "private var myFace")
        let hasStory = slice(mine, from: "if let mine {", to: "} else {")
        XCTAssertTrue(hasStory.contains("open(mine)"))
        XCTAssertFalse(hasStory.contains("plusBadge"), "ストーリーがあるのに「＋」が出る")
        XCTAssertFalse(hasStory.contains("showComposer"), "自分の輪に投稿の的が残っている")
        // 無いときは今まで通り「＋」で投稿の入口
        let noStory = slice(row, from: "private func mineRing(", to: "private var myFace")
            .components(separatedBy: "} else {").dropFirst().joined()
        assertInOrder(["showComposer = true", "StoryRing(count: 1, unseen: false) { myFace }", "plusBadge",
                       ".frame(width: StoryRingMetrics.size)", "L(\"ストーリーを投稿\""], in: noStory, "自分の入口")
    }

    /// 「＋」の見た目は 22 のまま、押せるのは輪と名前の全体（44pt 以上）
    func testOwnPlusTapTargetIsAtLeast44() throws {
        XCTAssertEqual(StoryRingMetrics.plusSize, 22)
        XCTAssertGreaterThanOrEqual(StoryRingMetrics.size, WebTheme.minTapTarget)
        let row = try source("Features/Stories/StoriesRow.swift")
        XCTAssertFalse(row.contains(".frame(width: 30, height: 30)"), "「＋」だけの 30pt の的が残っている")
    }

    // MARK: - 39 輪の切れ目

    func testRingSegmentGapIsFourPointsWithButtCaps() throws {
        let ring = try source("Features/Stories/StoryRing.swift")
        XCTAssertTrue(ring.contains("lineCap: .butt"), "線の端を丸めると切れ目が潰れる")
        let body = slice(ring, from: "var body: some View", to: "static func style(")
        XCTAssertFalse(body.contains("lineCap: .round"))
        XCTAssertEqual(StoryRingMetrics.strokeCircumference, 2 * Double.pi * 31, accuracy: 0.0001)
        let segments = StoryPlayback.ringSegments(count: 3)
        let gapPoints = (segments[1].start - segments[0].end) * StoryRingMetrics.strokeCircumference
        XCTAssertEqual(gapPoints, Double(StoryRingMetrics.segmentGap), accuracy: 0.05, "板の切れ目は約 4pt")
    }

    // MARK: - 40 人の輪の読み上げ

    func testRingAccessibilityLabel() throws {
        XCTAssertEqual(StoriesRow.ringLabel(name: "haru_t", count: 3, unseen: true),
                       L("haru_t のストーリー 3本（まだ見ていない）", "haru_t's story, 3 items (not seen yet)"))
        XCTAssertEqual(StoriesRow.ringLabel(name: "nagi", count: 1, unseen: false),
                       L("nagi のストーリー 1本（見た）", "nagi's story, 1 item (seen)"))
        let row = try source("Features/Stories/StoriesRow.swift")
        let others = slice(row, from: "ForEach(ordered.others)", to: ".padding(.horizontal, 16)")
        assertInOrder(["ringItem(story: story", ".accessibilityLabel(Self.ringLabel(name: story.authorName",
                       "unseen: unseen))"], in: others, "人の輪の読み上げ")
    }

    // MARK: - 41 読み込み中は輪の列を出さない

    func testRingsHideWhileFirstLoading() throws {
        XCTAssertFalse(StoriesRow.showsRings(settled: false, hasRings: false, uploading: false),
                       "読み込み中に輪の列が出る")
        XCTAssertTrue(StoriesRow.showsRings(settled: false, hasRings: true, uploading: false),
                      "持っている輪を読み直しのたびに消す（ちらつく）")
        XCTAssertTrue(StoriesRow.showsRings(settled: false, hasRings: false, uploading: true))
        XCTAssertTrue(StoriesRow.showsRings(settled: true, hasRings: false, uploading: false))
        let row = try source("Features/Stories/StoriesRow.swift")
        XCTAssertTrue(row.contains("Self.showsRings(settled: model.settled, hasRings: !model.stories.isEmpty, uploading: uploads.isBusy)"))
        // 取れなかった回も「終わった」にする（圏外で投稿の入口が出なくならない）
        let load = slice(row, from: "func load(environment:", to: "let fetched = try? await")
        XCTAssertTrue(load.contains("defer { settled = true }"))
    }
}
