import Foundation

/// 探すの「撮影スポット」の段と、そこから開く一覧（札 #524・2026-11-11）。
///
/// 撮影スポット（台帳・`OfficialSpot`）を**地方 → 都道府県**で選べる形にまとめる。
/// 県の決め方・一覧の行・名前と別名での絞り方は、地図の「リスト」と同じ `RegionList.sections`
/// （写しを作らない）。ここで足すのは、地方ごとの束ね・並び・段の札の表紙だけ。
///
/// - 段の札（`groups`）: 地方（`PrefectureRegions` の北から）ごとに、撮影スポットのある県だけを
///   北から（JIS の順）。**0件の県・0件の地方は出さない**
/// - 全国の一覧（`nationalSections`）: 県を北から → 国（名前の順）→ 海外（その他）→ 分けられないもの。
///   起点（現在地）があっても県の順は動かさない（上の地方の札から跳ぶ先が動かないように）。県の中の行は近い順
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum SpotPrefectureIndex {

    /// 県の札（名前・件数・表紙）
    struct Card: Identifiable, Equatable {
        let prefecture: String
        let count: Int
        /// 表紙にする撮影スポットの写真（台帳の代表写真）。どの行も持たなければ nil
        let cover: SpotImage?
        /// 表紙がまだ無く、詳細を読めば写真が分かるかもしれない行（まだ索引だけの行の先頭）。
        /// 段は**出ている地方の札のこれだけ**詳細を読む（`OfficialSpotService.withDetails`・`SpotDetailNeeds`）
        var pending: OfficialSpot? = nil

        var id: String { prefecture }
    }

    /// 地方と、その中の県の札
    struct Group: Identifiable, Equatable {
        let region: PrefectureRegions.Region
        let cards: [Card]
        /// 地図の札に出す上位の名前（`topNames`・Web の `topSpotsByArea` と同じ並べ方）
        var names: [String] = []

        var id: String { region.name }
        var title: String { L(region.name, PrefectureRegions.englishName(region)) }
        /// 地方の中の撮影スポットの数（チップに添える）
        var count: Int { cards.reduce(0) { $0 + $1.count } }
    }

    /// 読み込みの段階（段の「読み込み中・失敗・空」を分ける）
    enum Load: Equatable {
        case loading
        case ready
        case failed
    }

    /// 撮影スポットから地方ごとの県の札。県の決め方は地図の「リスト」と同じ（`RegionList.sections`）
    static func groups(spots: [OfficialSpot]) -> [Group] {
        // 台帳の並び（索引に載っている順）。地図の札の上位の名前で、同じ段のときに使う
        let order = Dictionary(spots.enumerated().map { ($1.spotId, $0) }, uniquingKeysWith: { first, _ in first })
        return groups(RegionList.sections(photos: [], spots: spots, from: nil), order: order)
    }

    /// 地図の札に出す名前の数（Web の札と同じ 4 件）
    static let nameCount = 4

    /// 地方の上位の名前。**代表写真がある行 → 台帳の並び**（Web の `topSpotsByArea`: 公開済み → 代表写真 → 台帳の並び。
    /// 一覧に出るのは公開済みだけなので、残るのは写真と台帳の並び）
    static func topNames(_ rows: [OfficialSpotList.Row], order: [String: Int]) -> [String] {
        rows.enumerated()
            .sorted { a, b in
                let (pa, pb) = (a.element.spot.hasPhoto ? 0 : 1, b.element.spot.hasPhoto ? 0 : 1)
                if pa != pb { return pa < pb }
                let (oa, ob) = (order[a.element.spot.spotId] ?? Int.max, order[b.element.spot.spotId] ?? Int.max)
                return oa != ob ? oa < ob : a.offset < b.offset
            }
            .prefix(nameCount)
            .map(\.element.spot.name)
    }

    /// 地図の札の名前の行（「阿寒湖・大雪山 旭岳・ファーム富田・五稜郭 ほか」）。全部出せたら「ほか」を付けない
    static func namesLine(_ group: Group) -> String {
        let joined = group.names.joined(separator: L("・", ", "))
        return group.count > group.names.count ? L("\(joined) ほか", "\(joined), and more") : joined
    }

    /// 県の段（撮影スポットの行を持つもの）から地方ごとの県の札
    static func groups(_ sections: [RegionList.Section], order: [String: Int] = [:]) -> [Group] {
        var byPrefecture: [String: [OfficialSpotList.Row]] = [:]
        for section in sections {
            guard case .prefecture(let name) = section.key, !section.spots.isEmpty else { continue }
            byPrefecture[name, default: []].append(contentsOf: section.spots)
        }
        return PrefectureRegions.all.compactMap { region in
            let cards = region.prefectures.compactMap { name -> Card? in
                guard let rows = byPrefecture[name], !rows.isEmpty else { return nil }
                let picked = cover(rows)
                return Card(prefecture: name, count: rows.count, cover: picked,
                            pending: picked == nil ? pendingCover(rows) : nil)
            }
            guard !cards.isEmpty else { return nil }
            let rows = region.prefectures.flatMap { byPrefecture[$0] ?? [] }
            return Group(region: region, cards: cards, names: topNames(rows, order: order))
        }
    }

    /// 表紙の写真。**写真の数が多い撮影スポット**の代表写真（同じなら名前の順で先）。
    /// 2026-11-11 判断: 人が撮っている場所を県の顔にする。探すの段は写真を渡さずに束ねる（全写真を県に
    /// 振り分ける計算を探すの画面で回さない）ので、そこでは数が全部 0 で名前の順になる
    static func cover(_ rows: [OfficialSpotList.Row]) -> SpotImage? {
        rows.filter { $0.spot.photo != nil }
            .min { a, b in
                a.photoCount != b.photoCount ? a.photoCount > b.photoCount : a.spot.name < b.spot.name
            }?
            .spot.photo
    }

    /// 表紙のために詳細を読む行: **まだ索引だけで、索引が「写真あり」と言っている行**（`hasPhoto`）。
    /// 写真の無い行の詳細を読んでも表紙は増えない（確かめ役の指摘・2026-11-11）。並べ方は `cover` と同じ
    static func pendingCover(_ rows: [OfficialSpotList.Row]) -> OfficialSpot? {
        rows.filter { $0.spot.isIndexOnly && $0.spot.hasPhoto }
            .min { a, b in
                a.photoCount != b.photoCount ? a.photoCount > b.photoCount : a.spot.name < b.spot.name
            }?
            .spot
    }

    /// 表紙の詳細を読む `.task(id:)` の鍵。**画面に出ていない間は空**——出ていない間に届いた答えは捨てるので、
    /// 戻ったときに鍵が変わって読み直す（確かめ役の指摘・2026-11-11。以前は同じ鍵のまま読み直さなかった）
    static func coverTaskKey(_ needs: [OfficialSpot], onScreen: Bool) -> String {
        onScreen ? SpotDetailNeeds.key(needs) : ""
    }

    /// 索引を読んだ結果。**取り消された回は nil**（段階を変えない）。失敗は spots が nil で `.failed`。
    /// 探すは最初の読み込み・「もう一度試す」・引き下げの3か所からこれを通す（`SearchView.loadSpotIndex`）
    static func loaded(_ fetch: () async throws -> [OfficialSpot]) async -> (spots: [OfficialSpot]?, load: Load)? {
        do {
            let spots = try await fetch()
            return (spots, .ready)
        } catch {
            if Task.isCancelled || error is CancellationError { return nil }
            return (nil, .failed)
        }
    }

    /// 一覧の段（全国の並び・撮影スポットの行だけ）。**写真は県に振り分けない**——行の枚数は数えておいた
    /// `counts`（`OfficialSpotList.photoCounts`）を当てる。県の決め方・絞り方は `RegionList.sections` のまま
    static func listSections(spots: [OfficialSpot], query: String, aliases: [String: [String]],
                             counts: [String: Int], from center: Photo.Coords?) -> [RegionList.Section] {
        nationalSections(RegionList.sections(photos: [], spots: spots, query: query, aliases: aliases, from: center))
            .map { section in
                RegionList.Section(key: section.key, isCurrent: section.isCurrent, photos: [],
                                   spots: section.spots.map {
                                       OfficialSpotList.Row(spot: $0.spot, km: $0.km, photoCount: counts[$0.spot.spotId] ?? 0)
                                   })
            }
    }

    /// 段に出ている地方の札で、表紙のために詳細を読む行（無ければ空・通信しない）
    static func coverNeeds(_ group: Group?) -> [OfficialSpot] {
        group?.cards.compactMap(\.pending) ?? []
    }

    /// 段で最初に選んでおく地方。前に選んだ地方がまだあればそれ、無ければ**撮影スポットのいちばん多い地方**
    /// （同じなら北から）。2026-11-11 判断: 北から順（北海道）だと、件数の少ない地方で段が始まりやすい。
    /// 板 Search の「都道府県から探す」も多い順に並べている
    static func selected(_ name: String?, in groups: [Group]) -> Group? {
        if let name, let hit = groups.first(where: { $0.region.name == name }) { return hit }
        return groups.enumerated().max { a, b in
            a.element.count != b.element.count ? a.element.count < b.element.count : a.offset > b.offset
        }?.element
    }

    /// 全国の一覧の並び。**撮影スポットの行のある段だけ**（写真だけの段は出さない）。
    /// 県は北から、国は名前の順、海外（その他）・分けられないものは最後
    /// 地方の段だけ（地図の札の「すべて見る」の先・県は北から）
    static func regionSections(_ national: [RegionList.Section], region regionName: String) -> [RegionList.Section] {
        guard let region = PrefectureRegions.all.first(where: { $0.name == regionName }) else { return [] }
        let names = Set(region.prefectures)
        return national.filter { section in
            if case .prefecture(let name) = section.key { return names.contains(name) }
            return false
        }
    }

    static func nationalSections(_ sections: [RegionList.Section]) -> [RegionList.Section] {
        func rank(_ key: RegionList.Key) -> (Int, Int, String) {
            switch key {
            case .prefecture(let name): return (0, RegionList.prefectures.firstIndex(of: name) ?? Int.max, "")
            case .country(let name): return (1, 0, name)
            case .abroad: return (2, 0, "")
            case .unknown: return (3, 0, "")
            }
        }
        return sections
            .filter { !$0.spots.isEmpty }
            .sorted { rank($0.key) < rank($1.key) }
    }

    /// 全国の一覧の上の「跳ぶ」チップ: 地方（段のある地方だけ・北から）と、海外の段があれば「海外」。
    /// `target` はその地方で最初に出る段の id（`RegionList.Section.id`）
    struct Jump: Identifiable, Equatable {
        let id: String
        let title: String
        let target: String
        /// 跳ぶ先の見出しの字（読み上げの値・UI テストが着いたかを見る）
        let targetTitle: String
    }

    static func jumps(_ national: [RegionList.Section]) -> [Jump] {
        var out: [Jump] = []
        for region in PrefectureRegions.all {
            let names = Set(region.prefectures)
            if let first = national.first(where: { section in
                if case .prefecture(let name) = section.key { return names.contains(name) }
                return false
            }) {
                out.append(Jump(id: region.name, title: L(region.name, PrefectureRegions.englishName(region)),
                                target: first.id, targetTitle: first.title))
            }
        }
        if let abroad = national.first(where: { section in
            switch section.key {
            case .country, .abroad: return true
            default: return false
            }
        }) {
            out.append(Jump(id: "abroad", title: L("海外", "Outside Japan"), target: abroad.id, targetTitle: abroad.title))
        }
        return out
    }

    /// 県の札の読み上げ（「京都府、15件、写真: 作者」）。区切りは英語では「, 」
    static func spokenCard(_ card: Card) -> String {
        var parts = [card.prefecture, countLabel(card.count)]
        if let cover = card.cover { parts.append(cover.creditAuthor) }
        return parts.joined(separator: L("、", ", "))
    }

    /// 札の下の出典の字。開ける先があれば作者だけ（ライセンスは押した先のメニュー）、無ければ作者とライセンス
    static func creditText(_ photo: SpotImage) -> String {
        photo.creditLinks.isEmpty ? photo.credit : photo.creditAuthor
    }

    /// 一覧の行の枚数（撮影スポット id → 枚数）。**写真か結びが変わったときだけ数え直す**。
    /// 2026-11-11（確かめ役の見直し）: 以前は一覧を開いたときと結びが変わったときだけ数え、写真が後から届いても
    /// 全行が 0 枚（＝最初の1枚への誘い）のままだった
    struct PhotoCounter: Equatable {
        private(set) var counts: [String: Int] = [:]
        /// 数え直した回数（試験で「同じ材料なら数えない」を見る）
        private(set) var builds = 0
        private var key: Key?

        /// 数える材料（写真の id と本人が選んだ撮影スポット・結びの表）
        struct Key: Equatable {
            let photos: [String]
            let links: SpotPhotoLinks
        }

        static func key(_ photos: [Photo], links: SpotPhotoLinks) -> Key {
            Key(photos: photos.map { "\($0.id)|\($0.spotId ?? "")" }, links: links)
        }

        mutating func refresh(_ photos: [Photo], links: SpotPhotoLinks) {
            let next = Self.key(photos, links: links)
            guard next != key else { return }
            key = next
            counts = OfficialSpotList.photoCounts(photos, links: links)
            builds += 1
        }
    }

    /// 段の見出しの右の件数（「15件」）
    static func countLabel(_ count: Int) -> String {
        L("\(count)件", count == 1 ? "1 spot" : "\(count) spots")
    }
}
