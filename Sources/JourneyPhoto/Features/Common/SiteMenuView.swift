import SwiftUI

/// 見出しの「メニュー（≡）」から開く一覧（板 01d・Web のハンバーガーと同じ並び）。
///
/// 2026-09-26 owner「ヘッダーのハンバーガーは残す（サイトから外さない）」。
/// **下の札にある場所（マップ・マイページ）は札へ移す**——同じ画面をこの中に
/// もう1つ積むと、戻る先が2通りになる。札に無い場所（いいねした写真・
/// 共同アルバム・設定）はこの中で開く。
///
/// 板にある「保存した写真」と「管理（管理者のときだけ）」は**まだ置かない**。
/// どちらもアプリに行き先の画面が無く、押しても何も出ない行になる。
struct SiteMenuView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(L("見る", "Browse")) {
                    // 撮影地マップ＝下の札の「マップ」
                    Button {
                        dismiss()
                        TabRouter.shared.openMap()
                    } label: {
                        JPRowLabel(title: L("撮影地マップ", "Photo map"), systemImage: "map")
                    }
                    .buttonStyle(JPRowButtonStyle())
                    .accessibilityIdentifier("menu.map")
                    // **ログイン中だけ。** 未ログインの人に中身の無い画面を開かせない
                    // （設定でもこの行はログイン中だけ出している）
                    if auth.userId != nil {
                        JPCardDivider()
                        NavigationLink { FavoritesView() } label: {
                            JPRowLabel(title: Labels.Navigation.favorites, systemImage: "heart")
                        }
                        .buttonStyle(JPRowButtonStyle())
                    }
                }
                section(L("アカウント", "Account")) {
                    Button {
                        dismiss()
                        TabRouter.shared.openMyPage()
                    } label: {
                        JPRowLabel(title: Labels.Navigation.mypage, systemImage: "person")
                    }
                    .buttonStyle(JPRowButtonStyle())
                    JPCardDivider()
                    NavigationLink { AlbumsView() } label: {
                        JPRowLabel(title: Labels.Navigation.albums, systemImage: "rectangle.stack")
                    }
                    .buttonStyle(JPRowButtonStyle())
                    JPCardDivider()
                    NavigationLink { SettingsView() } label: {
                        JPRowLabel(title: L("設定", "Settings"), systemImage: "gearshape")
                    }
                    .buttonStyle(JPRowButtonStyle())
                }
                // **ログアウトはログイン中だけ。** 設定の最下部と同じ手順
                // （通知の宛先を外してから抜ける・`SettingsView.logoutSection`）
                if auth.userId != nil {
                    JPCard {
                        Button {
                            dismiss()
                            Task {
                                await push.signingOut()
                                await auth.signOut()
                            }
                        } label: {
                            JPRowLabel(title: Labels.Navigation.logout,
                                       systemImage: "rectangle.portrait.and.arrow.right", chevron: false)
                        }
                        .buttonStyle(JPRowButtonStyle())
                        .accessibilityIdentifier("menu.logout")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(L("メニュー", "Menu"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            JPSectionTitle(title)
            JPCard { content() }
        }
    }
}
