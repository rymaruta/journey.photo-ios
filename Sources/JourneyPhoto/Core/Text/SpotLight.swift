import Foundation

/// 撮影スポットの画面の「**光の時刻**」の節（2026-10-03）。写真が無い場所でも役に立つ、
/// その日の日の出・日の入りの時刻と方角、ゴールデンアワー・ブルーアワーの時間帯。
///
/// **計算は端末の中だけ**（`SunTimes`・NOAA の簡略式）。通信しない・有料の API を使わない。
///
/// ## 決まりごと
///
///  - 時刻は**その土地の時計**。時刻帯は台帳の国から引く（`SunTimes.timeZone(forCountry:)`・
///    日本は Asia/Tokyo）。表に無い国は**端末の時刻帯で出し、そう書く**（`Zone.isDevice`）
///  - 日の出・日の入りの方角は「東北東 67°」（16方位＋北から時計回りの度）
///  - ゴールデンアワーは太陽の高さ +6°〜−4°（Web とホームの札が「マジックアワー」と呼ぶ幅と同じ）、
///    ブルーアワーは −4°〜−6°
///  - 白夜・極夜で時刻が無い日は、**作り話の時刻を出さず**「白夜（沈まない）」「極夜（昇らない）」と言う
///  - 台帳の `timeOfDayGuide` のうち、夜明け・朝は「朝」の段、夕方の斜光・日没後は「夕」の段に並べる
///    （日中・夜は撮影ガイドの時間帯に残す）
enum SpotLight {

    /// 1行: 札（日の出・ゴールデンアワー…）・値（時刻か言い分け）・添え（方角）
    struct Row: Equatable {
        let label: String
        let value: String
        var detail: String? = nil
    }

    /// 朝・夕の段
    struct Block: Equatable {
        let title: String
        /// 朝の段か（台帳の時間帯の文をどちらに並べるかに使う）
        let isMorning: Bool
        let rows: [Row]
    }

    /// 時刻を言う時刻帯。`isDevice` は台帳の国から引けず、端末の時刻帯で代わりに出したとき
    struct Zone: Equatable {
        let timeZone: TimeZone
        let isDevice: Bool
    }

    /// 日付を送れる幅（今日から前後この日数まで）
    static let maxOffset = 366

    private static let horizon = -0.833

    // MARK: - 時刻帯・日付

    static func zone(country: String?, device: TimeZone = .current) -> Zone {
        if let zone = SunTimes.timeZone(forCountry: country) { return Zone(timeZone: zone, isDevice: false) }
        return Zone(timeZone: device, isDevice: true)
    }

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// その時刻帯での「今日から `offset` 日」の暦日 "YYYY-MM-DD"
    static func ymd(offset: Int, from now: Date, in zone: TimeZone) -> String? {
        let c = calendar(zone)
        guard let day = c.date(byAdding: .day, value: offset, to: now) else { return nil }
        let p = c.dateComponents([.year, .month, .day], from: day)
        guard let y = p.year, let m = p.month, let d = p.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// 日付の札: 「10月3日（土）· 今日」。年が今日と違えば年から（「2027年1月5日（火）」）
    static func dateLabel(_ ymd: String, offset: Int, todayYMD: String) -> String {
        guard let (y, m, d) = TakenDay.ymd(ymd) else { return ymd }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let weekday = utc.date(from: DateComponents(year: y, month: m, day: d))
            .map { utc.component(.weekday, from: $0) } ?? 1
        let ja = ["日", "月", "火", "水", "木", "金", "土"][(weekday - 1) % 7]
        let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(weekday - 1) % 7]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let sameYear = TakenDay.ymd(todayYMD)?.0 == y
        var label = sameYear
            ? L("\(m)月\(d)日（\(ja)）", "\(en), \(months[m - 1]) \(d)")
            : L("\(y)年\(m)月\(d)日（\(ja)）", "\(en), \(months[m - 1]) \(d), \(y)")
        switch offset {
        case 0: label += L(" · 今日", " · Today")
        case 1: label += L(" · 明日", " · Tomorrow")
        case -1: label += L(" · 昨日", " · Yesterday")
        default: break
        }
        return label
    }

    // MARK: - 方角

    /// 16方位（北から時計回り）
    static func compass(_ degrees: Double) -> String {
        let ja = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                  "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]
        let en = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                  "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let i = Int((normalized / 22.5).rounded()) % 16
        return L(ja[i], en[i])
    }

    /// 「東北東 67°」。度は整数に丸める（台帳の座標は約1km に丸めてあり、小数は意味を持たない）
    static func direction(_ degrees: Double?) -> String? {
        guard let degrees, degrees.isFinite else { return nil }
        let whole = Int(degrees.rounded()) % 360
        return "\(compass(degrees)) \(whole)°"
    }

    // MARK: - 段を組む

    /// "HH:MM" どうしで、後ろの方が早ければ翌日（`TripLight` と同じ言い方）
    private static func nextDay(_ earlier: String, _ later: String) -> String {
        later < earlier ? L("翌\(later)", "\(later) (+1)") : later
    }

    /// 時間帯 "HH:MM–HH:MM"。片方の端しか無ければ、時刻を作らず言葉で開いたままにする
    /// （「HH:MM–（翌朝まで）」「（前夜から）–HH:MM」——白夜の前後で太陽がその高さまで下がらない日）。
    /// どちらも無ければ nil
    static func spanText(_ span: SunTimes.Span, in zone: TimeZone) -> String? {
        let a = SunTimes.clock(span.start, in: zone)
        let b = SunTimes.clock(span.end, in: zone)
        switch (a, b) {
        case let (a?, b?): return "\(a)–\(nextDay(a, b))"
        case let (a?, nil): return L("\(a)–（翌朝まで）", "\(a)– (until morning)")
        case let (nil, b?): return L("（前夜から）–\(b)", "(from the night before) –\(b)")
        default: return nil
        }
    }

    /// 太陽が一日中その帯の上端まで上がらない日は、朝の帯の始まりと夕の帯の終わりが
    /// 昼をまたいで1本につながる（朝の終わり・夕の始まりが無い）。そのときの1本
    private static func joinedAcrossNoon(_ morning: SunTimes.Span, _ evening: SunTimes.Span) -> SunTimes.Span? {
        guard morning.start != nil, morning.end == nil, evening.start == nil, evening.end != nil else { return nil }
        return SunTimes.Span(start: morning.start, end: evening.end)
    }

    /// 日が昇らない／沈まない日の言い分け（同じ赤緯・同じ式なので、時刻が無ければ必ずどちらか）
    private static func noSunWord(_ altitude: (max: Double, min: Double)?) -> String? {
        guard let altitude else { return nil }
        if altitude.min > horizon { return L("白夜（沈まない）", "Midnight sun (no sunset)") }
        if altitude.max <= horizon { return L("極夜（昇らない）", "Polar night (no sunrise)") }
        return nil
    }

    /// その日の朝・夕の段。行が1つも無い段は落とす
    ///
    ///  - 極夜（日が昇らない）の日はゴールデンアワーを出さない（Web の表・ホームの札と同じ言い分け）
    ///  - 昼のあいだ太陽が 6° まで上がらない日は、ゴールデンアワーが朝から夕まで1本（「一日中」と添える）。
    ///    ブルーアワーも −4° まで上がらない日は同じく1本にする
    static func blocks(_ times: SunTimes, altitude: (max: Double, min: Double)?, in zone: TimeZone) -> [Block] {
        let golden = L("ゴールデンアワー", "Golden hour")
        let blue = L("ブルーアワー", "Blue hour")
        let noSun = noSunWord(altitude)
        let polarNight = altitude.map { $0.max <= horizon } ?? false
        let goldenJoined = polarNight ? nil : joinedAcrossNoon(times.morningGolden, times.eveningGolden)
        let blueJoined = joinedAcrossNoon(times.morningBlue, times.eveningBlue)

        var morning: [Row] = []
        if let rise = SunTimes.clock(times.sunrise, in: zone) {
            morning.append(Row(label: L("日の出", "Sunrise"), value: rise, detail: direction(times.sunriseAzimuth)))
        } else if let noSun {
            morning.append(Row(label: L("日の出", "Sunrise"), value: noSun))
        }
        if let s = spanText(blueJoined ?? times.morningBlue, in: zone) { morning.append(Row(label: blue, value: s)) }
        if let joined = goldenJoined {
            if let s = spanText(joined, in: zone) {
                morning.append(Row(label: golden, value: s + L("（一日中・太陽が 6° より上がらない）", " (all day · sun stays below 6°)")))
            }
        } else if !polarNight, let s = spanText(times.morningGolden, in: zone) {
            morning.append(Row(label: golden, value: s))
        }

        var evening: [Row] = []
        if let set = SunTimes.clock(times.sunset, in: zone) {
            let rise = SunTimes.clock(times.sunrise, in: zone)
            evening.append(Row(label: L("日の入り", "Sunset"), value: rise.map { nextDay($0, set) } ?? set,
                               detail: direction(times.sunsetAzimuth)))
        } else if let noSun {
            evening.append(Row(label: L("日の入り", "Sunset"), value: noSun))
        }
        if goldenJoined == nil, !polarNight, let s = spanText(times.eveningGolden, in: zone) {
            evening.append(Row(label: golden, value: s))
        }
        if blueJoined == nil, let s = spanText(times.eveningBlue, in: zone) { evening.append(Row(label: blue, value: s)) }

        return [Block(title: L("朝", "Morning"), isMorning: true, rows: morning),
                Block(title: L("夕", "Evening"), isMorning: false, rows: evening)].filter { !$0.rows.isEmpty }
    }

    /// 座標と暦日から、その日の段（日付が読めない・緯度が範囲外なら空）
    static func blocks(_ ymd: String, lat: Double, lng: Double, in zone: TimeZone) -> [Block] {
        guard let times = SunTimes.compute(ymd, lat: lat, lng: lng) else { return [] }
        return blocks(times, altitude: SunTimes.altitudeRange(ymd, lat: lat, lng: lng), in: zone)
    }

    // MARK: - 台帳の時間帯の文

    /// 朝の段に並べる時間帯（夜明け・朝）
    static let morningTimes = ["dawn", "morning"]
    /// 夕の段に並べる時間帯（夕方の斜光・日没後）
    static let eveningTimes = ["goldenHour", "dusk"]

    /// 台帳の `timeOfDayGuide` を朝・夕に分ける（並びは `SpotBodyText.orderedTimes`）
    static func guides(_ list: [SpotBody.TimeOfDay]) -> (morning: [SpotBody.TimeOfDay], evening: [SpotBody.TimeOfDay]) {
        let ordered = SpotBodyText.orderedTimes(list)
        return (ordered.filter { morningTimes.contains($0.time) },
                ordered.filter { eveningTimes.contains($0.time) })
    }

    /// 光の時刻の節に出したぶんを除いた残り（日中・夜）。撮影ガイドの「時間帯」はこれだけ出す
    static func remainingTimes(_ list: [SpotBody.TimeOfDay]) -> [SpotBody.TimeOfDay] {
        SpotBodyText.orderedTimes(list).filter { !morningTimes.contains($0.time) && !eveningTimes.contains($0.time) }
    }

    // MARK: - 注記

    /// 節の下の注記。端末の時刻帯で代わりに出したときは、そう書く
    static func note(_ zone: Zone) -> String {
        let id = zone.timeZone.identifier
        let clock = zone.isDevice
            ? L("時刻はこの端末の時刻帯（\(id)）で表示しています。現地の時刻とは違うことがあります。",
                "Times are shown in this device's time zone (\(id)) and may differ from local time.")
            : (id == "Asia/Tokyo"
                ? L("時刻は日本時間。", "Times in Japan Standard Time.")
                : L("時刻は現地時間（\(id)）。", "Times in local time (\(id))."))
        return clock + L(
            "端末で計算した値です。ゴールデンアワーは太陽の高さが 6° から −4°、ブルーアワーは −4° から −6° の間。方角は北から時計回り。天気や山・建物の影は含みません。",
            " Calculated on this device. Golden hour is when the sun is between 6° and −4°, blue hour between −4° and −6°. Directions are measured clockwise from north. Weather and shadows from terrain or buildings are not included.")
    }
}
