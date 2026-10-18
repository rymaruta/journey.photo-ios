import Foundation

// 写真で作るキャンピングカーの「何を持っているか」（2026-10-18・札 #307）。
//
// 第1段は**サーバーを変えない**。段（バン→キャンピングカー→トレーラーつき）も、集める部品の「持っている／まだ」も、
// 既に読める自分の投稿（`Photo`）から**この端末で**数える。板「集める部品の一覧」で「要サーバー」とされた部品
// （真鍮のホイール・木のカヌー・赤茶の縞・ホログラム・友達の署名入り）は第1段に入れない（docs/CAMPER.md の第2段）。
//
// 2026-10-18: 部品の一覧は板「部品図鑑」（CamperDex）が正。33 分類・132 個（id は「分類.部品」）。どの部品も
// **形が違う**（色違いで数を稼がない。塗装 paint.* は図鑑の数に入れない別扱い）。要サーバーの 33 個は「近日」と出して数から外す。

/// 車の段（板 CamperGrow）
enum CamperStage: String, CaseIterable, Codable, Sendable {
    case van
    case camper
    case trailer

    /// 2026-10-18 判断: 段は**旅の一冊の数**（`TripBook.shelfTrips`）で決める。板の「走った旅」と同じ数え方。
    /// 3 冊でキャンピングカー、10 冊でトレーラーつき（板の「あと [旅の数] 回」）。写真の枚数では決めない
    /// （1日に 100 枚撮っても旅は 1 つ）
    static let camperBooks = 3
    static let trailerBooks = 10

    static func stage(books: Int) -> CamperStage {
        if books >= trailerBooks { return .trailer }
        if books >= camperBooks { return .camper }
        return .van
    }

    /// この段に必要な旅の数
    var requiredBooks: Int {
        switch self {
        case .van: return 0
        case .camper: return Self.camperBooks
        case .trailer: return Self.trailerBooks
        }
    }

    var name: String {
        switch self {
        case .van: return L("バン", "Van")
        case .camper: return L("キャンピングカー", "Camper")
        case .trailer: return L("トレーラーつき", "With trailer")
        }
    }

    /// 寄りの倍率（板の注記「3 段の寄りの倍率は 1.02 / 0.95 / 0.74」）
    var zoom: Double {
        switch self {
        // 初めの寄り。車（と外の置き物）が画面の横幅の 8 割前後（2026-10-18 Mac の絵 run 530: 0.95 では 5 割で小さかった）
        case .van: return 1.6
        case .camper: return 1.45
        case .trailer: return 1.05
        }
    }
}

/// 時刻と天気（板 Main の「昼・夜・雪」）
enum CamperMood: String, CaseIterable, Codable, Sendable {
    case day
    case night
    case snow

    var name: String {
        switch self {
        case .day: return L("昼", "Day")
        case .night: return L("夜", "Night")
        case .snow: return L("雪", "Snow")
        }
    }
}

/// 置き場所（図鑑の上のタブ 6・板 CamperDex）
enum CamperGroupKind: String, CaseIterable, Sendable {
    case ext, side, roof, outdoor, inside, deco

    var name: String {
        switch self {
        case .ext: return L("外まわり", "Exterior")
        case .side: return L("横と後ろ", "Side and rear")
        case .roof: return L("屋根", "Roof")
        case .outdoor: return L("外の置き物", "Campsite")
        case .inside: return L("室内", "Interior")
        case .deco: return L("飾り", "Decor")
        }
    }
}

/// 部品の分類（板「部品図鑑」CamperDex の 33 分類。id は「分類.部品」。塗装 `paint` は図鑑の数に入れない別扱い）
enum CamperCategory: String, CaseIterable, Codable, Sendable {
    // 外まわり
    case wheel, hubcap
    case tireTread = "tire_tread"
    case headlight, grille, bumper, mirror, mudflap, handle
    case windowShape = "window_shape"
    // 横と後ろ
    case ladder
    case bikeRack = "bike_rack"
    case spareCover = "spare_cover"
    // 屋根
    case roofCargo = "roof_cargo"
    case roofTent = "roof_tent"
    case solar, antenna, flag
    // 外の置き物
    case chair, table
    case firePit = "fire_pit"
    case outdoorLight = "outdoor_light"
    case rug
    // 室内
    case curtain, cushion
    case hangingLamp = "hanging_lamp"
    case plant, mug, bookshelf
    case wallWood = "wall_wood"
    case floor
    // 飾り
    case awning
    case stickerEdge = "sticker_edge"
    /// 車体の色（図鑑の数に入れない・paint.*）
    case paint

    var group: CamperGroupKind {
        switch self {
        case .wheel, .hubcap, .tireTread, .headlight, .grille, .bumper, .mirror, .mudflap, .handle, .windowShape: return .ext
        case .ladder, .bikeRack, .spareCover: return .side
        case .roofCargo, .roofTent, .solar, .antenna, .flag: return .roof
        case .chair, .table, .firePit, .outdoorLight, .rug: return .outdoor
        case .curtain, .cushion, .hangingLamp, .plant, .mug, .bookshelf, .wallWood, .floor: return .inside
        case .awning, .stickerEdge, .paint: return .deco
        }
    }

    /// 図鑑の数に入る分類（塗装は入れない）
    var inDex: Bool { self != .paint }

    /// 付けないこともできる分類（はじめは付けない）。図鑑: ルーフテントだけは最初は空き
    var optional: Bool { self == .roofTent }

    var name: String {
        switch self {
        case .wheel: return L("ホイール", "Wheels")
        case .hubcap: return L("ホイールキャップ", "Hubcaps")
        case .tireTread: return L("タイヤの溝", "Tyre tread")
        case .headlight: return L("前照灯", "Headlights")
        case .grille: return L("グリル", "Grille")
        case .bumper: return L("バンパー", "Bumper")
        case .mirror: return L("ミラー", "Mirrors")
        case .mudflap: return L("泥よけ", "Mud flaps")
        case .handle: return L("取っ手", "Handles")
        case .windowShape: return L("窓の形", "Windows")
        case .ladder: return L("はしご", "Ladder")
        case .bikeRack: return L("自転車の台", "Bike rack")
        case .spareCover: return L("スペアタイヤのカバー", "Spare cover")
        case .roofCargo: return L("屋根の積み荷", "Roof cargo")
        case .roofTent: return L("ルーフテント", "Roof tent")
        case .solar: return L("ソーラーパネル", "Solar")
        case .antenna: return L("アンテナ", "Antenna")
        case .flag: return L("旗とペナント", "Flags")
        case .chair: return L("椅子", "Chairs")
        case .table: return L("机", "Table")
        case .firePit: return L("焚き火台", "Fire pit")
        case .outdoorLight: return L("外の灯り", "Outdoor light")
        case .rug: return L("外のラグ", "Outdoor rug")
        case .curtain: return L("カーテン", "Curtains")
        case .cushion: return L("クッション", "Cushions")
        case .hangingLamp: return L("吊りランプ", "Hanging lamp")
        case .plant: return L("観葉植物", "Plants")
        case .mug: return L("マグ", "Mugs")
        case .bookshelf: return L("本棚", "Bookshelf")
        case .wallWood: return L("壁の木", "Wall wood")
        case .floor: return L("床", "Floor")
        case .awning: return L("オーニング", "Awning")
        case .stickerEdge: return L("ステッカーの縁", "Sticker edge")
        case .paint: return L("塗装", "Paint")
        }
    }

    /// 札の印（SF Symbols）
    var symbol: String {
        switch self {
        case .wheel: return "circle.circle"
        case .hubcap: return "smallcircle.filled.circle"
        case .tireTread: return "circle.dashed"
        case .headlight: return "headlight.high.beam"
        case .grille: return "square.grid.3x1.below.line.grid.1x2"
        case .bumper: return "rectangle.portrait.bottomhalf.filled"
        case .mirror: return "rectangle.on.rectangle"
        case .mudflap: return "rectangle.portrait"
        case .handle: return "hand.point.up"
        case .windowShape: return "window.casement"
        case .ladder: return "stairs"
        case .bikeRack: return "bicycle"
        case .spareCover: return "circle.inset.filled"
        case .roofCargo: return "shippingbox"
        case .roofTent: return "tent"
        case .solar: return "sun.max"
        case .antenna: return "antenna.radiowaves.left.and.right"
        case .flag: return "flag"
        case .chair: return "chair"
        case .table: return "table.furniture"
        case .firePit: return "flame"
        case .outdoorLight: return "lantern"
        case .rug: return "square.grid.3x3"
        case .curtain: return "curtains.closed"
        case .cushion: return "square.stack"
        case .hangingLamp: return "lamp.ceiling"
        case .plant: return "leaf"
        case .mug: return "mug"
        case .bookshelf: return "books.vertical"
        case .wallWood: return "rectangle.split.3x1"
        case .floor: return "square.grid.2x2"
        case .awning: return "beach.umbrella"
        case .stickerEdge: return "seal"
        case .paint: return "drop"
        }
    }
}

/// 珍しさ（板: 4 段・真鍮の四角 4 つ）
enum CamperRarity: Int, CaseIterable, Codable, Sendable, Comparable {
    case common = 1
    case occasional = 2
    case rare = 3
    case veryRare = 4

    static func < (a: CamperRarity, b: CamperRarity) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .common: return L("いつもの", "Common")
        case .occasional: return L("ときどき", "Occasional")
        case .rare: return L("めずらしい", "Rare")
        case .veryRare: return L("とても珍しい", "Very rare")
        }
    }
}

/// 自分の投稿から、この端末で数えた値（サーバーには何も聞かない・図鑑の付箋「入手の決まり」）
struct CamperStats: Equatable, Sendable {
    var posts = 0
    var books = 0
    /// 夜（19 時〜翌 4 時）に撮った写真
    var nightShots = 0
    /// 夜明け前（4 時〜6 時前）に撮った写真
    var earlyShots = 0
    /// 朝（5 時〜10 時前）に撮った写真
    var morningShots = 0
    /// 季節ごとの写真（夏 6〜8 月・冬 12〜2 月）
    var summerShots = 0
    var winterShots = 0
    /// 冬の夜の写真
    var winterNightShots = 0
    /// 撮影地の都道府県の数（撮影地の文字から読む）
    var prefectures = 0
    /// 撮った場所の数（約 100 m の升）
    var places = 0
    /// 同じ場所（約 100 m の升）で撮った回数のいちばん多いもの
    var samePlace = 0
    /// 写真の色: 森の緑・晴れた空の青
    var forestShots = 0
    var skyShots = 0
    /// 撮影地や題・タグの言葉から: 山・海辺・湖・植物・街
    var mountainShots = 0
    var seaShots = 0
    var lakeShots = 0
    var plantShots = 0
    var cityShots = 0
    /// 南の島（北緯 28.5° より南か沖縄）で撮った写真
    var southIslandShots = 0
    /// 満月の夜（月齢 13.8〜15.8 日・夜）に撮った写真
    var fullMoonShots = 0
    /// 撮った年と月の数（12 で「一年続けて撮る」とみなす）
    var months = 0
    /// 海と山を同じ日に撮った日
    var seaAndMountainDays = 0
}

/// 部品の手に入れ方。端末だけで決まるものと、サーバーが要るもの（第1段は「近日」と出して数から外す）
enum CamperUnlock: Equatable, Sendable {
    case starter
    case posts(Int)
    case books(Int)
    case night(Int)
    case early(Int)
    case morning(Int)
    case summer(Int)
    case winter(Int)
    case winterNight(Int)
    case prefectures(Int)
    case places(Int)
    case samePlace(Int)
    case forest(Int)
    case sky(Int)
    case mountain(Int)
    case sea(Int)
    case lake(Int)
    case plants(Int)
    case city(Int)
    case southIsland(Int)
    case fullMoon(Int)
    case months(Int)
    case seaAndMountain(Int)
    /// 要サーバー（旅の投稿の数・友達・スポットの種類・行事の暦・天気）。第1段では届かない
    case server(String)
    /// 端末で決まるが、まだアプリに無いもの（キャンプ場など）。第1段では届かない
    case later(String)

    /// 第1段で届くか（要サーバー・まだ無いものは「近日」）
    var isAvailable: Bool {
        switch self {
        case .server, .later: return false
        default: return true
        }
    }

    /// (いまの数, 要る数)
    func progress(_ s: CamperStats) -> (have: Int, need: Int) {
        switch self {
        case .starter: return (1, 1)
        case .posts(let n): return (s.posts, n)
        case .books(let n): return (s.books, n)
        case .night(let n): return (s.nightShots, n)
        case .early(let n): return (s.earlyShots, n)
        case .morning(let n): return (s.morningShots, n)
        case .summer(let n): return (s.summerShots, n)
        case .winter(let n): return (s.winterShots, n)
        case .winterNight(let n): return (s.winterNightShots, n)
        case .prefectures(let n): return (s.prefectures, n)
        case .places(let n): return (s.places, n)
        case .samePlace(let n): return (s.samePlace, n)
        case .forest(let n): return (s.forestShots, n)
        case .sky(let n): return (s.skyShots, n)
        case .mountain(let n): return (s.mountainShots, n)
        case .sea(let n): return (s.seaShots, n)
        case .lake(let n): return (s.lakeShots, n)
        case .plants(let n): return (s.plantShots, n)
        case .city(let n): return (s.cityShots, n)
        case .southIsland(let n): return (s.southIslandShots, n)
        case .fullMoon(let n): return (s.fullMoonShots, n)
        case .months(let n): return (s.months, n)
        case .seaAndMountain(let n): return (s.seaAndMountainDays, n)
        case .server, .later: return (0, 1)
        }
    }

    func isMet(_ s: CamperStats) -> Bool {
        guard isAvailable else { return false }
        let p = progress(s)
        return p.have >= p.need
    }

    /// 0〜1 の進み具合（真鍮の細い棒）
    func fraction(_ s: CamperStats) -> Double {
        guard isAvailable else { return 0 }
        let p = progress(s)
        guard p.need > 0 else { return 1 }
        return min(1, max(0, Double(p.have) / Double(p.need)))
    }

    /// 入手の条件の短い言い方（図鑑の「入手」）
    var condition: String {
        switch self {
        case .starter: return L("最初から", "From the start")
        case .posts(let n): return L("写真 \(n) 枚", "Photos: \(n)")
        case .books(let n): return n >= CamperStage.trailerBooks ? L("トレーラーまで育てる", "Grow to the trailer stage")
            : L("旅 \(n) 冊", "\(n) trips")
        case .night(let n): return L("夜の写真 \(n) 枚", "\(n) night photos")
        case .early(let n): return L("朝 6 時前の写真 \(n) 枚", "Photos before 6am: \(n)")
        case .morning(let n): return L("朝の写真 \(n) 枚", "\(n) morning photos")
        case .summer(let n): return L("夏の写真 \(n) 枚", "\(n) summer photos")
        case .winter(let n): return L("冬の写真 \(n) 枚", "\(n) winter photos")
        case .winterNight(let n): return L("冬の夜の写真 \(n) 枚", "\(n) winter-night photos")
        case .prefectures(let n): return L("撮影地 \(n) 都道府県", "\(n) prefectures")
        case .places(let n): return L("撮影地 \(n) か所", "Places: \(n)")
        case .samePlace(let n): return L("同じ場所で \(n) 回", "The same place \(n) times")
        case .forest(let n): return L("森の写真 \(n) 枚", "\(n) forest photos")
        case .sky(let n): return L("晴れの写真 \(n) 枚", "\(n) clear-sky photos")
        case .mountain(let n): return n == 1 ? L("山の上で撮る", "Shoot on a mountain") : L("山で撮った写真 \(n) 枚", "\(n) mountain photos")
        case .sea(let n): return L("海辺の写真 \(n) 枚", "\(n) seaside photos")
        case .lake(let n): return L("湖の写真 \(n) 枚", "\(n) lake photos")
        case .plants(let n): return L("植物の写真 \(n) 枚", "\(n) plant photos")
        case .city(let n): return L("街の写真 \(n) 枚", "\(n) city photos")
        case .southIsland: return L("南の島の写真", "A photo from a southern island")
        case .fullMoon: return L("満月の夜に撮る", "Shoot on a full-moon night")
        case .months(let n): return n >= 12 ? L("一年続けて撮る", "Shoot through a whole year") : L("\(n) か月撮る", "\(n) months")
        case .seaAndMountain: return L("海と山を同じ日に撮る", "Shoot the sea and a mountain on one day")
        case .server(let text), .later(let text): return text
        }
    }

    /// 入手のしかた（一行）
    var how: String {
        switch self {
        case .starter: return L("最初から", "From the start")
        case .server, .later: return L("近日。\(condition)と届くようになります", "Coming soon: \(condition)")
        default: return L("\(condition)で届きます", "Arrives with: \(condition)")
        }
    }

    /// 届いた理由（届いたときの画面）
    var because: String {
        self == .starter ? L("最初から持っています", "You've had it from the start") : L("\(condition)で届きました", "Arrived for: \(condition)")
    }
}

/// 集める部品の1つ
struct CamperPart: Equatable, Sendable, Identifiable {
    let category: CamperCategory
    /// 分類の中の名前（保存の鍵・図鑑の id の後ろ半分。変えない）
    let key: String
    let name: String
    /// 見た目の一行（図鑑の説明）
    let look: String
    let rarity: CamperRarity
    let unlock: CamperUnlock
    /// 色の見本（塗装・オーニング。札の丸に出す）
    var swatch: UInt32?

    /// 図鑑の id（「分類.部品」）
    var id: String { "\(category.rawValue).\(key)" }
}

/// 部品の一覧（板「部品図鑑」CamperDex が正・2026-10-18。33 分類 132 個・端末だけ 99／要サーバー 33。
/// 名前と説明と珍しさと入手の条件は図鑑のまま。英語の名前は id から作る）
enum CamperCatalog {

    private static func english(_ key: String) -> String {
        let words = key.split(separator: "_").map(String.init)
        guard let first = words.first else { return key }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    private static func p(_ c: CamperCategory, _ key: String, _ ja: String, _ look: String, _ r: CamperRarity, _ u: CamperUnlock,
                          _ swatch: UInt32? = nil) -> CamperPart {
        CamperPart(category: c, key: key, name: L(ja, english(key)), look: L(look, english(key)), rarity: r, unlock: u, swatch: swatch)
    }

    static let dex: [CamperPart] = [
        // ホイール（wheel）
        p(.wheel, "chrome_dish", "クロームの皿", "鏡の皿・ナット 6・真鍮のキャップ", .common, .starter),
        p(.wheel, "steel_black", "黒い鉄ホイール", "黒い鉄に丸い穴 6", .occasional, .posts(30)),
        p(.wheel, "whitewall", "白い帯のタイヤ", "側面に白い帯", .occasional, .prefectures(5)),
        p(.wheel, "brass_spoke", "真鍮のスポーク", "細い真鍮のスポーク 16 本", .veryRare, .server("旅を 20 回投稿")),
        // ホイールキャップ（hubcap）
        p(.hubcap, "dome_chrome", "丸いクローム", "半球の鏡", .common, .starter),
        p(.hubcap, "flat_brass", "平らな真鍮", "放射の筋の真鍮", .occasional, .samePlace(3)),
        p(.hubcap, "star_cap", "星のキャップ", "五つの角の星", .rare, .night(10)),
        p(.hubcap, "baby_moon", "小さな月", "白い縁に小さな鏡", .rare, .fullMoon(1)),
        // タイヤの溝（tire_tread）
        p(.tireTread, "road_rib", "縦溝", "縦にまっすぐの溝 4 本", .common, .starter),
        p(.tireTread, "all_terrain", "山道の溝", "斜めにずれたブロック", .occasional, .mountain(10)),
        p(.tireTread, "mud_block", "泥のブロック", "大きな角ブロック", .rare, .server("雨の日に撮る")),
        p(.tireTread, "snow_sipe", "雪の切れ込み", "細いジグザグの切れ込み", .occasional, .winter(20)),
        // 前照灯（headlight）
        p(.headlight, "round", "丸い前照灯", "クロームの縁と反射板の輪", .common, .starter),
        p(.headlight, "square", "角形", "四角い縁と平らなレンズ", .occasional, .night(10)),
        p(.headlight, "twin_round", "二灯", "小さな丸を二つ並べる", .occasional, .places(3)),
        p(.headlight, "rally_brass", "真鍮のラリーランプ", "真鍮の丸灯 2 と横の棒", .rare, .early(3)),
        // グリル（grille）
        p(.grille, "bars_chrome", "横の桟", "クロームの桟 5 本", .common, .starter),
        p(.grille, "vertical_slats", "縦の桟", "細い縦の桟 10 本", .occasional, .posts(60)),
        p(.grille, "honeycomb", "蜂の巣", "六角の網", .rare, .server("旅を 5 回投稿")),
        p(.grille, "mesh_brass", "真鍮の網", "斜めに編んだ真鍮", .veryRare, .months(12)),
        // バンパー（bumper）
        p(.bumper, "chrome_blade", "クロームの刃", "細く長い鏡の棒", .common, .starter),
        p(.bumper, "black_steel", "黒い鉄板", "ボルト 8 の鉄板", .occasional, .posts(90)),
        p(.bumper, "wood_beam", "木の梁", "木目の梁と黒い金具", .rare, .server("森のスポットで撮る")),
        p(.bumper, "bullbar", "ブルバー", "前を囲う太い鉄の枠", .rare, .prefectures(10)),
        // ミラー（mirror）
        p(.mirror, "rect_black", "四角い黒", "黒い枠の四角い鏡", .common, .starter),
        p(.mirror, "round_chrome", "丸いクローム", "丸い鏡と細い腕", .occasional, .samePlace(3)),
        p(.mirror, "tall_tow", "縦長の牽引ミラー", "上下二本の腕で支える", .rare, .books(10)),
        p(.mirror, "brass_oval", "真鍮の楕円", "楕円の真鍮の枠", .veryRare, .server("友達から贈られる")),
        // 泥よけ（mudflap）
        p(.mudflap, "rubber_plain", "黒いゴム", "無地の黒い板", .common, .starter),
        p(.mudflap, "logo_brass", "真鍮の印", "丸い真鍮の印つき", .occasional, .posts(50)),
        p(.mudflap, "checker", "市松", "白黒の市松", .rare, .server("旅を 3 回投稿")),
        p(.mudflap, "long_rally", "長いラリー", "長く垂れて赤い帯", .rare, .seaAndMountain(1)),
        // 取っ手（handle）
        p(.handle, "chrome_bar", "クロームの棒", "棒と留め具 2", .common, .starter),
        p(.handle, "recessed", "埋め込み", "扉に沈んだ取っ手と鍵", .occasional, .posts(40)),
        p(.handle, "brass_lever", "真鍮のレバー", "丸い座金と横のレバー", .rare, .samePlace(5)),
        p(.handle, "rope_loop", "縄の輪", "真鍮の環に麻縄", .rare, .sea(10)),
        // 窓の形（window_shape）
        p(.windowShape, "rounded_rect", "角丸の窓", "角の丸い一枚窓", .common, .starter),
        p(.windowShape, "slider_split", "引き違い", "二枚の引き違い", .occasional, .posts(70)),
        p(.windowShape, "porthole", "丸窓", "ネジ 10 のクロームの丸窓", .rare, .server("港で撮る")),
        p(.windowShape, "arched", "アーチの窓", "上が弧の窓と十字の桟", .veryRare, .server("季節の行事の日に撮る")),
        // はしご（ladder）
        p(.ladder, "chrome_rails", "クロームのはしご", "柱 2 と段 7", .common, .starter),
        p(.ladder, "black_alu", "黒いアルミ", "滑り止めの段", .occasional, .posts(80)),
        p(.ladder, "folding", "折りたたみ", "途中で折れる真鍮の蝶番", .rare, .prefectures(7)),
        p(.ladder, "wood_rungs", "木の段", "木の柱と木の段", .veryRare, .server("友達のはしごを 3 回見に行く")),
        // 自転車の台（bike_rack）
        p(.bikeRack, "rear_two", "後ろに 2 台", "後ろの台に自転車 2", .occasional, .server("自転車道で撮る")),
        p(.bikeRack, "roof_one", "屋根に 1 台", "屋根の台に大きめの 1 台", .occasional, .posts(100)),
        p(.bikeRack, "folding_bike", "折りたたみ自転車", "小さな真鍮色の自転車", .rare, .server("旅を 8 回投稿")),
        p(.bikeRack, "cargo_basket", "荷かご", "鉄のかごに木箱と布の袋", .common, .starter),
        // スペアタイヤのカバー（spare_cover）
        p(.spareCover, "canvas_brass_ring", "帆布と真鍮の輪", "帆布に真鍮の輪と写真", .common, .starter),
        p(.spareCover, "leather", "革", "革に縫い目と真鍮の留め", .occasional, .posts(60)),
        p(.spareCover, "hardshell", "硬い殻", "鏡の殻と黒い中心", .rare, .server("旅を 6 回投稿")),
        p(.spareCover, "map_print", "地図柄", "自分の旅の道が描かれる", .veryRare, .prefectures(15)),
        // 屋根の積み荷（roof_cargo）
        p(.roofCargo, "crate_mat", "木箱とマット", "木目の箱と縫い目のマット", .common, .starter),
        p(.roofCargo, "roof_box", "ルーフボックス", "車体色の流線形", .occasional, .winter(20)),
        p(.roofCargo, "canoe", "木のカヌー", "赤茶の舟を伏せて留める", .rare, .server("水辺のスポットで撮る")),
        p(.roofCargo, "surfboard", "サーフボード", "白い板に青い線", .rare, .sea(15)),
        // ルーフテント（roof_tent）
        p(.roofTent, "clamshell", "貝殻", "斜めに開く硬い殻", .occasional, .posts(120)),
        p(.roofTent, "popup_canvas", "帆布の箱", "窓 3 つの帆布の箱", .occasional, .server("旅を 4 回投稿")),
        p(.roofTent, "triangle_hardtop", "三角の硬い屋根", "塗装の三角と窓", .rare, .mountain(1)),
        p(.roofTent, "wing", "翼のタープ", "片側に張る翼の布", .veryRare, .server("友達と同じ日に旅をする")),
        // ソーラーパネル（solar）
        p(.solar, "flat_one", "一枚", "8×2 の電池板", .common, .starter),
        p(.solar, "twin", "二枚", "二枚を並べる", .occasional, .sky(30)),
        p(.solar, "folding_suitcase", "折りたたみ", "鞄のように開く板", .rare, .server("旅を 5 回投稿")),
        p(.solar, "flexible_curve", "曲がる板", "屋根の丸みに沿う", .rare, .early(5)),
        // アンテナ（antenna）
        p(.antenna, "whip", "細い竿", "しなる細い竿", .common, .starter),
        p(.antenna, "mushroom_gps", "きのこ型", "白い半球", .occasional, .places(5)),
        p(.antenna, "dish", "パラボラ", "斜めの皿と受信部", .rare, .night(5)),
        p(.antenna, "ham_long", "長い無線の竿", "横棒 5 の長い竿", .veryRare, .server("友達 10 人と旅を交わす")),
        // 旗とペナント（flag）
        p(.flag, "pennant_triangle", "三角のペナント", "赤茶の三角に白い線", .common, .starter),
        p(.flag, "swallowtail", "燕尾の旗", "先が割れた藍の旗", .occasional, .server("旅を 2 回投稿")),
        p(.flag, "prayer_line", "連なる旗", "色の旗を紐に 6 枚", .rare, .server("旅先で 5 つの祭りの写真")),
        p(.flag, "windsock", "吹き流し", "橙と白の筒", .occasional, .server("風の強い日に撮る")),
        // 椅子（chair）
        p(.chair, "folding_chair", "布の折りたたみ", "縫い目のある布と黒い脚", .common, .starter),
        p(.chair, "director_chair", "ディレクターズ", "木の脚と藍の布", .occasional, .posts(50)),
        p(.chair, "wooden_stool", "木の丸椅子", "丸い座面と 4 本脚", .occasional, .forest(10)),
        p(.chair, "hammock", "ハンモック", "二本の柱に橙の布", .veryRare, .summer(30)),
        // 机（table）
        p(.table, "folding_alu", "アルミの折りたたみ", "細い脚の銀の机", .common, .starter),
        p(.table, "rolltop", "巻ける天板", "木の板を巻いて運ぶ", .occasional, .posts(70)),
        p(.table, "wooden_crate_table", "木箱の机", "木箱を伏せて天板を載せる", .rare, .server("旅を 6 回投稿")),
        p(.table, "camp_cube", "箱の机", "保冷箱を兼ねる箱", .occasional, .lake(5)),
        // 焚き火台（fire_pit）
        p(.firePit, "steel_bowl", "鉄の鉢", "黒い鉢と 2 本脚", .common, .starter),
        p(.firePit, "stone_ring", "石の輪", "石 9 つと三本の薪", .occasional, .later("キャンプ場で焚き火をする")),
        p(.firePit, "brazier", "火鉢", "穴の空いた鏡の鉢", .rare, .winterNight(5)),
        p(.firePit, "tripod_kettle", "三脚とやかん", "三脚から吊るす鉄の鍋", .veryRare, .server("友達の焚き火に薪をくべる 10 回")),
        // 外の灯り（outdoor_light）
        p(.outdoorLight, "brass_lantern", "真鍮のランタン", "真鍮の枠と硝子", .common, .starter),
        p(.outdoorLight, "string_lights", "電球の紐", "小さな電球 8 つ", .occasional, .night(15)),
        p(.outdoorLight, "paper_lantern", "提灯", "朱の紙の提灯", .rare, .server("夏祭りの写真")),
        p(.outdoorLight, "oil_lamp", "オイルランプ", "真鍮の油壺と硝子の火屋", .rare, .early(3)),
        // 外のラグ（rug）
        p(.rug, "woven_mat", "編んだ敷物", "麦わら色の編み目", .common, .starter),
        p(.rug, "striped", "縞のラグ", "藍と赤の縞", .occasional, .posts(40)),
        p(.rug, "round_braided", "丸い三つ編み", "色の輪を重ねる", .rare, .places(8)),
        p(.rug, "kilim", "キリム", "赤地に金のひし形", .veryRare, .server("友達から贈られる")),
        // カーテン（curtain）
        p(.curtain, "pleated_linen", "麻のひだ", "左右にひだ 5 つずつ", .common, .starter),
        p(.curtain, "cafe_short", "短いカフェ", "下半分だけの白", .occasional, .morning(10)),
        p(.curtain, "roman_blind", "たくし上げ", "段に上がる緑の布", .occasional, .posts(60)),
        p(.curtain, "beaded", "玉すだれ", "真鍮と朱と藍の玉", .veryRare, .server("季節の行事の日に撮る")),
        // クッション（cushion）
        p(.cushion, "square_plain", "四角", "生成りの四角", .common, .starter),
        p(.cushion, "bolster_round", "円筒", "緑の筒に真鍮の帯", .occasional, .posts(30)),
        p(.cushion, "knitted", "編み目", "縄編みの橙", .rare, .winter(15)),
        p(.cushion, "tasseled", "房飾り", "藍に金の房 4", .rare, .server("旅を 4 回投稿")),
        // 吊りランプ（hanging_lamp）
        p(.hangingLamp, "brass_dome", "真鍮の笠", "半球の真鍮", .common, .starter),
        p(.hangingLamp, "enamel_cone", "ホーローの円錐", "緑のホーローに白い縁", .occasional, .posts(50)),
        p(.hangingLamp, "rattan", "籐", "籐を編んだ笠", .rare, .southIsland(1)),
        p(.hangingLamp, "glass_globe", "硝子の球", "乳白の硝子の球", .veryRare, .night(30)),
        // 観葉植物（plant）
        p(.plant, "cactus", "サボテン", "腕 2 本に花", .common, .starter),
        p(.plant, "monstera", "モンステラ", "大きな葉 6 枚", .occasional, .plants(10)),
        p(.plant, "hanging_ivy", "吊るしたつる", "鉢から垂れるつる", .rare, .server("雨の写真 5 枚")),
        p(.plant, "bonsai", "盆栽", "黒い鉢と曲がった幹", .veryRare, .months(12)),
        // マグ（mug）
        p(.mug, "enamel_white", "ホーローの白", "藍の縁の白いマグ", .common, .starter),
        p(.mug, "tin_cup", "ブリキのカップ", "銀の筒と細い取っ手", .occasional, .posts(20)),
        p(.mug, "ceramic_glazed", "釉薬の陶器", "青い釉薬の丸み", .rare, .server("焼き物の町で撮る")),
        p(.mug, "double_wall", "二重硝子", "硝子の中に浮くコーヒー", .rare, .morning(20)),
        // 本棚（bookshelf）
        p(.bookshelf, "small_shelf", "小さな棚", "二段に本 17 冊", .common, .starter),
        p(.bookshelf, "wall_rack", "壁の棚板", "壁に二枚の板と小物", .occasional, .posts(80)),
        p(.bookshelf, "crate_stack", "木箱の棚", "木箱 3 つを積む", .rare, .server("旅を 7 回投稿")),
        p(.bookshelf, "map_drawer", "地図の引き出し", "真鍮の取っ手 4 と地図", .veryRare, .prefectures(20)),
        // 壁の木（wall_wood）
        p(.wallWood, "pine_boards", "松の板", "縦張りの明るい板と節", .common, .starter),
        p(.wallWood, "plywood_birch", "樺の合板", "細かい木目の白い板", .occasional, .posts(50)),
        p(.wallWood, "dark_walnut", "胡桃の横張り", "濃い横張り", .rare, .forest(20)),
        p(.wallWood, "herringbone", "ヘリンボーン", "矢筈に組む", .veryRare, .server("旅を 12 回投稿")),
        // 床（floor）
        p(.floor, "oak_planks", "ナラの板", "長い板の床", .common, .starter),
        p(.floor, "cork", "コルク", "粒の見える柔らかい床", .occasional, .posts(40)),
        p(.floor, "chevron", "シェブロン", "くの字に組む", .rare, .places(6)),
        p(.floor, "checker_tiles", "市松のタイル", "白黒のタイル", .rare, .city(20)),
        // オーニング（awning）
        p(.awning, "indigo_stripe", "藍の縞", "藍と生成りの縞", .common, .starter, 0x2F4F74),
        p(.awning, "forest_stripe", "森の緑の縞", "緑と生成りの縞", .occasional, .forest(15), 0x4A5A46),
        p(.awning, "scalloped_edge", "波の縁", "黄の布に波形の縁", .rare, .sea(20), 0xD9B24A),
        p(.awning, "rust_stripe", "赤茶の縞", "赤茶と生成りの縞", .veryRare, .server("友達から贈られる"), 0x7A2E22),
        // ステッカーの縁（sticker_edge）
        p(.stickerEdge, "white_cut", "白い切り抜き", "白い紙の縁", .common, .starter),
        p(.stickerEdge, "gold_foil", "金の箔押し", "真鍮色の箔の縁", .rare, .samePlace(3)),
        p(.stickerEdge, "holo", "ホログラム", "見る角度で虹色", .veryRare, .server("季節の行事の日に撮る")),
        p(.stickerEdge, "signed", "友達の署名入り", "友達の名前の刻印", .veryRare, .server("友達が贈る")),
    ]

    /// 塗装（図鑑の数に入れない・paint.*。板 CamperDecorate の 4 色）
    static let paints: [CamperPart] = [
        p(.paint, "cloud", "雲の影の灰", "撮った写真から拾った色", .common, .starter, 0x5B6168),
        p(.paint, "mist", "霧の白", "撮った写真から拾った色", .common, .starter, 0xD9D4C7),
        p(.paint, "sky", "朝の空の青", "晴れの写真から拾った色", .occasional, .sky(1), 0x7F97AB),
        p(.paint, "forest", "森の緑", "森の写真から拾った色", .occasional, .forest(15), 0x4A5A46),
    ]

    static let all: [CamperPart] = dex + paints

    /// 第1段で集められる部品（図鑑の数の分母。要サーバー・まだ無いものは外す）
    static var available: [CamperPart] { dex.filter { $0.unlock.isAvailable } }

    static func parts(_ c: CamperCategory) -> [CamperPart] { all.filter { $0.category == c } }

    static func part(_ id: String) -> CamperPart? { all.first { $0.id == id } }

    /// 分類の最初の部品（最初から持っている。ルーフテントには無い）
    static func starter(_ c: CamperCategory) -> CamperPart {
        parts(c).first { $0.unlock == .starter } ?? parts(c)[0]
    }

    static func owned(_ stats: CamperStats) -> Set<String> {
        Set(all.filter { $0.unlock.isMet(stats) }.map(\.id))
    }

    /// 図鑑の「持っている / 全部」（塗装は入れない・全部は第1段で集められる数）
    static func dexCount(_ owned: Set<String>) -> (have: Int, total: Int) {
        (available.filter { owned.contains($0.id) }.count, available.count)
    }
}

/// 車の飾り（分類ごとに付けている部品・オーニングを広げているか）
struct CamperLoadout: Codable, Equatable, Sendable {
    /// 分類 → 部品の key（付けないこともできる分類は "none"）
    var picks: [String: String] = [:]
    var awningOpen = false

    static let standard = CamperLoadout()
    static let none = "none"

    /// いま付けている部品の key。付けないこともできる分類は、選んでいなければ "none"
    func key(_ c: CamperCategory) -> String {
        if let k = picks[c.rawValue] { return k }
        return c.optional ? Self.none : CamperCatalog.starter(c).key
    }

    /// いま付けている部品（付けていなければ nil）
    func pickedPart(_ c: CamperCategory) -> CamperPart? {
        let k = key(c)
        guard k != Self.none else { return nil }
        return CamperCatalog.parts(c).first { $0.key == k } ?? (c.optional ? nil : CamperCatalog.starter(c))
    }

    /// いま付けている部品（付けていなければ分類の最初の部品。名前を言うときに使う）
    func part(_ c: CamperCategory) -> CamperPart { pickedPart(c) ?? CamperCatalog.starter(c) }

    mutating func pick(_ p: CamperPart) { picks[p.category.rawValue] = p.key }

    mutating func remove(_ c: CamperCategory) { picks[c.rawValue] = c.optional ? Self.none : nil }

    /// 持っていない部品は最初の部品（付けないこともできる分類は付けない）に戻す（数が減った・別の端末の控え）
    func sanitized(owned: Set<String>) -> CamperLoadout {
        var out = self
        for c in CamperCategory.allCases {
            let k = key(c)
            if k == Self.none { continue }
            let id = "\(c.rawValue).\(k)"
            if !owned.contains(id) || CamperCatalog.part(id) == nil { out.picks[c.rawValue] = nil }
        }
        return out
    }

    /// 塗装の色（0xRRGGBB）
    var paint: UInt32 { part(.paint).swatch ?? 0x5B6168 }
}

/// 飾りを人ごとにこの端末へ覚える（2026-10-18 判断: 第1段は端末だけ。第2段でサーバーへ）。
/// **鍵は人ごと**——別の人に替わったら前の人の色を使わない。退会で消す（`AccountLocalData`）
struct CamperStore {

    static func key(_ userId: String) -> String { "camper.loadout.\(userId)" }
    static func seenKey(_ userId: String) -> String { "camper.seen.\(userId)" }

    private let defaults: UserDefaults
    let userId: String?

    init(userId: String?, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.defaults = defaults
    }

    func load() -> CamperLoadout {
        guard let userId, let data = defaults.data(forKey: Self.key(userId)),
              let loadout = try? JSONDecoder().decode(CamperLoadout.self, from: data) else { return .standard }
        return loadout
    }

    func save(_ loadout: CamperLoadout) {
        guard let userId, let data = try? JSONEncoder().encode(loadout) else { return }
        defaults.set(data, forKey: Self.key(userId))
    }

    /// 「届いた」を見せ終えた部品
    var seen: Set<String>? {
        guard let userId, let list = defaults.stringArray(forKey: Self.seenKey(userId)) else { return nil }
        return Set(list)
    }

    func markSeen(_ ids: Set<String>) {
        guard let userId else { return }
        defaults.set(ids.sorted(), forKey: Self.seenKey(userId))
    }

    /// 新しく届いた部品（最初から持っているものは数えない）。珍しい順・一覧の順
    static func arrivals(owned: Set<String>, seen: Set<String>?) -> [CamperPart] {
        let fresh = owned.subtracting(seen ?? [])
        return CamperCatalog.all.filter { fresh.contains($0.id) && $0.unlock != .starter }
            .sorted { $0.rarity > $1.rarity }
    }

    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userId))
        defaults.removeObject(forKey: seenKey(userId))
    }
}

// MARK: - 投稿から数える

enum CamperCounting {

    /// 自分の投稿から数える（段と部品の入手）。`books` は旅の一冊の数（呼ぶ側が `TripBook.shelfTrips` で数える）。
    /// 2026-10-18 判断: 山・海辺・湖・植物・街は撮影地と題とタグの言葉で読む（写真の位置の標高は投稿に無い）。
    /// 一年続けて撮るは「撮った年と月が 12 個」。人の写った写真を外すのは第2段の切り抜きと一緒に入れる
    static func stats(photos: [Photo], books: Int) -> CamperStats {
        var s = CamperStats()
        s.posts = photos.count
        s.books = books
        var prefs = Set<String>()
        var places: [String: Int] = [:]
        var months = Set<String>()
        var seaDays = Set<String>(), mountainDays = Set<String>()
        for p in photos {
            let words = text(of: p)
            let isMountain = has(words, mountainWords), isSea = has(words, seaWords)
            if isMountain { s.mountainShots += 1 }
            if isSea { s.seaShots += 1 }
            if has(words, lakeWords) { s.lakeShots += 1 }
            if has(words, plantWords) { s.plantShots += 1 }
            if has(words, cityWords) { s.cityShots += 1 }
            if let t = shotTime(p.exif?.dateTimeOriginal ?? p.date) {
                let night = t.hour.map { $0 >= 19 || $0 < 4 } ?? false
                if let h = t.hour {
                    if night { s.nightShots += 1 } else if h < 6 { s.earlyShots += 1 }
                    if (5..<10).contains(h) { s.morningShots += 1 }
                }
                switch t.month {
                case 6...8: s.summerShots += 1
                case 12, 1, 2:
                    s.winterShots += 1
                    if night { s.winterNightShots += 1 }
                default: break
                }
                if night, isFullMoon(year: t.year, month: t.month, day: t.dayOfMonth) { s.fullMoonShots += 1 }
                months.insert("\(t.year)-\(t.month)")
                if isSea { seaDays.insert(t.day) }
                if isMountain { mountainDays.insert(t.day) }
            }
            let pref = prefecture(in: p.location)
            if let pref { prefs.insert(pref) }
            if pref == "沖縄" || (p.coords.map { $0.lat < 28.5 && $0.lat > 20 } ?? false) { s.southIslandShots += 1 }
            if let place = placeKey(p) { places[place, default: 0] += 1 }
            if let hex = p.dominantColor {
                switch colorKind(hex) {
                case .forest?: s.forestShots += 1
                case .sky?: s.skyShots += 1
                case nil: break
                }
            }
        }
        s.prefectures = prefs.count
        s.places = places.count
        s.samePlace = places.values.max() ?? 0
        s.months = months.count
        s.seaAndMountainDays = seaDays.intersection(mountainDays).count
        return s
    }

    static let mountainWords = ["山", "岳", "峠", "高原", "mountain", "Mt."]
    static let seaWords = ["海", "浜", "岬", "港", "湾", "ビーチ", "sea", "beach", "ocean"]
    static let lakeWords = ["湖", "lake"]
    static let plantWords = ["花", "植物", "庭", "苔", "桜", "紅葉", "flower", "garden", "plant"]
    static let cityWords = ["街", "通り", "駅", "商店", "city", "street"]

    private static func text(of p: Photo) -> String {
        ([p.location ?? "", p.displayTitle, p.category ?? ""] + (p.tags ?? [])).joined(separator: " ").lowercased()
    }

    private static func has(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0.lowercased()) }
    }

    /// 撮った年・月・日・時（EXIF の「2024:05:12 18:24:00」・「2024-05-12T18:24」・「2024-05-12」）
    static func shotTime(_ raw: String?) -> (year: Int, month: Int, dayOfMonth: Int, hour: Int?, day: String)? {
        guard let raw else { return nil }
        let nums = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 3, nums[0] > 1900, (1...12).contains(nums[1]), (1...31).contains(nums[2]) else { return nil }
        let hour = nums.count >= 4 && (0...23).contains(nums[3]) ? nums[3] : nil
        return (nums[0], nums[1], nums[2], hour, "\(nums[0])-\(nums[1])-\(nums[2])")
    }

    /// 満月か（2000-01-06 18:14 UTC の新月から朔望月 29.530588853 日で月齢を出し、13.8〜15.8 日を満月とみなす）
    static func isFullMoon(year: Int, month: Int, day: Int) -> Bool {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: c) else { return false }
        let ref = Date(timeIntervalSince1970: 947_182_440) // 2000-01-06 18:14 UTC
        let age = (date.timeIntervalSince(ref) / 86_400).truncatingRemainder(dividingBy: 29.530588853)
        let a = age < 0 ? age + 29.530588853 : age
        return a >= 13.8 && a <= 15.8
    }

    static let prefectureNames = [
        "北海道", "青森", "岩手", "宮城", "秋田", "山形", "福島", "茨城", "栃木", "群馬", "埼玉", "千葉", "東京", "神奈川",
        "新潟", "富山", "石川", "福井", "山梨", "長野", "岐阜", "静岡", "愛知", "三重", "滋賀", "京都", "大阪", "兵庫",
        "奈良", "和歌山", "鳥取", "島根", "岡山", "広島", "山口", "徳島", "香川", "愛媛", "高知", "福岡", "佐賀", "長崎",
        "熊本", "大分", "宮崎", "鹿児島", "沖縄",
    ]

    /// 撮影地の文字から都道府県を読む（「京都府京都市」「長野県 松本市」）。県名を含む市（「京都市」だけ）も数える
    static func prefecture(in location: String?) -> String? {
        guard let location, !location.isEmpty else { return nil }
        // 長い名前から（「神奈川」の前に「奈良」に当たらない）
        for name in prefectureNames.sorted(by: { $0.count > $1.count }) where location.contains(name) {
            return name
        }
        return nil
    }

    /// 同じ場所の升（緯度経度を 0.001° ≒ 100 m で丸める。無ければ撮影地の文字）
    static func placeKey(_ p: Photo) -> String? {
        if let c = p.coords {
            return String(format: "%.3f,%.3f", c.lat, c.lng)
        }
        if let loc = p.location?.trimmingCharacters(in: .whitespaces), !loc.isEmpty { return loc }
        return nil
    }

    enum ColorKind { case forest, sky }

    /// 代表色（#RRGGBB）が森の緑か空の青か
    static func colorKind(_ hex: String) -> ColorKind? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let delta = mx - mn
        guard mx > 0, delta / mx >= 0.18, delta > 0.04 else { return nil }
        var hue: Double
        if mx == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) } else if mx == g {
            hue = 60 * ((b - r) / delta + 2)
        } else { hue = 60 * ((r - g) / delta + 4) }
        if hue < 0 { hue += 360 }
        if (75...165).contains(hue), (0.1...0.85).contains(mx) { return .forest }
        if (185...240).contains(hue), mx >= 0.4 { return .sky }
        return nil
    }

    /// ナンバーの数字（日本のナンバーと同じく、4 桁に満たないぶんは「・」）。投稿の数から
    static func plateNumber(_ posts: Int) -> String {
        let n = max(0, posts) % 10_000
        if n >= 1000 { return String(format: "%02d-%02d", n / 100, n % 100) }
        let digits = String(n)
        return String(repeating: "・", count: 4 - digits.count) + digits
    }
}

/// 読み上げの文（車の様子を言葉で）
enum CamperText {

    /// 車の名前（2026-10-18 owner の決定: 「とおまわり号」・英語は Detour。板の「ひかり号」から改めた）。
    /// 板 Main では見出しの大きな字、CamperCollection・CamperDex では「とおまわり号の部品」
    static var carName: String { L("とおまわり号", "Detour") }

    /// 部品の一覧の眉ラベル（板 CamperCollection「とおまわり号の部品」）
    static var partsTitle: String { L("\(carName)の部品", "\(carName)\u{2019}s parts") }

    /// 見出しの上の眉ラベル。名前を入れていない人（「ユーザー」の代わりの呼び方）には名前を出さない。
    /// 日本語は名前と「の車」の間を空けない（2026-10-18: 実機の絵で「ユーザー の車」と出ていた）
    static func eyebrow(owner: String?, stage: CamperStage) -> String {
        let name = owner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, name != Labels.Common.unnamedUser, name != "ユーザー", name != "User" else {
            return L("わたしの車 · \(stage.name)", "My camper · \(stage.name)")
        }
        return L("\(name)の車 · \(stage.name)", "\(name)\u{2019}s camper · \(stage.name)")
    }

    /// 図鑑の数の注記（分母は第1段で集められる数。図鑑そのものは 132・「近日」はまだ数えない）
    static func dexNote() -> String {
        let soon = CamperCatalog.dex.count - CamperCatalog.available.count
        return L("図鑑 \(CamperCatalog.dex.count) · 近日 \(soon)", "Dex \(CamperCatalog.dex.count) · \(soon) soon")
    }

    static func accessibilityLabel(stage: CamperStage, mood: CamperMood, loadout: CamperLoadout, doorOpen: Bool,
                                   preview: CamperPart?) -> String {
        var parts: [String] = []
        parts.append(L("\(carName)、\(stage.name)。\(mood.name)", "\(carName), \(stage.name), \(mood.name)"))
        parts.append(L("塗装は\(loadout.part(.paint).name)", "Paint: \(loadout.part(.paint).name)"))
        parts.append(L("\(loadout.part(.wheel).name)のホイール", "\(loadout.part(.wheel).name) wheels"))
        parts.append(L("\(loadout.part(.headlight).name)", "\(loadout.part(.headlight).name)"))
        parts.append(L("屋根に\(loadout.part(.roofCargo).name)", "On the roof: \(loadout.part(.roofCargo).name)"))
        if let tent = loadout.pickedPart(.roofTent) { parts.append(L("ルーフテントは\(tent.name)", "Roof tent: \(tent.name)")) }
        parts.append(loadout.awningOpen
                     ? L("オーニングを広げている（\(loadout.part(.awning).name)）", "Awning out (\(loadout.part(.awning).name))")
                     : L("オーニングは畳んである", "Awning stowed"))
        let outside = [CamperCategory.chair, .table, .firePit, .outdoorLight, .rug].compactMap { loadout.pickedPart($0)?.name }
        if !outside.isEmpty {
            parts.append(L("外に\(outside.joined(separator: "・"))", "Outside: \(outside.joined(separator: ", "))"))
        }
        parts.append(L("室内に\(loadout.part(.plant).name)と\(loadout.part(.mug).name)", "Inside: \(loadout.part(.plant).name), \(loadout.part(.mug).name)"))
        parts.append(doorOpen ? L("扉が開いている", "Door open") : L("扉は閉じている", "Door closed"))
        if let preview {
            parts.append(L("まだ持っていない「\(preview.name)」を影で見ています", "Previewing \(preview.name), not yet collected"))
        }
        return parts.joined(separator: L("。", ". "))
    }

    /// 部品の札の読み上げ
    static func partLabel(_ p: CamperPart, owned: Bool, stats: CamperStats) -> String {
        if owned { return L("\(p.name)。\(p.rarity.name)", "\(p.name), \(p.rarity.name)") }
        guard p.unlock.isAvailable else {
            return L("近日。\(p.name)。\(p.unlock.condition)", "Coming soon: \(p.name). \(p.unlock.condition)")
        }
        let pr = p.unlock.progress(stats)
        return L("まだ持っていない部品。\(p.name)。\(p.unlock.how)。いま \(pr.have) / \(pr.need)",
                 "Not yet collected: \(p.name). \(p.unlock.how). \(pr.have) of \(pr.need)")
    }
}
