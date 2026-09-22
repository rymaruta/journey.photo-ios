import Foundation

/// 「現在地・周辺の写真」（モック3-7）。
///
/// **測るのは、いま手元にある座標だけ。** 通信しない。
///
/// ⚠️ **座標は保存時に約1km（小数第2位）へ丸めてある**
/// （`api-user/src/sanitize.ts` の `sanitizeCoords`）。だから
/// 距離も約1kmの粗さしか無い——**「500m以内」とは言えない**。
/// モックの「500m以内・8件」をそのまま出すと、丸めで消えた精度を
/// 持っているふりになる。出すのは**「約Nkm以内」**と、数えた件数。
enum NearbyPhotos {

    /// 選べる半径（km）。**1km 未満を置かない**——丸めより細かい線は引けない
    static let radiusChoices: [Double] = [5, 10, 50]
    static let defaultRadius: Double = 5

    /// 近い順。**座標の無い写真は入らない**（距離を測りようが無い）
    static func photos(_ photos: [Photo], near center: Photo.Coords,
                       withinKm radius: Double) -> [(photo: Photo, km: Double)] {
        photos.compactMap { photo -> (Photo, Double)? in
            guard let coords = photo.coords else { return nil }
            let km = TravelDistance.kilometers(from: center, to: coords)
            guard km <= radius else { return nil }
            return (photo, km)
        }
        .sorted { $0.1 < $1.1 }
        .map { (photo: $0.0, km: $0.1) }
    }

    /// 距離の言い方。**必ず「約」を付ける**（丸めた座標から出した値なので）。
    ///
    /// 1km 未満は「1km以内」——「0.3km」と書くと、持っていない精度を
    /// 言うことになる。
    static func label(km: Double) -> String {
        if km < 1 { return L("1km以内", "within 1 km") }
        if km < 10 { return L("約\(String(format: "%.1f", km))km", "about \(String(format: "%.1f", km)) km") }
        return L("約\(Int(km.rounded()))km", "about \(Int(km.rounded())) km")
    }

    /// 見出し。**数えた件数だけ**を出す
    static func heading(radiusKm: Double, count: Int) -> String {
        let r = radiusKm < 10 ? String(format: "%.0f", radiusKm) : String(Int(radiusKm))
        return L("半径約\(r)kmの写真 \(count)枚", "\(count) photos within about \(r) km")
    }
}
