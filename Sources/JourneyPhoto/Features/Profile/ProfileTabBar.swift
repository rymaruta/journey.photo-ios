import SwiftUI

/// プロフィールの下線の札（板 05c・31）。**マイページと人のページで同じもの**
/// ——人のページは以前、既定の `segmented` のままで見た目が食い違っていた。
///
/// **既定の `segmented` を使わない**——黒地の上で帯だけ明るく浮く
/// 板 05c: 下線の札（印＋名前・13px・高さ 44）。選んでいる札は白い字と
/// 下の 2pt の白い線、下に白12% の1本線。
///
/// **入らなければ4つとも印を外して字だけ**（大きい文字・狭い端末で「行きたい
/// 場所」が「…」で切れていた）。札ごとに決めると、印のある札と無い札が混ざり、
/// 押すたびに太字の幅で印が出たり消えたりする。並べ方は `TabRowLayout`（中身の
/// 幅＋余りの等分）——判定（理想の幅の和）と実際の幅を一致させる
struct ProfileTabBar: View {

    let tabs: [ProfileTab]
    @Binding var selection: ProfileTab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabRow(icons: true)
            tabRow(icons: false)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    private func tabRow(icons: Bool) -> some View {
        TabRowLayout {
            ForEach(tabs) { option in
                let selected = selection == option
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 6) {
                        if icons {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 16))
                                .accessibilityHidden(true)
                        }
                        tabLabel(option, selected: selected)
                    }
                    .foregroundStyle(selected ? Color.white : WebTheme.faint)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selected ? Color.white : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
                // ——以前は写真の上の「旅の記録」の札に付けていた
                .accessibilityIdentifier("profile.tab.\(option.rawValue)")
            }
        }
    }

    /// 名前。**幅は太字で測る**（選ぶたびに幅が変わって印が出入りしないように）。
    /// 太さは選んでいる札だけ変える
    private func tabLabel(_ option: ProfileTab, selected: Bool) -> some View {
        // 太字の幅で場所を取り、見える字は選んでいるときだけ太字
        Text(option.label)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                Text(option.label)
                    .font(.footnote.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
    }
}
