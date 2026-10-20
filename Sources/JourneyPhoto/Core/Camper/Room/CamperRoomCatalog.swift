import Foundation

// とおまわり号の中の家具図鑑（2026-10-19・板「家具図鑑」CamperFurniture が正）。
//
// 板の 16 分類・64 個（床 7・壁 5・天井 4 分類。1 分類に 4 つ、どれも形がちがう）に、
// 形の組み合わせで作る家具（`CamperRoomVariety`。あつ森の 2,076 を超える）を足す。id は「分類.部品」で、アプリの中では
// 前に `camper.room.` を付ける（外まわりの `table` と名前がぶつからない）。名前・説明・珍しさ・入手の条件は板のまま。
//
// 第1段（端末だけ）で届くのは、入手の条件が端末で決まり、**形を作り込んだもの**だけ（`isAvailable`）。
// - 板の 64 個は全部形を作り込んだ（2026-10-20 owner「全部作り込んで」。`CamperRoomFurnitureModels`〜`Models3`）。
// - 要サーバーの 10 個とキャンプ場が要る掛けたランタンは、形はあるが入手は「近日」のまま数（分母）から外す。
// - 2026-10-19 判断: 板の「写真に写った物（寺・和室・料理など。端末の画像分類）」は、外まわりの部品の山・海と同じく
//   撮影地・題・タグの言葉で読む（`CamperRoomStats`）。画像分類の精度は試していない（板の「確かめていない」と同じ）。

/// 家具を置く所（置ける場所の決まりになる）
enum CamperRoomPlacement: String, CaseIterable, Codable, Sendable {
    case floor, wall, ceiling

    var name: String {
        switch self {
        case .floor: return L("床", "Floor")
        case .wall: return L("壁", "Wall")
        case .ceiling: return L("天井", "Ceiling")
        }
    }

    /// 図鑑の段の名前（板「床に置く・壁に掛ける・天井から吊るす」）
    var title: String {
        switch self {
        case .floor: return L("床に置く", "On the floor")
        case .wall: return L("壁に掛ける", "On the wall")
        case .ceiling: return L("天井から吊るす", "From the ceiling")
        }
    }
}

/// 家具の分類（板の 16 分類）
enum CamperRoomCategory: String, CaseIterable, Codable, Sendable {
    // 床
    case bed, seating, table, storage, heater
    case roomRug = "room_rug"
    case floorLamp = "floor_lamp"
    // 壁
    case wallShelf = "wall_shelf"
    case photoFrame = "photo_frame"
    case poster
    case wallLamp = "wall_lamp"
    case clock
    // 天井
    case stringCeiling = "string_ceiling"
    case mobile
    case plantHanger = "plant_hanger"
    case roofHatch = "roof_hatch"

    var placement: CamperRoomPlacement {
        switch self {
        case .bed, .seating, .table, .storage, .heater, .roomRug, .floorLamp: return .floor
        case .wallShelf, .photoFrame, .poster, .wallLamp, .clock: return .wall
        case .stringCeiling, .mobile, .plantHanger, .roofHatch: return .ceiling
        }
    }

    var name: String {
        switch self {
        case .bed: return L("寝台", "Beds")
        case .seating: return L("椅子", "Seating")
        case .table: return L("机", "Tables")
        case .storage: return L("しまう物", "Storage")
        case .heater: return L("暖める物", "Heaters")
        case .roomRug: return L("部屋の敷物", "Rugs")
        case .floorLamp: return L("床の灯り", "Floor lamps")
        case .wallShelf: return L("壁の棚", "Wall shelves")
        case .photoFrame: return L("写真の額", "Photo frames")
        case .poster: return L("壁に貼る物", "Posters")
        case .wallLamp: return L("壁の灯り", "Wall lamps")
        case .clock: return L("時計", "Clocks")
        case .stringCeiling: return L("天井の飾り", "Ceiling strings")
        case .mobile: return L("モビール", "Mobiles")
        case .plantHanger: return L("吊るす植物", "Hanging plants")
        case .roofHatch: return L("天窓", "Roof hatches")
        }
    }

    /// 札の印（SF Symbols）
    var symbol: String {
        switch self {
        case .bed: return "bed.double"
        case .seating: return "sofa"
        case .table: return "table.furniture"
        case .storage: return "archivebox"
        case .heater: return "flame"
        case .roomRug: return "square.dashed"
        case .floorLamp: return "lamp.floor"
        case .wallShelf: return "books.vertical"
        case .photoFrame: return "photo.on.rectangle"
        case .poster: return "doc.richtext"
        case .wallLamp: return "lightbulb"
        case .clock: return "clock"
        case .stringCeiling: return "sparkles"
        case .mobile: return "bird"
        case .plantHanger: return "leaf"
        case .roofHatch: return "square.grid.2x2"
        }
    }
}

/// 自分の投稿から数える、室内の家具だけの値（外まわりの `CamperStats` に無いもの）。
/// 2026-10-19 判断: 写真に写った物は撮影地・題・タグの言葉で読む（`CamperCounting.natureText` で地名を外してから）
struct CamperRoomStats: Equatable, Sendable {
    /// 春（3〜5 月）の写真
    var springShots = 0
    /// 雪・市場・寺・和室・料理・本・星空・教会の写真
    var topics: [CamperRoomTopic: Int] = [:]
    /// 同じ日に撮った写真のいちばん多い数
    var sameDayMax = 0

    func count(_ t: CamperRoomTopic) -> Int { topics[t] ?? 0 }
}

/// 写真に写った物（言葉で読む）
enum CamperRoomTopic: String, CaseIterable, Sendable {
    case snow, market, temple, washitsu, food, book, starry, church

    /// 当たる言葉（日本語・英語。小文字で比べる）
    var words: [String] {
        switch self {
        case .snow: return ["雪", "snow"]
        case .market: return ["市場", "朝市", "マルシェ", "market"]
        case .temple: return ["寺", "temple"]
        case .washitsu: return ["和室", "座敷", "畳", "旅館", "tatami", "ryokan"]
        case .food: return ["料理", "ごはん", "ご飯", "食堂", "ランチ", "朝食", "夕食", "定食", "food", "lunch", "dinner"]
        case .book: return ["本", "書店", "古書", "図書", "book", "library"]
        case .starry: return ["星空", "星", "天の川", "starry", "stars", "milky way"]
        case .church: return ["教会", "聖堂", "church", "cathedral"]
        }
    }

    var name: String {
        switch self {
        case .snow: return L("雪", "snow")
        case .market: return L("市場", "market")
        case .temple: return L("寺", "temple")
        case .washitsu: return L("和室", "tatami room")
        case .food: return L("料理", "food")
        case .book: return L("本", "book")
        case .starry: return L("星空", "starry-sky")
        case .church: return L("教会", "church")
        }
    }
}

/// 家具の手に入れ方。外まわりの部品と同じ数え方（`CamperUnlock`）に、室内だけの条件を足す
enum CamperRoomUnlock: Equatable, Sendable {
    /// 外まわりの部品と同じ条件（最初から・写真の枚数・夜・冬・都道府県・同じ場所・森・空・満月・続けた月・車の段・要サーバー）
    case base(CamperUnlock)
    /// 写真に写った物の枚数（言葉で読む）
    case topic(CamperRoomTopic, Int)
    /// 春の写真の枚数
    case spring(Int)
    /// 同じ日に撮った枚数
    case sameDay(Int)

    var isAvailable: Bool {
        if case .base(let u) = self { return u.isAvailable }
        return true
    }

    func progress(_ s: CamperStats, _ r: CamperRoomStats) -> (have: Int, need: Int) {
        switch self {
        case .base(let u): return u.progress(s)
        case let .topic(t, n): return (r.count(t), n)
        case .spring(let n): return (r.springShots, n)
        case .sameDay(let n): return (r.sameDayMax, n)
        }
    }

    func isMet(_ s: CamperStats, _ r: CamperRoomStats) -> Bool {
        guard isAvailable else { return false }
        let p = progress(s, r)
        return p.have >= p.need
    }

    func fraction(_ s: CamperStats, _ r: CamperRoomStats) -> Double {
        guard isAvailable else { return 0 }
        let p = progress(s, r)
        guard p.need > 0 else { return 1 }
        return min(1, max(0, Double(p.have) / Double(p.need)))
    }

    var condition: String {
        switch self {
        case .base(let u): return u.condition
        case let .topic(t, n):
            return n <= 1 ? L("\(t.name)の写真", "A \(t.name) photo") : L("\(t.name)の写真 \(n) 枚", "Photos of \(t.name): \(n)")
        case .spring(let n): return L("春の写真 \(n) 枚", "Spring photos: \(n)")
        case .sameDay(let n): return L("同じ日に \(n) 枚撮る", "Photos in one day: \(n)")
        }
    }

    var isStarter: Bool { self == .base(.starter) }
}

/// 家具 1 つ（図鑑の 1 枠）
struct CamperRoomFurniture: Equatable, Sendable, Identifiable {
    let category: CamperRoomCategory
    /// 分類の中の名前（保存の鍵。変えない）
    let key: String
    let nameJa: String
    let nameEn: String
    let lookJa: String
    let lookEn: String
    let rarity: CamperRarity
    let unlock: CamperRoomUnlock
    /// 大きさ（マス）。床と天井は 横（x）× 奥（z）、壁は 横のマス × 段
    let width: Int
    let depth: Int
    /// 高さ（板の単位・1 マス = 10 ≈ 25 cm）。壁の物は壁から出る厚み
    let height: Double
    /// 写真を何枚入れるか（額・ポスター）
    let photoSlots: Int
    /// 夜に灯る（灯り・ストーブ・電球の紐）
    let lit: Bool
    /// 形を高い質で作り込んだか（第1段で届くのはこれだけ）
    let built: Bool

    var name: String { L(nameJa, nameEn) }
    var look: String { L(lookJa, lookEn) }
    var id: String { "\(category.rawValue).\(key)" }
    var placement: CamperRoomPlacement { category.placement }
    /// 敷物（床の 0 層。ほかの家具の下に敷ける）
    var isRug: Bool { category == .roomRug }
    /// 第1段で届くか（要サーバー・まだ形を作っていないものは「近日」）
    var isAvailable: Bool { built && unlock.isAvailable }
    /// 1 つ持てば何枚でも飾れる（写真を入れる額・ポスター）。2026-10-19 判断: 写真を飾るのがこの部屋の主役なので、
    /// 額は写真の上限（`CamperRoomKind.photoLimit`）まで何枚でも出せる。ほかの家具は 1 つ持てば 1 つ置ける
    var reusable: Bool { photoSlots > 0 }
}

enum CamperRoomCatalog {

    // swiftlint:disable:next function_parameter_count
    private static func f(_ c: CamperRoomCategory, _ key: String, _ ja: String, _ en: String, _ look: String, _ lookEn: String,
                          _ r: CamperRarity, _ u: CamperRoomUnlock, _ w: Int, _ d: Int, _ h: Double,
                          photos: Int = 0, lit: Bool = false, built: Bool = false) -> CamperRoomFurniture {
        CamperRoomFurniture(category: c, key: key, nameJa: ja, nameEn: en, lookJa: look, lookEn: lookEn, rarity: r, unlock: u,
                            width: w, depth: d, height: h, photoSlots: photos, lit: lit, built: built)
    }

    private static let starter = CamperRoomUnlock.base(.starter)
    private static func posts(_ n: Int) -> CamperRoomUnlock { .base(.posts(n)) }
    private static func server(_ ja: String, _ en: String) -> CamperRoomUnlock { .base(.server(ja, en)) }

    /// 64 個（板の並び）。大きさ・高さは板の付箋「マス目と寸法」（寝台 8×4・座卓 4×4・ストーブ 2×2・床の灯り 1×1・
    /// ラグ 6×4・椅子 3×3・本棚 3×1・物入れ 3×2、高さ 寝台 22・座卓 30・ストーブ 88・床の灯り 56）。板に無いものは実物の寸法から
    /// 板の 64 個。増やした家具は `all` にだけ足す（板の id は変えない）
    static let board: [CamperRoomFurniture] = [
        // 寝台（bed）
        f(.bed, "platform", "木の寝台", "Wooden platform bed", "低い木枠に布団と枕 2", "A low timber frame, a futon and two pillows",
          .common, starter, 8, 4, 22, built: true),
        f(.bed, "bunk", "二段寝台", "Bunk bed", "柱 2 と段 5 のはしご", "Two posts and a five-rung ladder",
          .rare, .base(.books(CamperStage.trailerBooks)), 8, 4, 80, built: true),
        f(.bed, "futon", "畳む布団", "Folding futon", "床に敷いて畳める", "Laid on the floor, folds away",
          .occasional, posts(40), 8, 4, 8, built: true),
        f(.bed, "daybed", "デイベッド", "Daybed", "両端に縦格子の枠", "Spindle frames at both ends",
          .veryRare, server("友達が 10 回泊まりに来る", "Friends stay over 10 times"), 8, 3, 36, built: true),
        // 椅子（seating）
        f(.seating, "floor_cushion", "座布団", "Floor cushion", "房の付いた丸い座布団", "A round cushion with tassels",
          .common, starter, 2, 2, 6, built: true),
        f(.seating, "wingback", "耳付きの椅子", "Wingback chair", "背が高く両脇が張り出す", "A tall back with wings",
          .rare, .base(.samePlace(5)), 3, 3, 44, built: true),
        f(.seating, "beanbag", "ビーズの袋", "Beanbag", "形の決まらない袋", "A bag that takes any shape",
          .occasional, posts(30), 3, 3, 25, built: true),
        f(.seating, "bench_storage", "物入れの長椅子", "Storage bench", "座面の下が物入れ", "Storage under the seat",
          .occasional, server("旅を 3 回投稿", "Post 3 trips"), 5, 2, 18, built: true),
        // 机（table）
        f(.table, "dinette_post", "一本脚の座卓", "Pedestal dinette table", "床から一本の柱", "A single post from the floor",
          .common, starter, 4, 3, 30, built: true),
        f(.table, "round_cafe", "丸いカフェ机", "Round café table", "鉄の三本脚に丸い天板", "A round top on three iron legs",
          .occasional, .base(.city(15)), 3, 3, 30, built: true),
        f(.table, "fold_down", "壁の折り畳み机", "Fold-down table", "壁から倒す天板と腕 2", "A top that folds down on two arms",
          .rare, posts(80), 4, 2, 30, built: true),
        f(.table, "chabudai", "ちゃぶ台", "Chabudai", "低い丸い天板と脚 4", "A low round top on four legs",
          .rare, .topic(.washitsu, 1), 3, 3, 13, built: true),
        // しまう物（storage）
        f(.storage, "trunk", "旅の鞄", "Travel trunk", "丸い蓋と真鍮の帯 2", "A domed lid and two brass bands",
          .common, starter, 3, 2, 18, built: true),
        f(.storage, "tall_drawers", "背の高い引き出し", "Tall drawers", "4 段と真鍮の取っ手", "Four drawers with brass pulls",
          .occasional, posts(50), 2, 2, 50, built: true),
        f(.storage, "wicker_baskets", "籐の籠 3", "Three wicker baskets", "編み目の籠を 3 つ", "Three woven baskets",
          .occasional, .topic(.market, 10), 3, 1, 12, built: true),
        f(.storage, "glass_cabinet", "硝子戸の棚", "Glass cabinet", "上は硝子の戸、下は木の戸", "Glass doors above, wooden doors below",
          .veryRare, .base(.prefectures(20)), 3, 2, 70, built: true),
        // 暖める物（heater）
        f(.heater, "wood_stove", "薪ストーブ", "Wood stove", "箱形に窓と煙突", "A box with a window and a flue",
          .common, starter, 2, 2, 88, lit: true, built: true),
        f(.heater, "pot_belly", "だるまストーブ", "Pot-belly stove", "丸い胴と煙突", "A round belly and a flue",
          .rare, .base(.winter(20)), 2, 2, 88, lit: true, built: true),
        f(.heater, "kerosene", "石油ストーブ", "Kerosene heater", "赤い胴と網", "A red body and a guard",
          .occasional, .topic(.snow, 10), 2, 2, 25, lit: true, built: true),
        f(.heater, "tile_hearth", "タイルの暖炉", "Tiled hearth", "市松のタイルとアーチ", "Checkered tiles and an arch",
          .veryRare, server("友達の焚き火に 10 回薪をくべる", "Add wood to friends' fires 10 times"), 3, 2, 88, lit: true, built: true),
        // 部屋の敷物（room_rug）
        f(.roomRug, "runner", "細長い敷物", "Runner", "通路に敷く細い一枚", "A narrow rug for the aisle",
          .common, starter, 6, 2, 0, built: true),
        f(.roomRug, "oval_hooked", "楕円の輪", "Oval hooked rug", "色の楕円を 5 重", "Five rings of colour",
          .occasional, posts(60), 6, 4, 0, built: true),
        f(.roomRug, "shag_round", "毛足の丸", "Round shag rug", "縁がふさふさの丸", "A round rug with a shaggy edge",
          .rare, .base(.winter(15)), 4, 4, 0, built: true),
        f(.roomRug, "tatami", "置き畳", "Tatami mat", "畳の目と黒い縁", "Woven rush with a black border",
          .rare, .topic(.temple, 1), 4, 4, 0, built: true),
        // 床の灯り（floor_lamp）
        f(.floorLamp, "brass_stem", "真鍮の一本足", "Brass stem lamp", "細い柱に緑の笠", "A slim stem and a green shade",
          .common, starter, 1, 1, 56, lit: true, built: true),
        f(.floorLamp, "tripod", "三脚の灯り", "Tripod lamp", "木の三脚に布の笠", "A wooden tripod and a fabric shade",
          .occasional, .base(.night(10)), 2, 2, 56, lit: true, built: true),
        f(.floorLamp, "arc", "弧の灯り", "Arc lamp", "大きく弧を描く腕", "A long arching arm",
          .rare, posts(100), 2, 2, 80, lit: true, built: true),
        f(.floorLamp, "paper_column", "和紙の柱", "Paper column lamp", "和紙の四角い筒", "A square washi column",
          .rare, server("夏祭りの写真", "A summer-festival photo"), 1, 1, 56, lit: true, built: true),
        // 壁の棚（wall_shelf）
        f(.wallShelf, "plank_brackets", "板と金具", "Plank and brackets", "一枚板を鉄の金具 2 で", "One plank on two iron brackets",
          .common, starter, 3, 1, 9, built: true),
        f(.wallShelf, "cubby_grid", "升目の棚", "Cubby grid", "3×3 の升目", "A three-by-three grid",
          .occasional, posts(70), 2, 2, 9, built: true),
        f(.wallShelf, "spice_rack", "小瓶の棚", "Spice rack", "3 段に小瓶 18", "Eighteen jars on three rails",
          .rare, .topic(.food, 10), 2, 1, 5, built: true),
        f(.wallShelf, "floating_corner", "角の棚", "Corner shelf", "壁の角に三角の板 2", "Two triangular boards in a corner",
          .occasional, server("旅を 4 回投稿", "Post 4 trips"), 1, 1, 9, built: true),
        // 写真の額（photo_frame）
        f(.photoFrame, "landscape", "横長の額", "Landscape frame", "黒い枠に白いマット", "A black frame with a white mat",
          .common, starter, 2, 1, 1.4, photos: 1, built: true),
        f(.photoFrame, "square", "正方形の額", "Square frame", "木の枠と吊り紐", "A wooden frame on a cord",
          .common, starter, 2, 1, 1.6, photos: 1, built: true),
        f(.photoFrame, "oval", "楕円の額", "Oval frame", "真鍮の楕円", "A brass oval",
          .rare, .base(.samePlace(3)), 1, 1, 1.4, photos: 1, built: true),
        f(.photoFrame, "triptych", "三枚続きの額", "Triptych", "3 枚を並べて一つの景色", "Three panels make one view",
          .veryRare, .sameDay(30), 4, 1, 1.4, photos: 1, built: true),
        // 壁に貼る物（poster）
        f(.poster, "tall_print", "縦長の写真", "Tall print", "白い余白とマスキングテープ", "A white border and masking tape",
          .common, starter, 2, 2, 0.3, photos: 1, built: true),
        f(.poster, "map_poster", "旅の地図", "Trip map", "自分の旅の道と点", "Your own routes and pins",
          .rare, .base(.prefectures(10)), 3, 2, 0.3, built: true),
        f(.poster, "postcard_grid", "絵はがきの列", "Postcard row", "6 枚をテープで", "Six postcards taped up",
          .occasional, server("友達から絵はがきが 6 枚届く", "Receive 6 postcards from friends"), 3, 1, 0.3, built: true),
        f(.poster, "tapestry", "タペストリー", "Tapestry", "布を棒に掛けて裾がぎざぎざ", "Cloth on a rod with a zigzag hem",
          .rare, server("旅を 8 回投稿", "Post 8 trips"), 3, 2, 1, built: true),
        // 壁の灯り（wall_lamp）
        f(.wallLamp, "glass_sconce", "硝子の壁灯", "Glass sconce", "乳白の笠と真鍮の座", "A milk-glass shade on a brass plate",
          .common, starter, 1, 1, 7, lit: true, built: true),
        f(.wallLamp, "swing_arm", "腕の灯り", "Swing-arm lamp", "折れる腕に緑の笠", "A folding arm and a green shade",
          .occasional, .topic(.book, 5), 1, 1, 12, lit: true, built: true),
        f(.wallLamp, "lantern_hook", "掛けたランタン", "Hanging lantern", "鉄の鉤にランタン", "A lantern on an iron hook",
          .occasional, .base(.later("キャンプ場の板でランタンを灯す", "Light a lantern at the campsite")), 1, 1, 9, lit: true, built: true),
        f(.wallLamp, "candle_sconce", "燭台", "Candle sconce", "真鍮の受けに蝋燭", "A candle on a brass holder",
          .rare, .base(.early(3)), 1, 1, 6, lit: true, built: true),
        // 時計（clock）
        f(.clock, "station", "駅の時計", "Station clock", "白い文字盤に目盛り 12", "A white dial with twelve marks",
          .common, starter, 1, 1, 3, built: true),
        f(.clock, "cuckoo", "鳩時計", "Cuckoo clock", "三角屋根と振り子", "A gabled roof and a pendulum",
          .rare, .base(.forest(20)), 1, 2, 6, built: true),
        f(.clock, "sunburst", "光の時計", "Sunburst clock", "真鍮の光 16 本", "Sixteen brass rays",
          .veryRare, .base(.months(12)), 2, 1, 3, built: true),
        f(.clock, "flip", "めくる時計", "Flip clock", "数字の板が二枚", "Two flaps of numbers",
          .occasional, posts(50), 1, 1, 5, built: true),
        // 天井の飾り（string_ceiling）
        f(.stringCeiling, "globe_string", "電球の紐", "Globe string lights", "丸い電球 8 つ", "Eight round bulbs",
          .common, starter, 6, 1, 14, lit: true, built: true),
        f(.stringCeiling, "fairy_net", "光の網", "Fairy-light net", "縦の線に粒 36", "Thirty-six lights on vertical strands",
          .rare, .topic(.starry, 5), 6, 1, 30, lit: true, built: true),
        f(.stringCeiling, "paper_garland", "紙の玉", "Paper garland", "色の丸 12", "Twelve paper circles",
          .occasional, .spring(20), 6, 1, 14, built: true),
        f(.stringCeiling, "bunting", "小さな旗", "Bunting", "三角の旗 9", "Nine triangular flags",
          .occasional, server("旅を 2 回投稿", "Post 2 trips"), 6, 1, 14, built: true),
        // モビール（mobile）
        f(.mobile, "paper_cranes", "折り鶴", "Paper cranes", "鶴 3 羽が揺れる", "Three cranes that sway",
          .occasional, posts(30), 1, 1, 30, built: true),
        f(.mobile, "wooden_birds", "木の鳥", "Wooden birds", "木の鳥 3 羽", "Three wooden birds",
          .common, starter, 1, 1, 30, built: true),
        f(.mobile, "star_mobile", "星", "Star mobile", "真鍮の弧に星 3", "Three stars on a brass arc",
          .rare, .base(.fullMoon(1)), 1, 1, 30, built: true),
        f(.mobile, "driftwood", "流木", "Driftwood mobile", "流木に硝子の粒 4", "Four glass drops on driftwood",
          .veryRare, .base(.sea(30)), 2, 1, 30, built: true),
        // 吊るす植物（plant_hanger）
        f(.plantHanger, "macrame", "マクラメ", "Macramé hanger", "結んだ紐に鉢", "A pot in knotted cord",
          .common, starter, 1, 1, 38, built: true),
        f(.plantHanger, "hanging_basket", "吊り籠", "Hanging basket", "籠から垂れるつる", "Vines trailing from a basket",
          .occasional, server("雨の写真 5 枚", "5 rainy-day photos"), 1, 1, 34, built: true),
        f(.plantHanger, "air_ring", "真鍮の輪", "Brass air ring", "輪に絡む葉 10", "Ten leaves wound round a ring",
          .rare, .base(.plants(15)), 1, 1, 30, built: true),
        f(.plantHanger, "glass_terrarium", "硝子の球", "Glass terrarium", "中に小さな山", "A tiny mountain inside",
          .veryRare, server("友達から贈られる", "A gift from a friend"), 1, 1, 30, built: true),
        // 天窓（roof_hatch）
        f(.roofHatch, "square_vent", "四角い換気窓", "Square roof vent", "枠と取っ手", "A frame and a handle",
          .common, starter, 2, 2, 4, built: true),
        f(.roofHatch, "round_hatch", "丸い天窓", "Round skylight", "鏡の縁の丸", "A round hatch with a bright rim",
          .occasional, .base(.sky(20)), 2, 2, 4, built: true),
        f(.roofHatch, "star_window", "星の天窓", "Star window", "夜は星が映る", "Stars show at night",
          .veryRare, .topic(.starry, 20), 2, 2, 4, built: true),
        f(.roofHatch, "stained_glass", "色硝子", "Stained glass", "8 色の扇", "A fan of eight colours",
          .rare, .topic(.church, 1), 2, 2, 4, built: true),
    ]

    /// 板の 64 個と、形の組み合わせで増やした家具
    static let all: [CamperRoomFurniture] = board + CamperRoomVariety.furniture

    private static let byId: [String: CamperRoomFurniture] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func furniture(_ id: String) -> CamperRoomFurniture? { byId[id] }

    static func items(_ c: CamperRoomCategory) -> [CamperRoomFurniture] { all.filter { $0.category == c } }

    /// 図鑑の探し欄。空なら全部。名前か id にその文字が入るもの（色違いの軸は id が「分類.x000」なので、板の id とは混ざらない）
    static func matchesDexQuery(_ f: CamperRoomFurniture, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        if f.id.range(of: q, options: .caseInsensitive) != nil { return true }
        return f.name.range(of: q, options: .caseInsensitive) != nil
    }

    static func items(_ p: CamperRoomPlacement) -> [CamperRoomFurniture] { all.filter { $0.placement == p } }

    /// 第1段で集められる家具（図鑑の数の分母）
    static var available: [CamperRoomFurniture] { all.filter(\.isAvailable) }

    /// 持っている家具（最初からの 17 と、条件を満たして形のできたもの）
    static func owned(_ s: CamperStats, _ r: CamperRoomStats) -> Set<String> {
        Set(all.filter { $0.isAvailable && $0.unlock.isMet(s, r) }.map(\.id))
    }

    /// 図鑑の「持っている / 全部」（全部は第1段で集められる数）
    static func dexCount(_ owned: Set<String>) -> (have: Int, total: Int) {
        (available.filter { owned.contains($0.id) }.count, available.count)
    }

    /// 近日（要サーバー・まだ形を作っていない）の数
    static var soonCount: Int { all.count - available.count }
}

// MARK: - 投稿から数える（室内だけの値）

enum CamperRoomCounting {

    /// 自分の写真から数える（下書きは数えない・`CamperCounting.count` と同じ）
    static func count(_ photos: [Photo]) -> CamperRoomStats {
        stats(photos.filter { $0.published != false })
    }

    static func stats(_ photos: [Photo]) -> CamperRoomStats {
        var r = CamperRoomStats()
        var days: [String: Int] = [:]
        for p in photos {
            // 地名を外した文（「国分寺市」の寺・「星ヶ丘」の星に当たらない）。市場と料理は「〜市場」「朝市」が市の名前として
            // 外されるので、外す前の文で読む
            let words = CamperCounting.natureText(of: p)
            let raw = ([p.location ?? "", p.displayTitle, p.category ?? ""] + (p.tags ?? [])).joined(separator: " ").lowercased()
            for t in CamperRoomTopic.allCases {
                let text = t == .market || t == .food ? raw : words
                guard t.words.contains(where: { text.contains($0.lowercased()) }) else { continue }
                r.topics[t, default: 0] += 1
            }
            if let t = CamperCounting.shotTime(p.exif?.dateTimeOriginal ?? p.date) {
                if (3...5).contains(t.month) { r.springShots += 1 }
                days[t.day, default: 0] += 1
            }
        }
        r.sameDayMax = days.values.max() ?? 0
        return r
    }
}
