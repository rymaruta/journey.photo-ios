import SwiftUI

/// 件数バッジ（CLAUDE.md の owner の好み: **真鍮の塗り＋墨の数字＋黒 2px の縁**・数字は 12pt の等幅）。
///
/// 地図の写真のピン（同じ撮影地の枚数）と、ピンの束（`MapPinClusters`）の枚数で同じ部品を使う
/// （2026-10-02 のレビュー: 薄い素材の丸で、本文の最小 12pt も割っていた）。
///
/// **v2（2026-10-14・Components 03）**: 塗りは真鍮そのもの（`accent` #C9A66B・墨で 9 超）、
/// 高さ 20・最小幅 20・左右 6・字は 12 の bold。黒の縁は**丸の外側に** 2（板の `box-shadow: 0 0 0 2px`）
/// ——内側に引くと真鍮が 16 に痩せる
struct CountBadge: View {
    let count: Int
    /// これを超えたら「99+」の形で出す（ストーリーの返信の数・2026-10-14）。無ければそのまま
    var maximum: Int? = nil

    /// 真鍮の丸の高さ・最小幅
    nonisolated static let size: CGFloat = 20
    nonisolated static let horizontalPadding: CGFloat = 6

    /// 出す字（`maximum` を超えたら「99+」）
    nonisolated static func text(count: Int, maximum: Int?) -> String {
        if let maximum, count > maximum { return "\(maximum)+" }
        return "\(count)"
    }

    var body: some View {
        Text(Self.text(count: count, maximum: maximum))
            .font(JPFont.number(JPTypeScale.caption, weight: .bold))
            .foregroundStyle(WebTheme.accentText)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(minWidth: Self.size, minHeight: Self.size)
            .background(WebTheme.accent, in: Capsule())
            // 外側の黒い縁（写真・地図の上で丸を切り離す）
            .padding(JPStroke.emphasis)
            .background(Color.black, in: Capsule())
            // 数はピンの読み上げ名に入っている
            .accessibilityHidden(true)
    }
}
