import SwiftUI
// Linux では `URLCache` が別モジュールに居る（iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 設定。**審査で必要な導線をここに集める**
/// （規約・プライバシー・ブロック一覧・退会・問い合わせ）。
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @State private var wantsPush = false
    @State private var showDeniedHint = false
    /// 切り替えている最中。二度押しで登録と解除が交差しないようにする
    @State private var isApplying = false
    /// ログアウトの最中。宛先を外し終えるまで（最大20秒）二度押させず、進み具合を見せる
    /// （`DeleteAccountView.isWorking` と同じ形）
    @State private var isSigningOut = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// 最下部の1行。接続先は**いつも出す**（本番かどうかを見分けるため）
    private var versionLine: String {
        let env = AppConfig.environment == .staging ? "staging" : L("本番", "production")
        return L("バージョン \(version) · 接続先 \(env)", "Version \(version) · \(env)")
    }

    var body: some View {
        list
            .task {
                await push.refreshAuthorization()
                // **本人の意思で見る。** 「預けられたか」で見ると、
                // シミュレータや圏外では必ず false になり、画面に入り直す
                // たびにオフへ戻る。端末の許可だけで見ると、オフにしたのに
                // 復活する（OS の許可は残る）
                wantsPush = push.isEnabled && push.isAuthorized
            }
            // **iOS の設定で許可を変えて戻ったら合わせ直す。** 開いたまま通知を切って戻ると、
            // 前面に戻ったときの読み直しで `isAuthorized` は倒れるのに、トグルが「入」のまま残った。
            // 切り替えの最中（`isApplying`）は `apply` が決めるので触らない。
            // 案内どおり許可して戻ったら、「許可されていません」の案内も下ろす
            .onChange(of: push.isAuthorized) { _, authorized in
                guard !isApplying else { return }
                wantsPush = push.isEnabled && authorized
                if authorized { showDeniedHint = false }
            }
    }

    /// 受け取る／受け取らないを切り替える。
    /// 押されたあとの本体（門は呼ぶ側で閉じてある）。
    private func apply(on: Bool) async {
        showDeniedHint = false
        defer { isApplying = false }
        if on {
            // **許可されたかだけで決める。** 宛先を預け終えたかで見ると、
            // APNs のトークンは少し遅れて届くので**必ず false になる**
            // ——押した直後に自分でオフへ戻る
            let granted = await push.enable()
            wantsPush = granted
            showDeniedHint = !granted
        } else {
            await push.disable()
            wantsPush = false
        }
    }

    /// 端末に溜まっている画像の控え。**見えないものは消せない**ので数を出す
    @State private var cacheSize: String = SettingsView.formattedCacheSize()

    static func formattedCacheSize() -> String {
        let bytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// 受け取る／受け取らないの切り替え。
    ///
    /// **`onChange` で拾わない。** 画面側から `wantsPush` を戻したときにも
    /// 発火し、**許可した直後に自分でオフへ戻す**（`enable()` の返りは APNs の
    /// トークンより先に来る）。押された瞬間だけを受ける形にする
    private var pushBinding: Binding<Bool> {
        Binding(get: { wantsPush },
                set: { on in
                    // **門は同期で閉じる。** `Task` の中で立てると、連打の
                    // 2発目が来る時点ではまだ開いている
                    guard !isApplying else { return }
                    isApplying = true
                    wantsPush = on
                    Task { await apply(on: on) }
                })
    }

    /// **並びはアーティファクト 43 の「設定」**（2026-09-26）。左寄せの明朝の
    /// 大見出し、節ごとに角丸の札、行の説明は行の中の2行目、最下部に等幅の版
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("設定", "Settings"))
                    .font(JPFont.display(30, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                if auth.userId != nil {
                    notificationsSection
                    privacySection
                }
                storageSection
                accountSection
                if auth.userId != nil {
                    logoutSection
                }
                // 板の最下部の1行「バージョン [0.0.0] · 接続先 [本番]」。
                // 接続先は**いつも出す**（本番かどうかを見分けるため）
                Text(versionLine)
                    .font(JPFont.mono(12))
                    // 白 45% は黒地で 4.43:1 と文字の線（4.5:1）を割る。注記の text-3（白 60%）
                    .foregroundStyle(WebTheme.faint)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .webScreen()
        // 戻るボタンの文言（子の画面の「< 設定」）のために題は持つが、
        // **バーの中央には出さない**（板は左寄せの大見出しだけ）
        .navigationTitle(L("設定", "Settings"))
        // ログアウトの途中は戻らせない・シートも払わせない（戻って開き直すと門が新しくなり、
        // 二度押せる。`DeleteAccountView` と同じ2つ）
        .navigationBarBackButtonHidden(isSigningOut)
        .interactiveDismissDisabled(isSigningOut)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
    }

    private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { JPSectionTitle(title) }
            JPCard { content() }
        }
    }

    private var notificationsSection: some View {
        section(L("お知らせ", "Activity")) {
            JPToggleRow(title: L("プッシュ通知を受け取る", "Push notifications"),
                        detail: L("いいね・コメント・フォロー・ストーリーへの返信を、アプリを開いていなくても受け取れます。",
                                  "Get likes, comments, follows and story replies even when the app is closed."),
                        isOn: pushBinding)
                .disabled(isApplying)
            if showDeniedHint {
                // **端末の許可は取り消せない。** 断られたあとは設定アプリへ
                // 行ってもらうしかない——黙って戻るだけだと「押しても何も
                // 起きない」に見える
                JPCardDivider()
                note(L("この端末で通知が許可されていません。iPhone の「設定 → 通知 → Journey Photo」から許可してください。",
                       "Notifications are off for this device. Allow them in Settings → Notifications → Journey Photo."),
                     color: WebTheme.faint)
            }
            if let message = push.errorMessage {
                JPCardDivider()
                note(message, color: WebTheme.danger)
            }
        }
    }

    /// 札の中の注記（行ではない1文）
    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    // 親しい友達・お気に入り・共同アルバムの入口をここにも置く
    // ——マイページの横並びだけだと見つからなかった
    private var privacySection: some View {
        section(L("プライバシー", "Privacy")) {
            NavigationLink { BlockedUsersView() } label: {
                JPRowLabel(title: L("ブロックした人", "Blocked people"), systemImage: "shield")
            }
            .buttonStyle(JPRowButtonStyle())
            JPCardDivider()
            NavigationLink { CloseFriendsView() } label: {
                JPRowLabel(title: L("親しい友達", "Close friends"), systemImage: "person.badge.plus")
            }
            .buttonStyle(JPRowButtonStyle())
            JPCardDivider()
            // 板の文言は「お気に入り」（しおりの印）だが、アプリの画面名（01d の
            // メニューも同じ）に揃える。しおりはアプリでは「保存」の印なので、ハート
            NavigationLink { FavoritesView() } label: {
                JPRowLabel(title: Labels.Navigation.favorites, systemImage: "heart")
            }
            .buttonStyle(JPRowButtonStyle())
            JPCardDivider()
            NavigationLink { AlbumsView() } label: {
                JPRowLabel(title: Labels.Navigation.albums, systemImage: "rectangle.stack")
            }
            .buttonStyle(JPRowButtonStyle())
        }
    }

    // **データとストレージ**（モック12）。写真の控えは端末に溜まる
    private var storageSection: some View {
        section(L("データとストレージ", "Data & storage")) {
            JPRowLabel(title: L("写真の控え", "Cached photos"), systemImage: "photo",
                       detail: L("一度見た写真を端末に控えています。空にすると、次に見るときだけ通信します。",
                                 "Photos you have seen are kept on this device. Clearing frees space."),
                       value: cacheSize, chevron: false)
                // 読み上げは「写真の控え、12 MB」を先に（長い説明は後ろのヒントへ）
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("写真の控え", "Cached photos"))
                .accessibilityValue(cacheSize)
                .accessibilityHint(L("一度見た写真を端末に控えています。空にすると、次に見るときだけ通信します。",
                                     "Photos you have seen are kept on this device. Clearing frees space."))
            JPCardDivider()
            Button {
                // **消すのは画像の控えだけ。** ログインの情報や
                // 保存した写真の印（`FavoritesStore`）は消さない
                URLCache.shared.removeAllCachedResponses()
                cacheSize = Self.formattedCacheSize()
            } label: {
                JPRowLabel(title: L("控えを空にする", "Clear cache"), chevron: false)
            }
            .buttonStyle(JPRowButtonStyle())
        }
    }

    // **規約・問い合わせは未ログインでも出す**（審査 1.2 の連絡先）。
    // 見出しの「アカウント」はログインしているときだけ
    private var accountSection: some View {
        section(auth.userId != nil ? L("アカウント", "Account") : nil) {
            if auth.userId != nil {
                NavigationLink { ChangePasswordView() } label: {
                    JPRowLabel(title: L("パスワードを変える", "Change password"), systemImage: "lock")
                }
                .buttonStyle(JPRowButtonStyle())
                JPCardDivider()
            }
            NavigationLink { LegalLinksView() } label: {
                JPRowLabel(title: L("利用規約・プライバシーポリシー", "Terms & Privacy"), systemImage: "flag")
            }
            .buttonStyle(JPRowButtonStyle())
            if let contact = LegalConsent.contactURL {
                JPCardDivider()
                Link(destination: contact) {
                    JPRowLabel(title: L("問い合わせ", "Contact"), systemImage: "bubble.left")
                }
                .buttonStyle(JPRowButtonStyle())
            }
            if auth.userId != nil {
                JPCardDivider()
                // 板: アイコンだけ赤・矢印なし
                NavigationLink { DeleteAccountView() } label: {
                    JPRowLabel(title: L("アカウントの削除", "Delete account"), systemImage: "trash",
                               chevron: false, iconColor: WebTheme.danger)
                }
                .buttonStyle(JPRowButtonStyle())
            }
        }
    }

    // **ログアウトは板に無いが残す。** 板ではメニュー（01d）にあり、
    // アプリもメニューに置いた（2026-09-26）。設定から抜けられる口も
    // 残しておく（ここを探す人がいる）。
    // 確認なしで効くので、**削除と同じ札に並べない**（押し間違い）
    private var logoutSection: some View {
        section(nil) {
            Button {
                // **門は押したその場で閉じる**（`Task` の中で立てると連打の2発目が通る）
                guard !isSigningOut else { return }
                isSigningOut = true
                Task {
                    defer { isSigningOut = false }
                    // **通知の宛先は、ログアウトの前に外す。**
                    // あとだと認証が通らず、外せないまま次にこの端末を
                    // 使う人へ前の人あての通知が飛ぶ
                    await push.signingOut()
                    await auth.signOut()
                }
            } label: {
                JPRowLabel(title: isSigningOut ? L("ログアウトしています…", "Signing out…") : Labels.Navigation.logout,
                           systemImage: "rectangle.portrait.and.arrow.right", chevron: false)
                    .overlay(alignment: .trailing) {
                        if isSigningOut { ProgressView().padding(.trailing, 14) }
                    }
            }
            .buttonStyle(JPRowButtonStyle())
            .disabled(isSigningOut)
        }
    }
}
