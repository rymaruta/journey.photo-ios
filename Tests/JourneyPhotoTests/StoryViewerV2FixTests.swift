import XCTest
@testable import JourneyPhoto

/// ストーリーの**見る画面**を v2 の板（StoryViewer・Menu・Paused・Reply・DeleteConfirm・HighlightPlayer・
/// 2026-10-16 の直し）どおりにした分の見張り。
///
/// 画面は Linux で描けないので、`StoryV2DesignTests` と同じく**値は数で**、**部品の作りは元のファイルを読んで**
/// 見る（呼び出しの順・使っている値まで）。決まりのうち画面を持たないもの（読み上げの文・先読みの行き先・
/// 読めなかった写真の扱い・反応の画面へ渡す一覧）は関数をそのまま試す。
final class StoryViewerV2FixTests: XCTestCase {

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

    private func viewer() throws -> String { try source("Features/Stories/StoryViewerView.swift") }

    /// `name` から次の宣言までを切り出す（ほかの関数の同じ字に当たらないように）
    private func member(_ name: String, in text: String,
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = text.range(of: name) else {
            XCTFail("\(name) が無い", file: file, line: line)
            return ""
        }
        let rest = text[start.upperBound...]
        let ends = ["\n    private func ", "\n    private var ", "\n    func ", "\n    var ",
                    "\n    static ", "\n    @MainActor static ", "\n    private static ", "\n}"]
            .compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
    }

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

    // MARK: - 1. 動画は画面いっぱい

    /// 🔴 動画は層（`AVPlayerLayer`）を**切って埋める**敷き方で出す。`VideoPlayer` は縦横比のまま収めて黒い帯が出た
    func testVideoFillsTheFrame() throws {
        XCTAssertEqual(StoryVideoSurface.gravity, .resizeAspectFill)
        let media = try source("Features/Stories/StoryMedia.swift")
        XCTAssertFalse(media.contains("VideoPlayer(player:"), "縦横比のまま収める VideoPlayer が残っている")
        XCTAssertTrue(media.contains("StoryVideoSurface(player: player)"))
        // 型の中の `func` で切れないよう、型の宣言から先で順を見る
        let surface = String(media[(media.range(of: "struct StoryVideoSurface: UIViewRepresentable")?.lowerBound ?? media.endIndex)...])
        assertInOrder(["view.isUserInteractionEnabled = false", "view.playerLayer.videoGravity = Self.gravity",
                       "view.playerLayer.player = player"], in: surface, "動画の面")
        XCTAssertTrue(media.contains("override class var layerClass: AnyClass { AVPlayerLayer.self }"))
    }

    // MARK: - 2・3. 「…」と削除の確認

    /// 🔴 暗幕は画面全体（足元・見出しの上まで）。写真の中に敷くのは返信を書いている間だけ
    func testOverlayDimCoversTheWholeScreen() throws {
        let text = try viewer()
        let content = member("private func content(for story: Story)", in: text)
        assertInOrder(["header(for: story)", "if overlayDimOpacity > 0 {", ".opacity(overlayDimOpacity)",
                       ".ignoresSafeArea()", "if showMenu {", "menuSheet(for: story)", "if showDeleteConfirm {"],
                      in: content, "画面全体の暗幕")
        let dim = member("private var overlayDimOpacity: Double", in: text)
        assertInOrder(["StoryViewerMetrics.deleteDim", "StoryViewerMetrics.menuDim"], in: dim, "暗幕の濃さ")
        XCTAssertFalse(dim.contains("replyDim"))
        let photo = member("private func photoArea(for story: Story)", in: text)
        XCTAssertTrue(photo.contains(".opacity(photoDimOpacity)"))
        XCTAssertFalse(photo.contains("overlayDimOpacity"), "「…」の暗幕が写真の中だけに敷かれている")
        XCTAssertEqual(StoryViewerMetrics.menuDim, 0.5)
        XCTAssertEqual(StoryViewerMetrics.deleteDim, 0.6)
    }

    /// 🔴 シート・確認の間は見出し（名前・…・✕）と足元を隠す。進み線は残す
    func testOverlayHidesTheHeader() throws {
        let c = StoryPlayback.chrome(longHeld: false, paused: false, overlayOpen: true)
        XCTAssertTrue(c.hidesChrome)
        XCTAssertFalse(c.showsPill)
        let content = member("private func content(for story: Story)", in: try viewer())
        assertInOrder(["progressBar(for: story)", "header(for: story)", ".opacity(chrome.hidesChrome ? 0 : 1)"],
                      in: content, "見出しの隠し方")
        let chrome = member("private var chrome: StoryPlayback.Chrome", in: try viewer())
        XCTAssertTrue(chrome.contains("overlayOpen: showMenu || showDeleteConfirm"))
    }

    // MARK: - 4. 長押しで止めている間

    /// 🔴 ひとこと・撮影地・曲・上下の暗がりも隠す（板 StoryViewerPaused は進み線・写真・札だけ）
    func testLongHoldHidesCaptionAndShades() throws {
        let photo = member("private func photoArea(for story: Story)", in: try viewer())
        assertInOrder(["StoryViewerMetrics.topShadeHeight", ".opacity(chrome.hidesChrome ? 0 : 1)",
                       "StoryViewerMetrics.bottomShadeHeight", ".opacity(chrome.hidesChrome ? 0 : 1)",
                       "captionBlock(for: story)", ".opacity(chrome.hidesChrome ? 0 : 1)",
                       ".allowsHitTesting(!chrome.hidesChrome)"], in: photo, "止めている間の写真の上")
        let held = StoryPlayback.chrome(longHeld: true, paused: false, overlayOpen: false)
        XCTAssertTrue(held.hidesChrome)
        XCTAssertTrue(held.showsPill)
    }

    // MARK: - 5〜8. 返信

    /// 板 StoryViewerReply の並び: 一言の候補 → 入力欄 → 「返信は〇〇さんにだけ届きます」
    func testReplyOrder() throws {
        let footer = member("private func footer(for story: Story)", in: try viewer())
        assertInOrder(["StoryPlayback.quickReplies.indices", "TextField(L(\"返信する\"",
                       "if replyFocused {", "返信は \\(story.authorName) さんにだけ届きます"],
                      in: footer, "返信の並び")
    }

    /// 送信は上向きの矢印（紙飛行機ではない）
    func testSendIsAnUpArrow() throws {
        let footer = member("private func footer(for story: Story)", in: try viewer())
        assertInOrder(["Image(systemName: \"arrow.up\")", "StoryViewerMetrics.sendSize"], in: footer, "送信の丸")
        XCTAssertFalse(footer.contains("paperplane"))
    }

    /// 一言の候補: 14・白 14% の地・縁なし・高さ 36（当たりは 44）
    func testQuickReplyChips() throws {
        XCTAssertEqual(StoryViewerMetrics.quickReplyHeight, 36)
        XCTAssertEqual(StoryViewerMetrics.quickReplyFill, 0.14)
        let footer = member("private func footer(for story: Story)", in: try viewer())
        assertInOrder([".jpSystemFont(StoryViewerMetrics.smallTextSize)",
                       ".frame(minHeight: StoryViewerMetrics.quickReplyHeight)",
                       ".background(Color.white.opacity(StoryViewerMetrics.quickReplyFill), in: Capsule())",
                       ".frame(minHeight: WebTheme.minTapTarget)"], in: footer, "一言の候補")
        XCTAssertFalse(footer.contains(".jpGlass(in: Capsule(), border: 0.14)"), "候補にガラスの縁が残っている")
    }

    /// ♡ は 26（色は owner の好みの真鍮のまま）
    func testHeartSize() throws {
        XCTAssertEqual(StoryViewerMetrics.heartSize, 26)
        let footer = member("private func footer(for story: Story)", in: try viewer())
        assertInOrder(["Image(systemName: reacted ? \"heart.fill\" : \"heart\")",
                       ".jpSystemFont(StoryViewerMetrics.heartSize", ".foregroundStyle(Self.heartColor)",
                       ".webTappable()"], in: footer, "♡")
    }

    // MARK: - 9. 字

    /// 見出しの名前・シートの先頭の名前・一時停止の札は 14。**文字の大きさの設定に付いてくる**（`@ScaledMetric`）
    func testSmallTextIs14AndScales() throws {
        XCTAssertEqual(StoryViewerMetrics.smallTextSize, 14)
        let text = try viewer()
        let author = member("private func authorLabel(for story: Story)", in: text)
        XCTAssertEqual(author.components(separatedBy: ".jpSystemFont(StoryViewerMetrics.smallTextSize, weight: .semibold)").count - 1,
                       2, "「あなた」と人の名前が 14・600 でない")
        XCTAssertFalse(author.contains(".subheadline.weight(.semibold)"))
        let header = member("private func menuHeader(for story: Story)", in: text)
        assertInOrder(["Text(menuTitle(for: story))", ".jpSystemFont(StoryViewerMetrics.smallTextSize, weight: .semibold)"],
                      in: header, "シートの先頭の名前")
        let pill = member("private var pausedPill: some View", in: text)
        assertInOrder(["StoryPlayback.pausedNote(", ".jpSystemFont(StoryViewerMetrics.smallTextSize)"], in: pill, "札の字")
        let font = try source("Core/Design/JPFont.swift")
        let scaled = String(font[(font.range(of: "struct JPScaledSystemFont: ViewModifier")?.lowerBound ?? font.endIndex)...])
        assertInOrder(["@ScaledMetric private var size: CGFloat", "ScaledMetric(wrappedValue: size, relativeTo: style)",
                       "content.font(.system(size: size, weight: weight))"], in: scaled, "伸び縮みする字")
    }

    // MARK: - 10. 一時停止の札の位置

    func testPausedPillSitsAboveCenter() throws {
        XCTAssertEqual(StoryViewerMetrics.pausedPillCenter, 380.0 / 844.0, accuracy: 0.0001)
        XCTAssertLessThan(StoryViewerMetrics.pausedPillCenter, 0.5, "真ん中より上でない")
        let content = member("private func content(for story: Story)", in: try viewer())
        assertInOrder(["if chrome.showsPill {", "GeometryReader { geo in", "pausedPill",
                       "y: geo.size.height * StoryViewerMetrics.pausedPillCenter", ".ignoresSafeArea()"],
                      in: content, "札の位置")
    }

    // MARK: - 11. 「文字を隠す」

    func testHideTextMenuRow() throws {
        let menu = member("private func menuSheet(for story: Story)", in: try viewer())
        assertInOrder(["if items.contains(.hideCaption) {", "captionHidden ? \"textformat\" : \"strikethrough\"",
                       "L(\"文字を隠す\", \"Hide text\")"], in: menu, "「文字を隠す」")
        XCTAssertFalse(menu.contains("テキストを非表示"))
    }

    // MARK: - 12. 上下の暗がり

    func testShadeMetrics() {
        XCTAssertEqual(StoryViewerMetrics.topShadeHeight, 170)
        XCTAssertEqual(StoryViewerMetrics.topShadeOpacity, 0.6)
        XCTAssertEqual(StoryViewerMetrics.bottomShadeHeight, 260)
        XCTAssertEqual(StoryViewerMetrics.bottomShadeOpacity, 0.7)
        XCTAssertEqual(StoryViewerMetrics.highlightBottomShadeHeight, 240)
    }

    // MARK: - 13. 読み上げ

    func testProgressLabel() throws {
        XCTAssertEqual(StoryPlayback.progressLabel(count: 4, index: 1, paused: false, inHighlight: false),
                       L("4本中2本目", "2 of 4"))
        XCTAssertEqual(StoryPlayback.progressLabel(count: 4, index: 1, paused: true, inHighlight: false),
                       L("4本中2本目・止まっています", "2 of 4, paused"))
        XCTAssertEqual(StoryPlayback.progressLabel(count: 5, index: 0, paused: false, inHighlight: true),
                       L("5件中1件目", "1 of 5"))
        let bar = member("private func progressBar(for story: Story)", in: try viewer())
        XCTAssertTrue(bar.contains("paused: spokenAsPaused, inHighlight: highlight != nil"))
        let paused = member("private var spokenAsPaused: Bool", in: try viewer())
        for flag in ["paused", "longHeld", "showMenu", "showDeleteConfirm", "replyFocused"] {
            XCTAssertTrue(paused.contains(flag), "\(flag) の間に「止まっています」と言わない")
        }
    }

    // MARK: - 14. キーボード

    /// 🔴 キーボードが出ても写真の枠を縮めない（写真と黒帯の場所はキーボードを無視・足元の中身だけ上がる）
    func testKeyboardDoesNotShrinkThePhoto() throws {
        let content = member("private func content(for story: Story)", in: try viewer())
        assertInOrder(["ZStack(alignment: .bottom) {", "VStack(spacing: 0) {", "photoArea(for: story)",
                       "Color.clear.frame(height: Self.footerHeight)", ".ignoresSafeArea(.keyboard, edges: .bottom)",
                       "footer(for: story)"], in: content, "写真と足元")
    }

    // MARK: - 15. 読めなかった写真

    /// 🔴 読めなかった写真は時計を回さず、読み直しを出す。使い切ったら進める（永久に固まらない）
    func testFailedPhotoOffersRetryInsteadOfAdvancing() {
        XCTAssertEqual(StoryPlayback.mediaSettled(loaded: true, hasURL: true, retriesUsed: 0),
                       .init(ready: true, offersRetry: false))
        XCTAssertEqual(StoryPlayback.mediaSettled(loaded: false, hasURL: true, retriesUsed: 0),
                       .init(ready: false, offersRetry: true))
        XCTAssertEqual(StoryPlayback.mediaSettled(loaded: false, hasURL: true,
                                                  retriesUsed: RemoteImageRetry.manualLimit - 1),
                       .init(ready: false, offersRetry: true))
        XCTAssertEqual(StoryPlayback.mediaSettled(loaded: false, hasURL: true, retriesUsed: RemoteImageRetry.manualLimit),
                       .init(ready: true, offersRetry: false), "読み直しを使い切っても止まったまま")
        XCTAssertEqual(StoryPlayback.mediaSettled(loaded: false, hasURL: false, retriesUsed: 0),
                       .init(ready: true, offersRetry: false), "URL の無い1本で読み直しを出している")
    }

    /// 読み直しのボタンは送る的より上（`RemoteImage` の中の印は的の下で押せない）。移ったら数え直す
    func testRetryButtonIsAboveTheTapZones() throws {
        let text = try viewer()
        let photo = member("private func photoArea(for story: Story)", in: text)
        assertInOrder(["mediaSettled(loaded, storyId: id, hasURL: hasURL)", ".id(\"\\(story.id)#\\(mediaReloads)\")",
                       "tapZones", "if offersMediaRetry {", "mediaRetryButton"], in: photo, "読み直しの置き場所")
        XCTAssertFalse(photo.contains("onSettled: { _ in mediaReady = true }"), "失敗でも時計を回している")
        let button = member("private var mediaRetryButton: some View", in: text)
        assertInOrder(["mediaRetries += 1", "mediaReloads += 1", ".frame(minHeight: WebTheme.minTapTarget)"],
                      in: button, "読み直しのボタン")
        let go = member("private func go(to target: Int)", in: text)
        XCTAssertTrue(go.contains("mediaRetries = 0"))
        XCTAssertTrue(go.contains("offersMediaRetry = false"))
    }

    // MARK: - 16. 先読み

    func testNextVideo() {
        XCTAssertEqual(StoryPlayback.nextVideo(after: 0, isVideo: [false, false, true, true]), 2)
        XCTAssertEqual(StoryPlayback.nextVideo(after: 2, isVideo: [false, false, true, true]), 3)
        XCTAssertNil(StoryPlayback.nextVideo(after: 3, isVideo: [false, false, true, true]))
        XCTAssertNil(StoryPlayback.nextVideo(after: 0, isVideo: [true, false]), "いまの1本を先読みしている")
        XCTAssertNil(StoryPlayback.nextVideo(after: 5, isVideo: [true]))
    }

    /// 先読みは1つだけ・受け取りは1回・別の URL には渡さない。閉じたら捨てる
    func testPreloaderHoldsOneAndHandsItOver() throws {
        let preloader = StoryVideoPreloader()
        let a = URL(string: "https://example.com/a.mp4")!
        let b = URL(string: "https://example.com/b.mp4")!
        preloader.preload(a)
        XCTAssertNil(preloader.take(b))
        preloader.preload(b)
        XCTAssertNil(preloader.take(a), "前の先読みを捨てていない（2つ持っている）")
        XCTAssertNotNil(preloader.take(b))
        XCTAssertNil(preloader.take(b), "同じ再生器を2回渡している")
        preloader.preload(a)
        preloader.clear()
        XCTAssertNil(preloader.take(a))
        XCTAssertGreaterThan(StoryVideoPreloader.bufferSeconds, 0)
        XCTAssertLessThanOrEqual(StoryVideoPreloader.bufferSeconds, 5, "先に読む長さが長すぎる")

        let media = try source("Features/Stories/StoryMedia.swift")
        XCTAssertTrue(media.contains("StoryVideoPreloader.shared.take(url) ?? AVPlayer(url: url)"))
        let text = try viewer()
        let prefetch = member("private func prefetchNext()", in: text)
        assertInOrder(["StoryPlayback.nextVideo(after: index", "StoryVideoPreloader.shared.preload(url)",
                       "URLSession.shared.dataTask(with: url).resume()"], in: prefetch, "先読み")
        XCTAssertTrue(text.contains("StoryVideoPreloader.shared.clear()"), "閉じても先読みを持ち続けている")
    }

    // MARK: - 17. 反応の画面へ一覧を渡す

    func testInsightsSeed() throws {
        let viewers = [StoryViewer(userId: "u1", displayName: "a", deleted: nil, at: nil)]
        let replies = [StoryReply(rawId: "r1", uid: "u1", name: "a", text: nil, emoji: "❤️", t: nil, deleted: nil)]
        XCTAssertEqual(StoryInsightsView.Seed.from(viewers: viewers, viewersLoaded: true, replies: replies, repliesLoaded: true),
                       StoryInsightsView.Seed(viewers: viewers, replies: replies))
        XCTAssertNil(StoryInsightsView.Seed.from(viewers: viewers, viewersLoaded: nil, replies: replies, repliesLoaded: true))
        XCTAssertNil(StoryInsightsView.Seed.from(viewers: viewers, viewersLoaded: false, replies: replies, repliesLoaded: true))
        XCTAssertNil(StoryInsightsView.Seed.from(viewers: viewers, viewersLoaded: true, replies: [], repliesLoaded: false),
                     "返信を読めていないのに渡している（反応の画面が「いいね 0」と言う）")
        XCTAssertTrue(StoryInsightsView.skipsFirstLoad(seed: StoryInsightsView.Seed(viewers: [], replies: [])))
        XCTAssertFalse(StoryInsightsView.skipsFirstLoad(seed: nil))

        let text = try viewer()
        assertInOrder(["StoryInsightsView(story: story,", "seed: StoryInsightsView.Seed.from(viewers: viewers, viewersLoaded: viewersLoaded",
                       "replies: replies, repliesLoaded: repliesLoaded)"], in: text, "反応の画面を開く")
        let insights = try source("Features/Stories/StoryInsightsView.swift")
        assertInOrder([".task {", "if skipsFirstLoad {", "skipsFirstLoad = false", "return", "await load()"],
                      in: insights, "最初の読み込み")
    }

    // MARK: - 30〜33. ハイライト

    /// ハイライトも写真の下の角丸 24 ＋足元の黒帯（以前は画面いっぱい・角丸なしで足元を写真に重ねていた）
    func testHighlightUsesTheFooterBand() throws {
        XCTAssertEqual(JPRadius.xl, 24)
        let text = try viewer()
        let content = member("private func content(for story: Story)", in: text)
        assertInOrder(["photoArea(for: story)", "Color.clear.frame(height: Self.footerHeight)",
                       "if let highlight {", "highlightFooter(for: story, highlight: highlight)"],
                      in: content, "ハイライトの足元")
        XCTAssertFalse(content.contains(".overlay(alignment: .bottom) {\n                        highlightFooter"),
                       "ハイライトの足元が写真の上に重なっている")
        let photo = member("private func photoArea(for story: Story)", in: text)
        // 2026-10-16 判断: 角は閲覧画面と隣の面で共有の StoryViewerMetrics.photoRadius（= JPRadius.xl）を読む
        XCTAssertEqual(StoryViewerMetrics.photoRadius, JPRadius.xl)
        assertInOrder([".clipShape(UnevenRoundedRectangle(bottomLeadingRadius: StoryViewerMetrics.photoRadius,",
                       "bottomTrailingRadius: StoryViewerMetrics.photoRadius))"], in: photo, "写真の下の角丸")
        XCTAssertFalse(photo.contains("highlight == nil ? JPRadius.xl : 0"))
    }

    /// 日付「YYYY.MM.DD · 残したストーリー」はひとことの下、足元は「編集」だけ
    func testHighlightDateUnderCaption() throws {
        let text = try viewer()
        let caption = member("private func captionBlock(for story: Story)", in: text)
        assertInOrder(["let keptDate = highlight == nil ? nil : StoryPlayback.dotDate(story.createdAt)",
                       "if let caption {", "if let keptDate {", "残したストーリー",
                       "JPFont.mono(13, relativeTo: .footnote)", "StoryViewerMetrics.highlightDateOpacity",
                       "if let place {"], in: caption, "ハイライトの日付")
        let footer = member("private func highlightFooter(", in: text)
        XCTAssertFalse(footer.contains("dotDate"), "足元に日付が残っている")
        XCTAssertFalse(footer.contains("残したストーリー"))
        XCTAssertEqual(StoryViewerMetrics.highlightDateOpacity, 0.82)
    }

    /// 「編集」は透明の地に白 14% の縁（ガラスにしない）
    func testHighlightEditIsOutlined() throws {
        XCTAssertEqual(StoryViewerMetrics.highlightEditBorder, 0.14)
        let footer = member("private func highlightFooter(", in: try viewer())
        assertInOrder(["Image(systemName: \"pencil\")", ".jpSystemFont(StoryViewerMetrics.smallTextSize, weight: .semibold)",
                       "Capsule().strokeBorder(Color.white.opacity(StoryViewerMetrics.highlightEditBorder)"],
                      in: footer, "「編集」")
        XCTAssertFalse(footer.contains("jpGlass"), "「編集」がガラスのまま")
    }

    /// ひとことの明朝: ストーリー 30（作る画面と同じ）・ハイライト 28
    func testCaptionSizes() throws {
        XCTAssertEqual(StoryViewerMetrics.captionSize, 30)
        XCTAssertEqual(StoryViewerMetrics.captionSize, StoryComposerView.captionSize, "作る画面と見る画面でずれた")
        XCTAssertEqual(StoryViewerMetrics.highlightCaptionSize, 28)
        let caption = member("private func captionBlock(for story: Story)", in: try viewer())
        assertInOrder(["JPFont.display(highlight == nil ? StoryViewerMetrics.captionSize",
                       ": StoryViewerMetrics.highlightCaptionSize", "relativeTo: .largeTitle"], in: caption, "ひとことの字")
    }
}
