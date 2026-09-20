import SwiftUI

struct RootView: View {

    let configurationError: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var consent: LegalConsent
    @State private var selection: Tab = .gallery

    enum Tab: Hashable {
        case gallery, search, upload, notifications, mypage
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
                Text("認証の初期化に失敗しました: \(configurationError)")
                    .font(.footnote)
                    .padding(8)
                    .background(.thinMaterial)
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack {
                GalleryView()
            }
            .tabItem { Label("ギャラリー", systemImage: "photo.on.rectangle.angled") }
            .tag(Tab.gallery)

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("さがす", systemImage: "magnifyingglass") }
            .tag(Tab.search)

            NavigationStack {
                UploadView()
            }
            .tabItem { Label("投稿", systemImage: "camera") }
            .tag(Tab.upload)

            NavigationStack {
                NotificationsView()
            }
            .tabItem { Label("お知らせ", systemImage: "bell") }
            .tag(Tab.notifications)

            NavigationStack {
                MyPageView()
            }
            .tabItem { Label("マイページ", systemImage: "person.crop.circle") }
            .tag(Tab.mypage)
        }
    }
}
