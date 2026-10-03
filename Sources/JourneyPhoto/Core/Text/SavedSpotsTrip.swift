import Foundation

/// 「行きたい場所」の地図から旅行プランを作る（3か月の計画の7「保存を地図で見る → 軽い旅の計画」の続き・2026-10-03）。
///
/// 地図（`SavedSpotsMapView`）でピンを複数選び、「この N か所で旅行プランを作る」で
/// **既存の旅行プラン**（`TripPlansModel.create`・`POST /user/trips`）を作って日程の画面
/// （`TripPlanDetailView`）へ進む。板 WishlistTab の「この3か所で旅行プランを作る」
/// （押すと TripPlanDays＝日程の画面へ直に進む）に合わせた。
///
/// - 項目は既存の `TripItem`（撮影スポット＝`.spot(spotId:)`・撮影地＝`.location(slug:)`）。写しを作らない
/// - 並びは座標から**近い順の案**（最初に選んだ場所から、いちばん近い未訪の場所へ進む貪欲法）。
///   距離は `TravelDistance.kilometers`（大圏・日付変更線をまたいでも正しい）で、**画面には出さない**
///   （移動時間・道のりは計算しない——`TripPlan` の約束）。並べ替えは日程の画面の今の仕組みのまま
/// - 日付は入れない（日程の画面の出発・帰着の入力のまま）
/// - どのプランに入っているかは、プランの一覧と突き合わせるだけ
///
/// サーバー・DB には触らない（既存の作成の口だけ）。
enum SavedSpotsTrip {

    /// 1回に選べる数。写真から選ぶ板と同じ上限（`TripPicker.pickMax`）
    static let selectMax = TripPicker.pickMax

    // MARK: - 選ぶ

    /// 選んだ場所（鍵）。**押した順を覚える**——近い順の案は最初に選んだ場所から始める
    struct Selection: Equatable {
        private(set) var keys: [String] = []

        var count: Int { keys.count }
        var isEmpty: Bool { keys.isEmpty }
        func contains(_ key: String) -> Bool { keys.contains(key) }

        /// 押し直すと外れる。上限に達していたら足さない（`false` を返す）。外したとき・足したときは `true`
        @discardableResult
        mutating func toggle(_ key: String) -> Bool {
            if let at = keys.firstIndex(of: key) {
                keys.remove(at: at)
                return true
            }
            guard keys.count < SavedSpotsTrip.selectMax else { return false }
            keys.append(key)
            return true
        }

        mutating func remove(_ key: String) {
            keys.removeAll { $0 == key }
        }

        /// 選んだ順の場所。**地図に無い鍵は落とす**（開いている間に外れたものを数えない）
        func items(in pinned: [SavedSpotsMap.Item]) -> [SavedSpotsMap.Item] {
            let byKey = Dictionary(pinned.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            return keys.compactMap { byKey[$0] }
        }
    }

    /// 選べる場所か（プランに入れられる鍵がある）。撮影地でスラッグの無いもの・索引に無いスポットは選べない
    static func canSelect(_ item: SavedSpotsMap.Item) -> Bool {
        tripItem(item) != nil
    }

    /// 日程に置く項目。**既存の `TripItem` のまま**（`TripPlanText.choices` と同じ鍵の取り方）
    static func tripItem(_ item: SavedSpotsMap.Item) -> TripItem? {
        switch item.target {
        case .place(let place):
            guard !place.slug.isEmpty, !SavedSpotKey.isOfficial(place.slug) else { return nil }
            return .location(slug: place.slug, note: nil)
        case .official(let row):
            guard let spot = row.spot, !spot.spotId.isEmpty else { return nil }
            return .spot(spotId: spot.spotId, note: nil)
        }
    }

    // MARK: - 近い順

    /// 近い順の案。**最初に選んだ場所から**、いちばん近い未訪の場所へ順に進む（最近傍の貪欲法）。
    ///
    /// - 同じ距離（同じ座標を含む）は**選んだ順**（毎回同じ並びにする・押した順を崩さない）
    /// - 座標の無いものは最後に、選んだ順で置く（地図のピンは座標を持つので、ふつうは無い）
    /// - 距離は大圏（`TravelDistance.kilometers`）。日付変更線の両側は近いと見る
    static func nearestOrder(_ items: [SavedSpotsMap.Item]) -> [SavedSpotsMap.Item] {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.key).inserted }
        var located = unique.filter { $0.coords != nil }
        let unlocated = unique.filter { $0.coords == nil }
        guard !located.isEmpty else { return unlocated }

        var result = [located.removeFirst()]
        var here = result[0].coords!
        while !located.isEmpty {
            var bestIndex = 0
            var bestKm = Double.infinity
            // 先の方（選んだ順の早い方）を残すため、厳密に近いときだけ替える
            for (i, item) in located.enumerated() {
                let km = TravelDistance.kilometers(from: here, to: item.coords!)
                if km < bestKm {
                    bestIndex = i
                    bestKm = km
                }
            }
            let next = located.remove(at: bestIndex)
            result.append(next)
            here = next.coords!
        }
        return result + unlocated
    }

    // MARK: - プランへ渡す

    /// 作るときに送る中身（題・日程）。日付は送らない（日程の画面で入れる）
    struct Draft: Equatable {
        let title: String
        let days: [TripDay]
    }

    /// 選んだ場所から、作るときに送る中身を作る。並びは `nearestOrder`。
    ///
    /// - 1日に入れるのは**サーバーの上限まで**（`TripPlanService.itemsPerDayMax`）。越えたら次の日へ
    ///   （サーバーは越えた分を黙って切り捨てる——`TripPicker.days` の注記）
    /// - 題は写真から選ぶ板と同じ作り方（地域の名前を2つまで・`TripPicker.defaultTitle`）。
    ///   撮影地は地域を持たないので、スポットの地域だけで決まる。無ければ「行きたい場所の旅」
    /// - 入れられない場所（`tripItem` が nil）は落とす。全部落ちたら nil（作らない）
    static func draft(_ selected: [SavedSpotsMap.Item]) -> Draft? {
        let ordered = nearestOrder(selected)
        let items = ordered.compactMap(tripItem)
        guard !items.isEmpty else { return nil }
        let cap = TripPlanService.itemsPerDayMax
        let days = stride(from: 0, to: items.count, by: cap).map {
            TripDay(items: Array(items[$0..<min($0 + cap, items.count)]))
        }
        let spots: [[OfficialSpot]] = ordered.compactMap {
            if case .official(let row) = $0.target, let spot = row.spot { return [spot] }
            return nil
        }
        let title = TripPlanService.titleToSend(TripPicker.defaultTitle(spots))
        return Draft(title: title, days: days)
    }

    /// 主ボタンの文言（板 WishlistTab「この3か所で旅行プランを作る」）
    static func createLabel(count: Int) -> String {
        L("この \(count) か所で旅行プランを作る",
          count == 1 ? "Plan a trip with this place" : "Plan a trip with these \(count) places")
    }

    // MARK: - どのプランに入っているか

    /// 項目の鍵（`TripPlanText.Choice.id` と同じ形）
    static func itemKey(_ item: TripItem) -> String {
        switch item {
        case .spot(let spotId, _): return "spot:\(spotId)"
        case .location(let slug, _): return "location:\(slug)"
        }
    }

    /// 項目の鍵 → 入っているプランの題（一覧の並びのまま・同じプランは1度）。題が空なら「無題のプラン」
    static func membership(_ plans: [TripPlan]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for plan in plans {
            let title = plan.title.isEmpty ? L("無題のプラン", "Untitled trip") : plan.title
            var inThisPlan = Set<String>()
            for day in plan.days {
                for item in day.items where inThisPlan.insert(itemKey(item)).inserted {
                    out[itemKey(item), default: []].append(title)
                }
            }
        }
        return out
    }

    /// その場所が入っているプランの題（無ければ空）
    static func plans(containing item: SavedSpotsMap.Item, in membership: [String: [String]]) -> [String] {
        guard let tripItem = tripItem(item) else { return [] }
        return membership[itemKey(tripItem)] ?? []
    }

    /// ピンの読み上げ名に足す一言。「旅行プラン「京都の旅」に入っています」。2つ以上は数で言う
    static func membershipPhrase(_ titles: [String]) -> String? {
        switch titles.count {
        case 0: return nil
        case 1: return L("旅行プラン「\(titles[0])」に入っています", "In trip “\(titles[0])”")
        default: return L("旅行プラン \(titles.count) 件に入っています", "In \(titles.count) trips")
        }
    }
}
