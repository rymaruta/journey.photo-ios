import Foundation

/// 行った県マップの**記録**（札 #503・提案書 第2版）。県ごとに「行った日」の並びだけを持つ。
/// 回数は日の数。周は回数から出す（全47県が n 回以上で「n 周そろった」・進行中は「n+1 周目 k/47」）。
///
/// 2026-11-08 判断（owner「任せる」・提案書 第2版の決め）:
/// - **回数は本人のタップ（日付つき）だけで増える。** 写真の枚数・投稿数・撮影日では増えない
///   （分けて投稿する不正の誘因を作らない）。写真から導いた県は「候補」（`PrefectureResolver`）で、
///   記録にするのは本人
/// - **塗り・回数は報酬（硬貨・バッジ・家具・Pro）にも他人への公開にも結びつけない。** このファイルは
///   サーバーにも `Badge`・`Camper`・`Trunk` にも触れない。バッジ「都道府県」の数は変えない
/// - 保存は端末内だけ（`VisitedPrefectureStore`）。内部の上限は99回
/// - 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる
struct VisitedPrefectures: Equatable {

    /// 内部の上限（札の「＋」はここで止まる）。数え間違いを直せるよう、9 で止めない
    nonisolated static let maxCount = 99
    /// 画面に出す数字の上限。これ以上は「9+」
    nonisolated static let displayCap = 8

    /// 県の正式名 → 行った日（"yyyy-MM-dd"・古い順）。**空の県は持たない**
    private(set) var visits: [String: [String]] = [:]
    /// 本人が「候補ではない」と外した県（写真に写っていても出さない）
    private(set) var dismissed: Set<String> = []
    /// 祝いを出し終えた周の数。nil＝この画面をまだ開いていない（`settleOnOpen`）
    private(set) var seenRounds: Int?

    nonisolated static let total = 47

    init() {}

    init(visits: [String: [String]], dismissed: Set<String> = [], seenRounds: Int? = nil) {
        var clean: [String: [String]] = [:]
        for (name, days) in visits where RegionList.prefectures.contains(name) && !days.isEmpty {
            // 古い順に並べ直す（保存の並びに頼らない）
            clean[name] = Array(days.sorted().prefix(Self.maxCount))
        }
        self.visits = clean
        self.dismissed = dismissed.filter { RegionList.prefectures.contains($0) }
        self.seenRounds = seenRounds.map { max(0, $0) }
    }

    // MARK: - 読む

    func count(_ prefecture: String) -> Int { visits[prefecture]?.count ?? 0 }

    func days(_ prefecture: String) -> [String] { visits[prefecture] ?? [] }

    /// 県ごとの回数（`RegionList.prefectures` の順）
    var counts: [Int] { RegionList.prefectures.map { count($0) } }

    /// 1回以上行った県の数（「行った県 n/47」）
    var visitedCount: Int { counts.filter { $0 >= 1 }.count }

    /// 全47県が n 回以上、の最大の n
    var completedRounds: Int { counts.min() ?? 0 }

    /// 進行中の周と、その周で済んだ県の数。1周もそろっていなければ「1周目」（k は行った県の数と同じ）
    var inProgress: (round: Int, done: Int) {
        let rounds = completedRounds
        return (rounds + 1, counts.filter { $0 > rounds }.count)
    }

    var recordedPrefectures: [String] { RegionList.prefectures.filter { count($0) >= 1 } }

    /// 同じ日にもう記録があるか（「今日は記録済みです」の確かめに使う）
    func hasVisit(_ prefecture: String, on day: String) -> Bool {
        visits[prefecture]?.contains(day) ?? false
    }

    // MARK: - 見た目の段

    /// 色・模様の段（提案書 第2版）: 0 未／1 回＝#796440 無地／2 回＝#C9A66B 点／3 回＝#F3DCA6 横縞／4 回以上＝#F3DCA6 格子
    nonisolated static func level(forCount count: Int) -> Int { min(max(count, 0), 4) }

    /// 地図・札・マスに出す数字。1〜8、9 以上は「9+」。0 は空
    nonisolated static func countText(_ count: Int) -> String {
        if count <= 0 { return "" }
        return count > displayCap ? "9+" : String(count)
    }

    // MARK: - 写真の候補

    /// 写真から導けた県のうち、まだ記録に無く、本人が外してもいないもの（JIS の順）
    func candidates(found: [String]) -> [String] {
        let set = Set(found)
        return RegionList.prefectures.filter { set.contains($0) && count($0) == 0 && !dismissed.contains($0) }
    }

    /// 地図の下の内訳（「写真から n・手で m」）。**バッジ「都道府県」の数とは別**（バッジは変えない）。
    /// - fromPhotos: 写真から導けた県の数
    /// - recordedOnly: 記録はあるが、写真からは導けない県の数（手で記録した分）
    func breakdown(found: [String]) -> (fromPhotos: Int, recordedOnly: Int) {
        let set = Set(found)
        return (set.count, recordedPrefectures.filter { !set.contains($0) }.count)
    }

    // MARK: - 書く（変えたら `VisitedChange` を返す。戻すのに使う）

    /// 1回足す。県名が違う・上限（99）なら nil
    @discardableResult
    mutating func add(_ prefecture: String, day: String) -> VisitedChange? {
        guard RegionList.prefectures.contains(prefecture), count(prefecture) < Self.maxCount else { return nil }
        let before = visits[prefecture] ?? []
        var after = before
        after.append(day)
        after.sort()
        visits[prefecture] = after
        return VisitedChange(before: [prefecture: before], after: [prefecture: after])
    }

    /// 1回減らす（いちばん新しい日から）。0 回の県は nil。0 になれば記録を外す
    @discardableResult
    mutating func removeLast(_ prefecture: String) -> VisitedChange? {
        guard let before = visits[prefecture], !before.isEmpty else { return nil }
        var after = before
        after.removeLast()
        visits[prefecture] = after.isEmpty ? nil : after
        return VisitedChange(before: [prefecture: before], after: [prefecture: after])
    }

    /// 日付を直す（記録の一つを別の日に）。範囲外・同じ日・**ほかの記録と同じ日になる**ときは nil
    /// （同じ日の2回目は「足す」で確かめてから記録できる。直すことで重なりを作らない）
    @discardableResult
    mutating func changeDay(_ prefecture: String, at index: Int, to day: String) -> VisitedChange? {
        guard let before = visits[prefecture], before.indices.contains(index), before[index] != day,
              !before.contains(day) else { return nil }
        var after = before
        after[index] = day
        after.sort()
        visits[prefecture] = after
        return VisitedChange(before: [prefecture: before], after: [prefecture: after])
    }

    /// 「47県ぜんぶ行った」: 0 回の県だけ、各1回として記録する（すでに記録のある県は変えない）。
    /// これも本人のタップによる確定。足す県が無ければ nil
    @discardableResult
    mutating func markAllVisited(day: String) -> VisitedChange? {
        var before: [String: [String]] = [:]
        var after: [String: [String]] = [:]
        for name in RegionList.prefectures where count(name) == 0 {
            before[name] = []
            after[name] = [day]
            visits[name] = [day]
        }
        return after.isEmpty ? nil : VisitedChange(before: before, after: after)
    }

    /// 記録を全部外す（確認のあとで）。無ければ nil
    @discardableResult
    mutating func clearAll() -> VisitedChange? {
        guard !visits.isEmpty else { return nil }
        let before = visits
        var after: [String: [String]] = [:]
        for name in before.keys { after[name] = [] }
        visits = [:]
        return VisitedChange(before: before, after: after)
    }

    /// 変えたことを戻す（`before` に置き直す）
    mutating func revert(_ change: VisitedChange) {
        for (name, days) in change.before where RegionList.prefectures.contains(name) {
            visits[name] = days.isEmpty ? nil : days
        }
    }

    /// 写真の候補を「候補ではない」と外す（記録は変えない）
    mutating func dismissCandidate(_ prefecture: String) {
        guard RegionList.prefectures.contains(prefecture) else { return }
        dismissed.insert(prefecture)
    }

    /// 外した候補を戻す（記録を足したときに呼ぶ）
    mutating func restoreCandidate(_ prefecture: String) {
        dismissed.remove(prefecture)
    }

    // MARK: - 祝い

    /// 祝いの種類。1周目は「47県そろった」、2周目以降は「n 周そろった」
    enum Celebration: Equatable {
        case allVisited
        case roundCompleted(Int)

        var round: Int {
            switch self {
            case .allVisited: return 1
            case .roundCompleted(let n): return n
            }
        }
    }

    /// 画面を開いたとき。**すでにそろっている状態で初めて開いた人には祝いを出さない**
    /// （そろった周の数を覚えるだけ）。開いたことがあれば何もしない
    mutating func settleOnOpen() {
        if seenRounds == nil { seenRounds = completedRounds }
    }

    /// 記録を変えたあとに呼ぶ。そろった周が増えていれば祝いを1つ返し、見せた周として覚える
    /// （取り消して足し直しても、見せた周は繰り返さない）。開く前（`seenRounds == nil`）は返さない
    mutating func takeCelebration() -> Celebration? {
        guard let seen = seenRounds else { return nil }
        let rounds = completedRounds
        guard rounds > seen else { return nil }
        seenRounds = rounds
        return rounds == 1 ? .allVisited : .roundCompleted(rounds)
    }
}

/// 1回の変更の前後（県ごとの日の並び。空＝記録なし）。「取り消す」「ひとつ戻す」に使う
struct VisitedChange: Equatable {
    let before: [String: [String]]
    let after: [String: [String]]
}

/// 「ひとつ戻す」の履歴。**新しい順に `limit`（20）手まで**。端末の中にも置かない（画面を閉じたら消える）
struct VisitedHistory: Equatable {
    nonisolated static let limit = 20
    private(set) var changes: [VisitedChange] = []

    var canUndo: Bool { !changes.isEmpty }
    var last: VisitedChange? { changes.last }

    mutating func push(_ change: VisitedChange) {
        changes.append(change)
        if changes.count > Self.limit { changes.removeFirst(changes.count - Self.limit) }
    }

    /// いちばん新しい変更を取り出して、記録を戻す
    @discardableResult
    mutating func undo(on record: inout VisitedPrefectures) -> VisitedChange? {
        guard let change = changes.popLast() else { return nil }
        record.revert(change)
        return change
    }

    mutating func removeAll() { changes.removeAll() }
}

/// 日付の文字（"yyyy-MM-dd"）。**暦は必ず西暦（グレゴリオ暦）**で、時刻帯だけ端末（渡した暦）のものを使う。
///
/// 🔴 端末の暦（和暦・仏暦）をそのまま使うと、和暦では 2026 年が「0008」になり、読み込みの `isValid`
/// （1900 年以上）で落ちて**記録が消えた**。保存する文字は暦に依らない西暦にそろえる
enum VisitedDay {

    /// 西暦の暦（時刻帯は渡された暦のもの）
    static func gregorian(like calendar: Calendar) -> Calendar {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        return g
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(c.year ?? 1970, 4))-\(pad(c.month ?? 1, 2))-\(pad(c.day ?? 1, 2))"
    }

    /// 日付の文字 → その日の正午（日付の選び直しに使う）。読めなければ nil
    static func date(from s: String, calendar: Calendar = .current) -> Date? {
        guard isValid(s) else { return nil }
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorian(like: calendar).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// 読める日付か
    static func isValid(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return false }
        return y >= 1900 && (1...12).contains(m) && (1...31).contains(d)
    }
}
