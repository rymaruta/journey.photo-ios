import SwiftUI

/// いいねした写真。**サーバーの一覧 ∪ 端末の控え − この起動中にこの端末で
/// 外したもの**を出す（`FavoritesStore.listedIds(server:)`）。
/// 以前マイページの「お気に入り」タブにあった一覧をここへ移した（2026-09-26。
/// タブの中身は保存した写真＝`SavedPhotosView` になった）。
///
/// サーバーの一覧の写しと控えの和だけだと、**詳細でハートを外して戻っても
/// 一覧に残る**（写しは開いた時点のまま）。だから外したぶんを引く。
/// 🔴 **ここで控えを入れ替えない**（`favorites.replace`）。サーバーの一覧の
/// 読み取りは強い整合でなく、外した直後に開くと古い一覧で外したいいねが
/// **控えに戻って保存される**。一覧の書き込みはベストエフォート
/// （`likes.ts` の `noteLiked`）で、控えがその救済——入れ替えるのは起動時の
/// `syncLikes` だけ。
/// 控えがあるので**圏外でも一覧は出る**（画像そのものは一度見たものだけ）。
struct FavoritesView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var hidden: ModerationStore
    /// 引き当て先（公開一覧＋自分の写真・`PhotoPools`）とサーバーのいいね一覧、
    /// 読み込みの答えを入れる時機（`LikedPhotosScreen`・H-2）。
    /// 以前のマイページのタブは自分の写真も見ていた——公開一覧だけだと、
    /// 自分の非公開の写真へのいいねが落ちる。サーバーの一覧は控えを書き換えず、
    /// 絞るときに和を取る（`refilter`）。**戻るたびに読み直し、答えは画面に
    /// 出ている間だけ入れる。取れなかった回は同じ人なら前の一覧を残す**
    @State private var screen = LikedPhotosScreen()
    /// 画面に出す分。**描画のたびに絞らない。**
    ///
    /// 絞りを計算に変えると、詳細画面でハートを外した瞬間に
    /// 元の `NavigationLink` が `ForEach` から消え、**見ている詳細画面が
    /// その場で閉じる**（SwiftUI は押した先を、押した元の存在に紐付ける）。
    /// 絞り直すのは**戻ってきたとき**（`.onAppear`）。
    @State private var photos: [Photo] = []
    /// 絞ったときの ID の数（「0件」と「出せる写真が無い」を分ける）
    @State private var idCount = 0
    /// 戻り `onAppear` のあと前面確定を待つ仕事（スワイプキャンセルで消す）
    @State private var frontSettle: Task<Void, Never>?

    /// 板 v2 Favorites: 先頭の1枚の下は 3 列・すき間 2・正方形
    private let columns = ProfileV2.gridItems

    /// 先頭の大きな1枚の高さ（板 v2 Favorites: 280）
    nonisolated static let heroHeight: CGFloat = 280

    var body: some View {
        ScrollView {
            header
            if screen.shown.partial {
                ErrorBanner(message: L("いいねを読み込めませんでした。この端末に覚えているぶんだけ出しています",
                                       "Couldn't load your likes — showing what's on this device")) {
                    Task { await load(force: true) }
                }
            }
            if photos.isEmpty {
                switch LikedPhotos.emptyState(idCount: idCount, loaded: screen.shown.loaded, failed: screen.shown.poolsFailed) {
                case .loading:
                    // 取得中に空の格子を出さない（v2: 格子の骨格・0.3 秒より早ければ出さない）
                    JPLoadingState(kind: .grid)
                case .none:
                    // 2026-10-17: いいねは写真から。写真に出会う所（ホーム）へ1手（マイページの保存0枚と同じ道）
                    EmptyState(message: L("まだいいねした写真がありません", "No liked photos yet"),
                               actionTitle: MyPageEmpty.browseTitle, actionIdentifier: "favorites.emptyBrowse") {
                        TabRouter.shared.openHome()
                    }
                case .nothingShown:
                    EmptyState(message: LikedPhotos.nothingShownMessage)
                case .unresolved:
                    ErrorBanner(message: L("いいねした写真を読み込めませんでした。通信の状態を確かめるか、消された写真かもしれません",
                                           "Couldn't load your liked photos. Check your connection — some may have been removed.")) {
                        Task { await load(force: true) }
                    }
                }
            } else {
                // 公開一覧から引き当てた写真だけ個別ページが在る（`LikedPhotos.fromPublicFeed`）
                let isPublic = LikedPhotos.fromPublicFeed(hidden.visible(screen.shown.feed))
                // 板 v2 Favorites: 先頭を大きな1枚に（題は写真の上に白・写真の上は白だけ）
                if let first = photos.first {
                    NavigationLink {
                        PhotoDetailView(photo: first, fromPublicFeed: isPublic(first), context: photos)
                    } label: {
                        hero(first)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(first.accessibilityText)
                    .padding(.top, JPSpace.m)
                }
                LazyVGrid(columns: columns, spacing: ProfileV2.gridSpacing) {
                    ForEach(photos.dropFirst()) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: photos)
                        } label: {
                            PhotoFrame(photo: photo, corner: 0)
                                .background(WebTheme.card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, ProfileV2.gridSpacing)
            }
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.favorites)
        .navigationBarTitleDisplayMode(.inline)
        // 題は下の明朝の見出しが受け持つ（板 v2）。バーの中央は空けておく（戻る文字と読み上げには題を持つ）
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
        // **ログイン状態が決まってから**聞く。確認中（`isResolving`）を
        // 未ログインと同じに扱わない。決まったら id が変わって読み直す
        // 鍵に戻ってきた回数を入れる——戻るたびに読み直す（消した自分の写真を落とす・H-2）
        .task(id: screen.key(auth: "\(auth.state)")) { await load() }
        .refreshable { await load(force: true) }
        // **戻ってきたら絞り直す。** 詳細画面でハートを外したぶんは、
        // その画面を閉じたこの時点で消える（見ている最中には消さない）
        // ブロック／通報したぶんも、同じく戻ってきたときに落とす
        // 読み込みの答えも、前面が確定してから入れる（スワイプ途中キャンセルで閉じない・H-2）
        .onAppear {
            screen.appear()
            refilter()
            frontSettle?.cancel()
            frontSettle = Task {
                try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                guard !Task.isCancelled else { return }
                if screen.confirmFront() { refilter() }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            screen.disappear()
        }
    }

    /// 見出し（板 v2 Favorites）: 眉「LIKED · N枚」（真鍮・黒地）→ 明朝の題 → 何の一覧かの一行（13・text-2）。
    /// 板の題は明朝 30 だが、字の段（`JPTypeScale`）に 30 は無いので画面の題の 26（`JPFont.screenTitle`）
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(photos.isEmpty ? L("LIKED", "LIKED") : L("LIKED · \(photos.count)枚", "LIKED · \(photos.count)"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            Text(Labels.Navigation.favorites)
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(L("ハートを押した写真。作者に届き、ほかの端末や Web でも同じ一覧が見られます。しおりで保存した写真はマイページの「保存」に。",
                   "Photos you liked. The photographer is notified, and the same list appears on your other devices and the web. Bookmarked photos are under Saved on your page."))
                .font(JPFont.footnote)
                .lineSpacing(4)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ProfileV2.gutter)
        .padding(.top, JPSpace.xs)
    }

    /// 先頭の大きな1枚（板 v2 Favorites: 高さ 280・下 120pt を黒 70% へ・左下に明朝 20 の題と撮影地）
    private func hero(_ photo: Photo) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.heroHeight)
            .overlay {
                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
            }
            .background(WebTheme.card)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if !photo.displayTitle.isEmpty {
                        Text(photo.displayTitle)
                            .font(JPFont.stateTitle)
                            .lineLimit(2)
                    }
                    let place = LocationMatch.display(photo.location)
                    if !place.isEmpty {
                        Text(place)
                            .font(JPFont.footnote)
                            .opacity(0.88)
                            .lineLimit(1)
                    }
                }
                // 写真の上は白だけ（CLAUDE.md）
                .foregroundStyle(Color.white)
                .padding(.horizontal, ProfileV2.gutter)
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
    }

    private func refilter() {
        let ids = favorites.listedIds(server: screen.shown.serverIds)
        idCount = ids.count
        photos = screen.shown.resolve(ids) { hidden.visible($0) }
    }

    private func load(force: Bool = false) async {
        guard !auth.isResolving else { return }
        // 読み終えた鍵での再実行は空振り（戻ったときに2本立てない・`LikedPhotosScreen.loadedKey`）
        let key = screen.key(auth: "\(auth.state)")
        guard force || screen.needsLoad(key) else { return }
        let user = auth.userId
        let signedIn = user != nil
        async let poolsTask = PhotoPools.load(environment, signedIn: signedIn, force: force)
        // **未ログインなら聞きに行かない**（端末の控えが答え）
        var failed = false
        var fetched: [String]?
        if signedIn {
            do {
                // 控えは書き換えない（上の説明）。和は `refilter` で取る
                fetched = try await environment.social.myLikedPhotoIds()
            } catch {
                // 取り消し（画面を離れた・読み直しに追い越された）は「聞けなかった」ではない
                failed = !(error is CancellationError) && !Task.isCancelled
            }
        }
        let pools = await poolsTask
        guard !Task.isCancelled else { return }
        // 取れなかった回は、同じ人なら前の一覧を残す（圏外で戻っても、ほかの端末の
        // いいねを消さない）。人が替わった直後は残さない（`LikedPhotosScreen.Materials.absorbing`）。
        // 画面に出ていなければ取っておき、戻ったときに入れる（詳細を閉じない）
        let fetch = LikedPhotosScreen.Fetch(user: user, feed: pools.feed, mine: pools.mine,
                                            serverIds: fetched, serverFailed: failed)
        if screen.receive(fetch, key: key) { refilter() }
    }
}
