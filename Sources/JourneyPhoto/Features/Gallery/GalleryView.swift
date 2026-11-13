import SwiftUI

struct GalleryView: View {

    // 起動直後の停止の切り分け（UI テストのときだけ・`PerfRecorder.event`・2026-11-07 札 #435 / #429）: 作られた時刻
    private let perfInit: Void = PerfRecorder.shared.event("GalleryView.init")

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// **「見せない」が変わったら読み直すため**に見ている。
    /// この画面はタブの根なので一度出たら生き続け、`.task` は二度と走らない
    /// ——ブロックしても、戻ってくるとその人の写真がまだ並んでいた
    @EnvironmentObject private var hidden: ModerationStore
    /// 電波があるか（電波が無いときは前に見た写真の上に帯・2026-11-12 第2章）
    @EnvironmentObject private var connectivity: Connectivity
    @StateObject private var model = GalleryViewModel()
    /// すれちがいの届いた束（板 PassHome・2026-10-16）
    @EnvironmentObject private var pass: PassStore
    /// 開いている束。**出す口はここに置く**（札は `LazyVStack` の中なので）
    @State private var passDeck: PassDeck?
    @State private var showPassBook = false
    /// 行った県の地図（「新しくなったこと」の行き先・札 #519）
    @State private var showVisitedMap = false
    /// 「新しくなったこと」から頼まれた画面を、シートが閉じきるまで待って積む
    @State private var homeScreenWait: Task<Void, Never>?
    /// すれちがいの「いま」。**時計で待たない**（ロック中に 18 時を越えると古いまま残る）——前面に来た・
    /// 知らせが届いた／押された・画面に戻ったときに入れ直す（2026-10-16 の読み直し）
    @State private var passNow = Date()
    /// 「ホーム」をもう一度押した合図（一番上へ戻る）
    @ObservedObject private var tabRouter = TabRouter.shared
    /// ストーリーの輪を読み直す合図（引き下げ・前面に戻った）
    /// 引き下げ・「もう一度試す」の読み直しの最中（重ねて走らせない）
    @State private var isRefreshing = false
    @State private var storiesRefresh = 0
    @Environment(\.scenePhase) private var scenePhase
    /// 背面へ行ったか（戻るときは background → inactive → active と段を踏むので、
    /// 直前の値だけでは「背面から戻った」と分からない）
    @State private var wentToBackground = false
    /// 通報している写真。**シートはカードではなくここに付ける**
    /// （`HomeMosaic.onReport` の注記）
    @State private var reportTarget: Photo?
    /// いまこの画面が出ているか。**詳細を上に積んでいる間は読み直さない**
    @State private var isOnScreen = false
    /// 出ていない間にブロック／通報があった。戻ってきたときに読み直す
    @State private var needsReload = false
    /// 出ていない間に電波が戻った。戻ってきたときに読み直す（`HomeReconnect`・2026-11-12）
    @State private var reloadAfterReconnect = false
    /// 一度でもこの画面が出たか。**戻ってきた回だけ自分の写真を読み直す**ための印
    /// （初回は `.task(id:)` が読む・`MyPageView` と同じ形）
    @State private var didAppear = false
    /// 描くときに落とす「見せない」の写し。**前面が確定したときだけ取り直す**。
    /// 戻った瞬間、読み直しが終わるまでブロックした人のカードが見えないように
    @State private var dropped = ModerationSnapshot()
    /// 戻るスワイプ途中の `onAppear` で絞り／読み直ししないための印
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?
    /// いま一覧を読んでいる人。**外側の nil は「まだ一度も決まっていない」**
    /// （内側の nil は未ログイン）。人が替わったのを見分けるのに使う
    @State private var shownViewer: String??
    /// 「いまの季節のスポット」の段の中身（決めるのは上の札 `HomeTopCardView`・#417 ④）
    @State private var seasonShelf: HomeSeasonShelfSlot?
    /// 上の札（`HomeTopCardView`）が見えている上端より上へ流れ切っているか
    @State private var topCardsAway = false
    /// 1本の並び（混ぜる・ブロックを落とす・投稿で束ねる・季節の段の前後に割る）の控え。
    /// 描き直しのたびに計算し直さない——材料か「見せない」が変わったときだけ（`HomeFeedPageMemo`）
    @State private var pageMemo = HomeFeedPageMemo()
    /// フォロー中の人の新しい写真を、どこまで上に出したか（`FollowingSeenStore`・札 #595）。
    /// **並べる基準は、人が決まったときと引き下げたときにだけ読み直す**（`FollowingBaseline`）——上に出した端から
    /// 覚えた値で並べ直すと、見ている間に上の段が消えて下の写真がずれる
    @State private var followingBaseline = FollowingBaseline()
    private let followingSeenStore = FollowingSeenStore()
    /// 「おすすめの人」でフォローしたあと、並びの頭へ送る合図（上にその人の写真が出る）
    @State private var scrollToTopRequests = 0
    /// ヘッダーのベル用（タブから外したので、ここから開く）
    var unread: Int = 0
    var onOpenNotifications: () -> Void = {}
    /// 見出しの吹き出しの点（受信箱に未読の会話がある・2026-11-10 札 #505）
    var messagesUnread = false

    var body: some View {
        // UI テストのときだけ: body の評価を数える（`PerfRecorder`・札 #435 / #429。無効なら何もしない）
        let _ = PerfRecorder.shared.bodyHit(.home)
        VStack(spacing: 0) {
            // **切り替えは置かない。** 範囲の切り替え（自分／フォロー中／すべて）は整理案 01c（2026-09-26）で、
            // フィードの切り替え（おすすめ／フォロー中／新着）は札 #595（2026-11-13）で外し、1本の並びにした。
            // 自分の写真はマイページが持ち場
            switch model.state {
            case .loading:
                // v2（Components 06）: 中身と同じ形の灰の骨格（0.3 秒より早ければ出さない）
                ScrollView { JPLoadingState(kind: .grid) }
            case .failed(let message):
                if connectivity.isOffline {
                    // 2026-11-12 判断（第2章「画面の状態とそろえ」）: **控えが1枚も無いときだけ**中央の状態。
                    // 電波が無いことを先に言う（「読み込めませんでした」だと何が起きたか分からない）
                    ScrollView { HomeOfflineState(isBusy: isRefreshing) { retryHome() } }
                } else {
                    ErrorBanner(message: message, isBusy: isRefreshing) {
                        retryHome()
                    }
                }
            case .loaded(let photos):
                let _ = PerfRecorder.shared.mark("home.loaded.body")
                // 2026-11-12 判断（第2章・板 v2 Main の「電波なし」）: **電波が無くても一覧は消さない。**
                // 前に見た写真（端末の控え）をそのまま出し、上に帯で知らせる。写真を見るまで 0 回、読み直しは 1 回
                if connectivity.isOffline {
                    HomeOfflineBand(isBusy: isRefreshing) { retryHome() }
                }
                // 🔴 **0枚でも並びごと描く**（ストーリー・上の札・空の知らせの一手を残す）
                feed(photos)
                    .onAppear { PerfRecorder.shared.mark("home.feed.appear") }   // 起動直後の停止の切り分け（UI テストのときだけ・2026-11-07）
            }
        }
        .webScreen()
        // **Web のヘッダーと同じ名前を出す。** あちらは全ページ共通で
        // 「Journey Photo」を左上に出している（`app/layout.tsx` の
        // `<header>`・高さ64・`bg-black/60`・下辺 `border-white/10`）。
        // 大見出しで「ギャラリー」と出していたので、開いた瞬間に
        // 別のサイトに見えていた
        .navigationTitle("Journey Photo")
        .navigationBarTitleDisplayMode(.inline)
        // 見出しはどの画面も同じ（ロゴ・探す・お知らせ・メニュー・`AppHeaderItems`）。
        // **地図のアイコンは外した**——下の札に「マップ」があり、
        // 同じ場所への入口が2つあった
        .toolbar { AppHeaderItems(unread: unread, onOpenNotifications: onOpenNotifications, messagesUnread: messagesUnread) }
        // 上の札の「⋯」で旅行プランを消した・ホームに出さないにした知らせと「元に戻す」（2026-11-12・`TripPlanRemovalQueue`）
        .overlay(alignment: .bottom) { TripRemovalBar(queue: TripPlanRemovalQueue.shared) }
        .task {
            // **環境の1つに繋ぎ直してから読む。** 自前のを持ったままだと
            // `setHidden` が届かず、ブロックが一生効かない
            // 「新着」はページで読む（`GET /feed`・2026-10-03）。同じ理由で環境の1つを渡す
            model.use(gallery: environment.gallery, feed: environment.publicFeed)
            PerfRecorder.shared.event("home.load>")   // 起動直後の停止の切り分け（UI テストのときだけ・2026-11-07 札 #435 / #429）
            await model.load()
            PerfRecorder.shared.event("home.load<")
        }
        // **ログイン状態が決まってから範囲を決める**（範囲は選んでいるフィードが決める）。
        // フォロー中の一覧は、その範囲を選ぶ人にだけ要る
        .task(id: auth.userId) {
            // **取りに行った人で反映する。** 待っている間に人が替わっても、
            // 再開した時点の `auth.userId` で前の人の集合を記録しない
            let userId = auth.userId
            model.expect(viewerId: userId)
            // 人が決まった・替わった → フォロー中の人の写真を上に出した所の基準を読み直す（札 #595）
            followingBaseline.capture(viewer: userId, store: followingSeenStore)
            // **人が替わったら一覧を読み直す**（前の人の限定公開を捨てる）。
            // 初回（`shownViewer` がまだ無い）は上の `.task` が読むので何もしない
            if let previous = shownViewer, previous != userId {
                shownViewer = .some(userId)
                await model.switchViewer(from: previous, to: userId)
            } else {
                shownViewer = .some(userId)
            }
            guard userId != nil else {
                model.use(viewerId: nil, following: [])
                await model.loadMyPhotos(environment.photos, viewerId: nil)
                return
            }
            // **取れなかった回を空の集合にしない**（`followingFailed`）。
            let ticket = model.beginFollowingFetch()
            let following = await fetchFollowing()
            // **待っている間に人が替わったら何も書かない。** 古い回の答えを次の人の
            // `auth.userId` で書くと、後から来る正しい答えを上書きしうる。
            guard auth.userId == userId else { return }
            // 画面を離れて取り消され、**取れなかった**回は何もしない（取り消しは
            // 「取れなかった」ではない——失敗の印を立てない）。取れていれば入れる
            // （取り消しで一律に飛ばすと、`.task` が走り直さなければ人が入らないまま残る）
            if following == nil && Task.isCancelled { return }
            model.use(viewerId: userId, following: following, ticket: ticket)
            // 今日のテーマに参加したかの判定に要る（API から読む）
            await model.loadMyPhotos(environment.photos, viewerId: userId)
        }
        .refreshable { await refreshAll() }
        // 電波が戻ったら、押さなくても読み直す（帯の「もう一度」を待たない・2026-11-12 第2章）。
        // 上に詳細を積んでいる・別のタブにいる間は読み直さず**印だけ立て**、戻ってきたとき
        // （`landOnScreen`）に読み直す（`HomeReconnect`）
        .onChange(of: connectivity.isOffline) { _, offline in
            switch HomeReconnect.onConnectivityChange(offline: offline, isOnScreen: isOnScreen) {
            case .reloadNow: reloadAfterReconnect = false; retryHome()
            case .reloadWhenBack: reloadAfterReconnect = true
            case .nothing: break
            }
        }
        // **下の「投稿」を閉じたら自分の写真を読み直す。** 今日のテーマの札から投稿しても、
        // シートは `RootView` にあるので `.task(id:)` は走らず、札が「参加する」のまま残った
        //
        // 🔴 **画面に出ている間だけ**（`MyPageView` と同じ）。旅の一冊などを上に積んだまま
        // 読み直すと、札が差し替わって開いている画面ごと閉じる。出ていない回は
        // 戻ってきたとき（`onAppear`）の読み直しが拾う
        .onChange(of: tabRouter.postSheetsClosed) { _, _ in
            guard auth.userId != nil, isOnScreen else { return }
            // 上げた写真は読み直しを待たずに先に足す（索引が遅れて返らないことがある・`PostedPhotos`）
            model.showPosted(tabRouter.lastPosted, viewerId: auth.userId)
            reloadMyPhotos()
        }
        // **前面に戻ったら輪を読み直す。** 日をまたいで戻っても昨日の輪のまま、
        // フォローしている人の新しいストーリーも出なかった
        // **背面から戻ったときだけ。** コントロールセンター・Face ID・許可の確認から
        // 戻るたび（inactive → active）に読み直すと、読み込み中の輪を取り消して取り直していた
        // 背面で起動された回（通知・位置など）は、最初の値に `onChange` が来ないので
        // ここで印を立てる（前面に来たとき輪を読み直す）
        .onAppear { if scenePhase == .background { wentToBackground = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { wentToBackground = true }
            if phase == .active { passNow = Date() }
            if phase == .active, wentToBackground {
                wentToBackground = false
                storiesRefresh &+= 1
            }
        }
        // **限定公開の取り口が入れ替わった後にも読み直す。** `auth.userId` の変化と
        // 取り口の入れ替え（`JourneyPhotoApp.applyRestrictedFeed`）の順は決まっておらず、
        // 先に読むと前の人の口の控えを拾いうる。最初の1回（今の回数）は読まない
        .task {
            var isFirst = true
            for await _ in await environment.gallery.restrictedChanges() {
                if isFirst { isFirst = false; continue }
                await model.load()
            }
        }
        // **限定公開の写真の画像が期限切れで割れたら、限定公開だけ取り直して新しい URL をもらう**
        // （2026-10-18・札 #294。`SignedImageExpiry`）。**この画面の写真のときだけ**・15秒に1回まで。
        // `force` なしで読む＝ページ・位置・全件の控えはそのまま（「新着」を1ページ目へ戻さない）
        .task {
            var gate = SignedImageRefetchGate()
            for await url in SignedImageExpiry.signals() {
                guard model.showsImage(url), gate.shouldRefetch(after: url, now: Date()) else { continue }
                await environment.gallery.expireRestricted(containing: url)
                await model.load()
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(photoId: target.id, ownerId: target.userId ?? target.uploadedBy)
        }
        // すれちがいの束（札を押した・夕方の知らせを押した）。「帳に入れる」は閉じてから帳を積む
        .fullScreenCover(item: $passDeck) { deck in
            PassViewerView(cards: deck.cards, mode: .bundle) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showPassBook = true }
            }
        }
        .navigationDestination(isPresented: $showPassBook) { PassBookView() }
        .navigationDestination(isPresented: $showVisitedMap) { VisitedMapScreen() }
        // 「新しくなったこと」の項目 → ホームに積む（札 #519）。ホームがまだ出ていなかった回は出たときに受け取る
        .onChange(of: tabRouter.homeScreenRequests) { _, _ in openRequestedScreen() }
        .onAppear { openRequestedScreen() }
        .onChange(of: pass.openRequests) { _, _ in
            passNow = Date()
            openPendingPass()
        }
        .onChange(of: pass.arrivals) { _, _ in passNow = Date() }
        // 冷えた起動で知らせを押した回は、写真を引き終えてから開く
        .onChange(of: pass.photos.count) { _, _ in openPendingPass() }
        // 届いた束の写真を引く（届いた数・ブロック／通報が変わったら引き直す）。**引くのは「いま」で**
        .task(id: PassResolveKey(due: pass.encounters.filter { $0.deliverAt <= passNow }.count,
                                 hidden: hidden.revision)) {
            let now = Date()
            guard pass.hasDelivered(now: now) else { return }
            await pass.resolve(gallery: environment.gallery, profiles: environment.profiles, now: now)
        }
        // **ブロック／通報の直後に消す。** 手元に読み終えた配列が残るので、
        // 読み直さないと画面は変わらない。
        //
        // **集合を自分で渡してから読む。** 呼んだ側（`ReportSheet`）は
        // 通報とブロックを挟んでから `setHidden` を呼ぶので、その中断中に
        // 走るとこちらは**古い集合のまま**取ってしまう。
        // 1本にまとめてあるのは、2本だと全件取得が同時に2回走るため
        //
        // 🔴 **詳細を開いている間は読み直さない。** 読み直すと押した元のカードが
        // 一覧から消え、開いている詳細がその場で閉じる（「ブロックしました」も、
        // 通報シートのブロック失敗の文言も見えない）。戻ってきたとき（`onAppear`）に
        // 読み直す。カードの「…」や一覧に付けた通報シートからの回は画面に出ている
        .onChange(of: hidden.revision) { _, _ in
            if isOnScreen {
                dropped = hidden.snapshot
                reloadHidden()
            } else {
                needsReload = true
            }
        }
        .onAppear {
            switch front.appear() {
            case .first:
                landOnScreen(reloadMy: false)
                didAppear = true
            case .returning:
                // スワイプ途中で dropped／読み直しすると押した元が消えて詳細が閉じる
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    landOnScreen(reloadMy: true)
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
            isOnScreen = false
            model.leaveScreen()
        }
    }

    /// 頼まれた画面を積む。**シート（新しくなったこと・メニュー）が閉じきってから**——閉じる動きの最中に積むと
    /// 黙って無視されることがある（最長 3 秒待つ。過ぎたら積む）
    private func openRequestedScreen() {
        guard tabRouter.pendingHomeScreen != nil else { return }
        homeScreenWait?.cancel()
        homeScreenWait = Task { @MainActor in
            let started = Date()
            repeat {
                try? await Task.sleep(nanoseconds: 300_000_000)
            } while !Task.isCancelled && (ModalProbe.isPresenting() || ModalProbe.isTransitioning())
                && Date().timeIntervalSince(started) < 3
            guard !Task.isCancelled, let screen = tabRouter.takePendingHomeScreen() else { return }
            switch screen {
            case .passBook: showPassBook = true
            case .visitedMap: showVisitedMap = true
            }
        }
    }

    /// 夕方の知らせを押した分の束を開く。**写真を引けるまで待つ**（引けた束が空なら諦める）
    private func openPendingPass() {
        guard pass.hasPendingOpen, passDeck == nil else { return }
        let cards = passCards(now: Date())
        guard !cards.isEmpty else {
            if !pass.photos.isEmpty { _ = pass.takePendingOpen() }
            return
        }
        _ = pass.takePendingOpen()
        passDeck = PassDeck(cards: cards)
    }

    /// 届いた束のうち、まだ開いていない分（ブロック・通報を落とす）
    private func passCards(now: Date) -> [PassCardContent] {
        pass.contents(pass.unopened(hiding: hidden.snapshot, now: now), book: pass.book(hiding: hidden.snapshot, now: now))
    }

    /// 前面確定後: 写し・印・必要なら読み直し
    private func landOnScreen(reloadMy: Bool) {
        isOnScreen = true
        passNow = Date()
        openPendingPass()
        // 印は同期で立て（`markOnScreen`）、詳細を開いていた間に届いた「新着」の続きだけ
        // 後から足す（`GalleryViewModel.pageWrite`）
        model.markOnScreen()
        Task { await model.applyPendingPages() }
        dropped = hidden.snapshot
        // **戻ってきたら毎回自分の写真を読み直す**（`MyPageView` と同じ形）。
        // 合図が来ない変わり方がある——すでに「消した」印の付いた写真を消した・
        // 下書きを公開にした（`hidden.revision` が進まない）。
        // `reloadHidden` は自分の写真も読むので、その回は二重に取りに行かない
        if needsReload {
            reloadHidden()
        } else if reloadMy {
            reloadMyPhotos()
        }
        // 出ていない間に電波が戻った（2026-11-12 第2章・`HomeReconnect`）。前に見た写真の帯を残さない
        if HomeReconnect.reloadOnLanding(pending: reloadAfterReconnect, offline: connectivity.isOffline) {
            reloadAfterReconnect = false
            retryHome()
        }
    }

    private func reloadMyPhotos() {
        guard let userId = auth.userId else { return }
        Task { await model.loadMyPhotos(environment.photos, viewerId: userId) }
    }

    private func reloadHidden() {
        needsReload = false
        Task {
            await environment.gallery.setHidden(hidden.snapshot)
            await model.load()
        }
        // 自分の写真も読み直す。消した・非公開にした写真の札（1年前・旅の一冊・今日のテーマ）が
        // 残り、押すと 404 だった（写真を消す・非公開にすると `revision` が進む）。
        // 書いた直後はサーバーの索引が古い答えを返しうるので、その回は次に読み直すまで
        // 札に残りうる（印で絞る形は回帰が出たのでやめた。2026-09-30 判断）
        reloadMyPhotos()
    }

    /// 選ばれた写真の横並び（カテゴリごと・Web の `FeaturedSections`）。1本の並びの 2. の頭に置く。
    /// 1.（フォロー中の人の新しい写真）に出した写真は落とす（同じ写真を2回出さない）
    private func featuredGroups(excluding shown: Set<String>) -> [FeaturedGroups.Group] {
        model.featured.compactMap { group in
            let photos = dropped.visible(group.photos).filter { !shown.contains($0.id) }
            return photos.isEmpty ? nil : FeaturedGroups.Group(id: group.id, label: group.label, photos: photos)
        }
    }

    @ViewBuilder
    private func featuredSections(_ groups: [FeaturedGroups.Group]) -> some View {
        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: JPSpace.s) {
                // v2（Search の板の節の見出しと同じ型）: 眉（真鍮＋消える線）→ 明朝 22 → 右に「すべて ›」
                JPSectionHeading(eyebrow: "PICKS", spoken: L("選ばれた写真", "Picks"), title: group.label) {
                    NavigationLink {
                        TagPhotosView(kind: .category(group.id))
                    } label: {
                        MoreLink(text: L("すべて見る", "See all"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, JPSpace.gutter)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WebTheme.gridSpacing) {
                        ForEach(group.photos) { photo in
                            NavigationLink {
                                PhotoDetailView(photo: photo, context: group.photos)
                            } label: {
                                PhotoTile(photo: photo, aspect: 3.0 / 4.0)
                                    .frame(width: 240)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, JPSpace.gutter)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.featured")
        }
    }

    /// UI テストのときだけ、1本の並びの数を見えない要素（`home.feed.probe`）に出す（`PreviewSession.feedProbe`）。
    /// 読んだページの数・上の段の数・並びの数・続きの目印があるか・新着の最初の札が上から何枚目か（無ければ -1）
    private func feedProbeText(_ rows: HomeFeedPageMemo.Rows) -> String {
        "pages=\(model.loadedPageCount) following=\(rows.following.count) main=\(rows.lead.count + rows.rest.count)"
            + " more=\(rows.truncated || model.hasMorePages) firstLatest=\(rows.firstLatestTile ?? -1)"
            + " topCardsAway=\(topCardsAway)"
    }

    /// ホームは**板 01c の写真の並び**（`HomeMosaic`・2026-09-26）。
    /// 集約ページ（タグ・撮影地・機材）は角丸の `PhotoGrid` のまま。
    ///
    /// **2026-11-13（札 #595・owner 決定）: 「おすすめ・フォロー中・新着」の切り替えをやめ、タブの無い1本の並びにした。**
    /// 上から、フォロー中の人の新しい写真 → 選ばれた写真の横並び → 選ばれた写真・いいね順に新着を混ぜた並び
    /// （ひと回りの後ろに季節の撮影スポットの段）。並べ方は `HomeFeed.arrange`（純粋な関数）。
    /// 切り替えの札・留まる札の行・横に払う入れ物（`ProfileTabBar`・`ProfileTabPager`）はホームから外した
    /// （マイページ・人のページは今までどおり）
    private func feed(_ photos: [Photo]) -> some View {
        let fresh = followingFresh
        let featured = featuredGroups(excluding: Set(fresh.map(\.id)))
        let rows = pageMemo.rows(HomeFeedPageMemo.Input(
            following: fresh, recommended: model.recommendedPhotos, latest: photos,
            latestHasMore: model.hasMorePages, excluding: Set(featured.flatMap { $0.photos.map(\.id) })),
            hidden: dropped)
        return ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: Self.feedSpacing) {
                // 「ホーム」をもう一度押したときに戻る先（高さ0の目印）
                Color.clear.frame(height: 0).id(Self.feedTopID)
                // **ストーリーはホームの一番上**（モック1）。
                // 2026-09-20 に Web がトップから外してマイページへ移したが、
                // アプリの提案図では**ホームに戻っている**ので合わせる
                // ——「いま誰が旅に出ているか」は開いた瞬間に見たいもの
                // 投稿シートを閉じたとき・引き下げ更新・前面に戻ったときに読み直す
                // （どちらの数も増える一方なので、和は必ず変わる）
                // **すれちがいの届いた束**（板 PassHome: 見出しのすぐ下・「ここから下はいつものホーム」）。
                // 届いた束をまだ開いていないときだけ出る（`PassHomeSlot`）
                let passBundle = passCards(now: passNow)
                PassHomeSlot(cards: passBundle, now: passNow) { passDeck = PassDeck(cards: passBundle) }
                StoriesRow(reloadToken: tabRouter.postSheetsClosed &+ storiesRefresh,
                           myPhotos: model.myPhotos.filter { !dropped.deleted.contains($0.id) })
                // **今日のテーマ**（モック1）。通信はしない——日付から決まる。
                // 整理案 01c で1枚目の写真の後ろの細い帯にしたが、owner の
                // 「前の方が好きだった」で先頭の大きな札に戻した（2026-09-26）
                // 背景の写真もブロック／通報を落とした並びから（読み直しが終わるまで
                // ブロックした人の写真が札の背景に出ていた）
                // 2026-09-27: 上段は「開く場面ごとに1枚」（出発・旅の最中・一冊・1年前）
                // 2026-09-28: 当たる札と今日のテーマを**横にめくる並び**に（owner「両方欲しい」）
                // 自分の写真は**消した印だけ**落とす（`dropped.deleted`・2026-10-12 判断）。
                // 全部の `gone`（非公開含む）で絞ると、Web で公開に戻した写真がこの端末でだけ
                // 最大7日 札から消える（2026-09-30 の回帰）。消した id は使い回されないので安全。
                // 非公開にしただけ・サーバー索引が古い回は、読み直しが返るまで札に残りうる（従来どおり）
                HomeTopCardView(themePhotos: dropped.visible(model.allPhotosForTheme),
                                myPhotos: model.myPhotos.filter { !dropped.deleted.contains($0.id) },
                                // 札の1枚目を人で替える（2026-11-12・`HomeTopCard.Audience`）。読めるまでは常連の並び
                                myPhotosKnown: auth.userId != nil && model.myPhotosOwner == auth.userId,
                                reloadToken: storiesRefresh &+ tabRouter.menuSheetsClosed,
                                seasonShelf: $seasonShelf,
                                scrolledAway: topCardsAway)
                    // 上の札が見えている上端より上へ流れ切ったか（`HomeTopCardView.scrolledAway`・#426）。
                    // 札の差し替え（今日の一問・旅行プラン・日替わり）を戻るまで後回しにし、深く送っている間に
                    // 札の高さが変わって下の写真がずれないようにする
                    .onGeometryChange(for: Bool.self) { proxy in
                        proxy.frame(in: .scrollView).maxY < 0
                    } action: { away in
                        topCardsAway = away
                    }
                feedSection(rows, featured: featured)
            }
            .padding(.top, 8)
            // 最後のカードがタブバーに掛からないようにする
            .padding(.bottom, 24)
        }
        // 写真を手に取っている間は縦の送りを止める（2026-11-12 札 #543・`PhotoLift`）
        .modifier(PhotoLiftScrollLock(center: PhotoLiftCenter.shared))
        // UI テストのときだけ: 1本の並びの数を見えない要素に出す（`PreviewSession.feedProbe`）
        .overlay(alignment: .bottomTrailing) {
            if PreviewSession.feedProbe {
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("home.feed.probe")
                    .accessibilityValue(feedProbeText(rows))
            }
        }
        // **ホームを開いたまま「ホーム」をもう一度押したら一番上へ**
        // （`TabRouter.homeTopRequests`）。「おすすめの人」でフォローした後も頭へ（上にその人の写真が出る）
        .onChange(of: tabRouter.homeTopRequests &+ scrollToTopRequests) { _, _ in
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(Self.feedTopID, anchor: .top)
            }
        }
        // 1. を出した（新しく届いた分も）→ 上に出した所を覚える（次に並べ直すときは、それより新しい分だけを上に出す）
        .onChange(of: rows.following.map(\.id), initial: true) { _, shown in
            guard !shown.isEmpty else { return }
            markFollowingShown()
        }
        }
    }

    private static let feedTopID = "home-feed-top"

    /// 1. フォロー中の人の新しい写真（`HomeFeed.followingFresh`）。基準は画面が持つ（`followingBaseline`）
    private var followingFresh: [Photo] {
        guard let userId = auth.userId, followingBaseline.viewer == userId else { return [] }
        return model.followingFresh(viewerId: userId, seen: followingBaseline.seen, hiding: dropped)
    }

    /// 上に出したフォロー中の人の写真の、いちばん新しい投稿日を覚える（並べる基準 `followingBaseline` は替えない）
    private func markFollowingShown() {
        guard let userId = auth.userId,
              let newest = model.followingNewest(viewerId: userId, hiding: dropped) else { return }
        followingSeenStore.mark(newest, for: userId)
    }

    /// 並びの段の間（以前の一覧の `LazyVStack` の間と同じ 24）
    nonisolated static let feedSpacing: CGFloat = 24

    /// 1本の並びの中身。
    ///
    /// - 1. フォロー中の人の新しい写真: 眉「FOLLOWING」（真鍮・黒地）＋明朝の題の節。無い日は節ごと出さない
    /// - 2. の頭に選ばれた写真の横並び（PICKS）
    /// - 2.・3. を混ぜた写真の並び（`HomeMosaic`）。**ひと回り（大1→2→2）の後ろに季節の撮影スポットの段**
    ///   （#417 ④・`HomeFeed.splitForSeasonShelf`）。段の有無で枝を替えない（段の中身は後から届くので、
    ///   替えると一覧が作り直され、ちらつき・開いた詳細の元の札が作り直される）
    /// - フォローが0人のログイン中の人には、ひと回りと季節の段の後ろに「おすすめの人」（1.1.83・資料④）
    /// - 読めた新着を使い切ったら並びを切り、最後の段に続きを読む目印（`pageFooter`）
    ///
    /// 2026-11-13 判断（#595）: フォロー一覧を読めなかった回（`followingFailed`）は、1. の段を出さないだけにする。
    /// 前は「フォロー中」の札の中で「フォロー中の人を読み込めませんでした」を出していたが、1本の並びでは 2.・3. は
    /// 読めているので、ホームの上に失敗の帯を出すと写真より先に読むものが増える。引き下げで読み直す。
    /// 「おすすめの人」も、読めなかった回には出さない（フォローしている人に「まず、写真の好きな人を」と言わない）
    @ViewBuilder
    private func feedSection(_ rows: HomeFeedPageMemo.Rows, featured: [FeaturedGroups.Group]) -> some View {
        if !rows.following.isEmpty {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                // 眉は真鍮（黒地の上の合図）・題は明朝（板の節の見出し・PICKS と同じ型）
                JPSectionHeading(eyebrow: "FOLLOWING", spoken: L("フォロー中", "Following"),
                                 title: L("フォロー中の人の新しい写真", "New from people you follow"))
                    .padding(.horizontal, JPSpace.gutter)
                HomeMosaic(groups: rows.following, onReport: { reportTarget = $0 })
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.following")
        }
        featuredSections(featured)
        let isEmpty = rows.lead.isEmpty && rows.rest.isEmpty
        // **続きがある間は「まだありません」と言わない**（読んだ範囲がブロックで全部落ちた・
        // 続きを読んでいる最中）。下の目印が次を読む
        if isEmpty && rows.following.isEmpty && featured.isEmpty && !model.hasMorePages {
            feedEmptyState
        }
        HomeMosaic(groups: rows.lead, onReport: { reportTarget = $0 },
                   footer: rows.rest.isEmpty ? footer(rows) : nil)
        // 写真が0枚の日は段を出さない——空の知らせのすぐ下に作例の段が並ぶと、空なのか分からなくなる
        if !isEmpty, let seasonShelf {
            HomeSpotShelfView(shelf: seasonShelf.shelf, spots: seasonShelf.spots,
                              photos: dropped.visible(model.allPhotosForTheme),
                              reloadToken: storiesRefresh &+ tabRouter.menuSheetsClosed)
                // 板: 段の上 12＋写真の隙間 4・下 8＋4（一覧の段の間 24 から詰める）
                .padding(.top, Self.seasonShelfTopTrim)
                .padding(.bottom, Self.seasonShelfBottomTrim)
        }
        if !isEmpty, let userId = auth.userId, model.following(for: userId).isEmpty,
           !model.followingFailed, !suggestedPeople(userId).isEmpty {
            // 資料「SNS をもっと SNS に」④（1.1.83）: 写真のある人をその場に並べる（フォローまで 1回）。
            // 2026-11-13（#595）: 「フォロー中」の札が無くなったので、誰もフォローしていない人の並びの中に置く。
            // 写真が主役なので、ひと回り（1画面目）と季節の段の後ろ
            HomeSuggestedPeopleView(people: suggestedPeople(userId)) { followed in
                Task { await showFollowingAfterSuggested(followed, userId: userId) }
            }
        }
        if !rows.rest.isEmpty {
            HomeMosaic(groups: rows.rest, onReport: { reportTarget = $0 }, footer: footer(rows))
        }
    }

    /// 続きを読む目印。並びの遅れて作る段（`HomeMosaic` の `LazyVStack`）の最後に置く——普通の並びに置くと、
    /// 画面の外でも `onAppear` がすぐ走り、送らなくても全部のページを読んでいた（#426 確かめ役）
    private func footer(_ rows: HomeFeedPageMemo.Rows) -> AnyView? {
        rows.truncated || model.hasMorePages ? AnyView(pageFooter) : nil
    }

    /// 季節の段の上下を、一覧の段の間（24）から板の間（上 16・下 12）へ詰める量
    nonisolated static let seasonShelfTopTrim: CGFloat = -8
    nonisolated static let seasonShelfBottomTrim: CGFloat = -12

    /// 続き（`GET /feed`・2026-10-03）。**下まで送ったら次のページを読む**。
    ///
    /// `LazyVStack` の最後の子なので、ここが作られる＝下まで来た。読んだページの数で
    /// 作り直す（`id`）——短いページで目印が画面に残ったままでも次を頼むため。
    /// 重ねて頼まないのはモデル側（`isLoadingPage`）。読めなかったら「もう一度試す」
    @ViewBuilder
    private var pageFooter: some View {
        if model.hasMorePages {
            Group {
                if model.pageFailed {
                    RetryButton(isBusy: model.isLoadingPage) {
                        Task { await model.loadNextPage() }
                    }
                } else {
                    ProgressView()
                        .onAppear { Task { await model.loadNextPage() } }
                }
            }
            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
            .id(model.loadedPageCount)
        }
    }

    /// 0枚のとき。**v2（2026-10-14・Components 06）**: 共通の `EmptyState`（明朝 20 の見出し → 15 の text-2 → 一手）。
    /// 一手は `EmptyState` の主ボタン（写真の無い所＝真鍮の塗り＋墨・CLAUDE.md の owner の好み）
    private var feedEmptyState: some View {
        EmptyState(title: nil, message: Labels.Gallery.empty,
                   actionTitle: L("撮影地を地図で探す", "Explore shooting places"),
                   actionIdentifier: "home.emptyAction") {
            tabRouter.openMap()
        }
    }

    /// 「おすすめの人」に並べる人（`SuggestedPeople`）。ブロック・通報は画面の写し（`dropped`）で落とし、
    /// 描くたびに全件をなめない（`GalleryViewModel.suggestedPeople` が控える）
    private func suggestedPeople(_ userId: String) -> [SuggestedPeople.Person] {
        model.suggestedPeople(viewerId: userId, hiding: dropped)
    }

    /// 「おすすめの人」でフォローしたあとの「フォロー中の写真を見る」。フォロー一覧を引き直し、並びの頭へ送る
    /// （上の段にその人の新しい写真が出る）。引けなかったら、この場でフォローした人を足した手元の一覧で並べる
    /// （押して何も起きない、を作らない）
    private func showFollowingAfterSuggested(_ followed: Set<String>, userId: String) async {
        let ticket = model.beginFollowingFetch()
        let fetched = await fetchFollowing()
        guard auth.userId == userId else { return }
        model.refreshFollowing(fetched ?? model.followingIds.union(followed), viewerId: userId, ticket: ticket)
        scrollToTopRequests &+= 1
    }

    /// 引き下げ・「もう一度試す」の読み直し。**重ねて走らせない**——続けて押すと、
    /// 遅れて返った古い回が新しい回の答えを上書きした（2026-10-02 のレビュー）
    /// 帯・中央の状態の「もう一度」（引き下げと同じ読み直し。重ねて走らせない）
    private func retryHome() {
        Task { await refreshAll() }
    }

    private func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // ストーリーの輪も読み直す（写真だけ読み直すと、輪は古いまま残った）
        storiesRefresh &+= 1
        // 上に出したフォロー中の人の写真は、引き下げたら上から外す（並べる基準を覚えた所まで進める）
        followingBaseline.capture(viewer: auth.userId, store: followingSeenStore)
        await model.load(force: true)
        // **フォロー一覧も取り直す**（取れなかった回の出口は引き下げ）
        if let userId = auth.userId {
            let ticket = model.beginFollowingFetch()
            let following = await fetchFollowing()
            // 待っている間に人が替わっていたら捨てる
            guard auth.userId == userId else { return }
            model.refreshFollowing(following, viewerId: userId, ticket: ticket)
            // 今日のテーマの「参加済み」も取り直す（`.task(id:)` は人が替わらないと走らない）
            await model.loadMyPhotos(environment.photos, viewerId: userId)
        }
    }

    /// フォロー一覧。**取れなかったら nil**（空の集合と分ける）
    private func fetchFollowing() async -> Set<String>? {
        let ids = try? await environment.social.myFollowingIds()
        return ids.map { Set($0) }
    }
}

/// ホームの1本の並びの控え（`GalleryView.feed`）。材料（同じ入れ物なら中身を見ずに一致）と
/// 「見せない」の写しが同じなら、前の答えを返す
final class HomeFeedPageMemo {

    /// 並べる材料（`HomeFeed.arrange` の入力）
    struct Input: Equatable {
        let following: [Photo]
        let recommended: [Photo]
        let latest: [Photo]
        let latestHasMore: Bool
        let excluding: Set<String>
    }

    struct Rows: Equatable {
        /// 1. フォロー中の人の新しい写真（投稿で束ねた後）
        let following: [PhotoGroups.Group]
        /// 2.・3. を混ぜた並びの、季節の段の前（大1→2→2）と後ろ
        let lead: [PhotoGroups.Group]
        let rest: [PhotoGroups.Group]
        /// 読めた新着を使い切ったので、ここで切った（`HomeFeed.Arranged.truncated`）
        let truncated: Bool
        /// 新着から入れた最初の束が、写真の札（`feed.photo`）の上から何枚目か（0 から・1. の札も数える）。
        /// UI テストが新着の1枚目を開くため（`home.feed.probe` の `firstLatest`）
        var firstLatestTile: Int? = nil
    }

    struct Key: Equatable {
        let input: Input
        let hidden: ModerationSnapshot
    }

    private let memo = DerivedMemo<Key, Rows>()

    init() {}

    func rows(_ input: Input, hidden: ModerationSnapshot) -> Rows {
        memo.value(for: Key(input: input, hidden: hidden)) { Self.make(input, hidden: hidden) }
    }

    /// 計算した回数（試験用）
    var computeCount: Int { memo.computeCount }

    static func make(_ input: Input, hidden: ModerationSnapshot) -> Rows {
        let arranged = HomeFeed.arrange(following: hidden.visible(input.following),
                                        recommended: hidden.visible(input.recommended),
                                        latest: hidden.visible(input.latest),
                                        latestHasMore: input.latestHasMore, excluding: input.excluding)
        let main = PhotoGroups.group(arranged.main)
        let split = HomeFeed.splitForSeasonShelf(main)
        let following = PhotoGroups.group(arranged.following)
        let firstLatest = main.firstIndex { arranged.fromLatest.contains($0.cover.id) }.map { following.count + $0 }
        return Rows(following: following, lead: split.lead, rest: split.rest,
                    truncated: arranged.truncated, firstLatestTile: firstLatest)
    }
}

/// 届いた束の写真を引き直す合図（`GalleryView`）
private struct PassResolveKey: Equatable {
    let due: Int
    let hidden: Int
}

/// フォロー中の人の新しい写真を並べる基準（`FollowingSeenStore` の値を、決まったときにだけ写す・札 #595）
struct FollowingBaseline: Equatable {
    /// 誰の基準か（nil なら未ログイン・まだ読んでいない）
    private(set) var viewer: String?
    /// 上に出した所（nil なら1度も出していない＝全部が新しい）
    private(set) var seen: String?

    mutating func capture(viewer: String?, store: FollowingSeenStore) {
        self.viewer = viewer
        seen = store.seen(for: viewer)
    }
}
