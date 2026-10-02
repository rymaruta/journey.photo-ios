import SwiftUI

/// 件数バッジ（CLAUDE.md の owner の好み: **真鍮の塗り＋墨の数字＋黒 2px の縁**・数字は 12pt の等幅）。
///
/// 地図の写真のピン（同じ撮影地の枚数）と、ピンの束（`MapPinClusters`）の枚数で同じ部品を使う
/// （2026-10-02 のレビュー: 薄い素材の丸で、本文の最小 12pt も割っていた）
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(JPFont.mono(12, medium: true))
            .foregroundStyle(WebTheme.accentText)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(WebTheme.accentFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black, lineWidth: 2))
            // 数はピンの読み上げ名に入っている
            .accessibilityHidden(true)
    }
}
