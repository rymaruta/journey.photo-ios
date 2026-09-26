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

    private var list: some View {
        List {
            if auth.userId != nil {
                Section {
                    // **`onChange` で拾わない。** 画面側から `wantsPush` を
                    // 戻したときにも発火し、**許可した直後に自分でオフへ
                    // 戻す**（`enable()` の返りは APNs のトークンより先に来る）。
                    // 押された瞬間だけを受ける形にする
                    Toggle(L("プッシュ通知を受け取る", "Push notifications"),
                           isOn: Binding(get: { wantsPush },
                                         set: { on in
                                             // **門は同期で閉じる。** `Task` の
                                             // 中で立てると、連打の2発目が来る
                                             // 時点ではまだ開いている
                                             guard !isApplying else { return }
                                             isApplying = true
                                             wantsPush = on
                                             Task { await apply(on: on) }
                                         }))
                        .disabled(isApplying)
                        // **軌道は暗い真鍮。** 既定の tint（白）だと、入れたときに白い軌道に
                        // 白いつまみが乗り、入か切かが見えない
                        .tint(WebTheme.accentDeep)
                    if showDeniedHint {
                        // **端末の許可は取り消せない。** 断られたあとは
                        // 設定アプリへ行ってもらうしかない——黙って
                        // 戻るだけだと「押しても何も起きない」に見える
                        Text(L("この端末で通知が許可されていません。iPhone の「設定 → 通知 → Journey Photo」から許可してください。",
                               "Notifications are off for this device. Allow them in Settings → Notifications → Journey Photo."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = push.errorMessage {
                        Text(message).font(.caption).foregroundStyle(WebTheme.danger)
                    }
                } header: {
                    Text(L("お知らせ", "Activity"))
                } footer: {
                    Text(L("いいね・コメント・フォロー・ストーリーへの返信を、アプリを開いていなくても受け取れます。",
                           "Get likes, comments, follows and story replies even when the app is closed."))
                }

                // **並びはアーティファクト 43 の「設定」**（2026-09-26）。
                // 親しい友達・お気に入り・共同アルバムの入口をここにも置く
                // ——マイページの横並びだけだと見つからなかった
                Section(L("プライバシー", "Privacy")) {
                    NavigationLink { BlockedUsersView() } label: {
                        Label(L("ブロックした人", "Blocked people"), systemImage: "shield")
                    }
                    NavigationLink { CloseFriendsView() } label: {
                        Label(L("親しい友達", "Close friends"), systemImage: "person.badge.plus")
                    }
                    // 板の文言は「お気に入り」（しおりの印）だが、アプリの画面名（01d の
                    // メニューも同じ）に揃える。しおりはアプリでは「保存」の印なので、ハート
                    NavigationLink { FavoritesView() } label: {
                        Label(Labels.Navigation.favorites, systemImage: "heart")
                    }
                    NavigationLink { AlbumsView() } label: {
                        Label(Labels.Navigation.albums, systemImage: "rectangle.stack")
                    }
                }
            }

            // **データとストレージ**（モック12）。写真の控えは端末に溜まる
            Section {
                HStack {
                    Label(L("写真の控え", "Cached photos"), systemImage: "photo")
                    Spacer()
                    Text(cacheSize).foregroundStyle(.secondary)
                }
                Button(L("控えを空にする", "Clear cache")) {
                    // **消すのは画像の控えだけ。** ログインの情報や
                    // 保存した写真の印（`FavoritesStore`）は消さない
                    URLCache.shared.removeAllCachedResponses()
                    cacheSize = Self.formattedCacheSize()
                }
            } header: {
                Text(L("データとストレージ", "Data & storage"))
            } footer: {
                Text(L("一度見た写真を端末に控えています。空にすると、次に見るときだけ通信します。",
                       "Photos you have seen are kept on this device. Clearing frees space."))
            }

            // **規約・問い合わせは未ログインでも出す**（審査 1.2 の連絡先）。
            // 見出しの「アカウント」はログインしているときだけ
            Section {
                if auth.userId != nil {
                    NavigationLink { ChangePasswordView() } label: {
                        Label(L("パスワードを変える", "Change password"), systemImage: "lock")
                    }
                }
                NavigationLink { LegalLinksView() } label: {
                    Label(L("利用規約・プライバシーポリシー", "Terms & Privacy"), systemImage: "flag")
                }
                if let contact = LegalConsent.contactURL {
                    Link(destination: contact) {
                        Label(L("問い合わせ", "Contact"), systemImage: "bubble.left")
                    }
                }
                if auth.userId != nil {
                    NavigationLink { DeleteAccountView() } label: {
                        Label(L("アカウントの削除", "Delete account"), systemImage: "trash")
                    }
                    .foregroundStyle(WebTheme.danger)
                }
            } header: {
                if auth.userId != nil { Text(L("アカウント", "Account")) }
            } footer: {
                // 未ログインでは下のログアウトの節ごと無いので、バージョンはここに出す
                if auth.userId == nil { Text(versionLine) }
            }

            // **ログアウトは板に無いが、まだ外せない。** 板ではメニュー（01d）に
            // あり、そのメニューがアプリに無い間はここが唯一の出口。
            // 確認なしで効くので、**削除と同じ節に並べない**（押し間違い）
            // **行の無い節を作らない**（足元ごと省かれると、未ログインの画面から
            // バージョンが消える）。ログインしているときだけ節を置く
            if auth.userId != nil {
                Section {
                    Button {
                        Task {
                            // **通知の宛先は、ログアウトの前に外す。**
                            // あとだと認証が通らず、外せないまま次にこの端末を
                            // 使う人へ前の人あての通知が飛ぶ
                            await push.signingOut()
                            await auth.signOut()
                        }
                    } label: {
                        Label(Labels.Navigation.logout, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    // 板の最下部の1行「バージョン [0.0.0] · 接続先 [本番]」
                    Text(versionLine)
                }
            }
        }
        .webScreen()
        .navigationTitle(L("設定", "Settings"))
    }
}
