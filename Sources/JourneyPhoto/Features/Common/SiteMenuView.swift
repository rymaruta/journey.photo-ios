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
///   説明で「いいね＝作者に届く／保存＝自分だけ」の違いを読ませる（板の付箋）
/// - 「アカウント」の行は 52 の素の行（題 15・右に ›）。ログアウトは text-2 の字で › を付けない
/// - 節の見出しは眉（真鍮＋消える線・`JPEyebrowLine`）。行は札で囲まず、白 8% の線で区切る
/// - 下に利用規約・プライバシーポリシーの真鍮のリンク（黒地の上・外へ出るリンク）と版
/// - 板は「旅行プラン」「共同アルバム」を「見る」に置く。並びは板どおり（2026-10-14 判断）
struct SiteMenuView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.section) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    JPEyebrowLine(L("見る", "Browse"))
                        .padding(.bottom, JPSpace.xxs)
                    // 撮影地マップ＝下の札の「マップ」
                    Button {
                        dismiss()
                        TabRouter.shared.openMap()
                    } label: {
                        SiteMenuRow(title: L("撮影地マップ", "Photo map"), systemImage: "map",
                                    note: L("撮影地と撮影スポットを地図で見る", "Shooting places and spots on the map"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("menu.map")
                    // **ログイン中だけ。** 未ログインの人に中身の無い画面を開かせない
                    // （設定でもこの行はログイン中だけ出している）
                    if auth.userId != nil {
                        NavigationLink { FavoritesView() } label: {
                            SiteMenuRow(title: Labels.Navigation.favorites, systemImage: "heart",
                                        note: L("ハートを押した写真 · 作者に届きます", "Photos you liked · the author is told"))
                        }
                        .buttonStyle(.plain)
                        NavigationLink { SavedPhotosView() } label: {
                            SiteMenuRow(title: L("保存した写真", "Saved photos"), systemImage: "bookmark",
                                        note: L("しおりで保存 · 自分だけ", "Bookmarked · only you can see"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.saved")
                        // 旅行プラン（本人だけ・中身は本人しか読めない `/user/trips`）。
                        // 以前はマイページの横並びのボタンにあったが、そのボタン列は
                        // マイページを板 05c に寄せたときに無くなった。板に入口が無いので、
                        // 札に無い場所を開くこのメニューに置く
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
                }

                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    JPEyebrowLine(L("アカウント", "Account"))
                        .padding(.bottom, JPSpace.xxs)
                    Button {
                        dismiss()
                        TabRouter.shared.openMyPage()
                    } label: {
                        SiteMenuPlainRow(title: Labels.Navigation.mypage)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { SettingsView() } label: {
                        SiteMenuPlainRow(title: L("設定", "Settings"))
                    }
                    .buttonStyle(.plain)
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
            Text("Journey Photo \(Self.version) · journey-photo.com")
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
