import SwiftUI

/// どの画面でも同じ見出し（板 01c・04・11）: **ロゴを左、右に［探す］［お知らせ］［メニュー］**。
/// 前はホームだけ「探す」を置いていた（板 01c）が、2026-10-21 にどのタブも同じ3つにそろえた
/// （右の枠の幅がタブごとに違い、ロゴの位置がずれて見えた・全画面の点検 run 609）。
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
/// **右の3つの絵は 17pt regular・箱は幅 24・高さ 44**（2026-10-14 owner「デカすぎる」。
/// 22pt semibold ＋ 44 の枠で、iOS 26 のガラスの帯が太っていた。`webToolbarIcon` の注記）。
///
/// **ホームにあった地図のアイコンは外した。** 下のタブに「マップ」が
/// あるので、同じ場所への入口が2つあった（モックにも無い）。
// `ToolbarContent` は `View` と違って主アクタに縛られていないので、
// 中で SwiftUI の部品を組むには自分で名乗る
@MainActor
struct AppHeaderItems: ToolbarContent {

    let unread: Int
    let onOpenNotifications: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        // ロゴ。**`navigationTitle` の文字の代わりに置く**——モックは
        // どの画面も記号＋ワードマークで、字だけだと別のアプリに見える。
        // **左寄せ**（板 01c・04・11）。
        //
        // 🔴 **`.topBarLeading` に置かない。** iOS 26 は左右の枠の中身をボタンとして
        // ガラスの丸に入れるので、ロゴが丸に押し込まれて「J」までしか見えなかった
        // （1.0.16・CI の絵と owner の実機で確認）。**中央の枠に置き、枠いっぱいに
        // 広げて左へ寄せる**——中央の枠はガラスを持たず、以前（〜1.0.12）もここで
        // 正しく描けていた。中央を埋めるので、各画面の `navigationTitle`（戻る文字と
        // 読み上げのために持つ）が文字で出ることもない
        ToolbarItem(placement: .principal) {
            AppLogo()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 🔴 **右の3つは1つの枠に、44×44 の当たりで並べる**（2026-10-21 判断・全画面の点検 run 609）。
        // 1つずつ別の枠に置くと、iOS 26 は枠ごとに余白を足してガラスの帯へ入れるので、当たりを 44 に
        // 広げると帯が太る（「デカすぎる」）。幅 24 に詰めた結果、当たりは 25〜27pt しかなかった。
        // 1つの枠の中で 44 ずつ並べると、帯の長さは前とほぼ同じ（前は絵の中心の間が約 52pt、いまは 44）のまま、
        // どのボタンも 44pt 押せる。当たりは並びの寸法の中にしか作れない（`webToolbarIcon` の注記・run 432）
        //
        // **どのタブでも同じ中身**（探す・お知らせ・メニュー）。前はホームだけ「探す」があり、右の枠の幅が
        // タブごとに違ったので、探す・マップではロゴが真ん中に寄って見えた（run 609 の 10・11・13）。
        // 探すのタブで押すと、探す口に字を打てるようにする（`SearchView`）
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 0) {
                Button {
                    // 下の札の「探す」へ移る（同じ画面をここに積まない）
                    TabRouter.shared.openSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .webToolbarIcon()
                        .appHeaderHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Navigation.searchTab)
                .accessibilityIdentifier("header.search")
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
                                    // 板どおり絵の右上の角に（`toolbarBadgeOffset`）。点は絵の箱（幅 24）に付け、
                                    // 当たりの 44 の枠には付けない（付けると絵から離れる）
                                    .offset(x: WebTheme.toolbarBadgeOffset.x,
                                            y: WebTheme.toolbarBadgeOffset.y)
                            }
                        }
                        .appHeaderHitArea()
                }
                .buttonStyle(.plain)
                // v2（Main の板の aria-label）: 未読の点は色の合図なので、読み上げでも「未読あり」と言う
                .accessibilityLabel(unread > 0 ? L("お知らせ（未読あり）", "Activity, unread") : L("お知らせ", "Activity"))
                .accessibilityIdentifier("header.notifications")
                Button {
                    TabRouter.shared.openMenu()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .webToolbarIcon()
                        .appHeaderHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("メニュー", "Menu"))
                .accessibilityIdentifier("header.menu")
            }
        }
    }
}

extension View {
    /// 見出しの右の3つの当たり（44×44）。絵の大きさ（`webToolbarIcon`・幅 24）は変えず、
    /// 押せる範囲だけを 44 にする（2026-10-21・当たりが 25〜27pt しかなかった）
    func appHeaderHitArea() -> some View {
        self
            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            .contentShape(Rectangle())
    }
}
