import Foundation

// 旅のトランクの部品（カプセルの機械から出る・9 種類 108 点・モック Parts.dc.html・2026-10-17 owner 承認）。
//
// **id は `<kind>.<1〜12>`**。番号はモックの各行の並び順（1 始まり）で、サーバーの
// `api-user/src/data/trunkParts.json` も同じ並びで作る（名前・段もここと同じ）。
// 見た目の値（色・形・模様）は Parts.dc.html の各行の値をそのまま写す。描き方は `TrunkPartDrawing`。
//
// SwiftUI を読まない層（Linux でテストできるように）。

// MARK: - 種類と段

/// 部品の種類（モックの行の順）
enum TrunkPartKind: String, CaseIterable, Identifiable {
    case handle, corner, lock, lining, tag, pin, patch, charm, key

    var id: String { rawValue }

    /// 部品箱・付け替えのタブの短い名前（モック PartsBox・Equip）
    var tabName: String {
        switch self {
        case .handle: return L("持ち手", "Handles")
        case .corner: return L("角金具", "Corners")
        case .lock: return L("錠前", "Locks")
        case .lining: return L("内張り", "Linings")
        case .tag: return L("タグ", "Tags")
        case .pin: return L("ピン", "Pins")
        case .patch: return L("ワッペン", "Patches")
        case .charm: return L("チャーム", "Charms")
        case .key: return L("鍵", "Keys")
        }
    }

    /// 中身と確率・開けた画面の名前（モック GachaOdds の行）
    var title: String {
        switch self {
        case .handle: return L("持ち手", "Handle")
        case .corner: return L("角金具", "Corner fitting")
        case .lock: return L("錠前", "Lock")
        case .lining: return L("内張りの布", "Lining cloth")
        case .tag: return L("手荷物タグ", "Luggage tag")
        case .pin: return L("ピンバッジ", "Pin badge")
        case .patch: return L("刺繍のワッペン", "Embroidered patch")
        case .charm: return L("チャーム", "Charm")
        case .key: return L("ホテルの鍵", "Hotel key")
        }
    }

    /// 中身と確率の行の例（モック GachaOdds の `ex`）
    var examples: String {
        switch self {
        case .handle: return L("革の持ち手・籐の持ち手・真鍮の輪", "Leather, rattan, brass ring")
        case .corner: return L("打ち出しの角・鋲の角・彫りの角", "Hammered, riveted, engraved")
        case .lock: return L("菊・羅針盤・船の舵・寝台列車", "Chrysanthemum, compass, helm, sleeper")
        case .lining: return L("縞の綿・絹の更紗・紺の天鵞絨", "Striped cotton, silk chintz, navy velvet")
        case .tag: return L("空の便・船旅・夜行列車の札", "Flights, voyages, night trains")
        case .pin: return L("鳥居・富士・汽船・羅針盤", "Torii, Fuji, steamer, compass")
        case .patch: return L("京都・北海道・登山・世界一周", "Kyoto, Hokkaido, summit, world")
        case .charm: return L("灯台・ゴンドラ・紅葉・金の星", "Lighthouse, gondola, maple, gold star")
        case .key: return L("真鍮の涙・寝台車・船室・金の鍵", "Brass teardrop, sleeper, cabin, gold")
        }
    }

    /// 付けられる数（ピンバッジ 3・ワッペン 2・ほかは 1。サーバーの `PINS_MAX`・`PATCHES_MAX`）
    var capacity: Int {
        switch self {
        case .pin: return 3
        case .patch: return 2
        default: return 1
        }
    }

    /// 1つの種類の点数
    static let perKind = 12
}

/// 部品の段（サーバーの `rarityWeights` 70 / 25 / 5）
enum TrunkPartRarity: Int, CaseIterable, Comparable {
    case common = 0, rare = 1, veryRare = 2

    var name: String {
        switch self {
        case .common: return L("ふつう", "Common")
        case .rare: return L("めずらしい", "Rare")
        case .veryRare: return L("とてもめずらしい", "Very rare")
        }
    }

    /// 段の出る確率（％）。**画面に必ず出す**（中身と確率）
    var percent: Int {
        switch self {
        case .common: return 70
        case .rare: return 25
        case .veryRare: return 5
        }
    }

    static func < (l: TrunkPartRarity, r: TrunkPartRarity) -> Bool { l.rawValue < r.rawValue }
}

// MARK: - 金属

/// 金属（モック Part の `M`・`metMid`・`metDark`）
enum TrunkPartMetal: String, CaseIterable {
    case brass, silver, copper, iron, gold, chrome, bronze, darkbrass

    /// 明るい・中・暗い（`linear-gradient(135deg, a 0%, b 45%, c 100%)`）
    var tones: (light: TrunkRGBA, mid: TrunkRGBA, dark: TrunkRGBA) {
        switch self {
        case .brass: return (TrunkRGBA(0xF2DFAE), TrunkRGBA(0xC9A66B), TrunkRGBA(0x8A6B39))
        case .silver: return (TrunkRGBA(0xFFFFFF), TrunkRGBA(0xC9CED3), TrunkRGBA(0x7E868E))
        case .copper: return (TrunkRGBA(0xF6C9A8), TrunkRGBA(0xB8734A), TrunkRGBA(0x6E3A20))
        case .iron: return (TrunkRGBA(0x77777C), TrunkRGBA(0x33333A), TrunkRGBA(0x121214))
        case .gold: return (TrunkRGBA(0xFFF1C4), TrunkRGBA(0xE3BF5E), TrunkRGBA(0x8A6420))
        case .chrome: return (TrunkRGBA(0xFFFFFF), TrunkRGBA(0xD9DDE1), TrunkRGBA(0x8A9198))
        case .bronze: return (TrunkRGBA(0xCFE2D2), TrunkRGBA(0x7FA48C), TrunkRGBA(0x3E5A48))
        case .darkbrass: return (TrunkRGBA(0xD8C08A), TrunkRGBA(0x9C8150), TrunkRGBA(0x55442A))
        }
    }

    /// 絵の塗りの色（`metMid`）
    var midTone: TrunkRGBA {
        switch self {
        case .brass: return TrunkRGBA(0xC9A66B)
        case .silver: return TrunkRGBA(0xC9CED3)
        case .gold: return TrunkRGBA(0xE3BF5E)
        case .copper: return TrunkRGBA(0xB8734A)
        case .iron: return TrunkRGBA(0x3A3A40)
        case .bronze: return TrunkRGBA(0x7FA48C)
        case .chrome: return TrunkRGBA(0xD9DDE1)
        case .darkbrass: return TrunkRGBA(0x9C8150)
        }
    }

    /// 絵の縁の色（`metDark`）
    var darkTone: TrunkRGBA {
        switch self {
        case .brass: return TrunkRGBA(0x6E5630)
        case .silver: return TrunkRGBA(0x5E666E)
        case .gold: return TrunkRGBA(0x7E5A18)
        case .copper: return TrunkRGBA(0x5A2E18)
        case .iron: return TrunkRGBA(0x0E0E10)
        case .bronze: return TrunkRGBA(0x2E4A38)
        case .chrome: return TrunkRGBA(0x6E767E)
        case .darkbrass: return TrunkRGBA(0x3E3220)
        }
    }

    /// 彫りの線の色（モックの `ink`）
    var ink: TrunkRGBA {
        switch self {
        case .iron: return TrunkRGBA(r: 230, g: 230, b: 235, a: 0.75)
        case .bronze: return TrunkRGBA(r: 30, g: 50, b: 40, a: 0.75)
        default: return TrunkRGBA(r: 60, g: 40, b: 15, a: 0.72)
        }
    }

    /// 金属の名前（開けた画面の見出し「真鍮の錠前「菊」」）
    var name: String {
        switch self {
        case .brass: return L("真鍮", "Brass")
        case .silver: return L("銀", "Silver")
        case .copper: return L("銅", "Copper")
        case .iron: return L("黒鉄", "Iron")
        case .gold: return L("金", "Gold")
        case .chrome: return L("クローム", "Chrome")
        case .bronze: return L("青銅", "Bronze")
        case .darkbrass: return L("古い真鍮", "Old brass")
        }
    }

    /// `met(k)`（135° の 0%・45%・100%）
    var gradient: TrunkGradient {
        let t = tones
        return TrunkGradient(angle: 135, stops: [TrunkStop(color: t.light, location: 0),
                                                 TrunkStop(color: t.mid, location: 0.45),
                                                 TrunkStop(color: t.dark, location: 1)])
    }
}

// MARK: - 塗り（CSS の background を、描ける形にしたもの）

/// 縞の1本（1周期の中の始まり・終わり・色。CSS の `repeating-linear-gradient`）
struct TrunkPartBand: Equatable {
    let from: Double
    let to: Double
    let color: TrunkRGBA
}

/// 点の並び（CSS の `radial-gradient(color r1, transparent r2) ox oy / tile tile`）。
/// 点の中心は升の左上から (`cx`, `cy`)（px）。`inner` までは色・`outer` で透ける
struct TrunkPartDots: Equatable {
    let color: TrunkRGBA
    let tile: Double
    let cx: Double
    let cy: Double
    let inner: Double
    let outer: Double

    init(color: TrunkRGBA, tile: Double, center: Double, inner: Double, outer: Double) {
        self.init(color: color, tile: tile, cx: center, cy: center, inner: inner, outer: outer)
    }

    init(color: TrunkRGBA, tile: Double, cx: Double, cy: Double, inner: Double, outer: Double) {
        self.color = color
        self.tile = tile
        self.cx = cx
        self.cy = cy
        self.inner = inner
        self.outer = outer
    }
}

/// 楕円の光・しみ（CSS の `radial-gradient(rx ry at cx cy, a, b stop)`。中心と半径は面に対する割合）
struct TrunkPartGlow: Equatable {
    let stops: [TrunkStop]
    let cx: Double
    let cy: Double
    let rx: Double
    let ry: Double
    /// 半径を「いちばん遠い角までの長さ」の割合で数える（CSS の `circle at …` の既定）
    let farthestCorner: Bool
}

/// 塗り。`layers` は CSS と同じく**先頭がいちばん上**
indirect enum TrunkPartPaint: Equatable {
    case solid(TrunkRGBA)
    case metal(TrunkPartMetal)
    case linear(TrunkGradient)
    case glow(TrunkPartGlow)
    case stripes(angle: Double, period: Double, bands: [TrunkPartBand])
    case dots(TrunkPartDots)
    /// 輪の繰り返し（`repeating-radial-gradient(circle at cx cy, transparent 0 from, color from to)`）
    case rings(cx: Double, cy: Double, period: Double, from: Double, color: TrunkRGBA)
    /// 市松（`repeating-conic-gradient(a 0 25%, b 0 50%) 0 0 / tile tile`）
    case checker(a: TrunkRGBA, b: TrunkRGBA, tile: Double)
    /// 青海波（26×13 の升の下の真ん中を中心に、2重の弧）
    case seigaiha(base: TrunkRGBA, line: TrunkRGBA)
    case layers([TrunkPartPaint])

    /// 塗りの代表の色（3D の箱の持ち手・読み上げに使わない・色の近さのテスト）。いちばん下の層の色
    var baseColor: TrunkRGBA {
        switch self {
        case .solid(let c): return c
        case .metal(let m): return m.tones.mid
        case .linear(let g): return g.stops.first?.color ?? TrunkRGBA(0x000000)
        case .glow(let g): return g.stops.last?.color ?? TrunkRGBA(0x000000)
        case .stripes(_, _, let bands): return bands.first?.color ?? TrunkRGBA(0x000000)
        case .dots(let d): return d.color
        case .rings(_, _, _, _, let c): return c
        case .checker(let a, _, _): return a
        case .seigaiha(let base, _): return base
        case .layers(let list): return list.last?.baseColor ?? TrunkRGBA(0x000000)
        }
    }
}

// MARK: - 種類ごとの見た目（モック Part の `spec`）

/// 錠前の形
enum TrunkPartLockShape: String, CaseIterable { case plate, round, padlock, dial, twin }
/// 錠前の彫り
enum TrunkLockEmblem: String, CaseIterable { case kiku, compass, helm, train, sakura, wave, star, shell }
/// 手荷物タグの札の形
enum TrunkTagShape: String, CaseIterable { case paper, ticket, leather, wood, brass }
/// ピンバッジの形
enum TrunkPinShape: String, CaseIterable { case circle, shield, square, banner }
/// ワッペンの形
enum TrunkPatchShape: String, CaseIterable { case circle, oval, rect, shield }
/// 鍵の札の形
enum TrunkKeyFob: String, CaseIterable { case tear, diamond, oval, rect }
/// 角金具の彫り
enum TrunkCornerEngrave: String, CaseIterable { case none, hammer, karakusa, lines }

/// 絵（モック Part の `SH`・ピン・ワッペン・チャームが使う）
enum TrunkPartIcon: String, CaseIterable {
    case torii, lighthouse, sakura, star, fuji, plane, ship, gondola, shell, compass, heart, train, maple, mountain, wave, globe

    /// SVG の `d`（viewBox -20 -20 40 40）
    var d: String {
        switch self {
        case .torii: return "M-16 -12 C-6 -9 6 -9 16 -12 L15 -7 C6 -5 -6 -5 -15 -7 Z M-12 -3 H12 V0 H-12 Z M-9 -6 H-5 V16 H-9 Z M5 -6 H9 V16 H5 Z"
        case .lighthouse: return "M-5 -10 H5 L7 16 H-7 Z M-4 -16 H4 V-10 H-4 Z M-2 -19 H2 V-16 H-2 Z"
        case .sakura: return "M0 -16 C6 -12 6 -6 0 -2 C-6 -6 -6 -12 0 -16 Z M15 -5 C14 2 8 4 2 -1 C5 -7 11 -9 15 -5 Z M9 13 C3 14 0 9 1 2 C7 2 11 7 9 13 Z M-9 13 C-11 7 -7 2 -1 2 C0 9 -3 14 -9 13 Z M-15 -5 C-11 -9 -5 -7 -2 -1 C-8 4 -14 2 -15 -5 Z"
        case .star: return "M0 -17 L5 -6 L17 -5 L8 3 L11 15 L0 9 L-11 15 L-8 3 L-17 -5 L-5 -6 Z"
        case .fuji: return "M-18 12 L-5 -8 L-2 -5 L1 -9 L4 -5 L18 12 Z"
        case .plane: return "M-17 1 L13 -1 C17 -1 17 2 13 2 L2 3 L-6 14 L-9 14 L-4 3 L-12 3 L-15 7 L-17 7 L-15 2 Z M-1 -1 L-8 -12 L-5 -12 L5 -1 Z"
        case .ship: return "M-17 5 H17 L12 13 H-12 Z M-11 -1 H11 V5 H-11 Z M-6 -9 H-2 V-1 H-6 Z M2 -9 H6 V-1 H2 Z"
        case .gondola: return "M-18 4 C-10 10 10 10 18 0 L17 -2 C10 5 -10 5 -16 1 Z M14 -3 L19 -12 L20 -11 L16 -2 Z M-4 -2 H4 V3 H-4 Z"
        case .shell: return "M-15 6 A15 15 0 0 1 15 6 L0 14 Z"
        case .compass: return "M0 -17 L4 -4 L0 0 L-4 -4 Z M0 17 L4 4 L0 0 L-4 4 Z M-17 0 L-4 -4 L0 0 L-4 4 Z M17 0 L4 -4 L0 0 L4 4 Z"
        case .heart: return "M0 14 C-18 2 -14 -14 0 -6 C14 -14 18 2 0 14 Z"
        case .train: return "M-16 8 V-2 H-4 V-9 H4 V-2 H11 L16 3 V8 Z M-10 12 a3 3 0 1 0 0.1 0 Z M2 12 a3 3 0 1 0 0.1 0 Z"
        case .maple: return "M0 -17 L4 -7 L13 -11 L9 -2 L17 0 L9 5 L12 13 L2 9 L1 17 L-1 17 L-2 9 L-12 13 L-9 5 L-17 0 L-9 -2 L-13 -11 L-4 -7 Z"
        case .mountain: return "M-17 12 L-7 -4 L-2 3 L5 -10 L17 12 Z"
        case .wave: return "M-17 8 C-12 -4 -2 -8 6 -4 C0 -2 0 4 6 5 C10 -2 14 -4 17 -2 L17 12 L-17 12 Z"
        case .globe: return "M0 -15 A15 15 0 1 0 0.1 -15 Z M-15 0 H15 M0 -15 C-7 -8 -7 8 0 15 C7 8 7 -8 0 -15"
        }
    }
}

/// 1点の見た目（モック Parts の各行の `spec`。省いた値はモックの既定）
enum TrunkPartLook: Equatable {
    struct Handle: Equatable {
        /// 持ち手の面（`fill || met(metal)`）
        let paint: TrunkPartPaint
        /// 太さ（モックの `w ?? 12`）
        let width: Double
        let stitch: Bool
        /// 付け根の金具（`clip || 'brass'`）
        let clip: TrunkPartMetal
    }
    struct Corner: Equatable {
        /// 角の面（`fill || met(metal)`）
        let paint: TrunkPartPaint
        let engrave: TrunkCornerEngrave
        let rivets: Bool
        /// 透かし（丸い穴）
        let pierce: Bool
        /// 鋲の暗い色の金属（`M[metal] || M.brass`）
        let rivetMetal: TrunkPartMetal
    }
    struct Lock: Equatable {
        let metal: TrunkPartMetal
        let shape: TrunkPartLockShape
        let emblem: TrunkLockEmblem?
    }
    struct Tag: Equatable {
        let shape: TrunkTagShape
        /// 札の面（真鍮の名札は `met('brass')`）
        let paint: TrunkPartPaint
        let fg: TrunkRGBA
        let t1: String
        let t2: String
        /// 紐の色（無ければ #2A2A2A）
        let string: TrunkRGBA
    }
    struct Pin: Equatable {
        let metal: TrunkPartMetal
        let enamel: TrunkRGBA
        let icon: TrunkPartIcon
        /// 絵の色（`ink || metMid[metal]`）
        let ink: TrunkRGBA
        let shape: TrunkPinShape
    }
    struct Patch: Equatable {
        let shape: TrunkPatchShape
        let bg: TrunkRGBA
        let border: TrunkRGBA
        let thread: TrunkRGBA
        let icon: TrunkPartIcon
        let text: String
    }
    struct Charm: Equatable {
        let metal: TrunkPartMetal
        let icon: TrunkPartIcon
        /// 塗り（`fill || metMid[metal]`）
        let fill: TrunkRGBA
        let rot: Double
        let ringMetal: TrunkPartMetal
    }
    struct Key: Equatable {
        let metal: TrunkPartMetal
        let fob: TrunkKeyFob
        /// 札の面（`fobBg || met(metal)`）
        let fobPaint: TrunkPartPaint
        let ink: TrunkRGBA
        let t1: String
        let no: String
    }

    case handle(Handle)
    case corner(Corner)
    case lock(Lock)
    case lining(TrunkPartPaint)
    case tag(Tag)
    case pin(Pin)
    case patch(Patch)
    case charm(Charm)
    case key(Key)

    var kind: TrunkPartKind {
        switch self {
        case .handle: return .handle
        case .corner: return .corner
        case .lock: return .lock
        case .lining: return .lining
        case .tag: return .tag
        case .pin: return .pin
        case .patch: return .patch
        case .charm: return .charm
        case .key: return .key
        }
    }

    /// 主な金属（開けた画面の見出しに添える。金属でない部品は nil）
    var metal: TrunkPartMetal? {
        switch self {
        case .handle(let h): if case .metal(let m) = h.paint { return m } else { return nil }
        case .corner(let c): if case .metal(let m) = c.paint { return m } else { return nil }
        case .lock(let l): return l.metal
        case .pin(let p): return p.metal
        case .charm(let c): return c.metal
        case .key(let k): return k.metal
        case .lining, .tag, .patch: return nil
        }
    }
}

/// 部品1点
struct TrunkPart: Equatable, Identifiable, Hashable {
    /// `<kind>.<1〜12>`
    let id: String
    let kind: TrunkPartKind
    /// 種類の中の番号（1〜12・モックの並び順）
    let number: Int
    /// 名前（日本語。モックの名前のまま）
    let name: String
    let rarity: TrunkPartRarity
    let look: TrunkPartLook

    static func == (l: TrunkPart, r: TrunkPart) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 台帳

enum TrunkPartCatalog {

    /// 108 点（種類の順・種類の中は番号の順）
    static let all: [TrunkPart] = TrunkPartKind.allCases.flatMap(parts(of:))

    private static let byId: [String: TrunkPart] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// id から（知らない id は nil）
    static func part(_ id: String) -> TrunkPart? { byId[id] }

    /// 種類の 12 点
    static func parts(of kind: TrunkPartKind) -> [TrunkPart] {
        rows(kind).enumerated().map { i, row in
            TrunkPart(id: "\(kind.rawValue).\(i + 1)", kind: kind, number: i + 1, name: row.name,
                      rarity: TrunkPartRarity(rawValue: row.rarity) ?? .common, look: row.look)
        }
    }

    /// 段の中の点数（中身と確率の「1点あたり」に使う）
    static func count(_ rarity: TrunkPartRarity) -> Int { all.filter { $0.rarity == rarity }.count }

    // MARK: 塗りの道具（モック Parts の `leather`・`rope`）

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> TrunkRGBA {
        TrunkRGBA(r: r, g: g, b: b, a: a)
    }

    private static func linear(_ angle: Double, _ stops: [(UInt32, Double)]) -> TrunkPartPaint {
        .linear(TrunkGradient(angle: angle, stops: stops.map { TrunkStop(color: TrunkRGBA($0.0), location: $0.1) }))
    }

    /// `radial-gradient(rgba(0,0,0,0.2) 0.7px, transparent 1.3px) 0 0/4px 4px, linear-gradient(135deg, a, b)`
    private static func leather(_ a: UInt32, _ b: UInt32) -> TrunkPartPaint {
        .layers([.dots(TrunkPartDots(color: rgba(0, 0, 0, 0.2), tile: 4, center: 2, inner: 0.7, outer: 1.3)),
                 linear(135, [(a, 0), (b, 1)])])
    }

    /// `repeating-linear-gradient(60deg, a 0 3px, b 3px 4.5px, a 4.5px 7px)`
    private static func rope(_ a: UInt32, _ b: UInt32) -> TrunkPartPaint {
        .stripes(angle: 60, period: 7, bands: [TrunkPartBand(from: 0, to: 3, color: TrunkRGBA(a)),
                                               TrunkPartBand(from: 3, to: 4.5, color: TrunkRGBA(b)),
                                               TrunkPartBand(from: 4.5, to: 7, color: TrunkRGBA(a))])
    }

    private static func stripes(_ angle: Double, _ period: Double, _ bands: [(Double, Double, UInt32)]) -> TrunkPartPaint {
        .stripes(angle: angle, period: period, bands: bands.map { TrunkPartBand(from: $0.0, to: $0.1, color: TrunkRGBA($0.2)) })
    }

    /// 木目（`repeating-linear-gradient(90deg, #A8743E 0 3px, #8E5A2C 3px 7px)`）
    private static let wood = stripes(90, 7, [(0, 3, 0xA8743E), (3, 7, 0x8E5A2C)])
    /// 飴色の樹脂（`linear-gradient(135deg, #F2B866, #A8561E 60%, #5A2A0C)`）
    private static let amber = linear(135, [(0xF2B866, 0), (0xA8561E, 0.6), (0x5A2A0C, 1)])

    private struct Row {
        let name: String
        let rarity: Int
        let look: TrunkPartLook
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func rows(_ kind: TrunkPartKind) -> [Row] {
        switch kind {
        case .handle:
            func h(_ name: String, _ r: Int, _ paint: TrunkPartPaint, w: Double = 12, stitch: Bool = false,
                   clip: TrunkPartMetal = .brass) -> Row {
                Row(name: name, rarity: r, look: .handle(.init(paint: paint, width: w, stitch: stitch, clip: clip)))
            }
            return [
                h("茶の革", 0, leather(0x8A5530, 0x4A2814), stitch: true),
                h("黒の革", 0, leather(0x3A3A3E, 0x111114), stitch: true),
                h("赤の革", 1, leather(0x8A2A22, 0x4A100C), stitch: true),
                h("鹿革", 0, leather(0xD9C7A4, 0xA88E62), stitch: true),
                h("籐巻き", 1, stripes(90, 4, [(0, 3, 0xD8BC86), (3, 4, 0xA8875A)]), w: 13),
                h("麻縄", 0, rope(0xE2D2A8, 0xA8955F), w: 10, clip: .iron),
                h("赤の組紐", 1, rope(0xC8352A, 0x6E140F), w: 9, clip: .gold),
                h("真鍮の輪", 0, .metal(.brass), w: 7),
                h("銀の輪", 1, .metal(.silver), w: 7, clip: .silver),
                h("飴色の樹脂", 1, amber, w: 14),
                h("黒檀の握り", 2, stripes(80, 6, [(0, 3, 0x2A1A12), (3, 6, 0x120A06)]), w: 15, clip: .gold),
                h("金の鎖", 2, stripes(90, 8, [(0, 3, 0xFFF1C4), (3, 4, 0x8A6420), (4, 7, 0xE3BF5E), (7, 8, 0x5A4010)]),
                  w: 8, clip: .gold),
            ]
        case .corner:
            func c(_ name: String, _ r: Int, _ metal: TrunkPartMetal?, engrave: TrunkCornerEngrave = .none,
                   rivets: Bool = false, pierce: Bool = false, fill: TrunkPartPaint? = nil) -> Row {
                Row(name: name, rarity: r, look: .corner(.init(paint: fill ?? .metal(metal ?? .brass), engrave: engrave,
                                                               rivets: rivets, pierce: pierce, rivetMetal: metal ?? .brass)))
            }
            return [
                c("打ち出しの真鍮", 0, .brass, engrave: .hammer, rivets: true),
                c("鋲の真鍮", 0, .brass, rivets: true),
                c("唐草の彫り", 1, .brass, engrave: .karakusa, rivets: true),
                c("銀", 0, .silver, rivets: true),
                c("銅", 0, .copper, rivets: true),
                c("黒鉄", 0, .iron, rivets: true),
                c("斜めの線彫り", 1, .darkbrass, engrave: .lines, rivets: true),
                c("クローム", 1, .chrome),
                c("厚革", 0, nil, rivets: true, fill: leather(0x6B3E1E, 0x2E1808)),
                c("透かしの真鍮", 1, .brass, pierce: true),
                c("緑青の青銅", 2, .bronze, engrave: .hammer, rivets: true),
                c("金の唐草", 2, .gold, engrave: .karakusa, rivets: true),
            ]
        case .lock:
            func l(_ name: String, _ r: Int, _ metal: TrunkPartMetal, _ shape: TrunkPartLockShape,
                   _ emblem: TrunkLockEmblem? = nil) -> Row {
                Row(name: name, rarity: r, look: .lock(.init(metal: metal, shape: shape, emblem: emblem)))
            }
            return [
                l("無地の錠前", 0, .brass, .plate),
                l("菊", 1, .brass, .plate, .kiku),
                l("桜", 1, .silver, .round, .sakura),
                l("青海波", 0, .brass, .plate, .wave),
                l("羅針盤", 1, .darkbrass, .round, .compass),
                l("船の舵", 1, .brass, .round, .helm),
                l("寝台列車", 1, .iron, .plate, .train),
                l("貝", 0, .copper, .round, .shell),
                l("南京錠", 0, .brass, .padlock),
                l("ダイヤル錠", 1, .chrome, .dial),
                l("双子の留め金", 0, .silver, .twin),
                l("金の星", 2, .gold, .round, .star),
            ]
        case .lining:
            func f(_ name: String, _ r: Int, _ paint: TrunkPartPaint) -> Row {
                Row(name: name, rarity: r, look: .lining(paint))
            }
            let plaidLine = rgba(140, 47, 43, 0.5)
            let mapLine = rgba(120, 90, 50, 0.25)
            let gold = rgba(255, 241, 196, 0.6)
            return [
                f("縞の綿", 0, stripes(90, 15, [(0, 6, 0xEFE6D2), (6, 8, 0x2F4A6E), (8, 14, 0xEFE6D2), (14, 15, 0xB8463A)])),
                f("格子の綿", 0, .layers([.stripes(angle: 0, period: 14, bands: [TrunkPartBand(from: 0, to: 4, color: plaidLine)]),
                                          .stripes(angle: 90, period: 14, bands: [TrunkPartBand(from: 0, to: 4, color: plaidLine)]),
                                          .solid(TrunkRGBA(0xEDE4D0))])),
                f("千鳥格子", 0, .checker(a: TrunkRGBA(0x1A1A1A), b: TrunkRGBA(0xE9E2D2), tile: 10)),
                f("麻", 0, .layers([.stripes(angle: 0, period: 3, bands: [TrunkPartBand(from: 0, to: 1, color: rgba(0, 0, 0, 0.06))]),
                                    .stripes(angle: 90, period: 3, bands: [TrunkPartBand(from: 0, to: 1, color: rgba(255, 255, 255, 0.08))]),
                                    .solid(TrunkRGBA(0xC9B48A))])),
                f("市松", 0, .checker(a: TrunkRGBA(0x2E5D50), b: TrunkRGBA(0xE9E2D2), tile: 18)),
                f("青海波", 1, .seigaiha(base: TrunkRGBA(0x1F3A5A), line: TrunkRGBA(0xF2E6CC))),
                f("紺の天鵞絨", 1, .glow(TrunkPartGlow(stops: [TrunkStop(color: TrunkRGBA(0x2C3E6E), location: 0),
                                                              TrunkStop(color: TrunkRGBA(0x0E1630), location: 0.8)],
                                                      cx: 0.3, cy: 0.2, rx: 1.2, ry: 0.9, farthestCorner: false))),
                f("赤の天鵞絨", 1, .glow(TrunkPartGlow(stops: [TrunkStop(color: TrunkRGBA(0x8E2230), location: 0),
                                                              TrunkStop(color: TrunkRGBA(0x3A0810), location: 0.8)],
                                                      cx: 0.3, cy: 0.2, rx: 1.2, ry: 0.9, farthestCorner: false))),
                f("地図の柄", 1, .layers([
                    .stripes(angle: 90, period: 16, bands: [TrunkPartBand(from: 0, to: 1, color: mapLine)]),
                    .stripes(angle: 0, period: 16, bands: [TrunkPartBand(from: 0, to: 1, color: mapLine)]),
                    .glow(TrunkPartGlow(stops: [TrunkStop(color: TrunkRGBA(0xC8B88A), location: 0),
                                                TrunkStop(color: TrunkRGBA(0xC8B88A).alpha(0), location: 1)],
                                        cx: 0.3, cy: 0.4, rx: 0.4, ry: 0.3, farthestCorner: false)),
                    .glow(TrunkPartGlow(stops: [TrunkStop(color: TrunkRGBA(0xC8B88A), location: 0),
                                                TrunkStop(color: TrunkRGBA(0xC8B88A).alpha(0), location: 1)],
                                        cx: 0.7, cy: 0.65, rx: 0.3, ry: 0.25, farthestCorner: false)),
                    .solid(TrunkRGBA(0xE8DDC2)),
                ])),
                f("星の柄", 1, .layers([
                    .dots(TrunkPartDots(color: TrunkRGBA(0xE3C98F), tile: 12, center: 6, inner: 1, outer: 1.6)),
                    .dots(TrunkPartDots(color: TrunkRGBA(0xE3C98F), tile: 12, center: 12, inner: 0.8, outer: 1.3)),
                    .solid(TrunkRGBA(0x101A34)),
                ])),
                f("絹の更紗", 2, .layers([
                    .dots(TrunkPartDots(color: TrunkRGBA(0xC8352A), tile: 22, center: 22 * 0.25, inner: 4, outer: 4.5)),
                    .dots(TrunkPartDots(color: TrunkRGBA(0x2E5D50), tile: 22, center: 22 * 0.75, inner: 3, outer: 3.5)),
                    .dots(TrunkPartDots(color: TrunkRGBA(0xE3B23C), tile: 22, cx: 22 * 0.75, cy: 22 * 0.25, inner: 2, outer: 2.5)),
                    .solid(TrunkRGBA(0xF2E6CC)),
                ])),
                f("金襴", 2, .layers([
                    .stripes(angle: 45, period: 8, bands: [TrunkPartBand(from: 0, to: 2, color: gold)]),
                    .stripes(angle: -45, period: 8, bands: [TrunkPartBand(from: 0, to: 2, color: gold)]),
                    linear(135, [(0x5A1A1A, 0), (0x2A0808, 1)]),
                ])),
            ]
        case .tag:
            func t(_ name: String, _ r: Int, _ shape: TrunkTagShape, _ bg: TrunkPartPaint, _ fg: UInt32, _ t1: String,
                   _ t2: String, string: UInt32 = 0x2A2A2A) -> Row {
                Row(name: name, rarity: r, look: .tag(.init(shape: shape, paint: bg, fg: TrunkRGBA(fg), t1: t1, t2: t2,
                                                            string: TrunkRGBA(string))))
            }
            return [
                t("空の便", 0, .paper, .solid(TrunkRGBA(0xEFE6D2)), 0x1E2A44, "HND→HEL", "空の便"),
                t("船旅", 0, .paper, .solid(TrunkRGBA(0xC7D8E2)), 0x13303F, "SEA ROUTE", "船旅"),
                t("夜行列車", 1, .paper, .solid(TrunkRGBA(0x2A1414)), 0xE7C77A, "NIGHT TRAIN", "夜行"),
                t("一等船室", 1, .ticket, .solid(TrunkRGBA(0xF2E6CC)), 0x8C2F2B, "FIRST CLASS", "一等"),
                t("ホテルの札", 0, .paper, .solid(TrunkRGBA(0xF1C9A0)), 0x3A1E10, "HOTEL", "宿"),
                t("手小荷物", 0, .paper, .solid(TrunkRGBA(0xE8D8B0)), 0x3A2412, "RAILWAY", "手荷物"),
                t("航空便", 0, .ticket, .solid(TrunkRGBA(0xF4F1EA)), 0x1F4E8C, "PAR AVION", "航空便"),
                t("こわれもの", 0, .paper, .solid(TrunkRGBA(0xC8352A)), 0xF4F1EA, "FRAGILE", "取扱注意"),
                t("和紙の荷札", 1, .paper, .solid(TrunkRGBA(0xF2EDE0)), 0x2B2B2B, "NIFUDA", "荷札", string: 0xB3261E),
                t("革の名札", 1, .leather, linear(135, [(0x7A4A26, 0), (0x3E2010, 1)]), 0xE3C98F, "NAME", "持ち主", string: 0x3E2010),
                t("木の名札", 1, .wood, wood, 0x2B1A0C, "NAME", "持ち主", string: 0x5A3418),
                t("真鍮の名札", 2, .brass, .metal(.brass), 0x3A2A12, "No. ___", "持ち主", string: 0x8A6B39),
            ]
        case .pin:
            func p(_ name: String, _ r: Int, _ metal: TrunkPartMetal, _ enamel: UInt32, _ icon: TrunkPartIcon,
                   _ ink: UInt32, _ shape: TrunkPinShape = .circle) -> Row {
                Row(name: name, rarity: r, look: .pin(.init(metal: metal, enamel: TrunkRGBA(enamel), icon: icon,
                                                            ink: TrunkRGBA(ink), shape: shape)))
            }
            return [
                p("鳥居", 0, .gold, 0xB3261E, .torii, 0xF2E6CC),
                p("富士", 0, .silver, 0x1F4E8C, .fuji, 0xF4F1EA),
                p("桜", 1, .gold, 0xF2C6CF, .sakura, 0xC8355A),
                p("灯台", 0, .brass, 0x2E5D50, .lighthouse, 0xF2E6CC, .shield),
                p("紅葉", 0, .gold, 0x3A1E10, .maple, 0xE06A2A),
                p("飛行機", 0, .silver, 0xEAF2F8, .plane, 0x1F4E8C, .square),
                p("汽船", 1, .brass, 0x1A2A44, .ship, 0xE7C77A, .square),
                p("ゴンドラ", 1, .gold, 0x2C4A5E, .gondola, 0xF2E6CC, .banner),
                p("波", 0, .silver, 0x0E3A5A, .wave, 0x9CC3E6),
                p("羅針盤", 1, .darkbrass, 0xF2E6CC, .compass, 0x8C2F2B, .shield),
                p("夜行列車", 1, .gold, 0x14233A, .train, 0xE7C77A, .square),
                p("金の星", 2, .gold, 0x0E1630, .star, 0xFFF1C4),
            ]
        case .patch:
            func w(_ name: String, _ r: Int, _ shape: TrunkPatchShape, _ bg: UInt32, _ border: UInt32, _ thread: UInt32,
                   _ icon: TrunkPartIcon, _ text: String) -> Row {
                Row(name: name, rarity: r, look: .patch(.init(shape: shape, bg: TrunkRGBA(bg), border: TrunkRGBA(border),
                                                              thread: TrunkRGBA(thread), icon: icon, text: text)))
            }
            return [
                w("京都", 0, .circle, 0x8E2A22, 0xE7C77A, 0xF3E6CC, .torii, "KYOTO"),
                w("北海道", 0, .oval, 0x22405E, 0xF2EEE4, 0xF2EEE4, .mountain, "HOKKAIDO"),
                w("沖縄", 0, .rect, 0x0F6E7A, 0xF6F0E2, 0xF6F0E2, .wave, "OKINAWA"),
                w("富士山", 1, .shield, 0xBFD3D6, 0x1C3A44, 0x1C3A44, .fuji, "FUJI"),
                w("パリ", 0, .rect, 0xF2E6CC, 0x1F4E8C, 0x8C2F2B, .heart, "PARIS"),
                w("北欧", 1, .circle, 0x1E3A55, 0xE7B85A, 0xEFE3C8, .star, "NORDIC"),
                w("登山", 0, .shield, 0x2E5D50, 0xE2D2A8, 0xE2D2A8, .mountain, "SUMMIT"),
                w("船乗り", 0, .circle, 0xF4F1EA, 0x1A2A44, 0x1A2A44, .ship, "SAILOR"),
                w("桜の旅", 1, .oval, 0xF6D6DE, 0x8E2A40, 0x8E2A40, .sakura, "SAKURA"),
                w("空の旅", 0, .rect, 0xEAF2F8, 0xC8352A, 0x1F4E8C, .plane, "AIR"),
                w("世界一周", 1, .circle, 0x14233A, 0xC9A66B, 0xE7C77A, .globe, "WORLD"),
                w("金糸の紅葉", 2, .shield, 0x3A1010, 0xE3BF5E, 0xF2C766, .maple, "AUTUMN"),
            ]
        case .charm:
            func c(_ name: String, _ r: Int, _ metal: TrunkPartMetal, _ icon: TrunkPartIcon, fill: UInt32? = nil,
                   rot: Double = 0, ring: TrunkPartMetal = .silver) -> Row {
                Row(name: name, rarity: r, look: .charm(.init(metal: metal, icon: icon,
                                                              fill: fill.map { TrunkRGBA($0) } ?? metal.midTone,
                                                              rot: rot, ringMetal: ring)))
            }
            return [
                c("鳥居", 0, .brass, .torii, fill: 0xC8352A),
                c("灯台", 0, .silver, .lighthouse),
                c("ゴンドラ", 0, .brass, .gondola, rot: -8),
                c("桜", 1, .silver, .sakura, fill: 0xF2C6CF),
                c("飛行機", 0, .chrome, .plane, rot: -10),
                c("汽船", 0, .brass, .ship),
                c("貝", 0, .copper, .shell),
                c("羅針盤", 1, .darkbrass, .compass),
                c("紅葉", 1, .copper, .maple, fill: 0xC8572A),
                c("富士", 0, .silver, .fuji),
                c("ハート", 1, .gold, .heart, ring: .gold),
                c("金の星", 2, .gold, .star, ring: .gold),
            ]
        case .key:
            func k(_ name: String, _ r: Int, _ metal: TrunkPartMetal, _ fob: TrunkKeyFob, bg: TrunkPartPaint? = nil,
                   ink: UInt32 = 0x3A2A12, _ t1: String, _ no: String) -> Row {
                Row(name: name, rarity: r, look: .key(.init(metal: metal, fob: fob, fobPaint: bg ?? .metal(metal),
                                                            ink: TrunkRGBA(ink), t1: t1, no: no)))
            }
            return [
                k("真鍮の涙", 0, .brass, .tear, "HOTEL", "12"),
                k("真鍮のひし形", 0, .brass, .diamond, "HOTEL", "207"),
                k("銀の楕円", 0, .silver, .oval, ink: 0x2A3036, "HOTEL", "305"),
                k("赤い札", 0, .brass, .tear, bg: .solid(TrunkRGBA(0x8C2F2B)), ink: 0xF2E6CC, "GRAND", "418"),
                k("紺の札", 0, .silver, .rect, bg: .solid(TrunkRGBA(0x1A2A44)), ink: 0xE7C77A, "RYOKAN", "桐"),
                k("緑の札", 1, .brass, .diamond, bg: .solid(TrunkRGBA(0x2E5D50)), ink: 0xF2E6CC, "LODGE", "9"),
                k("木の札", 0, .iron, .rect, bg: wood, ink: 0x2B1A0C, "INN", "梅"),
                k("飴色の札", 1, .brass, .tear, bg: amber, ink: 0x2B1A0C, "HOTEL", "501"),
                k("銅の札", 0, .copper, .oval, ink: 0x3A1E10, "SPA", "7"),
                k("寝台車", 1, .darkbrass, .rect, bg: .solid(TrunkRGBA(0x2A1414)), ink: 0xE7C77A, "SLEEPER", "B6"),
                k("船室", 1, .silver, .diamond, bg: .solid(TrunkRGBA(0xF4F1EA)), ink: 0x1F4E8C, "CABIN", "23"),
                k("金の鍵", 2, .gold, .tear, "SUITE", "1"),
            ]
        }
    }
}
