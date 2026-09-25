import SwiftUI

/// どの画面でも同じ見出し（モック1・3・9・10 はどれも
/// **ロゴ ＋ 通知 ＋ 自分のアイコン**）。
///
/// 揃える前は、ホームだけ「Journey Photo」で、さがすは「さがす」、
/// マップは「マップ」——**タブを移るたびに別のアプリに見えていた**
/// （実機の絵で確認・run 37）。
///
/// **ホームにあった地図のアイコンは外した。** 下のタブに「マップ」が
/// あるので、同じ場所への入口が2つあった（モックにも無い）。
// `ToolbarContent` は `View` と違って主アクタに縛られていないので、
// 中で SwiftUI の部品を組むには自分で名乗る
@MainActor
struct AppHeaderItems: ToolbarContent {

    let unread: Int
    /// 自分のアイコン。**値で受け取る**——`ToolbarContent` は `View` では
    /// ないので、`@EnvironmentObject` が注ぎ込まれる保証が無い
    /// （注がれないと実機で「見つからない」と言って落ちる。手元の模型は
    /// 素通しするので、ここでは絶対に出ない）
    let avatarURL: URL?
    let onOpenNotifications: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        // ロゴ。**`navigationTitle` の文字の代わりに置く**——モックは
        // どの画面も記号＋ワードマークで、字だけだと別のアプリに見える
        ToolbarItem(placement: .principal) {
            AppLogo()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onOpenNotifications) {
                Image(systemName: "bell")
                    .webToolbarIcon()
                    .overlay(alignment: .topTrailing) {
                        // 未読があることだけ伝える（数は開けば分かる）
                        if unread > 0 {
                            Circle().fill(Color.pink).frame(width: 8, height: 8)
                                .offset(x: -8, y: 10)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("お知らせ", "Activity"))
            .accessibilityIdentifier("header.notifications")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // **押すとマイページの札へ移る。** 同じ画面をこの中に
                // もう1つ積まない（戻る先が2通りになる）
                TabRouter.shared.openMyPage()
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("マイページ", "My page"))
        }
    }

    /// 自分のアイコン。**未ログインなら人型**（誰かの顔を借りない）
    @ViewBuilder
    private var avatar: some View {
        if let url = avatarURL {
            RemoteImage(url: url, placeholderSymbol: "person.crop.circle.fill")
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
        } else {
            Image(systemName: "person.crop.circle")
                .webToolbarIcon()
        }
    }
}
