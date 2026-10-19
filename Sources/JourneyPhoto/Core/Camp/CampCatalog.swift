import Foundation

// 写真で作るキャンプ場の部品（板「写真で作るキャンプ場」CampDex・版 25・2026-10-18）。
//
// - 24 分類・96 部品。1 分類に 4 つ、色ちがいではなく**形ちがい**
// - id は `分類.部品`（英小文字と _ だけ）。アプリの中では前に `camp.` を付ける
//   （キャンピングカーは `camper.`。別の担当なので重ならないよう前置きで分ける）
// - 置き場所 8: 寝る所・火と料理・灯り・置き物・自然・地面・道具・島
// - 珍しさ 4 段: いつもの 23（最初から持つ）／ときどき 32／めずらしい 31／とても珍しい 10
// - 端末だけで判定 79・要サーバー 17。**要サーバーの部品はサーバーの口ができるまで「近日」と出して数から外す**
//   （旅の投稿の数・友達・スポットの種類・行事の暦・天気。DB と費用は owner の承認が要る・2026-10-18）

/// 置き場所（図鑑のタブ）
enum CampPlace: String, CaseIterable, Sendable {
    case shelter, fire, light, furniture, nature, ground, gear, island

    var name: String {
        switch self {
        case .shelter: return L("寝る所", "Shelter")
        case .fire: return L("火と料理", "Fire & cooking")
        case .light: return L("灯り", "Light")
        case .furniture: return L("置き物", "Furniture")
        case .nature: return L("自然", "Nature")
        case .ground: return L("地面", "Ground")
        case .gear: return L("道具", "Gear")
        case .island: return L("島", "Island")
        }
    }
}

/// 珍しさ。印は真鍮の四角の数（いつもの 1 … とても珍しい 4・黒地の上だけ）
enum CampRarity: Int, CaseIterable, Comparable, Sendable {
    case common = 1, uncommon, rare, epic

    static func < (a: CampRarity, b: CampRarity) -> Bool { a.rawValue < b.rawValue }

    /// 印の四角の数（板: 4 つのうち塗るもの）
    var marks: Int { rawValue }

    var name: String {
        switch self {
        case .common: return L("いつもの", "Common")
        case .uncommon: return L("ときどき", "Uncommon")
        case .rare: return L("めずらしい", "Rare")
        case .epic: return L("とても珍しい", "Very rare")
        }
    }
}

/// 写真に写った物（端末の画像分類で見分ける・`CampSubjectRule`）
enum CampSubject: String, CaseIterable, Codable, Sendable {
    case mountain, starrySky, forest, campfire, seaside, bamboo, park, river, waterside, lake, wetland,
         pasture, springWater, firewood, snow
}

/// 撮った時刻の段（`CampClock.slot`）。朝・昼・夕・夜に、夜明け前を足したもの
enum CampSlot: String, CaseIterable, Codable, Sendable {
    case predawn, morning, day, evening, night
}

/// 季節（日本の暦の月で分ける・`CampClock.season`）
enum CampSeason: String, CaseIterable, Codable, Sendable {
    case spring, summer, autumn, winter

    var name: String {
        switch self {
        case .spring: return L("春", "Spring")
        case .summer: return L("夏", "Summer")
        case .autumn: return L("秋", "Autumn")
        case .winter: return L("冬", "Winter")
        }
    }
}

/// サーバーが要る理由（板の「要サーバー」の札の小さな字）
enum CampServerNeed: String, CaseIterable, Sendable {
    case friends, weather, posts, spotKind, calendar

    var name: String {
        switch self {
        case .friends: return L("友達", "Friends")
        case .weather: return L("天気", "Weather")
        case .posts: return L("投稿の数", "Posts")
        case .spotKind: return L("スポットの種類", "Spot type")
        case .calendar: return L("行事の暦", "Events")
        }
    }
}

/// 集める条件。数を持つものは `CampCollection.progress` で「いま 3 / 10」を出す
enum CampUnlock: Equatable, Sendable {
    /// 最初から持つ（1 分類に 1 つ・水だけは無い）
    case starter
    /// 写真の枚数
    case photos(Int)
    /// 写真に写った物（森・川・雪など）
    case subject(CampSubject, Int)
    /// 季節の写真
    case season(CampSeason, Int)
    /// 撮った時刻（朝・夜・夜明け前）
    case time(CampSlot, Int)
    /// 写った物 × 時刻（海辺の夕方）
    case subjectAtTime(CampSubject, CampSlot, Int)
    /// 写った物 × 季節（秋の森）
    case subjectInSeason(CampSubject, CampSeason, Int)
    /// 満月の夜に撮る（日付から月齢を計算・`CampMoon`）
    case fullMoonNight
    /// 一年続けて撮る（12 か月続けて、どの月にも 1 枚以上）
    case yearRound
    /// 同じ場所で N 回
    case samePlace(Int)
    /// 撮影地 N か所
    case places(Int)
    /// 撮影地 N 都道府県（iOS の地名変換）
    case prefectures(Int)
    /// 高原の写真（標高 `CampCollection.highlandMeters` 以上）
    case highland(Int)
    /// 山頂で撮る（標高 `CampCollection.summitMeters` 以上）
    case summit
    /// 要サーバー（今は集められない）
    case server(CampServerNeed)

    var needsServer: Bool {
        if case .server = self { return true }
        return false
    }

    /// 集めるのに要る数（数の無い条件は 1）
    var target: Int {
        switch self {
        case .starter, .fullMoonNight, .summit, .server: return 1
        case .yearRound: return 12
        case .photos(let n), .subject(_, let n), .season(_, let n), .time(_, let n),
             .subjectAtTime(_, _, let n), .subjectInSeason(_, _, let n), .samePlace(let n),
             .places(let n), .prefectures(let n), .highland(let n):
            return n
        }
    }
}

/// 部品 1 つ
struct CampPart: Identifiable, Equatable, Sendable {
    /// 分類の中の名前（`ridge_canvas`）
    let key: String
    /// 分類の名前（`tent`）
    let category: String
    let rarity: CampRarity
    let unlock: CampUnlock
    /// 画面の名前（「帆布の三角」）
    let name: String
    /// 形の一言（「稜線の支柱 2 と張り綱」）。色ちがいでなく形で見分けるための説明
    let shape: String
    /// 集める条件の一文（「山の写真 10 枚」）
    let condition: String

    /// 板の id（`tent.ridge_canvas`）
    var boardId: String { category + "." + key }
    /// アプリの中の id（`camp.tent.ridge_canvas`）。キャンピングカー（`camper.`）と重ならない
    var id: String { CampCatalog.prefix + boardId }
    var needsServer: Bool { unlock.needsServer }
    var isStarter: Bool { unlock == .starter }
}

/// 分類 1 つ（4 部品）
struct CampCategory: Identifiable, Equatable, Sendable {
    let key: String
    let place: CampPlace
    let name: String
    let parts: [CampPart]

    var id: String { key }
}

/// 部品の台帳
enum CampCatalog {

    /// アプリの中の id の前置き
    nonisolated static let prefix = "camp."

    nonisolated static var allParts: [CampPart] { categories.flatMap(\.parts) }

    static func part(_ id: String) -> CampPart? {
        let board = id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
        return allParts.first { $0.boardId == board }
    }

    static func categories(in place: CampPlace) -> [CampCategory] {
        categories.filter { $0.place == place }
    }

    /// 端末だけで集められる部品（「n / 79」の分母）
    static var collectible: [CampPart] { allParts.filter { !$0.needsServer } }

    /// 最初から持つ部品（いつもの 23）
    static var starters: [CampPart] { allParts.filter(\.isStarter) }

    /// 板の 3D に形がある部品（島に立っている 9 個）。ほかは図鑑の絵だけ（板の付箋「部品の Camp の値」）
    nonisolated static let modeled: [String] = [
        "camp.tent.ridge_canvas", "camp.fire_ring.stone_ring", "camp.chair.low_sling", "camp.cooler.hard_box",
        "camp.tree.pine", "camp.rock.boulder", "camp.path.stepping_stones", "camp.island_edge.grass_lip",
        "camp.island_base.cone_rock",
    ]
}
