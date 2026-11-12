import Foundation

/// 旅行プランの日付の段の「休みの組」（2026-11-12 判断・資料「SNS をもっと SNS に」2a）。
///
/// 押すと出発と帰着の2日がまとめて入る（「11/22 · 23（日・祝）」「11/28 · 29（土日）」）。
/// 祝日は**端末で計算する**（外の API・表のファイルは使わない）。決まりは今の祝日法（2020 年以降の形）:
///
/// - 日付の決まった祝日（元日・建国記念の日・天皇誕生日・昭和の日・憲法記念日・みどりの日・こどもの日・山の日・文化の日・勤労感謝の日）
/// - 月曜の祝日（成人の日＝1月第2・海の日＝7月第3・敬老の日＝9月第3・スポーツの日＝10月第2）
/// - 春分の日・秋分の日（1980〜2099 年の近似式。国立天文台の暦要項と同じ日になる式）
/// - 振替休日（日曜の祝日のあと、最初の祝日でない日）・国民の休日（祝日にはさまれた平日）
///
/// 🔴 2020・2021 年の五輪の移動は入れていない（過ぎた年なので休みの組には出ない）。
/// 暦は UTC の暦で数える（`TripPlanText.calendar`・`YYYY-MM-DD` の日そのもの）
enum TripHolidays {

    // MARK: - 祝日

    /// その日が祝日（振替休日・国民の休日を含む）か
    static func isHoliday(_ ymd: String) -> Bool {
        guard let (y, m, d) = TakenDay.ymd(ymd) else { return false }
        return holidays(year: y).contains(key(m, d))
    }

    /// 休み（土曜・日曜・祝日）か
    static func isOff(_ ymd: String) -> Bool {
        var years = Years()
        return years.isOff(ymd)
    }

    /// 年ごとの祝日の控え（休みの組を探す1回の中だけで使う）。
    /// 2026-11-12（確かめ役の指摘）: 日ごとに年の祝日を計算し直していて、日付の段の描き直しのたびに約13ms かかった
    struct Years {
        private var sets: [Int: Set<Int>] = [:]

        mutating func isHoliday(_ ymd: String) -> Bool {
            guard let (y, m, d) = TakenDay.ymd(ymd) else { return false }
            if sets[y] == nil { sets[y] = TripHolidays.holidays(year: y) }
            return sets[y]?.contains(m * 100 + d) ?? false
        }

        mutating func isOff(_ ymd: String) -> Bool {
            guard let date = TripPlanText.date(fromYMD: ymd) else { return false }
            let w = TripPlanText.calendar.component(.weekday, from: date)
            return w == 1 || w == 7 || isHoliday(ymd)
        }

        /// 平日の祝日か
        mutating func isWeekdayHoliday(_ ymd: String) -> Bool {
            guard let date = TripPlanText.date(fromYMD: ymd) else { return false }
            let w = TripPlanText.calendar.component(.weekday, from: date)
            return w != 1 && w != 7 && isHoliday(ymd)
        }
    }

    /// その年の祝日（`月*100+日`）
    static func holidays(year y: Int) -> Set<Int> {
        var base: Set<Int> = [key(1, 1), key(2, 11), key(2, 23), key(4, 29), key(5, 3), key(5, 4), key(5, 5),
                              key(8, 11), key(11, 3), key(11, 23)]
        base.insert(key(1, nthMonday(y, 1, 2)))
        base.insert(key(7, nthMonday(y, 7, 3)))
        base.insert(key(9, nthMonday(y, 9, 3)))
        base.insert(key(10, nthMonday(y, 10, 2)))
        base.insert(key(3, vernalEquinox(y)))
        base.insert(key(9, autumnalEquinox(y)))

        var out = base
        // 振替休日: 日曜の祝日のあと、最初の祝日でない日
        for k in base.sorted() where weekday(y, k / 100, k % 100) == 1 {
            var next = shifted(y, k, by: 1)
            while let n = next, out.contains(n) { next = shifted(y, n, by: 1) }
            if let n = next { out.insert(n) }
        }
        // 国民の休日: 前後が祝日（もとの祝日）にはさまれた日（日曜は除く）
        for k in base.sorted() {
            guard let mid = shifted(y, k, by: 1), let after = shifted(y, k, by: 2),
                  !out.contains(mid), base.contains(after), weekday(y, mid / 100, mid % 100) != 1 else { continue }
            out.insert(mid)
        }
        return out
    }

    /// 春分の日（3月）。1980〜2099 年の式
    static func vernalEquinox(_ y: Int) -> Int {
        Int(20.8431 + 0.242194 * Double(y - 1980)) - (y - 1980) / 4
    }

    /// 秋分の日（9月）。1980〜2099 年の式
    static func autumnalEquinox(_ y: Int) -> Int {
        Int(23.2488 + 0.242194 * Double(y - 1980)) - (y - 1980) / 4
    }

    // MARK: - 休みの組

    /// 押すと2日が入る休みの組
    struct Pair: Equatable, Identifiable {
        let start: String
        let end: String
        /// 「11/22 · 23（日・祝）」
        let label: String
        /// 祝日を含む（連休）
        let hasHoliday: Bool
        var id: String { start }
    }

    /// 探す先（日）。これより先の休みの組は出さない
    static let horizonDays = 120

    /// `today` から先の休みの組。**1つ目はいちばん近い組、2つ目は祝日を含むいちばん近い組**（無ければ次の組）。
    ///
    /// 2026-11-12 判断: 3日以上続く休み（土日月の連休など）は、**祝日とその隣の休みの2日**にする
    /// （「11/21 土・22 日・23 月祝」→「11/22 · 23（日・祝）」・資料の模型と同じ）。祝日が平日に無い組は頭の2日
    static func pairs(from today: String, limit: Int = 2) -> [Pair] {
        let all = allPairs(from: today)
        guard let first = all.first else { return [] }
        var out = [first]
        if limit > 1, let holiday = all.dropFirst().first(where: \.hasHoliday) ?? all.dropFirst().first {
            out.append(holiday)
        }
        if limit > 2 {
            out += all.filter { p in !out.contains(p) }.prefix(limit - out.count)
        }
        return Array(out.prefix(limit))
    }

    /// `today` から `horizonDays` 日の間の、2日以上続く休みを組にしたもの（近い順）
    static func allPairs(from today: String) -> [Pair] {
        guard let start = TripPlanText.date(fromYMD: today) else { return [] }
        let days: [String] = (0..<horizonDays).compactMap { i in
            TripPlanText.calendar.date(byAdding: .day, value: i, to: start).map(TripPlanText.ymd)
        }
        var years = Years()
        var runs: [[String]] = []
        var current: [String] = []
        for day in days {
            if years.isOff(day) {
                current.append(day)
            } else {
                if current.count >= 2 { runs.append(current) }
                current = []
            }
        }
        if current.count >= 2 { runs.append(current) }
        return runs.map { pair(of: $0, years: &years) }
    }

    /// 続く休みから2日を選ぶ（平日の祝日があれば、その祝日と隣の休み）
    static func pair(of run: [String]) -> Pair {
        var years = Years()
        return pair(of: run, years: &years)
    }

    static func pair(of run: [String], years: inout Years) -> Pair {
        let weekdayHoliday = run.firstIndex { years.isWeekdayHoliday($0) }
        let i: Int
        if let h = weekdayHoliday { i = h == 0 ? 0 : h - 1 } else { i = 0 }
        let two = Array(run[i...].prefix(2))
        return Pair(start: two[0], end: two[1], label: label(two[0], two[1], years: &years),
                    hasHoliday: two.contains { years.isHoliday($0) })
    }

    /// 「11/22 · 23（日・祝）」「11/28 · 29（土日）」「12/31 · 1/1（木・祝）」
    static func label(_ start: String, _ end: String) -> String {
        var years = Years()
        return label(start, end, years: &years)
    }

    static func label(_ start: String, _ end: String, years: inout Years) -> String {
        guard let (_, m1, d1) = TakenDay.ymd(start), let (_, m2, d2) = TakenDay.ymd(end) else { return start }
        let second = m1 == m2 ? "\(d2)" : "\(m2)/\(d2)"
        let marks = [mark(start, years: &years), mark(end, years: &years)]
        let weekendOnly = marks == [L("土", "Sat"), L("日", "Sun")]
        let tail = weekendOnly ? L("土日", "weekend") : marks.joined(separator: L("・", ", "))
        return L("\(m1)/\(d1) · \(second)（\(tail)）", "\(m1)/\(d1) – \(second) (\(tail))")
    }

    /// 読み上げ（「11月22日 日曜日から 11月23日 祝日まで」は長いので、期間の1行と同じ形）
    static func spoken(_ pair: Pair) -> String {
        let range = TripDraft.rangeLine(start: pair.start, end: pair.end) ?? pair.label
        return pair.hasHoliday ? L("\(range)・祝日を含む", "\(range), includes a holiday") : range
    }

    /// 曜日の1字。平日の祝日は「祝」
    private static func mark(_ day: String, years: inout Years) -> String {
        guard let date = TripPlanText.date(fromYMD: day) else { return "" }
        if years.isWeekdayHoliday(day) { return L("祝", "holiday") }
        return TripDraft.weekday(date)
    }

    // MARK: - 暦の小道具

    private static func key(_ m: Int, _ d: Int) -> Int { m * 100 + d }

    /// 1＝日曜 … 7＝土曜
    private static func weekday(_ y: Int, _ m: Int, _ d: Int) -> Int {
        guard let date = TripPlanText.calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return 0 }
        return TripPlanText.calendar.component(.weekday, from: date)
    }

    /// その月の第 n 月曜の日
    private static func nthMonday(_ y: Int, _ m: Int, _ n: Int) -> Int {
        let first = weekday(y, m, 1)
        let firstMonday = 1 + (9 - first) % 7
        return firstMonday + (n - 1) * 7
    }

    /// 同じ年の中で `days` 日ずらした `月*100+日`。年をまたいだら nil
    private static func shifted(_ y: Int, _ k: Int, by days: Int) -> Int? {
        guard let date = TripPlanText.calendar.date(from: DateComponents(year: y, month: k / 100, day: k % 100)),
              let moved = TripPlanText.calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        let c = TripPlanText.calendar.dateComponents([.year, .month, .day], from: moved)
        guard c.year == y, let m = c.month, let d = c.day else { return nil }
        return key(m, d)
    }
}
