import Foundation

/// 地図で押した地点を、名前の検索結果から拾い直すときの選び方。
///
/// Apple の地点は `MKMapItemRequest` で詳細（住所・電話・Web・Apple の
/// 詳細カード）を引くが、**引けない地点がある**。引けないと札のボタンが
/// ずっと押せないままで、owner には「押しても中身が見えない」と映った
/// （2026-09-25）。名前で検索し直して、**押した場所のすぐ近くの結果だけ**
/// を同じ地点とみなす——同じ名前の別の店舗を拾わないため。
enum PlaceLookup {

    /// 同じ地点とみなす距離（km）。大きな施設でも入口と中心がこの程度はずれる
    static let sameSpotKm: Double = 0.3

    /// 候補のうち `center` にいちばん近く、`withinKm` 以内のものの位置。無ければ nil
    static func nearestIndex(of candidates: [Photo.Coords], to center: Photo.Coords,
                             withinKm: Double = sameSpotKm) -> Int? {
        var best: (index: Int, km: Double)?
        for (index, coords) in candidates.enumerated() {
            let km = TravelDistance.kilometers(from: center, to: coords)
            guard km <= withinKm else { continue }
            if best == nil || km < best!.km { best = (index, km) }
        }
        return best?.index
    }
}
