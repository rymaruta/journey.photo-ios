import Foundation

/// 撮影地マップの絞り込み（モック3 の検索窓・チップ・「このエリアを検索」）。
///
/// ここが返した写真を `MapPin.group` に通したものが地図のピン。
/// 「リスト」の札（`RegionList`）も同じ当て方（`matches`）で絞るが、
/// 県ごとにまとめるので座標の無い写真も残す。
///
/// **通信しない。** 手元の配列と、既に取ってある台帳だけを見る。
/// 都市名で当たるのは撮影地の文字列に含まれているときだけで、
/// ジオコーディングはしない。
///
/// 画面を持たない層（`MapKit` を読まない）に置いてあるので、Linux の
/// `swift test` で検証できる。
enum MapSearch {

    /// 絞りの条件。**空の条件は「絞らない」**
    struct Filter: Equatable {
        var query: String = ""
        var category: String? = nil
        /// 「このエリアを検索」を押したときの範囲。**押すまで nil**
        /// （地図を動かしただけで絞られると「消えた」に見える）
        var frame: MapFraming.Frame? = nil
    }

    /// 条件に合う写真。**座標の無い写真は最初から入れない**（地図に置けない）。
    /// 「リスト」の札は座標の無い写真も「場所が分からない写真」に出す（`RegionList.filter`）
    ///
    /// ⚠️ **ここで当たるのは撮影地の文字列だけ。** 撮影スポットの台帳は
    /// Web が `content/spots.json`（review 段階の下書き）として持ち、アプリは
    /// `OfficialSpot` として**別に**読む（`OfficialSpotIndex.matches` が名前・
    /// 読み・地域で引き、`OfficialPins` が地図に置く）。写真との紐付けは
    /// `Photo.spotId` だけで、**写真の絞り込みにスポットの名前は効かない**。
    static func photos(_ photos: [Photo], filter: Filter) -> [Photo] {
        let needle = fold(filter.query)
        let categoryKey = filter.category.map { CategoryChoices.key($0) }
        return photos.filter { photo in
            guard let coords = photo.coords else { return false }
            if let categoryKey, CategoryChoices.key(photo.category ?? "") != categoryKey { return false }
            if let frame = filter.frame, !contains(frame, latitude: coords.lat, longitude: coords.lng) { return false }
            if !needle.isEmpty, !matches(photo, needle: needle) { return false }
            return true
        }
    }

    /// 撮影地の文字列を**名前として、向きを見て**当てる（`LocationMatch.photoIsIn`・Web の
    /// `photoIsInLocation` と同じ規則）。「パリ」は「パリ, フランス」にも「オペラ・ガルニエ（パリ）」
    /// にも当たる。全角半角・大小は区別しない。
    ///
    /// 🔴 2026-10-07 判断: 以前は両向きの字の部分一致で、地図の「福岡」が宮城県白石市の
    /// 「福岡八宮」を含む撮影地（蔵王キツネ村）に当たり、**宮城県の写真へ飛んでいた**。
    /// 狭い語で広い撮影地の写真も拾っていた（「パリ, フランス」で撮影地「パリ」の写真）。
    /// 撮影地のページ（`PhotoQuery.photos(_:in: .location)`）と同じ当て方にそろえる
    static func matches(_ photo: Photo, needle: String) -> Bool {
        let location = fold(photo.location ?? "")
        guard !location.isEmpty else { return false }
        return LocationMatch.photoIsIn(location, fold(needle))
    }

    /// その点が範囲に入っているか。**幅の半分**で切る（`span` は端から端）。
    ///
    /// 経度 180 度をまたぐ範囲は単純な引き算では判定できない。
    /// 写真の実データ（日本・欧州）では起きないので、そのままにしてある
    static func contains(_ frame: MapFraming.Frame, latitude: Double, longitude: Double) -> Bool {
        abs(latitude - frame.latitude) <= frame.latitudeSpan / 2
            && abs(longitude - frame.longitude) <= frame.longitudeSpan / 2
    }

    /// 突き合わせる前の揃え方（前後の空白・全角半角・大小）。
    /// スポットの索引の名前は、これに加えて空白・括弧も見ない（`OfficialSpotIndex.spotName`）
    static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}
