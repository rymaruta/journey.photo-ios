import SwiftUI

struct RootView: View {

    let configurationError: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: Tab = .home
    @State private var unread = 0
    @Environment(\.scenePhase) private var scenePhase
    /// 投稿の「＋」から開くもの
    @State private var showPostChoice = false
    @State private var showPhotoUpload = false
    /// 今日のテーマから来たときのタグ（投稿画面に最初から入れておく）
    @State private var pendingThemeTag: String?
    @ObservedObject private var missions = MissionRouter.shared
    @ObservedObject private var tabRouter = TabRouter.shared
    @State private var showStoryComposer = false
    /// お知らせ（タブから外してヘッダーへ移した）
    @State private var showNotifications = false
    /// 見出しの「メニュー（≡）」（板 01d）
    @State private var showMenu = false
    /// 通知を押して開いたか（`AppDelegate` から届く）
    @StateObject private var router = NotificationRouter.shared
    /// 通知を押したあと、ほかのシートが閉じるのを待っている間の仕事
    @State private var activityWait: Task<Void, Never>?

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

    /// 通知を押した分を受け取って、お知らせを出す。
    ///
    /// 🔴 **ほかのシートが出ている間は、お知らせのシートは出ない**
    /// （SwiftUI は1つずつ——黙って無視される）。投稿の2択・メニューは
    /// 何も抱えていないので閉じる。それ以外（投稿・ストーリー・写真の中の
    /// シート）は**勝手に閉じない**——書きかけが消えるので、閉じられるのを
    /// 待ってから出す
    private func takeActivityRequest() {
        guard router.takePendingActivity() else { return }
        // 既に開いている: お知らせの画面が数を見て読み直す
        guard !showNotifications else { return }
        showPostChoice = false
        showMenu = false
        activityWait?.cancel()
        activityWait = Task { @MainActor in
            // 閉じる動きが終わるのを待ってから確かめる
            repeat {
                try? await Task.sleep(nanoseconds: 300_000_000)
            } while !Task.isCancelled && ModalProbe.isPresenting()
            guard !Task.isCancelled else { return }
            // 通知はタブではなくなったので、ホームのヘッダーから開く
            selection = .home
            showNotifications = true
        }
    }

    private var tabs: some View {
        // **同じ札をもう一度押したことを拾う。** `$selection` のままだと
        // 値が変わらないので何も届かない。本物の TabView は選ばれている札を
        // 押しても setter を呼ぶので、そこで比べる
        TabView(selection: Binding(
            get: { selection },
            set: { tapped in
                tabRouter.tabTapped(isHome: tapped == .home, alreadySelected: tapped == selection)
                selection = tapped
            }
        )) {
            NavigationStack {
                GalleryView(unread: unread, onOpenNotifications: { showNotifications = true })
            }
            .tabItem { Label(L("ホーム", "Home"), systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                SearchView(unread: unread, onOpenNotifications: { showNotifications = true })
            }
            .tabItem { Label(Labels.Navigation.searchTab, systemImage: "magnifyingglass") }
            .tag(Tab.search)

            // **中央は投稿。** 押すと写真／ストーリーの2択が出る。
            // **画面は持たない**——`onChange` でシートを出し、元のタブへ戻す
            Color.clear
                .tabItem { Label(L("投稿", "Post"), systemImage: "plus.app") }
                .tag(Tab.post)

            // **4つ目は地図**（指示書 4-1 の並び）。旅の一冊は
            // マイページから開く——撮った本人の記録なので持ち場が合う
            NavigationStack {
                PhotoMapView(unread: unread,
                             onOpenNotifications: { showNotifications = true },
                             onPost: { showPostChoice = true })
            }
            .tabItem { Label(Labels.Navigation.mapTab, systemImage: "map") }
            .tag(Tab.map)

            NavigationStack {
                MyPageView()
            }
            .tabItem { Label(Labels.Navigation.mypage, systemImage: "person") }
            .tag(Tab.mypage)
        }
        .task(id: auth.userId) { await refreshUnread() }
        // **前面に戻ったら数え直す。** 裏にいる間に届いた通知の分が、
        // お知らせを開くかログインし直すまでベルに出ていなかった
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshUnread() } }
        }
        // **押した通知の行き先。** 数で見るのは、2回続けて押したときに
        // 「変わっていない」と見なされて2回目が効かなくなるため
        .onChange(of: router.openActivityRequests) { _, _ in
            takeActivityRequest()
        }
        // **画面が出てきたときにも取りに行く。** 冷えた状態から押した回・
        // 規約の同意画面が出ていた回は、数が変わった瞬間にここが居なかった
        .onAppear { takeActivityRequest() }
        // **開いている間に届いた通知もベルに出す**（`AppDelegate.willPresent`）
        .onChange(of: router.arrivals) { _, _ in
            Task { await refreshUnread() }
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
        // メニューの「マイページ」が押されたら、マイページの札へ移る
        .onChange(of: tabRouter.myPageRequests) { _, _ in
            selection = .mypage
        }
        // 見出しの「探す」（ホームだけ）→ 探すの札へ
        .onChange(of: tabRouter.searchRequests) { _, _ in
            selection = .search
        }
        // メニューの「撮影地マップ」→ マップの札へ
        .onChange(of: tabRouter.mapRequests) { _, _ in
            selection = .map
        }
        .onChange(of: tabRouter.menuRequests) { _, _ in
            showMenu = true
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
        // **閉じたら知らせる**（`TabRouter.postSheetsClosed`）。マイページの
        // 格子とストーリーの行はこれを見て読み直す
        .sheet(isPresented: $showPhotoUpload, onDismiss: { tabRouter.postSheetClosed() }) {
            NavigationStack { UploadView(initialTag: pendingThemeTag) }
        }
        .sheet(isPresented: $showStoryComposer, onDismiss: { tabRouter.postSheetClosed() }) {
            NavigationStack { StoryComposerView() }
        }
        .sheet(isPresented: $showMenu) {
            NavigationStack { SiteMenuView() }
        }
        // お知らせを閉じたら数え直す（タブではなくシートになったので）
        .sheet(isPresented: $showNotifications, onDismiss: { Task { await refreshUnread() } }) {
            NavigationStack {
                NotificationsView()
                    // **閉じる口を画面に置く。** タブからシートへ移したとき
                    // 閉じるボタンを足しておらず、下へ払う以外に閉じる手段が
                    // 無かった——owner は「✕が見えない、閉じられない」と
                    // 受け取った（2026-09-25）。置き場所はほかのシート
                    // （写真の編集・曲の選択）と同じ `cancellationAction`
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Labels.Common.close) { showNotifications = false }
                                .accessibilityIdentifier("notifications.close")
                        }
                    }
            }
        }
    }
}
