import SwiftUI

/// 丸い端の小さな切り替え（板 11 の「すべて／写真／人…」・板 12 の「人気／新着／撮影日」）。
///
/// 選んでいる間は白地に黒い字、それ以外は薄い地に細い縁（`DesignSystem` の chip）。
/// **選択は読み上げにも渡す**（`.isSelected`）——色だけで伝えない。
///
/// 見た目の札は 36、上下 4 の余白まで押せる＝**押せる範囲は 44**（地図の切り替えと同じ形）。
/// 幅も 44 を下回らせない（「秋」「夜」のような1文字の札は字と左右の余白で約 41 にしかならない）。
/// 並べる側は `.padding(.vertical, -PillChip.tapSlack)` を外側（横の ScrollView の外）に付け、
/// 並びの見た目の間隔を前のまま保つ。
struct PillChip: View {

    let title: String
    let selected: Bool
    let action: () -> Void

    /// 札の上下に足す押せるだけの余白（36＋4＋4＝44）
    static let tapSlack: CGFloat = 4

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 36)
                .background(selected ? WebTheme.accentBackground : Color.white.opacity(0.05),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? WebTheme.accentBackground : Color.white.opacity(0.10), lineWidth: 1))
                .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted)
                // 余白で広げる——字を大きくしても札の上下に押せる余白が残る
                .padding(.vertical, Self.tapSlack)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
