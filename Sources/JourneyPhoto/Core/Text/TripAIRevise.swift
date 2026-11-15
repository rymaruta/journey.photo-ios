import Foundation

/// AI で直した日程を、今の日程に重ねる（札 #621・確かめ役の指摘 2026-11-15「中身が消える」）。
///
/// - AI に渡していない項目（撮影地 `.location`・台帳に無い観光スポット）は、**元の日に残す**（並びは元の日の後ろ）
/// - AI に渡したのに AI が選ばなかった場所は捨てず、日の下の「外しました　戻す」へ出す（`dropped`）
/// - メモは同じ場所に残す
/// - 日の数と日付は元を下回らない（AI が日を減らしても、空の日として残す）
enum TripAIRevise {
    struct Dropped: Equatable {
        let day: Int
        let index: Int
        let item: TripItem
    }

    /// - Parameters:
    ///   - before: 今の日程
    ///   - aiDays: AI が選んだ観光スポットの ID（日ごと・並びのまま）
    ///   - sent: AI に今の日程として渡した観光スポットの ID
    static func merge(before: [TripDay], aiDays: [[String]], sent: Set<String>) -> (days: [TripDay], dropped: [Dropped]) {
        var memo: [String: String] = [:]
        for day in before {
            for item in day.items { if case .spot(let id, let note?) = item { memo[id] = note } }
        }
        let chosen = Set(aiDays.flatMap { $0 })
        let count = max(before.count, aiDays.count, 1)
        var out: [TripDay] = (0..<count).map { i in TripDay(date: before.indices.contains(i) ? before[i].date : nil, items: []) }
        for (i, ids) in aiDays.enumerated() {
            out[i].items = ids.map { .spot(spotId: $0, note: memo[$0]) }
        }
        var dropped: [Dropped] = []
        for (d, day) in before.enumerated() {
            for (i, item) in day.items.enumerated() {
                if case .spot(let id, _) = item, sent.contains(id) {
                    if !chosen.contains(id) { dropped.append(Dropped(day: d, index: i, item: item)) }
                } else {
                    out[d].items.append(item)
                }
            }
        }
        return (out, dropped)
    }
}
