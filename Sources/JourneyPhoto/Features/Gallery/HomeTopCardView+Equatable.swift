import SwiftUI

/// ホームの上の札を、**ホーム（`GalleryView`）が描き直されただけでは描き直さない**（2026-11-28 判断・札 #594 の2回目）。
///
/// **数（Mac run 1870・`testUsageSurveyProbe`）**: 写真の詳細を開いて戻る 3 回の段で、ホームの body（`body.home`）が 18 回、
/// そのたびに上の札の body（`home.topCard.body`）も 18 回評価し直されていた。理由はすべて `chg.HomeTopCardView.@self`
/// （親から渡された値が違う）で、引き金はホームの `_model` の変化（12 回）など、札に渡す値を変えないものだった。
/// 札に渡す写真の並びは、ホームが毎回 `filter`・`dropped.visible` で作り直す新しい配列なので、SwiftUI の比べ方では
/// 中身が同じでも「違う」になる。札の body は並びの計算の控え（`HomeTopCardMemo`）の鍵作りなどを毎回する。
///
/// 比べるのは、描く中身を変える値（`HomeTopCardViewInputs`）だけにする。`seasonShelf`（`@Binding`）は比べない——
/// 札はこの口に**書くだけ**で読まず、書き先はいつもホームの同じ `@State`。
/// 札自身の状態（`@State`・`@EnvironmentObject`・`@ObservedObject`）が変わったときは、今までどおり描き直す
extension HomeTopCardView: Equatable {
    nonisolated static func == (lhs: HomeTopCardView, rhs: HomeTopCardView) -> Bool {
        let same = lhs.drawnInputs == rhs.drawnInputs
        // 違ったら、どの値が違ったかを数える（UI テストのときだけ・`PerfChangeLog.noteDifferences`）
        if !same { PerfChangeLog.noteDifferences("HomeTopCardView", lhs.drawnInputs, rhs.drawnInputs) }
        return same
    }

    /// 親から渡される値のうち、描く中身を変えるもの
    nonisolated var drawnInputs: HomeTopCardViewInputs {
        HomeTopCardViewInputs(themePhotos: themePhotos, myPhotos: myPhotos, myPhotosKnown: myPhotosKnown,
                              reloadToken: reloadToken, friendPhotos: friendPhotos, followingIds: followingIds,
                              scrolledAway: scrolledAway)
    }
}

/// 上の札が親から受け取る値のうち、描く中身を変えるもの（`HomeTopCardView` の `==` が比べる・書くだけの口は入れない）
struct HomeTopCardViewInputs: Equatable {
    let themePhotos: [Photo]
    let myPhotos: [Photo]
    let myPhotosKnown: Bool
    let reloadToken: Int
    let friendPhotos: [Photo]
    let followingIds: Set<String>
    let scrolledAway: Bool
}
