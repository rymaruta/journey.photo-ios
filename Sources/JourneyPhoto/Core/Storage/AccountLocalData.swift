import Foundation

/// 退会した人の、この端末に残っている控えを消す。
///
/// 🔴 **退会しても端末に本人の控えが残っていた。** 控えは人ごとの鍵に分けて
/// あるので次の人には見えないが、消えるべきもの（いいね・保存・行きたい場所・
/// ブロック・参加したアルバム・見たストーリー・最近の曲・ストーリーの書きかけ
/// とその画像・登録の確認の控え・通知の設定・ホームの札から開いた一冊の印・電波なしで使える旅）が端末に残り続けていた。
/// 審査 5.1.1(v) の「アカウントの削除」は、端末に残した本人のデータも含む。
///
/// **鍵の形は各控えが持つ**（ここで綴りを写すと、片方だけ変えたときに
/// 消し損ねる）。ここは呼ぶ順番を1か所にまとめるだけ。
@MainActor
enum AccountLocalData {

    /// - Parameters:
    ///   - userId: 退会した人
    ///   - username: Cognito のユーザー名（登録のときの UUID）。登録の確認の
    ///     控え（`jp_verify_<メール>`）を探すのに使う。取れなければ nil
    ///   - defaults: 試験で差し替える
    ///   - draftDirectory: ストーリーの書きかけの画像の置き場（試験で差し替える）
    ///   - offlineTripsRoot: 電波なしで使える旅の置き場（試験で差し替える）
    static func remove(userId: String, username: String?,
                       defaults: UserDefaults = .standard,
                       draftDirectory: URL? = nil,
                       offlineTripsRoot: URL? = nil) {
        guard !userId.isEmpty else { return }
        FavoritesStore(defaults: defaults).removeData(for: userId)
        SavedPhotosStore(defaults: defaults).removeData(for: userId)
        ModerationStore(defaults: defaults).removeData(for: userId)
        WishlistStore(defaults: defaults).removeData(for: userId)
        JoinedAlbumsStore(defaults: defaults).removeData(for: userId)
        SeenStoriesStore(defaults: defaults).removeData(for: userId)
        RecentSongsStore(defaults: defaults).removeData(for: userId)
        StoryDraftStore(defaults: defaults, directory: draftDirectory).removeData(for: userId)
        OpenedTripBooks(defaults: defaults).removeData(for: userId)
        PushCenter.removeLocalData(for: userId, defaults: defaults)
        // 電波なしで使える旅（作例・地図の画像とメモ）
        OfflineTripStore.removeData(for: userId, root: offlineTripsRoot, defaults: defaults)
        // 共有のために書いた旅の一冊の画像（表紙の写真を含む）
        TripBookCard.removeAll()
        if let username, !username.isEmpty {
            PendingVerificationStore(defaults: defaults).forget(username: username)
        }
    }
}
