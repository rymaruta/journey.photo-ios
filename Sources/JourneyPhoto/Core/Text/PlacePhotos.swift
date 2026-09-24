import Foundation

/// 地図で選んだ地点（Apple の地図が描く POI）の写真。
///
/// **通信しない。** 地図がすでに持っている写真（`PhotoMapViewModel.photos`）
/// から拾う。拾い方は2つで、重ならないように合わせる:
///
///   1. 撮影地の文字列にその地点の名前が入っている写真（`LocationMatch`）
///   2. 座標がその地点から `radiusKm` 以内の写真
///
/// ⚠️ 座標は保存時に**約1km（小数第2位）へ丸めてある**
/// （`api-user/src/sanitize.ts` の `sanitizeCoords`）。地点で撮った写真の
/// 座標は、実際の場所から最大でおよそ0.8km ずれた格子点に居る。
/// だから範囲は 1km——これより狭いと、その場所で撮った写真が落ちる。
/// 同じ理由で、画面では「この場所で」ではなく**「この付近で」**と書く。
enum PlacePhotos {

    /// 座標で拾う範囲（km）。丸めの粗さ（約1km）より狭くしない
    static let radiusKm: Double = 1

    /// 名前の当たった写真（新しい順）→ 座標の近い写真（近い順）。同じ写真は1回だけ
    static func photos(_ photos: [Photo], name: String?, at center: Photo.Coords) -> [Photo] {
        let named = photos
            .filter { LocationMatch.photoIsIn($0.location, name) }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        let namedIds = Set(named.map(\.id))
        let near = NearbyPhotos.photos(photos, near: center, withinKm: radiusKm)
            .map(\.photo)
            .filter { !namedIds.contains($0.id) }
        return named + near
    }
}
