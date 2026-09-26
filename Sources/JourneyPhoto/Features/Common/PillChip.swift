import SwiftUI

/// 丸い端の小さな切り替え（板 11 の「すべて／写真／人…」・板 12 の「人気／新着／撮影日」）。
///
/// 選んでいる間は白地に黒い字、それ以外は薄い地に細い縁（`DesignSystem` の chip）。
/// **選択は読み上げにも渡す**（`.isSelected`）——色だけで伝えない。
struct PillChip: View {

    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(selected ? WebTheme.accentBackground : Color.white.opacity(0.05),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? WebTheme.accentBackground : Color.white.opacity(0.10), lineWidth: 1))
                .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
