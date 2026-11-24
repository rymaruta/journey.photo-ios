import SwiftUI

/// 地図を、**親（`RootView`）が描き直されただけでは描き直さない**（2026-11-24 判断・札 #594・owner「アプリ全体的に挙動重い」1.2.1）。
///
/// ホーム（`GalleryView+Equatable`・2026-11-14）と同じ理由: `RootView` の状態が変わるたびに、毎回新しく作られる
/// `onOpenNotifications`・`onPost`（閉じた処理は比べられず、いつも「違う」）のせいで `PhotoMapView` の body が評価し直されていた。
/// 地図は一度開くと下のタブが持ち続けるので、**ほかのタブにいる間も**、親が動くたびに地図の body（ピンの束・下の一覧）が走る。
///
/// 比べるのは描く中身を変える値（未読の数・受信箱の未読）だけ。`onOpenNotifications`・`onPost` は比べない——中身は毎回同じ
/// `RootView.openNotificationsFromBell()`・`RootView.openCreateFlow(.post)` で、前の値を使っても同じ状態（`@State` の置き場）を動かす。
/// 積み重ねを根まで戻す `.id(mapStackId)` は外側に付いているので、今までどおり作り直す。
/// 地図自身の状態（`@State`・`@ObservedObject`・`@EnvironmentObject`）の変化では、今までどおり描き直す
extension PhotoMapView: Equatable {
    nonisolated static func == (lhs: PhotoMapView, rhs: PhotoMapView) -> Bool {
        lhs.drawnInputs == rhs.drawnInputs
    }

    /// 親から渡される値のうち、描く中身を変えるもの（ホームと同じ形）
    nonisolated var drawnInputs: GalleryViewInputs {
        GalleryViewInputs(unread: unread, messagesUnread: messagesUnread)
    }
}
