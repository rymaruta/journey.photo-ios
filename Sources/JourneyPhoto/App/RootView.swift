import SwiftUI

struct RootView: View {

    let configurationError: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: Tab = .gallery
    @State private var unread = 0
    /// 投稿の「＋」から開くもの
    @State private var showPostChoice = false
    @State private var showPhotoUpload = false
    @State private var showStoryComposer = false
    /// 通知を押して開いたか（`AppDelegate` から届く）
    @StateObject private var router = NotificationRouter.shared

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
        // **Web と同じ「固定ダーク」にする。** `app/globals.css` が
        // `color-scheme: dark` で明暗の切り替えを持たない＝端末が
        // ライトでも黒地。ここで端末に従うと、ライトの人だけ別アプリに見える
        .preferredColorScheme(.dark)
        // 押せるものは白（Web の `--accent-bg` は白92%）。既定の橙は
        // Web のどこにも出てこない色だった
        .tint(WebTheme.foreground)
        .background(WebTheme.background)
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
        // **押した通知の行き先。** 数で見るのは、2回続けて押したときに
        // 「変わっていない」と見なされて2回目が効かなくなるため
        .onChange(of: router.openActivityRequests) { _, _ in
            selection = .notifications
        }
        // **どの画面からでも投稿できるようにする。** Web も同じ理由で
        // 全ページに「＋」を置いている（`app/components/PostFab.tsx`——
        // owner の「どこに投稿する機能があるか分かりづらい」から）。
        // アプリは入口がマイページの中だけで、同じ分かりにくさがあった。
        // **投稿・ストーリーの画面はシートで全面に出る**ので、
        // Web のような「出さないページ」の判定は要らない
        // 鳴っている間だけ、どの画面にも出る（Web の `MiniPlayer`）
        .overlay(alignment: .bottom) {
            MiniPlayerBar().padding(.bottom, 56)
        }
        .overlay(alignment: .bottomTrailing) {
            if auth.userId != nil {
                Button {
                    showPostChoice = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(width: 56, height: 56)
                        .background(WebTheme.accentBackground, in: Circle())
                        .shadow(radius: 12)
                }
                .accessibilityLabel(L("投稿する", "Post"))
                .accessibilityIdentifier("post.fab")
                // タブバーの上に逃がす（Web も下の物の上に置いている）
                .padding(.trailing, 16)
                .padding(.bottom, 72)
            }
        }
        .sheet(isPresented: $showPostChoice) {
            PostSheet { kind in
                switch kind {
                case .photo: showPhotoUpload = true
                case .story: showStoryComposer = true
                }
            }
        }
        .sheet(isPresented: $showPhotoUpload) {
            NavigationStack { UploadView() }
        }
        .sheet(isPresented: $showStoryComposer) {
            NavigationStack { StoryComposerView() }
        }
        .onChange(of: selection) { _, tab in
            // お知らせを開いたら、閉じたときに数え直す
            if tab != .notifications {
                Task { await refreshUnread() }
            }
        }
    }
}
