import SwiftUI

/// いいねした写真。**端末の控え（`FavoritesStore`）を、取れた回にサーバーへ
/// 入れ替えてから**出す（起動時の `syncLikes` と同じ・`LikedPhotos`）。
/// 以前マイページの「お気に入り」タブにあった一覧をここへ移した（2026-09-26。
/// タブの中身は保存した写真＝`SavedPhotosView` になった）。
///
/// サーバーの一覧を画面に写しで持って控えと和を取ると、**詳細でハートを外して
/// 戻っても一覧に残る**（写しは開いた時点のまま）。控えだけを見れば、
/// 別の端末で押したぶん（入れ替えで足される）も、ここで外したぶん
/// （`favorites.set` で引かれる）も両方効く。
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
    /// 画面に出す分。**描画のたびに絞らない。**
    ///
    /// 絞りを計算に変えると、詳細画面でハートを外した瞬間に
    /// 元の `NavigationLink` が `ForEach` から消え、**見ている詳細画面が
    /// その場で閉じる**（SwiftUI は押した先を、押した元の存在に紐付ける）。
    /// 絞り直すのは**戻ってきたとき**（`.onAppear`）。
    @State private var photos: [Photo] = []
    /// 絞ったときの ID の数（「0件」と「引き当てられなかった」を分ける）
    @State private var idCount = 0
    /// 引き当て先を一度でも読み終えたか（「まだ」と「0件」を混ぜない）
    @State private var loaded = false
    /// サーバーに聞けなかった回（端末のぶんは消さない。足りないことだけ伝える）
    @State private var partial = false

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
                switch LikedPhotos.emptyState(idCount: idCount, loaded: loaded) {
                case .loading:
                    // 取得中に空の格子を出さない（以前のタブと同じく ProgressView）
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                case .none:
                    ErrorBanner(message: L("まだお気に入りがありません", "No liked photos yet"))
                case .unresolved:
                    ErrorBanner(message: L("いいねした写真を読み込めませんでした。通信の状態を確かめるか、消された写真かもしれません",
                                           "Couldn't load your liked photos. Check your connection — some may have been removed.")) {
                        Task { await load(force: true) }
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink { PhotoDetailView(photo: photo, context: photos) } label: {
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
        .onAppear { refilter() }
    }

    private func refilter() {
        feed = hidden.visible(feed)
        let ids = favorites.ids
        idCount = ids.count
        photos = LikedPhotos.resolve(ids, in: [feed, mine])
    }

    private func load(force: Bool = false) async {
        guard !auth.isResolving else { return }
        let signedIn = auth.userId != nil
        async let poolsTask = PhotoPools.load(environment, signedIn: signedIn, force: force)
        // **未ログインなら聞きに行かない**（端末の控えが答え）
        var failed = false
        if signedIn {
            do {
                let serverIds = try await environment.social.myLikedPhotoIds()
                // 取れた回だけ控えをサーバーに入れ替える（足し算と引き算の両方）
                if !Task.isCancelled { favorites.replace(with: serverIds) }
            } catch {
                // 取り消し（画面を離れた・読み直しに追い越された）は「聞けなかった」ではない
                failed = !(error is CancellationError) && !Task.isCancelled
            }
        }
        let pools = await poolsTask
        guard !Task.isCancelled else { return }
        partial = failed
        feed = pools.feed ?? feed
        // ログアウトしたら前の人の写真を残さない
        mine = signedIn ? (pools.mine ?? mine) : []
        loaded = true
        refilter()
    }
}
