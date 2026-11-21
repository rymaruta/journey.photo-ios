import Foundation
import Combine

/// 旅行プランの**着く時刻の目安**（札 #677・2026-11-21 owner「旅行プランも何時に〇〇みたいなのあるといいね」・案A）。
///
/// 2026-11-21 判断: `TripPlan` の「計算していない数字を出さない」と `TripTravel.dayWarning` の「滞在の時間は足さない」を、
/// **時刻に「目安」と書く形で緩める**（owner の今回の要望。`dayWarning` の判定そのものは変えない）。
///
/// - 時刻は**端末で計算する目安**。AI を使わない、サーバーと DB は変えない（保存しない。開くたびに計算する）
/// - 着く時刻 = 前の場所に着いた時刻 + 滞在の目安（観光スポットの種類から・`stayMinutes`）+ 移動（今の見込み）。5分の単位
/// - 1か所目に着く時刻 = 出発の時刻（既定 9:00）。変えた出発の時刻だけ、この iPhone にプランごと日ごとに覚える（`TripStartStore`）
/// - 夜（日没後・夜）の場所は日の入りのあと、夕方の斜光の場所は斜光の始まりに合わせ、あきの一行を出す。並べ替えはしない
/// - 朝（夜明け・朝）の場所に 10:00 より後に着くときは一言
/// - 移動が分からない区間（長い移動）から先は時刻を出さない（作った数を重ねない）
enum TripTimes {

    /// 出発の既定（9:00・分）
    static let defaultStart = 9 * 60
    /// 選べる出発の時刻（模型どおり 7:00〜12:00 の1時間ごと）
    static let startChoices = [7, 8, 9, 10, 11, 12].map { $0 * 60 }
    /// 朝の場所に着きたい時刻（これより後なら一言）
    static let morningLate = 10 * 60
    /// 分からない種類・撮影地・行きたい場所の滞在
    static let defaultStay = 60
    /// 夜・夕方の場所で待たせる長さの上限（分）。超えたら待たせず、日の入りの時刻だけ添える
    static let maxWait = 4 * 60

    // MARK: - 滞在の目安（観光スポットの種類から）

    /// 種類（`OfficialSpot.category`）ごとの滞在（分）。
    /// 2026-11-21 判断: 索引（journey-photo.com の `spot-feed/index.json`・4,586件・73種類）にある値を全部ここで振り分けた。
    /// 寺、神社、城、町並み 60／公園、庭園、自然、美術館、博物館、展望台 90／駅舎、橋、建物 45（札 #677 の模型の表）
    static let stayTable: [String: Int] = {
        var t: [String: Int] = [:]
        for k in ["寺社", "寺院", "神社", "教会", "仏像", "城", "城跡", "宮殿", "史跡", "遺跡", "産業遺産",
                  "町並み", "街並み", "街", "温泉街", "市場", "集落", "農村", "広場", "祭り"] { t[k] = 60 }
        for k in ["公園", "庭園", "植物園", "動物園", "水族館", "遊園地", "花園", "花畑", "農場",
                  "博物館", "美術館", "アート", "劇場", "展望台", "温泉",
                  "山岳", "火山", "高原", "湿原", "森林", "草原", "砂丘", "棚田", "樹木", "動物", "自然現象",
                  "渓谷", "峡谷", "渓流", "滝", "湧水", "鍾乳洞", "洞窟",
                  "湖沼", "湖", "池", "火口湖", "海岸", "岬", "島", "湾", "海峡", "古道"] { t[k] = 90 }
        for k in ["建築", "橋", "駅", "鉄道", "灯台", "ダム", "道路", "運河", "港", "並木道"] { t[k] = 45 }
        return t
    }()

    /// 種類の字から滞在。表に無い新しい種類は字の中の言葉で振り分け、分からなければ 60 分
    static func stayMinutes(category: String?) -> Int {
        let c = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !c.isEmpty else { return defaultStay }
        if let exact = stayTable[c] { return exact }
        if ["駅", "橋", "建築", "塔"].contains(where: c.contains) { return 45 }
        if ["園", "館", "山", "湖", "海", "滝", "島", "展望"].contains(where: c.contains) { return 90 }
        return defaultStay
    }

    static func stayMinutes(for spot: OfficialSpot?) -> Int {
        stayMinutes(category: spot?.category)
    }

    // MARK: - 移動

    /// まっすぐの距離から移動の分（道のり 1.3 倍、時速 30km・5分の単位・最小 5 分）。AI の画面の流れと同じ見積もり
    static func roughMoveMinutes(_ a: Photo.Coords, _ b: Photo.Coords) -> Int {
        let straight = TripAICandidates.km(a, b)
        let minutes = Int((straight * 1.3 / 30 * 60).rounded())
        return max(5, Int((Double(minutes) / 5).rounded()) * 5)
    }

    /// 概算（時速 30km）で時刻を積むのは、まっすぐ 60km 以内の区間だけ（2026-11-21 判断・札 #677 の確かめ役）。
    /// 前は 500km 未満まで積み、東京から京都で 16 時間になった。遠い区間は新幹線・飛行機で、概算が大きく外れる
    static let roughKm = 60.0

    /// 時刻に使う移動（Apple の見込みが無いとき）。同じ座標は 0 分、座標が分からない・60km より遠いときは nil
    /// （そこから先は時刻を出さない）
    static func scheduleMoveMinutes(_ a: Photo.Coords?, _ b: Photo.Coords?) -> Int? {
        guard let a, let b else { return nil }
        if a == b { return 0 }
        return TripAICandidates.km(a, b) <= roughKm ? roughMoveMinutes(a, b) : nil
    }

    /// Apple の見込み（秒）を5分の単位へ切り上げ
    static func minutes(seconds: Int) -> Int {
        ceil5(Int((Double(seconds) / 60).rounded(.up)))
    }

    static func ceil5(_ m: Int) -> Int { Int((Double(m) / 5).rounded(.up)) * 5 }

    /// 旅行プランの頁の1日の移動（場所ごと・`schedule` の `moves`）。
    /// - その場所へ入る同じ日の区間があれば、Apple の見込み（先に出した手段）。まだ返らない・圏外は AI の画面と同じ見積もり
    /// - 長い移動の形で出ている区間は nil（そこから先は時刻を出さない）
    /// - 見込みの無い区間は `scheduleMoveMinutes`（60km 以内だけ概算、遠ければ nil）
    /// - 1か所目と、前と同じ座標の場所は 0 分。**座標の無い場所（とその次）は nil**（分からない移動を 0 分として続けない）。
    ///   前の日からの区間は数えない（1か所目は出発の時刻）
    static func planMoves(numbers: [Int], coords: [Photo.Coords?], legs: [TripTravel.Leg],
                          estimates: [[TripTravel.Estimate]], long: [Bool]) -> [Int?] {
        numbers.enumerated().map { i, number -> Int? in
            guard i > 0 else { return 0 }
            let here = coords.indices.contains(i) ? coords[i] : nil
            let before = coords.indices.contains(i - 1) ? coords[i - 1] : nil
            guard let here, let before else { return nil }
            if here == before { return 0 }
            guard let li = legs.firstIndex(where: { !$0.crossesDay && $0.to.number == number }) else { return nil }
            if long.indices.contains(li), long[li] { return nil }
            if estimates.indices.contains(li), let seconds = estimates[li].first?.seconds { return minutes(seconds: seconds) }
            return scheduleMoveMinutes(legs[li].from.coords, legs[li].to.coords)
        }
    }

    // MARK: - 時刻を並べる

    struct Stop: Equatable {
        let name: String
        let stay: Int
        /// 時間帯の案内（`SpotBodyText.timeOrder` の綴り）
        let times: [String]
    }

    /// 日の光の時刻（その日の 0:00 からの分・その土地の時計）
    struct Light: Equatable {
        let sunset: Int?
        let goldenStart: Int?
    }

    struct Row: Equatable {
        /// 着く時刻（分）。移動が分からない区間より後は nil
        let arrive: Int?
        /// 着く前のあき（分）。夜・夕方の場所で日の入り・斜光まで待つとき
        var wait = 0
        /// 何まで待つか（「日の入り」「夕方の斜光」）と、その時刻（分）
        var waitFor: (label: String, at: Int)? = nil
        /// 朝の場所に遅れて着く（その時間帯の名前「朝」「夜明け」）
        var lateMorning: String? = nil
        /// 待ちが長すぎて待たせなかった夜・夕方の場所の、日の入り（斜光の始まり）。「日の入りは 16:30」と添える
        var notWaited: (label: String, at: Int)? = nil

        static func == (a: Row, b: Row) -> Bool {
            a.arrive == b.arrive && a.wait == b.wait && a.waitFor?.label == b.waitFor?.label
                && a.waitFor?.at == b.waitFor?.at && a.lateMorning == b.lateMorning
                && a.notWaited?.label == b.notWaited?.label && a.notWaited?.at == b.notWaited?.at
        }
    }

    struct Day: Equatable {
        let rows: [Row]
        /// 最後の場所を出る時刻（「17:30ごろ 終わり」）。分からなければ nil
        let end: Int?
    }

    /// 1日の時刻。`moves[i]` は i 番目の場所へ前の場所からの移動（分）。`moves[0]` は使わない。nil は分からない（長い移動）
    static func schedule(start: Int, stops: [Stop], moves: [Int?], light: Light?) -> Day {
        var t: Int? = start
        var rows: [Row] = []
        for (i, stop) in stops.enumerated() {
            if i > 0, let now = t {
                let move = moves.indices.contains(i) ? moves[i] : 0
                t = move.map { now + $0 }
            }
            guard var at = t else {
                rows.append(Row(arrive: nil))
                continue
            }
            var row = Row(arrive: at)
            // 夜・夕方の場所: 着くのが日の入り（斜光の始まり）より前なら、そこまで待つ
            // 待ちが 4 時間を超えるときは待たせず、着いた時刻のまま日の入りだけ添える（確かめ役の指摘・2026-11-21）
            if let target = waitTarget(stop.times, light: light), at < target.at {
                let until = ceil5(target.at)
                if until - at > maxWait {
                    row.notWaited = target
                } else {
                    row = Row(arrive: until, wait: until - at, waitFor: target)
                    at = until
                }
            }
            if let morning = morningLabel(stop.times), at > morningLate {
                row.lateMorning = morning
            }
            rows.append(row)
            t = at + stop.stay
        }
        return Day(rows: rows, end: stops.isEmpty ? nil : t)
    }

    /// 待つ先。日没後・夜は日の入り、夕方の斜光は斜光の始まり。
    /// 2026-11-21 判断（回 1672 の絵: 朝と夕方の斜光の両方の案内がある金沢城公園を、10:20 に着くのに日の入りまで
    /// 6時間待たせていた）: **朝・夜明け・日中の案内もある場所は待たせない**（着いた時刻でも向いている）。
    /// 斜光の始まりが計算できない日は待たせない（日の入りに合わせると斜光を逃す）
    static func waitTarget(_ times: [String], light: Light?) -> (label: String, at: Int)? {
        guard let light, !times.contains(where: earlyTimes.contains) else { return nil }
        if times.contains("dusk") || times.contains("night"), let set = light.sunset {
            return (L("日の入り", "Sunset"), set)
        }
        if times.contains("goldenHour"), let g = light.goldenStart {
            return (SpotBodyText.timeLabel("goldenHour") ?? "", g)
        }
        return nil
    }

    /// 朝の場所なら、その時間帯の名前（夜明けを先に）。**日中・夕方・夜の案内もある場所は言わない**（遅く着いても向いている）
    static func morningLabel(_ times: [String]) -> String? {
        guard !times.contains(where: laterTimes.contains) else { return nil }
        if times.contains("dawn") { return SpotBodyText.timeLabel("dawn") }
        if times.contains("morning") { return SpotBodyText.timeLabel("morning") }
        return nil
    }

    static let earlyTimes: Set<String> = ["dawn", "morning", "day"]
    static let laterTimes: Set<String> = ["day", "goldenHour", "dusk", "night"]

    /// 日の出・日の入りの計算（`TripDraft.Sun`）を、その土地の時計の分にする
    static func light(_ sun: TripDraft.Sun?) -> Light? {
        guard let sun else { return nil }
        let set = minuteOfDay(sun.sunsetDate, zone: sun.zone)
        let golden = minuteOfDay(sun.goldenStart, zone: sun.zone)
        guard set != nil || golden != nil else { return nil }
        return Light(sunset: set, goldenStart: golden)
    }

    static func minuteOfDay(_ date: Date?, zone: TimeZone) -> Int? {
        guard let date else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        let p = c.dateComponents([.hour, .minute], from: date)
        guard let h = p.hour, let m = p.minute else { return nil }
        return h * 60 + m
    }

    /// プランの日付が無いときは今日（この iPhone の暦）
    static func todayYMD(now: Date = Date()) -> String {
        TripPlanText.ymd(pickedIn: .current, now)
    }

    // MARK: - 言葉

    /// 「9:00」。日をまたいだら「翌0:30」、2日またいだら「翌々0:30」、3日からは「+3日 0:30」
    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % (24 * 60)) + 24 * 60) % (24 * 60)
        return dayPrefix(minutes) + String(format: "%d:%02d", m / 60, m % 60)
    }

    /// 何日またいだかの頭（0 日は空）
    static func dayPrefix(_ minutes: Int) -> String {
        let days = max(0, minutes / (24 * 60))
        switch days {
        case 0: return ""
        case 1: return L("翌", "+1 ")
        case 2: return L("翌々", "+2 ")
        default: return L("+\(days)日 ", "+\(days) ")
        }
    }

    /// 読み上げの時刻（「9時」「9時30分」）
    static func spokenClock(_ minutes: Int) -> String {
        let m = ((minutes % (24 * 60)) + 24 * 60) % (24 * 60)
        let h = m / 60, mm = m % 60
        let ja = dayPrefix(minutes) + (mm == 0 ? "\(h)時" : "\(h)時\(mm)分")
        return L(ja, clock(minutes))
    }

    /// 読み上げの1か所（「9時、日比谷公園」）
    static func spokenStop(_ minutes: Int?, name: String) -> String {
        guard let minutes else { return name }
        return spokenClock(minutes) + L("、", ", ") + name
    }

    /// 「1時間55分」「40分」
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return L("\(m)分", "\(m) min") }
        if m == 0 { return L("\(h)時間", "\(h) h") }
        return L("\(h)時間\(m)分", "\(h) h \(m) min")
    }

    /// 時刻の上の一行
    static var note: String {
        L("時刻は目安です（滞在は場所の種類から）", "Times are estimates (stay length by place type).")
    }

    /// あきの一行（「日の入り 16:32 まで 1時間55分あき」）
    static func waitLine(_ row: Row) -> String? {
        guard row.wait > 0, let target = row.waitFor else { return nil }
        return L("\(target.label) \(clock(target.at)) まで \(duration(row.wait))あき",
                 "\(duration(row.wait)) free until \(target.label.lowercased()) \(clock(target.at))")
    }

    /// 朝の場所に遅れて着く一言（「朝の案内の場所ですが、着くのは11:00ごろ」）
    static func lateMorningLine(_ row: Row) -> String? {
        guard let label = row.lateMorning, let at = row.arrive else { return nil }
        return L("\(label)の案内の場所ですが、着くのは\(clock(at))ごろ",
                 "Best in the \(label.lowercased()), but you arrive around \(clock(at))")
    }

    /// 待たせなかった夜・夕方の場所の一言（「日の入りは 16:30」「夕方の斜光は 15:40 から」）
    static func notWaitedLine(_ row: Row) -> String? {
        guard let target = row.notWaited else { return nil }
        if target.label == L("日の入り", "Sunset") {
            return L("日の入りは \(clock(target.at))", "Sunset at \(clock(target.at))")
        }
        return L("\(target.label)は \(clock(target.at)) から", "\(target.label) from \(clock(target.at))")
    }

    /// 場所の下に添える一言（朝の場所に遅れて着く、または待たせなかった夜・夕方の場所）
    static func cautionLine(_ row: Row) -> String? {
        lateMorningLine(row) ?? notWaitedLine(row)
    }

    /// 終わりの一行（「17:30ごろ 終わり」）
    static func endLine(_ end: Int) -> String {
        L("\(clock(end))ごろ 終わり", "Done around \(clock(end))")
    }

    /// 出発の札の字（「出発 9:00」）と読み上げ
    static func startLabel(_ start: Int) -> String { L("出発", "Start") }
    static func startSpoken(_ start: Int) -> String {
        L("出発の時刻 \(spokenClock(start))", "Start time \(clock(start))")
    }
    static var startHint: String {
        L("押すと出発の時刻を選べます。時刻がそろってずれます", "Choose a start time. All times shift.")
    }
}

/// 変えた出発の時刻（この iPhone だけ・旅行プランの頁だけ・プランごと日ごと）。既定の 9:00 は覚えない（消す）。
///
/// 2026-11-21 判断（札 #677 の確かめ役）: 前は日の番号に付けて覚え、日を消す・組み直し・仲間の変更で別の日にずれた。
/// - 鍵は**日付のある日はその日の日付**（`<planId>@<YYYY-MM-DD>`）、日付の無い日は番号（`<planId>#<番号>`）
/// - 日程が変わったら（日を消す・組み直し・元に戻す・仲間の変更・日付の変更）、**場所の重なりで前の日と今の日を対応させて**
///   時刻を運ぶ（`carried`）。重なる日が無い日は、同じ鍵の前の日が残っていればその値、無ければ 9:00
/// - AI の画面は保存したプランと日がそろわないので、ここを使わない（画面の中だけの値）
/// - プランを消したとき・ログアウトで消す
@MainActor
final class TripStartStore: ObservableObject {
    static let shared = TripStartStore()

    nonisolated static let defaultsKey = "tripStartTimes.v2"
    /// 日の番号だけで覚えていた前の版（読まずに消す）
    nonisolated static let oldDefaultsKey = "tripStartTimes.v1"

    @Published private(set) var starts: [String: Int]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: Self.oldDefaultsKey)
        self.starts = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int]) ?? [:]
    }

    func minutes(planId: String?, ymd: String?, day: Int) -> Int {
        guard let planId, !planId.isEmpty else { return TripTimes.defaultStart }
        return starts[TripStartKeys.key(planId: planId, ymd: ymd, day: day)] ?? TripTimes.defaultStart
    }

    func set(_ minutes: Int, planId: String?, ymd: String?, day: Int) {
        guard let planId, !planId.isEmpty else { return }
        let k = TripStartKeys.key(planId: planId, ymd: ymd, day: day)
        if minutes == TripTimes.defaultStart { starts[k] = nil } else { starts[k] = minutes }
        save()
    }

    /// 日程が変わったとき、時刻を今の日へ運ぶ
    func carry(from old: [TripStartKeys.DaySlot], to new: [TripStartKeys.DaySlot]) {
        let next = TripStartKeys.carried(starts, from: old, to: new)
        guard next != starts else { return }
        starts = next
        save()
    }

    /// プランを消したとき
    func forget(planId: String) {
        let next = starts.filter { !TripStartKeys.belongs($0.key, to: planId) }
        guard next != starts else { return }
        starts = next
        save()
    }

    /// ログアウト・退会（次の人に残さない）
    func forgetAll() {
        starts = [:]
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func save() { defaults.set(starts, forKey: Self.defaultsKey) }
}

/// 出発の時刻の覚えの鍵と、日程が変わったときの運び方（値だけの計算・`TripStartStore` が使う）
enum TripStartKeys {
    /// 日を見分ける鍵と、その日の場所（前の日程と対応させるため）
    struct DaySlot: Equatable, Sendable {
        let key: String
        let items: [String]
    }

    static func key(planId: String, ymd: String?, day: Int) -> String {
        if let ymd, !ymd.isEmpty { return "\(planId)@\(ymd)" }
        return "\(planId)#\(day)"
    }

    /// 日程を日ごとの鍵と場所に（`TripPlanText.dayDate` の日付があれば日付の鍵）
    static func slots(planId: String, days: [TripDay], start: String?, end: String?) -> [DaySlot] {
        days.enumerated().map { i, day in
            DaySlot(key: key(planId: planId, ymd: TripPlanText.dayDate(index: i, day: day, start: start, end: end), day: i),
                    items: day.items.map { String(describing: $0) })
        }
    }

    static func belongs(_ key: String, to planId: String) -> Bool {
        key.hasPrefix(planId + "@") || key.hasPrefix(planId + "#")
    }

    /// 前の日程の時刻を今の日程へ運ぶ。前の日と今の日を、重なる場所の数が多い組から1対1で対応させる
    /// （同じ数なら同じ鍵、近い番号を先に）。前が空（開いたばかり）なら何もしない
    static func carried(_ starts: [String: Int], from old: [DaySlot], to new: [DaySlot]) -> [String: Int] {
        guard !old.isEmpty, old != new else { return starts }
        var pairs: [(n: Int, o: Int, overlap: Int, same: Bool)] = []
        for (n, nd) in new.enumerated() {
            let items = Set(nd.items)
            for (o, od) in old.enumerated() {
                let overlap = items.intersection(od.items).count
                if overlap > 0 { pairs.append((n, o, overlap, nd.key == od.key)) }
            }
        }
        pairs.sort {
            if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
            if $0.same != $1.same { return $0.same }
            return abs($0.n - $0.o) < abs($1.n - $1.o)
        }
        var fromOld: [Int: Int] = [:]
        var usedOld = Set<Int>()
        for p in pairs where fromOld[p.n] == nil && !usedOld.contains(p.o) {
            fromOld[p.n] = p.o
            usedOld.insert(p.o)
        }
        // 場所の重ならない日（空の日など）は、同じ鍵の前の日が残っていればそのまま
        for (n, nd) in new.enumerated() where fromOld[n] == nil {
            if let o = old.firstIndex(where: { $0.key == nd.key }), !usedOld.contains(o) {
                fromOld[n] = o
                usedOld.insert(o)
            }
        }
        var out = starts
        for od in old { out[od.key] = nil }
        for (n, nd) in new.enumerated() {
            if let o = fromOld[n], let value = starts[old[o].key] { out[nd.key] = value }
        }
        return out
    }
}
