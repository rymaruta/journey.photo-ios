import Foundation

/// AI で旅行プランを作る（札 #621・owner 承認 2026-11-15）の、画面を持たない決まり。
///
/// 流れ（案 https://claude.ai/artifact/2EH3WZ8v3s5dUokTvsNFoG の「AI に場所を作らせない」）:
/// 1. 行き先と日数は**アプリが決まった手順で読む**（`TripAIDestination`・`TripAIDays`）。AI は使わない
/// 2. 台帳と行きたい場所から**候補を 20 件まで**選ぶ（`TripAICandidates`）
/// 3. AI（端末の AI か、サーバーの AI）は候補の**番号から**選んで日に割り、理由を1文書くだけ
/// 4. 知らない番号・重なり・範囲の外の日は落とす（`TripAIPlan.sanitized`）。サーバーも同じことをする
/// 5. 圏外・上限・AI が答えないときは、AI なしの組み方（`TripAIFallback`）にする
///
/// 30件の試験（2026-11-15・scratchpad の ai-trip/trial）: 行き先は 30/30（別の10件でも 10/10）、
/// 日数は決まった手順で 29/30（読めない1件は AI の値で 30/30）。
enum TripAILimits {
    /// 🔴 サーバーの `api-user/src/tripAiConfig.ts` の `TRIP_AI_LIMITS` と同じ値にする（owner 2026-11-15）。
    /// 画面はサーバーが返す `limit` を先に使う。ここは返事が無いとき（圏外など）の表示だけ
    static let free = 30
    static let pro = 300
    static let admin = 300

    /// 残りがこの数以下になったら帯で知らせる（案「残り5回を切ったら帯で知らせ」）
    static let warnAt = 5
    /// 候補の数の上限（サーバーの `TRIP_AI_MAX_CANDIDATES`）
    static let maxCandidates = 20
    /// 日数の上限（サーバーの `TRIP_AI_MAX_DAYS`）
    static let maxDays = 7
    /// 頼みの文の長さの上限（サーバーの `TRIP_AI_MAX_REQUEST`）
    static let maxRequest = 200
    /// 1日の移動がこれを超えたら遠い所から外す（案「1日の移動が4時間を超えたら」）
    static let maxTravelMinutesPerDay = 240
}

// MARK: - 日数

enum TripAIDays {
    private static let digits: [Character: Character] = [
        "一": "1", "二": "2", "三": "3", "四": "4", "五": "5", "六": "6", "七": "7",
        "０": "0", "１": "1", "２": "2", "３": "3", "４": "4", "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
    ]

    /// 頼みの文から日数を読む。読めなければ nil（AI の答えか 1 日を使う）。
    /// 「日帰り」「半日」= 1、「1泊2日」= 2、「2泊」= 3、「3日間」= 3
    static func parse(_ text: String) -> Int? {
        let t = String(text.map { digits[$0] ?? $0 })
        if t.contains("日帰り") || t.contains("半日") { return 1 }
        if let g = groups(#"(\d+)\s*泊\s*(\d+)\s*日"#, t), let d = Int(g[1]) { return clamp(d) }
        if let g = groups(#"(\d+)\s*泊"#, t), let n = Int(g[0]) { return clamp(n + 1) }
        if let g = groups(#"(\d+)\s*日(?:間|で|かけ|、|。|$)"#, t), let d = Int(g[0]) { return clamp(d) }
        return nil
    }

    /// 最初に当たった所の組（1 番から）
    private static func groups(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { i in Range(m.range(at: i), in: text).map { String(text[$0]) } }
    }

    private static func clamp(_ d: Int) -> Int { min(max(d, 1), TripAILimits.maxDays) }
}

// MARK: - 行き先

enum TripAIDestination {

    struct Match: Equatable {
        /// 当たった県（点の高い順）
        let prefectures: [String]
        /// 当たった市町村（台帳の綴り）
        let cities: Set<String>
    }

    /// 「足柄下郡箱根町」→ 箱根町・箱根、「札幌市中央区」→ 札幌市・札幌
    static func cityKeys(_ city: String) -> Set<String> {
        var c = city
        // 郡の中は町と村だけ（「郡山市」「大和郡山市」の郡は名前の一部）
        if let r = c.dropFirst().range(of: "郡"), c.hasSuffix("町") || c.hasSuffix("村") { c = String(c[r.upperBound...]) }
        if let r = c.range(of: "市"), r.upperBound < c.endIndex, c.hasSuffix("区") { c = String(c[..<r.upperBound]) }
        var keys: Set<String> = [c]
        if let last = c.last, "市町村区".contains(last) {
            let short = String(c.dropLast())
            if short.count >= 2 { keys.insert(short) }
        }
        return keys
    }

    static func prefectureShort(_ p: String) -> String {
        guard p != "北海道", let last = p.last, "都府県".contains(last) else { return p }
        return String(p.dropLast())
    }

    /// 文を助詞で切る（「河口湖で1泊」→「河口湖」）
    static func chunks(_ text: String) -> [String] {
        let separators = ["、", "。", "，", ",", "・", " ", "　", "に", "で", "を", "と", "へ", "の", "が", "は", "も", "や",
                          "から", "まで", "だけ", "かけて", "見える"]
        var parts = [text]
        for sep in separators.sorted(by: { $0.count > $1.count }) {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.filter { $0.count >= 2 && $0.rangeOfCharacter(from: .decimalDigits) == nil }
    }

    /// 頼みの文から行き先を読む。当たらなければ nil（「行き先が分かりませんでした」）。
    ///
    /// 1) 県・市・観光スポットの名前（別名を含む）が文の中にあれば一致
    /// 2) 文を助詞で切った語が、市の名前か観光スポットの名前の一部なら一致（河口湖 → 富士河口湖町、能登 → 能登島）
    /// 3) 複数の県に当たったら、点の高い県の 1/3 以上の県だけ残す（高山 → 岐阜県高山市）
    static func match(_ text: String, spots: [OfficialSpot]) -> Match? {
        let domestic = spots.filter { ($0.region?.country ?? "").isEmpty && !$0.isDraft }
        var byCity: [String: [OfficialSpot]] = [:]   // "県|市"
        var prefectures: Set<String> = []
        for s in domestic {
            guard let pref = s.region?.prefecture else { continue }
            prefectures.insert(pref)
            if let city = s.region?.city { byCity["\(pref)|\(city)", default: []].append(s) }
        }
        var found: [String: Int] = [:]   // "県|市" または "県|" → 点
        let parts = chunks(text)
        for (key, rows) in byCity {
            let city = String(key.split(separator: "|", maxSplits: 1).last ?? "")
            let keys = cityKeys(city)
            for k in keys where text.contains(k) { found[key, default: 0] += 10 * k.count + rows.count }
            for s in rows {
                for n in [s.name] + (s.aliases?.value ?? []) where n.count >= 2 && text.contains(n) {
                    found[key, default: 0] += 100 * n.count
                }
            }
            for ch in parts where keys.contains(where: { $0.contains(ch) }) || rows.contains(where: { $0.name.contains(ch) }) {
                found[key, default: 0] += 5 * ch.count
            }
        }
        for p in prefectures where text.contains(p) || text.contains(prefectureShort(p)) {
            found["\(p)|", default: 0] += 50
        }
        guard !found.isEmpty else { return nil }
        var byPref: [String: Int] = [:]
        for (key, w) in found { byPref[String(key.split(separator: "|", omittingEmptySubsequences: false)[0]), default: 0] += w }
        let best = byPref.values.max() ?? 0
        let kept = byPref.filter { $0.value * 3 >= best }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        var cities: Set<String> = []
        for key in found.keys {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, !parts[1].isEmpty, kept.contains(parts[0]) { cities.insert(parts[1]) }
        }
        return Match(prefectures: kept, cities: cities)
    }

    /// 読めなかったときに出す県（行きたい場所の多い県から3つ）
    static func suggestions(wishlist: [OfficialSpot]) -> [String] {
        var count: [String: Int] = [:]
        for s in wishlist { if let p = s.region?.prefecture { count[p, default: 0] += 1 } }
        return count.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3).map(\.key)
    }
}

// MARK: - 季節

enum TripAISeason {
    /// 頼みの文に出てくる季節（紅葉 → 秋 など）。無ければ nil
    static func of(_ text: String) -> String? {
        let words: [(String, String)] = [("紅葉", "autumn"), ("秋", "autumn"), ("桜", "spring"), ("春", "spring"),
                                         ("夏", "summer"), ("雪", "winter"), ("冬", "winter")]
        return words.first { text.contains($0.0) }?.1
    }
}

// MARK: - 候補

enum TripAICandidates {

    /// 行き先の県の観光スポットから、候補を `limit` 件まで選ぶ。
    /// 点: 当たった市 +100、行きたい場所 +60、当たった所からの近さ（km を引く）、頼みの季節の案内 +15、時間帯の案内 +3、写真 +2
    static func pick(text: String, match: TripAIDestination.Match, spots: [OfficialSpot],
                     wishlist: Set<String>, limit: Int = TripAILimits.maxCandidates) -> [OfficialSpot] {
        let prefs = Set(match.prefectures)
        let pool = spots.filter { s in
            guard let p = s.region?.prefecture, prefs.contains(p), !s.isDraft else { return false }
            return (s.region?.country ?? "").isEmpty
        }
        let anchors = pool.filter { match.cities.contains($0.region?.city ?? "") }.compactMap(\.coords)
        let season = TripAISeason.of(text)
        func score(_ s: OfficialSpot) -> Double {
            var v = 0.0
            if match.cities.contains(s.region?.city ?? "") { v += 100 }
            if wishlist.contains(s.spotId) { v += 60 }
            if let c = s.coords, !anchors.isEmpty { v -= anchors.map { km(c, $0) }.min() ?? 0 }
            if let season, s.hasSeason(season) { v += 15 }
            if !s.timeKeys.isEmpty { v += 3 }
            if s.hasPhoto { v += 2 }
            return v
        }
        let scored: [(spot: OfficialSpot, score: Double)] = pool.map { (spot: $0, score: score($0)) }
        let sorted = scored.sorted { (a: (spot: OfficialSpot, score: Double), b: (spot: OfficialSpot, score: Double)) -> Bool in
            if a.score != b.score { return a.score > b.score }
            return a.spot.spotId < b.spot.spotId
        }
        return Array(sorted.prefix(limit).map { $0.spot })
    }

    static func km(_ a: Photo.Coords, _ b: Photo.Coords) -> Double {
        let dy = (a.lat - b.lat) * 111
        let dx = (a.lng - b.lng) * 111 * cos(a.lat * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - AI の答え

struct TripAIPlan: Codable, Equatable {
    struct Stop: Codable, Equatable {
        /// 候補の番号（1 から）
        let n: Int
        /// 何日目（1 から）
        let day: Int
    }
    var title: String
    var days: Int
    var stops: [Stop]
    var reason: String
    /// 落とした数（候補の外の番号・重なり）
    var dropped: Int = 0

    /// 候補の外の番号・重なりを落とし、日を範囲に収める。1つも残らなければ nil（読み取れなかった扱い）
    func sanitized(candidateCount: Int, fixedDays: Int?) -> TripAIPlan? {
        let d = min(max(fixedDays ?? days, 1), TripAILimits.maxDays)
        var seen = Set<Int>()
        var out: [Stop] = []
        var drop = 0
        for s in stops {
            guard (1...max(candidateCount, 1)).contains(s.n), candidateCount > 0, !seen.contains(s.n) else { drop += 1; continue }
            seen.insert(s.n)
            out.append(Stop(n: s.n, day: min(max(s.day, 1), d)))
        }
        guard !out.isEmpty else { return nil }
        let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        let cleanReason = String(reason.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        return TripAIPlan(title: cleanTitle, days: d, stops: out, reason: cleanReason, dropped: dropped + drop)
    }

    /// 日ごとの観光スポット（AI の並びのまま。空の日は詰める）
    func dayLists(_ candidates: [OfficialSpot]) -> [[OfficialSpot]] {
        var out: [[OfficialSpot]] = Array(repeating: [], count: max(days, 1))
        for s in stops where (1...candidates.count).contains(s.n) {
            out[min(max(s.day, 1), out.count) - 1].append(candidates[s.n - 1])
        }
        let filled = out.filter { !$0.isEmpty }
        return filled.isEmpty ? [[]] : filled
    }

    /// 理由の文に候補の外の県の名前があれば、理由ごと出さない（案「詳しく」）
    func reasonChecked(against candidates: [OfficialSpot]) -> String {
        let areas = candidates.map { "\($0.region?.prefecture ?? "")\($0.region?.city ?? "")\($0.name)" }.joined()
        let outside = TripAIText.prefectures.contains { reason.contains($0) && !areas.contains($0) }
        return outside ? "" : reason
    }
}

// MARK: - AI なしの組み方

enum TripAIFallback {
    /// 圏外・上限・AI が答えないとき。候補の上から1日4か所前後を取り、今の割り振り（`TripDraft.plan`）に任せる
    static func plan(candidates: [OfficialSpot], days: Int, title: String) -> TripAIPlan {
        let take = min(candidates.count, max(days * 4, 2))
        let places = candidates.prefix(take).map { TripDraft.place(spot: $0) }
        let grouped = TripDraft.plan(Array(places), dayCount: days)
        var stops: [TripAIPlan.Stop] = []
        for (i, day) in grouped.enumerated() {
            for p in day {
                if let n = candidates.firstIndex(where: { TripDraft.place(spot: $0).id == p.id }) {
                    stops.append(.init(n: n + 1, day: i + 1))
                }
            }
        }
        return TripAIPlan(title: title, days: max(days, 1), stops: stops, reason: "")
    }
}

// MARK: - 言葉

enum TripAIText {
    static let prefectures = ["北海道", "青森", "岩手", "宮城", "秋田", "山形", "福島", "茨城", "栃木", "群馬", "埼玉", "千葉", "東京", "神奈川",
        "新潟", "富山", "石川", "福井", "山梨", "長野", "岐阜", "静岡", "愛知", "三重", "滋賀", "京都", "大阪", "兵庫", "奈良", "和歌山",
        "鳥取", "島根", "岡山", "広島", "山口", "徳島", "香川", "愛媛", "高知", "福岡", "佐賀", "長崎", "熊本", "大分", "宮崎", "鹿児島", "沖縄"]

    /// 例のチップ（押すとそのまま送る）
    static var examples: [String] {
        [L("今週末の日帰り", "Day trip this weekend"), L("行きたい場所で2日", "2 days from my saved places"), L("秋の京都", "Kyoto in autumn")]
    }

    static var placeholder: String { L("例: 来月、金沢に1泊2日。紅葉", "e.g. Kanazawa, 2 days next month, autumn leaves") }

    /// 題が無いときの題（行き先の県と日数）
    static func defaultTitle(prefecture: String?, days: Int) -> String {
        let place = prefecture.map(TripAIDestination.prefectureShort) ?? L("旅", "Trip")
        return days <= 1 ? L("\(place)の日帰り", "\(place) day trip") : L("\(place)の\(days)日", "\(days) days in \(place)")
    }

    /// 上限・残りの帯の文（日本時間の翌月1日に戻る）
    static func remainingLine(remaining: Int, resetsOn: String?) -> String {
        let when = resetsOn.flatMap(monthDay) ?? ""
        if remaining <= 0 {
            return when.isEmpty ? L("今月の AI の回数を使い切りました", "You've used this month's AI plans")
                : L("今月の AI の回数を使い切りました。\(when)に戻ります", "You've used this month's AI plans. Resets \(when).")
        }
        return when.isEmpty ? L("今月の AI はあと\(remaining)回", "\(remaining) AI plans left this month")
            : L("今月の AI はあと\(remaining)回。\(when)に戻ります", "\(remaining) AI plans left this month. Resets \(when).")
    }

    /// "2026-12-01" → 「12月1日」
    static func monthDay(_ ymd: String) -> String? {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return L("\(p[1])月\(p[2])日", "\(p[1])/\(p[2])")
    }

    /// 日本時間の翌月1日（サーバーの `resetsOn` と同じ）
    static func nextReset(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let c = cal.dateComponents([.year, .month], from: now)
        var y = c.year ?? 2026
        var m = (c.month ?? 1) + 1
        if m > 12 { m = 1; y += 1 }
        return String(format: "%04d-%02d-01", y, m)
    }
}
