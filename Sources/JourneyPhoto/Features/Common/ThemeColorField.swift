import SwiftUI

/// プロフィールの色を選ぶ欄（Web の見本8色と同じ）。
struct ThemeColorField: View {

    @Binding var themeColor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("プロフィールの色", "Profile color"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // **押せる範囲は 44pt。** 丸（28）と「なし」の札の見た目はそのままで、周りの透明な枠で
            // 広げる。枠どうしが重ならないよう間は 0——丸と丸の見える間は 16、丸と札の間は前と同じ 8
            FlowLayout(spacing: 0) {
                ForEach(ThemeColor.presets, id: \.self) { hex in
                    swatch(hex)
                }
                // **選ばない**に戻せるようにする（押しても何も起きない状態を作らない）
                Button {
                    themeColor = ""
                } label: {
                    Text(L("なし", "None"))
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(themeColor.isEmpty ? WebTheme.accentText : WebTheme.muted)
                        .background(themeColor.isEmpty ? WebTheme.accentBackground : WebTheme.surface,
                                    in: Capsule())
                        // 札（高さ約26）の外側だけ広げる（`background` より後ろ＝見た目は変えない）
                        .webTappable()
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(themeColor.isEmpty ? .isSelected : [])
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let chosen = themeColor.lowercased() == hex
        return Button {
            themeColor = hex
        } label: {
            Circle()
                .fill(Color(hex: hex) ?? .gray)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.primary, lineWidth: chosen ? 2 : 0))
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("色 \(hex)", "Color \(hex)"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

extension Color {
    /// `#rrggbb` から。読めない値は nil（**既定色に化かさない**——
    /// 化かすと「保存できていないのに色が付いて見える」）。
    init?(hex: String) {
        guard let rgb = ThemeColor.rgb(hex) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
