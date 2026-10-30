import SwiftUI

/// プロフィールの下線の札（板 v2 MyPage・UserProfile の「棚」のタブ）。マイページと人のページで同じ見た目。
///
/// **既定の `segmented` を使わない**——黒地の上で帯だけ明るく浮く。
///
/// **2026-10-30 owner 採用（#418・板「マイページ」の区分の札の案A）**: 字と線を磨いた（値は `ProfileTabStyle`）。
/// - 字 15。選んだ札は真鍮の 600（semibold）、ほかは text-3 の 500（medium）。札の間 24・左右 16・高さ 48（当たり 48）
/// - 真鍮の下線は 2pt・角丸 1・長さは字の幅＋左右 2（`ProfileTabStyle.underlineWidth`）・札の下端。下に白 8% の線
/// - 押している間は字を白 95%、離すと 0.15 秒で戻す（`ProfileTabPressStyle`）
/// - 切り替えは下線が 0.28 秒のばね（減衰 0.85）で次の札の幅に伸び縮みしながら滑る。字の色は 0.15 秒。
///   「視差効果を減らす」では滑らせずに置く（`ProfileTabMotion`）
/// - 送って上に留まったとき（`stuck`・マイページの `pinnedTabRow`）は地を黒 100%・下の線を白 12% に濃くする
/// - **押せる範囲は札の間の半分（12）まで左右に広げる**（2026-10-30 確かめ役の見直し: 字の幅＋2 だけだと「投稿」「保存」が
///   約 34pt で 44 に足りなかった）。並びは「札ごとに左右 12 の余白・端は 16−12＝4」で、見た目は札の間 24・左右 16 のまま。
///   広げた並び（`fill`）では割り当ての幅いっぱいが押せる
///
/// 色だけで言わない——下線と太さと読み上げの「選択中」でも言う。
///
/// **入らなければ（大きい文字・狭い端末）幅いっぱいに割って縮める**（`TabRowLayout`・中身の幅＋余りの等分）。
/// 下線はそのときも字の幅＋左右 2（割り当てた幅いっぱいにしない）
struct ProfileTabBar: View {

    let tabs: [ProfileTab]
    @Binding var selection: ProfileTab
    /// 上に留まっているか（地を黒 100%・下の線を白 12% に）。人のページは留めないので既定は false
    var stuck: Bool = false
    /// 名前の字の大きさ（`.subheadline` と同じだけ伸びる。既定 15）。縮める下限の計算に使う
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = ProfileTabStyle.labelSize
    /// 下線を選んだ札へ滑らせる目印（2026-10-24 判断・owner「切り替えスムーズに」）。
    /// 以前は札ごとに「選んでいれば真鍮・でなければ透明」で描き、切り替えで瞬時に入れ替わっていた
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(tabs) { option in tab(option, fill: false) }
                Spacer(minLength: 0)
            }
            TabRowLayout {
                ForEach(tabs) { option in tab(option, fill: true) }
            }
        }
        .padding(.horizontal, ProfileTabStyle.rowInset)
        // 区切り線は地の側（`background`）——真鍮の下線の上に重ねない
        .background {
            (stuck ? Color.black : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(ProfileTabStyle.lineOpacity(stuck: stuck)))
                        .frame(height: JPStroke.hairline)
                }
        }
    }

    /// 1つの札。下線は字の幅＋左右 2（`fill` のときも割り当てた幅いっぱいにしない）
    private func tab(_ option: ProfileTab, fill: Bool) -> some View {
        let selected = selection == option
        return Button {
            // 滑らせる（「視差効果を減らす」のときは動かさない・`ProfileTabMotion`）
            withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                selection = option
            }
        } label: {
            label(option, selected: selected)
                .padding(.horizontal, ProfileTabStyle.underlineInset)
                .frame(minHeight: ProfileTabStyle.height)
                .overlay(alignment: .bottom) {
                    // 真鍮の下線は1本だけ。選んだ札へ形ごと移る（`matchedGeometryEffect`）——幅も次の札の字の幅に伸び縮みする。
                    // 長さは字の幅＋左右 2（広げた当たりの余白の内側）。
                    // id に並びの別（`fill`）を足す——`ViewThatFits` の2案が同じ id を持つと、両方が元になる
                    if selected {
                        RoundedRectangle(cornerRadius: ProfileTabStyle.underlineRadius)
                            .fill(WebTheme.accent)
                            .frame(height: JPStroke.emphasis)
                            .matchedGeometryEffect(id: "profile.tab.underline.\(fill)", in: underline)
                    }
                }
                // 押せる範囲: 左右に札の間の半分（12）、広げた並びでは割り当ての幅いっぱい
                .padding(.horizontal, ProfileTabStyle.hitSlack)
                .frame(maxWidth: fill ? .infinity : nil)
                .contentShape(Rectangle())
        }
        // 字の色（選んだ・押している）は押し方の部品で 0.15 秒。その動きは色だけに閉じ込め、下線はばねで滑らせる
        .buttonStyle(ProfileTabPressStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("profile.tab.\(option.rawValue)")
    }

    /// 名前の色。選んでいる札は真鍮（黒地の上だけ・マイページも人のページも黒地）
    @MainActor
    static func color(selected: Bool) -> Color {
        selected ? WebTheme.accent : WebTheme.text3
    }

    /// 押している間の色を含めた名前の色（押している間は選んでいても白 95%）
    @MainActor
    static func color(selected: Bool, pressed: Bool) -> Color {
        pressed ? Color.white.opacity(ProfileTabStyle.pressedOpacity) : color(selected: selected)
    }

    /// 名前。**幅は太字で測る**（選ぶたびに幅が変わって並びが揺れないように）。
    /// 太さは選んでいる札だけ変える（選んだ 600・ほか 500）
    private func label(_ option: ProfileTab, selected: Bool) -> some View {
        Text(option.label)
            .font(ProfileTabStyle.font(selected: true))
            .lineLimit(1)
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                Text(option.label)
                    .font(ProfileTabStyle.font(selected: selected))
                    .lineLimit(1)
                    // **縮めても 12pt まで**（本文の最小）
                    .minimumScaleFactor(WebTheme.minimumScale(forTextSize: labelSize))
            }
    }
}

/// 区分の札の値（2026-10-30 owner 採用 #418・板「マイページ」の区分の札の案A）。
/// Linux のテストで見張るため `nonisolated static` で持つ（`ProfileTabBarStyleTests`）
enum ProfileTabStyle {
    /// 字の大きさ（`.subheadline` ＝ 15）
    nonisolated static let labelSize: CGFloat = 15
    /// 札と札の間（板 gap 24。v2 の 22 から広げた）
    nonisolated static let gap: CGFloat = 24
    /// 左右の余白（字の左の 2 の外側まで）
    nonisolated static let gutter: CGFloat = JPSpace.gutter
    /// 押せる範囲を札の左右に広げる量（札の間の半分）。札の間 24 はこの 2 つ分
    nonisolated static let hitSlack: CGFloat = gap / 2
    /// 行の端の余白（左右 16 から、端の札の広げた分を引く）
    nonisolated static let rowInset: CGFloat = gutter - hitSlack
    /// 札の高さ（当たりも 48）
    nonisolated static let height: CGFloat = 48
    /// 下線を字からはみ出させる量（左右それぞれ）。札の字の左右の余白も同じ
    nonisolated static let underlineInset: CGFloat = 2
    /// 下線の角丸
    nonisolated static let underlineRadius: CGFloat = 1
    /// 押している間の字の白の濃さ
    nonisolated static let pressedOpacity: Double = 0.95
    /// 字の色の入れ替え（選んだ・押した・離した）の秒
    nonisolated static let colorFade: Double = 0.15
    /// 下線のばね（秒・減衰）
    nonisolated static let springResponse: Double = 0.28
    nonisolated static let springDamping: Double = 0.85
    /// 下の線の白の濃さ（ふだん 8%・上に留まったら 12%）
    nonisolated static func lineOpacity(stuck: Bool) -> Double { stuck ? 0.12 : 0.08 }

    /// 下線の長さ＝字の幅＋左右 2
    nonisolated static func underlineWidth(textWidth: CGFloat) -> CGFloat {
        textWidth + underlineInset * 2
    }

    /// 字（選んだ 600＝semibold・ほか 500＝medium。どちらも 15＝subheadline）
    static func font(selected: Bool) -> Font {
        selected ? JPFont.bodyEmphasis : Font.subheadline.weight(.medium)
    }
}

/// 札を押したときの字の色（押している間は白 95%、離すと 0.15 秒で戻す）。選び替えの色も 0.15 秒。
/// **0.15 秒の動きは色だけに閉じ込める**（`value:` 付きの `.animation` だと、中の下線のばねまで 0.15 秒の直線になる）
struct ProfileTabPressStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        // 0.15 秒の動きは字の色だけに付ける（`animation(_:body:)`）。中の下線の動き（ばね）には掛けない
        configuration.label
            .animation(.easeOut(duration: ProfileTabStyle.colorFade)) { content in
                content.foregroundStyle(ProfileTabBar.color(selected: selected, pressed: configuration.isPressed))
            }
    }
}
