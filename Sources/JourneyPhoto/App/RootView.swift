import SwiftUI

struct RootView: View {

    let configurationError: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: Tab = .gallery
    @State private var unread = 0

    enum Tab: Hashable {
        case gallery, search, notifications, mypage
    }

    var body: some View {
        Group {
            if consent.needsConsent {
                // **使う前に規約へ同意させる**（審査要件 1.2 / UGC）
                LegalGateView()
            } else {
                tabs
            }
        }
        .overlay(alignment: .top) {
            if let configurationError {
                Text(L("認証の初期化に失敗しました: \(configurationError)", "Sign-in setup failed: \(configurationError)"))
                    .font(.footnote)
                    .padding(8)
                    .background(.thinMaterial)
            }
        }
    }

    /// 未読の数だけを取りに行く。
    ///
    /// **開いたことにはしない。** 既読にするのは `NotificationsView` が
    /// 一覧を読めたときだけ——ここで既読にすると、バッジを見ただけで消える。
    private func refreshUnread() async {
        guard auth.userId != nil else {
            unread = 0
            return
        }
        unread = (try? await environment.notifications.fetch().unread) ?? 0
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack {
                GalleryView()
            }
            .tabItem { Label(Labels.Navigation.gallery, systemImage: "photo.on.rectangle.angled") }
            .tag(Tab.gallery)

            NavigationStack {
                SearchView()
            }
            .tabItem { Label(L("さがす", "Search"), systemImage: "magnifyingglass") }
            .tag(Tab.search)

            NavigationStack {
                NotificationsView()
            }
            .tabItem { Label(L("お知らせ", "Activity"), systemImage: "bell") }
            .badge(unread)
            .tag(Tab.notifications)

            NavigationStack {
                MyPageView()
            }
            .tabItem { Label(Labels.Navigation.mypage, systemImage: "person.crop.circle") }
            .tag(Tab.mypage)
        }
        .task(id: auth.userId) { await refreshUnread() }
        .onChange(of: selection) { _, tab in
            // お知らせを開いたら、閉じたときに数え直す
            if tab != .notifications {
                Task { await refreshUnread() }
            }
        }
    }
}
