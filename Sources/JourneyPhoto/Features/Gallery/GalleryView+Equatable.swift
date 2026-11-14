import SwiftUI

/// ホームを、**親（`RootView`）が描き直されただけでは描き直さない**（2026-11-14 判断・札 #594「アプリ全体を軽くする」）。
///
/// **数（Mac run 1238・`testUsageSurveyProbe`・`_printChanges`）**: ホームにいない段でも、`RootView` の状態
/// （下のタブ `_selection`・受信箱 `_messages`・`_tabRouter`・`_scenePhase` など）が変わるたびに
/// `chg.GalleryView.@self`（親から渡された値が違う）が同じ回数だけ起き（地図 5・DM 4・投稿の札 4・投稿の画面 1）、
/// そこからホームの札（`HomeTopCardView.@self`）・格子（`HomeMosaic.@self`）・マス（`HomeFeedTile.@self`
/// 地図 83・DM 135・投稿の札 60 回）まで描き直していた。
/// 下のタブだけが変わった回（`GalleryView` には渡していない値）にも `@self` が起きていたので、引き金は
/// 毎回新しく作られる `onOpenNotifications`（閉じた処理は比べられず、いつも「違う」になる）。
///
/// 比べるのは、描く中身を変える値（`GalleryViewInputs`: 未読の数・受信箱の未読）だけにする。`onOpenNotifications` は
/// 比べない——中身は毎回同じ `RootView.openNotificationsFromBell()` で、前の値を使っても同じ状態（`@State` の置き場）を開く。
/// ホーム自身の状態（`@State`・`@StateObject`・`@EnvironmentObject`）の変化では、今までどおり描き直す
extension GalleryView: Equatable {
    nonisolated static func == (lhs: GalleryView, rhs: GalleryView) -> Bool {
        lhs.drawnInputs == rhs.drawnInputs
    }

    /// 親から渡される値のうち、描く中身を変えるもの
    nonisolated var drawnInputs: GalleryViewInputs {
        GalleryViewInputs(unread: unread, messagesUnread: messagesUnread)
    }
}

/// ホームが親から受け取る値のうち、描く中身を変えるもの（`GalleryView` の `==` が比べる・閉じた処理は入れない）
struct GalleryViewInputs: Equatable {
    let unread: Int
    let messagesUnread: Bool
}
