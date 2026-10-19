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

    /// 板の注記の寄りの倍率。車庫の初めの向きは外寸から計算する（`CamperFraming.overview`）
    var zoom: Double {
        switch self {
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
    /// 要サーバー（旅の投稿の数・友達・スポットの種類・行事の暦・天気）。第1段では届かない。条件の文（日本語・英語）
    case server(String, String)
    /// 端末で決まるが、まだアプリに無いもの（キャンプ場など）。第1段では届かない。条件の文（日本語・英語）
    case later(String, String)

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
        case .months(let n):
            return n >= 12 ? L("一年続けて撮る（続いた 12 か月）", "Shoot every month for a year (12 months in a row)")
                : L("\(n) か月続けて撮る", "Months in a row: \(n)")
        case .seaAndMountain: return L("海と山を同じ日に撮る", "Shoot the sea and a mountain on one day")
        case .server(let ja, let en), .later(let ja, let en): return L(ja, en)
        }
    }

    /// 入手のしかた（一行）
    var how: String { how(serverOpen: false) }

    /// 入手のしかた。要サーバーの部品は、サーバーの口が読めて配り始めている間（`serverOpen`）だけ「届きます」と言う
    /// （2026-10-19 第2段）。キャンプ場の焚き火（`.later`）はいつも「近日」
    func how(serverOpen: Bool) -> String {
        switch self {
        case .starter: return L("最初から", "From the start")
        case .server where serverOpen: return L("\(condition)と届きます", "Arrives with: \(condition)")
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
    /// 名前と見た目の一行（図鑑の説明）の日本語・英語。画面の言葉は読むたびに選ぶ（`name`・`look`）——一覧は
    /// 一度だけ作る `static let` なので、作った時の言語で固めると、言語を替えても変わらない（#312 の見直し）
    let nameJa: String
    let nameEn: String
    let lookJa: String
    let lookEn: String
    var name: String { L(nameJa, nameEn) }
    var look: String { L(lookJa, lookEn) }
    let rarity: CamperRarity
    let unlock: CamperUnlock
    /// 色の見本（塗装・オーニング。札の丸に出す）
    var swatch: UInt32?

    /// 図鑑の id（「分類.部品」）
    var id: String { "\(category.rawValue).\(key)" }
}

/// 部品の一覧（板「部品図鑑」CamperDex が正・2026-10-18。33 分類 132 個・端末だけ 99／要サーバー 33。
/// 名前と説明と珍しさと入手の条件は図鑑のまま。英語の名前・説明・要サーバーの条件は 2026-10-18 に付けた・#312 の見直し）
enum CamperCatalog {

    private static func p(_ c: CamperCategory, _ key: String, _ ja: String, _ en: String, _ look: String, _ lookEn: String,
                          _ r: CamperRarity, _ u: CamperUnlock, _ swatch: UInt32? = nil) -> CamperPart {
        CamperPart(category: c, key: key, nameJa: ja, nameEn: en, lookJa: look, lookEn: lookEn, rarity: r, unlock: u, swatch: swatch)
    }

    static let dex: [CamperPart] = [
        // ホイール（wheel）
        p(.wheel, "chrome_dish", "クロームの皿", "Chrome dish", "鏡の皿・ナット 6・真鍮のキャップ", "Mirror dish, six nuts and a brass cap", .common, .starter),
        p(.wheel, "steel_black", "黒い鉄ホイール", "Black steel wheel", "黒い鉄に丸い穴 6", "Black steel with six round holes", .occasional, .posts(30)),
        p(.wheel, "whitewall", "白い帯のタイヤ", "Whitewall tyre", "側面に白い帯", "A white band on the sidewall", .occasional, .prefectures(5)),
        p(.wheel, "brass_spoke", "真鍮のスポーク", "Brass spokes", "細い真鍮のスポーク 16 本", "Sixteen thin brass spokes", .veryRare, .server("旅を公開で 20 回投稿", "Post 20 public trips")),
        // ホイールキャップ（hubcap）
        p(.hubcap, "dome_chrome", "丸いクローム", "Chrome dome", "半球の鏡", "A half-sphere mirror", .common, .starter),
        p(.hubcap, "flat_brass", "平らな真鍮", "Flat brass", "放射の筋の真鍮", "Brass with radiating lines", .occasional, .samePlace(3)),
        p(.hubcap, "star_cap", "星のキャップ", "Star cap", "五つの角の星", "A five-pointed star", .rare, .night(10)),
        p(.hubcap, "baby_moon", "小さな月", "Baby moon", "白い縁に小さな鏡", "A small mirror with a white rim", .rare, .fullMoon(1)),
        // タイヤの溝（tire_tread）
        p(.tireTread, "road_rib", "縦溝", "Road ribs", "縦にまっすぐの溝 4 本", "Four straight grooves", .common, .starter),
        p(.tireTread, "all_terrain", "山道の溝", "All-terrain", "斜めにずれたブロック", "Staggered diagonal blocks", .occasional, .mountain(10)),
        p(.tireTread, "mud_block", "泥のブロック", "Mud blocks", "大きな角ブロック", "Big square blocks", .rare, .server("雨の日に撮る", "Shoot on a rainy day")),
        p(.tireTread, "snow_sipe", "雪の切れ込み", "Snow sipes", "細いジグザグの切れ込み", "Fine zigzag cuts", .occasional, .winter(20)),
        // 前照灯（headlight）
        p(.headlight, "round", "丸い前照灯", "Round headlights", "クロームの縁と反射板の輪", "Chrome rims and reflector rings", .common, .starter),
        p(.headlight, "square", "角形", "Square", "四角い縁と平らなレンズ", "Square rims and flat lenses", .occasional, .night(10)),
        p(.headlight, "twin_round", "二灯", "Twin round", "小さな丸を二つ並べる", "Two small rounds side by side", .occasional, .places(3)),
        p(.headlight, "rally_brass", "真鍮のラリーランプ", "Brass rally lamps", "真鍮の丸灯 2 と横の棒", "Two brass lamps on a bar", .rare, .early(3)),
        // グリル（grille）
        p(.grille, "bars_chrome", "横の桟", "Chrome bars", "クロームの桟 5 本", "Five chrome bars", .common, .starter),
        p(.grille, "vertical_slats", "縦の桟", "Vertical slats", "細い縦の桟 10 本", "Ten thin vertical slats", .occasional, .posts(60)),
        p(.grille, "honeycomb", "蜂の巣", "Honeycomb", "六角の網", "Hexagon mesh", .rare, .server("旅を公開で 5 回投稿", "Post 5 public trips")),
        p(.grille, "mesh_brass", "真鍮の網", "Brass mesh", "斜めに編んだ真鍮", "Diagonally woven brass", .veryRare, .months(12)),
        // バンパー（bumper）
        p(.bumper, "chrome_blade", "クロームの刃", "Chrome blade", "細く長い鏡の棒", "A long thin mirror bar", .common, .starter),
        p(.bumper, "black_steel", "黒い鉄板", "Black steel plate", "ボルト 8 の鉄板", "A steel plate with eight bolts", .occasional, .posts(90)),
        p(.bumper, "wood_beam", "木の梁", "Wooden beam", "木目の梁と黒い金具", "A wood-grain beam with black fittings", .rare, .server("森のスポットで撮る", "Shoot at a forest spot")),
        p(.bumper, "bullbar", "ブルバー", "Bull bar", "前を囲う太い鉄の枠", "A thick steel frame around the front", .rare, .prefectures(10)),
        // ミラー（mirror）
        p(.mirror, "rect_black", "四角い黒", "Black rectangle", "黒い枠の四角い鏡", "A square mirror in a black frame", .common, .starter),
        p(.mirror, "round_chrome", "丸いクローム", "Round chrome", "丸い鏡と細い腕", "A round mirror on a thin arm", .occasional, .samePlace(3)),
        p(.mirror, "tall_tow", "縦長の牽引ミラー", "Tall tow mirror", "上下二本の腕で支える", "Held by two arms, top and bottom", .rare, .books(10)),
        p(.mirror, "brass_oval", "真鍮の楕円", "Brass oval", "楕円の真鍮の枠", "An oval brass frame", .veryRare, .server("友達から贈られる", "Get it as a gift from a friend")),
        // 泥よけ（mudflap）
        p(.mudflap, "rubber_plain", "黒いゴム", "Plain rubber", "無地の黒い板", "A plain black flap", .common, .starter),
        p(.mudflap, "logo_brass", "真鍮の印", "Brass badge", "丸い真鍮の印つき", "With a round brass badge", .occasional, .posts(50)),
        p(.mudflap, "checker", "市松", "Checker", "白黒の市松", "Black and white checks", .rare, .server("旅を公開で 3 回投稿", "Post 3 public trips")),
        p(.mudflap, "long_rally", "長いラリー", "Long rally", "長く垂れて赤い帯", "Long flaps with a red band", .rare, .seaAndMountain(1)),
        // 取っ手（handle）
        p(.handle, "chrome_bar", "クロームの棒", "Chrome bar", "棒と留め具 2", "A bar with two mounts", .common, .starter),
        p(.handle, "recessed", "埋め込み", "Recessed", "扉に沈んだ取っ手と鍵", "Sunk into the door with a lock", .occasional, .posts(40)),
        p(.handle, "brass_lever", "真鍮のレバー", "Brass lever", "丸い座金と横のレバー", "A round plate and a lever", .rare, .samePlace(5)),
        p(.handle, "rope_loop", "縄の輪", "Rope loop", "真鍮の環に麻縄", "Hemp rope through a brass ring", .rare, .sea(10)),
        // 窓の形（window_shape）
        p(.windowShape, "rounded_rect", "角丸の窓", "Rounded window", "角の丸い一枚窓", "One pane with rounded corners", .common, .starter),
        p(.windowShape, "slider_split", "引き違い", "Sliding pair", "二枚の引き違い", "Two sliding panes", .occasional, .posts(70)),
        p(.windowShape, "porthole", "丸窓", "Porthole", "ネジ 10 のクロームの丸窓", "A chrome porthole with ten screws", .rare, .server("港で撮る", "Shoot at a harbour")),
        p(.windowShape, "arched", "アーチの窓", "Arched window", "上が弧の窓と十字の桟", "An arched top with a cross bar", .veryRare, .server("季節の行事の日に撮る", "Shoot on a seasonal festival day")),
        // はしご（ladder）
        p(.ladder, "chrome_rails", "クロームのはしご", "Chrome ladder", "柱 2 と段 7", "Two rails and seven rungs", .common, .starter),
        p(.ladder, "black_alu", "黒いアルミ", "Black aluminium", "滑り止めの段", "Non-slip rungs", .occasional, .posts(80)),
        p(.ladder, "folding", "折りたたみ", "Folding", "途中で折れる真鍮の蝶番", "Brass hinges halfway up", .rare, .prefectures(7)),
        p(.ladder, "wood_rungs", "木の段", "Wooden rungs", "木の柱と木の段", "Wooden rails and rungs", .veryRare, .server("友達のはしごを 3 回見に行く", "Visit a friend's ladder 3 times")),
        // 自転車の台（bike_rack）
        p(.bikeRack, "rear_two", "後ろに 2 台", "Two at the back", "後ろの台に自転車 2", "Two bikes on a rear rack", .occasional, .server("自転車道で撮る", "Shoot on a cycling road")),
        p(.bikeRack, "roof_one", "屋根に 1 台", "One on the roof", "屋根の台に大きめの 1 台", "One larger bike on the roof", .occasional, .posts(100)),
        p(.bikeRack, "folding_bike", "折りたたみ自転車", "Folding bike", "小さな真鍮色の自転車", "A small brass-coloured bike", .rare, .server("旅を公開で 8 回投稿", "Post 8 public trips")),
        p(.bikeRack, "cargo_basket", "荷かご", "Cargo basket", "鉄のかごに木箱と布の袋", "A steel basket with a crate and a bag", .common, .starter),
        // スペアタイヤのカバー（spare_cover）
        p(.spareCover, "canvas_brass_ring", "帆布と真鍮の輪", "Canvas and brass ring", "帆布に真鍮の輪と写真", "Canvas with a brass ring and a photo", .common, .starter),
        p(.spareCover, "leather", "革", "Leather", "革に縫い目と真鍮の留め", "Stitched leather with a brass clasp", .occasional, .posts(60)),
        p(.spareCover, "hardshell", "硬い殻", "Hard shell", "鏡の殻と黒い中心", "A mirror shell with a black centre", .rare, .server("旅を公開で 6 回投稿", "Post 6 public trips")),
        p(.spareCover, "map_print", "地図柄", "Map print", "自分の旅の道が描かれる", "Printed with the roads of your trips", .veryRare, .prefectures(15)),
        // 屋根の積み荷（roof_cargo）
        p(.roofCargo, "crate_mat", "木箱とマット", "Crate and mat", "木目の箱と縫い目のマット", "A wooden crate and a stitched mat", .common, .starter),
        p(.roofCargo, "roof_box", "ルーフボックス", "Roof box", "車体色の流線形", "A streamlined box in the body colour", .occasional, .winter(20)),
        p(.roofCargo, "canoe", "木のカヌー", "Wooden canoe", "赤茶の舟を伏せて留める", "A russet canoe strapped upside down", .rare, .server("水辺のスポットで撮る", "Shoot at a waterside spot")),
        p(.roofCargo, "surfboard", "サーフボード", "Surfboard", "白い板に青い線", "A white board with a blue stripe", .rare, .sea(15)),
        // ルーフテント（roof_tent）
        p(.roofTent, "clamshell", "貝殻", "Clamshell", "斜めに開く硬い殻", "A hard shell that opens at an angle", .occasional, .posts(120)),
        p(.roofTent, "popup_canvas", "帆布の箱", "Pop-up canvas", "窓 3 つの帆布の箱", "A canvas box with three windows", .occasional, .server("旅を公開で 4 回投稿", "Post 4 public trips")),
        p(.roofTent, "triangle_hardtop", "三角の硬い屋根", "Triangle hardtop", "塗装の三角と窓", "A painted triangle with a window", .rare, .mountain(1)),
        p(.roofTent, "wing", "翼のタープ", "Wing tarp", "片側に張る翼の布", "A wing of cloth on one side", .veryRare, .server("友達と同じ日に旅をする", "Travel on the same day as a friend")),
        // ソーラーパネル（solar）
        p(.solar, "flat_one", "一枚", "Single panel", "8×2 の電池板", "An 8 by 2 cell panel", .common, .starter),
        p(.solar, "twin", "二枚", "Twin panels", "二枚を並べる", "Two panels side by side", .occasional, .sky(30)),
        p(.solar, "folding_suitcase", "折りたたみ", "Folding case", "鞄のように開く板", "Panels that open like a suitcase", .rare, .server("旅を公開で 5 回投稿", "Post 5 public trips")),
        p(.solar, "flexible_curve", "曲がる板", "Flexible panel", "屋根の丸みに沿う", "Follows the curve of the roof", .rare, .early(5)),
        // アンテナ（antenna）
        p(.antenna, "whip", "細い竿", "Whip", "しなる細い竿", "A thin, springy rod", .common, .starter),
        p(.antenna, "mushroom_gps", "きのこ型", "Mushroom", "白い半球", "A white half-sphere", .occasional, .places(5)),
        p(.antenna, "dish", "パラボラ", "Dish", "斜めの皿と受信部", "A tilted dish and receiver", .rare, .night(5)),
        p(.antenna, "ham_long", "長い無線の竿", "Long radio mast", "横棒 5 の長い竿", "A tall mast with five cross bars", .veryRare, .server("友達 10 人と旅を交わす", "Swap trips with 10 friends")),
        // 旗とペナント（flag）
        p(.flag, "pennant_triangle", "三角のペナント", "Triangle pennant", "赤茶の三角に白い線", "A russet triangle with a white line", .common, .starter),
        p(.flag, "swallowtail", "燕尾の旗", "Swallowtail flag", "先が割れた藍の旗", "An indigo flag with a split tip", .occasional, .server("旅を公開で 2 回投稿", "Post 2 public trips")),
        p(.flag, "prayer_line", "連なる旗", "Flag line", "色の旗を紐に 6 枚", "Six coloured flags on a string", .rare, .server("旅先で 5 つの祭りの写真", "Photos of 5 festivals on your trips")),
        p(.flag, "windsock", "吹き流し", "Windsock", "橙と白の筒", "An orange and white tube", .occasional, .server("風の強い日に撮る", "Shoot on a windy day")),
        // 椅子（chair）
        p(.chair, "folding_chair", "布の折りたたみ", "Folding chair", "縫い目のある布と黒い脚", "Stitched cloth on black legs", .common, .starter),
        p(.chair, "director_chair", "ディレクターズ", "Director chair", "木の脚と藍の布", "Wooden legs and indigo cloth", .occasional, .posts(50)),
        p(.chair, "wooden_stool", "木の丸椅子", "Wooden stool", "丸い座面と 4 本脚", "A round seat on four legs", .occasional, .forest(10)),
        p(.chair, "hammock", "ハンモック", "Hammock", "二本の柱に橙の布", "Orange cloth between two posts", .veryRare, .summer(30)),
        // 机（table）
        p(.table, "folding_alu", "アルミの折りたたみ", "Folding aluminium", "細い脚の銀の机", "A silver table on thin legs", .common, .starter),
        p(.table, "rolltop", "巻ける天板", "Roll-top", "木の板を巻いて運ぶ", "Wooden slats that roll up", .occasional, .posts(70)),
        p(.table, "wooden_crate_table", "木箱の机", "Crate table", "木箱を伏せて天板を載せる", "A crate upside down with a top", .rare, .server("旅を公開で 6 回投稿", "Post 6 public trips")),
        p(.table, "camp_cube", "箱の机", "Camp cube", "保冷箱を兼ねる箱", "A box that doubles as a cooler", .occasional, .lake(5)),
        // 焚き火台（fire_pit）
        p(.firePit, "steel_bowl", "鉄の鉢", "Steel bowl", "黒い鉢と 2 本脚", "A black bowl on two legs", .common, .starter),
        p(.firePit, "stone_ring", "石の輪", "Stone ring", "石 9 つと三本の薪", "Nine stones and three logs", .occasional, .later("キャンプ場で焚き火をする", "Light a fire at a campsite")),
        p(.firePit, "brazier", "火鉢", "Brazier", "穴の空いた鏡の鉢", "A mirror bowl with holes", .rare, .winterNight(5)),
        p(.firePit, "tripod_kettle", "三脚とやかん", "Tripod and kettle", "三脚から吊るす鉄の鍋", "An iron pot hung from a tripod", .veryRare, .server("友達の焚き火に薪をくべる 10 回", "Add wood to a friend's fire 10 times")),
        // 外の灯り（outdoor_light）
        p(.outdoorLight, "brass_lantern", "真鍮のランタン", "Brass lantern", "真鍮の枠と硝子", "A brass frame and glass", .common, .starter),
        p(.outdoorLight, "string_lights", "電球の紐", "String lights", "小さな電球 8 つ", "Eight small bulbs", .occasional, .night(15)),
        p(.outdoorLight, "paper_lantern", "提灯", "Paper lantern", "朱の紙の提灯", "A vermilion paper lantern", .rare, .server("夏祭りの写真", "A photo of a summer festival")),
        p(.outdoorLight, "oil_lamp", "オイルランプ", "Oil lamp", "真鍮の油壺と硝子の火屋", "A brass oil pot and glass chimney", .rare, .early(3)),
        // 外のラグ（rug）
        p(.rug, "woven_mat", "編んだ敷物", "Woven mat", "麦わら色の編み目", "A straw-coloured weave", .common, .starter),
        p(.rug, "striped", "縞のラグ", "Striped rug", "藍と赤の縞", "Indigo and red stripes", .occasional, .posts(40)),
        p(.rug, "round_braided", "丸い三つ編み", "Round braided", "色の輪を重ねる", "Rings of colour", .rare, .places(8)),
        p(.rug, "kilim", "キリム", "Kilim", "赤地に金のひし形", "Gold diamonds on red", .veryRare, .server("友達から贈られる", "Get it as a gift from a friend")),
        // カーテン（curtain）
        p(.curtain, "pleated_linen", "麻のひだ", "Pleated linen", "左右にひだ 5 つずつ", "Five pleats on each side", .common, .starter),
        p(.curtain, "cafe_short", "短いカフェ", "Short café", "下半分だけの白", "White on the lower half only", .occasional, .morning(10)),
        p(.curtain, "roman_blind", "たくし上げ", "Roman blind", "段に上がる緑の布", "Green cloth folding up in steps", .occasional, .posts(60)),
        p(.curtain, "beaded", "玉すだれ", "Bead curtain", "真鍮と朱と藍の玉", "Brass, vermilion and indigo beads", .veryRare, .server("季節の行事の日に撮る", "Shoot on a seasonal festival day")),
        // クッション（cushion）
        p(.cushion, "square_plain", "四角", "Square", "生成りの四角", "A plain square in natural cloth", .common, .starter),
        p(.cushion, "bolster_round", "円筒", "Bolster", "緑の筒に真鍮の帯", "A green roll with brass bands", .occasional, .posts(30)),
        p(.cushion, "knitted", "編み目", "Knitted", "縄編みの橙", "Orange cable knit", .rare, .winter(15)),
        p(.cushion, "tasseled", "房飾り", "Tasselled", "藍に金の房 4", "Indigo with four gold tassels", .rare, .server("旅を公開で 4 回投稿", "Post 4 public trips")),
        // 吊りランプ（hanging_lamp）
        p(.hangingLamp, "brass_dome", "真鍮の笠", "Brass dome", "半球の真鍮", "A half-sphere of brass", .common, .starter),
        p(.hangingLamp, "enamel_cone", "ホーローの円錐", "Enamel cone", "緑のホーローに白い縁", "Green enamel with a white rim", .occasional, .posts(50)),
        p(.hangingLamp, "rattan", "籐", "Rattan", "籐を編んだ笠", "A woven rattan shade", .rare, .southIsland(1)),
        p(.hangingLamp, "glass_globe", "硝子の球", "Glass globe", "乳白の硝子の球", "A milky glass globe", .veryRare, .night(30)),
        // 観葉植物（plant）
        p(.plant, "cactus", "サボテン", "Cactus", "腕 2 本に花", "Two arms and a flower", .common, .starter),
        p(.plant, "monstera", "モンステラ", "Monstera", "大きな葉 6 枚", "Six big leaves", .occasional, .plants(10)),
        p(.plant, "hanging_ivy", "吊るしたつる", "Hanging ivy", "鉢から垂れるつる", "Vines trailing from a pot", .rare, .server("雨の写真 5 枚", "5 photos in the rain")),
        p(.plant, "bonsai", "盆栽", "Bonsai", "黒い鉢と曲がった幹", "A black pot and a twisted trunk", .veryRare, .months(12)),
        // マグ（mug）
        p(.mug, "enamel_white", "ホーローの白", "White enamel", "藍の縁の白いマグ", "A white mug with an indigo rim", .common, .starter),
        p(.mug, "tin_cup", "ブリキのカップ", "Tin cup", "銀の筒と細い取っ手", "A silver cup with a thin handle", .occasional, .posts(20)),
        p(.mug, "ceramic_glazed", "釉薬の陶器", "Glazed ceramic", "青い釉薬の丸み", "A round cup in blue glaze", .rare, .server("焼き物の町で撮る", "Shoot in a pottery town")),
        p(.mug, "double_wall", "二重硝子", "Double-wall glass", "硝子の中に浮くコーヒー", "Coffee floating in glass", .rare, .morning(20)),
        // 本棚（bookshelf）
        p(.bookshelf, "small_shelf", "小さな棚", "Small shelf", "二段に本 17 冊", "Seventeen books on two shelves", .common, .starter),
        p(.bookshelf, "wall_rack", "壁の棚板", "Wall rack", "壁に二枚の板と小物", "Two boards and small things", .occasional, .posts(80)),
        p(.bookshelf, "crate_stack", "木箱の棚", "Crate shelf", "木箱 3 つを積む", "Three crates stacked", .rare, .server("旅を公開で 7 回投稿", "Post 7 public trips")),
        p(.bookshelf, "map_drawer", "地図の引き出し", "Map drawer", "真鍮の取っ手 4 と地図", "Four brass pulls and maps", .veryRare, .prefectures(20)),
        // 壁の木（wall_wood）
        p(.wallWood, "pine_boards", "松の板", "Pine boards", "縦張りの明るい板と節", "Light vertical boards with knots", .common, .starter),
        p(.wallWood, "plywood_birch", "樺の合板", "Birch plywood", "細かい木目の白い板", "Pale board with a fine grain", .occasional, .posts(50)),
        p(.wallWood, "dark_walnut", "胡桃の横張り", "Walnut boards", "濃い横張り", "Dark horizontal boards", .rare, .forest(20)),
        p(.wallWood, "herringbone", "ヘリンボーン", "Herringbone", "矢筈に組む", "Laid in a herringbone", .veryRare, .server("旅を公開で 12 回投稿", "Post 12 public trips")),
        // 床（floor）
        p(.floor, "oak_planks", "ナラの板", "Oak planks", "長い板の床", "Long plank floor", .common, .starter),
        p(.floor, "cork", "コルク", "Cork", "粒の見える柔らかい床", "A soft floor with a fine grain", .occasional, .posts(40)),
        p(.floor, "chevron", "シェブロン", "Chevron", "くの字に組む", "Laid in a chevron", .rare, .places(6)),
        p(.floor, "checker_tiles", "市松のタイル", "Checker tiles", "白黒のタイル", "Black and white tiles", .rare, .city(20)),
        // オーニング（awning）
        p(.awning, "indigo_stripe", "藍の縞", "Indigo stripes", "藍と生成りの縞", "Indigo and natural stripes", .common, .starter, 0x2F4F74),
        p(.awning, "forest_stripe", "森の緑の縞", "Forest stripes", "緑と生成りの縞", "Green and natural stripes", .occasional, .forest(15), 0x4A5A46),
        p(.awning, "scalloped_edge", "波の縁", "Scalloped edge", "黄の布に波形の縁", "Yellow cloth with a wavy edge", .rare, .sea(20), 0xD9B24A),
        p(.awning, "rust_stripe", "赤茶の縞", "Rust stripes", "赤茶と生成りの縞", "Russet and natural stripes", .veryRare, .server("友達から贈られる", "Get it as a gift from a friend"), 0x7A2E22),
        // ステッカーの縁（sticker_edge）
        p(.stickerEdge, "white_cut", "白い切り抜き", "White cut", "白い紙の縁", "A white paper edge", .common, .starter),
        p(.stickerEdge, "gold_foil", "金の箔押し", "Gold foil", "真鍮色の箔の縁", "A brass-coloured foil edge", .rare, .samePlace(3)),
        p(.stickerEdge, "holo", "ホログラム", "Hologram", "見る角度で虹色", "Rainbow at every angle", .veryRare, .server("季節の行事の日に撮る", "Shoot on a seasonal festival day")),
        p(.stickerEdge, "signed", "友達の署名入り", "Signed by a friend", "友達の名前の刻印", "Your friend's name stamped on it", .veryRare, .server("友達が贈る", "A friend gives it to you")),
    ]

    /// 塗装（図鑑の数に入れない・paint.*。板 CamperDecorate の 4 色）
    static let paints: [CamperPart] = [
        p(.paint, "cloud", "雲の影の灰", "Cloud grey", "撮った写真から拾った色", "A colour picked from your photos", .common, .starter, 0x5B6168),
        p(.paint, "mist", "霧の白", "Mist white", "撮った写真から拾った色", "A colour picked from your photos", .common, .starter, 0xD9D4C7),
        p(.paint, "sky", "朝の空の青", "Morning sky blue", "晴れの写真から拾った色", "A colour picked from clear-sky photos", .occasional, .sky(1), 0x7F97AB),
        p(.paint, "forest", "森の緑", "Forest green", "森の写真から拾った色", "A colour picked from forest photos", .occasional, .forest(15), 0x4A5A46),
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

    let defaults: UserDefaults
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

    /// 画面を開いた時の「届いた」。**写真を一度でも読めた時だけ**判定して印を付ける（読む前は数が 0 で、
    /// 前の印を消すと次に読めた時に同じ部品がもう一度「届いた」になる）。印は前の印との和集合で残す
    ///
    /// 2026-10-19 判断（第2段・板の付箋「同じ写真で一度に届くのは 3 個まで」）: 一度に見せるのは `limit` 個まで。
    /// 見せなかった分は印を付けず、次に開いたときに見せる。**はじめて開いた（印がまだ無い）ときは今までどおり全部に
    /// 印を付ける**（端末で前から持っていた部品を何度にも分けて「届いた」にしない）。先に見せる部品（`first`・
    /// サーバーのこの回に届いた分・写真の保存で届いた分）は珍しさより前に並べる
    func openArrivals(owned: Set<String>, photosLoaded: Bool, first: [String] = [], limit: Int = .max) -> [CamperPart] {
        guard photosLoaded else { return [] }
        let previous = seen
        let fresh = Self.arrivals(owned: owned, seen: previous, first: first)
        let shown = Array(fresh.prefix(max(0, limit)))
        if previous == nil {
            markSeen(owned)
        } else {
            markSeen((previous ?? []).union(owned.subtracting(fresh.map(\.id))).union(shown.map(\.id)))
        }
        return shown
    }

    /// 新しく届いた部品（最初から持っているものは数えない）。`first` に在るものを先に（その並びで）、残りは珍しい順・一覧の順
    static func arrivals(owned: Set<String>, seen: Set<String>?, first: [String] = []) -> [CamperPart] {
        let fresh = owned.subtracting(seen ?? [])
        let rest = CamperCatalog.all.filter { fresh.contains($0.id) && $0.unlock != .starter && !first.contains($0.id) }
            .sorted { $0.rarity > $1.rarity }
        let lead = first.compactMap { id in fresh.contains(id) ? CamperCatalog.part(id) : nil }.filter { $0.unlock != .starter }
        return lead + rest
    }

    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userId))
        defaults.removeObject(forKey: seenKey(userId))
        defaults.removeObject(forKey: inboxKey(userId))
    }
}

/// 画面で付け外しする飾り（2026-10-18 #312 の見直し）。**保存する値は持っていない部品も外さない**——
/// 数え直しの途中や写真を読む前（数が 0）に外して保存すると、選んだ部品が消える。外すのは見せる時だけ（`worn`）
struct CamperGarageEditor: Equatable {
    private(set) var loadout = CamperLoadout.standard

    /// 開いた時: 保存した値をそのまま持つ
    mutating func open(_ store: CamperStore) { loadout = store.load() }

    /// 画面に出す飾り（持っていない部品を外す）
    func worn(owned: Set<String>) -> CamperLoadout { loadout.sanitized(owned: owned) }

    /// 持っている部品だけ付けて保存する（持っていなければ何もしない）
    @discardableResult
    mutating func equip(_ part: CamperPart, owned: Set<String>, store: CamperStore) -> Bool {
        guard owned.contains(part.id) else { return false }
        loadout.pick(part)
        store.save(loadout)
        return true
    }

    /// 付けない（付けないこともできる分類）
    mutating func remove(_ c: CamperCategory, store: CamperStore) {
        loadout.remove(c)
        store.save(loadout)
    }

    /// オーニングを広げる・畳む（`save` が false なら見せるだけ。部品を見る時に広げる）
    mutating func setAwning(_ open: Bool, store: CamperStore?) {
        loadout.awningOpen = open
        store?.save(loadout)
    }
}

// MARK: - 投稿から数える

enum CamperCounting {

    /// 自分の写真の一覧から数える（**下書きは数えない**・旅の一冊も公開した写真から）。マイページの写真の一覧
    /// （`MyPageViewModel.photos`）には下書きが入るので、ここで `published != false` に絞る（2026-10-18 #312 の見直し）
    /// 数え直す目印。数えに使う欄（id・公開か・撮った時・撮影地・題・分類・タグ・位置・代表色）を全部並べた値の hash。
    /// 先頭と最後の id だけでは、公開と下書きの切り替え・撮影地の直し・間の 1 枚の入れ替えを拾わなかった（#312 の見直し）
    static func countKey(_ photos: [Photo], loaded: Bool) -> Int {
        var h = Hasher()
        h.combine(loaded)
        h.combine(photos.count)
        for p in photos {
            h.combine(p.id)
            h.combine(p.published)
            h.combine(p.exif?.dateTimeOriginal)
            h.combine(p.date)
            h.combine(p.location)
            h.combine(p.displayTitle)
            h.combine(p.category)
            h.combine(p.tags)
            h.combine(p.coords?.lat)
            h.combine(p.coords?.lng)
            h.combine(p.dominantColor)
        }
        return h.finalize()
    }

    static func count(_ photos: [Photo]) -> CamperStats {
        let posted = photos.filter { $0.published != false }
        return stats(photos: posted, books: TripBook.shelfTrips(from: posted).count)
    }

    /// 自分の投稿から数える（段と部品の入手）。`books` は旅の一冊の数（呼ぶ側が `TripBook.shelfTrips` で数える）。
    /// 2026-10-18 判断: 山・海辺・湖・植物・街は撮影地と題とタグの言葉で読む（写真の位置の標高は投稿に無い）。
    /// 地名（都道府県・市区町村・「横浜」など）は先に外す（`natureText`）。
    /// 一年続けて撮るは「続いた 12 か月」（`longestMonthRun`）。人の写った写真を外すのは第2段の切り抜きと一緒に入れる
    static func stats(photos all: [Photo], books: Int) -> CamperStats {
        let photos = all.filter { $0.published != false }
        var s = CamperStats()
        s.posts = photos.count
        s.books = books
        var prefs = Set<String>()
        var places: [String: Int] = [:]
        var months = Set<Int>()
        // 日ごとの海の写真と山の写真（「海と山を同じ日」は別々の写真に限る）
        var seaByDay: [String: Set<String>] = [:], mountainByDay: [String: Set<String>] = [:]
        for p in photos {
            let words = natureText(of: p)
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
                months.insert(t.year * 12 + (t.month - 1))
                if isSea { seaByDay[t.day, default: []].insert(p.id) }
                if isMountain { mountainByDay[t.day, default: []].insert(p.id) }
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
        s.months = longestMonthRun(months)
        s.seaAndMountainDays = seaByDay.keys.filter { day in
            guard let sea = seaByDay[day], let mountain = mountainByDay[day] else { return false }
            // 海の写真と山の写真が別々に在る（1 枚が海と山の両方に当たるだけでは数えない）
            return sea.contains { a in mountain.contains { $0 != a } }
        }.count
        return s
    }

    /// 続いた月の最長（月は 年×12＋月−1 の通し番号）。「一年続けて撮る」は 12
    static func longestMonthRun(_ months: Set<Int>) -> Int {
        var best = 0
        for m in months where !months.contains(m - 1) {
            var n = 1
            while months.contains(m + n) { n += 1 }
            best = max(best, n)
        }
        return best
    }

    static let mountainWords = ["山", "岳", "峠", "高原", "mountain", "Mt."]
    static let seaWords = ["海", "浜", "岬", "港", "湾", "ビーチ", "sea", "beach", "ocean"]
    static let lakeWords = ["湖", "lake"]
    static let plantWords = ["花", "植物", "庭", "苔", "桜", "紅葉", "flower", "garden", "plant"]
    static let cityWords = ["街", "通り", "駅", "商店", "city", "street"]

    /// 山・海などの言葉に当たる地名（市の名前・区の名前）。部分一致で「北海道→海」「横浜→浜」などに当たらないよう、先に外す
    static let placeNamesWithNatureWords = [
        "北海道", "横浜", "浜松", "浜田", "浜北", "郡山", "松山", "岡山", "富山", "和歌山", "山形", "山口", "山梨", "港区",
        "海老名", "海南", "小浜", "高山", "館山", "小山", "福山", "山陽", "山陰", "湖西", "湖南",
    ]

    /// 撮影地・題・タグの言葉から、地名を外した文（都道府県名・「〜市」「〜区」「〜町」「〜村」「〜郡」・地名の表）
    static func natureText(of p: Photo) -> String {
        natureText(([p.location ?? "", p.displayTitle, p.category ?? ""] + (p.tags ?? [])).joined(separator: " "))
    }

    static func natureText(_ raw: String) -> String {
        var t = raw
        for name in prefectureNames.sorted(by: { $0.count > $1.count }) {
            for suffix in ["都", "道", "府", "県", ""] { t = t.replacingOccurrences(of: name + suffix, with: " ") }
        }
        for name in placeNamesWithNatureWords { t = t.replacingOccurrences(of: name, with: " ") }
        // 漢字の続きで終わる市区町村・郡（「鎌倉市」「港区」「山中湖村」）
        t = t.replacingOccurrences(of: "[\\p{Han}々ヶケ]{1,6}[市区町村郡]", with: " ", options: .regularExpression)
        return t.lowercased()
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
    static func dexNote(serverOpen: Bool = false) -> String {
        let soon = CamperCatalog.dex.count - CamperCatalog.collectable(serverOpen: serverOpen).count
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
    static func partLabel(_ p: CamperPart, owned: Bool, stats: CamperStats, server: CamperServerParts = .closed) -> String {
        if owned { return L("\(p.name)。\(p.rarity.name)", "\(p.name), \(p.rarity.name)") }
        if server.open, p.unlock.isServer {
            // 要サーバーの部品（2026-10-19 第2段）。記録で決まる部品だけ数を言う（写真で決まる部品は「まだ」だけ）
            guard let pr = CamperServerRule.progress(p.id, server.progress) else {
                return L("まだ持っていない部品。\(p.name)。\(p.unlock.how(serverOpen: true))",
                         "Not yet collected: \(p.name). \(p.unlock.how(serverOpen: true))")
            }
            return L("まだ持っていない部品。\(p.name)。\(p.unlock.how(serverOpen: true))。いま \(pr.have) / \(pr.need)",
                     "Not yet collected: \(p.name). \(p.unlock.how(serverOpen: true)). \(pr.have) of \(pr.need)")
        }
        guard p.unlock.isAvailable else {
            return L("近日。\(p.name)。\(p.unlock.condition)", "Coming soon: \(p.name). \(p.unlock.condition)")
        }
        let pr = p.unlock.progress(stats)
        return L("まだ持っていない部品。\(p.name)。\(p.unlock.how)。いま \(pr.have) / \(pr.need)",
                 "Not yet collected: \(p.name). \(p.unlock.how). \(pr.have) of \(pr.need)")
    }
}
