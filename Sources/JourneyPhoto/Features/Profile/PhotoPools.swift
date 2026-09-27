import Foundation

/// 保存した写真・いいねした写真を引き当てる先（`LikedPhotos.resolve`）。
/// **公開一覧と自分の写真**。
///
/// 3つの画面（`SavedPhotosView`・`FavoritesView`・マイページの「お気に入り」
/// タブ）で先が食い違っていた（2026-09-26 のレビュー）——メニューから開くと
/// 公開一覧だけ、タブからだと自分の写真まで、で同じ保存の中身が違って見えた。
/// マイページは自分の写真を `MyPageViewModel.photos`（同じ `myPhotos()`）で
/// 既に持っているので、公開一覧だけをここの外で読む。
@MainActor
enum PhotoPools {

    struct Loaded {
        /// 公開一覧。取れなければ nil
        var feed: [Photo]?
        /// 自分の写真（非公開も含む）。未ログイン・取れなければ nil
        var mine: [Photo]?
    }

    /// 自分の写真は**鍵が要る**ので、ログイン中だけ聞く。
    static func load(_ environment: AppEnvironment, signedIn: Bool, force: Bool = false) async -> Loaded {
        async let feedTask = environment.gallery.fetchPhotos(force: force)
        var mine: [Photo]?
        if signedIn {
            mine = try? await environment.photos.myPhotos()
        }
        let feed = try? await feedTask
        return Loaded(feed: feed, mine: mine)
    }
}
