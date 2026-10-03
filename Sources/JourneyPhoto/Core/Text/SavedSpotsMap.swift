import Foundation

/// 「行きたい場所」を地図で見る（3か月の計画の7「保存を地図で見る → 軽い旅の計画」の第一歩・2026-10-03）。
///
/// 「行きたい」の入れ物（`WishlistStore`）には2種類の鍵が同居する:
///
///     撮影地（スラッグ）      → `DerivedSpot.Place`（写真から導く。座標は写真の1枚目）
///     撮影スポット（SPOT-…）  → `OfficialWishlist.Row`（座標は索引 `app/data/spots.json` の coords）
///
/// マイページの一覧と**同じ行**から、地図に置けるもの（座標がある）と置けないものに分ける。
/// 置けないもの（索引に無い・座標の無い行・壊れた座標）は地図の下に一覧で残す
/// ——**押した覚えのあるものを地図から黙って消さない**（`OfficialWishlist` と同じ考え）。
///
/// サーバー・DB には触らない。使うのは既存の控えと索引だけ。
enum SavedSpotsMap {

    struct Item: Identifiable, Equatable {
        enum Target: Equatable {
            case place(DerivedSpot.Place)
            case official(OfficialWishlist.Row)
        }

        let target: Target
        /// 入れ物に入っている鍵（撮影地はスラッグ、スポットは `SPOT-<slug>`）
        let key: String
        let name: String
        /// 「京都府 · 京都市」など。無ければ nil
        let subtitle: String?
        /// **地図に置ける座標だけ**（壊れた値は nil に倒す・`usable`）
        let coords: Photo.Coords?
        /// ピンの丸に出す写真（スポットは Commons の写真、撮影地は代表の1枚）。無ければ真鍮の丸
        let imageURL: URL?
        /// 押して開ける画面があるか（索引に無いスポットの鍵は開けない）
        let canOpen: Bool
        /// 下書き（運営未確認）の撮影スポットか。読み上げ・一覧の札に使う
        let isDraft: Bool

        var id: String { key }
    }

    struct Split: Equatable {
        /// 地図に置くもの（並びは一覧と同じ）
        let pinned: [Item]
        /// 座標が無く、地図の下に一覧で残すもの
        let unplaced: [Item]

        var isEmpty: Bool { pinned.isEmpty && unplaced.isEmpty }
        var count: Int { pinned.count + unplaced.count }
    }

    /// 一覧の行（撮影地が先、スポットが後——マイページと同じ並び）を地図用に分ける。
    /// 同じ鍵が2度来たら最初の1つだけ（同じピンを重ねない）
    static func split(places: [DerivedSpot.Place], officialRows: [OfficialWishlist.Row]) -> Split {
        var seen = Set<String>()
        var pinned: [Item] = []
        var unplaced: [Item] = []
        let all = places.map(item) + officialRows.map(item)
        for entry in all where seen.insert(entry.key).inserted {
            if entry.coords != nil {
                pinned.append(entry)
            } else {
                unplaced.append(entry)
            }
        }
        return Split(pinned: pinned, unplaced: unplaced)
    }

    static func item(_ place: DerivedSpot.Place) -> Item {
        let broader = place.broader.joined(separator: " · ")
        return Item(target: .place(place),
                    key: place.slug.isEmpty ? place.label : place.slug,
                    name: place.label,
                    subtitle: broader.isEmpty ? nil : broader,
                    coords: usable(place.coords),
                    imageURL: place.cover?.pinImageURL,
                    canOpen: true,
                    isDraft: false)
    }

    static func item(_ row: OfficialWishlist.Row) -> Item {
        Item(target: .official(row),
             key: row.key,
             name: row.name,
             subtitle: row.regionLabel,
             coords: usable(row.spot?.coords),
             imageURL: row.spot?.photo?.url,
             canOpen: row.spot != nil,
             isDraft: row.spot?.isDraft ?? false)
    }

    /// 地図に置ける座標か。**数でない値・範囲の外は置かない**（古いデータ・壊れた行で
    /// 地図の枠が壊れないように。`MapFraming.largestCluster` と同じ線）
    static func usable(_ coords: Photo.Coords?) -> Photo.Coords? {
        guard let coords,
              coords.lat.isFinite, coords.lng.isFinite,
              abs(coords.lat) <= 90, abs(coords.lng) <= 180 else { return nil }
        return coords
    }

    /// **保存した場所が全部入る枠。**
    ///
    /// 地図のタブ・プロフィールの地図（`MapFraming.frame`）は「いちばん重い塊」に寄せるが、
    /// ここは旅の候補を見渡す画面なので**1か所も外に出さない**。
    ///
    /// - 経度は日付変更線をまたぐ並びも狭く囲む（ハワイと日本なら太平洋側で囲む）。
    ///   点の間の**いちばん広い隙間の反対側**を枠にする
    /// - 余白は `MapFraming.padding`、いちばん狭い幅は `MapFraming.minimumSpan`（1か所だけでも寄りすぎない）
    /// - 枠は**南北の極を越えない**（越えた枠は地図が受け付けない）。越えるときは幅を縮めず、
    ///   中心を極から離す（極のすぐそばの1点でも寄りすぎない）
    /// - 点が無ければ nil（呼ぶ側は地図の既定に任せる）
    static func frame(for coords: [Photo.Coords]) -> MapFraming.Frame? {
        let points = coords.compactMap(usable)
        guard let first = points.first else { return nil }

        var minLat = first.lat, maxLat = first.lat
        for p in points {
            minLat = min(minLat, p.lat)
            maxLat = max(maxLat, p.lat)
        }
        let rawLat = maxLat - minLat
        // 幅はいつもの余白つき（180° まで）。極を越えるなら**中心を極から離して**収める
        // （幅を縮めると、極のすぐそばの1点で地図が寄りすぎた）。幅が点の広がり以上なので、
        // ずらしても点は枠の中に残る
        let latSpan = min(180, max(rawLat, MapFraming.minimumSpan, rawLat * MapFraming.padding))
        var centerLat = (minLat + maxLat) / 2
        if centerLat + latSpan / 2 > 90 { centerLat = 90 - latSpan / 2 }
        if centerLat - latSpan / 2 < -90 { centerLat = -90 + latSpan / 2 }

        // 経度: 並べて、隣り合う点の間（端から端へ回り込む隙間を含む）でいちばん広い所を外にする
        let lngs = points.map(\.lng).sorted()
        var start = lngs[0]
        var end = lngs[lngs.count - 1]
        var widestGap = lngs[0] + 360 - lngs[lngs.count - 1]
        for i in lngs.indices.dropFirst() {
            let gap = lngs[i] - lngs[i - 1]
            if gap > widestGap {
                widestGap = gap
                start = lngs[i]
                end = lngs[i - 1] + 360
            }
        }
        let rawLng = end - start
        var centerLng = start + rawLng / 2
        if centerLng > 180 { centerLng -= 360 }
        let lngSpan = min(360, max(MapFraming.minimumSpan, rawLng * MapFraming.padding))

        return MapFraming.Frame(latitude: centerLat, longitude: centerLng,
                                latitudeSpan: latSpan, longitudeSpan: lngSpan)
    }

    /// 開く先の読み上げのヒント。撮影スポットと撮影地で言い分ける（開く画面が違う）
    static func openHint(_ item: Item) -> String {
        switch item.target {
        case .place: return L("撮影地の画面を開きます", "Opens the place")
        case .official: return L("撮影スポットの画面を開きます", "Opens the spot")
        }
    }

    /// ピンの読み上げ名。「伏見稲荷大社 · 京都府 · 行きたい場所」。下書きならそれも言う
    static func spokenLabel(_ item: Item) -> String {
        var parts = [item.name]
        if let subtitle = item.subtitle { parts.append(subtitle) }
        if item.isDraft { parts.append(L("下書き", "Draft")) }
        parts.append(L("行きたい場所", "Want to go"))
        return parts.joined(separator: " · ")
    }

    /// 見出しの下の一行。「地図に 5 か所 · 場所の分からないもの 2 か所」
    static func summary(_ split: Split) -> String {
        if split.unplaced.isEmpty {
            return L("地図に \(split.pinned.count) か所", "\(split.pinned.count) on the map")
        }
        return L("地図に \(split.pinned.count) か所 · 場所の分からないもの \(split.unplaced.count) か所",
                 "\(split.pinned.count) on the map · \(split.unplaced.count) without a location")
    }
}
