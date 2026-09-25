import SwiftUI

/// プロフィールの色を選ぶ欄（Web の見本8色と同じ）。
struct ThemeColorField: View {

    @Binding var themeColor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("プロフィールの色", "Profile color"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
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
