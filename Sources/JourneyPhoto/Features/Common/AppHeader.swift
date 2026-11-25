import SwiftUI
import UIKit

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

    /// 右の当たりどうしの間（2026-11-25 判断・人間工学の確かめ 観点3「中心の間 50pt 以上・間 6pt 以上」）
    nonisolated static let buttonGap: CGFloat = 6

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
        //
        // 2026-11-25 判断（人間工学の確かめ 観点3・Artifact「人間工学アーティファクト」の A）: **当たりの間を 6pt ずつ空ける。**
        // 44pt の当たりが隙間なく接していると、いちばん遠い右上の角で押す目安の円（9.2mm・約55pt）が隣にかかり、
        // 押し間違えると隣の画面が開く。当たりは 44 のまま、絵の大きさ（17pt・箱 24）も変えない。中心の間は 50pt。
        // 帯は 18pt 長くなるので、字つきの「AI に頼む」を出す幅（`AskEntryButton.labelMinWindowWidth`）を上げ、
        // 375pt の iPhone ではロゴを少し深く縮められるようにした（`AppLogo.headerMinimumScale`）。
        // 未読の点は絵の箱（`webToolbarIcon`）に付いていて、当たりの外の間には付かないので、位置は変わらない
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: Self.buttonGap) {
                // 2026-11-21 判断（札 #675・案1）: 「✦ AI に頼む」をどのタブの帯にも（ホーム、探す、マップ）。押すと AI の画面
                AskEntryButton()
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

/// 上の帯の「✦ AI に頼む」（札 #675・2026-11-21 判断・Artifact「AI に頼む 独立の案」の案1）。
/// 字つきの小さな札（2026-11-21 判断: 帯のガラスの下を写真が流れるので、字と印は白。初めての日の光だけ真鍮）。大きな字（アクセシビリティの大きさ）では帯に収まらないので ✦ だけにする。
/// 読み上げはどちらも「AI に頼む」。当たりは 44pt
struct AskEntryButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 初めての日に一度だけ光る（前は探すの欄の縁を光らせていた・案1 の「今の欄の光り方を移す」）
    @State private var glow = false
    /// 光らせたかの鍵（端末に覚える。#652 の欄の光と同じ鍵）
    static let glowKey = "journey-photo-ask-glow-shown"

    /// 字と印の色（白。写真の上に重なるガラスの帯なので真鍮にしない）
    static let tint = WebTheme.text

    /// 字を出せる窓の幅。2026-11-21 判断（確かめ役の指摘「狭い iPhone でロゴが押されないか」）の配置の計算:
    /// 右の枠は ✦ の字つき 約90 ＋ メッセージ、お知らせ、メニューの 44×3 ＝ 約222。左右の余白 16×2 と枠の間 約16 を引くと、
    /// ロゴ（絵 19 ＋ 間 8 ＋「Journey Photo」22pt 約150、縮めて 0.8 で約147）に残るのは 375pt の iPhone SE で約105、
    /// 390pt で約120 しかなく、ロゴが切れる。✦ だけ（44）なら 375pt でも約151 残る。400pt 以上（402、430、440）は字つき
    ///
    /// 2026-11-25 判断（当たりの間 6pt×3 を足した・`AppHeaderItems.buttonGap`）: 右の枠は字つきで約240、✦ だけで約194。
    /// ロゴの縮めた幅は約132（絵 19 ＋ 間 8 ＋ 字 約150×0.7・`AppLogo.headerMinimumScale`）。字つきは 48＋240＋132＝420pt 以上
    /// （430、440）だけにし、402pt は ✦ だけにする（字つきだと残りが約114 でロゴが切れる）。375pt は ✦ だけで残り約133
    ///
    /// 2026-11-25 判断（Mac run 1818 の 440pt の絵と寸法で上の見積もりを改めた）: 440pt でも帯のガラスに使えるのは約209pt
    /// （ロゴの右 約195 から右の余白 21 まで）で、字つきの並び（約247）が入らず、✦ がガラスの外のロゴの隣にはみ出し、
    /// 「AI に頼む」の字が吹き出しにかかった（「AI に頼む」の当たりは 54pt に押し縮められていた）。✦ だけ（並び 194）なら入る。
    /// iPhone（〜440pt）はどれも ✦ だけにし、字つきは約480pt 以上の広い窓（iPad など）だけにする。読み上げは今までどおり「AI に頼む」
    static let labelMinWindowWidth: CGFloat = 480

    /// 字を出さず ✦ だけにするか（大きな字のとき、狭い iPhone のとき）。窓の幅が読めなければ字を出す
    nonisolated static func iconOnly(largeText: Bool, windowWidth: CGFloat? = nil) -> Bool {
        if largeText { return true }
        if let windowWidth, windowWidth > 0, windowWidth < labelMinWindowWidth { return true }
        return false
    }

    /// 窓の幅（読めなければ nil）
    @MainActor
    static func windowWidth() -> CGFloat? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
                return window.bounds.width
            }
        }
        return nil
    }

    var body: some View {
        Button {
            TabRouter.shared.openAsk()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                if !Self.iconOnly(largeText: dynamicType >= .xxLarge, windowWidth: Self.windowWidth()) {
                    Text(AskEntry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            // 2026-11-21 判断（確かめ役の指摘）: 帯はガラスで、下を写真が流れる。真鍮は黒地の上だけの決まりなので、字と印は白
            .foregroundStyle(AskEntryButton.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .overlay(
                Capsule()
                    .strokeBorder(WebTheme.accent.opacity(glow ? 1 : 0), lineWidth: JPStroke.hairline)
                    .shadow(color: WebTheme.accent.opacity(glow ? 0.45 : 0), radius: 5)
            )
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AskEntry.buttonLabel)
        .accessibilityIdentifier("header.ask")
        .onAppear { glowOnceIfFirst() }
    }

    /// 初めて見えたときだけ一度光らせる（1.6 秒・動きを減らす設定と UI テストでは光らせない）
    private func glowOnceIfFirst() {
        guard !UserDefaults.standard.bool(forKey: Self.glowKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.glowKey)
        guard !reduceMotion, !AskFixture.isOn, !PerfRecorder.shared.isEnabled else { return }
        withAnimation(.easeOut(duration: 0.55)) { glow = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.easeOut(duration: 1.0)) { glow = false }
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

/// 吹き出し（メッセージ）とベル（お知らせ）の、絵・読み上げ・押したときの行き先（見出しの右の2つ）。
///
/// 2026-11-16（A3）でマイページの表紙の右上にも同じ2つを置いたが、2026-11-18 owner 判断「マイページにそれは入れなくていい」で
/// 外した（マイページの右上は歯車だけ・板 MyPage どおり）。値の口はここに1つのまま残す
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

extension View {
    /// 見出しの右の3つの当たり（44×44）。絵の大きさ（`webToolbarIcon`・幅 24）は変えず、
    /// 押せる範囲だけを 44 にする（2026-10-21・当たりが 25〜27pt しかなかった）
    func appHeaderHitArea() -> some View {
        self
            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            .contentShape(Rectangle())
    }
}
