import Foundation

/// 旅行プランの**当日モード**: 今日か明日に予定した撮影スポットの光の時刻と季節の案内
/// （owner・2026-09-30「旅行プランで当日と前後の日になったらでいい」）。
///
/// ホームの旅の札（出発が近い・旅の最中）の小さい行に出す。**札は増やさない**
/// （札の並びは owner が決めた「旅 → 季節 → テーマ → 1年前」のまま）。
///
/// ## 決まりごと
///
///  - 出すのは**前日から最終日まで**。今日の日に撮影スポットがあれば今日、無ければ明日の最初のスポット。
///    前日は「明日（1日目）」になる。それ以外の日は nil
///  - 日付は `TripPlanText.dayDate`（その日の日付 → 無ければ出発日から数える）。推測はしない
///  - スポットは**公開済みで座標があり、時刻帯が引ける**ものだけ（`SunTimes.timeZone(forCountry:)`）
///  - 時刻は**その土地の時計**（旅先の時刻）。季節の案内はその日の月の季節の文（台帳の文のまま・短く切る）
///  - 天気は含まない（言わない。計算値だけ）
enum TripLight {

    struct Entry: Equatable {
        let spot: OfficialSpot
        let isTomorrow: Bool
        /// 1から（出発日が1日目）
        let dayNumber: Int
        /// 日の入り。日付をまたげば「翌00:10」、白夜なら「白夜」（Web の撮影の光の表と同じ言い分け）
        let sunset: String?
        /// 夕方のゴールデンアワー "HH:MM–HH:MM"。一日中低ければ「終日」、終わらなければ「HH:MM–（沈まない）」
        let eveningGolden: String?
        /// その季節の案内（短く切ったもの）。札には出さず、呼ぶ側が使うときのため
        let seasonGuide: String?
        /// "spring"〜"winter"
        let season: String
    }

    /// 季節の案内をここまでに切る
    static let guideLimit = 38

    private static let horizon = -0.833
    private static let goldenTop = 6.0

    /// "HH:MM" どうしで、後ろの方が早ければ翌日（日付をまたいだ）。Web の `nextDay` と同じ
    private static func nextDay(_ earlier: String, _ later: String) -> String {
        later < earlier ? L("翌\(later)", "\(later) (+1)") : later
    }

    /// 日の入りとゴールデンアワーの言い方（Web の `lightCalendar` と同じ言い分け・9d7ba04e のレビュー）。
    /// 呼び名は 2026-10-03 owner 判断で「ゴールデンアワー」（Web は同じ幅を「マジックアワー」と呼ぶ）
    static func words(_ times: SunTimes, altitude: (max: Double, min: Double)?, in zone: TimeZone)
        -> (sunset: String?, golden: String?) {
        let rise = SunTimes.clock(times.sunrise, in: zone)
        let set = SunTimes.clock(times.sunset, in: zone)
        var sunset: String?
        if let set {
            sunset = rise.map { nextDay($0, set) } ?? set
        } else if let altitude {
            // 日の入りが無い日は白夜か極夜（同じ赤緯・同じ式なので必ずどちらか・Web と同じ）
            sunset = altitude.min > horizon ? L("白夜", "Midnight sun") : L("極夜", "Polar night")
        }
        let gStart = SunTimes.clock(times.eveningGolden.start, in: zone)
        let gEnd = SunTimes.clock(times.eveningGolden.end, in: zone)
        var golden: String?
        if let gStart, let gEnd {
            golden = "\(gStart)–\(nextDay(gStart, gEnd))"
        } else if gStart == nil, let altitude, altitude.max < goldenTop, altitude.max > horizon {
            // 昇るが一日中 6° まで上がらない＝昼のあいだずっとゴールデンアワー（昇らない日には言わない）
            golden = L("終日", "All day")
        } else if gStart == nil, let altitude, altitude.max <= horizon {
            golden = L("極夜", "Polar night")
        } else if let gStart {
            // −4° まで下がらない。沈まない（白夜）か、沈むが明け方までつながるか（Web と同じ言い分け）
            golden = (altitude?.min ?? horizon) > horizon
                ? L("\(gStart)–（沈まない）", "\(gStart)– (sun stays up)")
                : L("\(gStart)–（明け方まで）", "\(gStart)– (until dawn)")
        }
        return (sunset, golden)
    }

    static func entry(plan: TripPlan, today: Date, spots: [OfficialSpot]) -> Entry? {
        let todayYMD = TripPlanText.ymd(today)
        guard let tomorrowDate = TripPlanText.calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        let tomorrowYMD = TripPlanText.ymd(tomorrowDate)
        let byId = Dictionary(spots.map { ($0.spotId, $0) }, uniquingKeysWith: { first, _ in first })

        for (wanted, isTomorrow) in [(todayYMD, false), (tomorrowYMD, true)] {
            for (index, day) in plan.days.enumerated() {
                guard let date = TripPlanText.dayDate(index: index, day: day, start: plan.startDate, end: plan.endDate),
                      date == wanted else { continue }
                for item in day.items {
                    guard case .spot(let spotId, _) = item,
                          let spot = byId[spotId], !spot.isDraft,
                          let coords = spot.coords,
                          let zone = SunTimes.timeZone(forCountry: spot.region?.country),
                          let times = SunTimes.compute(date, lat: coords.lat, lng: coords.lng) else { continue }
                    let month = TakenDay.ymd(date)?.1 ?? 1
                    let season = SpotBodyText.season(ofMonth: month)
                    let guide = spot.seasons.first { $0.season == season }?.text
                    let said = words(times, altitude: SunTimes.altitudeRange(date, lat: coords.lat, lng: coords.lng), in: zone)
                    return Entry(spot: spot, isTomorrow: isTomorrow, dayNumber: index + 1,
                                 sunset: said.sunset,
                                 eveningGolden: said.golden,
                                 seasonGuide: guide.map { shorten($0) },
                                 season: season)
                }
            }
        }
        return nil
    }

    /// 札の小さい行（**ほかの札と同じ2行まで**——3行にすると並びの背が揃うぶん全部の札が高くなり、
    /// 下の写真の一覧が押し下がる）:
    ///   「明日 · 銀山温泉 · ゴールデンアワー 16:26–17:18 · 日の入り 17:02」
    /// 季節の案内は札に出さない（スポットの画面にある）。時刻が1つも無ければ名前だけ
    static func line(_ entry: Entry) -> String {
        let when = entry.isTomorrow ? L("明日", "Tomorrow") : L("今日", "Today")
        var parts = [when, entry.spot.name]
        if let golden = entry.eveningGolden { parts.append(L("ゴールデンアワー \(golden)", "Golden hour \(golden)")) }
        if let sunset = entry.sunset { parts.append(L("日の入り \(sunset)", "Sunset \(sunset)")) }
        return parts.joined(separator: " · ")
    }

    static func seasonLabel(_ season: String) -> String {
        switch season {
        case "spring": return L("春", "Spring")
        case "summer": return L("夏", "Summer")
        case "autumn": return L("秋", "Autumn")
        default: return L("冬", "Winter")
        }
    }

    private static func shorten(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= guideLimit ? trimmed : String(trimmed.prefix(guideLimit)) + "…"
    }
}
