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
    /// 通報している写真。**シートはカードではなくここに付ける**
    /// （`HomeMosaic.onReport` の注記）
    @State private var reportTarget: Photo?
    /// いまこの画面が出ているか。**詳細を上に積んでいる間は読み直さない**
    @State private var isOnScreen = false
    /// 出ていない間にブロック／通報があった。戻ってきたときに読み直す
    @State private var needsReload = false
    /// 描くときに落とす「見せない」の写し。**画面に出ている間だけ取り直す**。
    /// 戻った瞬間、読み直しが終わるまでブロックした人のカードが見えないように
    @State private var dropped = ModerationSnapshot()
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
            guard auth.userId != nil else {
                model.use(viewerId: nil, following: [])
                await model.loadMyPhotos(environment.photos, viewerId: nil)
                return
            }
            let ids = (try? await environment.social.myFollowingIds()) ?? []
            model.use(viewerId: auth.userId, following: Set(ids))
            // 今日のテーマに参加したかの判定に要る（API から読む）
            await model.loadMyPhotos(environment.photos, viewerId: auth.userId)
        }
        .refreshable { await model.load(force: true) }
        .sheet(item: $reportTarget) { target in
            ReportSheet(photoId: target.id, ownerId: target.userId)
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
        }
        .onDisappear { isOnScreen = false }
    }

    private func reloadHidden() {
        needsReload = false
        Task {
            await environment.gallery.setHidden(userIds: hidden.blockedUserIds,
                                                photoIds: hidden.reportedPhotoIds)
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
                        Text(L("すべて見る", "See all"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
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
                        guard feed == .following, auth.userId != nil else { return }
                        Task {
                            // **取れなかった回に空で潰さない**（圏外で押しただけで
                            // 「フォロー中」が知らせも無く空になる）
                            guard let ids = try? await environment.social.myFollowingIds() else { return }
                            model.refreshFollowing(Set(ids))
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
                StoriesRow(reloadToken: tabRouter.postSheetsClosed)
                // **今日のテーマ**（モック1）。通信はしない——日付から決まる。
                // 整理案 01c で1枚目の写真の後ろの細い帯にしたが、owner の
                // 「前の方が好きだった」で先頭の大きな札に戻した（2026-09-26）
                // 背景の写真もブロック／通報を落とした並びから（読み直しが終わるまで
                // ブロックした人の写真が札の背景に出ていた）
                DailyThemeCard(photos: dropped.visible(model.allPhotosForTheme), myPhotos: model.myPhotos)
                feedPicker
                featuredSections
                // **同じ投稿の写真は1枚のカードに束ねる**（モック6・8）。
                // 行は1枚ずつのままなので、個別ページもサイトマップも変わらない
                let groups = PhotoGroups.group(photos)
                if groups.isEmpty {
                    Text(model.feed == .following
                         ? L("フォロー中の人の写真はまだありません", "No photos from people you follow yet")
                         : Labels.Gallery.empty)
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .padding(.horizontal, 24)
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
}
