import XCTest
@testable import JourneyPhoto

/// v2 の土台（Artifact「デザインシステム v2」・2026-10-14）の値と、共通の部品がその値を通っていること。
///
/// 画面の部品は Linux では描けないので、**値は数で**、**部品の作りは元のファイルを読んで**見張る
/// （`FollowListSignInTests` と同じやり方）。ソースを読むときは型の範囲に絞り、呼び出しの**順**まで見る
/// ——字があるかだけを見ると、修飾子の入れ替えや呼び出しの削除で落ちない（2026-10-14 のレビュー）。
final class DesignFoundationTests: XCTestCase {

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

    /// `struct <name>` から次の型の宣言までを切り出す（ほかの型の同じ字に当たらないように）
    private func declaration(_ name: String, in text: String,
                             file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = text.range(of: "struct \(name)") else {
            XCTFail("struct \(name) が無い", file: file, line: line)
            return ""
        }
        let rest = text[start.upperBound...]
        let ends = ["\nstruct ", "\nprivate struct ", "\nenum ", "\nextension "]
            .compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
    }

    /// `parts` がこの順に `text` に現れる（並びの入れ替え・呼び出しの削除で落ちる）
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

    // MARK: - 物差し

    /// 余白はすべて 4 の倍数（板 04「4 と 8 の律動」）。画面の端 16・節の間 32
    func testSpacingIsOnTheFourGrid() {
        for value in JPSpace.all {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) は 4 の倍数でない")
        }
        XCTAssertEqual(JPSpace.all, [4, 8, 12, 16, 20, 24, 32, 48, 64])
        XCTAssertEqual(JPSpace.gutter, 16)
        XCTAssertEqual(JPSpace.section, 32)
    }

    /// 角（板 04）と線・高さ（Components 01・05）
    func testRadiiStrokesAndHeights() {
        XCTAssertEqual(JPRadius.all, [6, 10, 12, 14, 16, 24])
        XCTAssertEqual(JPStroke.hairline, 1)
        XCTAssertEqual(JPStroke.emphasis, 2)
        XCTAssertEqual(JPStroke.ringGap, 3)
        XCTAssertEqual(JPHeight.primaryButton, 50)
        XCTAssertEqual(JPHeight.secondaryButton, 44)
        XCTAssertEqual(JPHeight.field, 48)
        XCTAssertEqual(JPHeight.row, 52)
        XCTAssertEqual(JPHeight.tallRow, 64)
        // 副ボタンは押せるものの最小そのもの
        XCTAssertGreaterThanOrEqual(JPHeight.secondaryButton, WebTheme.minTapTarget)
    }

    // MARK: - 字の段

    /// 明朝は 32・26・22・20・18。18 未満に使わない
    func testMinchoSteps() {
        XCTAssertEqual(JPTypeScale.mincho, [32, 26, 22, 20, 18])
        for size in JPTypeScale.mincho {
            XCTAssertGreaterThanOrEqual(size, 18, "明朝 \(size) は下限の 18 を割る")
        }
    }

    /// 本文系は 12 以上。11 は眉ラベルだけ（CLAUDE.md・板 02）
    func testBodyTextNeverBelowTwelve() {
        XCTAssertEqual(JPTypeScale.body, 15)
        XCTAssertEqual(JPTypeScale.caption, 12)
        XCTAssertEqual(JPTypeScale.headline, 17)
        XCTAssertEqual(JPTypeScale.footnote, 13)
        for size in JPTypeScale.text {
            XCTAssertGreaterThanOrEqual(size, Double(WebTheme.minBodyText), "本文系 \(size) が 12 を割る")
        }
        XCTAssertEqual(JPTypeScale.eyebrow, 11)
        XCTAssertFalse(JPTypeScale.text.contains(11), "11 は眉ラベルだけ")
        XCTAssertEqual(JPTypeScale.eyebrowTracking, 1.54, accuracy: 0.001)
    }

    /// 数字は SF の等幅数字。**段に書いた大きさと、実際に出る文字の種類の標準の大きさが一致する**
    /// （`number` は近い文字の種類に寄せるので、30 と書くと 28 で出ていた・2026-10-14 のレビュー）
    func testNumberSizesAreWhatIsShown() {
        for size in JPTypeScale.numbers {
            let style = JPFont.numberStyle(size: size, relativeTo: .caption)
            let shown = JPFont.standardSizes.first { $0.style == style }?.size
            XCTAssertEqual(shown, size, "段の \(size) は \(shown ?? 0) で出る")
        }
        XCTAssertEqual(JPFont.numberStyle(size: JPTypeScale.figureLarge, relativeTo: .title), .title)
    }

    func testFontAndEyebrowUseTheScale() throws {
        let font = try source("Core/Design/JPFont.swift")
        for name in ["JPTypeScale.display", "JPTypeScale.title1", "JPTypeScale.title2",
                     "JPTypeScale.stateTitle", "JPTypeScale.title3"] {
            XCTAssertTrue(font.contains("display(\(name)"), "見出しの \(name) を段から作っていない")
        }
        XCTAssertTrue(font.contains("number(JPTypeScale.eyebrow, weight: .semibold"), "眉ラベルは SF 600")
        XCTAssertTrue(font.contains(".tracking(JPTypeScale.eyebrowTracking)"), "眉ラベルの字間が板の 0.14em でない")
    }

    // MARK: - 色

    /// v2 で沈めた面と、文字の3段
    func testV2PaletteValues() {
        XCTAssertEqual(BrandPalette.surface, 0x0E0E0F)
        XCTAssertEqual(BrandPalette.surface2, 0x161617)
        XCTAssertEqual(BrandPalette.accentSoft, 0x1C170E)
        XCTAssertEqual(BrandPalette.text2, 0xB8B8B8)
        XCTAssertEqual(BrandPalette.text3, 0x9A9A9A)
        XCTAssertEqual(BrandPalette.accentHighlight, 0xF3DCA6)
        XCTAssertEqual(BrandPalette.accentShadow, 0x9A7A45)
        // 白の主ボタンは 94%。黒に重ねた値と透明度が合っている
        XCTAssertEqual(WebTheme.primaryFillOpacity, 0.94)
        XCTAssertEqual(BrandPalette.primary & 0xFF, UInt32((255 * WebTheme.primaryFillOpacity).rounded()))
        // 変えていないもの
        XCTAssertEqual(BrandPalette.accent, 0xC9A66B)
        XCTAssertEqual(BrandPalette.danger, 0xF0565A)
    }

    /// 副文・注記の灰は黒と札の上で 4.5 を保つ（板の 10.6・7.4——板は 7.46 を切り捨てて書いている）
    func testSecondaryTextIsReadable() {
        XCTAssertEqual(BrandPalette.contrast(BrandPalette.text2, BrandPalette.background), 10.6, accuracy: 0.1)
        XCTAssertEqual(BrandPalette.contrast(BrandPalette.text3, BrandPalette.background), 7.46, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.text3, BrandPalette.surface2), 4.5)
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.ink, BrandPalette.primary), 4.5)
    }

    func testThemeUsesV2Values() throws {
        let theme = try source("Core/Design/WebTheme.swift")
        XCTAssertTrue(theme.contains("static let text2 = rgb(BrandPalette.text2)"))
        XCTAssertTrue(theme.contains("static let text3 = rgb(BrandPalette.text3)"))
        XCTAssertTrue(theme.contains("static let card = rgb(BrandPalette.surface)"))
        XCTAssertTrue(theme.contains("static let sheet = rgb(BrandPalette.surface2)"))
        XCTAssertTrue(theme.contains("Color.white.opacity(primaryFillOpacity)"))
        // 危険の色は danger だけ（系統の赤を作らない）
        XCTAssertFalse(theme.contains("Color.red"))
    }

    /// 🔴 **写真の上で使う灰は白の透過のまま**（2026-10-14 のレビュー）。不透明の灰にすると
    /// 明るい写真の上で沈む（白地＋黒 65% の影で 4.56 → 3.53）。黒地用の不透明の灰は `text2`・`text3`
    func testGraysOnPhotosStayTranslucent() throws {
        let theme = try source("Core/Design/WebTheme.swift")
        XCTAssertTrue(theme.contains("static let muted2 = Color.white.opacity(0.72)"), "muted2 が白の透過でない")
        XCTAssertTrue(theme.contains("static let faint = Color.white.opacity(0.6)"), "faint が白の透過でない")
        // 写真の上に字を置く画面は、不透明の灰・札の面を使わない
        for path in ["Features/Stories/StoryViewerView.swift", "Features/PhotoDetail/PhotoViewerView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("WebTheme.muted2"), "\(path) の写真の上の字をたどれない")
            for opaque in ["WebTheme.text2", "WebTheme.text3", "WebTheme.card"] {
                XCTAssertFalse(text.contains(opaque), "\(path) が写真の上で \(opaque) を使っている")
            }
        }
        // 写真の詳細は v2（2026-10-14・第3段）で題から下を写真の下の黒地に移した——黒地の部品は text2・text3 を使う。
        // 写真の上に残る部品（撮影地・撮影スポットの行・ページの点・コメントの欄）は
        // `PhotoScreensV2Tests.testPhotoFootIsWhiteOnly`・`testCommentSendIsWhiteCircle` が部品ごとに見張る
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("WebTheme.muted2"), "写真の詳細の写真の上の字をたどれない")
        XCTAssertFalse(detail.contains("WebTheme.card"), "写真の詳細に札の面")
    }

    /// 札（#0E0E0F）はシート（#161617）より暗い。シートの上の札は地を渡して浮かせる
    func testCardsOnTheReportSheetStandOut() throws {
        XCTAssertLessThan(BrandPalette.luminance(BrandPalette.surface), BrandPalette.luminance(BrandPalette.surface2))
        let sheet = try source("Features/Social/ReportSheet.swift")
        XCTAssertTrue(sheet.contains("sheetBackground = WebTheme.sheet"), "通報のシートの地が v2 の surface-2 でない")
        XCTAssertFalse(sheet.contains("JPCard {"), "シートの上に既定の地の札がある（シートと同じ暗さで札に見えない）")
        XCTAssertEqual(sheet.components(separatedBy: "JPCard(fill: WebTheme.surface)").count - 1, 2)
        let card = declaration("JPCard", in: try source("Core/Design/FormParts.swift"))
        XCTAssertTrue(card.contains(".background(fill ?? WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))"))
    }

    // MARK: - 主ボタン

    /// 写真のある画面は白、写真の無い画面は真鍮の塗り（CLAUDE.md の owner の好み・板より優先）
    func testMainButtonColorFollowsPhoto() {
        XCTAssertEqual(JPPillStyle.main(onPhoto: true), .primary)
        XCTAssertEqual(JPPillStyle.main(onPhoto: false), .accent)
    }

    /// 高さは 50（塗り）と 44（線）の2種類だけ。線の縁は白 14%
    func testPillHeights() {
        XCTAssertEqual(JPPillStyle.primary.height, 50)
        XCTAssertEqual(JPPillStyle.accent.height, 50)
        XCTAssertEqual(JPPillStyle.danger.height, 50)
        XCTAssertEqual(JPPillStyle.outline.height, 44)
        XCTAssertEqual(JPPillStyle.outline.borderOpacity, 0.14)
        XCTAssertEqual(JPPillStyle.primary.borderOpacity, 0)
    }

    func testPillButtonUsesStyleMetrics() throws {
        let parts = try source("Core/Design/FormParts.swift")
        XCTAssertTrue(parts.contains("Color.white.opacity(style.borderOpacity)"))
        XCTAssertFalse(parts.contains("minHeight: 52"), "v1 の 52 が残っている")
    }

    /// 同じ場所で主ボタン（50）と線のボタンが入れ替わる帯は、線のボタンも 50 にする（跳ねない）
    func testSwappedButtonsKeepOneHeight() throws {
        let parts = try source("Core/Design/FormParts.swift")
        XCTAssertTrue(parts.contains("minHeight: height ?? style.height)"), "カプセルの高さが段から来ていない")
        let pick = try source("Features/Trips/LibraryTripPickView.swift")
        assertInOrder(["if isLoading {", "jpPillButton(.outline, height: JPHeight.primaryButton)",
                       "} else {", ".jpPillButton(.primary)"], in: pick, "旅の記録に入れる帯")
    }

    /// 撮影スポットの「投稿」は共通の決まりを通る（写真があれば白・無ければ真鍮・並んでいれば線）
    func testOfficialSpotPostButtonGoesThroughMainRule() throws {
        XCTAssertEqual(OfficialSpotView.postButtonStyle(hasCover: true, hasLinked: false, postedHere: false), .primary)
        XCTAssertEqual(OfficialSpotView.postButtonStyle(hasCover: false, hasLinked: false, postedHere: false), .accent)
        XCTAssertEqual(OfficialSpotView.postButtonStyle(hasCover: true, hasLinked: true, postedHere: false), .outline)
        XCTAssertTrue(try source("Features/Spots/OfficialSpotView.swift").contains(".main(onPhoto: hasCover)"))
    }

    // MARK: - 合図の部品

    /// 件数バッジ: 真鍮（accent）＋墨＋外側の黒 2
    func testCountBadge() throws {
        XCTAssertEqual(CountBadge.size, 20)
        XCTAssertEqual(CountBadge.horizontalPadding, 6)
        let badge = declaration("CountBadge", in: try source("Features/Common/CountBadge.swift"))
        // 墨の字 → 真鍮の丸 → 外へ 2 広げて → 黒の丸（順が入れ替わると縁が内側に入る）
        assertInOrder([".foregroundStyle(WebTheme.accentText)",
                       ".frame(minWidth: Self.size, minHeight: Self.size)",
                       ".background(WebTheme.accent, in: Capsule())",
                       ".padding(JPStroke.emphasis)",
                       ".background(Color.black, in: Capsule())"], in: badge, "件数バッジ")
        // 地図の写真のピンと束が同じ部品を使う
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertEqual(map.components(separatedBy: "CountBadge(count:").count - 1, 2)
    }

    /// 眉ラベルの線: 真鍮 55% → 0 の 1px、字は `jpEyebrow` の真鍮
    func testEyebrowLine() throws {
        XCTAssertEqual(JPEyebrowLine.lineStartOpacity, 0.55)
        XCTAssertEqual(JPEyebrowLine.gap, 10)
        let eyebrow = declaration("JPEyebrowLine", in: try source("Core/Design/EyebrowLine.swift"))
        assertInOrder(["Text(text)", ".jpEyebrow()", ".foregroundStyle(WebTheme.accent)",
                       "LinearGradient(colors: [WebTheme.accent.opacity(Self.lineStartOpacity), WebTheme.accent.opacity(0)]",
                       ".frame(height: JPStroke.hairline)"], in: eyebrow, "眉ラベルの線")
    }

    /// 上の丸いガラスの札の印は 17pt regular（main にある決まり）
    func testToolbarIcon() {
        XCTAssertEqual(WebTheme.toolbarIconSize, 17)
        XCTAssertEqual(WebTheme.minTapTarget, 44)
    }

    // MARK: - 状態

    /// 空・失敗は同じ並び（明朝 20 の見出し → 15 の灰 → 一手）。空の一手は写真の無い画面の主ボタン
    func testStatesShareTheV2Layout() throws {
        let states = try source("Features/Common/ErrorBanner.swift")
        assertInOrder(["StateLayout {", "if let title { StateTitle(text: title) }", "StateMessage(text: message)",
                       "RetryButton(isBusy: isBusy, action: retry)"],
                      in: declaration("ErrorBanner", in: states), "失敗の表示")
        assertInOrder(["StateLayout {", "if let title { StateTitle(text: title) }", "StateMessage(text: message)",
                       ".jpPillButton(.main(onPhoto: false))"],
                      in: declaration("EmptyState", in: states), "空の表示")
        XCTAssertTrue(declaration("StateTitle", in: states).contains(".font(JPFont.stateTitle)"))
        let message = declaration("StateMessage", in: states)
        XCTAssertTrue(message.contains(".font(JPFont.body)"))
        XCTAssertTrue(message.contains(".foregroundStyle(WebTheme.muted2)"))
        assertInOrder(["if compact {", "} else {", ".frame(minHeight: JPHeight.secondaryButton)",
                       ".overlay(Capsule().strokeBorder(WebTheme.line"],
                      in: declaration("RetryButton", in: states), "「もう一度」の線のボタン")
        // 失敗の印を赤にしない・本文を .callout（16）に戻さない
        XCTAssertFalse(states.contains("WebTheme.danger"))
        XCTAssertFalse(states.contains(".font(.callout)"))
    }

    /// 読み込み中の骨格は 0.3 秒待ってから
    func testLoadingRevealDelay() {
        XCTAssertEqual(JPLoadingState.revealDelay, .milliseconds(300))
        XCTAssertEqual(JPLoadingState.boneGray, 0x1C1C1E)
    }

    /// 主な画面（ホーム・マイページ・人・地図）の空・失敗の表示が、共通の部品を通っている。
    /// 呼び出しを消したり、手書きの `Text` に戻したりすると落ちる
    func testMainScreensUseStateParts() throws {
        let expected: [(path: String, calls: [String])] = [
            ("Features/Gallery/GalleryView.swift", ["ErrorBanner(message: message)"]),
            ("Features/Profile/MyPageView.swift", ["EmptyState(message: L(\"まだ写真がありません\"",
                                                   "ErrorBanner(message: error)",
                                                   "ErrorBanner(message: reloadError)"]),
            ("Features/Profile/UserProfileView.swift", ["EmptyState(message: L(\"公開された写真はまだありません\""]),
            ("Features/Map/PhotoMapView.swift", ["ErrorBanner(message: Self.loadFailedText, isBusy: model.isLoading)",
                                                 "EmptyState(message: L(\"見つかりませんでした\""]),
        ]
        for (path, calls) in expected {
            let text = try source(path)
            for call in calls {
                XCTAssertTrue(text.contains(call), "\(path) の「\(call)」が共通の部品を通っていない")
            }
        }
    }

    /// 地図が透けるガラスの札の中の「もう一度」は小さい札（線だけの 44 は見えにくく、隣の字が折り返す）
    func testRetryInsideTheMapCardIsCompact() throws {
        let map = try source("Features/Map/PhotoMapView.swift")
        guard let start = map.range(of: "private func placePhotos(") else { return XCTFail("placePhotos が無い") }
        let tail = String(map[start.upperBound...])
        let body = String(tail[..<(tail.range(of: "\n    }\n")?.lowerBound ?? tail.endIndex)])
        XCTAssertTrue(body.contains("RetryButton(isBusy: model.isLoading, compact: true)"))
        XCTAssertFalse(body.contains("RetryButton(isBusy: model.isLoading) {"))
    }
}
