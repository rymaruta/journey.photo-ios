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
        let tab = try slice(bar, from: "private func tab(", to: "static func color(selected: Bool) -> Color")
        let padding = try XCTUnwrap(tab.range(of: ".padding(.horizontal, ProfileTabStyle.underlineInset)"), "字の左右の 2 が無い")
        let underline = try XCTUnwrap(tab.range(of: ".matchedGeometryEffect(id: \"profile.tab.underline.\\(fill)\", in: underline)"))
        let fill = try XCTUnwrap(tab.range(of: ".frame(maxWidth: fill ? .infinity : nil)"), "広げた並びの幅が無い")
        XCTAssertLessThan(padding.lowerBound, underline.lowerBound)
        XCTAssertLessThan(underline.lowerBound, fill.lowerBound, "下線が割り当ての幅いっぱいに伸びる（字の幅＋2 でない）")
        XCTAssertTrue(tab.contains(".frame(minHeight: ProfileTabStyle.height)"), "札の高さが 48 でない")
        // 下線は札の下端
        XCTAssertTrue(tab.contains(".overlay(alignment: .bottom) {"))
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
        XCTAssertTrue(bar.contains(".font(ProfileTabStyle.font(selected: true))\n            .lineLimit(1)\n            .hidden()"))
        // 留まったら地を黒 100%
        XCTAssertTrue(bar.contains(".background(stuck ? Color.black : Color.clear)"), "留まった札の地が黒でない")
    }

    /// 🔴 押している間は字を白 95%、離すと 0.15 秒で戻す。選び替えの字の色も 0.15 秒
    func testPressedLabelTurnsWhite() throws {
        XCTAssertEqual(ProfileTabStyle.pressedOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(ProfileTabStyle.colorFade, 0.15, accuracy: 0.0001)
        let bar = try source("ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("pressed ? Color.white.opacity(ProfileTabStyle.pressedOpacity) : color(selected: selected)"))
        let style = try slice(bar, from: "struct ProfileTabPressStyle", to: "struct ProfilePinnedTabRow")
        XCTAssertTrue(style.contains("ProfileTabBar.color(selected: selected, pressed: configuration.isPressed)"),
                      "押している間の色を見ていない")
        XCTAssertTrue(style.contains(".animation(.easeOut(duration: ProfileTabStyle.colorFade), value: configuration.isPressed)"))
        XCTAssertTrue(style.contains(".animation(.easeOut(duration: ProfileTabStyle.colorFade), value: selected)"))
        // 0.15 秒の動きは字だけ。下線は押し方の部品の外（中にあると、下線のばねまで 0.15 秒になる）
        XCTAssertFalse(style.contains("matchedGeometryEffect"))
        let tab = try slice(bar, from: "private func tab(", to: "static func color(selected: Bool) -> Color")
        let pressStyle = try XCTUnwrap(tab.range(of: ".buttonStyle(ProfileTabPressStyle(selected: selected))"), "押し方の部品を使っていない")
        let underline = try XCTUnwrap(tab.range(of: "RoundedRectangle(cornerRadius: ProfileTabStyle.underlineRadius)"))
        XCTAssertLessThan(pressStyle.lowerBound, underline.lowerBound, "下線が押し方の部品の中にある")
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

    /// 🔴 留まった・留まりかけた分だけ下げて、時計の帯の下に置く（カバーを時計の裏まで伸ばしたマイページ）
    func testPinnedRowSitsUnderTheClock() {
        // まだ下にある: 下げない・留まっていない
        XCTAssertEqual(ProfileTabStyle.pinLift(rowTop: 300, visibleTop: 59), 0)
        XCTAssertFalse(ProfileTabStyle.isStuck(rowTop: 300, visibleTop: 59))
        // 時計の帯の中へ入りかけ（上端 20）: 39 下げて帯の下（59）に置く
        XCTAssertEqual(ProfileTabStyle.pinLift(rowTop: 20, visibleTop: 59), 39)
        XCTAssertTrue(ProfileTabStyle.isStuck(rowTop: 20, visibleTop: 59))
        // 留まった（見えている枠の 0）: 帯の高さだけ下げる
        XCTAssertEqual(ProfileTabStyle.pinLift(rowTop: 0, visibleTop: 59), 59)
        XCTAssertEqual(ProfileTabStyle.pinLift(rowTop: -40, visibleTop: 59), 59)
        // カバーの無い人（安全域の下に留まる）: 下げない。留まったら黒地
        XCTAssertEqual(ProfileTabStyle.pinLift(rowTop: 0, visibleTop: 0), 0)
        XCTAssertTrue(ProfileTabStyle.isStuck(rowTop: 0, visibleTop: 0))
        XCTAssertFalse(ProfileTabStyle.isStuck(rowTop: 120, visibleTop: 0))
    }

    /// 測った上端は時計の帯の高さの間だけ変わる（その外では同じ値＝送るたびに描き直さない）
    func testPinTopOnlyChangesInsideTheClockBand() {
        XCTAssertEqual(ProfileTabStyle.pinTop(500, visibleTop: 59), 60)
        XCTAssertEqual(ProfileTabStyle.pinTop(900, visibleTop: 59), 60)
        XCTAssertEqual(ProfileTabStyle.pinTop(30, visibleTop: 59), 30)
        XCTAssertEqual(ProfileTabStyle.pinTop(-10, visibleTop: 59), 0)
        XCTAssertFalse(ProfileTabStyle.isStuck(rowTop: ProfileTabStyle.pinTop(500, visibleTop: 59), visibleTop: 59))
        XCTAssertFalse(ProfileTabStyle.isStuck(rowTop: ProfileTabStyle.pinTop(400, visibleTop: 0), visibleTop: 0))
    }

    /// 🔴 マイページは区分の札を節の見出しで留める。札の行の目印（替えたとき頭から）は流れる位置に置く
    func testMyPagePinsTheTabRow() throws {
        let page = try source("MyPageView.swift")
        XCTAssertTrue(page.contains("LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders])"),
                      "区分の札を上に留めていない")
        let section = try slice(page, from: "Section {", to: ".refreshable")
        let header = try slice(section, from: "} header: {", to: ".onGeometryChange(for: CGFloat.self)")
        XCTAssertTrue(header.contains("ProfilePinnedTabRow(visibleTop: visibleTop) { stuck in"))
        XCTAssertTrue(header.contains("tabPicker(stuck: stuck)"), "留まったときの地と線を渡していない")
        XCTAssertTrue(header.contains(".modifier(ProfileTabSwipe(tabs: ProfileTab.tabs(isMe: true), selection: $tab))"),
                      "留まった札の行で払えない")
        // 目印は見出し（留まる）に付けない——留まった位置では「深く送ったか」が分からない
        XCTAssertFalse(header.contains(".id(ProfileTabScroll.rowID)"), "札の行の目印が留まる見出しに付いている")
        let marker = try slice(section, from: ".background(alignment: .top) {", to: "} header: {")
        XCTAssertTrue(marker.contains(".alignmentGuide(.top) { _ in tabRowHeight + 14 }"), "目印が流れる札の行の位置にない")
        XCTAssertTrue(marker.contains(".id(ProfileTabScroll.rowID)"))
        XCTAssertTrue(marker.contains("tabRow.record(frame, height: tabRowHeight)"))
        // 留める部品は下げる前の枠で測る（下げた分で測り直して揺れない）
        let bar = try source("ProfileTabBar.swift")
        let pinned = try slice(bar, from: "struct ProfilePinnedTabRow", to: "extension ProfileTabStyle")
        let offset = try XCTUnwrap(pinned.range(of: ".offset(y: ProfileTabStyle.pinLift(rowTop: top, visibleTop: visibleTop))"))
        let measure = try XCTUnwrap(pinned.range(of: ".onGeometryChange(for: CGFloat.self)"))
        XCTAssertLessThan(offset.lowerBound, measure.lowerBound)
        XCTAssertTrue(pinned.contains("ProfileTabStyle.pinTop(proxy.frame(in: .scrollView).minY, visibleTop: visibleTop)"))
    }
}
