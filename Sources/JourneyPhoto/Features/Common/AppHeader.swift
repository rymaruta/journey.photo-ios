import SwiftUI

/// どの画面でも同じ見出し（板 01c・04・11）: **ロゴを左、右に［お知らせ］［メニュー］**。
/// ホームだけ、お知らせの左に「探す」を置く（板 01c。探す・マップの板には無い）。
///
/// 揃える前は、ホームだけ「Journey Photo」で、さがすは「さがす」、
/// マップは「マップ」——**タブを移るたびに別のアプリに見えていた**
/// （実機の絵で確認・run 37）。
///
/// **探す・マップだけロゴを外したことがある（PR #10）が、戻した**（2026-09-26）。
/// 外してもバーの高さは変わらず、左上が空いた帯になっただけだった
/// （run 96 の絵）。owner も前の方が良いと判断。アーティファクトも v28 でロゴに戻した。
///
/// **右端は自分のアイコンではなくメニュー（≡）**（2026-09-26 owner「ヘッダーの
/// ハンバーガーは残す」・板 01d）。マイページへは下の札とメニューから行ける。
///
/// **ホームにあった地図のアイコンは外した。** 下のタブに「マップ」が
/// あるので、同じ場所への入口が2つあった（モックにも無い）。
// `ToolbarContent` は `View` と違って主アクタに縛られていないので、
// 中で SwiftUI の部品を組むには自分で名乗る
@MainActor
struct AppHeaderItems: ToolbarContent {

    let unread: Int
    /// お知らせの左に「探す」を置くか（ホームだけ）
    var showsSearch = false
    let onOpenNotifications: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        // ロゴ。**`navigationTitle` の文字の代わりに置く**——モックは
        // どの画面も記号＋ワードマークで、字だけだと別のアプリに見える。
        // **左寄せ**（板 01c・04・11）
        ToolbarItem(placement: .topBarLeading) {
            AppLogo()
        }
        // **中央は空けておく。** ロゴを左へ移したので、何も置かないと各画面の
        // `navigationTitle`（「探す」「マップ」——戻る文字と読み上げのために持つ）が
        // バーの中央に文字で出てしまう。設定の画面と同じく見えない部品で塞ぐ
        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
        if showsSearch {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // 下の札の「探す」へ移る（同じ画面をここに積まない）
                    TabRouter.shared.openSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .webToolbarIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Navigation.searchTab)
                .accessibilityIdentifier("header.search")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onOpenNotifications) {
                Image(systemName: "bell")
                    .webToolbarIcon()
                    .overlay(alignment: .topTrailing) {
                        // 未読があることだけ伝える（数は開けば分かる）
                        if unread > 0 {
                            // 真鍮＝合図。黒の縁で、どの地の上でも点が割れない
                            Circle().fill(WebTheme.accent).frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(WebTheme.background, lineWidth: 2)
                                    .padding(-2))
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
                TabRouter.shared.openMenu()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .webToolbarIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("メニュー", "Menu"))
            .accessibilityIdentifier("header.menu")
        }
    }
}
