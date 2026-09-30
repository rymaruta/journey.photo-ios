import SwiftUI

struct GalleryView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// **「見せない」が変わったら読み直すため**に見ている。
    /// この画面はタブの根なので一度出たら生き続け、`.task` は二度と走らない
    /// ——ブロックしても、戻ってくるとその人の写真がまだ並んでいた
    @EnvironmentObject private var hidden: ModerationStore
    @StateObject private var model = GalleryViewModel()
    /// 「ホーム」をもう一度押した合図（一番上へ戻る）
    @ObservedObject private var tabRouter = TabRouter.shared
    /// ストーリーの輪を読み直す合図（引き下げ・前面に戻った）
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
    /// 出ていない間に投稿を閉じた。戻ってきたときに自分の写真を読み直す
    @State private var needsMyPhotosReload = false
    /// 描くときに落とす「見せない」の写し。**画面に出ている間だけ取り直す**。
    /// 戻った瞬間、読み直しが終わるまでブロックした人のカードが見えないように
    @State private var dropped = ModerationSnapshot()
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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
            model.use(gallery: environment.gallery)
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
        .refreshable {
            // ストーリーの輪も読み直す（写真だけ読み直すと、輪は古いまま残った）
            storiesRefresh &+= 1
            await model.load(force: true)
            // **フォロー一覧も取り直す。** 取れなかった回の出口
            // （「読み込めませんでした。引き下げて読み直せます」）
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
        // **下の「投稿」を閉じたら自分の写真を読み直す。** 今日のテーマの札から投稿しても、
        // シートは `RootView` にあるので `.task(id:)` は走らず、札が「参加する」のまま残った
        //
        // 🔴 **画面に出ている間だけ**（`MyPageView` と同じ）。旅の一冊などを上に積んだまま
        // 読み直すと、札が差し替わって開いている画面ごと閉じる。出ていない回は印を立て、
        // 戻ってきたとき（`onAppear`）に読み直す
        .onChange(of: tabRouter.postSheetsClosed) { _, _ in
            guard auth.userId != nil else { return }
            if isOnScreen { reloadMyPhotos() } else { needsMyPhotosReload = true }
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
        .sheet(item: $reportTarget) { target in
            ReportSheet(photoId: target.id, ownerId: target.userId ?? target.uploadedBy)
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
            isOnScreen = true
            dropped = hidden.snapshot
            if needsReload { reloadHidden() }
            if needsMyPhotosReload { reloadMyPhotos() }
        }
        .onDisappear { isOnScreen = false }
    }

    private func reloadMyPhotos() {
        needsMyPhotosReload = false
        guard let userId = auth.userId else { return }
        Task { await model.loadMyPhotos(environment.photos, viewerId: userId) }
    }

    private func reloadHidden() {
        needsReload = false
        Task {
            await environment.gallery.setHidden(hidden.snapshot)
            await model.load()
        }
    }

    /// owner が選んだ「おすすめ」。Web はトップの一覧の上に、
    /// カテゴリごとの横並びで出している（`FeaturedSections`）。
    @ViewBuilder
    private var featuredSections: some View {
        // おすすめの横並びも、モザイクと同じ写しで落とす（戻った直後に見えない）
        ForEach(model.featured.filter { !dropped.visible($0.photos).isEmpty }) { group in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.label)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.foreground)
                    Spacer()
                    NavigationLink {
                        TagPhotosView(kind: .category(group.id))
                    } label: {
                        // 字の見た目・行の高さはそのまま、当たりだけ 44pt。
                        // **上へ多めに広げる**——上は並び同士の間（24）が空いているが、
                        // 下は 8 で写真の横並びがすぐ来る（写真の押し下げを奪わない）
                        Text(L("すべて見る", "See all"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                            .padding(.top, 18)
                            .padding(.bottom, 10)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                            .padding(.top, -18)
                            .padding(.bottom, -10)
                    }
                }
                .padding(.horizontal, 12)

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
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// ホームからJourney Photoの核（撮影地の発見）へ直接つなぐ。
    /// 写真が少ない時期でも、空のSNSに見せず「次に何ができるか」を示す。
    private var discoveryBridge: some View {
        HStack(spacing: 10) {
            Button { tabRouter.openMap() } label: {
                discoveryAction(title: L("撮影地を探す", "Explore places"),
                                note: L("地図から見つける", "Discover on the map"),
                                systemImage: "map")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.exploreMap")

            Button { tabRouter.openSearch() } label: {
                discoveryAction(title: L("写真から探す", "Explore photos"),
                                note: L("場所・機材・季節", "Place · gear · season"),
                                systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.exploreSearch")
        }
        .padding(.horizontal, 16)
    }

    private func discoveryAction(title: String, note: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(WebTheme.accent)
                .frame(width: 34, height: 34)
                .background(WebTheme.background, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                // 本文の最小は 12pt（CLAUDE.md）。縮めずに2行まで
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WebTheme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    /// フィードの切り替え（おすすめ / フォロー中 / 新着）。
    ///
    /// **推薦の口は無い**ので、おすすめの規則を下に1行で出す
    /// （指示書 5-2——実装済みであるかのように見せない）。**その一文は
    /// 整理案 01c で画面から外した**（owner の承認・2026-09-26）。文言は `HomeFeed.note`
    private var feedPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
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
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(selected ? AnyShapeStyle(WebTheme.foreground)
                                                 : AnyShapeStyle(Color.clear),
                                        in: Capsule())
                            // 押せる範囲だけ 44pt 以上に（札も帯も大きさは変えない。`CategoryField` と
                            // 同じ形で、外側の帯の余白 4 の分まで押せる）。選んでいない札は
                            // 地が透明で、字の上しか押せなかった
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .padding(.vertical, -4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(WebTheme.surface, in: Capsule())
            // **規則の一文は出さない**（整理案 01c）。写真より先に
            // 説明が並ぶと、開いた瞬間に読むものが増える。
            // 文言は `HomeFeed.note` に残してある
        }
        .padding(.horizontal, 16)
    }

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
                StoriesRow(reloadToken: tabRouter.postSheetsClosed &+ storiesRefresh)
                // **今日のテーマ**（モック1）。通信はしない——日付から決まる。
                // 整理案 01c で1枚目の写真の後ろの細い帯にしたが、owner の
                // 「前の方が好きだった」で先頭の大きな札に戻した（2026-09-26）
                // 背景の写真もブロック／通報を落とした並びから（読み直しが終わるまで
                // ブロックした人の写真が札の背景に出ていた）
                // 2026-09-27: 上段は「開く場面ごとに1枚」（出発・旅の最中・一冊・1年前）
                // 2026-09-28: 当たる札と今日のテーマを**横にめくる並び**に（owner「両方欲しい」）
                // 自分の写真も同じ写しで絞る（消した・非公開にした写真の札が残り、押すと 404。
                // `gone` は `published: false` の行を落とさないので、下書きは残る）
                HomeTopCardView(themePhotos: dropped.visible(model.allPhotosForTheme),
                                myPhotos: dropped.visible(model.myPhotos),
                                reloadToken: storiesRefresh &+ tabRouter.menuSheetsClosed)
                feedPicker
                discoveryBridge
                featuredSections
                // **同じ投稿の写真は1枚のカードに束ねる**（モック6・8）。
                // 行は1枚ずつのままなので、個別ページもサイトマップも変わらない
                let groups = PhotoGroups.group(photos)
                if groups.isEmpty {
                    feedEmptyState
                }
                // 板 01c: 大きく1枚 → 2枚 → 2枚、端から端まで・隙間 4pt
                HomeMosaic(groups: groups, onReport: { reportTarget = $0 })
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

    private var feedEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: model.feed == .following ? "person.2" : "photo.on.rectangle.angled")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center)
            if !model.followingFailed {
                Button {
                    model.feed == .following ? tabRouter.openSearch() : tabRouter.openMap()
                } label: {
                    Label(model.feed == .following
                          ? L("写真や人を探す", "Find photos and people")
                          : L("撮影地を地図で探す", "Explore shooting places"),
                          systemImage: model.feed == .following ? "magnifyingglass" : "map")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(WebTheme.foreground, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.emptyAction")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }

    /// 0枚のときの一文。**フォロー一覧を取れなかった回に「まだありません」と言わない**
    /// （形は探すの写真の「読み込めませんでした。引き下げて読み直せます」と同じ）
    private var emptyMessage: String {
        guard model.feed == .following else { return Labels.Gallery.empty }
        return model.followingFailed
            ? L("フォロー中の人を読み込めませんでした。引き下げて読み直せます",
                "Couldn't load the people you follow. Pull to retry")
            : L("フォロー中の人の写真はまだありません", "No photos from people you follow yet")
    }

    /// フォロー一覧。**取れなかったら nil**（空の集合と分ける）
    private func fetchFollowing() async -> Set<String>? {
        let ids = try? await environment.social.myFollowingIds()
        return ids.map { Set($0) }
    }
}
