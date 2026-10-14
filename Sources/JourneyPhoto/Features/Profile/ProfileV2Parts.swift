import SwiftUI

/// **v2 のプロフィールまわりの値と小さな部品**（Artifact「デザインシステム v2」の MyPage・UserProfile・
/// FollowList・ProfileEdit・Shelf の板、2026-10-14）。
///
/// マイページと人のページ・フォロー一覧で同じ形を使う所だけをここに置く。値は土台（`JPSpace`・
/// `JPHeight`・`JPStroke`・`WebTheme`）から取り、新しい色・大きさは作らない。
/// 値を `nonisolated static` で持つのは、Linux のテストで見張るため（`ProfileV2DesignTests`）。
enum ProfileV2 {

    /// 写真の格子のすき間（板 v2 の `.g3`: gap 2）。v1 は 4 だった
    nonisolated static let gridSpacing: CGFloat = 2
    /// 写真の格子の縦横比（板 v2 の `.g3 a`: aspect-ratio 4/5・縦長）。v1 は正方形
    nonisolated static let gridAspect: CGFloat = 4.0 / 5.0
    /// 写真の格子の列（板 v2: 3 列）
    nonisolated static let gridColumns = 3

    /// 画面の左右の端（v1 は 20。v2 は全画面 16＝`JPSpace.gutter`）
    nonisolated static let gutter: CGFloat = JPSpace.gutter

    /// 見出しの横の線のボタン（「プロフィールを編集」）の見た目の高さ（板 v2: 36）。当たりは 44
    nonisolated static let headerButtonHeight: CGFloat = JPHeight.inlineButton
    /// 人のページの「フォローする」の見た目の高さ（板 v2 UserProfile: 40）。当たりは 44
    nonisolated static let followButtonHeight: CGFloat = 40

    /// 見た目の高さ `visible` のものを、当たり 44 まで上下に広げる量（それぞれ）
    nonisolated static func tapSlack(visible: CGFloat) -> CGFloat {
        max(0, (WebTheme.minTapTarget - visible) * 0.5)
    }

    /// 下線の札の名前と名前の間（板 v2 の `nav`: gap 22）
    nonisolated static let tabGap: CGFloat = 22

    /// 写真の格子の列
    static var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: gridColumns)
    }
}

/// 数の札（板 v2 の `.st`: 数字が上・12pt の text-3 の名前が下）。マイページの3列と人のページの並びで同じ形。
///
/// **数字は `JPFont.statNumber`（SF の title3 semibold）のまま**——板は 20 の regular だが、
/// 2026-10-02 の owner の好み（白い大きい数字を SF らしく締める）が板より優先（CLAUDE.md）。
/// 数は合図ではないので白（真鍮にしない）
struct ProfileStat: View {

    /// nil は読み込み中。**数を出さずに高さだけ取る**（出たときに並びが動かない）
    let value: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "0")
                .font(JPFont.statNumber)
                .foregroundStyle(WebTheme.foreground)
                .opacity(value == nil ? 0 : 1)
                .accessibilityHidden(value == nil)
            Text(label)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .lineLimit(1)
        }
    }
}

/// 見出しの横の線のボタン（「プロフィールを編集」・板 v2 Components 01 の副ボタンの形）。
/// 見た目は 36・透明の地に白 14% の縁（`WebTheme.line`）・13pt semibold。**当たりは 44**。
/// 形は土台の `jpOutlineButton(.inline)`（2026-10-14 判断: 線の小ボタンを1つに寄せた）
struct ProfileOutlinePill: View {

    let title: String

    var body: some View {
        Text(title)
            .jpOutlineButton(.inline)
    }
}

/// 人のページの「フォローする」／「フォロー中 ▾」（板 v2 UserProfile）。
///
/// **形で分ける**（色だけで状態を言わない）: フォローしていなければ白 94% の塗りに墨の字、
/// フォロー中は透明の地に白 14% の線と下向きの印（押すと外す確認が出ることの手がかり）。
/// 人のページは写真のある画面なので主ボタンは白（CLAUDE.md の owner の好み）。
/// 見た目は 40・**当たりは 44**
struct ProfileFollowButtonLabel: View {

    let isFollowing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(isFollowing ? L("フォロー中", "Following") : L("フォローする", "Follow"))
                .font(JPFont.bodyEmphasis)
                .lineLimit(1)
            if isFollowing {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isFollowing ? WebTheme.foreground : WebTheme.accentText)
        .padding(.horizontal, isFollowing ? 18 : 22)
        .frame(minHeight: ProfileV2.followButtonHeight)
        .background(isFollowing ? Color.clear : WebTheme.accentBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(isFollowing ? WebTheme.line : Color.clear, lineWidth: JPStroke.hairline))
        .padding(.vertical, ProfileV2.tapSlack(visible: ProfileV2.followButtonHeight))
        .contentShape(Rectangle())
    }
}

extension View {
    /// 一覧（`List`）の行を v2 の作法にする（板 v2 Albums・FollowList: 左右 16・地は黒・系統の区切り線は出さない）。
    /// `divider` の行だけ下に白 8% の線（板の `.al`・`.pr`）
    func profileListRow(divider: Bool = false) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                if divider {
                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: ProfileV2.gutter, bottom: 4, trailing: ProfileV2.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
