import Foundation

/// プロフィールの「旅した距離」。
///
/// **実際に移動した距離ではない**（指示書 8-3）。写真に残っている座標を
/// **古い順に直線でつないだ合計**で、Web 側（`app/users/UserProfileClient.tsx`
/// の `footprint` と `lib/utils/journey.ts` の `haversineKm`）と同じ計算。
///
/// ずれる理由をはっきりさせておく:
///
/// - **道のりではなく直線。** 東京→大阪は新幹線の線路ではなく、地球の
///   表面をまっすぐ結んだ長さになる
/// - **座標のある写真しか数えない。** 撮っていない区間は飛ぶ
/// - **座標は約1kmに丸めてある**（`coords`）。細かい移動は消える
/// - **日時の読めない写真は入れない。** つなぐ順が決まらない写真を
///   「いちばん古い場所」として数えると、そこから1脚ぶん距離が増える
///   （Web 側が踏んでいる穴）
///
/// だから画面では「**写真をつないだ距離**」と呼び、数字の隣に出典を出す。
/// 「旅した距離 74,164km」とだけ書くと、**実際に歩いた／飛んだ距離だと
/// 読まれる**。
enum TravelDistance {

    /// 地球の半径（km）
    private static let earthRadiusKm = 6371.0

    /// 2点間の大円距離（km）。Web の `haversineKm` と同じ式。
    static func kilometers(from: Photo.Coords, to: Photo.Coords) -> Double {
        let dLat = radians(to.lat - from.lat)
        let dLng = radians(to.lng - from.lng)
        let h = pow(sin(dLat / 2), 2)
            + cos(radians(from.lat)) * cos(radians(to.lat)) * pow(sin(dLng / 2), 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// 写真をつないだ合計（km）。
    ///
    /// **座標と日時の両方を持つ写真だけ**を古い順につなぐ。
    static func total(of photos: [Photo]) -> Double {
        let points = photos
            .compactMap { photo -> (Date, Photo.Coords)? in
                guard let coords = photo.coords, let day = TripBook.day(of: photo) else { return nil }
                return (day, coords)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += kilometers(from: points[index - 1], to: points[index])
        }
        return total
    }

    /// 画面に出す文字（3桁区切り）。
    static func formatted(_ kilometers: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: kilometers)) ?? "0"
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
