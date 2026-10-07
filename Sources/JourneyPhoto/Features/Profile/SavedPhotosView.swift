import SwiftUI

/// 保存した写真（板 35「お気に入り」・板 01d のメニューの「保存した写真」）。
///
/// 写真の詳細のしおり（保存）の行き先。**いいねとは別の入れ物**
/// （`SavedPhotosStore` と `FavoritesStore`）——以前はマイページの
/// 「お気に入り」（しおりの印・英語は "Saved"）の中身がいいねした写真で、
/// 保存した写真を見返す場所がどこにも無かった。
///
/// 並びは板どおり**先頭を大きく1枚、その下は2列**（`PhotoGrid`）。
/// 板の注記「この端末に覚えています」は**書かない**——保存はサーバーが本体で、
/// ほかの端末にも出る（`SaveService`）。事実と違う文を置かない。
struct SavedPhotosView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var hidden: ModerationStore
    /// 引き当て先（公開一覧＋自分の写真・`PhotoPools`）と、読み込みの答えを入れる時機。
    /// **戻るたびに読み直し、答えは画面に出ている間だけ入れる**（`LikedPhotosScreen`・H-2）
    @State private var screen = LikedPhotosScreen()
    /// 画面に出す分。**戻ってきたときに絞り直す**（`FavoritesView` と同じ理由——
    /// 見ている詳細でしおりを外した瞬間に元の行が消えると、詳細が閉じる）
    @State private var photos: [Photo] = []
    /// 絞ったときの ID の数（「0件」と「出せる写真が無い」を分ける）
    @State private var idCount = 0

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                switch LikedPhotos.emptyState(idCount: idCount, loaded: screen.shown.loaded, failed: screen.shown.poolsFailed) {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                case .none:
                    EmptyState(message: Self.emptyMessage)
                case .nothingShown:
                    EmptyState(message: LikedPhotos.nothingShownMessage)
                case .unresolved:
                    ErrorBanner(message: Self.unresolvedMessage) {
                        Task { await load(force: true) }
                    }
                }
            } else {
                // 公開一覧から引き当てた写真だけ個別ページが在る（`LikedPhotos.fromPublicFeed`）
                let isPublic = LikedPhotos.fromPublicFeed(hidden.visible(screen.shown.feed))
                PhotoGrid(photos: photos) { photo in
                    PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: photos)
                }
            }
        }
        .webScreen()
        .navigationTitle(ProfileTab.favorites.label)
        // 鍵に戻ってきた回数を入れる——戻るたびに読み直す（消した自分の写真を落とす・H-2）
        .task(id: "\(auth.state)#\(screen.returns)") { await load() }
        .refreshable { await load(force: true) }
        .onAppear {
            screen.appear()
            refilter()
        }
        .onDisappear { screen.disappear() }
    }

    /// マイページの「お気に入り」タブでも使う
    static var emptyMessage: String {
        L("保存した写真はまだありません。写真の詳細のしおりで保存できます",
          "No saved photos yet. Tap the bookmark on a photo to save it.")
    }

    /// 保存はあるのに、引き当て先の読み込みが失敗して1枚も出せなかった回
    /// （マイページのタブでも使う）。
    /// 「まだありません」と言うと、保存が消えたように読める
    static var unresolvedMessage: String {
        L("保存した写真を読み込めませんでした。通信の状態を確かめるか、消された写真かもしれません",
          "Couldn't load your saved photos. Check your connection — some may have been removed.")
    }

    // 引き当ての決まり（id を手元の写真の束から探す・重複は1枚に）はいいねと同じ
    // （`LikedPhotos.resolve`）。保存のために同じ関数をもう1つ作らない
    private func refilter() {
        let ids = savedPhotos.ids
        idCount = ids.count
        photos = screen.shown.resolve(ids) { hidden.visible($0) }
    }

    private func load(force: Bool = false) async {
        // ログインの確認中は待つ（決まったら `.task(id:)` が読み直す）
        guard !auth.isResolving else { return }
        let user = auth.userId
        let pools = await PhotoPools.load(environment, signedIn: user != nil, force: force)
        // 取り消された回（画面を離れた・読み直しに追い越された）は何も書かない
        guard !Task.isCancelled else { return }
        // 画面に出ていなければ取っておき、戻ったときに入れる（詳細を閉じない）
        if screen.receive(.init(user: user, feed: pools.feed, mine: pools.mine)) { refilter() }
    }
}
