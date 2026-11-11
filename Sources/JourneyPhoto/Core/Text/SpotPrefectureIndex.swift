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
        groups(RegionList.sections(photos: [], spots: spots, from: nil))
    }

    /// 県の段（撮影スポットの行を持つもの）から地方ごとの県の札
    static func groups(_ sections: [RegionList.Section]) -> [Group] {
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
                            pending: picked == nil ? rows.first(where: { $0.spot.isIndexOnly })?.spot : nil)
            }
            return cards.isEmpty ? nil : Group(region: region, cards: cards)
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
                                target: first.id))
            }
        }
        if let abroad = national.first(where: { section in
            switch section.key {
            case .country, .abroad: return true
            default: return false
            }
        }) {
            out.append(Jump(id: "abroad", title: L("海外", "Outside Japan"), target: abroad.id))
        }
        return out
    }

    /// 段の見出しの右の件数（「15件」）
    static func countLabel(_ count: Int) -> String {
        L("\(count)件", count == 1 ? "1 spot" : "\(count) spots")
    }
}
