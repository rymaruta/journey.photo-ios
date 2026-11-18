import Foundation

/// 二十四節気（共有の絵「暦（差し色）」・2026-11-18 owner「暦 差し色採用」）。
///
/// **固定の日付の表は使わず、太陽の黄経を計算して決める**（年ごとに節気の日は1日ずれる。2025 年の立春は 2/3、2026 年は 2/4）。
/// 黄経 315° が立春（1番目）、15° ごとに次。24個。
///
/// 太陽の黄経は VSOP87（地球・Meeus『Astronomical Algorithms』付録 III の切り詰めた表）から
/// 地心の黄経にし、FK5 への補正・章動（主な4項）・光行差を足した見かけの黄経。精度は角度で数秒（時刻で1分ほど）。
/// 国立天文台の暦要項（2025〜2027 年）の節気の時刻と、72個すべて ±1 分で合う（`SolarTermTests`）。
///
/// **2026-11-18 判断: その日の節気は、日本時間のその日の終わり（24 時）の黄経で決める。** 仕様は「正午の黄経」だったが、
/// 正午で決めると、午後に節気に入る日（2025 年の立春 2/3 23:10 など）が前の節気になり、国立天文台の暦要項・
/// ふつうのカレンダーの「節気の日」と1日ずれる（2025〜2027 年の 72 個のうち 34 個。模型の見本の 2026.11.07 立冬 18:52 も霜降になる。
/// 正午に替えて `SolarTermTests` を流して数えた）。日の終わりで決めると、節気に入った日がその節気になる
enum SolarTerm {

    struct Term: Equatable {
        /// 立春から数えた番号（1〜24）
        let number: Int
        /// 漢字の名前（寒露）。暦の字なので英語の画面でも漢字のまま
        let name: String
        /// 読みのラテン文字（KANRO）
        let latin: String
        /// 意味の一文（露が冷たく感じられるころ）
        let meaning: String

        /// 節気に入る太陽の黄経（度）
        var longitude: Double { (315 + Double(number - 1) * 15).truncatingRemainder(dividingBy: 360) }
    }

    /// 24行の表（立春から）
    static var all: [Term] {
        let rows: [(String, String, String)] = [
            ("立春", "RISSHUN", L("春のはじまり", "The start of spring")),
            ("雨水", "USUI", L("雪が雨に変わり、氷が解けはじめるころ", "Snow turns to rain")),
            ("啓蟄", "KEICHITSU", L("土の中の虫が目を覚ますころ", "Insects awaken")),
            ("春分", "SHUNBUN", L("昼と夜の長さがほぼ同じになるころ", "The spring equinox")),
            ("清明", "SEIMEI", L("草木が清らかに明るく芽吹くころ", "Pure and bright")),
            ("穀雨", "KOKUU", L("穀物をうるおす春の雨が降るころ", "Rain for the grain")),
            ("立夏", "RIKKA", L("夏のはじまり", "The start of summer")),
            ("小満", "SHOMAN", L("草木が育ち、満ちはじめるころ", "Plants begin to flourish")),
            ("芒種", "BOSHU", L("稲や麦の種をまくころ", "Time to sow the grain")),
            ("夏至", "GESHI", L("一年で昼がいちばん長いころ", "The summer solstice")),
            ("小暑", "SHOSHO", L("暑さが本格的になりはじめるころ", "The heat begins")),
            ("大暑", "TAISHO", L("一年でいちばん暑いころ", "The height of summer")),
            ("立秋", "RISSHU", L("秋のはじまり", "The start of autumn")),
            ("処暑", "SHOSHO", L("暑さがおさまるころ", "The heat eases")),
            ("白露", "HAKURO", L("草に白い露が宿るころ", "White dew on the grass")),
            ("秋分", "SHUBUN", L("昼と夜の長さがほぼ同じになるころ", "The autumn equinox")),
            ("寒露", "KANRO", L("露が冷たく感じられるころ", "The dew turns cold")),
            ("霜降", "SOKO", L("霜が降りはじめるころ", "The first frost")),
            ("立冬", "RITTO", L("冬のはじまり", "The start of winter")),
            ("小雪", "SHOSETSU", L("わずかに雪が降りはじめるころ", "The first light snow")),
            ("大雪", "TAISETSU", L("雪が本格的に降るころ", "Heavy snow")),
            ("冬至", "TOJI", L("一年で昼がいちばん短いころ", "The winter solstice")),
            ("小寒", "SHOKAN", L("寒さが厳しくなりはじめるころ", "The cold begins")),
            ("大寒", "DAIKAN", L("一年でいちばん寒いころ", "The depth of winter")),
        ]
        return rows.enumerated().map { Term(number: $0.offset + 1, name: $0.element.0, latin: $0.element.1,
                                            meaning: $0.element.2) }
    }

    /// 日本時間
    static let japan = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!

    /// 撮った日（`TripBook.day(of:)` の、その日の UTC 0 時で持つ暦の日）の節気。
    /// 日本時間のその日の終わり（翌日 0 時）の黄経で決める（型の注記の 2026-11-18 判断）
    static func term(onDay takenDay: Date) -> Term {
        let offset = TimeInterval(japan.secondsFromGMT(for: takenDay))
        let endOfDay = takenDay.addingTimeInterval(86_400 - offset)
        return term(atLongitude: apparentLongitude(at: endOfDay))
    }

    /// 黄経（度）から節気（その黄経を過ぎた最後の節気）
    static func term(atLongitude longitude: Double) -> Term {
        let from = (longitude - 315).truncatingRemainder(dividingBy: 360)
        let index = Int(((from < 0 ? from + 360 : from) / 15).rounded(.down)) % 24
        return all[index]
    }

    /// 黄経がちょうど `term` の角度になる時刻（`near` の前後 3 日で探す・試験と確かめ用）
    static func moment(of term: Term, near date: Date) -> Date {
        var low = date.addingTimeInterval(-3 * 86_400), high = date.addingTimeInterval(3 * 86_400)
        func ahead(_ d: Date) -> Bool {
            var delta = (apparentLongitude(at: d) - term.longitude).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            return delta >= 0
        }
        for _ in 0..<40 {
            let mid = Date(timeIntervalSince1970: (low.timeIntervalSince1970 + high.timeIntervalSince1970) / 2)
            if ahead(mid) { high = mid } else { low = mid }
        }
        return high
    }

    // MARK: - 太陽の見かけの黄経

    /// 地球時と世界時の差（秒）。2025 年ごろで約 69 秒。数十年の違いでも黄経で 1 秒角に届かないので固定にする
    static let deltaT: Double = 69.2

    /// その瞬間の太陽の見かけの黄経（度・0〜360）
    static func apparentLongitude(at date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 + deltaT / 86_400
        let tau = (julianDay - 2_451_545) / 365_250
        let series = [l0, l1, l2, l3, l4, l5].enumerated().reduce(0.0) { sum, item in
            let value = item.element.reduce(0.0) { $0 + $1.0 * cos($1.1 + $1.2 * tau) }
            return sum + value * pow(tau, Double(item.offset))
        }
        // 地球の日心黄経（ラジアン）→ 太陽の地心黄経（度）
        var longitude = series / 1e8 * 180 / .pi + 180
        let t = tau * 10
        // FK5 への補正
        longitude -= 0.09033 / 3600
        // 章動（主な4項・秒角）
        let omega = (125.04452 - 1934.136261 * t) * .pi / 180
        let sun = (280.4665 + 36000.7698 * t) * .pi / 180
        let moon = (218.3165 + 481267.8813 * t) * .pi / 180
        let nutation = -17.20 * sin(omega) - 1.32 * sin(2 * sun) - 0.23 * sin(2 * moon) + 0.21 * sin(2 * omega)
        // 光行差（距離は 1 天文単位とみなす。違いは 0.4 秒角まで）
        longitude += (nutation - 20.4898) / 3600
        let wrapped = longitude.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    // VSOP87 地球の日心黄経 L0〜L5（振幅 ×1e-8 ラジアン、位相、周波数。Meeus 付録 III）
    private static let l0: [(Double, Double, Double)] = [
        (175_347_046, 0, 0), (3_341_656, 4.6692568, 6283.07585), (34894, 4.6261, 12566.1517),
        (3497, 2.7441, 5753.3849), (3418, 2.8289, 3.5231), (3136, 3.6277, 77713.7715),
        (2676, 4.4181, 7860.4194), (2343, 6.1352, 3930.2097), (1324, 0.7425, 11506.7698),
        (1273, 2.0371, 529.691), (1199, 1.1096, 1577.3435), (990, 5.233, 5884.927),
        (902, 2.045, 26.298), (857, 3.508, 398.149), (780, 1.179, 5223.694),
        (753, 2.533, 5507.553), (505, 4.583, 18849.228), (492, 4.205, 775.523),
        (357, 2.92, 0.067), (317, 5.849, 11790.629), (284, 1.899, 796.298),
        (271, 0.315, 10977.079), (243, 0.345, 5486.778), (206, 4.806, 2544.314),
        (205, 1.869, 5573.143), (202, 2.458, 6069.777), (156, 0.833, 213.299),
        (132, 3.411, 2942.463), (126, 1.083, 20.775), (115, 0.645, 0.98),
        (103, 0.636, 4694.003), (102, 0.976, 15720.839), (102, 4.267, 7.114),
        (99, 6.21, 2146.17), (98, 0.68, 155.42), (86, 5.98, 161000.69),
        (85, 1.3, 6275.96), (85, 3.67, 71430.7), (80, 1.81, 17260.15),
        (79, 3.04, 12036.46), (75, 1.76, 5088.63), (74, 3.5, 3154.69),
        (74, 4.68, 801.82), (70, 0.83, 9437.76), (62, 3.98, 8827.39),
        (61, 1.82, 7084.9), (57, 2.78, 6286.6), (56, 4.39, 14143.5),
        (56, 3.47, 6279.55), (52, 0.19, 12139.55), (52, 1.33, 1748.02),
        (51, 0.28, 5856.48), (49, 0.49, 1194.45), (41, 5.37, 8429.24),
        (41, 2.4, 19651.05), (39, 6.17, 10447.39), (37, 6.04, 10213.29),
        (37, 2.57, 1059.38), (36, 1.71, 2352.87), (36, 1.78, 6812.77),
        (33, 0.59, 17789.85), (30, 0.44, 83996.85), (30, 2.74, 1349.87),
        (25, 3.16, 4690.48),
    ]
    private static let l1: [(Double, Double, Double)] = [
        (628_331_966_747, 0, 0), (206059, 2.678235, 6283.07585), (4303, 2.6351, 12566.1517),
        (425, 1.59, 3.523), (119, 5.796, 26.298), (109, 2.966, 1577.344),
        (93, 2.59, 18849.23), (72, 1.14, 529.69), (68, 1.87, 398.15),
        (67, 4.41, 5507.55), (59, 2.89, 5223.69), (56, 2.17, 155.42),
        (45, 0.4, 796.3), (36, 0.47, 775.52), (29, 2.65, 7.11),
        (21, 5.34, 0.98), (19, 1.85, 5486.78), (19, 4.97, 213.3),
        (17, 2.99, 6275.96), (16, 0.03, 2544.31), (16, 1.43, 2146.17),
        (15, 1.21, 10977.08), (12, 2.83, 1748.02), (12, 3.26, 5088.63),
        (12, 5.27, 1194.45), (12, 2.08, 4694), (11, 0.77, 553.57),
        (10, 1.3, 6286.6), (10, 4.24, 1349.87), (9, 2.7, 242.73),
        (9, 5.64, 951.72), (8, 5.3, 2352.87), (6, 2.65, 9437.76),
        (6, 4.67, 4690.48),
    ]
    private static let l2: [(Double, Double, Double)] = [
        (52919, 0, 0), (8720, 1.0721, 6283.0758), (309, 0.867, 12566.152),
        (27, 0.05, 3.52), (16, 5.19, 26.3), (16, 3.68, 155.42),
        (10, 0.76, 18849.23), (9, 2.06, 77713.77), (7, 0.83, 775.52),
        (5, 4.66, 1577.34), (4, 1.03, 7.11), (4, 3.44, 5573.14),
        (3, 5.14, 796.3), (3, 6.05, 5507.55), (3, 1.19, 242.73),
        (3, 6.12, 529.69), (3, 0.31, 398.15), (3, 2.28, 553.57),
        (2, 4.38, 5223.69), (2, 3.75, 0.98),
    ]
    private static let l3: [(Double, Double, Double)] = [
        (289, 5.844, 6283.076), (35, 0, 0), (17, 5.49, 12566.15),
        (3, 5.2, 155.42), (1, 4.72, 3.52), (1, 5.3, 18849.23), (1, 5.97, 242.73),
    ]
    private static let l4: [(Double, Double, Double)] = [(114, 3.142, 0), (8, 4.13, 6283.08), (1, 3.84, 12566.15)]
    private static let l5: [(Double, Double, Double)] = [(1, 3.14, 0)]
}
