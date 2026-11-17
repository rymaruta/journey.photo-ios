import SwiftUI

/// どの画面でも同じ見出し（板 01c・04・11）: **ロゴを左、右に［メッセージ］［お知らせ］［メニュー］**
/// （2026-11-12 に［探す］を外した——下のタブと同じ所へ行く入口が2つあった・案 第10章）。
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
    /// 受信箱に未読の会話がある（リクエストは数えない・`DMInboxStore.hasUnread`）
    var messagesUnread = false

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
        // **どのタブでも同じ中身**（メッセージ・お知らせ・メニュー）。前はホームだけ「探す」があり、右の枠の幅が
        // タブごとに違ったので、探す・マップではロゴが真ん中に寄って見えた（run 609 の 10・11・13）。
        // 探すのタブで押すと、探す口に字を打てるようにする（`SearchView`）
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 0) {
                // 2026-11-12 判断（デザインの案 第10章「どこに何を置くか」）: **見出しの「探す」は外した**（4 → 3つ）。
                // 下のタブの「探す」と同じ所へ行くだけで、入口が2つあった。どのタブでも同じ3つ（メッセージ・お知らせ・メニュー）
                // メッセージ（2026-11-10 札 #505・owner 承認「ベル（お知らせ）の左に吹き出し」）。絵は `bubble.left`
                // （紙飛行機ではない・owner 指示）。点は受信箱の未読だけ（リクエストでは出さない・画面案 A）
                Button {
                    AppHeaderInbox.openMessages()
                } label: {
                    Image(systemName: AppHeaderInbox.messagesSymbol)
                        .webToolbarIcon()
                        .overlay(alignment: .topTrailing) {
                            if messagesUnread { headerDot }
                        }
                        .appHeaderHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppHeaderInbox.messagesLabel(unread: messagesUnread))
                .accessibilityIdentifier("header.messages")
                Button(action: onOpenNotifications) {
                    Image(systemName: AppHeaderInbox.bellSymbol)
                        .webToolbarIcon()
                        .overlay(alignment: .topTrailing) {
                            // 未読があることだけ伝える（数は開けば分かる）
                            if unread > 0 { headerDot }
                        }
                        .appHeaderHitArea()
                }
                .buttonStyle(.plain)
                // v2（Main の板の aria-label）: 未読の点は色の合図なので、読み上げでも「未読あり」と言う
                .accessibilityLabel(AppHeaderInbox.bellLabel(unread: unread > 0))
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

extension AppHeaderItems {
    /// 未読の点。真鍮＝合図。黒の縁で、どの地の上でも点が割れない（`BrassDot`）。
    /// 板どおり絵の右上の角に（`toolbarBadgeOffset`）。点は絵の箱（幅 24）に付け、
    /// 当たりの 44 の枠には付けない（付けると絵から離れる）
    private var headerDot: some View {
        BrassDot()
            .offset(x: WebTheme.toolbarBadgeOffset.x, y: WebTheme.toolbarBadgeOffset.y)
    }
}

/// 吹き出し（メッセージ）とベル（お知らせ）の、絵・読み上げ・押したときの行き先（見出しとマイページで同じ）。
///
/// 2026-11-16 判断（使い勝手の見直し A3・owner「使い勝手にフォーカスして最高の UI にしたい」）: マイページは上の帯を
/// 隠しているので、DM もお知らせも1回で届かず、未読の点も見えなかった。マイページの表紙の右上（歯車の左）に
/// 同じ2つを置く（`AppHeaderGlassInbox`）。**ここを1つにして、見出しと写しを作らない**
enum AppHeaderInbox {
    /// 吹き出し（紙飛行機ではない・owner 指示・札 #505）
    static let messagesSymbol = "bubble.left"
    static let bellSymbol = "bell"

    /// 未読の点は色の合図なので、読み上げでも「未読あり」と言う（Main の板の aria-label）
    static func messagesLabel(unread: Bool) -> String {
        unread ? L("メッセージ（未読あり）", "Messages, unread") : L("メッセージ", "Messages")
    }

    static func bellLabel(unread: Bool) -> String {
        unread ? L("お知らせ（未読あり）", "Activity, unread") : L("お知らせ", "Activity")
    }

    /// 受信箱を開く（`RootView` の `tabRouter.messagesRequests` が受ける。どのタブからでも同じ画面）
    @MainActor static func openMessages() {
        TabRouter.shared.openMessages()
    }
}

/// マイページの表紙の右上のガラスの丸（吹き出し・ベル）。2026-11-16 判断（A3・模型 MBEk の A3）:
/// 歯車（`MyPageView.settingsButton`）と同じ 44pt のガラスの丸（黒55%＋ぼかし＋白10%の縁・`jpGlass`）、
/// 印は歯車と同じ 18pt medium の白、丸の間 8pt。未読の点（8pt に黒 2pt の縁。黒地は真鍮・カバー写真の上は白・`dotColor`）を丸の右上から 8pt 内側に。
/// 板 MyPage は右上に歯車だけ——ほかのタブの見出しと同じ入口を1回で届く所に足すため、板から足した
struct AppHeaderGlassInbox: View {
    let unread: Int
    var messagesUnread = false
    /// 丸の後ろがカバー写真か（ガラスの地に写真が透ける）。点の色を替える（`dotColor`）
    var onPhoto = false
    let onOpenNotifications: () -> Void

    var body: some View {
        HStack(spacing: AppHeaderGlassInbox.gap) {
            Button {
                AppHeaderInbox.openMessages()
            } label: {
                circle(AppHeaderInbox.messagesSymbol, dot: messagesUnread)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppHeaderInbox.messagesLabel(unread: messagesUnread))
            .accessibilityIdentifier("mypage.messages")
            Button(action: onOpenNotifications) {
                circle(AppHeaderInbox.bellSymbol, dot: unread > 0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppHeaderInbox.bellLabel(unread: unread > 0))
            .accessibilityIdentifier("mypage.notifications")
        }
    }

    /// 丸と丸の間（模型: gap 8）。歯車との間も同じ
    static let gap: CGFloat = JPSpace.xs
    /// 未読の点の色（2026-11-16 判断）。**カバー写真の上（ガラスの地に写真が透ける）は白、カバーが無い人（黒地）は真鍮。**
    /// 真鍮は黒い地の上だけ（写真の上では読めない）——CLAUDE.md の「写真の上に直に置くものは白」「ガラス越しに地図が透ける地は白
    /// （2026-10-02・地図の札のリンク）」と同じ理由。黒 2pt の縁はどちらも同じ（`BrassDot` と同じ形）
    static func dotColor(onPhoto: Bool) -> Color {
        switch dotTone(onPhoto: onPhoto) {
        case .white: return Color.white
        case .brass: return WebTheme.accent
        }
    }

    /// 点の色の種類（試験が Linux でも比べられるように、色そのものではなく種類で決める）
    enum DotTone: Equatable { case brass, white }

    static func dotTone(onPhoto: Bool) -> DotTone {
        onPhoto ? .white : .brass
    }

    /// 点を丸の右上の角から内へ寄せる量（模型: 12pt の点（縁込み）を上・右 6pt＝8pt の点の中心が 12pt 内側）
    static let dotInset: CGFloat = 8

    private func circle(_ symbol: String, dot: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.white)
            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            .jpGlass(in: Circle())
            .overlay(alignment: .topTrailing) {
                if dot {
                    Circle().fill(Self.dotColor(onPhoto: onPhoto)).frame(width: DMLook.dot, height: DMLook.dot)
                        .overlay(Circle().strokeBorder(WebTheme.background, lineWidth: 2).padding(-2))
                        .offset(x: -Self.dotInset, y: Self.dotInset)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Circle())
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
