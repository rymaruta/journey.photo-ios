import SwiftUI

struct RootView: View {

    let configurationError: String?

    @EnvironmentObject private var auth: AuthStore
    @State private var selection: Tab = .gallery

    enum Tab: Hashable {
        case gallery, upload, mypage
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                GalleryView()
            }
            .tabItem { Label("ギャラリー", systemImage: "photo.on.rectangle.angled") }
            .tag(Tab.gallery)

            NavigationStack {
                UploadView()
            }
            .tabItem { Label("投稿", systemImage: "camera") }
            .tag(Tab.upload)

            NavigationStack {
                MyPageView()
            }
            .tabItem { Label("マイページ", systemImage: "person.crop.circle") }
            .tag(Tab.mypage)
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
}
