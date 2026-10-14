import SwiftUI

/// 丸い端の小さな切り替え（板 11 の「すべて／写真／人…」・板 12 の「人気／新着／撮影日」）。
///
/// 選んでいる間は白地に黒い字、それ以外は薄い地に細い縁（`DesignSystem` の chip）。
/// **選択は読み上げにも渡す**（`.isSelected`）——色だけで伝えない。
///
/// **v2（2026-10-14・Components の chip・TagPhotos・Notifications の板）**:
/// 見た目は 34・左右 14・字 13。地は白 7%（`WebTheme.surface`）に白 8% の縁（`hairline`）。
/// **選ぶと白 94% の塗り＋墨の字＋チェックの印**——色だけでなく形でも選んだことを見せる。
/// 件数（`count`）を添えるときは灰（text-3）の等幅の数字で沈める（数は合図ではない・板 Search の `.chip .c`）。
///
/// 見た目の札は 34、上下 5 の余白まで押せる＝**押せる範囲は 44**（地図の切り替えと同じ形）。
/// 幅も 44 を下回らせない（「秋」「夜」のような1文字の札は字と左右の余白で約 41 にしかならない）。
/// 並べる側は `.padding(.vertical, -PillChip.tapSlack)` を外側（横の ScrollView の外）に付け、
/// 並びの見た目の間隔を前のまま保つ。
struct PillChip: View {

    let title: String
    /// 添える件数（タグの枚数など）。nil なら出さない
    var count: Int?
    let selected: Bool
    let action: () -> Void

    /// 見た目の札の高さ（板の chip 34。土台の `JPHeight` に無いのでここに持つ）
    nonisolated static let height: CGFloat = 34
    /// 札の上下に足す押せるだけの余白（34＋5＋5＝44）
    nonisolated static let tapSlack: CGFloat = (WebTheme.minTapTarget - height) / 2

    init(title: String, count: Int? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: JPSpace.xxs) {
                if selected {
                    // 選んだ印（板: 白の塗り＋チェック）。色だけに頼らない
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(JPFont.footnote.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(JPFont.number(JPTypeScale.footnote, weight: .regular, relativeTo: .footnote))
                        // 選んだ札の上は墨のまま（白の上の灰は沈みすぎる）
                        .foregroundStyle(selected ? WebTheme.accentText : WebTheme.text3)
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: WebTheme.minTapTarget, minHeight: Self.height)
            .background(selected ? WebTheme.accentBackground : WebTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : WebTheme.hairline,
                                            lineWidth: JPStroke.hairline))
            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.text)
            // 余白で広げる——字を大きくしても札の上下に押せる余白が残る
            .padding(.vertical, Self.tapSlack)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
