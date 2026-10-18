import SwiftUI

/// カバーが無いときの**自分のマイページだけ**の額縁（#304・板 52 MyPageCoverFrame・2026-10-18）。
///
/// 帯の場所に真鍮の細い縁（1pt・黒地の上なので真鍮）と明朝の「ここにあなたの1枚」。灰色の塗りは置かない・
/// 責める言い方をしない。押すとプロフィールの編集（カバーの候補・板 50）へ。**人のページには出さない**（黒のまま・板 31）
struct CoverFrameBand: View {

    /// 板 52: 高さ 150・左右 12・角 14
    nonisolated static let height: CGFloat = 150

    var body: some View {
        NavigationLink { ProfileEditView() } label: {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .accessibilityHidden(true)
                Text(L("ここにあなたの1枚", "Your photo goes here"))
                    .font(JPFont.display(17, relativeTo: .headline))
                Text(L("押すと、あなたの写真から選べます", "Tap to choose from your photos"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.top, 30)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: Self.height, alignment: .top)
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m)
                .strokeBorder(WebTheme.accent.opacity(0.8), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("カバーを選ぶ。ここにあなたの1枚", "Choose a cover. Your photo goes here"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("mypage.coverFrame")
    }
}
