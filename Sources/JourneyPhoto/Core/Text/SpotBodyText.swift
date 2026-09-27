import Foundation

/// 撮影スポットの本文（`SpotBody`）の言い方。
///
/// **日本語の呼び名・見出し・印の文は Web の `SpotGuideClient` と同じ。** 英語は
/// アプリで付けた訳（Web は英語でも日本語の呼び名を出す）。
/// **並びは Web と違う**——Web は台帳の並びのまま、アプリは板 13 に従い
/// 季節は今の季節から巡る順、時間帯は夜明け→夜の順に並べる。
enum SpotBodyText {

    /// 季節の巡り（`spring` → `winter`。並べるときは今の季節から巡らせる）
    static let seasonOrder = ["spring", "summer", "autumn", "winter"]
    /// 時間帯の並び（夜明け→夜）
    static let timeOrder = ["dawn", "morning", "day", "goldenHour", "dusk", "night"]

    /// 季節の名前。**知らない値は nil**（生の英語を画面に出さない）
    static func seasonLabel(_ season: String) -> String? {
        switch season {
        case "spring": return L("春", "Spring")
        case "summer": return L("夏", "Summer")
        case "autumn": return L("秋", "Autumn")
        case "winter": return L("冬", "Winter")
        default: return nil
        }
    }

    /// 時間帯の名前（Web の `TIME_LABEL` と同じ）。知らない値は nil
    static func timeLabel(_ time: String) -> String? {
        switch time {
        case "dawn": return L("夜明け", "Dawn")
        case "morning": return L("朝", "Morning")
        case "day": return L("日中", "Daytime")
        case "goldenHour": return L("夕方の斜光", "Golden hour")
        case "dusk": return L("日没後", "Blue hour")
        case "night": return L("夜", "Night")
        default: return nil
        }
    }

    /// 月から季節（春3〜5月・夏6〜8月・秋9〜11月・冬12〜2月。板 52 の注記と同じ）
    static func season(ofMonth month: Int) -> String {
        switch month {
        case 3...5: return "spring"
        case 6...8: return "summer"
        case 9...11: return "autumn"
        default: return "winter"
        }
    }

    /// 端末の時刻帯で見た、今の季節
    static func currentSeason(now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return season(ofMonth: calendar.component(.month, from: now))
    }

    /// **今の季節を先頭に、そこから巡る順**（板 13「今の季節を先頭に開く」）。
    /// 秋なら 秋→冬→春→夏——次に来る季節を2番目に置く。知らない季節は落とす
    static func orderedSeasons(_ list: [SpotBody.Seasonal], current: String) -> [SpotBody.Seasonal] {
        let known = list.filter { seasonLabel($0.season) != nil }
        let start = seasonOrder.firstIndex(of: current) ?? 0
        func rank(_ s: SpotBody.Seasonal) -> Int {
            let i = seasonOrder.firstIndex(of: s.season) ?? seasonOrder.count
            return (i - start + seasonOrder.count) % seasonOrder.count
        }
        return known.enumerated().sorted { lhs, rhs in
            let (a, b) = (rank(lhs.element), rank(rhs.element))
            return a != b ? a < b : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// 時間帯は決まった順（夜明け→夜）。知らない時間帯は落とす
    static func orderedTimes(_ list: [SpotBody.TimeOfDay]) -> [SpotBody.TimeOfDay] {
        list.filter { timeLabel($0.time) != nil }.enumerated().sorted { lhs, rhs in
            let a = timeOrder.firstIndex(of: lhs.element.time) ?? timeOrder.count
            let b = timeOrder.firstIndex(of: rhs.element.time) ?? timeOrder.count
            return a != b ? a < b : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// 確かめた印の1行を、**出典の題を押せる形**で（Web は題ごとにリンク）。
    /// 文字は `checkLine` と同じ
    static func linkedCheckLine(_ check: SpotBody.Check) -> AttributedString {
        guard case .ai(let day, let sources) = check else { return AttributedString(checkLine(check)) }
        var line = AttributedString(L("出典: ", "Source: "))
        for (i, source) in sources.enumerated() {
            if i > 0 { line += AttributedString(L("、", ", ")) }
            var title = AttributedString(source.title)
            title.link = source.url
            line += title
        }
        line += AttributedString(L("（AI 照合 \(day)）", " (checked by AI against the source, \(day))"))
        return line
    }

    /// 確かめた印の1行。**人の確認だけが「運営」と名乗る**（AI 照合は出典を書く）
    static func checkLine(_ check: SpotBody.Check) -> String {
        switch check {
        case .human(let day):
            return L("情報の最終確認: \(day)（運営）", "Last checked: \(day) (by our team)")
        case .ai(let day, let sources):
            let names = sources.map(\.title).joined(separator: L("、", ", "))
            return L("出典: \(names)（AI 照合 \(day)）",
                     "Source: \(names) (checked by AI against the source, \(day))")
        }
    }
}
