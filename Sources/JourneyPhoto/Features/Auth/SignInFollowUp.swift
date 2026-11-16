import Foundation

/// ログインできたら、**押した操作を自動で最後まで済ませる**（2026-11-16 判断・使い勝手の見直し A4）。
///
/// 以前は、ログインしていない人がいいね・保存を押すとログインの画面に進めたが、ログインして戻ると
/// **もう一度押し直す**必要があった（いいね 2＋ログイン＋押し直し）。フォローはボタン自体が無かった。
/// いまは押した操作をここに覚えておき、ログインして画面が読み直されたら、その続きを済ませる
/// （いいね・保存・フォロー 1＋ログイン）。
///
/// **付けるだけで、外さない。** ログインした人が前からいいね・保存・フォロー済みなら何もしない
/// ——読み直す前に送ると、入れ替えの操作が外す向きに化ける。そのため、画面が「今の人の状態」を
/// 読み終わるまで待つ（`step`）
enum SignInFollowUp: Equatable {
    case like(photoId: String)
    case save(photoId: String)
    case follow(userId: String)

    /// 続きをどうするか
    enum Step: Equatable {
        /// まだ読み終わっていない（次に読み終わったときに見直す）
        case wait
        /// 済ませる
        case run
        /// 何もせずに忘れる（もう済んでいる・別の写真や人へ移った・自分だった）
        case drop
    }

    /// 写真の詳細で、続きをどうするか。
    ///
    /// - Parameters:
    ///   - me: いまログインしている人（nil ならまだログインしていない）
    ///   - reactionsReadyFor: いいね・保存の状態を**誰の分として**読み終えたか（読み終える前は別の人か nil）
    ///   - isFollowing: 写真の持ち主をフォロー中か（nil はまだ分からない）
    ///   - followLookupFailed: フォローの状態を取れなかった（押した側で取り直してから送る・`toggleFollow`）
    static func step(_ followUp: SignInFollowUp, me: String?, currentPhotoId: String, reactionsReadyFor: String?,
                     liked: Bool, saved: Bool, ownerId: String?, isFollowing: Bool?,
                     followLookupFailed: Bool) -> Step {
        guard let me else { return .wait }
        switch followUp {
        case .like(let photoId):
            guard photoId == currentPhotoId else { return .drop }
            guard reactionsReadyFor == me else { return .wait }
            return liked ? .drop : .run
        case .save(let photoId):
            guard photoId == currentPhotoId else { return .drop }
            guard reactionsReadyFor == me else { return .wait }
            return saved ? .drop : .run
        case .follow(let userId):
            return followStep(userId: userId, me: me, shownUserId: ownerId, isFollowing: isFollowing,
                              lookupFailed: followLookupFailed)
        }
    }

    /// 人のページ・写真の詳細の「フォローする」の続き。
    ///
    /// - Parameter shownUserId: いま出している人（写真の持ち主・人のページの人）
    static func followStep(userId: String, me: String?, shownUserId: String?, isFollowing: Bool?,
                           lookupFailed: Bool) -> Step {
        guard let me else { return .wait }
        // 自分のページだった（ログインしてみたら自分の写真）・別の人へ移った
        guard userId != me, userId == shownUserId else { return .drop }
        if isFollowing == true { return .drop }
        // 取り直している最中は待つ。取れなかった回は押した側で取り直してから送る
        if isFollowing == nil && !lookupFailed { return .wait }
        return .run
    }
}
