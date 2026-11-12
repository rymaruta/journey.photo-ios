import SwiftUI

/// 見出しの「メニュー（≡）」から開く一覧（板 01d・Web のハンバーガーと同じ並び）。
///
/// 2026-09-26 owner「ヘッダーのハンバーガーは残す（サイトから外さない）」。
/// **下の札にある場所（マップ・マイページ）は札へ移す**——同じ画面をこの中に
/// もう1つ積むと、戻る先が2通りになる。札に無い場所（いいねした写真・
/// 共同アルバム・設定）はこの中で開く。
///
/// 「保存した写真」は板 35 の一覧（`SavedPhotosView`）。「管理」は**管理者のときだけ**
/// （ID トークンの群・Web と同じ判定）で、アプリに管理の画面は作らず**サイトの
/// /admin をブラウザで開く**（管理の口は Web にしか無い）。
///
/// **v2（2026-10-14・SiteMenu の板）**:
/// - 「見る」の行は 72 の行に、左に 40 の角 12 の印の札、題は明朝、下に一行の説明（12・text-3）。
///   説明で「いいね＝作者に届く」を読ませる（板の付箋。保存の行は 2026-11-12 に外した）
/// - 「アカウント」の行は 52 の素の行（題 15・右に ›）。ログアウトは text-2 の字で › を付けない
/// - 節の見出しは眉（真鍮＋消える線・`JPEyebrowLine`）。行は札で囲まず、白 8% の線で区切る
/// - 下に利用規約・プライバシーポリシーの真鍮のリンク（黒地の上・外へ出るリンク）と版
/// - 板は「旅行プラン」「共同アルバム」を「見る」に置く。並びは板どおり（2026-10-14 判断）
///
/// **2026-11-12 判断（デザインの案 第10章「どこに何を置くか」）: 道具の一覧はここ1か所。**
/// - タブと重なる3行（撮影地マップ＝マップのタブ・マイページ＝タブ・保存＝マイページの保存のタブ）を外した
/// - 設定の「旅の道具」の節（6行）をここへ移した。設定はオン・オフと決まりだけ（設定の中にしか無い入口を作らない）
/// - 節は「旅の準備」（旅行プラン・共同アルバム・光と天気の予報・保存した旅）と
///   「旅の楽しみ」（すれちがい乗車券・旅のトランク・とおまわり号）。輪から外れる楽しみは下の段
/// - いいねした写真・設定・ログアウトは「ほか」。眉の節は3つ
/// - 意見を送る（札 #546）・使い方（札 #517）は、それぞれの札の担当がこの「ほか」に足す
struct SiteMenuView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var offline: OfflineTripStore
    @ObservedObject private var trunkAvailability = TrunkAvailability.shared
    @ObservedObject private var trunkEntry = TrunkEntryStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.section) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    JPEyebrowLine(L("旅の準備", "Plan a trip"))
                        .padding(.bottom, JPSpace.xxs)
                    // 旅行プラン（本人だけ・中身は本人しか読めない `/user/trips`）。**ログイン中だけ**
                    // （未ログインの人に中身の無い画面を開かせない）
                    if auth.userId != nil {
                        NavigationLink { TripPlansView() } label: {
                            SiteMenuRow(title: L("旅行プラン", "Trip plans"), systemImage: "calendar",
                                        note: L("行きたい場所から日程を組む", "Plan days from places you want to go"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.tripPlans")
                    }
                    NavigationLink { AlbumsView() } label: {
                        SiteMenuRow(title: Labels.Navigation.albums, systemImage: "rectangle.stack",
                                    note: L("招待リンクで、旅の仲間と写真を集める", "Collect photos with your travel companions"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("menu.albums")
                    if auth.userId != nil {
                        // 光と天気の予報（Pro）。前は設定の Pro の節にしか一覧の入口が無かった。
                        // Pro でない人には一覧の画面が Pro の案内を出す（`LightForecastView` の `.notPro`）
                        NavigationLink { LightForecastView() } label: {
                            SiteMenuRow(title: L("光と天気の予報", "Light & weather forecast"), systemImage: "sun.max",
                                        note: L("行きたい場所の今週の光\u{2002}Pro", "This week's light at your wishlist\u{2002}Pro"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.lightForecast")
                    }
                    // 保存した旅（Pro）。端末に保存した旅があるときだけ（無い人に空の画面を開かせない。
                    // 保存は旅行プラン・撮影スポットの頁から）。前は設定の Pro の節にしか入口が無かった
                    if offline.hasLocalData {
                        NavigationLink { OfflineSavedView() } label: {
                            SiteMenuRow(title: L("保存した旅", "Offline trips"), systemImage: "arrow.down.circle",
                                        note: L("圏外でも開ける\u{2002}Pro", "Opens without a connection\u{2002}Pro"),
                                        value: OfflineTripText.settingsDetail(count: offline.saved.count,
                                                                              bytes: offline.totalBytes))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.offlineTrips")
                    }
                }

                if auth.userId != nil {
                    VStack(alignment: .leading, spacing: JPSpace.xxs) {
                        JPEyebrowLine(L("旅の楽しみ", "Travel extras"))
                            .padding(.bottom, JPSpace.xxs)
                        // すれちがい乗車券（帳の頭に入り切りの行がある・`PassBookView`）。右の値はいまの入り切り
                        NavigationLink { PassBookView() } label: {
                            SiteMenuRow(title: PassTicket.featureName, systemImage: "ticket",
                                        note: L("すれちがい帳と入り切り", "Your pass book and on/off"),
                                        value: pass.settings.enabled ? pass.settings.mode.label : L("オフ", "Off"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.pass")
                        trunkRow
                        camperRow
                    }
                }

                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    JPEyebrowLine(L("ほか", "More"))
                        .padding(.bottom, JPSpace.xxs)
                    if auth.userId != nil {
                        NavigationLink { FavoritesView() } label: {
                            SiteMenuRow(title: Labels.Navigation.favorites, systemImage: "heart",
                                        note: L("ハートを押した写真、作者に届きます", "Photos you liked, the author is told"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.favorites")
                    }
                    NavigationLink { SettingsView() } label: {
                        SiteMenuPlainRow(title: L("設定", "Settings"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("menu.settings")
                    if auth.isAdmin {
                        Button {
                            openURL(AppConfig.siteBaseURL.appendingPathComponent("admin"))
                        } label: {
                            SiteMenuPlainRow(title: L("管理", "Admin"))
                        }
                        .buttonStyle(.plain)
                    }
                    // **ログアウトはログイン中だけ。** 設定の最下部と同じ手順
                    // （通知の宛先を外してから抜ける・`SettingsView.logoutSection`）
                    if auth.userId != nil {
                        Button {
                            // 印は `AuthStore` の共有のもの（メニューは先に閉じるので、
                            // 画面の印では閉じる間の2発目を止められない）
                            guard !auth.isSigningOut else { return }
                            dismiss()
                            auth.startSigningOut { await push.signingOut() }
                        } label: {
                            SiteMenuPlainRow(title: Labels.Navigation.logout, isQuiet: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.logout")
                        .disabled(auth.isSigningOut)
                    }
                }

                footer
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.l)
            .padding(.bottom, JPSpace.section)
        }
        .webScreen()
        .navigationTitle(L("メニュー", "Menu"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
        }
        // 旅のトランクの行（口が読めたことのある人だけ）と硬貨の数。読むかは決まりのとおり
        // （覚えている人は 6 時間に1回・`TrunkAvailabilityRule`・`TrunkEntryRule`）。設定から移した（2026-11-12）
        .task(id: auth.userId) {
            await trunkAvailability.refresh(userId: auth.userId, service: environment.trunk)
            await trunkEntry.refresh(userId: auth.userId, available: trunkAvailability.isAvailable,
                                     service: environment.trunk)
        }
    }

    /// 旅のトランク（2026-11-12 に設定の「旅の道具」から移した）。**口が読めたことのある人だけ**（`TrunkEntryRule.shows`）。
    /// 右の値は硬貨の枚数（読めていれば）。読み上げは硬貨と貼っていないラベルの有無
    @ViewBuilder
    private var trunkRow: some View {
        if TrunkEntryRule.shows(signedIn: auth.userId != nil, available: trunkAvailability.isAvailable) {
            NavigationLink {
                MyNameLoader { name in
                    TrunkView(ownerName: name)
                }
                .onDisappear { trunkEntry.markStale() }
            } label: {
                SiteMenuRow(title: TrunkEntryText.title, systemImage: "suitcase",
                            note: TrunkEntryText.detail,
                            value: trunkEntry.summary.map { TrunkEntryText.coins($0.coins) })
            }
            .buttonStyle(.plain)
            // 押せる1つのボタンのまま、名前と値を付ける（`.ignore` で包むと VoiceOver の2回叩きで開けない）
            .accessibilityLabel(TrunkEntryText.title)
            .accessibilityValue(TrunkEntryText.accessibilityValue(trunkEntry.summary))
            .accessibilityIdentifier("menu.trunk")
            // トランクから戻ったら数を読み直す（`markStale` のときだけ読む）
            .onAppear {
                Task {
                    await trunkEntry.refresh(userId: auth.userId, available: trunkAvailability.isAvailable,
                                             service: environment.trunk)
                }
            }
        }
    }

    /// 写真で作るキャンピングカー「とおまわり号」（2026-11-12 に設定から移した）。**メニューは自分の写真を持たない**ので、
    /// 行き先が自分で読む（`CamperGarageLoader`・読めるまでは車の画面を出さない）
    private var camperRow: some View {
        NavigationLink {
            MyNameLoader { name in
                CamperGarageLoader(ownerName: name, userId: auth.userId)
            }
        } label: {
            SiteMenuRow(title: CamperText.carName, systemImage: "bus",
                        note: L("写真で作るキャンピングカー、撮るほど部品が集まる",
                                "A camper made from your photos, collect parts as you shoot"))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.camper")
    }

    /// 規約のリンク（真鍮・黒地の上・外へ出るリンク——CLAUDE.md の owner の好み「出典と規約のリンクは真鍮」）と版
    private var footer: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            HStack(spacing: JPSpace.m) {
                Link(destination: LegalConsent.termsURL) {
                    Text(L("利用規約", "Terms of Use")).underline()
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                Link(destination: LegalConsent.privacyURL) {
                    Text(L("プライバシーポリシー", "Privacy Policy")).underline()
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
            }
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.accent)
            Text("Journey Photo \(Self.version)\u{2002}journey-photo.com")
                .font(JPFont.meta)
                .foregroundStyle(WebTheme.text3)
        }
    }

    /// 表に出る版（`MARKETING_VERSION`）
    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

/// 「見る」の行（v2 の板 SiteMenu の `.mi`）: 72 の高さ・左に 40 の角 12 の印の札（#161617）・
/// 明朝の題（板 19 → 字の段の 18）・下に一行の説明（12・text-3）・右に ›・下に白 8% の線
struct SiteMenuRow: View {
    let title: String
    let systemImage: String
    let note: String
    /// 右の値（入り切り・硬貨の枚数・保存した旅の数。2026-11-12 に設定の行から移したもの）。無ければ出さない
    var value: String? = nil

    /// 行の高さ（板の 72）
    nonisolated static let height: CGFloat = 72
    /// 印の札の大きさ（板の 40）
    nonisolated static let iconTile: CGFloat = 40

    var body: some View {
        HStack(spacing: JPSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(WebTheme.text)
                .frame(width: Self.iconTile, height: Self.iconTile)
                .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                Text(note)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                // 設定の行の値と同じ形（等幅の数字・text-2）
                Text(value)
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Self.height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 「アカウント」の行（板: 52 の高さ・題 15・右に ›・下に白 8% の線）。
/// `isQuiet`（ログアウト）は text-2 の字で、› も線も付けない（板の最後の行）
struct SiteMenuPlainRow: View {
    let title: String
    var isQuiet = false

    var body: some View {
        HStack(spacing: JPSpace.s) {
            Text(title)
                .font(JPFont.body)
                .foregroundStyle(isQuiet ? WebTheme.text2 : WebTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isQuiet {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: JPHeight.row)
        .overlay(alignment: .bottom) {
            if !isQuiet {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 自分の名前を読んでから中身に渡す（旅のトランク・とおまわり号の画面は持ち主の名前を出す）。
/// 読めるまでは nil で出す（どちらの画面も名前なしの形で描ける）。2026-11-12・メニューから開く口のため
struct MyNameLoader<Content: View>: View {
    @ViewBuilder let content: (String?) -> Content
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var name: String?

    var body: some View {
        content(name)
            .task(id: auth.userId) {
                guard auth.userId != nil else { return }
                let profiles = environment.profiles
                let fresh = try? await profiles.myProfile()
                if let fresh { name = fresh.name }
            }
    }
}
