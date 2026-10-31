import XCTest
@testable import JourneyPhoto

/// マイページの区分の札（2026-10-30 owner 採用 #418・板「マイページ」の区分の札の案A）。
/// 字と線の値・下線の長さ・押している間の色・切り替えの動き・「視差効果を減らす」・送ると上に留まることを見張る。
/// 画面は Linux の模型では描けないので、**値**と**書いてあること**を見る。直しを戻すと落ちる
final class ProfileTabBarStyleTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Profile/" + path),
                          encoding: .utf8)
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        let lower = try XCTUnwrap(text.range(of: start), "「\(start)」が見つからない")
        let upper = try XCTUnwrap(text.range(of: end, range: lower.upperBound..<text.endIndex), "「\(end)」が見つからない")
        return String(text[lower.lowerBound..<upper.lowerBound])
    }

    // MARK: - 寸法

    /// 字 15・札の間 24・左右 16・高さ 48（当たり 48）・下線 2pt・角丸 1
    func testMetricsMatchTheBoard() {
        XCTAssertEqual(ProfileTabStyle.labelSize, 15)
        XCTAssertEqual(ProfileTabStyle.gap, 24, "札の間は 24（v2 の 22 に戻っている）")
        XCTAssertEqual(ProfileTabStyle.gutter, 16)
        XCTAssertEqual(ProfileTabStyle.height, 48, "札の高さ（当たり）は 48")
        XCTAssertGreaterThanOrEqual(ProfileTabStyle.height, WebTheme.minTapTarget)
        XCTAssertEqual(JPStroke.emphasis, 2, "下線は 2pt")
        XCTAssertEqual(ProfileTabStyle.underlineRadius, 1, "下線の角丸は 1")
    }

    /// 🔴 下線の長さは字の幅＋左右 2（札の割り当ての幅いっぱいにしない）
    func testUnderlineIsTextWidthPlusTwoEachSide() throws {
        XCTAssertEqual(ProfileTabStyle.underlineInset, 2)
        XCTAssertEqual(ProfileTabStyle.underlineWidth(textWidth: 30), 34)
        XCTAssertEqual(ProfileTabStyle.underlineWidth(textWidth: 90), 94)
        // 下線は「字＋左右 2 の余白」の札（ボタン）に重ね、割り当ての幅（`fill`）はその外で取る
        let bar = try source("ProfileTabBar.swift")
        let tab = try slice(bar, from: "private func tab(", to: "private func spoken(")
        let padding = try XCTUnwrap(tab.range(of: ".padding(.horizontal, ProfileTabStyle.underlineInset)"), "字の左右の 2 が無い")
        let underline = try XCTUnwrap(tab.range(of: ".matchedGeometryEffect(id: \"profile.tab.underline.\\(fill)\", in: underline)"))
        let slack = try XCTUnwrap(tab.range(of: ".padding(.horizontal, ProfileTabStyle.hitSlack)"), "押せる範囲を広げていない")
        let fill = try XCTUnwrap(tab.range(of: ".frame(maxWidth: fill ? .infinity : nil)"), "広げた並びの幅が無い")
        XCTAssertLessThan(padding.lowerBound, underline.lowerBound)
        XCTAssertLessThan(underline.lowerBound, slack.lowerBound, "下線が広げた当たりの幅まで伸びる（字の幅＋2 でない）")
        XCTAssertLessThan(underline.lowerBound, fill.lowerBound, "下線が割り当ての幅いっぱいに伸びる（字の幅＋2 でない）")
        XCTAssertTrue(tab.contains(".frame(minHeight: ProfileTabStyle.height)"), "札の高さが 48 でない")
        // 下線は札の下端
        XCTAssertTrue(tab.contains(".overlay(alignment: .bottom) {"))
    }

    /// 🔴 押せる範囲は札の左右に札の間の半分（12）まで広げる。見た目は札の間 24・左右 16 のまま。
    /// 「投稿」「保存」（字 約30）でも当たりが 44 に届く。広げた並びでは割り当ての幅いっぱい
    func testHitAreaReachesFortyFour() throws {
        XCTAssertEqual(ProfileTabStyle.hitSlack, 12)
        XCTAssertEqual(ProfileTabStyle.hitSlack * 2, ProfileTabStyle.gap, "札の間（見た目）が 24 でなくなる")
        XCTAssertEqual(ProfileTabStyle.rowInset + ProfileTabStyle.hitSlack, ProfileTabStyle.gutter, "左右の余白（見た目）が 16 でなくなる")
        let twoLetters: CGFloat = 30
        XCTAssertGreaterThanOrEqual(ProfileTabStyle.underlineWidth(textWidth: twoLetters) + ProfileTabStyle.hitSlack * 2,
                                    WebTheme.minTapTarget, "2文字の札の当たりが 44 に足りない")
        let bar = try source("ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("HStack(spacing: 0) {"), "札の間を spacing で空けている（間が押せない）")
        XCTAssertTrue(bar.contains(".padding(.horizontal, ProfileTabStyle.rowInset(gutter: gutter))"))
        XCTAssertEqual(ProfileTabStyle.rowInset(gutter: ProfileTabStyle.gutter), ProfileTabStyle.rowInset,
                       "既定の余白で行の端が 4 でなくなる")
        let tab = try slice(bar, from: "private func tab(", to: "private func spoken(")
        let fill = try XCTUnwrap(tab.range(of: ".frame(maxWidth: fill ? .infinity : nil)"))
        let shape = try XCTUnwrap(tab.range(of: ".contentShape(Rectangle())"), "当たりの形が無い")
        XCTAssertLessThan(fill.lowerBound, shape.lowerBound, "広げた並びの割り当ての残りが押せない")
        let label = try slice(tab, from: "} label: {", to: ".buttonStyle(")
        XCTAssertTrue(label.contains(".contentShape(Rectangle())"), "当たりの形がボタンの中身に無い")
    }

    // MARK: - 色と字

    /// 選んだ札は真鍮 #C9A66B の 600、ほかは text-3 #9A9A9A の 500。下の線は白 8%（留まると 12%）
    func testColorsAndWeights() throws {
        XCTAssertEqual(BrandPalette.accent, 0xC9A66B)
        XCTAssertEqual(BrandPalette.text3, 0x9A9A9A)
        XCTAssertEqual(ProfileTabStyle.lineOpacity(stuck: false), 0.08, accuracy: 0.0001)
        XCTAssertEqual(ProfileTabStyle.lineOpacity(stuck: true), 0.12, accuracy: 0.0001, "留まった札の下の線は白 12%")
        let bar = try source("ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("selected ? JPFont.bodyEmphasis : Font.subheadline.weight(.medium)"),
                      "選んでいない札が 500（medium）でない")
        XCTAssertTrue(bar.contains("selected ? WebTheme.accent : WebTheme.text3"))
        // 幅は太字で測る（選び替えで並びが揺れない）
        XCTAssertTrue(bar.contains(".font(ProfileTabStyle.font(selected: true))\n                .lineLimit(1)\n                .hidden()"))
        // 留まったら地を黒 100%。区切り線は地の側（真鍮の下線の上に重ねない）
        let body = try slice(bar, from: "var body: some View {", to: "private func tab(")
        let background = try slice(body, from: ".background {", to: "\n    }")
        XCTAssertTrue(background.contains("(stuck ? Color.black : Color.clear)"), "留まった札の地が黒でない")
        XCTAssertTrue(background.contains(".fill(Color.white.opacity(ProfileTabStyle.lineOpacity(stuck: stuck)))"),
                      "区切り線が地の側に無い（下線の上に重なる）")
        XCTAssertFalse(body.contains(".overlay(alignment: .bottom) {\n            Rectangle()"), "区切り線が下線の上に重なっている")
    }

    /// 🔴 押している間は字を白 95%、離すと 0.15 秒で戻す。選び替えの字の色も 0.15 秒
    func testPressedLabelTurnsWhite() throws {
        XCTAssertEqual(ProfileTabStyle.pressedOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(ProfileTabStyle.colorFade, 0.15, accuracy: 0.0001)
        let bar = try source("ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("pressed ? Color.white.opacity(ProfileTabStyle.pressedOpacity) : color(selected: selected)"))
        // 2026-10-31（#426）: 札の部品を区分の型で受ける形にしたので、色は値の側（`ProfileTabStyle`）に置く
        let style = try slice(bar + "\n//END", from: "struct ProfileTabPressStyle", to: "\n//END")
        XCTAssertTrue(style.contains("ProfileTabStyle.color(selected: selected, pressed: configuration.isPressed)"),
                      "押している間の色を見ていない")
        // 0.15 秒の動きは字の色だけに閉じ込める（`value:` 付きだと、中の下線のばねまで 0.15 秒の直線になる）
        XCTAssertTrue(style.contains(".animation(.easeOut(duration: ProfileTabStyle.colorFade)) { content in\n                content.foregroundStyle("),
                      "字の色の 0.15 秒が色だけに閉じていない")
        XCTAssertFalse(style.contains(", value:"), "0.15 秒の動きが下線にも掛かる")
        let tab = try slice(bar, from: "private func tab(", to: "private func spoken(")
        XCTAssertTrue(tab.contains(".buttonStyle(ProfileTabPressStyle(selected: selected))"), "押し方の部品を使っていない")
    }

    // MARK: - 切り替えの動き

    /// 🔴 下線は 0.28 秒のばね（減衰 0.85）。「視差効果を減らす」では滑らせずに置く
    func testSwitchUsesSpringAndRespectsReduceMotion() throws {
        XCTAssertEqual(ProfileTabStyle.springResponse, 0.28, accuracy: 0.0001)
        XCTAssertEqual(ProfileTabStyle.springDamping, 0.85, accuracy: 0.0001)
        XCTAssertNil(ProfileTabMotion.animation(reduceMotion: true), "視差効果を減らすでも下線が滑る")
        XCTAssertNotNil(ProfileTabMotion.animation(reduceMotion: false))
        let pager = try source("ProfileTabPager.swift")
        let motion = try slice(pager, from: "enum ProfileTabMotion", to: "struct ProfileTabSwipe")
        XCTAssertTrue(motion.contains(".spring(response: ProfileTabStyle.springResponse,"), "切り替えがばねでない")
        XCTAssertTrue(motion.contains("dampingFraction: ProfileTabStyle.springDamping"))
        XCTAssertTrue(motion.contains("reduceMotion ? nil :"))
        XCTAssertFalse(motion.contains(".easeOut(duration:"), "前の 0.25 秒の easeOut が残っている")
    }

    // MARK: - 上に留まる

    /// 🔴 札の行が見えている上端を越えたら留める（ちょうど上端に居る間は元の行のまま）
    func testPinsOnlyAfterTheRowCrossesTheTop() {
        XCTAssertFalse(ProfileTabScroll.pinsRow(rowMinY: 300, visibleTop: 59))
        XCTAssertFalse(ProfileTabScroll.pinsRow(rowMinY: 59, visibleTop: 59), "替えて頭へ送った直後まで重ねる")
        XCTAssertTrue(ProfileTabScroll.pinsRow(rowMinY: 20, visibleTop: 59))
        XCTAssertTrue(ProfileTabScroll.pinsRow(rowMinY: -400, visibleTop: 59))
        // カバーの無い人（安全域の内側で測る）
        XCTAssertFalse(ProfileTabScroll.pinsRow(rowMinY: 0, visibleTop: 0))
        XCTAssertTrue(ProfileTabScroll.pinsRow(rowMinY: -1, visibleTop: 0))
    }

    /// 🔴 マイページは中身を `VStack` のまま（上の段を作り直さない）、越えている間だけ留まった札を重ねる。
    /// 流れている元の行は見せず・押させず・読ませない（二重にしない）。重ねた札は地が黒（`stuck: true`）
    func testMyPageOverlaysThePinnedRow() throws {
        let page = try source("MyPageView.swift")
        XCTAssertFalse(page.contains("LazyVStack(alignment: .leading, spacing: 14"),
                       "中身を LazyVStack にしている（上の段が画面外で作り直され、読み直しが走る）")
        XCTAssertFalse(page.contains("pinnedViews:"))
        let content = try slice(page, from: "private var content: some View {", to: "private func scroll(")
        XCTAssertTrue(content.contains("if tabRowPinned { pinnedTabRow }"), "留まった札を重ねていない")
        let pinned = try slice(page, from: "private var pinnedTabRow: some View {", to: "\n    }")
        XCTAssertTrue(pinned.contains("tabPicker(stuck: true)"), "留まった札の地が黒でない")
        let scroll = try slice(page, from: "private func scroll(", to: ".refreshable")
        let row = try slice(scroll, from: "tabPicker(stuck: false)", to: "photoBanners")
        XCTAssertTrue(row.contains(".opacity(tabRowPinned ? 0 : 1)"))
        XCTAssertTrue(row.contains(".allowsHitTesting(!tabRowPinned)"))
        XCTAssertTrue(row.contains(".accessibilityHidden(tabRowPinned)"), "読み上げ・UI テストで札が二重になる")
        XCTAssertTrue(row.contains(".id(ProfileTabScroll.rowID)"), "替えたら頭から見せる目印が流れる行に無い")
        XCTAssertTrue(row.contains("ProfileTabScroll.pinsRow(rowMinY: proxy.frame(in: .scrollView).minY, visibleTop: visibleTop)"))
        XCTAssertTrue(row.contains(".onGeometryChange(for: Bool.self)"), "越えたかを送るたびに書いている")
    }
}
