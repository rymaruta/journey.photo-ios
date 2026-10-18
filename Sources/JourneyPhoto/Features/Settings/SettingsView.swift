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
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var pass: PassStore
    /// 旅のトランクの口が在るか（無い間は行を出さない・マイページと同じ）と、入口の数（2026-10-18）
    @ObservedObject private var trunkAvailability = TrunkAvailability.shared
    @ObservedObject private var trunkEntry = TrunkEntryStore.shared
    /// 自分のプロフィール（Pro の節の中身・第2段階）。読めなければ nil
    @State private var myProfile: UserProfile?
    @State private var wantsPush = false
    @State private var showDeniedHint = false
    /// 切り替えている最中。二度押しで登録と解除が交差しないようにする
    @State private var isApplying = false
    /// ログアウトの最中。宛先を外し終えるまで（最大20秒）二度押させず、進み具合を見せる
    /// （`DeleteAccountView.isWorking` と同じ形）
    /// 印は `AuthStore` の共有のもの（メニューから押した分とも1本にまとめる）
    private var isSigningOut: Bool { auth.isSigningOut }
    /// 「新しくなったこと」を開き直す（起動で出たものと同じ画面・2026-10-04）
    @State private var showWhatsNew = false
    /// トランクを見せる（板 TrunkPrivacy・2026-10-18）。トランクの口がある人にだけ出す（`TrunkAvailability`）
    @StateObject private var trunkPrivacy = TrunkPrivacyModel()

    /// 「トランクを見せる」を出すか（口が読めたことがあり、いまの設定が読めたとき）
    private var showsTrunkPrivacy: Bool { trunkAvailability.isAvailable && trunkPrivacy.state != nil }

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
            // Pro の節のためのプロフィール。名前の横を決めた・購入した（`noteProfileChanged`）ら読み直す
            .task(id: auth.profileRevision) { await loadMyProfile() }
            // 旅のトランクの行（マイページを開く前に設定へ来た人にも出す）と、トランクの見せる設定・わたしの乗車券の揃え。
            // 読むかはどちらも決まりのとおり（覚えている人は 6 時間に1回・`TrunkAvailabilityRule`・`TrunkEntryRule`）。
            // `GET /user/trunk` は入口の店（`TrunkEntryStore`）の1本にまとめる
            .task(id: auth.userId) {
                // 入っている人が替わったら、前の人の設定・見本の札を消してから読む
                trunkPrivacy.reset(for: auth.userId)
                await trunkAvailability.refresh(userId: auth.userId, service: environment.trunk)
                await trunkEntry.refresh(userId: auth.userId, available: trunkAvailability.isAvailable,
                                         service: environment.trunk)
                guard let userId = auth.userId, trunkAvailability.isAvailable else { return }
                await trunkPrivacy.load(userId: userId, service: environment.trunk, pass: pass.settings)
            }
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
            // **ほかの所から「受け取る」にしたときも合わせる**（Pro の「前の晩に知らせる」の
            // 「通知がオフのため届きません」を押した・2026-10-11）。端末の許可が前から
            // あると `isAuthorized` は変わらず、上だけではトグルが「切」のまま残る
            .onChange(of: push.isEnabled) { _, enabled in
                guard !isApplying else { return }
                wantsPush = enabled && push.isAuthorized
            }
    }

    private func loadMyProfile() async {
        guard auth.userId != nil else { return }
        let profiles = environment.profiles
        let fresh = try? await profiles.myProfile()
        if let fresh { myProfile = fresh }
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
    /// 大見出し、節ごとに角丸の札、行の説明は行の中の2行目、最下部に等幅の版。
    ///
    /// **v2（2026-10-14・板 Settings）**: 節の見出しを真鍮の眉ラベルに（`SettingsGroup`）、節の間を
    /// 物差しの「節と節の間」（`JPSpace.section`）に、行の絵を外した（Pro の行の Pro マークだけ残す）。
    /// アカウントの削除は名前ごと危険の色（`WebTheme.danger`）
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                Text(L("設定", "Settings"))
                    .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .padding(.horizontal, JPSpace.xxs)
                    .accessibilityAddTraits(.isHeader)
                if auth.userId != nil {
                    // 板 43 の並び: Pro がいちばん上
                    ProSettingsSection(profile: myProfile)
                    notificationsSection
                    passSection
                    trunkSection
                    privacySection
                    if showsTrunkPrivacy {
                        TrunkPrivacyPreview(model: trunkPrivacy, profile: myProfile, userId: auth.userId)
                    }
                }
                compositionSection
                storageSection
                accountSection
                if auth.userId != nil {
                    logoutSection
                }
                // 板の最下部の1行「バージョン [0.0.0] · 接続先 [本番]」。
                // 接続先は**いつも出す**（本番かどうかを見分けるため）
                Text(versionLine)
                    .font(JPFont.meta)
                    // 白 45% は黒地で 4.43:1 と文字の線（4.5:1）を割る。注記の text-3（v2 の #9A9A9A・黒地だけ）
                    .foregroundStyle(WebTheme.text3)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xxs)
            .padding(.bottom, JPSpace.emptyTop)
            // **ログアウトの途中は、ほかの行も押させない**（`DeleteAccountView` と同じ考え方）。
            // 退会・パスワード変更に進めると、ログアウトが先に終わって Cognito の
            // 呼び出しが落ち続けた。ログアウトの行の進み具合はそのまま出る
            .disabled(isSigningOut)
        }
        .webScreen()
        // 戻るボタンの文言（子の画面の「< 設定」）のために題は持つが、
        // **バーの中央には出さない**（板は左寄せの大見出しだけ）
        .navigationTitle(L("設定", "Settings"))
        // ログアウトの途中は戻らせない・シートも払わせない（戻って開き直すと門が新しくなり、
        // 二度押せる。`DeleteAccountView` と同じ2つ）
        // 設定から開いたときは履歴（新しい版が上・版ごとに区切りの見出し・2026-10-18 owner「過去の履歴を見れるようにしたい」）
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(releases: WhatsNew.bundled(), mode: .history, primaryTitle: Labels.Common.close)
        }
        .navigationBarBackButtonHidden(isSigningOut)
        .interactiveDismissDisabled(isSigningOut)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
    }

    private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        SettingsGroup(title) { content() }
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
                     color: WebTheme.text3)
            }
            if let message = push.errorMessage {
                JPCardDivider()
                note(message, color: WebTheme.danger)
            }
        }
    }

    /// すれちがい（板 PassSettings の戻り先が設定・2026-10-16）。お知らせとプライバシーの間
    /// （近くの人とカードを交換する＝届くものと、見せるものの両方に関わる）
    private var passSection: some View {
        section(L("すれちがい", "Pass")) {
            NavigationLink { PassSettingsView() } label: {
                JPRowLabel(title: L("すれちがい", "Pass"),
                           detail: L("旅先で近くにいた人と、わたしの乗車券をカードで交換する",
                                     "Swap your ticket with people you pass on your travels"),
                           value: pass.settings.enabled ? pass.settings.mode.label : L("オフ", "Off"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("settings.pass")
        }
    }

    /// 旅のトランク（2026-10-18 owner「入口がわかりずらい」）。すれちがいと同じ形の、機能ごとの節に1行。
    /// 置き場はすれちがいの下（どちらも旅先・投稿で届くもの）。**口が読めたことのある人だけ**（`TrunkEntryRule.shows`）。
    /// 右の値は硬貨の枚数（読めていれば・ほかの行の値と同じ等幅の字）。読み上げは硬貨と貼っていないラベルの有無
    @ViewBuilder
    private var trunkSection: some View {
        if TrunkEntryRule.shows(signedIn: auth.userId != nil, available: trunkAvailability.isAvailable) {
            section(TrunkEntryText.title) {
                NavigationLink {
                    TrunkView(ownerName: myProfile?.name)
                        .onDisappear { trunkEntry.markStale() }
                } label: {
                    JPRowLabel(title: TrunkEntryText.title, detail: TrunkEntryText.detail,
                               value: trunkEntry.summary.map { TrunkEntryText.coins($0.coins) })
                }
                .buttonStyle(JPRowButtonStyle())
                // 押せる1つのボタンのまま、名前と値を付ける（`.ignore` で包むと VoiceOver の2回叩きで開けない）
                .accessibilityLabel(TrunkEntryText.title)
                .accessibilityValue(TrunkEntryText.accessibilityValue(trunkEntry.summary))
                .accessibilityHint(TrunkEntryText.detail)
                .accessibilityIdentifier("settings.trunk")
            }
            // トランクから戻ったら数を読み直す（`markStale` のときだけ読む・2026-10-18 見直し）
            .onAppear {
                Task {
                    await trunkEntry.refresh(userId: auth.userId, available: trunkAvailability.isAvailable,
                                             service: environment.trunk)
                }
            }
        }
    }

    /// 札の中の注記（行ではない1文）
    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(JPFont.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, JPSpace.s)
    }

    // 親しい友達・お気に入り・共同アルバムの入口をここにも置く
    // ——マイページの横並びだけだと見つからなかった
    private var privacySection: some View {
        section(L("プライバシー", "Privacy")) {
            NavigationLink { BlockedUsersView() } label: {
                JPRowLabel(title: L("ブロックした人", "Blocked people"))
            }
            .buttonStyle(JPRowButtonStyle())
            JPCardDivider()
            NavigationLink { CloseFriendsView() } label: {
                JPRowLabel(title: L("親しい友達", "Close friends"))
            }
            .buttonStyle(JPRowButtonStyle())
            JPCardDivider()
            // 板 TrunkPrivacy: 親しい友達の下（人に見せるかの切り替え）
            if showsTrunkPrivacy {
                TrunkShowRow(model: trunkPrivacy, service: environment.trunk)
                JPCardDivider()
            }
            // 板の文言は「お気に入り」（しおりの印）だが、アプリの画面名（01d の
            // メニューも同じ）に揃える。しおりはアプリでは「保存」の印なので、ハート
            NavigationLink { FavoritesView() } label: {
                JPRowLabel(title: Labels.Navigation.favorites)
            }
            .buttonStyle(JPRowButtonStyle())
            JPCardDivider()
            NavigationLink { AlbumsView() } label: {
                JPRowLabel(title: Labels.Navigation.albums)
            }
            .buttonStyle(JPRowButtonStyle())
        }
    }

    private var compositionSection: some View {
        section(L("撮影ガイド", "Shooting guide")) {
            NavigationLink { CompositionCatalogView() } label: {
                JPRowLabel(title: L("構図一覧", "Composition guide"),
                           detail: L("構図の説明と作例の配置図を見る", "Explore compositions and illustrated examples"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("settings.compositionCatalog")
        }
    }

    // **データとストレージ**（モック12）。写真の控えは端末に溜まる
    private var storageSection: some View {
        section(L("データとストレージ", "Data & storage")) {
            JPRowLabel(title: L("写真の控え", "Cached photos"),
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
                // 板 v2: 押すとその場で効く行は真鍮の字（黒地の札の上の手がかり）
                SettingsActionLabel(title: L("控えを空にする", "Clear cache"), color: WebTheme.accent)
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
                    JPRowLabel(title: L("パスワードを変える", "Change password"))
                }
                .buttonStyle(JPRowButtonStyle())
                JPCardDivider()
            }
            // 「新しくなったこと」はいつでも開き直せる（未ログインでも出す）
            Button { showWhatsNew = true } label: {
                JPRowLabel(title: L("新しくなったこと", "What's new"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("settings.whatsNew")
            JPCardDivider()
            NavigationLink { LegalLinksView() } label: {
                JPRowLabel(title: L("利用規約・プライバシーポリシー", "Terms & Privacy"))
            }
            .buttonStyle(JPRowButtonStyle())
            if let contact = LegalConsent.contactURL {
                JPCardDivider()
                Link(destination: contact) {
                    JPRowLabel(title: L("問い合わせ", "Contact"))
                }
                .buttonStyle(JPRowButtonStyle())
            }
            if auth.userId != nil {
                JPCardDivider()
                // 板 v2: 名前ごと危険の色（#F0565A）・行き先があるので矢印あり（v1 はアイコンだけ赤・矢印なし）
                // Pro かどうか（定期購入の知らせ）を渡す。読めていなければ nil のまま＝知らせを出す
                NavigationLink { DeleteAccountView(profile: myProfile) } label: {
                    SettingsActionLabel(title: L("アカウントの削除", "Delete account"), color: WebTheme.danger,
                                        chevron: true)
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
                // **門は押したその場で閉じる**（`startSigningOut` が共有の印を立てる）。
                // **通知の宛先は、ログアウトの前に外す。** あとだと認証が通らず、
                // 外せないまま次にこの端末を使う人へ前の人あての通知が飛ぶ
                auth.startSigningOut { await push.signingOut() }
            } label: {
                JPRowLabel(title: isSigningOut ? L("ログアウトしています…", "Signing out…") : Labels.Navigation.logout,
                           chevron: false)
                    .overlay(alignment: .trailing) {
                        if isSigningOut { ProgressView().padding(.trailing, 14) }
                    }
            }
            .buttonStyle(JPRowButtonStyle())
            .disabled(isSigningOut)
        }
    }
}

/// 設定の見た目の決まり（v2 の板 Settings・2026-10-14）。テストで見張る
enum SettingsLayout {
    /// 大見出し「設定」（明朝 30・板の値。積む画面の大見出しは板の全画面で 30）
    static let titleSize: Double = 30
    /// 節と節の間（物差しの「節と節の間」）
    static let sectionSpacing: CGFloat = JPSpace.section
    /// 眉ラベルと札の間
    static let headerSpacing: CGFloat = JPSpace.xs
}

/// 設定の節（v2 の板 Settings の `.grp`）: **真鍮の眉ラベル**（黒地の上の合図）＋ 札（`JPCard`）。
///
/// v1 は白 60% の小さい見出し（`JPSectionTitle`）だった。見出しが無い節（ログアウト）は札だけ。
/// Pro の節（`ProSettingsSection`）も同じ形で組む
struct SettingsGroup<Content: View>: View {

    let title: String?
    let content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.headerSpacing) {
            if let title {
                Text(title)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, JPSpace.xxs)
                    .accessibilityAddTraits(.isHeader)
            }
            JPCard { content }
        }
    }
}

/// 押すとその場で効く行・危ない行の見た目（板 v2: 名前だけを色で——「控えを空にする」は真鍮、
/// 「アカウントの削除」は #F0565A）。寸法は `JPRowLabel` と同じ（最小 54・左右 14）。
/// **色だけで危なさを伝えない**: 名前そのものが「削除」と言う
struct SettingsActionLabel: View {

    let title: String
    let color: Color
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}
