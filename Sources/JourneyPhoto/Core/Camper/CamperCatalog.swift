import Foundation

// 写真で作るキャンピングカーの「何を持っているか」（2026-10-18・札 #307）。
//
// 第1段は**サーバーを変えない**。段（バン→キャンピングカー→トレーラーつき）も、集める部品の「持っている／まだ」も、
// 既に読める自分の投稿（`Photo`）から**この端末で**数える。板「集める部品の一覧」で「要サーバー」とされた部品
// （真鍮のホイール・木のカヌー・赤茶の縞・ホログラム・友達の署名入り）は第1段に入れない（docs/CAMPER.md の第2段）。
//
// 2026-10-18 owner「部品もっと欲しい」: 31 分類・129 部品。どの部品も**形が違う**（色違いで数を稼がない。
// 塗装だけは色そのものが部品）。珍しさは「いつもの」を多く、「とても珍しい」を少なく。

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
        case .van: return 1.02
        case .camper: return 0.95
        case .trailer: return 0.74
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

/// 分類のまとまり（集める画面の上の札）
enum CamperGroupKind: String, CaseIterable, Sendable {
    case exterior, roof, decor, outside, inside

    var name: String {
        switch self {
        case .exterior: return L("車の外", "Exterior")
        case .roof: return L("屋根", "Roof")
        case .decor: return L("飾り", "Decor")
        case .outside: return L("外の置き物", "Campsite")
        case .inside: return L("室内", "Interior")
        }
    }
}

/// 部品の分類（板 CamperCatalog の 6 分類に、owner の例の分類を足した 31 分類）
enum CamperCategory: String, CaseIterable, Codable, Sendable {
    // 車の外
    case wheel, tread, light, grille, bumper, mirror, mudflap, ladder, handle, window, awning, rear
    // 屋根
    case roof, solar, antenna, flag
    // 飾り
    case paint, stickerEdge, sticker, plate
    // 外の置き物
    case chair, table, outLight, rug
    // 室内
    case curtain, cushion, lamp, shelf, wall, floor, trinket

    var group: CamperGroupKind {
        switch self {
        case .wheel, .tread, .light, .grille, .bumper, .mirror, .mudflap, .ladder, .handle, .window, .awning, .rear: return .exterior
        case .roof, .solar, .antenna, .flag: return .roof
        case .paint, .stickerEdge, .sticker, .plate: return .decor
        case .chair, .table, .outLight, .rug: return .outside
        case .curtain, .cushion, .lamp, .shelf, .wall, .floor, .trinket: return .inside
        }
    }

    /// 付けないこともできる分類（はじめは付けない）
    var optional: Bool {
        switch self {
        case .rear, .antenna, .flag, .chair, .table, .outLight, .rug: return true
        default: return false
        }
    }

    var name: String {
        switch self {
        case .wheel: return L("ホイール", "Wheels")
        case .tread: return L("タイヤの溝", "Tyre tread")
        case .light: return L("前照灯", "Headlights")
        case .grille: return L("グリル", "Grille")
        case .bumper: return L("バンパー", "Bumper")
        case .mirror: return L("ミラー", "Mirrors")
        case .mudflap: return L("泥よけ", "Mud flaps")
        case .ladder: return L("はしご", "Ladder")
        case .handle: return L("取っ手", "Handles")
        case .window: return L("窓の形", "Windows")
        case .awning: return L("オーニング", "Awning")
        case .rear: return L("後ろの荷台", "Rear carrier")
        case .roof: return L("屋根の積み荷", "Roof cargo")
        case .solar: return L("ソーラーパネル", "Solar")
        case .antenna: return L("アンテナ", "Antenna")
        case .flag: return L("旗", "Flag")
        case .paint: return L("塗装", "Paint")
        case .stickerEdge: return L("ステッカーの縁", "Sticker edge")
        case .sticker: return L("ステッカー", "Stickers")
        case .plate: return L("ナンバー", "Plate")
        case .chair: return L("椅子", "Chairs")
        case .table: return L("机と焚き火", "Table and fire")
        case .outLight: return L("外の灯り", "Outdoor lights")
        case .rug: return L("外のラグ", "Outdoor rug")
        case .curtain: return L("カーテン", "Curtains")
        case .cushion: return L("クッション", "Cushions")
        case .lamp: return L("吊りランプ", "Hanging lamp")
        case .shelf: return L("棚", "Shelf")
        case .wall: return L("壁の木", "Wall wood")
        case .floor: return L("床", "Floor")
        case .trinket: return L("内装の小物", "Keepsakes")
        }
    }

    /// 札の印（SF Symbols）
    var symbol: String {
        switch self {
        case .wheel: return "circle.circle"
        case .tread: return "circle.dashed"
        case .light: return "headlight.high.beam"
        case .grille: return "square.grid.3x1.below.line.grid.1x2"
        case .bumper: return "rectangle.portrait.bottomhalf.filled"
        case .mirror: return "rectangle.on.rectangle"
        case .mudflap: return "rectangle.portrait"
        case .ladder: return "stairs"
        case .handle: return "hand.point.up"
        case .window: return "window.casement"
        case .awning: return "beach.umbrella"
        case .rear: return "bicycle"
        case .roof: return "shippingbox"
        case .solar: return "sun.max"
        case .antenna: return "antenna.radiowaves.left.and.right"
        case .flag: return "flag"
        case .paint: return "drop"
        case .stickerEdge: return "seal"
        case .sticker: return "star.circle"
        case .plate: return "textformat.123"
        case .chair: return "chair"
        case .table: return "flame"
        case .outLight: return "lantern"
        case .rug: return "square.grid.3x3"
        case .curtain: return "curtains.closed"
        case .cushion: return "square.stack"
        case .lamp: return "lamp.ceiling"
        case .shelf: return "books.vertical"
        case .wall: return "rectangle.split.3x1"
        case .floor: return "square.grid.2x2"
        case .trinket: return "leaf"
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

/// 自分の投稿から、この端末で数えた値（サーバーには何も聞かない）
struct CamperStats: Equatable, Sendable {
    var posts = 0
    var books = 0
    /// 夜（19 時〜翌 4 時）に撮った写真
    var nightShots = 0
    /// 朝（4 時〜6 時前）に撮った写真
    var earlyShots = 0
    /// 季節ごとの写真（春 3〜5 月・夏 6〜8 月・秋 9〜11 月・冬 12〜2 月）
    var springShots = 0
    var summerShots = 0
    var autumnShots = 0
    var winterShots = 0
    /// 撮影地の都道府県の数（撮影地の文字から読む。iOS の地名変換は使わない）
    var prefectures = 0
    /// 同じ場所（約 100 m の升）で撮った回数のいちばん多いもの
    var samePlace = 0
    /// 森の色（代表色が緑）の写真
    var forestShots = 0
    /// 空の色（代表色が青）の写真
    var skyShots = 0
    /// 撮った日の数（同じ日は 1 つ）
    var days = 0
}

/// 部品の手に入れ方（**端末だけで決まるもの**だけ）
enum CamperUnlock: Equatable, Sendable {
    case starter
    case posts(Int)
    case books(Int)
    case night(Int)
    case early(Int)
    case spring(Int)
    case summer(Int)
    case autumn(Int)
    case winter(Int)
    case prefectures(Int)
    case samePlace(Int)
    case forest(Int)
    case sky(Int)
    case days(Int)

    /// (いまの数, 要る数)
    func progress(_ s: CamperStats) -> (have: Int, need: Int) {
        switch self {
        case .starter: return (1, 1)
        case .posts(let n): return (s.posts, n)
        case .books(let n): return (s.books, n)
        case .night(let n): return (s.nightShots, n)
        case .early(let n): return (s.earlyShots, n)
        case .spring(let n): return (s.springShots, n)
        case .summer(let n): return (s.summerShots, n)
        case .autumn(let n): return (s.autumnShots, n)
        case .winter(let n): return (s.winterShots, n)
        case .prefectures(let n): return (s.prefectures, n)
        case .samePlace(let n): return (s.samePlace, n)
        case .forest(let n): return (s.forestShots, n)
        case .sky(let n): return (s.skyShots, n)
        case .days(let n): return (s.days, n)
        }
    }

    func isMet(_ s: CamperStats) -> Bool {
        let p = progress(s)
        return p.have >= p.need
    }

    /// 0〜1 の進み具合（真鍮の細い棒）
    func fraction(_ s: CamperStats) -> Double {
        let p = progress(s)
        guard p.need > 0 else { return 1 }
        return min(1, max(0, Double(p.have) / Double(p.need)))
    }

    /// 数えるもの（「写真が」「夜に撮った写真が」…）
    private var what: (ja: String, en: String) {
        switch self {
        case .starter: return ("", "")
        case .posts: return ("写真が", "photos")
        case .books: return ("旅が", "trips")
        case .night: return ("夜に撮った写真が", "photos taken at night")
        case .early: return ("朝 6 時前に撮った写真が", "photos taken before 6am")
        case .spring: return ("春に撮った写真が", "spring photos")
        case .summer: return ("夏に撮った写真が", "summer photos")
        case .autumn: return ("秋に撮った写真が", "autumn photos")
        case .winter: return ("冬に撮った写真が", "winter photos")
        case .prefectures: return ("撮影地の都道府県が", "prefectures")
        case .samePlace: return ("同じ場所で撮った回数が", "shots of the same place")
        case .forest: return ("森で撮った写真が", "forest photos")
        case .sky: return ("空の写真が", "sky photos")
        case .days: return ("撮った日が", "days of shooting")
        }
    }

    private var unit: String {
        switch self {
        case .books: return "冊"
        case .prefectures: return "つ"
        case .samePlace: return "回"
        case .days: return "日"
        default: return "枚"
        }
    }

    /// 入手のしかた（一行）
    var how: String {
        guard self != .starter else { return L("最初から", "From the start") }
        let n = progress(CamperStats()).need
        return L("\(what.ja) \(n) \(unit)になると届きます", "Arrives at \(n) \(what.en)")
    }

    /// 届いた理由（届いたときの画面）
    var because: String {
        guard self != .starter else { return L("最初から持っています", "You've had it from the start") }
        let n = progress(CamperStats()).need
        return L("\(what.ja) \(n) \(unit)になったので届きました", "You reached \(n) \(what.en)")
    }
}

/// 集める部品の1つ
struct CamperPart: Equatable, Sendable, Identifiable {
    let category: CamperCategory
    /// 分類の中の名前（保存の鍵。変えない）
    let key: String
    let name: String
    /// 見た目の一行（板の「look」）
    let look: String
    let rarity: CamperRarity
    let unlock: CamperUnlock
    /// 色の見本（塗装・オーニング・ナンバー。札の丸に出す）
    var swatch: UInt32?

    var id: String { "\(category.rawValue).\(key)" }
}

/// 部品の一覧（2026-10-18 判断: 入手の数は板の案と、端末で数えられる値。人の写った写真を外す決まりは第2段の切り抜きと一緒に入れる）
enum CamperCatalog {

    private static func p(_ c: CamperCategory, _ key: String, _ ja: String, _ en: String, _ lookJa: String, _ lookEn: String,
                          _ r: CamperRarity, _ u: CamperUnlock, _ swatch: UInt32? = nil) -> CamperPart {
        CamperPart(category: c, key: key, name: L(ja, en), look: L(lookJa, lookEn), rarity: r, unlock: u, swatch: swatch)
    }

    static let all: [CamperPart] = [
        // ホイール
        p(.wheel, "chrome", "クロームの皿", "Chrome dish", "鏡の皿・ナット 6・真鍮のキャップ", "Mirror dish, 6 nuts, brass cap", .common, .starter),
        p(.wheel, "steel", "黒い鉄ホイール", "Black steel", "黒い鉄に丸い穴 6、クロームのキャップ", "Black steel with 6 holes", .common, .posts(30)),
        p(.wheel, "whitewall", "白い帯のタイヤ", "Whitewall", "側面に白い帯、クロームの皿", "White band on the sidewall", .occasional, .prefectures(5)),
        p(.wheel, "spoke", "銀のスポーク", "Silver spokes", "細いスポーク 8 本の奥にブレーキの胴", "Eight thin spokes", .rare, .days(30)),
        p(.wheel, "deep", "深いリム", "Deep dish", "磨いたアルミの深い縁と小さな芯", "Polished deep lip, small centre", .veryRare, .books(12)),
        // タイヤの溝
        p(.tread, "road", "道の溝", "Road tread", "横溝 22 本 × 2 列と縦溝 1", "22 × 2 blocks and a centre groove", .common, .starter),
        p(.tread, "rib", "細い縦溝", "Rib tread", "縦に走る溝 4 本", "Four running ribs", .common, .posts(15)),
        p(.tread, "block", "山道のブロック", "Trail blocks", "大きな四角い山 16 × 3 列", "Big square lugs", .occasional, .autumn(10)),
        p(.tread, "snow", "雪のサイプ", "Snow sipes", "細かな山 30 × 3 列", "Fine blocks for snow", .occasional, .winter(10)),
        // 前照灯
        p(.light, "round", "丸い前照灯", "Round", "クロームの縁と反射板の輪 2", "Chrome bezel, two reflector rings", .common, .starter),
        p(.light, "twin", "丸目 4 灯", "Quad round", "小さな丸い灯を 2 つずつ", "Two small lamps each side", .occasional, .night(5)),
        p(.light, "square", "角形の前照灯", "Square", "四角い縁と平らなレンズ", "Square bezel, flat lens", .occasional, .night(10)),
        p(.light, "rally", "真鍮のラリーランプ", "Brass rally lamps", "バンパーの上に真鍮の丸灯 2", "Two brass lamps above the bumper", .rare, .early(3)),
        // グリル
        p(.grille, "bars", "クロームの桟", "Chrome bars", "横の桟 4 本", "Four horizontal bars", .common, .starter),
        p(.grille, "mesh", "網目のグリル", "Mesh", "細かな格子", "Fine grid", .common, .posts(20)),
        p(.grille, "slats", "縦の桟", "Vertical slats", "縦に並ぶ桟 9 本", "Nine upright slats", .occasional, .books(4)),
        p(.grille, "brass", "真鍮の桟", "Brass bars", "太い真鍮の桟と縁", "Thick brass bars and frame", .rare, .samePlace(5)),
        // バンパー
        p(.bumper, "chrome", "クロームのバンパー", "Chrome bumper", "丸みのある鏡の板", "Rounded mirror bar", .common, .starter),
        p(.bumper, "steel", "黒い鉄のバンパー", "Steel bumper", "角張った黒い鉄と牽引の輪", "Square black steel, tow rings", .common, .posts(10)),
        p(.bumper, "wood", "木のバンパー", "Wooden bumper", "厚い木の梁に鉄の帯", "Thick beam with iron straps", .occasional, .forest(5)),
        p(.bumper, "tube", "パイプのバンパー", "Tube bumper", "曲げたパイプの枠", "Bent tube frame", .rare, .autumn(20)),
        // ミラー
        p(.mirror, "square", "黒い角形のミラー", "Square mirror", "黒い箱に鏡", "Black box mirror", .common, .starter),
        p(.mirror, "round", "丸いクロームのミラー", "Round mirror", "丸い鏡と細い腕", "Round chrome mirror on a thin arm", .common, .posts(8)),
        p(.mirror, "long", "長い腕のミラー", "Long-arm mirror", "車幅より外へ出る長い腕", "Arms reaching past the body", .occasional, .books(5)),
        p(.mirror, "bullet", "砲弾形のミラー", "Bullet mirror", "流線形のクローム", "Streamlined chrome", .rare, .summer(20)),
        // 泥よけ
        p(.mudflap, "rubber", "黒いゴムの泥よけ", "Rubber flaps", "車輪の後ろの黒い板", "Plain black flaps", .common, .starter),
        p(.mudflap, "split", "割れた泥よけ", "Split flaps", "細い 2 枚に割れたゴム", "Two narrow strips", .common, .books(2)),
        p(.mudflap, "diamond", "縞板の泥よけ", "Tread plate flaps", "滑り止めの山のあるアルミ", "Aluminium with raised diamonds", .occasional, .posts(25)),
        p(.mudflap, "long", "長い泥よけ", "Long flaps", "地面近くまで、真鍮の重り", "Down to the ground with a brass weight", .rare, .winter(15)),
        // はしご
        p(.ladder, "chrome", "クロームのはしご", "Chrome ladder", "柱 2・段 8・留め具 4", "Two rails, eight rungs", .common, .starter),
        p(.ladder, "flat", "黒い平らな段", "Flat-step ladder", "踏み板の広い黒いはしご", "Wide black steps", .common, .posts(12)),
        p(.ladder, "wood", "木のはしご", "Wooden ladder", "木の柱と段、真鍮の金具", "Wood with brass fittings", .occasional, .forest(10)),
        p(.ladder, "rail", "手すりつきのはしご", "Ladder with handrail", "上に真鍮の輪の手すり", "A brass hoop at the top", .rare, .books(8)),
        // 取っ手
        p(.handle, "bar", "クロームの取っ手", "Chrome bar", "細い棒の取っ手", "A slim bar", .common, .starter),
        p(.handle, "lever", "黒いレバー", "Black lever", "倒して開けるレバー", "A lever handle", .common, .books(1)),
        p(.handle, "ring", "真鍮の輪", "Brass ring", "輪を引いて開ける", "A brass ring pull", .occasional, .posts(18)),
        p(.handle, "wood", "木の握り", "Wooden grip", "木の握りと真鍮の台", "A wooden grip on brass mounts", .occasional, .forest(8)),
        // 窓の形
        p(.window, "rounded", "角丸の窓", "Rounded windows", "角の丸い四角", "Rounded rectangles", .common, .starter),
        p(.window, "grid", "格子の窓", "Grid windows", "十字の桟の入った窓", "Windows with a cross bar", .occasional, .books(6)),
        p(.window, "round", "丸窓", "Portholes", "船のような丸い窓", "Round ship windows", .occasional, .sky(10)),
        p(.window, "arch", "アーチの窓", "Arched windows", "上が半円の窓", "Round-topped windows", .rare, .spring(15)),
        // オーニング
        p(.awning, "indigo", "藍の縞", "Indigo stripes", "藍と生成りの縞 10 本、脚 2・張り綱 2", "Indigo and ecru stripes", .common, .starter, 0x2F4F74),
        p(.awning, "canvas", "生成りの帆布", "Plain canvas", "無地の帆布と真っ直ぐな垂れ", "Plain canvas, straight valance", .common, .posts(40), 0xE8E0CC),
        p(.awning, "forest", "森の緑の縞", "Forest stripes", "森の緑と生成りの縞、波の垂れ", "Forest stripes, scalloped valance", .occasional, .forest(15), 0x4A5A46),
        p(.awning, "tarp", "三角のタープ", "Tarp", "一本の柱で張る三角の布", "A triangle on one pole", .rare, .summer(10), 0x8A6D3D),
        // 後ろの荷台
        p(.rear, "bike", "自転車 1 台", "One bike", "後ろの台に赤い自転車", "A red bike on the rear rack", .common, .posts(5)),
        p(.rear, "box", "木の荷箱", "Wooden box", "後ろに提げた木の箱", "A wooden box on the rack", .common, .books(2)),
        p(.rear, "bikes", "自転車 2 台", "Two bikes", "赤と紺の自転車", "Red and navy bikes", .occasional, .books(5)),
        p(.rear, "firewood", "薪の棚", "Firewood rack", "割った薪を積んだ鉄の棚", "Split logs in an iron rack", .rare, .winter(5)),
        // 屋根の積み荷
        p(.roof, "crate", "木箱と巻いたマット", "Crate and mat", "木目の箱・縫い目のマット・赤い携行缶", "Crate, stitched mat, jerry can", .common, .starter),
        p(.roof, "basket", "荷かごと鞄", "Basket and bags", "鉄の荷かごに鞄 2 つ", "Two bags in a roof basket", .common, .posts(12)),
        p(.roof, "box", "ルーフボックス", "Roof box", "車体色の流線形の箱、クロームの留め金 2", "Streamlined box, two chrome latches", .occasional, .winter(20)),
        p(.roof, "surf", "サーフボード", "Surfboards", "2 枚を帯で留める", "Two boards strapped down", .occasional, .summer(5)),
        p(.roof, "kayak", "カヤック", "Kayak", "黄色い樹脂の舟を伏せて", "A yellow kayak, upside down", .rare, .summer(15)),
        p(.roof, "tent", "ルーフテント", "Roof tent", "屋根の上で開く三角のテントとはしご", "A tent that opens on the roof", .veryRare, .books(15)),
        // ソーラーパネル
        p(.solar, "single", "太陽電池 1 枚", "One panel", "枠と 6 列の升", "Framed, six columns", .common, .starter),
        p(.solar, "double", "太陽電池 2 枚", "Two panels", "小さめの 2 枚を並べて", "Two smaller panels", .occasional, .posts(35)),
        p(.solar, "wind", "風車つき", "With wind turbine", "太陽電池と小さな風車の柱", "Panel plus a small turbine", .rare, .prefectures(8)),
        p(.solar, "full", "屋根いっぱい", "Full roof", "屋根を覆う 3 枚", "Three panels across the roof", .veryRare, .posts(120)),
        // アンテナ
        p(.antenna, "whip", "細い竿のアンテナ", "Whip", "しなる細い竿", "A thin whip", .common, .starter),
        p(.antenna, "spring", "ばねのアンテナ", "Spring antenna", "根元にばね", "A coil spring at the base", .occasional, .posts(22)),
        p(.antenna, "dish", "パラボラ", "Dish", "小さな皿形のアンテナ", "A small satellite dish", .occasional, .night(15)),
        p(.antenna, "fin", "背びれのアンテナ", "Shark fin", "屋根の背びれ", "A shark-fin housing", .rare, .early(6)),
        // 旗
        p(.flag, "pennant", "三角の旗", "Pennant", "竿の先に三角の旗", "A pennant on a pole", .common, .starter),
        p(.flag, "flag", "四角い旗", "Flag", "竿に四角い旗", "A square flag", .common, .books(1)),
        p(.flag, "bunting", "連なる小旗", "Bunting", "オーニングの箱に小旗の列", "A string of pennants", .occasional, .spring(5)),
        p(.flag, "windsock", "吹き流し", "Windsock", "筒の吹き流し", "A tapered windsock", .rare, .samePlace(4)),
        // 塗装（板 CamperDecorate の 4 色）
        p(.paint, "cloud", "雲の影の灰", "Cloud-shadow grey", "撮った写真から拾った色", "Picked from your photos", .common, .starter, 0x5B6168),
        p(.paint, "mist", "霧の白", "Mist white", "撮った写真から拾った色", "Picked from your photos", .common, .starter, 0xD9D4C7),
        p(.paint, "sky", "朝の空の青", "Morning-sky blue", "空の写真から拾った色", "Picked from your sky photos", .occasional, .sky(1), 0x7F97AB),
        p(.paint, "forest", "森の緑", "Forest green", "森の写真から拾った色", "Picked from your forest photos", .occasional, .forest(15), 0x4A5A46),
        // ステッカーの縁
        p(.stickerEdge, "white", "白い切り抜き", "White die-cut", "白い紙の縁と艶", "White paper edge", .common, .starter),
        p(.stickerEdge, "black", "黒い縁", "Black edge", "細い黒の縁", "A thin black edge", .common, .posts(6)),
        p(.stickerEdge, "patch", "刺繍のワッペン", "Embroidered patch", "厚い布に縫い目の縁", "Thick cloth with a stitched rim", .occasional, .days(10)),
        p(.stickerEdge, "gold", "金の箔押し", "Gold foil", "真鍮色の箔の縁", "Brass foil edge", .rare, .samePlace(3)),
        // ステッカー（第1段は図柄。写真のステッカーは第2段）
        p(.sticker, "mountain", "山並み", "Mountains", "青い山並みに雪の頂", "Blue ridges, snowy peaks", .common, .starter),
        p(.sticker, "sun", "太陽", "Sun", "光の筋 12 本", "Twelve rays", .occasional, .posts(10)),
        p(.sticker, "wave", "波", "Wave", "重なる波", "Overlapping waves", .occasional, .books(3)),
        p(.sticker, "star", "一番星", "Evening star", "夜空色の地に星", "A star on night blue", .rare, .night(20)),
        p(.sticker, "compass", "方位", "Compass", "八方の方位の星", "An eight-point compass", .veryRare, .prefectures(12)),
        // ナンバー
        p(.plate, "white", "白いナンバー", "White plate", "白い地に緑の数字", "Green on white", .common, .starter, 0xECE7DA),
        p(.plate, "yellow", "黄色いナンバー", "Yellow plate", "黄色い地に黒い数字", "Black on yellow", .occasional, .posts(10), 0xE8C547),
        p(.plate, "wood", "木の名札", "Wooden plate", "角の丸い木の板に焼いた数字", "Burnt numbers on rounded wood", .occasional, .forest(12), 0x9A6A3E),
        p(.plate, "brass", "真鍮の旅札", "Brass plate", "真鍮の板にねじ 4 つ", "Brass with four screws", .rare, .books(7), 0xC9A66B),
        // 椅子
        p(.chair, "canvas", "帆布の椅子", "Canvas chair", "折りたたみの帆布の椅子 2 脚", "Two folding canvas chairs", .common, .starter),
        p(.chair, "stool", "丸い腰掛け", "Stools", "丸太を切った腰掛け 3 つ", "Three log stools", .common, .posts(4)),
        p(.chair, "deck", "デッキチェア", "Deck chairs", "木の枠に縞の布", "Wooden frame, striped seat", .occasional, .summer(8)),
        p(.chair, "hammock", "ハンモック", "Hammock", "弧の台に吊った網", "A hammock on an arched stand", .rare, .forest(20)),
        // 机と焚き火
        p(.table, "folding", "折りたたみの机", "Folding table", "アルミの脚と木の天板", "Aluminium legs, wooden top", .common, .starter),
        p(.table, "firepit", "焚き火台", "Fire pit", "鉄の皿に薪", "An iron bowl with logs", .occasional, .autumn(5)),
        p(.table, "log", "丸太の机", "Log table", "太い丸太を半分に", "A split log on legs", .occasional, .forest(6)),
        p(.table, "stove", "薪ストーブ", "Wood stove", "煙突のある小さな鉄の箱", "A small iron stove with a chimney", .rare, .winter(25)),
        // 外の灯り
        p(.outLight, "lantern", "ランタン", "Lantern", "台に掛けた真鍮のランタン", "A brass lantern on a stand", .common, .starter),
        p(.outLight, "string", "ストリングライト", "String lights", "オーニングから脚へ電球の列", "Bulbs from the awning to the pole", .occasional, .night(8)),
        p(.outLight, "torch", "松明", "Torches", "竹の松明 2 本", "Two bamboo torches", .rare, .summer(25)),
        p(.outLight, "toro", "石の灯籠", "Stone lantern", "小さな石の灯籠", "A small stone lantern", .veryRare, .books(20)),
        // 外のラグ
        p(.rug, "woven", "織りのラグ", "Woven rug", "縞の四角いラグ", "A striped rectangle", .common, .starter),
        p(.rug, "round", "丸い編みラグ", "Braided rug", "輪を重ねた丸いラグ", "Concentric braided rings", .common, .posts(16)),
        p(.rug, "deck", "ウッドデッキ", "Deck boards", "地面に並べた板", "Boards laid on the ground", .occasional, .books(9)),
        p(.rug, "fringe", "房飾りのマット", "Fringed mat", "端に房のあるマット", "A mat with tassels", .rare, .spring(10)),
        // カーテン
        p(.curtain, "pleat", "ひだのカーテン", "Pleated", "左右にひだ 3 枚ずつ", "Three pleats each side", .common, .starter),
        p(.curtain, "roller", "巻き上げの日よけ", "Roller blind", "上に巻いた布", "Rolled up at the top", .common, .posts(7)),
        p(.curtain, "cafe", "下半分のカーテン", "Café curtain", "窓の下半分だけ", "Covers the lower half", .occasional, .books(3)),
        p(.curtain, "blind", "羽根のブラインド", "Venetian blind", "細い羽根の列", "Rows of thin slats", .rare, .night(25)),
        // クッション
        p(.cushion, "square", "四角いクッション", "Square cushions", "長椅子に 2 つ", "Two on the bench", .common, .starter),
        p(.cushion, "round", "丸いクッション", "Round cushions", "平たい丸 3 つ", "Three flat rounds", .common, .posts(9)),
        p(.cushion, "bolster", "筒のクッション", "Bolsters", "端に置く筒形", "Rolls at each end", .occasional, .summer(3)),
        p(.cushion, "patch", "継ぎはぎのクッション", "Patchwork", "四色の布を継いだ", "Four cloths sewn together", .rare, .days(20)),
        // 吊りランプ
        p(.lamp, "dome", "真鍮の笠", "Brass dome", "吊り下げの真鍮の笠", "A brass dome shade", .common, .starter),
        p(.lamp, "bulb", "裸電球", "Bare bulb", "コードの先の電球", "A bulb on a cord", .common, .posts(14)),
        p(.lamp, "paper", "紙の提灯", "Paper lantern", "丸い紙の提灯", "A round paper lantern", .occasional, .spring(3)),
        p(.lamp, "chandelier", "小さな燭台", "Little chandelier", "輪に灯が 4 つ", "Four lights on a ring", .veryRare, .prefectures(15)),
        // 棚
        p(.shelf, "books", "本棚", "Bookshelf", "吊り戸棚の下に本の段", "A row of books", .common, .starter),
        p(.shelf, "spice", "香辛料の棚", "Spice rack", "小瓶が 6 つ", "Six little jars", .common, .posts(11)),
        p(.shelf, "mugs", "マグの掛け", "Mug hooks", "掛けたマグ 4 つ", "Four mugs on hooks", .occasional, .early(1)),
        p(.shelf, "plants", "鉢の棚", "Plant shelf", "小さな鉢が 3 つ", "Three little pots", .rare, .forest(25)),
        // 壁の木
        p(.wall, "birch", "白樺の合板", "Birch ply", "明るい無地の板", "Plain light panels", .common, .starter),
        p(.wall, "walnut", "胡桃の板", "Walnut panels", "濃い板に縦の継ぎ目", "Dark panels with seams", .occasional, .books(5)),
        p(.wall, "shiplap", "白い横板", "White shiplap", "横に重ねた白い板", "Horizontal white boards", .occasional, .posts(45)),
        p(.wall, "cedar", "杉の細板", "Cedar slats", "細い縦板の溝", "Narrow upright slats", .rare, .autumn(15)),
        // 床
        p(.floor, "oak", "楢の板", "Oak boards", "長い板目", "Long oak boards", .common, .starter),
        p(.floor, "cork", "コルク", "Cork", "柔らかなコルクの升", "Soft cork tiles", .common, .books(2)),
        p(.floor, "checker", "市松のタイル", "Checker tiles", "白と黒の升", "Black and white squares", .occasional, .posts(28)),
        p(.floor, "terrazzo", "石の粒の床", "Terrazzo", "石の粒を散らした床", "Speckled stone", .rare, .prefectures(10)),
        // 内装の小物
        p(.trinket, "plant", "鉢植え", "Potted plant", "素焼きの鉢に丸い葉", "Round leaves in terracotta", .common, .starter),
        p(.trinket, "books", "本の山", "Stack of books", "旅の本が 5 冊", "Five travel books", .common, .posts(5)),
        p(.trinket, "radio", "古いラジオ", "Old radio", "木の箱につまみ 2 つ", "A wooden box with two knobs", .occasional, .night(3)),
        p(.trinket, "guitar", "ギター", "Guitar", "長椅子に立てかけた木のギター", "A guitar leaning on the bench", .occasional, .books(3)),
        p(.trinket, "globe", "地球儀", "Globe", "真鍮の子午線の地球儀", "A globe with a brass meridian", .rare, .prefectures(3)),
    ]

    static func parts(_ c: CamperCategory) -> [CamperPart] { all.filter { $0.category == c } }

    static func part(_ id: String) -> CamperPart? { all.first { $0.id == id } }

    /// 分類の最初の部品（最初から持っている。付けないこともできる分類にも1つある）
    static func starter(_ c: CamperCategory) -> CamperPart {
        parts(c).first { $0.unlock == .starter } ?? parts(c)[0]
    }

    static func owned(_ stats: CamperStats) -> Set<String> {
        Set(all.filter { $0.unlock.isMet(stats) }.map(\.id))
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

    /// 自分の投稿から数える（段と部品の入手）。`books` は旅の一冊の数（呼ぶ側が `TripBook.shelfTrips` で数える）
    static func stats(photos: [Photo], books: Int) -> CamperStats {
        var s = CamperStats()
        s.posts = photos.count
        s.books = books
        var prefs = Set<String>()
        var places: [String: Int] = [:]
        var days = Set<String>()
        for p in photos {
            if let t = shotTime(p.exif?.dateTimeOriginal ?? p.date) {
                if let h = t.hour {
                    if h >= 19 || h < 4 { s.nightShots += 1 } else if h < 6 { s.earlyShots += 1 }
                }
                switch t.month {
                case 3...5: s.springShots += 1
                case 6...8: s.summerShots += 1
                case 9...11: s.autumnShots += 1
                default: s.winterShots += 1
                }
                days.insert(t.day)
            }
            if let pref = prefecture(in: p.location) { prefs.insert(pref) }
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
        s.samePlace = places.values.max() ?? 0
        s.days = days.count
        return s
    }

    /// 撮った月と時と日（EXIF の「2024:05:12 18:24:00」・「2024-05-12T18:24」・「2024-05-12」）
    static func shotTime(_ raw: String?) -> (month: Int, hour: Int?, day: String)? {
        guard let raw else { return nil }
        let nums = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 3, nums[0] > 1900, (1...12).contains(nums[1]), (1...31).contains(nums[2]) else { return nil }
        let hour = nums.count >= 4 && (0...23).contains(nums[3]) ? nums[3] : nil
        return (nums[1], hour, "\(nums[0])-\(nums[1])-\(nums[2])")
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

    static func accessibilityLabel(stage: CamperStage, mood: CamperMood, loadout: CamperLoadout, doorOpen: Bool,
                                   preview: CamperPart?) -> String {
        var parts: [String] = []
        parts.append(L("\(stage.name)。\(mood.name)", "\(stage.name), \(mood.name)"))
        parts.append(L("塗装は\(loadout.part(.paint).name)", "Paint: \(loadout.part(.paint).name)"))
        parts.append(L("\(loadout.part(.wheel).name)のホイール", "\(loadout.part(.wheel).name) wheels"))
        parts.append(L("\(loadout.part(.light).name)", "\(loadout.part(.light).name)"))
        parts.append(L("屋根に\(loadout.part(.roof).name)", "On the roof: \(loadout.part(.roof).name)"))
        parts.append(loadout.awningOpen
                     ? L("オーニングを広げている（\(loadout.part(.awning).name)）", "Awning out (\(loadout.part(.awning).name))")
                     : L("オーニングは畳んである", "Awning stowed"))
        let outside = [CamperCategory.chair, .table, .outLight, .rug].compactMap { loadout.pickedPart($0)?.name }
        if !outside.isEmpty {
            parts.append(L("外に\(outside.joined(separator: "・"))", "Outside: \(outside.joined(separator: ", "))"))
        }
        parts.append(L("室内に\(loadout.part(.trinket).name)", "Inside: \(loadout.part(.trinket).name)"))
        parts.append(doorOpen ? L("扉が開いている", "Door open") : L("扉は閉じている", "Door closed"))
        if let preview {
            parts.append(L("まだ持っていない「\(preview.name)」を影で見ています", "Previewing \(preview.name), not yet collected"))
        }
        return parts.joined(separator: L("。", ". "))
    }

    /// 部品の札の読み上げ
    static func partLabel(_ p: CamperPart, owned: Bool, stats: CamperStats) -> String {
        if owned { return L("\(p.name)。\(p.rarity.name)", "\(p.name), \(p.rarity.name)") }
        let pr = p.unlock.progress(stats)
        return L("まだ持っていない部品。\(p.name)。\(p.unlock.how)。いま \(pr.have) / \(pr.need)",
                 "Not yet collected: \(p.name). \(p.unlock.how). \(pr.have) of \(pr.need)")
    }
}
