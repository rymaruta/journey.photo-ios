import Foundation

/// 退会した人の、この端末に残っている控えを消す。
///
/// 🔴 **退会しても端末に本人の控えが残っていた。** 控えは人ごとの鍵に分けて
/// あるので次の人には見えないが、消えるべきもの（いいね・保存・行きたい場所・
/// ブロック・参加したアルバム・見たストーリー・すれちがいの帳・最近の曲・最近の検索・ストーリーと写真の投稿の書きかけ
/// とその画像・登録の確認の控え・通知の設定・投稿の「撮影地の位置を付ける」・ホームの札から開いた一冊の印・電波なしで使える旅）が端末に残り続けていた。
/// 審査 5.1.1(v) の「アカウントの削除」は、端末に残した本人のデータも含む。
///
/// **鍵の形は各控えが持つ**（ここで綴りを写すと、片方だけ変えたときに
/// 消し損ねる）。ここは呼ぶ順番を1か所にまとめるだけ。
@MainActor
enum AccountLocalData {

    /// - Parameters:
    ///   - userId: 退会した人
    ///   - username: Cognito のユーザー名（登録のときの UUID）。登録の確認の
    ///     控え（鍵はメールのハッシュ `jp_pending_<指紋>`。中身のユーザー名で探す）を探すのに使う。取れなければ nil
    ///   - defaults: 試験で差し替える
    ///   - draftDirectory: ストーリー・写真の投稿の書きかけの画像の置き場（試験で差し替える）
    ///   - offlineTripsRoot: 電波なしで使える旅の置き場（試験で差し替える）
    ///   - passRoot: すれちがいの帳の置き場（試験で差し替える）
    ///   - feedbackRoot: 意見箱の送れていない下書きの置き場（試験で差し替える）
    static func remove(userId: String, username: String?,
                       defaults: UserDefaults = .standard,
                       draftDirectory: URL? = nil,
                       offlineTripsRoot: URL? = nil,
                       passRoot: URL? = nil,
                       feedbackRoot: URL? = nil) {
        ALDTimer.mark("remove.enter")
        guard !userId.isEmpty else { return }
        // 🔴 **すれちがいの電波を先に止める**（2026-10-16）。止めないと、消した後も前の乗車券を出し続け、
        // 手元に持っている帳が次の保存で書き戻される
        if PassStore.shared.userId == userId {
            PassStore.shared.use(userId: nil)
            PassCoordinator.shared.refresh()
        }
        ALDTimer.mark("L37 }")
        FavoritesStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L38 FavoritesStore(defaults: defaults).removeData(for: userId)")
        SavedPhotosStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L39 SavedPhotosStore(defaults: defaults).removeData(for: userId)")
        ModerationStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L40 ModerationStore(defaults: defaults).removeData(for: userId)")
        WishlistStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L41 WishlistStore(defaults: defaults).removeData(for: userId)")
        // AI で作った旅行プランの「まだ見ていない」印（札 #621）
        TripAIUnseen.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L43 TripAIUnseen.removeData(for: userId, defaults: defaults)")
        JoinedAlbumsStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L44 JoinedAlbumsStore(defaults: defaults).removeData(for: userId")
        SeenStoriesStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L45 SeenStoriesStore(defaults: defaults).removeData(for: userId)")
        RecentSongsStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L46 RecentSongsStore(defaults: defaults).removeData(for: userId)")
        // 探すの「最近の検索」（2026-11-14）
        RecentSearchesStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L48 RecentSearchesStore(defaults: defaults).removeData(for: user")
        // 投稿の撮影地の候補に出す「最近使った撮影地」（2026-11-16・A11）
        RecentSearchesStore.places(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L50 RecentSearchesStore.places(defaults: defaults).removeData(fo")
        StoryDraftStore(defaults: defaults, directory: draftDirectory).removeData(for: userId)
        ALDTimer.mark("L51 StoryDraftStore(defaults: defaults, directory: draftDirector")
        StoryDraftStore(defaults: defaults, directory: draftDirectory, slot: .auto).removeData(for: userId)
        ALDTimer.mark("L52 StoryDraftStore(defaults: defaults, directory: draftDirector")
        // 下書きを複数持つ形（2026-10-29・#400）: ストーリーと投稿の下書きを全部。**ログアウトでは消さない**
        // （人ごとの鍵で残り、同じ人が入り直すと戻る）——消すのは退会のときだけ
        StoryDraftStore.removeAllEntries(for: userId, defaults: defaults, directory: draftDirectory)
        ALDTimer.mark("L55 StoryDraftStore.removeAllEntries(for: userId, defaults: defa")
        UploadDraftStore(defaults: defaults, directory: draftDirectory).removeAllEntries(for: userId)
        ALDTimer.mark("L56 UploadDraftStore(defaults: defaults, directory: draftDirecto")
        DraftViewPreference(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L57 DraftViewPreference(defaults: defaults).removeData(for: user")
        // 写真の投稿の下書きとその画像（2026-10-11）
        UploadDraftStore(defaults: defaults, directory: draftDirectory).removeData(for: userId)
        ALDTimer.mark("L59 UploadDraftStore(defaults: defaults, directory: draftDirecto")
        // 自動で残した書きかけ・送信の控え（別の枠・2026-10-16）
        UploadDraftStore(defaults: defaults, directory: draftDirectory, slot: .auto).removeData(for: userId)
        ALDTimer.mark("L61 UploadDraftStore(defaults: defaults, directory: draftDirecto")
        // 送信の控え（投稿ごと・`send:<userId>:<ID>`）を全部。画像の頭も
        UploadDraftStore(defaults: defaults, directory: draftDirectory).removeAllJournals(for: userId)
        ALDTimer.mark("L63 UploadDraftStore(defaults: defaults, directory: draftDirecto")
        // 投稿の「撮影地の位置を付ける」の選んだ値（2026-10-18）
        UploadLocationPreference(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L65 UploadLocationPreference(defaults: defaults).removeData(for:")
        // ストーリーの「24時間後も自分用に残す」の選んだ値（2026-11-11）
        StoryArchivePreference(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L67 StoryArchivePreference(defaults: defaults).removeData(for: u")
        OpenedTripBooks(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L68 OpenedTripBooks(defaults: defaults).removeData(for: userId)")
        // ホームの上の札に出さない旅・消すのを待っている旅行プラン（2026-11-12）
        HomeHiddenTrips(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L70 HomeHiddenTrips(defaults: defaults).removeData(for: userId)")
        TripPlanRemovalQueue.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L71 TripPlanRemovalQueue.removeData(for: userId, defaults: defau")
        FollowingSeenStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L72 FollowingSeenStore(defaults: defaults).removeData(for: userI")
        // 行った県マップの記録（県ごとの行った日・外した候補・祝いを見せた周・2026-11-08・札 #503）
        VisitedPrefectureStore(defaults: defaults).removeData(for: userId)
        ALDTimer.mark("L74 VisitedPrefectureStore(defaults: defaults).removeData(for: u")
        PushCenter.removeLocalData(for: userId, defaults: defaults)
        ALDTimer.mark("L75 PushCenter.removeLocalData(for: userId, defaults: defaults)")
        // 電波なしで使える旅（作例・地図の画像とメモ）
        OfflineTripStore.removeData(for: userId, root: offlineTripsRoot, defaults: defaults)
        ALDTimer.mark("L77 OfflineTripStore.removeData(for: userId, root: offlineTripsR")
        // すれちがいの帳と設定（受け取ったカード・乗車券・ひとこと）
        PassStore.removeData(for: userId, root: passRoot, defaults: defaults)
        ALDTimer.mark("L79 PassStore.removeData(for: userId, root: passRoot, defaults: ")
        // 意見箱の送れていない下書き（2026-11-11 札 #546）
        FeedbackOutbox(root: feedbackRoot).removeData(for: userId)
        ALDTimer.mark("L81 FeedbackOutbox(root: feedbackRoot).removeData(for: userId)")
        // 旅のトランク（2026-10-17）: 入口を出すかの覚え・古び方の区切りの知らせを出した印
        TrunkAvailability.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L83 TrunkAvailability.removeData(for: userId, defaults: defaults")
        // 回す箱の正面の絵の端末の置き場（2026-11-11・貼ったラベルの地名が描かれている）
        TrunkSpinDiskCache.removeAll()
        ALDTimer.mark("L85 TrunkSpinDiskCache.removeAll()")
        TrunkTicketSyncRule.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L86 TrunkTicketSyncRule.removeData(for: userId, defaults: defaul")
        // はじめての硬貨をもらった印（2026-10-18）
        TrunkWelcome.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L88 TrunkWelcome.removeData(for: userId, defaults: defaults)")
        // アイコン・カバーのお礼の控えと「この1枚をカバーに」の覚え（#304・2026-10-18）
        ProfileReward.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L90 ProfileReward.removeData(for: userId, defaults: defaults)")
        CoverOfferStore.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L91 CoverOfferStore.removeData(for: userId, defaults: defaults)")
        // 初期ユーザー章の全画面を出した回数・終えた印（人ごと・2026-11-07）
        defaults.removeObject(forKey: FoundingGiftGate.shownKey(userId))
        ALDTimer.mark("L93 defaults.removeObject(forKey: FoundingGiftGate.shownKey(user")
        defaults.removeObject(forKey: FoundingGiftGate.doneKey(userId))
        ALDTimer.mark("L94 defaults.removeObject(forKey: FoundingGiftGate.doneKey(userI")
        defaults.removeObject(forKey: TrunkAgingNotice.key(userId))
        ALDTimer.mark("L95 defaults.removeObject(forKey: TrunkAgingNotice.key(userId))")
        defaults.removeObject(forKey: TrunkWrinkles.key(userId))
        ALDTimer.mark("L96 defaults.removeObject(forKey: TrunkWrinkles.key(userId))")
        // 写真で作るキャンピングカーの飾りと「届いた」を見せた印（2026-10-18）
        CamperStore.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L98 CamperStore.removeData(for: userId, defaults: defaults)")
        // とおまわり号の中の家具の配置（2026-10-19）
        CamperRoomStore.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L100 CamperRoomStore.removeData(for: userId, defaults: defaults)")
        CamperRoomSeenStore.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L101 CamperRoomSeenStore.removeData(for: userId, defaults: defaul")
        // はじめてのいいね・コメントを祝った印（2026-11-08）
        FirstReaction.removeData(for: userId, defaults: defaults)
        ALDTimer.mark("L103 FirstReaction.removeData(for: userId, defaults: defaults)")
        // 共有のために書いた旅の一冊の画像（表紙の写真を含む）
        TripBookCard.removeAll()
        ALDTimer.mark("L105 TripBookCard.removeAll()")
        if let username, !username.isEmpty {
            PendingVerificationStore(defaults: defaults).forget(username: username)
        }
        ALDTimer.mark("L108 }")
    }
}


/// 一時の枝 claude/xcode27-ald-time だけ: 区間ごとの時間を出す（#647・iOS 27.2 で AccountLocalDataTests の最初の1本が 40〜65秒）
enum ALDTimer {
    nonisolated(unsafe) static var last = Date().timeIntervalSinceReferenceDate
    static func reset(_ label: String) {
        last = Date().timeIntervalSinceReferenceDate
        NSLog("ALDTIME reset " + label)
    }
    static func mark(_ label: String) {
        let now = Date().timeIntervalSinceReferenceDate
        NSLog("ALDTIME " + String(format: "%.1fms ", (now - last) * 1000) + label)
        last = now
    }
}
