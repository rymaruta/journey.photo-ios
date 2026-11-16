import SwiftUI

/// マイページを、**親（`RootView`）が描き直されただけでは描き直さない**（2026-11-16・使い勝手の見直し A3 の確かめ役の指摘）。
///
/// A3 で表紙の右上に吹き出しとベルを置き、`RootView` から未読の値とベルを押したときの処理（`onOpenNotifications`）を
/// 渡すようにした。閉じた処理は比べられず、親が描き直すたびに「違う」になる（ホームの `GalleryView+Equatable`・札 #594 と同じ形）。
///
/// **数（Mac run 1421・`testUsageSurveyProbe`・`_printChanges`）**: マイページにいない段でも `chg.MyPageView.@self`
/// （親から渡された値が違う）が 地図 5・DM 4・投稿の札 4・投稿の画面 1 回起き、`body.myPage` も 地図 5・DM 5・投稿の札 4・
/// 投稿の画面 1 回（合わせて 15 回）評価し直していた。`body.root` の回数とそろう＝親の描き直しにそのままついて行っていた。
///
/// 比べるのは描く中身を変える値（`MyPageViewInputs`: 未読の数・受信箱の未読）だけ。`onOpenNotifications` は比べない——
/// 中身は毎回同じ `RootView.openNotificationsFromBell()` で、前の値を使っても同じ状態を開く。
/// マイページ自身の状態（`@State`・`@StateObject`・`@EnvironmentObject`）の変化では、今までどおり描き直す
extension MyPageView: Equatable {
    nonisolated static func == (lhs: MyPageView, rhs: MyPageView) -> Bool {
        lhs.drawnInputs == rhs.drawnInputs
    }

    /// 親から渡される値のうち、描く中身を変えるもの
    nonisolated var drawnInputs: MyPageViewInputs {
        MyPageViewInputs(unread: unread, messagesUnread: messagesUnread)
    }
}

/// マイページが親から受け取る値のうち、描く中身を変えるもの（`MyPageView` の `==` が比べる・閉じた処理は入れない）
struct MyPageViewInputs: Equatable {
    let unread: Int
    let messagesUnread: Bool
}
