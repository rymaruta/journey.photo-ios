import Foundation

/// 保存した写真（`SavedPhotosView`・マイページの「お気に入り」タブ）と
/// いいねした写真（`FavoritesView`）を、ID から写真に引き当てる決まり。
///
/// いいねした写真の ID は `FavoritesStore.listedIds(server:)`——サーバーの一覧
/// （`GET /user/likes`）と端末の控えの和から、**この起動中にこの端末で外した
/// もの**を引く。控えを入れ替えるのは起動時の `syncLikes` だけ（画面を開くたびに
/// 入れ替えると、強い整合でない古い一覧で外したいいねが控えに戻る）。
/// 取れなかった回は控えのまま出す（圏外でも一覧は出る）。
///
/// **「まだ」「引き当てられなかった」「0件」を混ぜない**（`emptyState`）。
enum LikedPhotos {

    /// 出す写真が0枚のときに、何を言うか。
    enum EmptyState: Equatable {
        /// 引き当て先をまだ読んでいる。「ありません」と言い切らない
        case loading
        /// 本当に0件（ID が1つも無い）
        case none
        /// ID はあるのに1枚も引き当てられなかった（読み込みの失敗・
        /// 消された写真・非公開に戻された写真）。「まだありません」と言うと嘘になる
        case unresolved
    }

    /// - Parameters:
    ///   - idCount: 引き当てようとした ID の数。**非表示（ブロック・通報）で
    ///     落ちたぶんは数えない**（`countExcludingHidden`）——数えると、全部が
    ///     非表示の人に「読み込めませんでした」と再試行が出続ける
    ///   - loaded: 引き当て先（公開一覧・自分の写真）を読み終えたか
    static func emptyState(idCount: Int, loaded: Bool) -> EmptyState {
        guard loaded else { return .loading }
        return idCount == 0 ? .none : .unresolved
    }

    /// ID の数から、**非表示で落ちただけの ID** を引いた数（`emptyState` に渡す）。
    ///
    /// 「引き当て先に無い」（読み込みの失敗・消された写真）と「あるが非表示で
    /// 落ちた」を分ける。後者は読み直しても出ないので、「読み込めませんでした」
    /// と言わない。
    /// - Parameters:
    ///   - pools: 絞る前の引き当て先
    ///   - visiblePools: 非表示を落とした後の引き当て先（`pools` と同じ並び）
    static func countExcludingHidden(_ ids: Set<String>, pools: [[Photo]], visiblePools: [[Photo]]) -> Int {
        let found = Set(resolve(ids, in: pools).map(\.id))
        let shown = Set(resolve(ids, in: visiblePools).map(\.id))
        return ids.count - found.subtracting(shown).count
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
}
