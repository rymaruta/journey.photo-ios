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
    /// 引き当て先（公開一覧＋自分の写真・`PhotoPools`）。
    /// 以前のマイページのタブは自分の写真も見ていた——公開一覧だけだと、
    /// 自分の非公開の写真へのいいねが落ちる
    @State private var feed: [Photo] = []
    @State private var mine: [Photo] = []
    /// 今回取れたサーバーのいいね一覧（取れなければ nil）。
    /// 控えは書き換えず、絞るときに和を取る（`refilter`）
    @State private var serverIds: [String]?
    /// 画面に出す分。**描画のたびに絞らない。**
    ///
    /// 絞りを計算に変えると、詳細画面でハートを外した瞬間に
    /// 元の `NavigationLink` が `ForEach` から消え、**見ている詳細画面が
    /// その場で閉じる**（SwiftUI は押した先を、押した元の存在に紐付ける）。
    /// 絞り直すのは**戻ってきたとき**（`.onAppear`）。
    @State private var photos: [Photo] = []
    /// 絞ったときの ID の数（「0件」と「出せる写真が無い」を分ける）
    @State private var idCount = 0
    /// 引き当て先を一度でも読み終えたか（「まだ」と「0件」を混ぜない）
    @State private var loaded = false
    /// 最後の読み込みで引き当て先が取れなかったか（「読み込めませんでした」はこの回だけ）
    @State private var poolsFailed = false
    /// サーバーに聞けなかった回（端末のぶんは消さない。足りないことだけ伝える）
    @State private var partial = false
    /// 一度でもこの画面が出たか。**戻ってきた回だけ読み直す**ための印
    /// （初回は `.task(id:)` が読む・`GalleryView`・`MyPageView` と同じ形）
    @State private var didAppear = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            if partial {
                ErrorBanner(message: L("サーバーのいいねを取れませんでした。この端末に覚えているぶんだけ出しています",
                                       "Couldn't reach the server — showing what's on this device")) {
                    Task { await load(force: true) }
                }
            }
            if photos.isEmpty {
                switch LikedPhotos.emptyState(idCount: idCount, loaded: loaded, failed: poolsFailed) {
                case .loading:
                    // 取得中に空の格子を出さない（以前のタブと同じく ProgressView）
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                case .none:
                    ErrorBanner(message: L("まだお気に入りがありません", "No liked photos yet"))
                case .nothingShown:
                    ErrorBanner(message: LikedPhotos.nothingShownMessage)
                case .unresolved:
                    ErrorBanner(message: L("いいねした写真を読み込めませんでした。通信の状態を確かめるか、消された写真かもしれません",
                                           "Couldn't load your liked photos. Check your connection — some may have been removed.")) {
                        Task { await load(force: true) }
                    }
                }
            } else {
                // 公開一覧から引き当てた写真だけ個別ページが在る（`LikedPhotos.fromPublicFeed`）
                let isPublic = LikedPhotos.fromPublicFeed(hidden.visible(feed))
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
        .task(id: auth.state) { await load() }
        .refreshable { await load(force: true) }
        // **戻ってきたら絞り直す。** 詳細画面でハートを外したぶんは、
        // その画面を閉じたこの時点で消える（見ている最中には消さない）
        // ブロック／通報したぶんも、同じく戻ってきたときに落とす
        // 消した自分の写真も、戻ってきたときに読み直して落とす（`SavedPhotosView` と同じ）
        .onAppear {
            refilter()
            if didAppear { Task { await load() } }
            didAppear = true
        }
    }

    private func refilter() {
        let ids = favorites.listedIds(server: serverIds)
        idCount = ids.count
        photos = LikedPhotos.resolve(ids, in: [hidden.visible(feed), mine])
    }

    private func load(force: Bool = false) async {
        guard !auth.isResolving else { return }
        let signedIn = auth.userId != nil
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
        partial = failed
        // 取れなかった回は前の一覧を**残さない**（控えだけ出す）。残すと、人が
        // 替わった直後に取れなかったとき、前の人のいいねが次の人に見える
        serverIds = fetched
        poolsFailed = pools.feed == nil || (signedIn && pools.mine == nil)
        feed = pools.feed ?? feed
        // ログアウトしたら前の人の写真を残さない
        mine = signedIn ? (pools.mine ?? mine) : []
        loaded = true
        refilter()
    }
}
