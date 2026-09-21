import SwiftUI

struct RootView: View {

    let configurationError: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: Tab = .home
    @State private var unread = 0
    /// 投稿の「＋」から開くもの
    @State private var showPostChoice = false
    @State private var showPhotoUpload = false
    /// 今日のテーマから来たときのタグ（投稿画面に最初から入れておく）
    @State private var pendingThemeTag: String?
    @ObservedObject private var missions = MissionRouter.shared
    @State private var showStoryComposer = false
    /// お知らせ（タブから外してヘッダーへ移した）
    @State private var showNotifications = false
    /// 通知を押して開いたか（`AppDelegate` から届く）
    @StateObject private var router = NotificationRouter.shared

    enum Tab: Hashable {
        // **提案の並び**（owner の絵・2026-09-21）:
        // ホーム / 探す / 投稿 / 旅 / マイページ。
        // 通知はタブを1つ使わずヘッダーへ移した（絵と同じ）
        case home, search, post, map, mypage
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
                GalleryView(unread: unread, onOpenNotifications: { showNotifications = true })
            }
            .tabItem { Label(L("ホーム", "Home"), systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                SearchView()
            }
            .tabItem { Label(L("探す", "Search"), systemImage: "magnifyingglass") }
            .tag(Tab.search)

            // **中央は投稿。** 押すと写真／ストーリーの2択が出る。
            // **画面は持たない**——`onChange` でシートを出し、元のタブへ戻す
            Color.clear
                .tabItem { Label(L("投稿", "Post"), systemImage: "plus.app") }
                .tag(Tab.post)

            // **4つ目は地図**（指示書 4-1 の並び）。旅の一冊は
            // マイページから開く——撮った本人の記録なので持ち場が合う
            NavigationStack {
                PhotoMapView()
            }
            .tabItem { Label(L("マップ", "Map"), systemImage: "map") }
            .tag(Tab.map)

            NavigationStack {
                MyPageView()
            }
            .tabItem { Label(Labels.Navigation.mypage, systemImage: "person") }
            .tag(Tab.mypage)
        }
        .task(id: auth.userId) { await refreshUnread() }
        // **押した通知の行き先。** 数で見るのは、2回続けて押したときに
        // 「変わっていない」と見なされて2回目が効かなくなるため
        .onChange(of: router.openActivityRequests) { _, _ in
            // 通知はタブではなくなったので、ホームのヘッダーから開く
            selection = .home
            showNotifications = true
        }
        // **中央の「投稿」はタブではなく入口。** 選ばれたら2択を出して、
        // タブは元へ戻す（空の画面を見せない）
        .onChange(of: selection) { previous, tab in
            if tab == .post {
                selection = previous == .post ? .home : previous
                showPostChoice = true
            }
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
        // 短い知らせ（Web の `Toast`）。ミニプレイヤーより上に出す
        .overlay(alignment: .bottom) {
            ToastOverlay().padding(.bottom, 116)
        }
        // 「参加する」が押されたら、投稿画面をそのタグで開く
        .onChange(of: missions.requests) { _, _ in
            pendingThemeTag = missions.tag
            showPhotoUpload = true
        }
        // 今日のテーマの「参加する」から来たときのタグ。
        // **投稿画面を閉じたら忘れる**（次の投稿に引きずらない）
        .onChange(of: showPhotoUpload) { _, shown in
            if !shown { pendingThemeTag = nil }
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
            NavigationStack { UploadView(initialTag: pendingThemeTag) }
        }
        .sheet(isPresented: $showStoryComposer) {
            NavigationStack { StoryComposerView() }
        }
        // お知らせを閉じたら数え直す（タブではなくシートになったので）
        .sheet(isPresented: $showNotifications, onDismiss: { Task { await refreshUnread() } }) {
            NavigationStack { NotificationsView() }
        }
    }
}
