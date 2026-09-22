import Foundation

/// 「お気に入り（いいねした写真）」に出すもの。
///
/// **サーバーの一覧と、この端末の控えの和。** Web の `useMyServerLikes` と
/// 同じ約束:
///
/// - サーバー（`GET /user/likes`）は**別の端末で押したぶん**を拾う
/// - 端末（`FavoritesStore`）は**未ログイン中に押したぶん**と、
///   一覧の書き込みが落ちた回を拾う
///
/// **「まだ」「聞けなかった」「0件」を混ぜない。** 取得中に「ありません」と
/// 言い切ると、別の端末で押したぶんが届く前に「無い」と読まれる。
enum LikedPhotos {

    enum Status: Equatable {
        /// ログイン確認中・取得中
        case loading
        /// サーバーにも聞けた
        case ready
        /// 聞けなかった。**端末の控えは出す**（足りていないことだけ伝える）
        case partial
        /// 未ログイン。端末の控えが答え（聞きに行かない）
        case deviceOnly
    }

    /// 出す ID の集合。
    /// - Parameter serverIds: 取れなければ nil（`partial` のとき）
    static func ids(serverIds: [String]?, deviceIds: Set<String>) -> Set<String> {
        deviceIds.union(serverIds ?? [])
    }

    /// ID を写真に引き当てる（新しい順）。
    ///
    /// **引き当てられない ID は落とす。** 非公開に戻された写真・消された
    /// 写真の ID が残っていても、出す中身が無い。数だけ合わせて空の枠を
    /// 置くより、並ばない方が正直。
    ///
    /// - Parameter pools: 探す先。**公開一覧と自分の写真の両方**を渡す
    ///   ——公開一覧だけだと他人の写真しか出ず、自分の写真だけだと
    ///   他人の写真が出ない（アプリは後者で、他人の写真へのいいねが
    ///   **一度も出なかった**）。
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
