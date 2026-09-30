import Foundation

/// 旅行プランの1日を地図で見る（2026-09-30・owner の判断「次」の段「プランを地図で見る・順に経路」）。
///
/// その日の項目を**日程の順のまま**番号を振って地図に置き、1か所ずつ「前の場所からの経路」を
/// Apple のマップで開く（iOS はアプリから複数地点の経路を一度に渡す口を持たない）。
///
/// **番号は日程の順番**（座標の無い場所も数える）——地図の番号と日程の行の番号を揃える。
/// 座標の無い場所はピンを置かず、経路の起点にもしない（前の場所は「座標のある前の場所」）。
/// 距離・時間は出さない（計算していない・`TripPlanText` の約束）。
enum TripDayMap {

    struct Stop: Identifiable, Equatable {
        /// 日程の中の順番（1から）
        let number: Int
        let name: String
        /// 約1kmに丸めた公開の座標。無ければ地図に置かない
        let coords: Photo.Coords?
        /// 経路の起点（座標のある前の場所）。1か所目・前に座標のある場所が無ければ nil（今いる場所から）
        let from: Photo.Coords?
        let fromName: String?

        var id: Int { number }
    }

    static func stops(of day: TripDay, index: [OfficialSpot], places: [DerivedSpot.Place]) -> [Stop] {
        var previous: (coords: Photo.Coords, name: String)?
        return day.items.enumerated().map { offset, item in
            let name = TripPlanText.label(for: item, index: index, places: places)
            let coords: Photo.Coords?
            switch item {
            case .spot(let spotId, _):
                coords = index.first { $0.spotId == spotId }?.coords
            case .location(let slug, _):
                coords = places.first { $0.slug == slug }?.coords
            }
            let stop = Stop(number: offset + 1, name: name, coords: coords,
                            from: previous?.coords, fromName: previous?.name)
            if let coords { previous = (coords, name) }
            return stop
        }
    }

    /// 地図に置ける場所があるか（無ければ「地図で見る」を出さない）
    static func hasPins(_ stops: [Stop]) -> Bool {
        stops.contains { $0.coords != nil }
    }
}
