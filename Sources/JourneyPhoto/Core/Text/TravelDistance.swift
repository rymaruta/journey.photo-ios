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
    /// **座標と日時の両方を持つ写真だけ**を古い順につなぐ。並びは
    /// **Web の `compareOldest`（`lib/utils/photoOrder.ts`）と同じ**
    /// （`webOldestFirst`）——端末の時刻帯は使わない。旅の一冊の並び
    /// （`TripBook.inOrder`・端末の時刻帯の暦日）で並べると、同じ写真でも
    /// 見ている端末の時刻帯で距離が変わり、Web のプロフィールとも食い違う
    static func total(of photos: [Photo]) -> Double {
        connect(webOldestFirst(photos.filter { TripBook.day(of: $0, in: utc) != nil }))
    }

    /// 並べた順に座標をつないだ合計（座標の無い写真は飛ばす）
    static func connect(_ photos: [Photo]) -> Double {
        let points = photos.compactMap(\.coords)
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += kilometers(from: points[index - 1], to: points[index])
        }
        return total
    }

    /// Web の `compareOldest` と同じ古い順。
    ///
    /// - キーは `date`（撮影日）→ 空なら `createdAt`。末尾のゾーン指定子
    ///   （`Z` / `+09:00`）を落とした**文字列のまま**比べる
    ///   （`YYYY-MM-DD[THH:MM:SS]` は辞書順がそのまま時系列順）。だから
    ///   日付だけの撮影日 `2026-05-02` は、同じ日の投稿日時
    ///   `2026-05-02T03:00:00Z` より**先**に来る
    /// - 同じキーは投稿日時の古い順 → id の昇順
    static func webOldestFirst(_ photos: [Photo]) -> [Photo] {
        photos.sorted { lhs, rhs in
            let byKey = compare(timeKey(lhs), timeKey(rhs))
            if byKey != 0 { return byKey < 0 }
            let byCreated = compare(stripZone(lhs.createdAt ?? ""), stripZone(rhs.createdAt ?? ""))
            if byCreated != 0 { return byCreated < 0 }
            return compare(lhs.id, rhs.id) < 0
        }
    }

    /// Web の `photoTimeKey`（`date || createdAt`。空文字は無いものとして扱う）
    private static func timeKey(_ photo: Photo) -> String {
        if let date = photo.date, !date.isEmpty { return stripZone(date) }
        return stripZone(photo.createdAt ?? "")
    }

    /// Web の `stripZone`。**全体の形で見て**、日付・時刻のあとのゾーン指定子だけ落とす
    private static func stripZone(_ value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        guard let match = zonePattern.firstMatch(in: value, range: range),
              let kept = Range(match.range(at: 1), in: value) else { return value }
        return String(value[kept])
    }

    private static let zonePattern = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?)?)(?:Z|[+-]\d{2}:?\d{2})?$"#,
        options: [.caseInsensitive])

    /// JS の文字列比較（UTF-16 の符号単位の順）。Swift の `<` は正規化を挟むので使わない
    private static func compare(_ lhs: String, _ rhs: String) -> Int {
        let l = Array(lhs.utf16), r = Array(rhs.utf16)
        if l == r { return 0 }
        return l.lexicographicallyPrecedes(r) ? -1 : 1
    }

    private static let utc = TimeZone(identifier: "UTC")!

    /// 画面に出す文字（3桁区切り）。
    static func formatted(_ kilometers: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: kilometers)) ?? "0"
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
