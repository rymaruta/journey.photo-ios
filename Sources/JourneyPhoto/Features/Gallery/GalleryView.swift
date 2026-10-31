import SwiftUI

struct GalleryView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// **「見せない」が変わったら読み直すため**に見ている。
    /// この画面はタブの根なので一度出たら生き続け、`.task` は二度と走らない
    /// ——ブロックしても、戻ってくるとその人の写真がまだ並んでいた
    @EnvironmentObject private var hidden: ModerationStore
    @StateObject private var model = GalleryViewModel()
    /// すれちがいの届いた束（板 PassHome・2026-10-16）
    @EnvironmentObject private var pass: PassStore
    /// 開いている束。**出す口はここに置く**（札は `LazyVStack` の中なので）
    @State private var passDeck: PassDeck?
    @State private var showPassBook = false
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
    /// 切り替えの札の行の位置の控え（マイページと同じ `ProfileTabRowSpot`）。送るたびに変わる値なので見張らない箱に置く
    @State private var feedRowSpot = ProfileTabRowSpot()
    /// 中身の横の量の箱を、縦の送りの外に重ねた札の行（留まった札）と分け合う（`ProfileTabPagerControl`）
    @State private var feedPager = ProfileTabPagerControl<HomeFeed>()
    /// 上の札（`HomeTopCardView`）が見えている上端より上へ流れ切っているか
    @State private var topCardsAway = false
    /// 札ごとの写真の束ね（ブロックを落とす・投稿で束ねる・季節の段の前後に割る）の控え（#426 確かめ役の見直し）。
    /// 描き直しのたびに全部の札で計算し直さない——元の写真か「見せない」が変わったときだけ
    @State private var pageMemo = HomeFeedPageMemo()
    /// 札の行が上に留まっているか（重ねて描く札 `pinnedFeedRow` を出す。変わったときだけ書く）
    @State private var feedRowPinned = false
    /// 札の行の高さ・見えている高さ（札の中身の最低の高さ `ProfileTabScroll.minPageHeight`）
    @State private var feedRowHeight: CGFloat = ProfileTabStyle.height
    @State private var feedViewport: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「フォロー中」をどこまで見たか（#417 ⑨・`FollowingSeenStore`）。人が替わったとき・覚え直したときに読み直す
    @State private var followingSeen: String?
    private let followingSeenStore = FollowingSeenStore()
    /// ヘッダーのベル用（タブから外したので、ここから開く）
    var unread: Int = 0
    var onOpenNotifications: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // **範囲の切り替え（自分／フォロー中／すべて）は置かない。**
            // 下のフィード（おすすめ／フォロー中／新着）が範囲も決めるので、
            // 「フォロー中」が2段に並んでいた（整理案 01c・2026-09-26）。
            // 自分の写真はマイページが持ち場
            switch model.state {
            case .loading:
                // v2（Components 06）: 中身と同じ形の灰の骨格（0.3 秒より早ければ出さない）
                ScrollView { JPLoadingState(kind: .grid) }
            case .failed(let message):
                ErrorBanner(message: message) {
                    Task { await model.load() }
                }
            case .loaded(let photos):
                // 🔴 **0枚でもフィードごと描く**（切り替えのタブを残す）。
                // 空の知らせで画面ごと置き換えると、「フォロー中」を押して
                // 0枚だった人が「おすすめ」へ戻れなかった——以前は上の段の
                // 切り替えが逃げ道だったが、整理案 01c で外した
                feed(photos)
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
        .toolbar { AppHeaderItems(unread: unread, onOpenNotifications: onOpenNotifications) }
        .task {
            // **環境の1つに繋ぎ直してから読む。** 自前のを持ったままだと
            // `setHidden` が届かず、ブロックが一生効かない
            // 「新着」はページで読む（`GET /feed`・2026-10-03）。同じ理由で環境の1つを渡す
            model.use(gallery: environment.gallery, feed: environment.publicFeed)
            await model.load()
        }
        // **ログイン状態が決まってから範囲を決める**（範囲は選んでいるフィードが決める）。
        // フォロー中の一覧は、その範囲を選ぶ人にだけ要る
        .task(id: auth.userId) {
            // **取りに行った人で反映する。** 待っている間に人が替わっても、
            // 再開した時点の `auth.userId` で前の人の集合を記録しない
            let userId = auth.userId
            model.expect(viewerId: userId)
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

    /// owner が選んだ「おすすめ」。Web はトップの一覧の上に、
    /// カテゴリごとの横並びで出している（`FeaturedSections`）。
    @ViewBuilder
    private func featuredSections(_ page: HomeFeed) -> some View {
        // おすすめの横並びも、モザイクと同じ写しで落とす（戻った直後に見えない）
        ForEach(model.featured(for: page).filter { !dropped.visible($0.photos).isEmpty }) { group in
            VStack(alignment: .leading, spacing: JPSpace.s) {
                // v2（Search の板の節の見出しと同じ型）: 眉（真鍮＋消える線）→ 明朝 22 → 右に「すべて ›」
                JPSectionHeading(eyebrow: "PICKS", spoken: L("おすすめ", "Picks"), title: group.label) {
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
                        ForEach(dropped.visible(group.photos)) { photo in
                            NavigationLink {
                                PhotoDetailView(photo: photo, context: dropped.visible(group.photos))
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
            // 画面写真の試験が「新着」で出ていないことを確かめる目印（`ScreenshotTests`）
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.featured")
        }
    }

    /// フィードの切り替え（おすすめ / フォロー中 / 新着）。
    ///
    /// **推薦の口は無い**ので、おすすめの規則を下に1行で出す
    /// （指示書 5-2——実装済みであるかのように見せない）。**その一文は
    /// 整理案 01c で画面から外した**（owner の承認・2026-09-26）。文言は `HomeFeed.note`
    ///
    /// **v2（2026-10-14・Main の板）: 字のタブにした。** 選んだタブは真鍮の字（600）と 2 の真鍮の下線、
    /// ほかは text-3 の字。並びの下に白 8% の区切り線。黒地の上なので真鍮が読める。
    /// **選んだことは下線（形）と読み上げ（`.isSelected`）でも伝える**——色だけにしない
    ///
    /// **2026-10-31 判断（#426・owner「ホームのタブの切り替えもマイページと同じようにスムーズに」）:
    /// マイページと同じ札の部品（`ProfileTabBar`）にした。** 下線は次の札の幅に伸び縮みしながらばねで滑り
    /// （0.28 秒・減衰 0.85）、押せる範囲は札の間の半分（12）まで左右に広がり、高さ 48。札の行でも横に払える
    /// （`ProfileTabSwipe`）。以前はここだけ自前の札（下線は瞬時に入れ替わる・当たりは字の幅だけ・高さ 44）だった
    ///
    /// **#417 ⑧（2026-10-30 owner 採用）: 写真の一覧の頭で、下へ送っても見出しの下に留まる**
    /// （`feed` の `LazyVStack(pinnedViews: [.sectionHeaders])` の見出し）。留まっている間は札の部品の
    /// 「留まった姿」（地を黒 100%・下の線を白 12%・マイページと同じ）。外した NEW の段の「すべて見る」が無くても、
    /// 「新着」はいつも1回で押せる。
    ///
    /// **#417 ⑨: フォロー中に新しい写真がある日は「フォロー中」の右上に真鍮の点**（8・黒 2 の縁・字の右端から 11・上から 9。
    /// お知らせの未読の点と同じ形・`ProfileTabDot`）。読み上げは「フォロー中・新しい写真あり」（`HomeFollowingNews`）
    private func feedPicker(followingHasNew: Bool, stuck: Bool) -> some View {
        ProfileTabBar(tabs: HomeFeed.allCases, selection: feedSelection, stuck: stuck,
                      dot: { $0 == .following && followingHasNew },
                      spokenLabel: { HomeFollowingNews.spokenLabel($0.label, hasNew: $0 == .following && followingHasNew) })
            // **規則の一文は出さない**（整理案 01c）。写真より先に
            // 説明が並ぶと、開いた瞬間に読むものが増える。
            // 文言は `HomeFeed.note` に残してある
            // 地は画面の黒（流れている札の行も黒地の上・留まった札は部品が黒 100% で塗る）
            .background(WebTheme.background)
    }

    /// 上に留まった切り替え（流れている元の行が見えている上端を越えている間だけ、縦の送りの外に重ねる）。
    ///
    /// **2026-10-31 判断（#426 Mac の確かめ・run 41201788362 の数）: マイページと同じ「重ねて描く札」にした。**
    /// 以前は `LazyVStack(pinnedViews: [.sectionHeaders])` の節の見出しで留めていたが、遅れて作る並びは札の中身
    /// （横に並べた入れ物）の高さを**1つ前の選びの高さのまま**持ち続けた（新着 → フォロー中で中身の高さ 6320、
    /// フォロー中 → 新着で 1042）。短い高さが残った回に送りの位置が詰められ（offset 178.33 → 169.00）、札の行が
    /// 留まりから外れて下がった（y 116 → 121.33・前の回は 118.33・130.33）。並びを `VStack` にして高さが選びと
    /// 一緒に変わるようにし、留め方はマイページ（`pinnedTabRow`）と同じにした。
    /// 横の払い: 重ねた札は縦の送りの外なので、縦の送りに足すパンは届かない。札の行の上だけ SwiftUI の
    /// 指の操作（`ProfileTabOverlaySwipe`）で受け、中身と同じ箱（`feedPager`）を動かす——中身が指に付いてくる
    private func pinnedFeedRow(followingHasNew: Bool) -> some View {
        feedPicker(followingHasNew: followingHasNew, stuck: true)
            .modifier(ProfileTabOverlaySwipe(tabs: HomeFeed.allCases, selection: feedSelection, control: feedPager))
            // 札の目印（`home.feed.*`）は中に残す（入れ物の目印で上書きしない）
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.feed.pinned")
    }

    /// 札で選んでいるフィード。押した・払ったのどちらも `selectFeed` を通す
    private var feedSelection: Binding<HomeFeed> {
        Binding(get: { model.feed }, set: { selectFeed($0) })
    }

    /// フィードを選ぶ（札を押した・中身か札の行を横に払った）
    private func selectFeed(_ feed: HomeFeed) {
        model.select(feed: feed, viewerId: auth.userId)
        // ⑧ 留まった切り替えで別のフィードを選んだら、新しい一覧の**頭**へ送る（PR #422 の確かめ）——
        // `feed` の `.onChange(of: model.feed)`（マイページと同じ `ProfileTabScroll.scrollsToRow`）
        // **選んだときにフォロー一覧を引き直す。** 一覧は
        // `.task(id: auth.userId)` で一度しか引いていないので、
        // 誰かをフォローしても「フォロー中」に出てこない
        // （上の段にあった範囲の切り替えが持っていた処理を移した）
        guard feed == .following, let userId = auth.userId else { return }
        Task {
            // **取れなかった回に空で潰さない**（圏外で押しただけで
            // 「フォロー中」が知らせも無く空になる）——nil は `refreshFollowing` が捨てる
            let ticket = model.beginFollowingFetch()
            let following = await fetchFollowing()
            // 待っている間に人が替わっていたら捨てる（前の人の集合を今の人に入れない）
            guard auth.userId == userId else { return }
            model.refreshFollowing(following, viewerId: userId, ticket: ticket)
        }
    }


    /// UI テストのときだけ、札の行の位置の数を見えない要素（`home.feed.probe`）に出す（`PreviewSession.feedProbe`）
    @State private var feedProbeText = ""

    private func updateFeedProbe() {
        let n: (CGFloat) -> String = { String(format: "%.2f", Double($0)) }
        let text = "feed=\(model.feed.rawValue) rowMinY=\(n(feedRowSpot.minY))"
            + " overflow=\(n(ProfileTabScroll.rowOverflow(rowMinY: feedRowSpot.minY, visibleTop: 0)))"
            + " pinned=\(feedRowPinned) rowH=\(n(feedRowHeight)) viewport=\(n(feedViewport))"
            + " pages=\(model.loadedPageCount) topCardsAway=\(topCardsAway)"
        if text != feedProbeText { feedProbeText = text }
    }

    /// ホームは**板 01c の写真の並び**（`HomeMosaic`・2026-09-26）。
    /// 集約ページ（タグ・撮影地・機材）は角丸の `PhotoGrid` のまま。
    private func feed(_ photos: [Photo]) -> some View {
        ZStack(alignment: .top) {
        ScrollViewReader { proxy in
        ScrollView {
            // 2026-10-31（#426 Mac の確かめ）: `LazyVStack` の節の見出しで留めるのをやめ、マイページと同じ `VStack` と
            // 重ねて描く札（`pinnedFeedRow`）にした。遅れて作る並びが札の中身の高さを1つ前の選びのまま持ち、送りの位置を
            // 詰めて札の行を動かしていた。写真の一覧の遅れて作る並びは `HomeMosaic` の中にある（画面に入った段だけ作る）
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
                StoriesRow(reloadToken: tabRouter.postSheetsClosed &+ storiesRefresh)
                // **#417 ⑦（2026-10-30 owner 採用）: 「NEW（みんなの新しい写真）」の段（2026-10-21・`HomeFreshStrip`）は外した。**
                // 新着は切り替えの「新着」に一本化。最初の画面の人の写真は、写真の一覧の1段目が受け持つ
                // （④で季節の段を一覧の中へ移し、①③で上を詰めたので、写真の大きな1枚目が1画面目に入る・Compare の板）。
                // 「フォロー中の人の写真を先に」の役目は、切り替えの「フォロー中」の真鍮の点（⑨）が引き継ぐ
                //
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
                                reloadToken: storiesRefresh &+ tabRouter.menuSheetsClosed,
                                seasonShelf: $seasonShelf,
                                scrolledAway: topCardsAway)
                    // 上の札が見えている上端より上へ流れ切ったか（`HomeTopCardView.scrolledAway`・#426）。
                    // 外側を `VStack` にしたので、流れ出ても `onDisappear` が来ない。main（`LazyVStack`）では流れ出ると
                    // `onDisappear` が来て、札の差し替え（今日の一問・旅行プラン・日替わり）を戻るまで後回しにしていた。
                    // その扱いを位置で続ける——深く送っている間に札の高さが変わって、下の写真がずれないように
                    .onGeometryChange(for: Bool.self) { proxy in
                        proxy.frame(in: .scrollView).maxY < 0
                    } action: { away in
                        topCardsAway = away
                        if PreviewSession.feedProbe { updateFeedProbe() }
                    }
                // ⑧ 切り替えは写真の一覧の頭。下へ送ると、見えている上端に留まる（重ねて描く `pinnedFeedRow`）。
                // 留まっている間は元の行を見せず・押させず・読ませない（場所は取り続ける——位置の控えと「替えたら頭から」の目印）
                feedPicker(followingHasNew: followingHasNew, stuck: false)
                    .opacity(feedRowPinned ? 0 : 1)
                    .allowsHitTesting(!feedRowPinned)
                    .accessibilityHidden(feedRowPinned)
                    .id(Self.feedRowID)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .scrollView)
                    } action: { frame in
                        if let height = feedRowSpot.record(frame, height: feedRowHeight) { feedRowHeight = height }
                        if PreviewSession.feedProbe { updateFeedProbe() }
                    }
                    // 上端を越えたかは、越えた・戻ったときだけ値が変わる（送るたびに描き直さない）
                    .onGeometryChange(for: Bool.self) { proxy in
                        ProfileTabScroll.pinsRow(rowMinY: proxy.frame(in: .scrollView).minY, visibleTop: 0)
                    } action: { feedRowPinned = $0 }
                // #426: 中身はフィードごとの札を横に並べて持つ（`ProfileTabPager`・マイページと同じ入れ物）。
                // 最低の高さは「見えている高さ − 札の行と間」——短いフィードへ替えても送りの位置が詰められず、札の行が跳ばない
                ProfileTabPager(tabs: HomeFeed.allCases, selection: feedSelection,
                                minHeight: ProfileTabScroll.minPageHeight(viewport: feedViewport, visibleTop: 0,
                                                                          rowHeight: feedRowHeight, spacing: Self.feedSpacing),
                                rowOverflow: { ProfileTabScroll.rowOverflow(rowMinY: feedRowSpot.minY, visibleTop: 0) },
                                // 選んでいる札と左右の隣だけを持つ（写真の一覧が長いので、離れた札は捨てる）
                                keepsDistantPages: false,
                                // 流れている札の行の上の払いも、この1つの払いが受ける（中身が指に付いてくる・`swipeExtendsUp`）
                                swipeExtendsUp: feedRowHeight + Self.feedSpacing,
                                // 重ねた札の行の払いと、中身の横の量の箱を分け合う
                                control: feedPager) { page in
                    VStack(spacing: Self.feedSpacing) {
                        feedSection(page, rows: pageRows(page, selected: photos))
                    }
                }
            }
            .padding(.top, 8)
            // 最後のカードがタブバーに掛からないようにする
            .padding(.bottom, 24)
        }
        // UI テストのときだけ: 札の行の位置の数を見えない要素に出す（`PreviewSession.feedProbe`）
        .overlay(alignment: .bottomTrailing) {
            if PreviewSession.feedProbe {
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("home.feed.probe")
                    .accessibilityValue(feedProbeText)
            }
        }
        // 見えている高さ（札の中身の最低の高さに使う。回したとき・文字の大きさで変わる）
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if height != feedViewport { feedViewport = height }
        }
        // **ホームを開いたまま「ホーム」をもう一度押したら一番上へ**
        // （`TabRouter.homeTopRequests`）
        .onChange(of: tabRouter.homeTopRequests) { _, _ in
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(Self.feedTopID, anchor: .top)
            }
        }
        // UI テストのときだけ: 読んだページの数・選んでいるフィードが変わったら数を出し直す
        .onChange(of: model.loadedPageCount) { _, _ in
            if PreviewSession.feedProbe { updateFeedProbe() }
        }
        // ⑧ 深く送ってから替えたら、新しい一覧は頭から（札の行を上端へ・マイページと同じ）。まだ送っていなければそのまま
        .onChange(of: model.feed) { _, _ in
            if PreviewSession.feedProbe { updateFeedProbe() }
            guard ProfileTabScroll.scrollsToRow(rowMinY: feedRowSpot.minY, visibleTop: 0) else { return }
            withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                proxy.scrollTo(Self.feedRowID, anchor: .top)
            }
        }
        // ⑨ 「フォロー中」を開いた・開いている間に届いた・人が替わった・初めての日 → 既読を覚え直す
        .onChange(of: FollowingSeenKey(feed: model.feed, newest: followingNewest, viewer: auth.userId),
                  initial: true) { _, _ in
            syncFollowingSeen()
        }
        }
        // 送ると上に留まる切り替え（縦の送りの外に重ねる・マイページの `pinnedTabRow` と同じ）
        if feedRowPinned { pinnedFeedRow(followingHasNew: followingHasNew) }
        }
    }

    private static let feedTopID = "home-feed-top"
    /// 切り替えの札の行（深く送ってから替えたら、ここを上端へ）
    static let feedRowID = "home.feed.row"

    /// 札ごとの写真の束。**選んでいるフィードは出している一覧**（`model.state`）、選んでいないフィード
    /// （横にめくった隣）は同じ決まりで手元から作る（`GalleryViewModel.photos(for:)`）。ブロックを落とし、
    /// 投稿で束ね、季節の段の前後に割るのは控えから（`HomeFeedPageMemo`）
    private func pageRows(_ page: HomeFeed, selected: [Photo]) -> HomeFeedPageMemo.Rows {
        let raw = page == model.feed ? selected : model.photos(for: page)
        return pageMemo.rows(page, photos: raw, hidden: dropped)
    }

    /// 札の中身の段の間（以前の一覧の `LazyVStack` の間と同じ 24）
    nonisolated static let feedSpacing: CGFloat = 24

    /// 切り替えの下の中身（そのフィードの中身だけ）。**`model.feed` ではなく渡された札で分ける**——
    /// 選んでいない札も持ち続ける（`ProfileTabPager`・マイページの `tabContent` と同じ）。
    ///
    /// 🔴 **切り替えの下には、選んだフィードの中身だけを置く**（2026-10-11 判断）。
    /// 前は切り替えの下に「撮影地を探す／写真から探す」の2枚の札と、おすすめの
    /// 横並び（カテゴリごと）がいつも挟まり、「新着」「フォロー中」を押しても
    /// 結果がずっと下に出て、押して何が変わったか見えなかった。
    /// - 「撮影地を探す／写真から探す」は**消した**。板（Main「ホーム」）に無く、
    ///   下の札の「マップ」・見出しの 🔍 と行き先が同じ（同じ場所への入口が2つ）。
    ///   0枚のときの出口は `feedEmptyState` の主ボタンが持っている
    /// - おすすめの横並びは「おすすめ」の中身なので、**「おすすめ」のときだけ**出す
    ///   （`HomeFeed.showsFeatured`）
    /// - **#417 ④: 「いまの季節のスポット」の段も「おすすめ」の中身**。写真の大1→2→2（5枚）の後ろに置く
    ///   （`HomeFeed.showsSeasonShelf`・`splitForSeasonShelf`）
    @ViewBuilder
    private func feedSection(_ page: HomeFeed, rows: HomeFeedPageMemo.Rows) -> some View {
        if page.showsFeatured {
            featuredSections(page)
        }
        // **同じ投稿の写真は1枚のカードに束ねる**（モック6・8）。
        // 行は1枚ずつのままなので、個別ページもサイトマップも変わらない
        let groups = rows.groups
        // **続きがある間は「まだありません」と言わない**（読んだ範囲がブロックで全部落ちた・
        // 続きを読んでいる最中）。下の目印が次を読む
        if groups.isEmpty && !(page == model.feed && model.hasMorePages) {
            feedEmptyState(page)
        }
        // 板 01c: 大きく1枚 → 2枚 → 2枚、端から端まで・隙間 4pt
        // 🔴 **「おすすめ」では段の有無に関係なく、いつも5枚で割る**（PR #422 の確かめ）。段の中身は後から届くので、
        // 段の有無で枝を替えると写真の一覧（`HomeMosaic`）が作り直され、ちらつき・開いた詳細の元の札が作り直される。
        // 段だけを間に挟む。**写真が0枚の日は段を出さない**——空の知らせのすぐ下に作例の段が並ぶと、
        // 「おすすめ」が空なのか分からなくなる（空の知らせの一手は地図）
        if page.showsSeasonShelf {
            let split = (lead: rows.lead, rest: rows.rest)
            HomeMosaic(groups: split.lead, onReport: { reportTarget = $0 })
            if !groups.isEmpty, let seasonShelf {
                HomeSpotShelfView(shelf: seasonShelf.shelf, spots: seasonShelf.spots,
                                  photos: dropped.visible(model.allPhotosForTheme),
                                  reloadToken: storiesRefresh &+ tabRouter.menuSheetsClosed)
                    // 板: 段の上 12＋写真の隙間 4・下 8＋4（一覧の段の間 24 から詰める）
                    .padding(.top, Self.seasonShelfTopTrim)
                    .padding(.bottom, Self.seasonShelfBottomTrim)
            }
            if !split.rest.isEmpty {
                HomeMosaic(groups: split.rest, onReport: { reportTarget = $0 })
            }
        } else {
            // 「新着」の続きを読む目印は、写真の一覧の遅れて作る並び（`HomeMosaic` の `LazyVStack`）の最後の段。
            // 札の中身の普通の並びに置くと、画面の外でも `onAppear` がすぐ走り、作り直す（`id`）たびにまた読んで、
            // 送らなくても全部のページを読んでいた（#426 確かめ役）。続きを読むのは選んでいる「新着」だけ（`hasMorePages`）
            HomeMosaic(groups: groups, onReport: { reportTarget = $0 },
                       footer: page == model.feed && model.hasMorePages ? AnyView(pageFooter) : nil)
        }
    }

    /// 季節の段の上下を、一覧の段の間（24）から板の間（上 16・下 12）へ詰める量
    nonisolated static let seasonShelfTopTrim: CGFloat = -8
    nonisolated static let seasonShelfBottomTrim: CGFloat = -12

    /// ⑨ フォロー中に、まだ見ていない新しい写真があるか（`HomeFollowingNews`）
    private var followingHasNew: Bool {
        HomeFollowingNews.showsDot(feed: model.feed, newest: followingNewest, seen: followingSeen)
    }

    private var followingNewest: String? {
        model.followingNewest(viewerId: auth.userId, hiding: dropped)
    }

    /// ⑨ 既読を覚え直す（「フォロー中」を開いている間・初めての日）。覚えたら読み直す
    private func syncFollowingSeen() {
        let userId = auth.userId
        let seen = followingSeenStore.seen(for: userId)
        if let value = HomeFollowingNews.seenToStore(feed: model.feed, newest: followingNewest, seen: seen) {
            followingSeenStore.mark(value, for: userId)
        }
        followingSeen = followingSeenStore.seen(for: userId)
    }

    /// 「新着」の続き（`GET /feed`・2026-10-03）。**下まで送ったら次のページを読む**。
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

    /// 0枚のとき。**v2（2026-10-14・Main の「フォロー中が空」・Components 06）**:
    /// 共通の `EmptyState`（明朝 20 の見出し → 15 の text-2 → 一手）に寄せた。読めなかった回は
    /// `ErrorBanner`（三角の印と「もう一度試す」）——0件と失敗を同じ形にしない。
    ///
    /// 一手は `EmptyState` の主ボタン（写真の無い所＝真鍮の塗り＋墨・CLAUDE.md の owner の好み）。
    /// 板は真鍮の下線の字のリンクだが、0件の画面で押す所が1つしかないので主ボタンの形を取った
    @ViewBuilder
    private func feedEmptyState(_ page: HomeFeed) -> some View {
        if model.followingFailed && page == .following {
            // 引き下げを知らない人にも出口を（2026-10-02 の調査）
            ErrorBanner(message: emptyMessage(page), isBusy: isRefreshing) { Task { await refreshAll() } }
        } else if model.followingFailed {
            EmptyState(title: emptyTitle(page), message: emptyMessage(page))
        } else {
            EmptyState(title: emptyTitle(page), message: emptyMessage(page),
                       actionTitle: page == .following
                           ? L("写真や人を探す", "Find photos and people")
                           : L("撮影地を地図で探す", "Explore shooting places"),
                       actionIdentifier: "home.emptyAction") {
                page == .following ? tabRouter.openSearch() : tabRouter.openMap()
            }
        }
    }

    /// 0枚のときの見出し（明朝 20）。フォロー中が空の回だけ「何が無いか」を言う（板 Main）
    private func emptyTitle(_ page: HomeFeed) -> String? {
        page == .following && !model.followingFailed
            ? L("フォロー中の人の写真はまだありません", "No photos from people you follow yet")
            : nil
    }

    /// 0枚のときの一文。**フォロー一覧を取れなかった回に「まだありません」と言わない**
    /// （形は探すの写真の「読み込めませんでした。引き下げて読み直せます」と同じ）。
    /// フォロー中が空の回は、見出しが「何が無いか」を言うので、ここは「どうすれば埋まるか」（板 Main）
    private func emptyMessage(_ page: HomeFeed) -> String {
        guard page == .following else { return Labels.Gallery.empty }
        return model.followingFailed
            ? L("フォロー中の人を読み込めませんでした。引き下げて読み直せます",
                "Couldn't load the people you follow. Pull to retry")
            : L("気になる作者をフォローすると、新しい写真がここに並びます。",
                "Follow photographers you like and their new photos will appear here.")
    }

    /// 引き下げ・「もう一度試す」の読み直し。**重ねて走らせない**——続けて押すと、
    /// 遅れて返った古い回が新しい回の答えを上書きした（2026-10-02 のレビュー）
    private func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // ストーリーの輪も読み直す（写真だけ読み直すと、輪は古いまま残った）
        storiesRefresh &+= 1
        await model.load(force: true)
        // **フォロー一覧も取り直す。** 取れなかった回の出口
        // （「読み込めませんでした」の下の「もう一度試す」と引き下げ）
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

/// ホームの札ごとの写真の束ねの控え（#426 確かめ役の見直し・`GalleryView.pageRows`）。
/// 元の写真（同じ入れ物なら中身を見ずに一致）と「見せない」の写しが同じなら、前の答えを返す
final class HomeFeedPageMemo {

    struct Rows: Equatable {
        /// 投稿で束ねた写真（ブロックを落とした後）
        let groups: [PhotoGroups.Group]
        /// 「おすすめ」の季節の段の前（大1→2→2）と後ろ。段を出さないフィードは全部 `lead`
        let lead: [PhotoGroups.Group]
        let rest: [PhotoGroups.Group]
    }

    struct Key: Equatable {
        let photos: [Photo]
        let hidden: ModerationSnapshot
    }

    private var memos: [HomeFeed: DerivedMemo<Key, Rows>] = [:]

    init() {}

    func rows(_ page: HomeFeed, photos: [Photo], hidden: ModerationSnapshot) -> Rows {
        let memo = memos[page] ?? DerivedMemo<Key, Rows>()
        memos[page] = memo
        return memo.value(for: Key(photos: photos, hidden: hidden)) {
            Self.make(page, photos: photos, hidden: hidden)
        }
    }

    /// 計算した回数（試験用）
    func computeCount(_ page: HomeFeed) -> Int { memos[page]?.computeCount ?? 0 }

    static func make(_ page: HomeFeed, photos: [Photo], hidden: ModerationSnapshot) -> Rows {
        let groups = PhotoGroups.group(hidden.visible(photos))
        guard page.showsSeasonShelf else { return Rows(groups: groups, lead: groups, rest: []) }
        let split = HomeFeed.splitForSeasonShelf(groups)
        return Rows(groups: groups, lead: split.lead, rest: split.rest)
    }
}

/// 届いた束の写真を引き直す合図（`GalleryView`）
private struct PassResolveKey: Equatable {
    let due: Int
    let hidden: Int
}

/// 「フォロー中」の既読を覚え直す合図（`GalleryView.syncFollowingSeen`）
private struct FollowingSeenKey: Equatable {
    let feed: HomeFeed
    let newest: String?
    let viewer: String?
}
