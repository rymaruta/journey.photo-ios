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
                feed(dropped.visible(photos))
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
        // 見出しはどの画面も同じ（ロゴ・お知らせ・メニュー。ホームだけ「探す」も・`AppHeaderItems`）。
        // **地図のアイコンは外した**——下の札に「マップ」があり、
        // 同じ場所への入口が2つあった
        .toolbar { AppHeaderItems(unread: unread, showsSearch: true, onOpenNotifications: onOpenNotifications) }
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
        // **限定公開の写真の画像が期限切れで割れたら、取り直して新しい URL をもらう**
        // （2026-10-18・札 #294。`SignedImageExpiry`）。控えを使わず読む（控えの URL も同じ期限）
        .task {
            for await _ in SignedImageExpiry.signals() {
                await model.load(force: true)
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
    private var featuredSections: some View {
        // おすすめの横並びも、モザイクと同じ写しで落とす（戻った直後に見えない）
        ForEach(model.featured.filter { !dropped.visible($0.photos).isEmpty }) { group in
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
    /// ほかは text-3 の字。並びの下に白 8% の区切り線。高さ 44・間 22・左右 16。
    /// 以前は白の塗りの丸い切り替え（白＝選択）だったが、v2 の板は「選んでいるタブ」を真鍮にした
    /// （CLAUDE.md の owner の好み「選んでいるタブは真鍮」とも合う）。黒地の上なので真鍮が読める。
    /// **選んだことは下線（形）と読み上げ（`.isSelected`）でも伝える**——色だけにしない
    private var feedPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Self.feedTabGap) {
                ForEach(HomeFeed.allCases) { feed in
                    let selected = model.feed == feed
                    Button {
                        model.select(feed: feed, viewerId: auth.userId)
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
                    } label: {
                        Text(feed.label)
                            .font(JPFont.bodyEmphasis)
                            .foregroundStyle(selected ? WebTheme.accent : WebTheme.text3)
                            .frame(minHeight: WebTheme.minTapTarget)
                            // 選んだタブの下線（板: inset 0 -2px 0 真鍮）。字の幅いっぱい
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(selected ? WebTheme.accent : Color.clear)
                                    .frame(height: JPStroke.emphasis)
                            }
                            // 字の上だけでなく 44 の帯ぜんぶを押せるように
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, JPSpace.gutter)
            // 並びの下の区切り線（板: border-bottom 白 8%）
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            // **規則の一文は出さない**（整理案 01c）。写真より先に
            // 説明が並ぶと、開いた瞬間に読むものが増える。
            // 文言は `HomeFeed.note` に残してある
        }
    }

    /// 字のタブの間（板 Main の gap 22。4 の倍数に寄せて 24——`JPSpace.xl`）
    nonisolated static let feedTabGap: CGFloat = JPSpace.xl

    /// ホームは**板 01c の写真の並び**（`HomeMosaic`・2026-09-26）。
    /// 集約ページ（タグ・撮影地・機材）は角丸の `PhotoGrid` のまま。
    private func feed(_ photos: [Photo]) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 24) {
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
                                reloadToken: storiesRefresh &+ tabRouter.menuSheetsClosed)
                feedPicker
                // 🔴 **切り替えの下には、選んだフィードの中身だけを置く**（2026-10-11 判断）。
                // 前は切り替えの下に「撮影地を探す／写真から探す」の2枚の札と、おすすめの
                // 横並び（カテゴリごと）がいつも挟まり、「新着」「フォロー中」を押しても
                // 結果がずっと下に出て、押して何が変わったか見えなかった。
                // - 「撮影地を探す／写真から探す」は**消した**。板（Main「ホーム」）に無く、
                //   下の札の「マップ」・見出しの 🔍 と行き先が同じ（同じ場所への入口が2つ）。
                //   0枚のときの出口は `feedEmptyState` の主ボタンが持っている
                // - おすすめの横並びは「おすすめ」の中身なので、**「おすすめ」のときだけ**出す
                //   （`HomeFeed.showsFeatured`）
                if model.feed.showsFeatured {
                    featuredSections
                }
                // **同じ投稿の写真は1枚のカードに束ねる**（モック6・8）。
                // 行は1枚ずつのままなので、個別ページもサイトマップも変わらない
                let groups = PhotoGroups.group(photos)
                // **続きがある間は「まだありません」と言わない**（読んだ範囲がブロックで全部落ちた・
                // 続きを読んでいる最中）。下の目印が次を読む
                if groups.isEmpty && !model.hasMorePages {
                    feedEmptyState
                }
                // 板 01c: 大きく1枚 → 2枚 → 2枚、端から端まで・隙間 4pt
                HomeMosaic(groups: groups, onReport: { reportTarget = $0 })
                pageFooter
            }
            .padding(.top, 8)
            // 最後のカードがタブバーに掛からないようにする
            .padding(.bottom, 24)
        }
        // **ホームを開いたまま「ホーム」をもう一度押したら一番上へ**
        // （`TabRouter.homeTopRequests`）
        .onChange(of: tabRouter.homeTopRequests) { _, _ in
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(Self.feedTopID, anchor: .top)
            }
        }
        }
    }

    private static let feedTopID = "home-feed-top"

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
    private var feedEmptyState: some View {
        if model.followingFailed && model.feed == .following {
            // 引き下げを知らない人にも出口を（2026-10-02 の調査）
            ErrorBanner(message: emptyMessage, isBusy: isRefreshing) { Task { await refreshAll() } }
        } else if model.followingFailed {
            EmptyState(title: emptyTitle, message: emptyMessage)
        } else {
            EmptyState(title: emptyTitle, message: emptyMessage,
                       actionTitle: model.feed == .following
                           ? L("写真や人を探す", "Find photos and people")
                           : L("撮影地を地図で探す", "Explore shooting places"),
                       actionIdentifier: "home.emptyAction") {
                model.feed == .following ? tabRouter.openSearch() : tabRouter.openMap()
            }
        }
    }

    /// 0枚のときの見出し（明朝 20）。フォロー中が空の回だけ「何が無いか」を言う（板 Main）
    private var emptyTitle: String? {
        model.feed == .following && !model.followingFailed
            ? L("フォロー中の人の写真はまだありません", "No photos from people you follow yet")
            : nil
    }

    /// 0枚のときの一文。**フォロー一覧を取れなかった回に「まだありません」と言わない**
    /// （形は探すの写真の「読み込めませんでした。引き下げて読み直せます」と同じ）。
    /// フォロー中が空の回は、見出しが「何が無いか」を言うので、ここは「どうすれば埋まるか」（板 Main）
    private var emptyMessage: String {
        guard model.feed == .following else { return Labels.Gallery.empty }
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

/// 届いた束の写真を引き直す合図（`GalleryView`）
private struct PassResolveKey: Equatable {
    let due: Int
    let hidden: Int
}
