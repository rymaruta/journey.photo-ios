import SwiftUI

/// 探すの「人気の撮影地」の札から開く画面（2枚以上ある地点はスポットの画面、1枚だけなら集約）。
///
/// 2026-11-28 判断（札 #594 の2回目）: 前は札の `NavigationLink { … }` の中で `DerivedSpot.openable` を呼んでいた。
/// `NavigationLink` は行き先を探すの body のたびに作るので、押していないのに、札の数だけ一覧の全部の写真をなめていた
/// （Mac run 1804 の止まりの積みで `SearchView.spotLink` の中の `DerivedSpot.openable` が見えた）。
/// ここでは行き先に撮影地の名前と写真だけを持たせ、**計算は開いた画面の body（押したとき・元の写真が変わったとき）だけ**にする
struct PopularSpotDestination: View {
    /// 札の撮影地（`DiscoverySections.Spot.id`＝撮影地の文字）
    let label: String
    /// 突き合わせる写真（探すの一覧そのまま）
    let photos: [Photo]

    /// 開く先（画面を持たない計算）
    enum Target: Equatable {
        /// スポットの画面（2枚以上・`DerivedSpot.openable`）
        case spot(DerivedSpot.Place)
        /// 撮影地の集約（1枚だけの地点）
        case tag(String)
    }

    nonisolated static func target(_ label: String, in photos: [Photo]) -> Target {
        DerivedSpot.openable(label, in: photos).map(Target.spot) ?? .tag(label)
    }

    var body: some View {
        switch Self.target(label, in: photos) {
        case .spot(let place):
            SpotDetailView(spot: place, photos: photos)
        case .tag(let label):
            TagPhotosView(kind: .location(label))
        }
    }
}
