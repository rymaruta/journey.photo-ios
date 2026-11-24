import SwiftUI

/// 探すを、**親（`RootView`）が描き直されただけでは描き直さない**（2026-11-24 判断・札 #594・owner「アプリ全体的に挙動重い」1.2.1）。
///
/// ホーム（`GalleryView+Equatable`・2026-11-14）と同じ理由: `RootView` の状態（下のタブ・受信箱・`TabRouter`・投稿の係など
/// 20 ほどの見張り）が変わるたびに、毎回新しく作られる `onOpenNotifications`（閉じた処理は比べられず、いつも「違う」）のせいで
/// `SearchView` の body が評価し直されていた。下のタブは一度開いた画面を持ち続けるので、探すを開いたあとは
/// **ホームや地図にいる間も**、親が動くたびに探すの body（撮影スポットの索引の並び・語の当たり）が走る。
///
/// 比べるのは描く中身を変える値（未読の数・受信箱の未読）だけ。`onOpenNotifications` は比べない——中身は毎回同じ
/// `RootView.openNotificationsFromBell()` で、前の値を使っても同じ状態（`@State` の置き場）を開く。
/// 探す自身の状態（`@State`・`@StateObject`・`@ObservedObject`・`@EnvironmentObject`）の変化では、今までどおり描き直す
extension SearchView: Equatable {
    nonisolated static func == (lhs: SearchView, rhs: SearchView) -> Bool {
        lhs.drawnInputs == rhs.drawnInputs
    }

    /// 親から渡される値のうち、描く中身を変えるもの（ホームと同じ形）
    nonisolated var drawnInputs: GalleryViewInputs {
        GalleryViewInputs(unread: unread, messagesUnread: messagesUnread)
    }
}
