import Foundation

/// 旅行プランを**まとめて作る**流れの決まり（2026-11-10 判断・札 #521・案 A の第 1 段）。
///
/// 「作る」を押したら、行きたい場所をまとめて選び、日付（決めないなら日数）を入れるだけ。
/// 日ごとの割り振りと日の中の並びは下書きで出す。画面（`TripCreateView`）から切り離して試験する。
///
/// - 割り振りは**今の作り1つ**（`TripPicker.grouped` → `TripPicker.days`・地域で束ねて近い順に日へ均す）。
///   写真から選ぶ・行きたい場所・行きたい場所の地図の3つの入口が、ここを通って同じ下書きになる
/// - 日の中は**時間帯の案内の順**（夜明け → 朝 → 日中 → 夕方の斜光 → 日没後 → 夜・`SpotBodyText.timeOrder`）。
///   案内の無い所は、近い順で決まった位置のまま動かさない
/// - 同じ日に短い時間帯（夜明け・夕方の斜光・日没後）が重なるときは、日の見出しの下に1行で知らせる
/// - 日の出・日の入りは端末で計算（`SunTimes`・外の API は使わない）。その日の最初の撮影スポットの座標と時刻帯で出す
/// - 下書きの段では移動時間は計算していない（そう書く）。移動の見込みは保存した日程の画面で出す（`TripTravel`）
enum TripDraft {

    // MARK: - 場所

    /// 下書きに置く1か所。撮影スポットか撮影地（`TripItem` と同じ2種類）
    struct Place: Identifiable, Equatable, TripAllocatable {
        let item: TripItem
        let name: String
        /// 「石川県 · 金沢市」。撮影地には無い
        let regionLabel: String?
        let coords: Photo.Coords?
        let region: TripPicker.Region
        /// 時間帯の案内がある時間帯（台帳の綴り）。撮影地・案内の無い所は空
        let times: [String]
        /// 台帳の slug・撮影地の slug（同じ距離のときの並び）
        let tie: String

        var id: String { SavedSpotsTrip.itemKey(item) }
        var isSpot: Bool { if case .spot = item { return true } else { return false } }

        var allocationID: String { id }
        var allocationCoords: Photo.Coords? { coords }
        var allocationRegion: TripPicker.Region { region }
        var allocationTie: String { tie }
    }

    static func place(spot: OfficialSpot) -> Place {
        Place(item: .spot(spotId: spot.spotId, note: nil), name: spot.name, regionLabel: spot.regionLabel,
              coords: spot.coords, region: TripPicker.region(of: spot), times: spot.timeKeys, tie: spot.slug)
    }

    /// 撮影地。**地域を持たないので1か所ずつ別の地域**（遠い撮影地を同じ地域として1日にまとめない）
    static func place(location: DerivedSpot.Place) -> Place {
        Place(item: .location(slug: location.slug, note: nil), name: LocationMatch.display(location.label),
              regionLabel: nil, coords: location.coords,
              region: TripPicker.Region(key: "none:location:\(location.slug)", label: nil), times: [], tie: location.slug)
    }

    /// 日程の項目から引き直す（引けなければ名前は鍵のまま・座標なし——`TripPlanText.label` と同じ）
    static func place(for item: TripItem, index: [OfficialSpot], places: [DerivedSpot.Place]) -> Place {
        switch item {
        case .spot(let spotId, _):
            if let spot = index.first(where: { $0.spotId == spotId }) {
                return place(spot: spot)
            }
        case .location(let slug, _):
            if let found = places.first(where: { $0.slug == slug }) {
                return place(location: found)
            }
        }
        let key = SavedSpotsTrip.itemKey(item)
        return Place(item: item, name: TripPlanText.label(for: item, index: index, places: places), regionLabel: nil,
                     coords: nil, region: TripPicker.Region(key: "none:\(key)", label: nil), times: [], tie: key)
    }

    // MARK: - 割り振り

    /// 選んだ順の場所から、日ごとの下書き。地域で束ね → 近い順 → 日へ均す（`TripPicker`）→ 日の中を時間帯の順に
    static func plan(_ picked: [Place], dayCount: Int?) -> [[Place]] {
        TripPicker.days(TripPicker.grouped(picked), dayCount: dayCount).map(timeOrdered)
    }

    /// 保存する日程（日付は付けない・出発日から数える——`TripPicker.tripDays` と同じ）
    static func tripDays(_ days: [[Place]]) -> [TripDay] {
        days.map { TripDay(items: $0.map(\.item)) }
    }

    /// 並べるときの時間帯（案内のある時間帯のうち**いちばん早いもの**）。無ければ nil
    static func primaryTime(_ times: [String]) -> String? {
        times.compactMap { SpotBodyText.timeOrder.firstIndex(of: $0) }.min().map { SpotBodyText.timeOrder[$0] }
    }

    /// 日の中を時間帯の順に。**案内の無い所は、近い順で決まった位置のまま**——案内のある所だけを、
    /// その位置どうしの中で並べ替える（同じ時間帯は近い順のまま）
    static func timeOrdered<T>(_ day: [T], times: (T) -> [String]) -> [T] {
        let ranks: [Int?] = day.map { primaryTime(times($0)).flatMap { SpotBodyText.timeOrder.firstIndex(of: $0) } }
        let slots = day.indices.filter { ranks[$0] != nil }
        let sorted = slots.enumerated()
            .sorted { (ranks[$0.element] ?? 0, $0.offset) < (ranks[$1.element] ?? 0, $1.offset) }
            .map { day[$0.element] }
        var out = day
        for (slot, value) in zip(slots, sorted) { out[slot] = value }
        return out
    }

    static func timeOrdered(_ day: [Place]) -> [Place] {
        timeOrdered(day, times: \.times)
    }

    /// 1日では回りにくい、短い時間帯（夜明け・夕方の斜光・日没後）。朝・日中・夜は長いので数えない
    static let shortWindows = ["dawn", "goldenHour", "dusk"]

    /// 同じ日に短い時間帯が重なるときの1行（「夕方の斜光が 2 か所あります」）。重ならなければ nil。
    /// 数えるのは**並べるときの時間帯**（`primaryTime`）
    static func overlapNote(_ times: [[String]]) -> String? {
        let primaries = times.compactMap(primaryTime)
        for window in shortWindows {
            let n = primaries.filter { $0 == window }.count
            if n >= 2, let label = SpotBodyText.timeLabel(window) {
                return L("\(label)が \(n) か所あります。1 日では回りきれないかもしれません",
                         "\(Plural.count(n, "place")) for \(label.lowercased()). You may not make it to all of them in one day.")
            }
        }
        return nil
    }

    /// 時間帯の札（「夜明け · 朝」）。夜明け → 夜の順で2つまで。無ければ nil
    static func timeChip(_ times: [String]) -> String? {
        let labels = SpotBodyText.timeOrder.filter(times.contains).compactMap(SpotBodyText.timeLabel)
        return labels.isEmpty ? nil : labels.prefix(2).joined(separator: " · ")
    }

    /// 季節の一文（「冬（12月）· 雪吊りの…」）。**その日の月の季節の案内があるときだけ**（撮影地・案内の無い行は nil）
    static func seasonLine(_ spot: OfficialSpot, ymd: String?) -> String? {
        guard let (_, month, _) = TakenDay.ymd(ymd) else { return nil }
        let season = SpotBodyText.season(ofMonth: month)
        guard let label = SpotBodyText.seasonLabel(season),
              let text = spot.seasons.first(where: { $0.season == season })?.text
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return L("\(label)（\(month)月）· \(text)", "\(label) (\(monthName(month))) · \(text)")
    }

    private static func monthName(_ month: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names.indices.contains(month - 1) ? names[month - 1] : "\(month)"
    }

    /// 下書きの見出しの下の1行（並べた理由を書く。計算していないものは計算していないと言う）
    static var explanation: String {
        L("地域でまとめ、近い順に日へ割りました。日の中は時間帯の案内の順（案内の無い所は近い順の位置のまま）。直線の距離で、移動時間は計算していません。",
          "Grouped by region and spread over days, nearest first. Within a day, places follow their best time of day (others keep their place). Straight-line distance; travel time isn't calculated here.")
    }

    // MARK: - 日の出・日の入り

    struct Sun: Equatable {
        /// "HH:MM"（その土地の時計）
        let sunrise: String?
        let sunset: String?
        let sunriseDate: Date?
        let sunsetDate: Date?
        /// 夕方の斜光（ゴールデンアワー）の始まり。無い日は nil
        var goldenStart: Date? = nil
        let zone: TimeZone
    }

    /// その日の**最初の撮影スポット**（座標と時刻帯が引けるもの）で計算した日の出・日の入り。無ければ nil
    static func sun(ymd: String?, spots: [OfficialSpot]) -> Sun? {
        guard let ymd, TripPlanText.date(fromYMD: ymd) != nil else { return nil }
        for spot in spots {
            guard let coords = spot.coords,
                  let zone = SunTimes.timeZone(named: spot.timeZone, country: spot.region?.country),
                  let times = SunTimes.compute(ymd, lat: coords.lat, lng: coords.lng) else { continue }
            let rise = SunTimes.clock(times.sunrise, in: zone)
            let set = SunTimes.clock(times.sunset, in: zone)
            guard rise != nil || set != nil else { continue }
            return Sun(sunrise: rise, sunset: set, sunriseDate: times.sunrise, sunsetDate: times.sunset,
                       goldenStart: times.eveningGolden.start, zone: zone)
        }
        return nil
    }

    // MARK: - 日付

    /// 暦の欄を押したとき。**1つ目で出発、2つ目で帰着**。出発より前を押したら出発を選び直す。
    /// 両方決まった後に押すと、そこから選び直す
    static func tap(start: String?, end: String?, day: String) -> (start: String?, end: String?) {
        guard let start, end == nil else { return (day, nil) }
        if day < start { return (day, nil) }
        return (start, day)
    }

    /// 選んだ期間の1行（「12月24日（木）〜 25日（金）· 1 泊 2 日」）。帰着が無ければ出発の1日
    static func rangeLine(start: String?, end: String?) -> String? {
        guard let s = start, let sd = TripPlanText.date(fromYMD: s) else { return nil }
        let e = end ?? s
        guard let ed = TripPlanText.date(fromYMD: e), ed >= sd,
              let days = TripPicker.dayCount(start: s, end: e) else { return nil }
        let stay = days == 1 ? L("日帰り", "Day trip")
            : L("\(days - 1) 泊 \(days) 日", "\(Plural.count(days - 1, "night")), \(Plural.count(days, "day"))")
        let c1 = TripPlanText.calendar.dateComponents([.year, .month, .day], from: sd)
        let c2 = TripPlanText.calendar.dateComponents([.year, .month, .day], from: ed)
        let first = monthDay(c1.month ?? 0, c1.day ?? 0, weekday(sd))
        guard days > 1 else { return "\(first) · \(stay)" }
        let second = c1.month == c2.month && c1.year == c2.year
            ? L("\(c2.day ?? 0)日（\(weekday(ed))）", "\(c2.day ?? 0) (\(weekday(ed)))")
            : monthDay(c2.month ?? 0, c2.day ?? 0, weekday(ed))
        return "\(first)〜 \(second) · \(stay)"
    }

    private static func monthDay(_ m: Int, _ d: Int, _ w: String) -> String {
        L("\(m)月\(d)日（\(w)）", "\(monthName(m)) \(d) (\(w))")
    }

    /// 曜日の1字（日〜土）。UTC の暦で数える（`TripPlanText.calendar`）
    static func weekday(_ date: Date) -> String {
        let i = TripPlanText.calendar.component(.weekday, from: date) - 1
        let ja = ["日", "月", "火", "水", "木", "金", "土"]
        let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return L(ja[max(0, min(6, i))], en[max(0, min(6, i))])
    }

    /// 暦の1か月（日曜はじまり）。前の空きは nil。`YYYY-MM-DD` を返す
    static func monthGrid(year: Int, month: Int) -> [String?] {
        guard let first = TripPlanText.calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = TripPlanText.calendar.range(of: .day, in: .month, for: first) else { return [] }
        let lead = TripPlanText.calendar.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: lead)
            + range.map { String(format: "%04d-%02d-%02d", year, month, $0) }
    }

    /// 月を送る（`delta` か月）
    static func shiftMonth(year: Int, month: Int, by delta: Int) -> (year: Int, month: Int) {
        let total = year * 12 + (month - 1) + delta
        return (total / 12, total % 12 + 1)
    }

    /// 日付を決めないときの日数の初め（1日 `TripPicker.placesPerDay` か所の目安）
    static func suggestedDayCount(places: Int) -> Int {
        max(1, min(TripPlanService.daysMax, Int((Double(places) / Double(TripPicker.placesPerDay)).rounded(.up))))
    }

    /// 日付の段の下の1行（「5 か所を 2 日に割り振ります。日付は後から変えられます。」）
    static func allocationNote(places: Int, days: Int) -> String {
        L("\(places) か所を \(days) 日に割り振ります。日付は後から変えられます。",
          "\(Plural.count(places, "place")) will be spread over \(Plural.count(days, "day")). You can change dates later.")
    }
}
