import StoreKit
import SwiftUI

/// 設定の「Pro」の節（板 43・2026-10-09）。**設定のいちばん上**（板の並び: Pro → お知らせ → …）。
///
/// 板のとおりの4行:
/// 1. 「Journey Photo Pro」（Pro マーク 20pt）。2行目は「月 ¥500 · 次の更新 2026.11.09 · App Store で管理」。
///    Pro でないと読めたら押すと Pro の案内（板 63）、Pro か、読めていなければ App Store の定期購入の管理
/// 2. 「サポーター証」（真鍮のカードの線の絵）。「No. 0001 · 手に取って回せます」。**番号を持つ人だけ**
///    （やめても番号は残るので、Pro でなくなっても出る・板 64 の注記）
/// 3. 「名前の横のバッジと Pro マーク」（真鍮のメダルの線の絵）。「初期ユーザー · Pro マークは 絞り羽根」
/// 4.「保存した旅」（電波なしで使える旅・板 72e）。「2 件 · 48 MB」。Pro か、保存した旅があるときだけ
///
/// 板の「お知らせ」の節にある「光と天気の知らせ」は、この節の最後に置く（`LightAlertSettingsRows` の注記）。
///
/// **v2（2026-10-14・板 Settings）**: 節の見出しは真鍮の眉ラベル（`SettingsGroup`）。行の絵は外し、
/// 先頭の Pro の行の Pro マークだけ残す（`ProSettingsLayout.markSide`）
struct ProSettingsSection: View {

    /// 自分のプロフィール（読めていなければ nil＝Pro かどうか分からない。案内は出さない）
    let profile: UserProfile?

    @EnvironmentObject private var store: StoreService
    @State private var showPaywall = false
    @State private var showManage = false
    @State private var showNameSide = false

    private var isPro: Bool { profile?.isPro ?? false }
    /// Pro かどうか。プロフィールが読めていなければ nil（`ProStatusText.settingsAction` の注記）
    private var knownPro: Bool? { profile?.isPro }
    private var action: ProStatusText.SettingsAction { ProStatusText.settingsAction(isPro: knownPro) }

    var body: some View {
        SettingsGroup("Pro") {
            proRow
            if let profile, let supporter = profile.supporterInfo {
                JPCardDivider()
                NavigationLink { SupporterCardView(profile: profile) } label: {
                    JPRowLabel(title: L("サポーター証", "Supporter card"),
                               detail: ProStatusText.supporterDetail(number: supporter.number))
                }
                .buttonStyle(JPRowButtonStyle())
                .accessibilityIdentifier("settings.supporterCard")
            }
            if profile != nil {
                JPCardDivider()
                Button { showNameSide = true } label: {
                    JPRowLabel(title: L("名前の横のバッジと Pro マーク", "Badge & Pro mark next to your name"),
                               detail: profile.map { ProStatusText.nameSideDetail($0) })
                }
                .buttonStyle(JPRowButtonStyle())
                .accessibilityIdentifier("settings.nameSide")
            }
            // 4. 保存した旅（板 72e・2026-10-09）。Pro が切れても、保存した旅があれば出す（見る・消すは誰でも）
            OfflineSavedSettingsRow(isPro: isPro)
            LightAlertSettingsRows(profile: profile)  // 光と天気の知らせ（第3段階・2026-10-09）
        }
        .task {
            // 値段・次の更新日を出すため（読めなければ板の値段のまま）
            await store.loadProducts()
            await store.refreshSubscription()
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .sheet(isPresented: $showNameSide) {
            if let profile { NameSideBadgeView(profile: profile) }
        }
    }

    private var proRow: some View {
        Button {
            switch action {
            case .manage: showManage = true
            case .paywall: showPaywall = true
            }
        } label: {
            JPRowLabel(title: "Journey Photo Pro",
                       detail: ProStatusText.settingsDetail(isPro: knownPro, state: store.subscription,
                                                            monthlyPrice: store.product(.monthly)?.displayPrice),
                       icon: AnyView(ProMark(style: .iris, side: ProSettingsLayout.markSide)))
        }
        .buttonStyle(JPRowButtonStyle())
        .accessibilityHint(action == .manage ? L("App Store で定期購入を管理します", "Manage your subscription in the App Store")
                                 : L("Pro の案内を開きます", "Opens the Pro page"))
        .accessibilityIdentifier("settings.pro")
    }
}

/// 設定の Pro の節の見た目（v2 の板 Settings）
enum ProSettingsLayout {
    /// Pro の行の先頭の Pro マーク。板は 28 だが、行の絵の箱（`JPRowLabel` の幅 24）に収まる 24 にする
    /// （2026-10-14 判断: 箱を広げると、ほかの行と名前の頭がずれる）。15 以上なので大きい版（羽根の線あり）
    static let markSide: Double = 24
}
