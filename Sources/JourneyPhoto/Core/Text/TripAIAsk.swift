import Foundation

/// AI に頼む中身（札 #621・2026-11-15 owner が採った磨き直しの案「打つより押す」）。
///
/// 行き先・日数・好みの3つの札と、足したいときだけの1行。**行き先と日数はアプリが決める**（AI は使わない）。
/// AI に渡す文は `requestText`（行き先と日数と好みと足した1行をつないだもの）
struct TripAIAsk: Equatable {
    /// 行き先の表示（「金沢」「石川県」）。空なら「選んでください」
    var place: String
    /// 行き先の県（候補を選ぶ範囲）。空なら行き先が決まっていない
    var prefectures: [String]
    /// 行き先の市（候補の点を上げる）
    var cities: Set<String>
    /// 日数（1〜7）。nil は「選んでください」
    var days: Int?
    /// 好み（「紅葉」「温泉」「ゆっくり」など）。nil は無し
    var preference: String?
    /// 足した1行（なくてよい）
    var extra: String = ""
    /// 先に入れたい場所（札の元になった行きたい場所）
    var mustSpotIds: [String] = []
    /// 行き先を選ばずに作ったので、アプリが決めた（「行き先はおまかせで、○○にしました」を出す・2026-11-23 owner）
    var autoPlaced: Bool = false

    var hasPlace: Bool { !prefectures.isEmpty }
    var isComplete: Bool { hasPlace && days != nil }

    /// 日数の言い方（日帰り・1泊2日・2泊3日）
    static func daysLabel(_ d: Int) -> String {
        d <= 1 ? L("日帰り", "Day trip") : L("\(d - 1)泊\(d)日", "\(d) days")
    }

    /// AI に渡す文
    var requestText: String {
        var parts = [place]
        if let days { parts.append(Self.daysLabel(days)) }
        if let preference { parts.append(preference) }
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: "、")
    }

    /// 打った文から札を埋める（行き先・日数・好み）。読めなかった札は空のまま（光らせて選ばせる）
    static func reading(_ text: String, spots: [OfficialSpot]) -> TripAIAsk {
        let match = TripAIDestination.match(text, spots: spots)
        let place = match.map { m in
            m.cities.count == 1 ? TripAIDestination.cityKeys(m.cities.first ?? "").min(by: { $0.count < $1.count }) ?? (m.prefectures.first ?? "")
                : TripAIDestination.prefectureShort(m.prefectures.first ?? "")
        } ?? ""
        return TripAIAsk(place: place, prefectures: match?.prefectures ?? [], cities: match?.cities ?? [],
                         days: TripAIDays.parse(text), preference: TripAIPreference.of(text), extra: text)
    }

    /// 日数の札の選択肢
    static let dayChoices = [1, 2, 3, 4]

    /// 行き先が空なら、アプリが行き先を決めて埋める（`TripAIAutoPlace`）。決められなければそのまま返す
    func withAutoPlace(spots: [OfficialSpot], wishlist: Set<String>, now: Date = Date()) -> TripAIAsk {
        guard !hasPlace, let pick = TripAIAutoPlace.choose(text: extra, spots: spots, wishlist: wishlist, now: now) else { return self }
        var out = self
        out.place = pick.place
        out.prefectures = pick.prefectures
        out.cities = pick.cities
        out.mustSpotIds = []
        out.autoPlaced = true
        return out
    }
}

/// 行き先を選ばずに「この内容で作る」を押したときの行き先（2026-11-23 owner「めんどいから行き先指定なしでも作れるようにして」）。
///
/// AI は使わない（回数を増やさない）。決めた行き先で頼むので、端末の AI もサーバーの AI も今の道のまま動く（サーバーは変えない）。
/// 決め方の順（2026-11-23 判断）:
/// 1. 頼みの文（足した1行）に地名があればそれ
/// 2. 行きたい場所に入っている県のうち、いちばん多い県
/// 3. 今の季節に見頃の案内がある観光スポットがいちばん多い県
/// 4. どれも無ければ、写真のある観光スポットがいちばん多い県（よく見られる所。人気の数は台帳に無いので、載っている数で見る）
/// 同じ数なら県の名前の順（`TripAISuggestion.groupsByPrefecture`）。国内の公開の観光スポットだけを見る
enum TripAIAutoPlace {
    enum Source: Equatable { case text, wishlist, season, popular }

    struct Pick: Equatable {
        let place: String
        let prefectures: [String]
        let cities: Set<String>
        let source: Source
    }

    static func choose(text: String, spots: [OfficialSpot], wishlist: Set<String>, now: Date = Date()) -> Pick? {
        let read = TripAIAsk.reading(text, spots: spots)
        if read.hasPlace {
            return Pick(place: read.place, prefectures: read.prefectures, cities: read.cities, source: .text)
        }
        let domestic = spots.filter { ($0.region?.country ?? "").isEmpty && !$0.isDraft && $0.region?.prefecture != nil }
        if let pref = TripAISuggestion.groupsByPrefecture(domestic.filter { wishlist.contains($0.spotId) }).first?.prefecture {
            return pick(pref, .wishlist)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let season = SpotBodyText.season(ofMonth: cal.component(.month, from: now))
        if let pref = TripAISuggestion.groupsByPrefecture(domestic.filter { $0.hasSeason(season) }).first?.prefecture {
            return pick(pref, .season)
        }
        if let pref = TripAISuggestion.groupsByPrefecture(domestic.filter(\.hasPhoto)).first?.prefecture
            ?? TripAISuggestion.groupsByPrefecture(domestic).first?.prefecture {
            return pick(pref, .popular)
        }
        return nil
    }

    private static func pick(_ prefecture: String, _ source: Source) -> Pick {
        Pick(place: TripAIDestination.prefectureShort(prefecture), prefectures: [prefecture], cities: [], source: source)
    }

    /// 作ったプランの上に出す1行
    static func line(place: String) -> String {
        L("行き先はおまかせで、\(place)にしました", "No place chosen, so we picked \(place)")
    }

    /// 行き先の札の既定（選ばなくても作れる）
    static var slotLabel: String { L("おまかせ", "Any") }
}

/// 好みの札（頼みの文から拾う語と、押すだけで足せる語）
enum TripAIPreference {
    static let words = ["紅葉", "桜", "夜景", "温泉", "雪", "海", "朝", "夕日"]
    static func of(_ text: String) -> String? { words.first { text.contains($0) } }
}

/// 一覧の上に出す「AI で作る」の札（決まった手順で出す。AI は使わない・回数0）。
/// ① 行きたい場所が3か所以上ある県（多い順）、② 今月の季節の案内が多い県、の順に2枚まで
struct TripAISuggestion: Identifiable, Equatable {
    var id: String { "\(kind)-\(ask.place)" }
    enum Kind: String { case wishlist, season }
    let kind: Kind
    let ask: TripAIAsk
    /// 「金沢　1泊2日」
    let title: String
    /// 「行きたい場所の5か所から　紅葉」
    let subtitle: String
    /// 札の写真（3枚まで）
    let photoSpots: [OfficialSpot]

    static func make(spots: [OfficialSpot], wishlist: Set<String>, now: Date = Date(), limit: Int = 2) -> [TripAISuggestion] {
        let domestic = spots.filter { ($0.region?.country ?? "").isEmpty && !$0.isDraft && $0.region?.prefecture != nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let season = SpotBodyText.season(ofMonth: cal.component(.month, from: now))
        let seasonWord = SpotBodyText.seasonLabel(season)
        var out: [TripAISuggestion] = []

        // ① 行きたい場所が3か所以上ある県
        let wished = domestic.filter { wishlist.contains($0.spotId) }
        let byPref = Self.groupsByPrefecture(wished).filter { $0.rows.count >= 3 }
        for (pref, rows) in byPref.prefix(limit) {
            let cityCount = Dictionary(grouping: rows) { $0.region?.city ?? "" }
            let topCity = cityCount.max { $0.value.count == $1.value.count ? $0.key > $1.key : $0.value.count < $1.value.count }
            // 半分以上が同じ市なら市の名前、それ以外は県の名前
            let useCity = (topCity?.value.count ?? 0) * 2 >= rows.count && !(topCity?.key.isEmpty ?? true)
            let place = useCity ? (TripAIDestination.cityKeys(topCity!.key).min { $0.count < $1.count } ?? pref)
                : TripAIDestination.prefectureShort(pref)
            let days = TripDraft.suggestedDayCount(places: rows.count)
            let hasSeason = rows.contains { $0.hasSeason(season) }
            let ask = TripAIAsk(place: place, prefectures: [pref], cities: useCity ? [topCity!.key] : [],
                                days: min(days, 3), preference: hasSeason ? seasonWord : nil,
                                mustSpotIds: rows.map(\.spotId))
            var sub = L("行きたい場所の\(rows.count)か所から", "From \(rows.count) saved places")
            if hasSeason, let seasonWord { sub += L("　\(seasonWord)の案内あり", "  \(seasonWord) notes") }
            out.append(TripAISuggestion(kind: .wishlist, ask: ask, title: "\(place)　\(TripAIAsk.daysLabel(ask.days ?? 1))",
                                        subtitle: sub, photoSpots: Array(rows.filter(\.hasPhoto).prefix(3))))
        }

        // ② 今月の季節の案内が多い県（行きたい場所の県と重ねない）
        if out.count < limit, let seasonWord {
            let used = Set(out.flatMap(\.ask.prefectures))
            let withSeason = domestic.filter { $0.hasSeason(season) && $0.hasPhoto }
            let seasonal = Self.groupsByPrefecture(withSeason).filter { !used.contains($0.prefecture) && $0.rows.count >= 3 }
            if let (pref, rows) = seasonal.first {
                let place = TripAIDestination.prefectureShort(pref)
                let ask = TripAIAsk(place: place, prefectures: [pref], cities: [], days: 2, preference: seasonWord)
                out.append(TripAISuggestion(kind: .season, ask: ask, title: "\(place)　\(TripAIAsk.daysLabel(2))",
                                            subtitle: L("\(seasonWord)の案内がある所", "Places with \(seasonWord) notes"),
                                            photoSpots: Array(rows.prefix(3))))
            }
        }
        return Array(out.prefix(limit))
    }

    /// 県ごとに束ね、多い順（同じ数なら県の名前の順）
    static func groupsByPrefecture(_ spots: [OfficialSpot]) -> [(prefecture: String, rows: [OfficialSpot])] {
        var groups: [String: [OfficialSpot]] = [:]
        for s in spots { groups[s.region?.prefecture ?? "", default: []].append(s) }
        let list: [(prefecture: String, rows: [OfficialSpot])] = groups.map { (prefecture: $0.key, rows: $0.value) }
        return list.sorted { (a: (prefecture: String, rows: [OfficialSpot]), b: (prefecture: String, rows: [OfficialSpot])) -> Bool in
            if a.rows.count != b.rows.count { return a.rows.count > b.rows.count }
            return a.prefecture < b.prefecture
        }
    }
}

/// 1か所を替える（AI を使わない・回数0）。候補は作るときに集めた場所の残りから、近い順に3つ
enum TripAISwap {
    static func choices(for spot: OfficialSpot, candidates: [OfficialSpot], used: Set<String>, limit: Int = 3) -> [OfficialSpot] {
        let rest = candidates.filter { $0.spotId != spot.spotId && !used.contains($0.spotId) }
        guard let c = spot.coords else { return Array(rest.prefix(limit)) }
        return Array(rest.sorted {
            let a = $0.coords.map { TripAICandidates.km(c, $0) } ?? .greatestFiniteMagnitude
            let b = $1.coords.map { TripAICandidates.km(c, $0) } ?? .greatestFiniteMagnitude
            return a == b ? $0.spotId < $1.spotId : a < b
        }.prefix(limit))
    }

    /// 2点の距離の言い方（「約1.2km」）
    static func distanceLabel(_ a: OfficialSpot, _ b: OfficialSpot) -> String? {
        guard let ca = a.coords, let cb = b.coords else { return nil }
        let km = TripAICandidates.km(ca, cb)
        return km < 1 ? L("約1km以内", "Within about 1 km") : L("約\(Int(km.rounded()))km", "About \(Int(km.rounded())) km")
    }
}

/// 日程の上の、押すだけの組み直し（AI を1回使う・札 #667）。
///
/// 2026-11-20 判断（owner「1のAI使う案いいとおもう」・案のページの案1の模型が正）: チップは「雨なら」「もっとゆっくり」の2つ。
/// ほかの言い方は「書いて頼む」の欄で打つ。前の「ゆっくり」「雨でも」「朝を早く」（AI で作ったプランの札の中だけ）は、
/// どのプランにも出るこのチップにまとめた（入口を2つにしない）
enum TripAITweak: String, CaseIterable, Identifiable {
    case rain, slow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rain: return L("雨なら", "If it rains")
        case .slow: return L("もっとゆっくり", "Slower pace")
        }
    }
    /// AI に渡す頼み
    var request: String {
        switch self {
        case .rain: return "雨の日でも楽しめる屋内の所を優先し、雨に向かない所は外すか別の日へ"
        case .slow: return "もっとゆっくり回りたい。1日3か所まで。入らない所は別の日へ"
        }
    }
}
