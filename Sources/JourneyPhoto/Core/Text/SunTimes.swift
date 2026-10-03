import Foundation

/// **その場所・その日の光の時刻**（日の出・日の入り・ゴールデンアワー・ブルーアワー）。
/// 通信しない（座標と日付から計算する）。**Web の `lib/utils/sunTimes.ts` と同じ式・同じ試験の値**。
///
/// 使い道（owner・2026-09-30）: 旅行プランの前日から最終日まで、その日と翌日に予定した撮影スポットの
/// 光の時刻をホームの札に出す（毎日全員にではなく、行く人にだけ）。
///
/// 式は日の出の方程式（NOAA の簡略式）。誤差はおおむね1〜2分で、座標は約1km に丸めてある（台帳）。
///
///  - 日の出・日の入り   太陽の上端が地平線（高度 −0.833°）
///  - ゴールデンアワー   高度 +6°〜−4°（Web は「マジックアワー」と呼ぶ。アプリは 2026-10-03 owner 判断で揃えた）
///  - ブルーアワー       高度 −4°〜−6°
///
/// 白夜・極夜で太陽がその高度を通らない日は nil（作り話の時刻を出さない）。
///
/// **方角（2026-10-03・撮影スポットの「光の時刻」）**: 日の出・日の入りの方位角を、北から時計回りの度で持つ
/// （東 90°・南 180°・西 270°）。同じ赤緯から球面三角の式で出す（Web の `sunTimes.ts` にはまだ無い）。
/// 国立天文台の暦（東京の夏至・冬至・春分、根室の夏至、鹿児島の冬至）と 0.5° 以内で合う（`SpotLightTests`。
/// 時刻は ±2分・方角は ±2° で判定し、方角は 0.5° でも見る）。
struct SunTimes: Equatable {
    struct Span: Equatable {
        let start: Date?
        let end: Date?
    }

    let sunrise: Date?
    let sunset: Date?
    let morningBlue: Span
    let morningGolden: Span
    let eveningGolden: Span
    let eveningBlue: Span
    /// 日の出の方位角（度・北から時計回り）。日が昇らない／沈まない日は nil
    var sunriseAzimuth: Double? = nil
    /// 日の入りの方位角（度・北から時計回り）。日が昇らない／沈まない日は nil
    var sunsetAzimuth: Double? = nil

    private static let rad = Double.pi / 180
    private static let j2000 = 2451545.0
    private static let jdUnixEpoch = 2440587.5

    private static func toJulian(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + jdUnixEpoch }
    private static func fromJulian(_ jd: Double) -> Date {
        // Web は Date をミリ秒に丸める。秒の端数で分の表示がずれないように同じく丸める
        Date(timeIntervalSince1970: ((jd - jdUnixEpoch) * 86_400_000).rounded() / 1000)
    }

    /// その暦日（`ymd` は "YYYY-MM-DD"・その場所の暦）の南中と赤緯
    private static func solarDay(_ ymd: String, lng: Double) -> (transit: Double, decl: Double)? {
        guard lng.isFinite, let (y, m, d) = TakenDay.ymd(ymd) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let noon = utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) else { return nil }
        let n = (toJulian(noon) - j2000).rounded() + 0.0008
        let jStar = n - lng / 360
        let M = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let Mr = M * rad
        let C = 1.9148 * sin(Mr) + 0.02 * sin(2 * Mr) + 0.0003 * sin(3 * Mr)
        let lambda = (M + C + 180 + 102.9372).truncatingRemainder(dividingBy: 360) * rad
        let transit = j2000 + jStar + 0.0053 * sin(Mr) - 0.0069 * sin(2 * lambda)
        let decl = asin(sin(lambda) * sin(23.4397 * rad))
        return (transit, decl)
    }

    /// 太陽がその高度（度）を通る、南中から何日ぶん前後か。通らなければ nil
    private static func hourAngleDays(_ altitude: Double, lat: Double, decl: Double) -> Double? {
        let phi = lat * rad
        let cosW = (sin(altitude * rad) - sin(phi) * sin(decl)) / (cos(phi) * cos(decl))
        guard cosW.isFinite, cosW >= -1, cosW <= 1 else { return nil }
        return acos(cosW) / (2 * Double.pi)
    }

    /// 太陽がその高度（度）にあるときの、朝側の方位角（度・北から時計回り）。夕方側は 360 から引いた値。
    /// 通らなければ nil
    private static func risingAzimuth(_ altitude: Double, lat: Double, decl: Double) -> Double? {
        let phi = lat * rad, h = altitude * rad
        let cosA = (sin(decl) - sin(phi) * sin(h)) / (cos(phi) * cos(h))
        guard cosA.isFinite, cosA >= -1, cosA <= 1 else { return nil }
        return acos(cosA) / rad
    }

    /// その暦日の太陽の高さの幅（度）: 南中の高さと、その反対側（Web の `sunAltitudeRange` と同じ）。
    /// 時刻が出ない理由を言い分けるのに使う（白夜＝いちばん低くても沈まない・終日＝いちばん高くても 6° に届かない）
    static func altitudeRange(_ ymd: String, lat: Double, lng: Double) -> (max: Double, min: Double)? {
        guard lat.isFinite, abs(lat) <= 90, let day = solarDay(ymd, lng: lng) else { return nil }
        let decl = day.decl / rad
        return (90 - abs(lat - decl), abs(lat + decl) - 90)
    }

    /// 日付が読めない・緯度が範囲外なら nil
    static func compute(_ ymd: String, lat: Double, lng: Double) -> SunTimes? {
        guard lat.isFinite, abs(lat) <= 90, let day = solarDay(ymd, lng: lng) else { return nil }
        func at(_ altitude: Double, _ side: Double) -> Date? {
            hourAngleDays(altitude, lat: lat, decl: day.decl).map { fromJulian(day.transit + side * $0) }
        }
        // 日の出・日の入りの時刻が出る日だけ方角を出す（時刻の無い日に方角だけ言わない）
        let rises = hourAngleDays(-0.833, lat: lat, decl: day.decl) != nil
        let azimuth = rises ? risingAzimuth(-0.833, lat: lat, decl: day.decl) : nil
        return SunTimes(
            sunrise: at(-0.833, -1),
            sunset: at(-0.833, 1),
            morningBlue: Span(start: at(-6, -1), end: at(-4, -1)),
            morningGolden: Span(start: at(-4, -1), end: at(6, -1)),
            eveningGolden: Span(start: at(6, 1), end: at(-4, 1)),
            eveningBlue: Span(start: at(-4, 1), end: at(-6, 1)),
            sunriseAzimuth: azimuth,
            sunsetAzimuth: azimuth.map { 360 - $0 }
        )
    }

    /// 国（台帳の `region.country`・日本語表記）→ 時刻帯。**Web の `COUNTRY_TIME_ZONES` と同じ表**。
    /// 無い国は nil——その土地の時計で言えないので時刻を出さない（端末の時計で言うと旅先で読み違える）
    static let countryTimeZones: [String: String] = [
        "日本": "Asia/Tokyo",
        "フランス": "Europe/Paris",
        "スペイン": "Europe/Madrid",
        "フィンランド": "Europe/Helsinki",
        "イタリア": "Europe/Rome",
        "ドイツ": "Europe/Berlin",
        "チェコ": "Europe/Prague",
        "スイス": "Europe/Zurich",
        "ギリシャ": "Europe/Athens",
        "イギリス": "Europe/London",
        "オランダ": "Europe/Amsterdam",
        "ポルトガル": "Europe/Lisbon",
        "クロアチア": "Europe/Zagreb",
        "バチカン市国": "Europe/Vatican",
        "オーストリア": "Europe/Vienna",
    ]

    /// 国が無い行は日本
    static func timeZone(forCountry country: String?) -> TimeZone? {
        let key = (country ?? "").trimmingCharacters(in: .whitespaces)
        return countryTimeZones[key.isEmpty ? "日本" : key].flatMap { TimeZone(identifier: $0) }
    }

    /// その時刻帯での "HH:MM"（24時間）。nil は nil のまま（画面は行ごと出さない）
    static func clock(_ date: Date?, in zone: TimeZone) -> String? {
        guard let date else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        let parts = c.dateComponents([.hour, .minute], from: date)
        guard let h = parts.hour, let m = parts.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// "HH:MM–HH:MM"。どちらかの端が無ければ nil
    static func span(_ s: Span, in zone: TimeZone) -> String? {
        guard let a = clock(s.start, in: zone), let b = clock(s.end, in: zone) else { return nil }
        return "\(a)–\(b)"
    }
}
