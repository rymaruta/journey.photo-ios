import Foundation

/// 大きく見る画面（`PhotoViewerView`）の下のハートに、何を出すか。
///
/// 詳細画面の1枚（`currentId`）は詳細の画面が持つ値（`PhotoDetailViewModel.liked`）、
/// 隣の写真は端末の控え（`FavoritesStore`・ホームのハートと同じ出どころ）で答える。
///
/// 🔴 **詳細の1枚だけ、答えが来るまで白いままだった。** 隣の写真は先に控えを灯すが、
/// 詳細の1枚は画面の値がサーバーの答えでしか替わらない。全画面でダブルタップすると
/// 中央のハートは弾けるのに、下のハートは答えまで白のまま（圏外なら白のまま失敗）。
/// だから**送っている間の向き（`pending`）を先に出す**——届かなければ `pending` を
/// 外すだけで、押す前の値に戻る
enum ViewerLike {

    /// - Parameters:
    ///   - pending: 送っている間の向き（写真 id → 付ける／外す）。答えが来たら外す
    ///   - currentLiked: 詳細の1枚の、画面が持つ値
    ///   - stored: 端末の控えの値（隣の写真）
    static func isLiked(_ photoId: String, currentId: String, currentLiked: Bool,
                        pending: [String: Bool], stored: Bool) -> Bool {
        if let sending = pending[photoId] { return sending }
        return photoId == currentId ? currentLiked : stored
    }

    /// 届かなかったときに、全画面の中に出す一言。**裏の詳細画面の赤字は見えない**
    static func failureNotice(_ error: Error?) -> String {
        (error as? LocalizedError)?.errorDescription ?? L("いいねできませんでした", "Couldn't like the photo")
    }
}
