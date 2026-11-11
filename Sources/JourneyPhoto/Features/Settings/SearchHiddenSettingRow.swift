import SwiftUI

/// 設定の「公開範囲とプライバシー」の1行: **検索エンジンにプロフィールを表示しない**
/// （2026-11-11 owner 承認・#526。Web の設定の同じ行と対）。
///
/// - プロフィールの `searchHidden` を部分更新で送る。**既定はオフ＝表示する**
/// - 効くのは Web の `/users/<id>`（検索エンジンに載せない・サイトマップから外す）。保存でサイトが作り直される
/// - 確かめのダイアログは出さない（取り消せる操作。CLAUDE.md「聞く・選ばせるのは最小に」）
/// - プロフィールが読めていない（圏外など）ときは行を出さない（今の値が分からないまま切り替えさせない）
///
/// 2026-11-11 判断: 置き場所は「トランクを見せる」の下（板 Settings の「公開範囲とプライバシー」＝人に見せるもの・
/// 見せない人を集める札）。入切は板の「前の晩に知らせる」と同じ `JPToggleRow`（説明つき）
struct SearchHiddenSettingRow: View {

    /// 自分のプロフィール。読めていなければ nil
    let profile: UserProfile?

    @EnvironmentObject private var environment: AppEnvironment

    @State private var hidden: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: UserProfile?) {
        self.profile = profile
        _hidden = State(initialValue: profile?.hidesFromSearch ?? false)
    }

    var body: some View {
        if profile != nil {
            JPCardDivider()
            JPToggleRow(title: SearchHiddenSettingText.title, detail: SearchHiddenSettingText.detail, isOn: binding)
                .disabled(isSaving)
                .accessibilityIdentifier("settings.searchHidden")
                // 読み直したプロフィールに合わせる（Web で切り替えた分。送っている最中は送った値のまま）
                .onChange(of: profile?.hidesFromSearch) { _, now in
                    if !isSaving, let now { hidden = now }
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
    }

    /// 押された瞬間だけ受ける（`SettingsView.pushBinding` と同じ理由——画面から戻したときに送り直さない）
    private var binding: Binding<Bool> {
        Binding(get: { hidden }, set: { on in
            guard !isSaving else { return }
            let before = hidden
            hidden = on
            isSaving = true
            errorMessage = nil
            Task {
                defer { isSaving = false }
                do {
                    try await environment.profiles.update(ProfilePatch(searchHidden: on))
                } catch {
                    // 送れなければ元に戻す（隠したつもりで出ている、を作らない）
                    hidden = before
                    errorMessage = LightAlertSettingsText.saveFailed(error)
                }
            }
        })
    }
}

/// 文言（テストで見張る）
enum SearchHiddenSettingText {
    /// 押す前に何が起きるか分かる言い方（owner 2026-11-11「検索エンジンにプロフィールを表示しない」）
    static var title: String { L("検索エンジンにプロフィールを表示しない", "Hide my profile from search engines") }
    static var detail: String {
        L("Google などの検索結果に、あなたのプロフィールのページを出さないようにします。写真ごとの公開の設定は変わりません。",
          "Your profile page won\u{2019}t appear in Google and other search results. Your photos keep their own sharing settings.")
    }
}
