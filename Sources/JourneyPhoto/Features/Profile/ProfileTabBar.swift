import SwiftUI

/// プロフィールの下線の札（板 v2 MyPage・UserProfile の「棚」のタブ）。マイページと人のページで同じ見た目。
///
/// **既定の `segmented` を使わない**——黒地の上で帯だけ明るく浮く。
///
/// **v2（2026-10-14）**: 名前だけ（印を外した）・15pt・高さ 44・名前の間 22 で**左に寄せる**。
/// 選んでいる札は**真鍮の字（semibold）と真鍮の 2pt の下線**（CLAUDE.md の owner の好み
/// 「選んでいるタブは真鍮」・板 v2 Components 02 の画面のタブ）、選んでいない札は text-3。
/// 下に白 8% の区切り線（`WebTheme.hairline`）。色だけで言わない——下線と太さと読み上げの「選択中」でも言う。
///
/// **入らなければ（大きい文字・狭い端末）幅いっぱいに割って縮める**（`TabRowLayout`・中身の幅＋余りの等分）。
/// 以前は印を外して入れていたが、v2 は初めから印が無いので、詰める段だけ残した
struct ProfileTabBar: View {

    let tabs: [ProfileTab]
    @Binding var selection: ProfileTab
    /// 名前の字の大きさ（`.subheadline` と同じだけ伸びる。既定 15）。縮める下限の計算に使う
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ProfileV2.tabGap) {
                ForEach(tabs) { option in tab(option, fill: false) }
                Spacer(minLength: 0)
            }
            TabRowLayout {
                ForEach(tabs) { option in tab(option, fill: true) }
            }
        }
        .padding(.horizontal, ProfileV2.gutter)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    /// 1つの札。下線は名前の幅（`fill` のときは割り当てた幅）
    private func tab(_ option: ProfileTab, fill: Bool) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            label(option, selected: selected)
                .foregroundStyle(ProfileTabBar.color(selected: selected))
                .frame(maxWidth: fill ? .infinity : nil, minHeight: WebTheme.minTapTarget)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? WebTheme.accent : Color.clear)
                        .frame(height: JPStroke.emphasis)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("profile.tab.\(option.rawValue)")
    }

    /// 名前の色。選んでいる札は真鍮（黒地の上だけ・マイページも人のページも黒地）
    @MainActor
    static func color(selected: Bool) -> Color {
        selected ? WebTheme.accent : WebTheme.text3
    }

    /// 名前。**幅は太字で測る**（選ぶたびに幅が変わって並びが揺れないように）。
    /// 太さは選んでいる札だけ変える
    private func label(_ option: ProfileTab, selected: Bool) -> some View {
        Text(option.label)
            .font(JPFont.bodyEmphasis)
            .lineLimit(1)
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                Text(option.label)
                    .font(selected ? JPFont.bodyEmphasis : JPFont.body)
                    .lineLimit(1)
                    // **縮めても 12pt まで**（本文の最小）
                    .minimumScaleFactor(WebTheme.minimumScale(forTextSize: labelSize))
            }
    }
}
