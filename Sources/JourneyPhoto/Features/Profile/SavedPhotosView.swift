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
    /// 引き当て先（公開一覧＋自分の写真・`PhotoPools`）
    @State private var feed: [Photo] = []
    @State private var mine: [Photo] = []
    /// 画面に出す分。**戻ってきたときに絞り直す**（`FavoritesView` と同じ理由——
    /// 見ている詳細でしおりを外した瞬間に元の行が消えると、詳細が閉じる）
    @State private var photos: [Photo] = []
    /// 絞ったときの ID の数（「0件」と「出せる写真が無い」を分ける）
    @State private var idCount = 0
    /// 引き当て先を一度でも読み終えたか（「まだ」と「0件」を混ぜない）
    @State private var loaded = false
    /// 最後の読み込みで引き当て先が取れなかったか（「読み込めませんでした」はこの回だけ）
    @State private var failed = false

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                switch LikedPhotos.emptyState(idCount: idCount, loaded: loaded, failed: failed) {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                case .none:
                    ErrorBanner(message: Self.emptyMessage)
                case .nothingShown:
                    ErrorBanner(message: LikedPhotos.nothingShownMessage)
                case .unresolved:
                    ErrorBanner(message: Self.unresolvedMessage) {
                        Task { await load(force: true) }
                    }
                }
            } else {
                // 公開一覧から引き当てた写真だけ個別ページが在る（`LikedPhotos.fromPublicFeed`）
                let isPublic = LikedPhotos.fromPublicFeed(hidden.visible(feed))
                PhotoGrid(photos: photos) { photo in
                    PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: photos)
                }
            }
        }
        .webScreen()
        .navigationTitle(ProfileTab.favorites.label)
        .task(id: auth.state) { await load() }
        .refreshable { await load(force: true) }
        .onAppear { refilter() }
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
        photos = LikedPhotos.resolve(ids, in: [hidden.visible(feed), mine])
    }

    private func load(force: Bool = false) async {
        // ログインの確認中は待つ（決まったら `.task(id:)` が読み直す）
        guard !auth.isResolving else { return }
        let signedIn = auth.userId != nil
        let pools = await PhotoPools.load(environment, signedIn: signedIn, force: force)
        // 取り消された回（画面を離れた・読み直しに追い越された）は何も書かない
        guard !Task.isCancelled else { return }
        failed = pools.feed == nil || (signedIn && pools.mine == nil)
        feed = pools.feed ?? feed
        // ログアウトしたら前の人の写真を残さない
        mine = signedIn ? (pools.mine ?? mine) : []
        loaded = true
        refilter()
    }
}
