import Foundation

/// 「AI に頼む」で**引いてよいもの**の棚（札 #652）。端末の AI の道具（`AskDeviceTools`）も、AI を使わない答え
/// （言葉の表）も、ここから選ぶ。**選ぶのはアプリ**で、AI は場所を作れない。
///
/// 置くものは4つだけ（CLAUDE.md「AI はアプリの作りやセキュリティのことを答えない」の「そもそも知らない」）:
/// - 観光スポットの台帳（公開の行だけ・下書きは外す）
/// - みんなの写真（**全体に公開の写真だけ**。フォロワーのみ、親しい友達の写真は外す）
/// - その人自身の行きたい場所と旅行プラン（**端末の AI の回だけ**。サーバーの AI には送らない）
/// - 使い方の頁（Web の /help と同じ中身・`AskHelpPages`）
///
/// 作りの資料、コード、設定、DM、ほかの人の非公開の物は置かない（道具も作らない）。
/// 画面を持たない層なので Linux の `swift test` で確かめる（`AskLibraryTests`）。
struct AskLibrary {

    /// 公開の観光スポット
    let spots: [OfficialSpot]
    /// 全体に公開の写真
    let photos: [Photo]
    /// その人の行きたい場所（台帳の観光スポットだけ）
    let wishlist: [OfficialSpot]
    /// その人の旅行プラン
    let trips: [TripPlan]
    /// 現在地（近さで探すときだけ。**端末の外へ出さない**）
    let here: Photo.Coords?

    init(spots: [OfficialSpot], photos: [Photo], wishlist: [OfficialSpot] = [], trips: [TripPlan] = [],
         here: Photo.Coords? = nil) {
        self.spots = spots.filter { !$0.isDraft }
        // 公開範囲が付いていない＝全体に公開（`Photo.audience`）。ほかの人の限定公開の写真は AI に渡さない
        self.photos = photos.filter { $0.audience == nil || $0.audience?.isEmpty == true }
        self.wishlist = wishlist.filter { !$0.isDraft }
        self.trips = trips
        self.here = here
    }

    /// 「近く」の半径（km・Artifact の見本「現在地から 30km」）
    static let nearKm = 30
    /// 札に出す数の上限
    static let maxSpots = 8
    static let maxPhotos = 6

    // MARK: - 観光スポットを選ぶ

    /// 選んだ1か所（距離と、台帳の案内の文）
    struct Pick: Equatable {
        let spot: OfficialSpot
        var distanceKm: Double?
    }

    /// 選ぶ条件（言葉の表の読み取りか、端末の AI が道具に渡した型）
    struct Query: Equatable {
        var place: String?
        var season: ShootingTime.Season?
        var dayPart: ShootingTime.DayPart?
        var keyword: String?
        var near = false
        /// 書かれていた月（「11月下旬」の 11）。季節は `season` に入れてあり、ここは並べる順にだけ使う
        var month: Int?
        /// 頼んだ数（「5選」の 5・`maxSpots` まで）。無ければ `maxSpots`
        var count: Int?

        var filter: ShootingTime.Filter { .init(season: season, dayPart: dayPart) }

        /// 札に出す数（頼んだ数と `maxSpots` の小さい方）
        var limit: Int { min(max(count ?? AskLibrary.maxSpots, 1), AskLibrary.maxSpots) }
    }

    /// 頼みの文から数と月を読む（端末の AI の道具にも同じ数と月を渡す・2026-11-23 判断）
    static func requested(_ sentence: String) -> (count: Int?, month: Int?) {
        let r = SearchSentence.readByTable(sentence)
        return (r.count.map { min(max($0, 1), maxSpots) }, r.month)
    }

    /// 言葉の表の読み取りと頼みの中身から、選ぶ条件を作る
    static func query(reading: SearchSentence.Reading, intent: AskQuery.Intent, sentence: String,
                      spots: [OfficialSpot]) -> Query {
        var q = Query(season: reading.season, dayPart: reading.dayPart, near: intent.near)
        // 2026-11-23 判断（owner の画面写真「11月下旬のおすすめの観光スポット5選教えて」で見出しは5つ、札は8枚）:
        // 頼んだ数だけ選ぶ。月は季節に直してある（`SearchSentence.readByTable`）
        q.count = reading.count.map { min(max($0, 1), maxSpots) }
        q.month = reading.month
        // 地名は台帳の県と市から当てる（旅行プランの AI と同じ当て方・`TripAIDestination.match`）
        if let match = TripAIDestination.match(sentence, spots: spots), let pref = match.prefectures.first {
            q.place = match.cities.count == 1 ? match.cities.first : pref
        }
        let words = ([reading.text].compactMap { $0 } + reading.unused).filter { w in
            q.place.map { !$0.contains(w) && !w.contains($0) } ?? true
        }
        q.keyword = words.compactMap(Self.keywordWord).first { w in
            RegionList.prefecture(named: w) == nil && !TripAIText.prefectures.contains(w) && !AskQuery.nearWords.contains(w)
        }
        return q
    }

    /// 頼みの言い回しのかけら（「観光スポット教えて」→「観光スポット教」）を語から落とす。残りが言い回しの語なら nil
    /// （run 1608 の絵で、読み取りの札に「観光スポット教」が出ていた）
    static func keywordWord(_ raw: String) -> String? {
        var w = raw
        for tail in ["教えて", "教え", "教", "作って", "作", "探して", "探", "調べて", "調", "組んで", "組"] where w.hasSuffix(tail) {
            w = String(w.dropLast(tail.count))
            break
        }
        let fillers: Set<String> = ["観光スポット", "スポット", "観光", "観光地", "所", "場所", "おすすめ", "オススメ", "旅行プラン", "プラン"]
        guard !w.isEmpty, !fillers.contains(w), !SearchSentence.fillerWords.contains(w) else { return nil }
        return w
    }

    /// 条件で選ぶ。近さで探すときは現在地から `nearKm` の中を近い順、それ以外は写真のある所を先に台帳の順
    func pickSpots(_ q: Query, limit: Int = AskLibrary.maxSpots) -> [Pick] {
        let limit = min(limit, q.limit)
        var pool = spots
        if let place = q.place, !place.isEmpty {
            pool = pool.filter { s in
                let r = s.region
                return (r?.prefecture ?? "").contains(place) || (r?.city ?? "").contains(place)
                    || place.contains(r?.city ?? "\u{0}") || s.name.contains(place)
            }
        }
        if !q.filter.isEmpty { pool = ShootingTime.spots(pool, filter: q.filter) }
        if let keyword = q.keyword, !keyword.isEmpty {
            let hit = pool.filter { Self.matches($0, keyword: keyword) }
            // 語で1件も当たらなければ、語は使わない（「きれいな」のような言い回しで0件にしない）
            if !hit.isEmpty { pool = hit }
        }
        var picks = pool.map { Pick(spot: $0, distanceKm: distance(to: $0)) }
        if q.near, here != nil {
            picks = picks.filter { ($0.distanceKm ?? .infinity) <= Double(Self.nearKm) }
                .sorted { ($0.distanceKm ?? .infinity) < ($1.distanceKm ?? .infinity) }
        } else {
            // 写真のある所を先に（札の顔が空にならない）。並びは崩さない
            // 2026-11-20 判断（run 1608 の絵で「おすすめ」が海外の所から並んだ）: 国内（`country` が空）を先に、その中で写真のある所を先に
            let domestic: (Pick) -> Bool = { ($0.spot.region?.country ?? "").isEmpty }
            // 2026-11-23 判断: 月を書いた頼みは、案内の文にその月がある所を先に（国内の中で、写真より先）
            let monthHit: (Pick) -> Bool = { p in q.month.map { Self.mentions(p.spot, month: $0, season: q.season) } ?? false }
            let order: (Pick) -> Int = { (domestic($0) ? 0 : 4) + (monthHit($0) ? 0 : 2) + ($0.spot.hasPhoto ? 0 : 1) }
            picks = picks.enumerated().sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }.map(\.element)
        }
        return Array(picks.prefix(limit))
    }

    /// 0件のときに1つ外した条件（語 → 時間帯 → 季節 → 近さの順）。外せる物が無ければ nil
    static func relaxed(_ q: Query) -> Query? {
        var next = q
        if next.keyword != nil { next.keyword = nil; return next }
        if next.dayPart != nil { next.dayPart = nil; return next }
        if next.near { next.near = false; return next }
        if next.season != nil, next.place != nil { next.season = nil; return next }
        return nil
    }

    /// 言い替えの文（「沖縄で冬に向く所」）
    static func phrase(_ q: Query) -> String {
        var head = q.place.map { L("\($0)で", "in \($0) ") } ?? ""
        if q.near { head = L("近くで", "nearby ") + head }
        let parts = [q.season?.label, q.dayPart?.phrase, q.keyword].compactMap { $0 }
        let cond = parts.isEmpty ? "" : parts.joined(separator: L("、", ", ")) + L("に向く", " ")
        return L("\(head)\(cond)所", "Places \(head)\(cond)".trimmingCharacters(in: .whitespaces))
    }

    /// 案内の文（その季節の文。季節が無ければ全部の季節の文）に「11月」「１１月」「十一月」があるか。
    /// 「1月」が「11月」「12月」に当たらないよう、前の字が数字でない所だけを見る
    static func mentions(_ spot: OfficialSpot, month: Int, season: ShootingTime.Season?) -> Bool {
        let texts = spot.seasons.filter { season == nil || $0.season == season?.rawValue }.map(\.text)
        let kanji = SearchSentence.kanjiNumbers.first { $0.1 == month }?.0
        return texts.contains { raw in
            let t = Array(SearchSentence.fold(raw))
            for word in ["\(month)月"] + (kanji.map { ["\($0)月"] } ?? []) {
                let w = Array(word)
                var i = 0
                while i + w.count <= t.count {
                    if Array(t[i..<(i + w.count)]) == w {
                        let before = i > 0 ? t[i - 1] : " "
                        let isDigit = before.isNumber || SearchSentence.kanjiNumbers.contains { $0.0 == String(before) }
                        if !isDigit { return true }
                    }
                    i += 1
                }
            }
            return false
        }
    }

    static func matches(_ spot: OfficialSpot, keyword: String) -> Bool {
        let k = SearchSentence.fold(keyword)
        var fields: [String] = [spot.name, spot.category ?? "", spot.summary ?? "", spot.reading ?? ""]
        fields += spot.aliases?.value ?? []
        fields += spot.seasons.map(\.text)
        fields += spot.times.map(\.text)
        return fields.contains { SearchSentence.fold($0).contains(k) }
    }

    func distance(to spot: OfficialSpot) -> Double? {
        guard let here, let c = spot.coords else { return nil }
        return TravelDistance.kilometers(from: here, to: c)
    }

    /// 札に添える1行（**台帳の案内の文をそのまま**・AI に書かせない）。季節と時間帯で絞っていればその文、
    /// 無ければ概要
    static func guide(for spot: OfficialSpot, query: Query) -> String? {
        if let g = ShootingTime.guide(for: spot, filter: query.filter) { return g }
        if let s = spot.summary, !s.isEmpty { return s }
        return nil
    }

    /// その回の季節で札と AI に渡す1行（2026-11-23 判断・owner の画面写真で、11月の頼みに本土寺の概要
    /// 「…アジサイ…」が出ていた）。季節が分かればその季節の案内、無ければ概要
    static func guide(for spot: OfficialSpot, season: ShootingTime.Season?) -> String? {
        guide(for: spot, query: Query(season: season))
    }

    /// 答えの読み取りの札（`AskAnswer.chips`）から、その回の季節を読む。季節の札が無ければ nil
    static func season(fromChips chips: [String]) -> ShootingTime.Season? {
        ShootingTime.Season.allCases.first { chips.contains($0.label) }
    }

    // MARK: - みんなの写真

    /// 選んだ観光スポットで撮られた公開の写真（無ければ語で当てる）。押すと持ち主の写真の詳細へ連れて行くだけ
    func pickPhotos(near picks: [Pick], keyword: String?, limit: Int = AskLibrary.maxPhotos) -> [Photo] {
        let ids = Set(picks.map(\.spot.spotId))
        var hit = photos.filter { p in p.spotId.map(ids.contains) ?? false }
        if hit.count < limit, let keyword, !keyword.isEmpty {
            let k = SearchSentence.fold(keyword)
            for p in photos where hit.count < limit && !hit.contains(where: { $0.id == p.id }) {
                let texts = [p.title?.resolved() ?? "", p.location ?? ""] + (p.tags ?? [])
                if texts.contains(where: { SearchSentence.fold($0).contains(k) }) { hit.append(p) }
            }
        }
        return Array(hit.prefix(limit))
    }

    // MARK: - AI に渡す行（データとして囲む）

    /// 観光スポットの行（番号、名前、県と市、距離、季節と時間帯、案内の文）。案内の文は台帳の文なので囲む
    static func spotLines(_ picks: [Pick], query: Query) -> String {
        guard !picks.isEmpty else { return L("合う観光スポットはありませんでした。", "No matching spots.") }
        return picks.enumerated().map { i, p in
            let s = p.spot
            var line = "\(i + 1). " + AskGuard.dataBlock(s.name, limit: 60)
            let area = [s.region?.prefecture, s.region?.city].compactMap { $0 }.joined(separator: " ")
            if !area.isEmpty { line += " " + area }
            if let km = p.distanceKm { line += " " + AskText.distance(km) }
            let seasons = s.seasonKeys.compactMap(SpotBodyText.seasonLabel)
            let times = s.timeKeys.compactMap(SpotBodyText.timeLabel)
            if !seasons.isEmpty { line += " 季節:" + seasons.joined(separator: "/") }
            if !times.isEmpty { line += " 時間帯:" + times.joined(separator: "/") }
            if let g = guide(for: s, query: query) { line += " 案内:" + AskGuard.dataBlock(g, limit: 120) }
            return line
        }.joined(separator: "\n")
    }

    /// 写真の行（題と撮影地だけ。写真そのもの、作者のメールなどは渡さない）
    static func photoLines(_ photos: [Photo]) -> String {
        guard !photos.isEmpty else { return L("合う写真はありませんでした。", "No matching photos.") }
        return photos.enumerated().map { i, p in
            let title = p.title?.resolved() ?? ""
            return "\(i + 1). " + AskGuard.dataBlock(title.isEmpty ? L("題なし", "Untitled") : title, limit: 60)
                + (p.location.map { " 撮影地:" + AskGuard.dataBlock($0, limit: 60) } ?? "")
        }.joined(separator: "\n")
    }

    /// 行きたい場所の行（その人自身の物）
    func wishlistLines() -> String {
        guard !wishlist.isEmpty else { return L("行きたい場所はまだありません。", "No saved places yet.") }
        return wishlist.prefix(20).map { s in
            "- " + AskGuard.dataBlock(s.name, limit: 60) + " " + [s.region?.prefecture, s.region?.city].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// 旅行プランの行（その人自身の物。題と日数と場所の名前だけ）
    func tripLines() -> String {
        guard !trips.isEmpty else { return L("旅行プランはまだありません。", "No trip plans yet.") }
        let names = Dictionary(spots.map { ($0.spotId, $0.name) }, uniquingKeysWith: { a, _ in a })
        return trips.prefix(5).map { t in
            var line = "- " + AskGuard.dataBlock(t.title, limit: 40) + L(" \(t.days.count)日", " \(t.days.count) days")
            if let start = t.startDate { line += " " + start }
            let places = t.days.flatMap(\.items).compactMap { item -> String? in
                if case .spot(let id, _) = item { return names[id] }
                return nil
            }
            if !places.isEmpty { line += " 場所:" + AskGuard.dataBlock(places.prefix(8).joined(separator: "、"), limit: 160) }
            return line
        }.joined(separator: "\n")
    }
}
