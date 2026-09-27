import SwiftUI

/// フォローの札の見た目（板 02・31）。人のページと写真の詳細で同じ形。
///
/// 高さ 36・13px の太字。まだなら白地に墨、フォロー中なら白12% の地に
/// 白の字と白18% の縁。**見た目は 36pt、押せる高さは 44pt**（上下に 4pt ずつ）。
///
/// 押したときの動き（外すときの確認など）は呼ぶ側が持つ。文言も呼ぶ側
/// ——人のページは「フォローする」、写真の詳細は短い「フォロー」。
/// フォロー一覧の行（`FollowListView`）は地の無い別の形なので、ここを使わない
struct FollowPill: View {

    let title: String
    let isFollowing: Bool

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isFollowing ? Color.white : WebTheme.accentText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 36)
            .background(isFollowing ? Color.white.opacity(0.12) : WebTheme.accentBackground,
                        in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(isFollowing ? 0.18 : 0),
                                            lineWidth: 1))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}
