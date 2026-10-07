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

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            if screen.shown.partial {
                ErrorBanner(message: L("サーバーのいいねを取れませんでした。この端末に覚えているぶんだけ出しています",
                                       "Couldn't reach the server — showing what's on this device")) {
                    Task { await load(force: true) }
                }
            }
            if photos.isEmpty {
                switch LikedPhotos.emptyState(idCount: idCount, loaded: screen.shown.loaded, failed: screen.shown.poolsFailed) {
                case .loading:
                    // 取得中に空の格子を出さない（以前のタブと同じく ProgressView）
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                case .none:
                    EmptyState(message: L("まだお気に入りがありません", "No liked photos yet"))
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
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: photos)
                        } label: {
                            PhotoFrame(photo: photo)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.favorites)
        // **ログイン状態が決まってから**聞く。確認中（`isResolving`）を
        // 未ログインと同じに扱わない。決まったら id が変わって読み直す
        // 鍵に戻ってきた回数を入れる——戻るたびに読み直す（消した自分の写真を落とす・H-2）
        .task(id: "\(auth.state)#\(screen.returns)") { await load() }
        .refreshable { await load(force: true) }
        // **戻ってきたら絞り直す。** 詳細画面でハートを外したぶんは、
        // その画面を閉じたこの時点で消える（見ている最中には消さない）
        // ブロック／通報したぶんも、同じく戻ってきたときに落とす
        // 読み込みの答えも、ここで入れる（詳細を開いている間に届いた分・H-2）
        .onAppear {
            screen.appear()
            refilter()
        }
        .onDisappear { screen.disappear() }
    }

    private func refilter() {
        let ids = favorites.listedIds(server: screen.shown.serverIds)
        idCount = ids.count
        photos = screen.shown.resolve(ids) { hidden.visible($0) }
    }

    private func load(force: Bool = false) async {
        guard !auth.isResolving else { return }
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
        if screen.receive(fetch) { refilter() }
    }
}
