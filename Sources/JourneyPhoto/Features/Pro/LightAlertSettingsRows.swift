import SwiftUI
import UIKit

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
    /// 通知が届く端末か（`LightAlertPushNotice`・2026-10-11）
    @EnvironmentObject private var push: PushCenter
    @Environment(\.openURL) private var openURL
    /// 通知を受け取るように切り替えている最中（二度押しで重ねて尋ねない）
    @State private var isTurningOnPush = false

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
        // 許可の段階を読む（設定の `.task` も読むが、こちらが先に描かれても「読んでいない」で止まらない）
        .task { if push.permission == .unknown { await push.refreshAuthorization() } }
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
        // 🔴 **通知が届かない端末では、オンに見えて何も来なかった**（既定がオン・2026-10-11）。
        // 板 Settings の「通知が切られています」の行と同じ形で、押すと直せる所へ進む
        if let notice = LightAlertPushNotice.state(wants: wants, knownNotPro: knownNotPro,
                                                   permission: push.permission, enabled: push.isEnabled) {
            JPCardDivider()
            pushNoticeRow(notice)
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(WebTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    /// 「通知がオフのため届きません」の行（板 Settings の F31 の行: 真鍮 8% の地・真鍮の字と線の絵・矢印）
    private func pushNoticeRow(_ notice: LightAlertPushNotice) -> some View {
        Button { Task { await fixPush(notice) } } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 18))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.subheadline)
                    Text(notice.detail)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            // 背景を描く前に行の幅を確定する。内容幅だけに背景が縮むのを防ぐ（2026-10-13）。
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                WebTheme.accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isTurningOnPush)
        .accessibilityElement(children: .combine)
        .accessibilityHint(notice.hint)
        .accessibilityIdentifier("settings.lightAlert.pushOff")
    }

    /// 行を押した。まだ聞いていない・アプリでオフにした → 受け取る（必要なら OS が尋ねる）。
    /// 断られている → OS はもう聞かないので設定アプリを開く
    private func fixPush(_ notice: LightAlertPushNotice) async {
        switch notice {
        case .openSettings:
            // 通知の設定の所を直接開く（2026-10-11・iOS 16 から）。アプリの設定の一番上だと
            // 「通知」の行を探して押す手間が1つ増える
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        case .turnOn:
            guard !isTurningOnPush else { return }
            isTurningOnPush = true
            defer { isTurningOnPush = false }
            // 断られたら `push.permission` が `.denied` になり、行は設定アプリへの案内に替わる
            await push.enable()
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
