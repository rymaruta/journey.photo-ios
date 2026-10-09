import StoreKit
import SwiftUI

/// 設定の「Pro」の節（板 43・2026-10-09）。**設定のいちばん上**（板の並び: Pro → お知らせ → …）。
///
/// 板のとおりの3行:
/// 1. 「Journey Photo Pro」（Pro マーク 20pt）。2行目は「月 ¥500 · 次の更新 2026.11.09 · App Store で管理」。
///    Pro でなければ押すと Pro の案内（板 63）、Pro なら App Store の定期購入の管理
/// 2. 「サポーター証」（真鍮のカードの線の絵）。「No. 0001 · 手に取って回せます」。**番号を持つ人だけ**
///    （やめても番号は残るので、Pro でなくなっても出る・板 64 の注記）
/// 3. 「名前の横のバッジと Pro マーク」（真鍮のメダルの線の絵）。「初期ユーザー · Pro マークは 絞り羽根」
///
/// 板の「お知らせ」の節にある「光と天気の知らせ」は、この節の最後に置く（`LightAlertSettingsRows` の注記）。
struct ProSettingsSection: View {

    /// 自分のプロフィール（読めていなければ nil＝Pro ではない扱いで出す）
    let profile: UserProfile?

    @EnvironmentObject private var store: StoreService
    @State private var showPaywall = false
    @State private var showManage = false
    @State private var showNameSide = false

    private var isPro: Bool { profile?.isPro ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            JPSectionTitle("Pro")
            JPCard {
                proRow
                if let profile, let supporter = profile.supporterInfo {
                    JPCardDivider()
                    NavigationLink { SupporterCardView(profile: profile) } label: {
                        JPRowLabel(title: L("サポーター証", "Supporter card"),
                                   detail: ProStatusText.supporterDetail(number: supporter.number),
                                   icon: AnyView(ProIconView(icon: .card, side: 20, color: WebTheme.accent, lineWidth: 1.7)))
                    }
                    .buttonStyle(JPRowButtonStyle())
                    .accessibilityIdentifier("settings.supporterCard")
                }
                if profile != nil {
                    JPCardDivider()
                    Button { showNameSide = true } label: {
                        JPRowLabel(title: L("名前の横のバッジと Pro マーク", "Badge & Pro mark next to your name"),
                                   detail: profile.map { ProStatusText.nameSideDetail($0) },
                                   icon: AnyView(ProIconView(icon: .medal, side: 20, color: WebTheme.accent, lineWidth: 1.7)))
                    }
                    .buttonStyle(JPRowButtonStyle())
                    .accessibilityIdentifier("settings.nameSide")
                }
                LightAlertSettingsRows(profile: profile)  // 光と天気の知らせ（第3段階・2026-10-09）
            }
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
            if isPro { showManage = true } else { showPaywall = true }
        } label: {
            JPRowLabel(title: "Journey Photo Pro",
                       detail: ProStatusText.settingsDetail(isPro: isPro, state: store.subscription),
                       icon: AnyView(ProMark(style: .iris, side: 20)))
        }
        .buttonStyle(JPRowButtonStyle())
        .accessibilityHint(isPro ? L("App Store で定期購入を管理します", "Manage your subscription in the App Store")
                                 : L("Pro の案内を開きます", "Opens the Pro page"))
        .accessibilityIdentifier("settings.pro")
    }
}
