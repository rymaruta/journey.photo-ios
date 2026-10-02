import SwiftUI

struct RootView: View {

    let configurationError: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
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
    /// 「旅の写真からまとめて」（全画面）
    @State private var showTripImport = false
    /// 旅の写真から選んだ本体。**流れが閉じきってから**投稿画面を開き、そこへ渡す
    @State private var pendingTripPhotos: [Data] = []
    /// お知らせ（タブから外してヘッダーへ移した）
    @State private var showNotifications = false
    /// 見出しの「メニュー（≡）」（板 01d）
    @State private var showMenu = false
    /// 通知を押して開いたか（`AppDelegate` から届く）
    @StateObject private var router = NotificationRouter.shared
    /// 通知を押したあと、ほかのシートが閉じるのを待っている間の仕事
    @State private var activityWait: Task<Void, Never>?
    /// ベルから開き直すまでの間の仕事（`openNotificationsFromBell`）
    @State private var bellReopen: Task<Void, Never>?
    /// ベルの数え直しの世代。**最後に始めた取得だけを画面に出す**
    /// （既読にする前の遅い応答が、あとから古い数で上書きしないように）
    @State private var unreadGeneration = 0
    /// いまの `unread` が誰の数か。失敗の回に「いまの数を残す」のは、
    /// それが**同じ人の数**のときだけ——人が替わった直後の取得が捨てられ、
    /// 次の取得が失敗すると、前の人の数が残っていた
    @State private var unreadOwner: String?

    enum Tab: Hashable {
        // **提案の並び**（owner の絵・2026-09-21）:
        // ホーム / 探す / 投稿 / 旅 / マイページ。
        // 通知はタブを1つ使わずヘッダーへ移した（絵と同じ）
        case home, search, post, map, mypage

        /// もう一度押したときに合図を出す札（`TabRouter.tabTapped`）
        var reselectable: TabRouter.Reselectable? {
            switch self {
            case .home: return .home
            case .map: return .map
            case .search, .post, .mypage: return nil
            }
        }
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
    ///
    /// 🔴 **最後に出た1本の答えだけを、出したときと同じ人のときだけ書く。** ログイン・
    /// 前面に戻る・お知らせを閉じる、の3か所から同時に走るので、古い数が後から着いて
    /// 上書きしていた。ログアウトした後に前の人の数が出ることもあった
    ///
    /// - Parameter keepOnFailure: 引けなかった回に**いまの数を残す**。
    ///   圏外で戻っただけでベルの印が消えていた。人が替わった回（前の人の数を残さない）は
    ///   `unreadOwner` で 0 に倒す。お知らせを閉じた回も残す——既読にできた回は
    ///   `readMarks` で先に 0 になっており、既読化に失敗した回はアイコンの数も残るので、
    ///   ここで 0 に倒すとベルだけ 0 に割れる
    private func refreshUnread(keepOnFailure: Bool = false) async {
        guard auth.userId != nil else {
            unread = 0
            unreadOwner = nil
            return
        }
        let owner = auth.userId
        unreadGeneration += 1
        let generation = unreadGeneration
        let fetched = try? await environment.notifications.fetch().unread
        // **返ってくる間に人が替わっていた・もっと新しい取得が始まっていたら捨てる**
        // （失敗の回も。古い1本の失敗で、新しい1本の数を 0 に倒さない）
        guard !Task.isCancelled, auth.userId == owner, generation == unreadGeneration else { return }
        if let fetched {
            unread = fetched
            unreadOwner = owner
        } else if !keepOnFailure || unreadOwner != owner {
            unread = 0
            unreadOwner = owner
        }
    }

    /// 通知を押した分を受け取って、お知らせを出す。
    ///
    /// 🔴 **ほかのシートが出ている間は、お知らせのシートは出ない**
    /// （SwiftUI は1つずつ——黙って無視される）。閉じてよいのは投稿の2択
    /// だけ（何も抱えていない）。メニューの奥には親しい友達・パスワード変更の
    /// 書きかけがあり、投稿・ストーリー・写真の中のシートも同じなので、
    /// **勝手に閉じずに**閉じられるのを待ってから出す。
    ///
    /// **開くのは `activityWaitLimit` までに閉じられた回だけ。** それより
    /// 遅いと、何分も後に突然お知らせが出てタブが動き、壊れて見える。
    /// その回は、閉じられたときに「ベルから見られる」と知らせる
    /// （シートが出ている間に知らせても、シートの裏に出て見えない）
    private func takeActivityRequest() {
        guard router.takePendingActivity() else { return }
        if showNotifications {
            // 本当に出ている: お知らせの画面が数を見て読み直す。
            // ただしログインしていない（中はログイン画面）なら、押した通知が誰宛てか
            // 分からないので行き先は捨てる（ログインした直後に別の人の画面を積まない）
            if ModalProbe.isPresenting() {
                // ログインの確認中（冷えた起動）は、確認が終わってから決める——確認中に捨てると
                // 正しい押し方の行き先まで落ち、決めずに抜けると未ログインのときに残った
                // 待ちは1本だけ（`activityWait`・押すたびに前の分を止める。裏へ回った・人が替わった
                // ときの `cancelActivityWait` でも止まる）
                activityWait?.cancel()
                activityWait = Task { @MainActor in
                    while !Task.isCancelled && auth.isResolving {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                    if !Task.isCancelled && auth.userId == nil { router.dropPendingTarget() }
                }
                return
            }
            // **出ていないのに true のまま**（出せなかった回）。残すと、この先
            // 押してもベルを押しても true → true で何も起きなくなる
            showNotifications = false
        }
        showPostChoice = false
        activityWait?.cancel()
        activityWait = Task { @MainActor in
            let started = Date()
            // **冷えた起動ではまずログインの確認を待つ。** 確認中は `userId` が
            // nil なので、ここで持ち主を決めると確認が終わった瞬間に
            // 「人が替わった」と見なして押した分を捨てていた
            while !Task.isCancelled && auth.isResolving {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            let owner = auth.userId
            // 閉じる動きが終わるのを待ってから確かめる。
            // 待っている間に（ベルなどから）お知らせが開いたら、そこで終える
            repeat {
                try? await Task.sleep(nanoseconds: 300_000_000)
            } while !Task.isCancelled && !showNotifications && ModalProbe.isPresenting()
            // **待っている間に人が替わっていたら開かない**（前の人の通知で
            // 次の人のお知らせを開かない）。ログインしていない人には開かない
            // （起動の確認で期限切れと分かった回など）
            guard !Task.isCancelled else { return }
            // **ログインしていない回は黙らない。** 圏外で起動して「分からない」扱いの
            // 人にも通知は届き続けるので、押しても何も起きないと壊れて見える
            let waited = Date().timeIntervalSince(started)
            guard let owner else {
                // 開かない回は、押した通知の行き先も捨てる（後でベルから開いた回に積まない）
                router.dropPendingTarget()
                // **待った後の今で確かめる。** 押したときのログイン画面でログインして
                // 閉じた回に「ログインしてください」と出ていた。何分も後にも言わない
                if auth.userId == nil {
                    if waited <= Self.activityHintLimit {
                        toasts.show(L("お知らせを見るにはログインしてください",
                                      "Sign in to see your notifications"))
                    }
                } else {
                    // 待っている間にログインした: 押した通知が誰あてか分からないので
                    // 開かないが、黙りもしない（押しても何も起きないと壊れて見える）
                    // 待っている間にベルから開いていれば、それで済んでいる
                    if waited <= Self.activityHintLimit, !showNotifications {
                        toasts.show(L("新しいお知らせは、右上のベルから見られます",
                                      "New activity is waiting behind the bell"))
                    }
                    await refreshUnread(keepOnFailure: true)
                }
                return
            }
            guard auth.userId == owner else {
                router.dropPendingTarget()
                return
            }
            // 待っている間に（ベルなどから）開いた: それで済んでいる。
            // **ここで「出せずに残った」と見なして戻さない**——開いた直後の
            // 描画が済む前だと、押したばかりのベルを取り消してしまう
            // （true のまま残った回は、次に押したときの入口で戻す）
            guard !showNotifications else { return }
            guard waited <= Self.activityWaitLimit else {
                router.dropPendingTarget()
                // あまりに後（何分も経ってから）の知らせは、何のことか分からない
                if waited <= Self.activityHintLimit {
                    toasts.show(L("新しいお知らせは、右上のベルから見られます",
                                  "New activity is waiting behind the bell"))
                }
                await refreshUnread(keepOnFailure: true)
                return
            }
            // 通知はタブではなくなったので、ホームのヘッダーから開く
            selection = .home
            showNotifications = true
        }
    }

    /// ベルを押した。**true のまま出ていない回**（SwiftUI が黙って無視した）は
    /// 一度戻してから開く——そのままだと true → true で何も起きない
    private func openNotificationsFromBell() {
        bellReopen?.cancel()
        guard showNotifications, !ModalProbe.isPresenting() else {
            showNotifications = true
            return
        }
        showNotifications = false
        let owner = auth.userId
        bellReopen = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            // 待つ間にほかのシートが出た・人が替わった・もう開いた: 開かない
            // （ほかのシートの裏で true にすると、また出ないまま残る）
            guard !Task.isCancelled, auth.userId == owner,
                  !showNotifications, !ModalProbe.isPresenting() else { return }
            showNotifications = true
        }
    }

    /// 通知を押したあと、ほかのシートが閉じられるのを待つ長さ
    private static let activityWaitLimit: TimeInterval = 5
    /// それを過ぎて閉じられたときに「ベルから見られる」と知らせる長さ
    private static let activityHintLimit: TimeInterval = 60

    /// 待ちをやめる（人が替わった・裏へ回った・画面が消えた）。
    /// **前の人の通知で、次の人のお知らせを開かない**
    private func cancelActivityWait() {
        activityWait?.cancel()
        activityWait = nil
        bellReopen?.cancel()
        bellReopen = nil
        // 押した通知の行き先も捨てる（後でベルから開いた回に勝手に積まない・次の人に出さない）
        router.dropPendingTarget()
    }

    private var tabs: some View {
        // **同じ札をもう一度押したことを拾う。** `$selection` のままだと
        // 値が変わらないので何も届かない。本物の TabView は選ばれている札を
        // 押しても setter を呼ぶので、そこで比べる
        TabView(selection: Binding(
            get: { selection },
            set: { tapped in
                tabRouter.tabTapped(tapped.reselectable, alreadySelected: tapped == selection)
                selection = tapped
            }
        )) {
            NavigationStack {
                GalleryView(unread: unread, onOpenNotifications: { openNotificationsFromBell() })
            }
            .tint(WebTheme.foreground)
            .tabItem { Label(L("ホーム", "Home"), systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                SearchView(unread: unread, onOpenNotifications: { openNotificationsFromBell() })
            }
            .tint(WebTheme.foreground)
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
                             onOpenNotifications: { openNotificationsFromBell() },
                             onPost: { showPostChoice = true })
            }
            .tint(WebTheme.foreground)
            .tabItem { Label(Labels.Navigation.mapTab, systemImage: "map") }
            .tag(Tab.map)

            NavigationStack {
                MyPageView()
            }
            .tint(WebTheme.foreground)
            .tabItem { Label(Labels.Navigation.mypage, systemImage: "person") }
            .tag(Tab.mypage)
        }
        // **選んでいるタブは真鍮**（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29））。タブの札の色は TabView の tint で決まる。
        // 中身には各タブの `.tint(WebTheme.foreground)`（白）で配り直す——真鍮を中身の
        // 既定の押せる色にまで広げない（`.borderedProminent` の白地の注記と同じ理由）
        .tint(WebTheme.accent)
        .task(id: auth.userId) { await refreshUnread() }
        // **人が替わったら待ちをやめる。** `.task(id:)` の中で取り消すと、
        // 出てきた瞬間（`onAppear` で待ちを作った直後）にも走って、
        // 冷えた起動で押した分を自分で消してしまう。`onChange` は初回に走らない
        // （ログインの確認が終わった nil → ID は「替わった」ではない）
        .onChange(of: auth.userId) { previous, _ in
            if previous != nil { cancelActivityWait() }
        }
        // **前面に戻ったら数え直す。** 裏にいる間に届いた通知の分が、
        // お知らせを開くかログインし直すまでベルに出ていなかった
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshUnread(keepOnFailure: true) } }
            if phase == .background { cancelActivityWait() }
        }
        .onDisappear { cancelActivityWait() }
        // **開いたはずなのに出ていない**（ほかのシートが閉じる途中にベルを
        // 押した回など、SwiftUI が黙って無視した）ときは戻す。残すと、この先
        // ベルを押しても true → true で何も起きない。描画が済むのを待ってから見る
        .onChange(of: showNotifications) { _, shown in
            guard shown else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if showNotifications && !ModalProbe.isPresenting() { showNotifications = false }
            }
        }
        // **押した通知の行き先。** 数で見るのは、2回続けて押したときに
        // 「変わっていない」と見なされて2回目が効かなくなるため
        .onChange(of: router.openActivityRequests) { _, _ in
            takeActivityRequest()
        }
        // **画面が出てきたときにも取りに行く。** 冷えた状態から押した回・
        // 規約の同意画面が出ていた回は、数が変わった瞬間にここが居なかった
        .onAppear { takeActivityRequest() }
        // お知らせを既読にできた（またはサーバーの未読がもう 0 だった）: 閉じたときの数え直しが落ちても 0 にする
        .onChange(of: router.readMarks) { _, _ in
            guard router.readOwner != nil, router.readOwner == auth.userId else { return }
            unreadGeneration += 1
            unread = 0
            unreadOwner = auth.userId
            // 既読のあとに届いた分は数え直す（0 のままにしない）。
            // 落ちても 0 は残る
            Task { await refreshUnread() }
        }
        // **開いている間に届いた通知もベルに出す**（`AppDelegate.willPresent`）
        // `.task(id:)` にするのは、続けて届いたときに前の取得を取り消すため
        // （遅れて返った古い数で上書きしない）
        .task(id: router.arrivals) {
            guard router.arrivals > 0 else { return }
            await refreshUnread(keepOnFailure: true)
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
            if !shown {
                pendingThemeTag = nil
                // 旅の写真も同じ（次の投稿に同じ写真が並ばない）
                pendingTripPhotos = []
            }
        }
        .sheet(isPresented: $showPostChoice) {
            PostSheet { kind in
                switch kind {
                case .photo: showPhotoUpload = true
                case .story: showStoryComposer = true
                case .trip: showTripImport = true
                }
            }
        }
        // **閉じきってから投稿画面を開く**（onDismiss）。閉じている途中に次を出すと出ないことがある
        .fullScreenCover(isPresented: $showTripImport, onDismiss: {
            if !pendingTripPhotos.isEmpty { showPhotoUpload = true }
        }) {
            LibraryTripFlowView { photos in pendingTripPhotos = photos }
        }
        // **閉じたら知らせる**（`TabRouter.postSheetsClosed`）。マイページの
        // 格子とストーリーの行はこれを見て読み直す
        .sheet(isPresented: $showPhotoUpload, onDismiss: { tabRouter.postSheetClosed() }) {
            // 旅の写真から来たときは、その写真を並べて**非公開で**始める
            NavigationStack {
                UploadView(initialTag: pendingThemeTag, initialPhotos: pendingTripPhotos,
                           startPrivate: !pendingTripPhotos.isEmpty)
            }
        }
        .sheet(isPresented: $showStoryComposer, onDismiss: { tabRouter.postSheetClosed() }) {
            NavigationStack { StoryComposerView() }
        }
        .sheet(isPresented: $showMenu, onDismiss: { tabRouter.menuSheetClosed() }) {
            NavigationStack { SiteMenuView() }
        }
        // お知らせを閉じたら数え直す（タブではなくシートになったので）
        .sheet(isPresented: $showNotifications, onDismiss: { Task { await refreshUnread(keepOnFailure: true) } }) {
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
