import Foundation

/// 写真から行き先を選ぶ（2026-09-30 owner の依頼「どこに旅行行きたいかを直感で操作できて
/// 旅行プラン作成する機能」）の決まり。画面から切り離して試験する。
///
/// **写真を見て指で選ぶだけで、行きたい場所が集まり、そのまま旅行プランの下書きになる。**
///
/// - 札に出すのは**公開済みで写真のある撮影スポットだけ**（下書き `isDraft` は出さない。
///   写真は作者とライセンスと必ず一緒に出す——`SpotImage`）
/// - 並びは**混ぜる**（毎回同じ上位から見せない・順位を作らない）
/// - 選んだ場所は**地域（国・都道府県）で束ね、近い順に**日へ割り振る。
///   距離は写真と同じ直線の式（`TravelDistance.kilometers`）で、**画面には出さない**
///   （移動時間・費用・道のりは計算していない。`TripPlanText` の約束）
/// - 日の数と1日の数は**サーバーの上限の内側**（`TripPlanService.daysMax`・`itemsPerDayMax`）
enum TripPicker {

    // MARK: - 札の山

    /// 1回に選べる数。**これを越えて足させない**（上限の無い選び方は日程が60日を越え、
    /// 保存でサーバーに断られる。40か所を1日1か所ずつでも60日に収まる）
    static let pickMax = 40

    /// 札に出してよいか。**公開済み・写真あり**だけ（下書きの場所を「行きたい」の札にしない）
    static func isEligible(_ spot: OfficialSpot) -> Bool {
        !spot.isDraft && spot.photo != nil
    }

    /// 札の山。出してよいものを、`seed` で混ぜて返す。
    ///
    /// - `excluding` は「行きたい」の鍵（`SavedSpotKey.official`）。**もう入れた場所は出さない**
    ///   （同じ場所を何度も見せない）
    /// - 同じ `spotId`・同じ `slug` は1枚（「行きたい」の鍵は slug から作るので、slug の重なりも落とす）
    /// - 混ぜ方は `seed` だけで決まる（試験で並びを固定できる。画面は開くたびに新しい種を渡す）
    static func deck(from spots: [OfficialSpot], excluding keys: Set<String>, seed: UInt64) -> [OfficialSpot] {
        var seenIds = Set<String>()
        var seenSlugs = Set<String>()
        let pool = spots
            .filter(isEligible)
            .filter { !keys.contains(SavedSpotKey.official($0.slug)) }
            // 並べ替えてから混ぜる（索引の並びが変わっても、同じ種なら同じ並びにする）
            .sorted { $0.spotId < $1.spotId }
            .filter { seenIds.insert($0.spotId).inserted && seenSlugs.insert($0.slug).inserted }
        return shuffled(pool, seed: seed)
    }

    /// 種で決まる混ぜ方（Fisher–Yates・SplitMix64）。`shuffled()` は種を渡せないので使わない
    static func shuffled<T>(_ items: [T], seed: UInt64) -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        var state = seed
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            let j = Int(z % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }

    /// 札に添える季節のひとこと。**いまの季節の案内があるときだけ**（無ければ nil・作らない）
    static func seasonHint(_ spot: OfficialSpot, now: Date, timeZone: TimeZone = .current) -> (label: String, text: String)? {
        let current = SpotBodyText.currentSeason(now: now, timeZone: timeZone)
        guard let guide = spot.seasons.first(where: { $0.season == current }),
              let label = SpotBodyText.seasonLabel(current) else { return nil }
        let text = guide.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (label, text)
    }

    // MARK: - 地域で束ねる

    /// 束ねる単位。**日本の外は国、日本は都道府県**（索引は日本の外の行だけ `country` を持つ）
    struct Region: Hashable {
        let key: String
        /// 画面に出す名前（台帳の表記のまま）。どちらも無ければ nil
        let label: String?
    }

    static func region(of spot: OfficialSpot) -> Region {
        if let country = trimmed(spot.region?.country) {
            return Region(key: "country:\(country)", label: country)
        }
        if let prefecture = trimmed(spot.region?.prefecture) {
            return Region(key: "prefecture:\(prefecture)", label: prefecture)
        }
        return Region(key: "none", label: nil)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// 選んだ場所を地域で束ね、回る順に並べる。
    ///
    /// - 最初の地域は**最初に選んだ場所の地域**、その中は最初に選んだ場所から始める
    /// - 次の地域は、**いまいる場所（前の地域の最後）にいちばん近い場所を持つ地域**。
    ///   その地域はその場所から始める
    /// - 地域の中は**いちばん近い未訪の場所へ**順に進む（近い順）
    /// - 座標の無い場所は、その地域の最後に選んだ順で置く。座標の無い地域は最後に選んだ順で置く
    /// - 同じ距離は slug の順（毎回同じ並びにする）
    static func grouped(_ picked: [OfficialSpot]) -> [[OfficialSpot]] {
        var seen = Set<String>()
        let unique = picked.filter { seen.insert($0.spotId).inserted }
        guard !unique.isEmpty else { return [] }

        // 地域ごとに、選んだ順のまま集める
        var order: [String] = []
        var members: [String: [OfficialSpot]] = [:]
        for spot in unique {
            let key = region(of: spot).key
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(spot)
        }

        var result: [[OfficialSpot]] = []
        var remaining = order
        var here: Photo.Coords?

        // 最初の地域は、最初に選んだ場所の地域
        let firstKey = remaining.removeFirst()
        let first = chain(members[firstKey] ?? [], from: nil)
        result.append(first)
        here = first.last(where: { $0.coords != nil })?.coords

        while !remaining.isEmpty {
            var next = 0
            if let here {
                var best: (index: Int, km: Double, slug: String)?
                for (i, key) in remaining.enumerated() {
                    for spot in members[key] ?? [] {
                        guard let coords = spot.coords else { continue }
                        let km = TravelDistance.kilometers(from: here, to: coords)
                        if best == nil || km < best!.km || (km == best!.km && spot.slug < best!.slug) {
                            best = (i, km, spot.slug)
                        }
                    }
                }
                // 座標のある地域が残っていなければ、選んだ順のまま
                next = best?.index ?? 0
            }
            let key = remaining.remove(at: next)
            let group = chain(members[key] ?? [], from: here)
            result.append(group)
            if let last = group.last(where: { $0.coords != nil })?.coords { here = last }
        }
        return result
    }

    /// 地域の中を近い順に辿る。`from` が nil なら最初に選んだ場所（座標のあるもの）から
    private static func chain(_ spots: [OfficialSpot], from start: Photo.Coords?) -> [OfficialSpot] {
        var located = spots.filter { $0.coords != nil }
        let unlocated = spots.filter { $0.coords == nil }
        guard !located.isEmpty else { return unlocated }

        var result: [OfficialSpot] = []
        var here: Photo.Coords
        if let start {
            here = start
        } else {
            let head = located.removeFirst()
            result.append(head)
            here = head.coords!
        }
        while !located.isEmpty {
            var bestIndex = 0
            var bestKm = Double.infinity
            for (i, spot) in located.enumerated() {
                let km = TravelDistance.kilometers(from: here, to: spot.coords!)
                if km < bestKm || (km == bestKm && spot.slug < located[bestIndex].slug) {
                    bestIndex = i
                    bestKm = km
                }
            }
            let spot = located.remove(at: bestIndex)
            result.append(spot)
            here = spot.coords!
        }
        return result + unlocated
    }

    // MARK: - 日へ割り振る

    /// 日付が無いときの1日の目安（か所）。**地域は日をまたいでも混ぜない**
    static let placesPerDay = 4

    /// 出発と帰着から日数。**両方が実在する日で、帰着が出発より前でないときだけ**。
    /// サーバーの上限（`daysMax`）で止める
    static func dayCount(start: String?, end: String?) -> Int? {
        guard let s = TripPlanText.date(fromYMD: start), let e = TripPlanText.date(fromYMD: end), e >= s,
              let diff = TripPlanText.calendar.dateComponents([.day], from: s, to: e).day else { return nil }
        return min(diff + 1, TripPlanService.daysMax)
    }

    /// 束ねた場所を日へ割り振る。**並び（回る順）は変えない**——切る位置だけを決める。
    ///
    /// - 日数が無い: 地域ごとに `placesPerDay` 前後で均して切る（地域を1日に混ぜない）
    /// - 日数がある:
    ///   - 足りないとき（場所が多い）: **隣り合う2日のうち合わせて少ない方から**1日にまとめる
    ///     （同じ数なら同じ地域どうしを先に）。1日の上限（`itemsPerDayMax`）を越えるまとめはしない
    ///     ——まとめ切れなければ日数を越えたまま返す（日付の無い日になる。場所を黙って落とさない）
    ///   - 余るとき（日数が多い）: **いちばん多い日を半分に**切っていき、それでも余れば
    ///     最後に空の日を足す（本人が後で埋める）
    static func days(_ groups: [[OfficialSpot]], dayCount: Int?) -> [[OfficialSpot]] {
        // 1日ぶんと、その日の地域（まとめるときに同じ地域を先にするため）
        var days: [(spots: [OfficialSpot], region: String?)] = []
        for group in groups where !group.isEmpty {
            let key = region(of: group[0]).key
            let parts = Int((Double(group.count) / Double(placesPerDay)).rounded(.up))
            for chunk in balanced(group, parts: parts) {
                days.append((chunk, key))
            }
        }
        guard let target = dayCount.map({ min($0, TripPlanService.daysMax) }), target > 0 else {
            return days.map(\.spots)
        }

        // 多すぎる日数を、隣どうしでまとめて減らす
        while days.count > target {
            var best: (index: Int, total: Int, sameRegion: Bool)?
            for i in 0..<(days.count - 1) {
                let total = days[i].spots.count + days[i + 1].spots.count
                guard total <= TripPlanService.itemsPerDayMax else { continue }
                let same = days[i].region != nil && days[i].region == days[i + 1].region
                if let b = best {
                    if total < b.total || (total == b.total && same && !b.sameRegion) {
                        best = (i, total, same)
                    }
                } else {
                    best = (i, total, same)
                }
            }
            guard let merge = best else { break }
            let a = days[merge.index], b = days[merge.index + 1]
            days[merge.index] = (a.spots + b.spots, a.region == b.region ? a.region : nil)
            days.remove(at: merge.index + 1)
        }

        // 余る日数は、いちばん多い日を切って埋める
        while days.count < target {
            // 同じ数なら前の日（`max(by:)` は等しいとき先のものを残す）
            guard let widest = days.indices.max(by: { days[$0].spots.count < days[$1].spots.count }),
                  days[widest].spots.count > 1 else { break }
            let halves = balanced(days[widest].spots, parts: 2)
            let region = days[widest].region
            days[widest] = (halves[0], region)
            days.insert((halves[1], region), at: widest + 1)
        }
        while days.count < target {
            days.append(([], nil))
        }
        return days.map(\.spots)
    }

    /// 並びを保ったまま `parts` 個に均して切る（前の方を1つ多く）。空の片は作らない
    private static func balanced(_ spots: [OfficialSpot], parts: Int) -> [[OfficialSpot]] {
        let n = max(1, min(parts, spots.count))
        guard !spots.isEmpty else { return [] }
        let base = spots.count / n
        let extra = spots.count % n
        var result: [[OfficialSpot]] = []
        var start = 0
        for i in 0..<n {
            let size = base + (i < extra ? 1 : 0)
            result.append(Array(spots[start..<(start + size)]))
            start += size
        }
        return result
    }

    /// 保存する日程。項目は台帳の鍵（`spotId`）。**日付は付けない**
    /// （出発日から数える——`TripPlanText.dayDate`。Web の画面も日に日付を付けない）
    static func tripDays(_ days: [[OfficialSpot]]) -> [TripDay] {
        days.map { TripDay(items: $0.map { .spot(spotId: $0.spotId, note: nil) }) }
    }

    /// その日の地域の名前（「京都府・奈良県」）。無ければ nil
    static func regionLabel(of day: [OfficialSpot]) -> String? {
        var seen = Set<String>()
        let labels = day.compactMap { region(of: $0).label }.filter { seen.insert($0).inserted }
        return labels.isEmpty ? nil : labels.joined(separator: "・")
    }

    /// 題の下書き。地域の名前を2つまで（「京都府・奈良県の旅」「京都府・奈良県ほかの旅」）。
    /// 地域の名前が1つも無ければ「行きたい場所の旅」
    static func defaultTitle(_ groups: [[OfficialSpot]]) -> String {
        var seen = Set<String>()
        let labels = groups.compactMap { $0.first.flatMap { region(of: $0).label } }
            .filter { seen.insert($0).inserted }
        guard !labels.isEmpty else { return L("行きたい場所の旅", "Places I want to go") }
        let head = labels.prefix(2).joined(separator: "・")
        let more = labels.count > 2
        return L("\(head)\(more ? "ほか" : "")の旅", "Trip to \(labels.prefix(2).joined(separator: ", "))\(more ? " and more" : "")")
    }
}
