import SwiftUI

/// 設定の Pro の節の「公開プロフィールに Pro の章を出す」の入切（2026-10-18 owner・#296・板 43 設定）。
/// 「名前の横のバッジと Pro マーク」の行のすぐ下（板の並び）。
///
/// - オフにすると、他の人の公開プロフィールから Pro のメダル（サポーター章・続けた年・季節の章）と、
///   サポーターの番号・申し込んだ日・続けた月数が消える（サーバーの `toPublicProfile`）。本人の画面はそのまま
/// - 送るのはプロフィールの `proBadgesHidden`（オン＝出す＝`false`）の部分更新だけ。`LightAlertSettingsRows` と同じ形
/// - 出すかは `ProBadgesPublicRule.showsRow`
struct ProBadgesPublicRow: View {

    /// 自分のプロフィール（`ProBadgesPublicRule.showsRow` が真のときだけ置く）
    let profile: UserProfile

    @EnvironmentObject private var environment: AppEnvironment
    /// 出す（= `proBadgesHidden` が偽）
    @State private var on: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: UserProfile) {
        self.profile = profile
        _on = State(initialValue: !(profile.proBadgesHiddenFlag ?? false))
    }

    var body: some View {
        Group {
            JPCardDivider()
            JPToggleRow(title: ProBadgesPublicRule.title, detail: ProBadgesPublicRule.detail, isOn: binding)
                .disabled(isSaving)
                .accessibilityIdentifier("settings.proBadgesPublic")
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WebTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        // 読み直したプロフィールに合わせる（Web で切り替えた分。送っている最中は送った値のまま）
        .onChange(of: profile.proBadgesHiddenFlag) { _, now in
            if !isSaving, let now { on = !now }
        }
    }

    /// 押された瞬間だけ受ける（`LightAlertSettingsRows.binding` と同じ理由——画面から戻したときに送り直さない）
    private var binding: Binding<Bool> {
        Binding(get: { on }, set: { next in
            guard !isSaving else { return }
            let before = on
            on = next
            isSaving = true
            errorMessage = nil
            Task {
                defer { isSaving = false }
                do {
                    try await environment.profiles.update(ProBadgesPublicRule.patch(show: next))
                } catch {
                    // 送れなければ元に戻す（隠したつもりで出ている、を作らない）
                    on = before
                    errorMessage = LightAlertSettingsText.saveFailed(error)
                }
            }
        })
    }
}

/// 「公開プロフィールに Pro の章を出す」の決まり（画面に依らない・テストで見張る）
enum ProBadgesPublicRule {

    static let title = L("公開プロフィールに Pro の章を出す", "Show Pro medals on your public profile")
    static let detail = L("オフにすると、Pro のメダル・サポーターの番号と続けた月数を他の人に見せません（いま Pro かどうかは乗車券の券面で分かります）",
                          "When off, other people won\u{2019}t see your Pro medals, supporter number or months supported (your pass face still shows whether you\u{2019}re Pro now).")

    /// 行を出すか（Pro のメダルの鍵かは `BadgeCatalog.isPro`。サーバーの `badgeKeys.ts` の `isProBadgeKey` と同じ規則）:
    /// - **サポーターの番号か Pro のメダルを持っている人だけ**（やめた人も。番号とメダルは残るので）
    /// - **自分のプロフィールに `proBadgesHidden` が無い（古いサーバー）ときは出さない**——古いサーバーは知らない
    ///   項目を黙って捨てるので、出すと押しても効かない入切になる（`passFace` の有無で分けたのと同じ考え方）
    static func showsRow(_ profile: UserProfile) -> Bool {
        guard profile.proBadgesHiddenFlag != nil else { return false }
        return profile.supporterInfo != nil || profile.earnedBadges.byKey.keys.contains(where: BadgeCatalog.isPro)
    }

    /// 送る部分更新（`show` が真＝出す＝`proBadgesHidden: false`）
    static func patch(show: Bool) -> ProfilePatch {
        ProfilePatch(proBadgesHidden: !show)
    }
}
