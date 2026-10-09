import Foundation

/// 光と天気の知らせ（Pro・デザインの板 LightAlert・2026-10-09）の**画面に出すものを決める純粋な部分**。
/// 通信は `LightForecastService`、画面は `LightForecastView`。
///
/// ## 一覧「行きたい場所の光（今週）」の札
///
/// **場所ごとに1枚。** 7日 × 朝焼け・夕焼け・夜景のうち、その場所でいちばん良いもの（`best`）を出す:
///
///  - 左: 色の四角（見込みの種類の色・`Tone`）
///  - 名前・いつ（「明日 · 日の出 5:42」）
///  - 右: 天気（「晴れ」）と見込み（「朝焼け 見込み高」。低いときは板どおり「見込み低」だけ）
///
/// いちばん良いもの = 見込みが高い → 早い日 → 朝・夕・夜の順。**もう過ぎた時間帯は選ばない**
/// （今日の朝焼けを夕方に勧めない）。
///
/// ## 並べ方（`cards`）
///
/// 板の並びは「明日 → 土 → 日 → 月」の**日の順**。見込みの高い順にすると、来週の「高」が明日の「中」より
/// 上に来て、近い予定が下に沈む。だから**札の「いつ」の早い順**（同じなら朝・夕・夜の順、同じならサーバーの
/// 順＝「行きたい」に新しく入れた方）。予報の無い場所は後ろ。
///
/// ## 真鍮の縁（`Card.isBest`）
///
/// 2026-10-09 判断: **見込み「高」のうち、いちばん早い1枚だけ。** 「高」が1つも無い週は縁を付けない
/// ——「中」や「低」を「いちばん良い」と飾ると、良い日に見える（見込みは目安で、知らせも「高」だけで送る・
/// サーバーの `pickAlert`）。
enum LightForecastText {

    // MARK: - 時間帯

    /// 朝焼け・夕焼け・夜景。並びの順（朝 → 夕 → 夜）
    enum Moment: Int, CaseIterable, Equatable {
        case morning, evening, night

        /// 「朝焼け」「夕焼け」「夜景」
        var word: String {
            switch self {
            case .morning: return L("朝焼け", "Morning glow")
            case .evening: return L("夕焼け", "Evening glow")
            case .night: return L("夜景", "Night view")
            }
        }

        /// その時間帯の目印の時刻の名前（「日の出」「日の入り」「ブルーアワー」）
        var eventWord: String {
            switch self {
            case .morning: return L("日の出", "Sunrise")
            case .evening: return L("日の入り", "Sunset")
            case .night: return L("ブルーアワー", "Blue hour")
            }
        }

        func outlook(in day: LightForecast.Day) -> LightForecast.Outlook? {
            switch self {
            case .morning: return day.morning
            case .evening: return day.evening
            case .night: return day.night
            }
        }

        /// 目印の時刻（朝は日の出・夕は日の入り・夜は夕方のブルーアワーの始まり）
        func clock(in day: LightForecast.Day) -> LightForecast.Clock? {
            switch self {
            case .morning: return day.sunrise
            case .evening: return day.sunset
            case .night: return day.eveningBlue?.start
            }
        }
    }

    // MARK: - 言葉

    static func weatherWord(_ weather: LightForecast.Weather) -> String {
        switch weather {
        case .clear: return L("晴れ", "Clear")
        case .partlyCloudy: return L("くもり時々晴れ", "Partly cloudy")
        case .cloudy: return L("くもり", "Cloudy")
        case .rain: return L("雨", "Rain")
        }
    }

    /// 「見込み高」（板の書き方）
    static func chanceWord(_ chance: LightForecast.Chance) -> String {
        switch chance {
        case .high: return L("見込み高", "High chance")
        case .mid: return L("見込み中", "Fair chance")
        case .low: return L("見込み低", "Low chance")
        }
    }

    /// 札の右下: 「朝焼け 見込み高」。**低いときは「見込み低」だけ**（板の4枚目）
    static func kindLine(_ moment: Moment, _ chance: LightForecast.Chance) -> String {
        chance == .low ? chanceWord(.low) : L("\(moment.word) \(chanceWord(chance))", "\(moment.word) · \(chanceWord(chance))")
    }

    /// "05:42" → "5:42"（板の書き方・サーバーの知らせの文面と同じ）
    static func shortClock(_ clock: String) -> String {
        guard clock.count == 5, clock.hasPrefix("0"), clock.dropFirst(2).hasPrefix(":") else { return clock }
        return String(clock.dropFirst())
    }

    /// 「今日」「明日」、それより先は曜日（「土曜」）。7日の中なので曜日だけで分かる。
    /// 読めない日付はそのまま
    static func dayWord(_ ymd: String, today: String) -> String {
        guard let offset = dayOffset(ymd, from: today) else { return ymd }
        switch offset {
        case 0: return L("今日", "Today")
        case 1: return L("明日", "Tomorrow")
        default:
            guard let weekday = weekday(ymd) else { return ymd }
            let ja = ["日", "月", "火", "水", "木", "金", "土"][weekday - 1]
            let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday - 1]
            return L("\(ja)曜", en)
        }
    }

    /// 暦の日数の差（`to` − `from`）。どちらかが読めなければ nil
    static func dayOffset(_ to: String, from: String) -> Int? {
        guard let a = utcDate(from), let b = utcDate(to) else { return nil }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    private static func utcDate(_ ymd: String) -> Date? {
        guard let (y, m, d) = TakenDay.ymd(ymd) else { return nil }
        return utcCalendar.date(from: DateComponents(year: y, month: m, day: d))
    }

    /// 1（日）〜7（土）
    private static func weekday(_ ymd: String) -> Int? {
        utcDate(ymd).map { utcCalendar.component(.weekday, from: $0) }
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// その場所の「今日」（その土地の暦）。時刻帯が読めなければ、サーバーが「今日」として返した最初の日
    static func today(for place: LightForecast.Place, now: Date) -> String? {
        if let name = place.timeZone, let zone = TimeZone(identifier: name),
           let ymd = SpotLight.ymd(offset: 0, from: now, in: zone) {
            return ymd
        }
        return place.days.first?.date
    }

    // MARK: - いちばん良い時間帯

    /// 札に出す1つ（場所・日・時間帯）
    struct Pick: Equatable {
        let day: LightForecast.Day
        /// 今日から何日先か
        let offset: Int
        let moment: Moment
        /// 見込み。予報の無い場所では nil（光の時刻だけ）
        let outlook: LightForecast.Outlook?
    }

    /// まだ来ていない時間帯か。**目印の時刻を過ぎたら選ばない**（読めない時刻は日付だけで見る）
    private static func isAhead(_ moment: Moment, in day: LightForecast.Day, offset: Int, now: Date) -> Bool {
        guard offset >= 0 else { return false }
        guard offset == 0 else { return true }
        guard let at = moment.clock(in: day)?.at, let date = NotificationGroups.parse(at) else { return true }
        return date > now
    }

    /// これから来る時間帯（日の順・朝夕夜の順）
    static func upcoming(_ place: LightForecast.Place, now: Date) -> [Pick] {
        guard let today = today(for: place, now: now) else { return [] }
        var out: [Pick] = []
        for day in place.days {
            guard let offset = dayOffset(day.date, from: today) else { continue }
            for moment in Moment.allCases where isAhead(moment, in: day, offset: offset, now: now) {
                out.append(Pick(day: day, offset: offset, moment: moment, outlook: moment.outlook(in: day)))
            }
        }
        return out.sorted { ($0.offset, $0.moment.rawValue) < ($1.offset, $1.moment.rawValue) }
    }

    /// その場所でいちばん良い時間帯。見込みが1つも無ければ、**次の日の出か日の入り**（光の時刻だけ出す）
    static func best(for place: LightForecast.Place, now: Date) -> Pick? {
        let ahead = upcoming(place, now: now)
        var best: Pick?
        for pick in ahead {
            guard let outlook = pick.outlook else { continue }
            // 厳密に良いときだけ入れ替える（同じ見込みなら早い方が残る）
            if best == nil || outlook.chance.rank > (best?.outlook?.chance.rank ?? -1) { best = pick }
        }
        if let best { return best }
        return ahead.first { $0.moment != .night && $0.moment.clock(in: $0.day) != nil }
    }

    // MARK: - 札

    /// 色の四角の色（板の4色。予報の無い場所は暗い灰）
    enum Tone: Equatable {
        case morning, evening, night, low, none

        /// 板 LightAlert の `tone`
        var hex: UInt32 {
            switch self {
            case .morning: return 0x4A3B32
            case .evening: return 0x2F3A45
            case .night: return 0x27352C
            case .low: return 0x3D3346
            case .none: return 0x222222
            }
        }
    }

    struct Card: Equatable, Identifiable {
        let id: String
        let name: String
        /// 「明日 · 日の出 5:42」
        let when: String
        /// 右上: 天気（「晴れ」）。予報の無い場所は「予報なし」
        let weather: String
        /// 右下: 「朝焼け 見込み高」
        let kind: String
        let tone: Tone
        /// 札の見込み（予報の無い場所は nil）
        let chance: LightForecast.Chance?
        /// 真鍮の縁（見込み「高」のうちいちばん早い1枚）
        var isBest: Bool
        /// 並べるための「いつ」（予報の無い場所は後ろ）
        fileprivate let sortKey: (Int, Int, Int)

        static func == (a: Card, b: Card) -> Bool {
            a.id == b.id && a.name == b.name && a.when == b.when && a.weather == b.weather
                && a.kind == b.kind && a.tone == b.tone && a.chance == b.chance && a.isBest == b.isBest
        }

        /// 読み上げ。**縁の色だけで「いちばん」を伝えない**
        var accessibilityLabel: String {
            let head = isBest ? L("今週いちばんの見込み、", "Best this week, ") : ""
            return head + [name, when, weather, kind].filter { !$0.isEmpty }.joined(separator: L("、", ", "))
        }
    }

    static func card(for place: LightForecast.Place, now: Date) -> Card {
        let today = today(for: place, now: now) ?? ""
        guard let pick = best(for: place, now: now) else {
            return Card(id: place.id, name: place.shownName, when: L("今週の光の時刻はありません", "No sun times this week"),
                        weather: L("予報なし", "No forecast"), kind: "", tone: .none, chance: nil, isBest: false,
                        sortKey: (2, 0, 0))
        }
        let when = whenLine(pick, today: today)
        guard let outlook = pick.outlook else {
            return Card(id: place.id, name: place.shownName, when: when,
                        weather: L("予報なし", "No forecast"), kind: L("光の時刻だけ", "Sun times only"),
                        tone: .none, chance: nil, isBest: false, sortKey: (1, pick.offset, pick.moment.rawValue))
        }
        let tone: Tone
        if outlook.chance == .low {
            tone = .low
        } else {
            switch pick.moment {
            case .morning: tone = .morning
            case .evening: tone = .evening
            case .night: tone = .night
            }
        }
        return Card(id: place.id, name: place.shownName, when: when,
                    weather: weatherWord(outlook.weather), kind: kindLine(pick.moment, outlook.chance),
                    tone: tone, chance: outlook.chance, isBest: false, sortKey: (0, pick.offset, pick.moment.rawValue))
    }

    /// 「明日 · 日の出 5:42」。時刻が無ければ「明日 · 日の出」
    static func whenLine(_ pick: Pick, today: String) -> String {
        var event = pick.moment.eventWord
        if let clock = pick.moment.clock(in: pick.day)?.clock { event += " " + shortClock(clock) }
        return "\(dayWord(pick.day.date, today: today)) · \(event)"
    }

    /// 一覧の札（並べ方と真鍮の縁は上の注記）
    static func cards(_ forecast: LightForecast, now: Date) -> [Card] {
        let made = forecast.places.enumerated().map { (index: $0.offset, card: card(for: $0.element, now: now)) }
        var sorted = made.sorted { a, b in
            if a.card.sortKey != b.card.sortKey { return a.card.sortKey < b.card.sortKey }
            return a.index < b.index
        }.map(\.card)
        // 「高」のうちいちばん早い1枚（並べたあとの先頭から探す＝早い順）
        if let first = sorted.firstIndex(where: { $0.chance == .high }) {
            sorted[first].isBest = true
        }
        return sorted
    }

    // MARK: - 札を開いたときの7日

    /// 1日ぶんの行（「明日」と、朝焼け・夕焼け・夜景の3つ）
    struct DayLine: Equatable, Identifiable {
        let id: String
        let title: String
        let items: [Item]

        struct Item: Equatable {
            /// 「日の出 5:42」
            let event: String
            /// 「朝焼け 見込み高 · 晴れ」。予報の無い時間帯は「予報なし」
            let outlook: String
            let chance: LightForecast.Chance?
        }
    }

    /// 今日から先の日を、朝・夕・夜の3行ずつ（過ぎた時間帯も日の中には残す——その日の姿として読む）
    static func week(_ place: LightForecast.Place, now: Date) -> [DayLine] {
        guard let today = today(for: place, now: now) else { return [] }
        return place.days.compactMap { day in
            guard let offset = dayOffset(day.date, from: today), offset >= 0 else { return nil }
            let items: [DayLine.Item] = Moment.allCases.compactMap { moment in
                let clock = moment.clock(in: day)
                let outlook = moment.outlook(in: day)
                guard clock != nil || outlook != nil else { return nil }
                var event = moment.eventWord
                if let clock { event += " " + shortClock(clock.clock) }
                let text = outlook.map { "\(moment.word) \(chanceWord($0.chance)) · \(weatherWord($0.weather))" }
                    ?? "\(moment.word) " + L("予報なし", "no forecast")
                return DayLine.Item(event: event, outlook: text, chance: outlook?.chance)
            }
            guard !items.isEmpty else { return nil }
            let title = offset <= 1 ? dayWord(day.date, today: today) : dateWithWeekday(day.date)
            return DayLine(id: day.date, title: title, items: items)
        }
    }

    /// 「10月11日（土）」
    static func dateWithWeekday(_ ymd: String) -> String {
        SpotLight.dateLabel(ymd, offset: 99, todayYMD: ymd)
    }

    // MARK: - 注記・出典

    /// 板の注記（サーバーが返さないときの文言）
    static var defaultNote: String {
        L("天気は外部の予報から。光の時刻はアプリで計算。見込みは目安で、外れることがあります。",
          "Weather comes from an outside forecast; sun times are calculated in the app. Chances are a guide and can be wrong.")
    }

    /// 画面の注記。**英語の端末にはサーバーの日本語を出さない**（サーバーは日本語だけ返す）
    static func note(_ forecast: LightForecast) -> String {
        guard Locale.preferredAppLanguage != "en", let note = forecast.note, !note.isEmpty else { return defaultNote }
        return note
    }

    // MARK: - 空のとき

    enum Empty: Equatable {
        /// 「行きたい」が1つも無い
        case noWishes
        /// 「行きたい」はあるが、光を出せる撮影スポットが無い（撮影地＝地名は決まった座標を持たない）
        case noSpots
    }

    /// - Parameter wishlist: 手元の「行きたい」の鍵（`WishlistStore.spotIds`）
    static func empty(wishlist: Set<String>) -> Empty {
        wishlist.isEmpty ? .noWishes : .noSpots
    }

    static func emptyTitle(_ empty: Empty) -> String {
        switch empty {
        case .noWishes: return L("行きたい場所がまだありません", "No places on your wishlist yet")
        case .noSpots: return L("光を出せる撮影スポットがありません", "No photo spots to forecast")
        }
    }

    static func emptyBody(_ empty: Empty) -> String {
        switch empty {
        case .noWishes:
            return L("撮影スポットの画面で「行きたい」を押すと、ここに今週の光と天気が並びます。",
                     "Tap \u{201C}Want to go\u{201D} on a photo spot, and this week\u{2019}s light and weather will appear here.")
        case .noSpots:
            return L("地名で入れた「行きたい」は決まった位置が無いので、光の時刻を出せません。撮影スポットの画面で「行きたい」を押してください。",
                     "Places saved by name have no fixed location, so sun times can\u{2019}t be worked out. Tap \u{201C}Want to go\u{201D} on a photo spot.")
        }
    }

    // MARK: - 読めなかったとき

    enum Failure: Equatable {
        /// 403（Pro でない）。Pro の案内へ
        case notPro
        /// 503（天気の鍵が無い・予報を読めない）
        case unavailable
        /// 圏外
        case unreachable
        /// ログインしていない・切れた
        case signedOut
        case other(String)
    }

    static func failure(for error: Error) -> Failure {
        guard let api = error as? APIError else { return .other(Labels.Common.loadFailed) }
        switch api {
        case .unreachable: return .unreachable
        case .notAuthenticated: return .signedOut
        case .server(let status, _) where status == 401: return .signedOut
        case .server(let status, _) where status == 403: return .notPro
        case .server(let status, _) where status == 503: return .unavailable
        default: return .other(api.errorDescription ?? Labels.Common.loadFailed)
        }
    }

    static func failureTitle(_ failure: Failure) -> String {
        switch failure {
        case .notPro: return L("Pro の機能です", "A Pro feature")
        case .unavailable: return L("いまは天気の予報を読めません", "Forecasts are unavailable right now")
        case .unreachable: return L("圏外のため読み込めませんでした", "You\u{2019}re offline")
        case .signedOut: return Labels.Common.signInRequired
        case .other: return Labels.Common.loadFailed
        }
    }

    static func failureBody(_ failure: Failure) -> String {
        switch failure {
        case .notPro:
            return L("行きたい場所の今週の光と天気、前の晩の知らせは Journey Photo Pro で使えます。",
                     "This week\u{2019}s light and weather for your wishlist, and the evening-before alert, come with Journey Photo Pro.")
        case .unavailable:
            return L("天気の予報の受け取り先に繋がっていません。しばらくしてからもう一度開いてください。",
                     "We can\u{2019}t reach the weather service. Please try again later.")
        case .unreachable:
            return L("電波のあるところで、もう一度お試しください。",
                     "Please try again with a signal.")
        case .signedOut:
            return L("ログインし直してから、もう一度開いてください。", "Please sign in again, then reopen this page.")
        case .other(let message):
            return message
        }
    }

    // MARK: - 画面写真のための見本（DEBUG だけ）

    /// 画面写真の試験（`ScreenshotTests`）だけが、Pro でなくても一覧を見るための鍵。
    /// `-JPLightForecastPreview sample` で見本、`empty` で空の姿。**Release では必ず nil**
    /// （`ComposeGuideAccess` と同じ決まり）
    static let previewDefaultsKey = "JPLightForecastPreview"

    enum Preview: String { case sample, empty }

    static var preview: Preview? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: previewDefaultsKey).flatMap(Preview.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// 見本（今日から4日・場所の名前は伏せ字）。**本物の予報ではない**
    static func sample(now: Date) -> LightForecast {
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        func day(_ offset: Int) -> String { SpotLight.ymd(offset: offset, from: now, in: zone) ?? "2026-10-10" }
        func clock(_ text: String) -> LightForecast.Clock { .init(at: "2100-01-01T00:00:00.000Z", clock: text) }
        func place(_ n: Int, _ days: [LightForecast.Day]) -> LightForecast.Place {
            .init(key: "SPOT-sample-\(n)", slug: "sample-\(n)", name: L("撮影スポット \(n)", "Photo spot \(n)"),
                  timeZone: "Asia/Tokyo", forecast: true, days: days)
        }
        return LightForecast(places: [
            place(1, [.init(date: day(1), sunrise: clock("05:42"), sunset: clock("17:22"),
                            morning: .init(weather: .clear, chance: .high),
                            evening: .init(weather: .partlyCloudy, chance: .mid))]),
            place(2, [.init(date: day(2), sunrise: clock("05:43"), sunset: clock("17:21"),
                            morning: .init(weather: .cloudy, chance: .low),
                            evening: .init(weather: .partlyCloudy, chance: .mid))]),
            place(3, [.init(date: day(3), sunrise: clock("05:44"), sunset: clock("17:20"),
                            eveningBlue: .init(start: clock("17:40"), end: clock("18:00")),
                            morning: .init(weather: .rain, chance: .low),
                            evening: .init(weather: .cloudy, chance: .low),
                            night: .init(weather: .clear, chance: .high))]),
            place(4, [.init(date: day(4), sunrise: clock("05:45"), sunset: clock("17:19"),
                            morning: .init(weather: .rain, chance: .low))]),
        ], note: nil)
    }
}
