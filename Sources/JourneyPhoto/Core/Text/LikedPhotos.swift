import Foundation

/// 保存した写真（`SavedPhotosView`・マイページの「お気に入り」タブ）と
/// いいねした写真（`FavoritesView`）を、ID から写真に引き当てる決まり。
///
/// いいねした写真の ID は `FavoritesStore.listedIds(server:)`——サーバーの一覧
/// （`GET /user/likes`）と端末の控えの和から、**この起動中にこの端末で外した
/// もの**を引く。控えを入れ替えるのは起動時の `syncLikes` だけ（画面を開くたびに
/// 入れ替えると、強い整合でない古い一覧で外したいいねが控えに戻る）。
/// 取れなかった回は、同じ人なら前に取れた一覧を残し、無ければ控えのまま出す
/// （圏外でも一覧は出る・`LikedPhotosScreen`）。
///
/// **「まだ」「引き当てられなかった」「0件」を混ぜない**（`emptyState`）。
enum LikedPhotos {

    /// 出す写真が0枚のときに、何を言うか。
    enum EmptyState: Equatable {
        /// 引き当て先をまだ読んでいる。「ありません」と言い切らない
        case loading
        /// 本当に0件（ID が1つも無い）
        case none
        /// ID はあり、引き当て先も読めたが、出せる写真が1枚も無い（消された・
        /// 非公開に戻された・ブロックや通報で非表示）。読み直しても出ないので
        /// エラーにせず、再試行も出さない（`nothingShownMessage`）
        case nothingShown
        /// ID はあるのに、**引き当て先の読み込みが失敗した**ので出せなかった。
        /// 「まだありません」と言うと、保存やいいねが消えたように読める
        case unresolved
    }

    /// - Parameters:
    ///   - idCount: 引き当てようとした ID の数
    ///   - loaded: 引き当て先（公開一覧・自分の写真）を読み終えたか
    ///   - failed: 最後の読み込みで引き当て先が取れなかったか（`PhotoPools` の
    ///     `feed` が nil など）。**「読み込めませんでした」はこの回だけ。**
    ///     公開一覧はブロック・通報を落として返る（`PublicGalleryService`）ので、
    ///     「引き当て先に無い」を失敗と数えると、全部が非表示の人に再試行が出続ける
    static func emptyState(idCount: Int, loaded: Bool, failed: Bool) -> EmptyState {
        guard loaded else { return .loading }
        if idCount == 0 { return .none }
        return failed ? .unresolved : .nothingShown
    }

    /// `.nothingShown` の文（保存した写真・いいねした写真・マイページのタブで共通）。
    /// 保存やいいねが消えたとは言わない——ID は残っていて、出せる写真が無いだけ
    static var nothingShownMessage: String {
        L("表示できる写真はありません", "No photos to show")
    }

    /// ID を写真に引き当てる（新しい順）。
    ///
    /// **引き当てられない ID は落とす。** 非公開に戻された写真・消された
    /// 写真の ID が残っていても、出す中身が無い。数だけ合わせて空の枠を
    /// 置くより、並ばない方が正直。
    ///
    /// - Parameter pools: 探す先。**公開一覧と自分の写真の両方**を渡す
    ///   （`PhotoPools`）——公開一覧だけだと自分の非公開の写真が出ず、
    ///   自分の写真だけだと他人の写真が出ない（アプリは後者で、他人の写真への
    ///   いいねが**一度も出なかった**）。3つの画面で同じ先を見ること
    static func resolve(_ ids: Set<String>, in pools: [[Photo]]) -> [Photo] {
        var seen = Set<String>()
        var found: [Photo] = []
        for pool in pools {
            for photo in pool where ids.contains(photo.id) && seen.insert(photo.id).inserted {
                found.append(photo)
            }
        }
        return GallerySort.new.apply(found)
    }

    /// 引き当てた写真を開くときの `PhotoDetailView.fromPublicFeed`（`PhotoLink`）。
    ///
    /// **公開一覧から引き当てた写真だけが真。** 自分の写真の束だけに在る写真
    /// （投稿した直後・非公開）は、個別ページ `/photo/<id>` がまだ建っていない
    /// ——既定の `true` のまま開くと、共有のリンクが建て直すまで 404 を指す。
    ///
    /// - Parameter feed: `resolve` に**最初の束として渡した**公開一覧（絞ったあとの
    ///   もの）。`resolve` は先の束で当たった写しを使うので、ここに在る id は
    ///   公開一覧から来た写真
    static func fromPublicFeed(_ feed: [Photo]) -> (Photo) -> Bool {
        let ids = Set(feed.map(\.id))
        return { ids.contains($0.id) }
    }
}
