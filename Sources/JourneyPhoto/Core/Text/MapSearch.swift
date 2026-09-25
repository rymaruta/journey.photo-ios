import Foundation

/// 撮影地マップの絞り込み（モック3 の検索窓・チップ・「このエリアを検索」）。
///
/// **地図とリストは同じ答えから描く。** ここが返した写真を `MapPin.group` に
/// 通したものがピンで、同じピンがリストの行になる——別々に絞ると
/// ピンの数と行の数が食い違う。
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

    /// 条件に合う写真。**座標の無い写真は最初から入れない**
    /// ——地図に置けないものをリストにだけ出すと、切り替えた瞬間に
    /// 件数が変わる。
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

    /// 撮影地の文字列はゆるく見る（`PhotoQuery.photos(_:in: .location)` と同じ約束:
    /// 「パリ」は「パリ, フランス」にも「オペラ・ガルニエ（パリ）」にも当たる）。
    /// 全角半角・大小は区別しない
    static func matches(_ photo: Photo, needle: String) -> Bool {
        let location = fold(photo.location ?? "")
        guard !location.isEmpty else { return false }
        return location == needle || location.contains(needle) || needle.contains(location)
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
    /// スポットの索引（`OfficialSpotIndex`）も同じ揃え方で引く
    static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}
