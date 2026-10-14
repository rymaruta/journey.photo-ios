import XCTest
@testable import JourneyPhoto

/// v2 の土台（Artifact「デザインシステム v2」・2026-10-14）の値と、共通の部品がその値を通っていること。
///
/// 画面の部品は Linux では描けないので、**値は数で**、**部品の作りは元のファイルを読んで**見張る
/// （`FollowListSignInTests` と同じやり方）。
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

    /// 数字は SF の等幅数字（`number` / `mono` が近い文字の種類を選ぶ）
    func testNumberStylesPickNearestTextStyle() {
        XCTAssertEqual(JPFont.numberStyle(size: JPTypeScale.eyebrow, relativeTo: .caption2), .caption2)
        XCTAssertEqual(JPFont.numberStyle(size: JPTypeScale.meta, relativeTo: .caption), .caption)
        XCTAssertEqual(JPFont.numberStyle(size: JPTypeScale.figureMedium, relativeTo: .title3), .title3)
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

    /// 副文・注記の灰は黒と札の上で 4.5 を保つ（板の 10.6・7.4）
    func testSecondaryTextIsReadable() {
        XCTAssertEqual(BrandPalette.contrast(BrandPalette.text2, BrandPalette.background), 10.6, accuracy: 0.1)
        XCTAssertEqual(BrandPalette.contrast(BrandPalette.text3, BrandPalette.background), 7.46, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.text3, BrandPalette.surface2), 4.5)
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.ink, BrandPalette.primary), 4.5)
    }

    func testThemeUsesV2Values() throws {
        let theme = try source("Core/Design/WebTheme.swift")
        XCTAssertTrue(theme.contains("static let muted2 = rgb(BrandPalette.text2)"))
        XCTAssertTrue(theme.contains("static let faint = rgb(BrandPalette.text3)"))
        XCTAssertTrue(theme.contains("static let card = rgb(BrandPalette.surface)"))
        XCTAssertTrue(theme.contains("Color.white.opacity(primaryFillOpacity)"))
        // 危険の色は danger だけ（系統の赤を作らない）
        XCTAssertFalse(theme.contains("Color.red"))
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
        XCTAssertTrue(parts.contains("minHeight: style.height"), "カプセルの高さが段から来ていない")
        XCTAssertTrue(parts.contains("Color.white.opacity(style.borderOpacity)"))
        XCTAssertFalse(parts.contains("minHeight: 52"), "v1 の 52 が残っている")
        // 札は v2 の面と髪線
        XCTAssertTrue(parts.contains("WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l)"))
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
        let badge = try source("Features/Common/CountBadge.swift")
        XCTAssertTrue(badge.contains(".background(WebTheme.accent, in: Capsule())"), "塗りが真鍮でない")
        XCTAssertTrue(badge.contains(".foregroundStyle(WebTheme.accentText)"), "字が墨でない")
        XCTAssertTrue(badge.contains(".padding(JPStroke.emphasis)"), "黒い縁が外側の 2 でない")
        XCTAssertTrue(badge.contains(".background(Color.black, in: Capsule())"))
        // 地図の写真のピンと束が同じ部品を使う
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertEqual(map.components(separatedBy: "CountBadge(count:").count - 1, 2)
    }

    /// 眉ラベルの線: 真鍮 55% → 0 の 1px、字は `jpEyebrow` の真鍮
    func testEyebrowLine() throws {
        XCTAssertEqual(JPEyebrowLine.lineStartOpacity, 0.55)
        XCTAssertEqual(JPEyebrowLine.gap, 10)
        let eyebrow = try source("Core/Design/EyebrowLine.swift")
        XCTAssertTrue(eyebrow.contains(".jpEyebrow()"))
        XCTAssertTrue(eyebrow.contains(".foregroundStyle(WebTheme.accent)"))
        XCTAssertTrue(eyebrow.contains(".frame(height: JPStroke.hairline)"))
    }

    /// 上の丸いガラスの札の印は 17pt regular（main にある決まり）
    func testToolbarIcon() {
        XCTAssertEqual(WebTheme.toolbarIconSize, 17)
        XCTAssertEqual(WebTheme.minTapTarget, 44)
    }

    // MARK: - 状態

    /// 空・失敗は同じ並び（明朝 20 の見出し → 15 の text-2 → 一手）。空の一手は写真の無い画面の主ボタン
    func testStatesShareTheV2Layout() throws {
        let states = try source("Features/Common/ErrorBanner.swift")
        XCTAssertTrue(states.contains(".font(JPFont.stateTitle)"))
        XCTAssertTrue(states.contains(".font(JPFont.body)"))
        XCTAssertTrue(states.contains(".foregroundStyle(WebTheme.muted2)"))
        XCTAssertTrue(states.contains(".jpPillButton(.main(onPhoto: false))"), "空の一手が真鍮の主ボタンでない")
        XCTAssertTrue(states.contains(".frame(minHeight: JPHeight.secondaryButton)"), "「もう一度」が 44 でない")
        XCTAssertTrue(states.contains("WebTheme.line"), "「もう一度」の縁が白 14% でない")
        // 失敗の印を赤にしない・本文を .callout（16）に戻さない
        XCTAssertFalse(states.contains("WebTheme.danger"))
        XCTAssertFalse(states.contains(".font(.callout)"))
    }

    /// 読み込み中の骨格は 0.3 秒待ってから
    func testLoadingRevealDelay() {
        XCTAssertEqual(JPLoadingState.revealDelay, .milliseconds(300))
        XCTAssertEqual(JPLoadingState.boneGray, 0x1C1C1E)
    }

    /// 主な画面（ホーム・マイページ・地図）が空・失敗の共通の部品を通っている
    func testMainScreensUseStateParts() throws {
        for path in ["Features/Gallery/GalleryView.swift", "Features/Profile/MyPageView.swift",
                     "Features/Map/PhotoMapView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("ErrorBanner(") || text.contains("RetryButton("), "\(path) が失敗の部品を通っていない")
        }
        for path in ["Features/Profile/MyPageView.swift", "Features/Map/PhotoMapView.swift",
                     "Features/Profile/UserProfileView.swift"] {
            XCTAssertTrue(try source(path).contains("EmptyState("), "\(path) が空の部品を通っていない")
        }
    }
}
