import SwiftUI

/// 設定の Pro の節の「光と天気の知らせ」の2行（Pro・2026-10-09）。`ProSettingsSection` の札の中に置く。
///
/// 1. 「光と天気の知らせ」（光の線の絵・真鍮）: 一覧「行きたい場所の光（今週）」を開く
/// 2. 「前の晩に知らせる」の入切: プロフィールの `lightAlert`（既定 受け取る）を部分更新で送る
///
/// **Pro でなければ、どちらを押しても Pro の案内**（入切は動かさない）。
/// プロフィールが読めていない（圏外など）ときは、一覧を開く行だけ出す（Pro かは一覧が 403 で知る）。
///
/// 2026-10-09 判断: 設定の板（Settings）ではこの入切は「お知らせ」の節にある（種類ごとの入切が並ぶ節）。
/// アプリの「お知らせ」の節はまだ入切が1つ（プッシュ全体）だけなので、一覧を開く行と並べて Pro の節に置いた。
/// 種類ごとの入切を作るときに「お知らせ」の節へ移す
struct LightAlertSettingsRows: View {

    /// 自分のプロフィール。読めていなければ nil
    let profile: UserProfile?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var auth: AuthStore

    @State private var wants: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var deliveredAtPaywall = 0

    init(profile: UserProfile?) {
        self.profile = profile
        _wants = State(initialValue: profile?.wantsLightAlert ?? true)
    }

    /// Pro でないと分かっている（読めていない人には案内を出さない）
    private var knownNotPro: Bool {
        guard let profile else { return false }
        return !profile.isPro && LightForecastText.preview == nil
    }

    var body: some View {
        Group {
            JPCardDivider()
            if knownNotPro {
                Button { openPaywall() } label: { listLabel }
                    .buttonStyle(JPRowButtonStyle())
                    .accessibilityHint(L("Pro の案内を開きます", "Opens the Pro page"))
                    .accessibilityIdentifier("settings.lightForecast")
            } else {
                NavigationLink { LightForecastView() } label: { listLabel }
                    .buttonStyle(JPRowButtonStyle())
                    .accessibilityIdentifier("settings.lightForecast")
            }
            if profile != nil {
                toggleRows
            }
        }
        // 読み直したプロフィールに合わせる（Web で切り替えた分。送っている最中は送った値のまま）
        .onChange(of: profile?.wantsLightAlert) { _, now in
            if !isSaving, let now { wants = now }
        }
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            // 案内で Pro になったらプロフィールを読み直す（設定の `loadMyProfile`）
            guard store.deliveredRevision != deliveredAtPaywall else { return }
            auth.noteProfileChanged()
        }) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var toggleRows: some View {
        JPCardDivider()
        JPToggleRow(title: L("前の晩に知らせる", "Alert me the evening before"),
                    detail: L("行きたい場所が、明日の朝に晴れて朝焼けになりそうなら前の晩に。",
                              "If a wishlist place looks set for a clear, glowing sunrise, we\u{2019}ll tell you the evening before."),
                    isOn: binding)
            .disabled(isSaving)
            .accessibilityIdentifier("settings.lightAlert")
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(WebTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    private var listLabel: some View {
        JPRowLabel(title: L("光と天気の知らせ", "Light & weather alerts"),
                   detail: L("行きたい場所の、今週の光と天気", "This week\u{2019}s light and weather at your wishlist places"),
                   icon: AnyView(ProIconView(icon: .light, side: 20, color: WebTheme.accent, lineWidth: 1.7)))
    }

    /// 押された瞬間だけ受ける（`SettingsView.pushBinding` と同じ理由——画面から戻したときに送り直さない）
    private var binding: Binding<Bool> {
        Binding(get: { wants }, set: { on in
            guard !isSaving else { return }
            guard !knownNotPro else {
                openPaywall()
                return
            }
            let before = wants
            wants = on
            isSaving = true
            errorMessage = nil
            Task {
                defer { isSaving = false }
                do {
                    try await environment.profiles.update(ProfilePatch(lightAlert: on))
                } catch {
                    // 送れなければ元に戻す（入っているように見せて届かない／止めたつもりで届く、を作らない）
                    wants = before
                    errorMessage = LightAlertSettingsText.saveFailed(error)
                }
            }
        })
    }

    private func openPaywall() {
        deliveredAtPaywall = store.deliveredRevision
        showPaywall = true
    }
}

/// 入切の文言（テストで見張る）
enum LightAlertSettingsText {
    /// 送れなかったときの1行。圏外はそう言う
    static func saveFailed(_ error: Error) -> String {
        if case .unreachable = error as? APIError {
            return L("圏外のため切り替えられませんでした。電波のあるところでもう一度お試しください。",
                     "You\u{2019}re offline, so this couldn\u{2019}t be changed. Please try again with a signal.")
        }
        return L("切り替えられませんでした。もう一度お試しください。", "Couldn\u{2019}t change this. Please try again.")
    }
}
