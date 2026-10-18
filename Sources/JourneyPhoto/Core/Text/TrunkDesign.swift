import Foundation

// 旅のトランクの**描き方の数**（モック Trunk.dc.html・Aging・MaterialAging・2026-10-17）。
//
// SwiftUI を読まない層。色の混ぜ方・古び方・ラベルの置き場・型ごとの部品と色を、
// モックの JavaScript の計算と同じ式で持つ（Linux でテストできるように）。
// 画面（`Features/Trunk/TrunkBoxView.swift`）はここの値を読んで描くだけ。

// MARK: - 色

/// 色（0〜255 の RGB と、0〜1 の不透明度）
struct TrunkRGBA: Equatable, Hashable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `0xRRGGBB`
    init(_ hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF)
        g = Double((hex >> 8) & 0xFF)
        b = Double(hex & 0xFF)
        a = alpha
    }

    /// `#RRGGBB`（読めなければ nil）
    init?(css: String) {
        let raw = css.hasPrefix("#") ? String(css.dropFirst()) : css
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        self.init(value)
    }

    /// 同じ色で不透明度だけ替える
    func alpha(_ a: Double) -> TrunkRGBA { TrunkRGBA(r: r, g: g, b: b, a: a) }

    /// `#rrggbb`（不透明度は捨てる）
    var css: String {
        String(format: "#%02x%02x%02x", Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
    }

    /// **モックの `mix(a, b, t)` と同じ**: 各色を `Math.round(v + (b - v) * t)`（2桁の16進に丸める）
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> TrunkRGBA {
        let x = TrunkRGBA(a), y = TrunkRGBA(b)
        func ch(_ p: Double, _ q: Double) -> Double { jsRound(p + (q - p) * t) }
        return TrunkRGBA(r: ch(x.r, y.r), g: ch(x.g, y.g), b: ch(x.b, y.b))
    }

    /// JavaScript の `Math.round`（.5 は大きい方へ）
    static func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    /// **CSS の `filter: saturate(s) sepia(p) brightness(k)` を色にかける**（Filter Effects の行列）。
    /// ラベルの褪せ・手荷物タグの褪せを、描く前に色そのものへ畳む（SwiftUI に sepia が無いため・
    /// 2026-10-17 判断。地の上の白・黒の薄い重ねには掛からないが、差は小さい）
    func filtered(saturate s: Double = 1, sepia p: Double = 0, brightness k: Double = 1) -> TrunkRGBA {
        var (x, y, z) = (r, g, b)
        if s != 1 {
            let nx = (0.213 + 0.787 * s) * x + (0.715 - 0.715 * s) * y + (0.072 - 0.072 * s) * z
            let ny = (0.213 - 0.213 * s) * x + (0.715 + 0.285 * s) * y + (0.072 - 0.072 * s) * z
            let nz = (0.213 - 0.213 * s) * x + (0.715 - 0.715 * s) * y + (0.072 + 0.928 * s) * z
            (x, y, z) = (nx, ny, nz)
        }
        if p > 0 {
            let q = min(1, p)
            let nx = (0.393 + 0.607 * (1 - q)) * x + (0.769 - 0.769 * (1 - q)) * y + (0.189 - 0.189 * (1 - q)) * z
            let ny = (0.349 - 0.349 * (1 - q)) * x + (0.686 + 0.314 * (1 - q)) * y + (0.168 - 0.168 * (1 - q)) * z
            let nz = (0.272 - 0.272 * (1 - q)) * x + (0.534 - 0.534 * (1 - q)) * y + (0.131 + 0.869 * (1 - q)) * z
            (x, y, z) = (nx, ny, nz)
        }
        (x, y, z) = (x * k, y * k, z * k)
        func clamp(_ v: Double) -> Double { min(255, max(0, v)) }
        return TrunkRGBA(r: clamp(x), g: clamp(y), b: clamp(z), a: a)
    }
}

/// 色の並び（グラデーションの1点）
struct TrunkStop: Equatable {
    let color: TrunkRGBA
    let location: Double
}

/// CSS の `linear-gradient(<角度>deg, …)`
struct TrunkGradient: Equatable {
    let angle: Double
    let stops: [TrunkStop]

    /// 始まりと終わり（0〜1 の割合）。**CSS と同じく、角度の線が四隅を通る長さ**で決める
    /// （`w`・`h` は描く面の大きさ。正方形でなければ 45° と 135° でも隅から隅にはならない）
    static func endpoints(angle: Double, width w: Double, height h: Double)
        -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let rad = angle * .pi / 180
        let dx = sin(rad), dy = -cos(rad)
        let length = abs(w * sin(rad)) + abs(h * cos(rad))
        let cx = w / 2, cy = h / 2
        let sx = cx - dx * length / 2, sy = cy - dy * length / 2
        let ex = cx + dx * length / 2, ey = cy + dy * length / 2
        guard w > 0, h > 0 else { return ((0.5, 0), (0.5, 1)) }
        return ((sx / w, sy / h), (ex / w, ey / h))
    }
}

// MARK: - 古び方

/// 投稿の数から決まる古び方（モック Aging: **段階で切り替えず、投稿1件ごとに少しずつ**）
enum TrunkAging {

    /// 0（はじめの日）〜1（投稿 100 で飴色の相棒）。モックの `Math.min(1, posts / 100)`
    static func stage(posts: Int) -> Double {
        min(1, max(0, Double(posts)) / 100)
    }

    /// 手荷物タグの枚数（投稿 20 で1枚目・50 で2枚・80 で3枚）
    static func tagCount(posts: Int) -> Int {
        posts >= 80 ? 3 : posts >= 50 ? 2 : posts >= 20 ? 1 : 0
    }

    /// 貼ったラベルの古び（`k` は古い順の番号・`n` は並べる枚数）。モックの
    /// `Math.max(0, st * (1 - k / Math.max(1, n)) * 1.05)` を 1 で止める
    static func labelAge(index k: Int, count n: Int, stage st: Double) -> Double {
        min(1, max(0, st * (1 - Double(k) / Double(max(1, n))) * 1.05))
    }

    /// 区切りの投稿の数と、そのとき変わったところ（モック Aging の10か所）。トランクを開いたときに短く知らせる
    static let milestones: [(posts: Int, ja: String, en: String)] = [
        (3, "持ち手に手の跡", "Hand marks on the handle"),
        (7, "革に少し艶が出る", "A little shine on the leather"),
        (12, "角が擦れ始める", "The corners begin to wear"),
        (20, "最初の手荷物タグ", "Your first baggage tag"),
        (30, "金具がくすみ始める", "The fittings begin to dull"),
        (45, "革が明るい茶色へ", "The leather turns a lighter brown"),
        (60, "古いラベルが褪せる", "Old labels begin to fade"),
        (80, "ラベルの端がめくれる", "Label corners begin to lift"),
        (100, "飴色の相棒。この先も少しずつ", "An amber companion — and still changing"),
    ]

    /// いまの投稿の数でいちばん新しく越えた区切り（無ければ nil）
    static func latestMilestone(posts: Int) -> (posts: Int, ja: String, en: String)? {
        milestones.last { posts >= $0.posts }
    }
}

// MARK: - ラベルの置き場

/// トランクの胴（360×268）の上の、ラベルの置き場 11 か所（モックの `allLabels` の位置と大きさ）
enum TrunkSlots {

    struct Slot: Equatable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        /// 置いたときの傾き（度・モックの見本の値）
        let rot: Double
    }

    static let slots: [Slot] = [
        Slot(x: 150, y: 120, w: 108, h: 72, rot: -6),
        Slot(x: 30, y: 142, w: 84, h: 84, rot: 8),
        Slot(x: 266, y: 120, w: 88, h: 64, rot: 5),
        Slot(x: 112, y: 22, w: 78, h: 52, rot: -8),
        Slot(x: 214, y: 186, w: 74, h: 74, rot: -12),
        Slot(x: 222, y: 22, w: 98, h: 58, rot: 6),
        Slot(x: 118, y: 196, w: 94, h: 66, rot: 3),
        Slot(x: 14, y: 70, w: 82, h: 56, rot: -4),
        Slot(x: 292, y: 196, w: 62, h: 66, rot: 12),
        Slot(x: 168, y: 82, w: 64, h: 40, rot: -3),
        Slot(x: 300, y: 64, w: 56, h: 56, rot: -6),
    ]

    /// 貼る順（古いものから）。モックの `[7, 3, 9, 1, 0, 2, 5, 10, 4, 6, 8]`
    static let order = [7, 3, 9, 1, 0, 2, 5, 10, 4, 6, 8]

    static var capacity: Int { order.count }

    /// 置いたラベル（置き場・その中に収めた大きさ・古び）
    struct Placed: Equatable {
        let label: TrunkLabel
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let rot: Double
        let age: Double
    }

    /// 貼ったラベル（**新しい順**・サーバーの `stuck`）を置き場に並べる。
    ///
    /// 置けるのは 11 枚まで。2026-10-17 判断: それより多いときは**新しい 11 枚**を出す
    /// （貼ったばかりのラベルが見えないのは困る）。並べる 11 枚の中では古いものほど褪せる
    static func place(_ stuckNewestFirst: [TrunkLabel], stage st: Double) -> [Placed] {
        let shown = Array(stuckNewestFirst.prefix(capacity).reversed())
        // 2026-10-17 判断（run 466 の見比べ）: 置き場の大きさをそのまま使う（モックの `allLabels` の x,y,w,h）。
        // 形の比に合わせて縮めると、モックより小さく形の違いが分かりにくかった
        return shown.enumerated().map { k, label in
            let slot = slots[order[k]]
            return Placed(label: label, x: slot.x, y: slot.y, w: slot.w, h: slot.h, rot: slot.rot,
                          age: TrunkAging.labelAge(index: k, count: shown.count, stage: st))
        }
    }
}

// MARK: - 型ごとの見た目

/// 金具の面（真鍮・クローム・金箔）。古びると暗くくすむ（モックの `brass(t)`・`chrome(t)`・`gilt(t)`）
enum TrunkMetal: Equatable {
    case brass, chrome, gilt

    /// 135° のグラデーションの色（`st` は古び方）
    func stops(_ st: Double) -> [TrunkStop] {
        switch self {
        case .brass:
            return [TrunkStop(color: .mix(0xF2DFAE, 0xB9A16C, st), location: 0),
                    TrunkStop(color: .mix(0xC9A66B, 0x957A48, st), location: 0.42),
                    TrunkStop(color: .mix(0x8A6B39, 0x55442A, st), location: 1)]
        case .chrome:
            return [TrunkStop(color: TrunkRGBA(0xFFFFFF), location: 0),
                    TrunkStop(color: .mix(0xD9DDE1, 0xB9BEC3, st), location: 0.30),
                    TrunkStop(color: TrunkRGBA(0x8A9198), location: 0.62),
                    TrunkStop(color: .mix(0xE8EBEE, 0xA9AFB5, st), location: 1)]
        case .gilt:
            return [TrunkStop(color: .mix(0xF6E3A6, 0xD2B470, st), location: 0),
                    TrunkStop(color: .mix(0xD4AF5A, 0xA88A44, st), location: 0.45),
                    TrunkStop(color: TrunkRGBA(0x7E5F22), location: 1)]
        }
    }

    /// 金箔だけ、45° の細い縞（彫りの目）を重ねる
    var hasEngraving: Bool { self == .gilt }
}

/// 面の塗り
enum TrunkFill: Equatable {
    case metal(TrunkMetal)
    case solid(TrunkRGBA)
    /// CSS の linear-gradient
    case linear(TrunkGradient)
    /// 木の桟（縦の木目の縞＋左右から中央へのグラデーション）
    case wood(edge: TrunkRGBA, middle: TrunkRGBA)
    /// 籐・柳の縁（3px ごとの縦の縞）
    case rattan(TrunkRGBA, TrunkRGBA)
}

/// 胴の地
enum TrunkSurface: Equatable {
    /// 楕円のグラデーション（中心と半径は胴の大きさに対する割合・外の色の位置）
    case radial(inner: TrunkRGBA, outer: TrunkRGBA, center: (x: Double, y: Double),
                radius: (x: Double, y: Double), outerStop: Double)
    /// 縞の帆布（16px の地・1px の細い線・2px の色の帯）
    case canvasStripes(base: TrunkRGBA, thin: TrunkRGBA, band: TrunkRGBA)
    /// 波板のアルミ（9px ごとの横の波）
    case corrugated
    /// 柳の編み（縦 6px の目・横 9px の段）
    case wicker(a: TrunkRGBA, b: TrunkRGBA, c: TrunkRGBA)
    /// チークの板張り（44px ごとの継ぎ目・木目）
    case planks(top: TrunkRGBA, bottom: TrunkRGBA)
    /// 磨いたアルミ（横に流れる光の帯）
    case polished

    static func == (l: TrunkSurface, r: TrunkSurface) -> Bool {
        switch (l, r) {
        case let (.radial(a, b, c, d, e), .radial(f, g, h, i, j)):
            return a == f && b == g && c == h && d == i && e == j
        case let (.canvasStripes(a, b, c), .canvasStripes(d, e, f)): return a == d && b == e && c == f
        case (.corrugated, .corrugated), (.polished, .polished): return true
        case let (.wicker(a, b, c), .wicker(d, e, f)): return a == d && b == e && c == f
        case let (.planks(a, b), .planks(c, d)): return a == c && b == d
        default: return false
        }
    }
}

/// 胴に重ねる目（革の粒・布の織り・アルミの光・機体の継ぎ目）
enum TrunkTexture: Equatable { case none, grain, weave, sheen, seams }

/// 胴の上の絵（漆の金蒔絵・船長の羅針盤・星図の星座）
enum TrunkArt: Equatable { case makie, compass, stars }

/// 1つの型の部品と色（モックの `M[model]` を、古び方 `st` を入れて計算したもの）
struct TrunkLook: Equatable {
    let model: TrunkModel
    let stage: Double

    let surface: TrunkSurface
    let texture: TrunkTexture
    let handle: TrunkRGBA
    /// 縁の革（幅 0 なら無し）。`gold` は内側に金の押し線
    let binding: (width: Double, color: TrunkRGBA, gold: Bool)
    /// 縁の縫い目（無ければ nil）
    let stitch: TrunkRGBA?
    /// 胴を横切る帯（上から 84）
    let rail: (height: Double, fill: TrunkFill)
    /// 縦・横の桟（`x` が在れば縦）
    let bars: [Bar]
    let barFill: TrunkFill?
    /// 革のベルト（左の位置・幅・色・縫い目・尾錠）
    let straps: Straps?
    /// 組紐（漆）
    let cords: (x: [Double], width: Double)?
    /// 麻の縄（柳行李）
    let hemp: (x: [Double], width: Double)?
    let corners: Corners
    /// 留め金（アルミのケースの2つ）
    let latches: Bool
    let lock: Lock
    /// 鋲の列（y・間隔）
    let rivetRows: [(y: Double, step: Double)]
    /// 鋲の色（列の鋲）
    let rivetMetal: TrunkMetal?
    /// 桟の上の鋲
    let slatRivets: Bool
    let art: TrunkArt?
    /// 名札（寝台列車の真鍮の札・飛行艇の小さいクロームの札）
    let plate: TrunkPlate?
    /// 艶（無ければ nil）
    let gloss: [TrunkGloss]
    /// 角の擦れ（明るいしみ）の強さ
    let scuff: Double
    /// 茶色いしみの強さ（帆布）
    let stain: Double
    /// 擦り傷の強さ（アルミ）
    let scratch: Double

    struct Bar: Equatable {
        let x: Double?
        let y: Double?
        let size: Double
        /// 真鍮の帯（桟の色ではなく）
        let brass: Bool
    }

    struct Straps: Equatable {
        let x: [Double]
        let width: Double
        let color: TrunkRGBA
        let edge: TrunkRGBA
        let buckle: TrunkMetal
    }

    struct Corners: Equatable {
        let size: Double
        let fill: TrunkFill
        let rivet: Bool
        /// アルミの丸い角
        let round: Bool
    }

    struct Lock: Equatable {
        let width: Double
        let height: Double
        let fill: TrunkFill
        let round: Bool
        /// 柳行李の革の留め（鍵穴の代わりに真鍮の輪）
        let tab: Bool
    }

    static func == (l: TrunkLook, r: TrunkLook) -> Bool {
        l.model == r.model && l.stage == r.stage
    }
}

/// 名札の種類
enum TrunkPlate: Equatable { case brass, chrome }

/// 艶の重ね
enum TrunkGloss: Equatable {
    case linear(TrunkGradient)
    /// 楕円の光（中心・半径は割合）
    case spot(color: TrunkRGBA, center: (x: Double, y: Double), radius: (x: Double, y: Double))

    static func == (l: TrunkGloss, r: TrunkGloss) -> Bool {
        switch (l, r) {
        case let (.linear(a), .linear(b)): return a == b
        case let (.spot(a, b, c), .spot(d, e, f)): return a == d && b == e && c == f
        default: return false
        }
    }
}

enum TrunkLooks {

    /// 胴の大きさ（モックの W・H）。全体は 360×300 で、胴は上から 32
    static let bodyWidth: Double = 360
    static let bodyHeight: Double = 268
    static let bodyTop: Double = 32
    static let canvasWidth: Double = 360
    static let canvasHeight: Double = 300
    /// 胴を横切る帯の高さの位置
    static let railY: Double = 84

    private static func gradient(_ angle: Double, _ stops: [(TrunkRGBA, Double)]) -> TrunkGradient {
        TrunkGradient(angle: angle, stops: stops.map { TrunkStop(color: $0.0, location: $0.1) })
    }

    private static func white(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> TrunkRGBA {
        TrunkRGBA(r: r, g: g, b: b, a: a)
    }

    // swiftlint:disable:next function_body_length
    static func look(_ model: TrunkModel, stage st: Double) -> TrunkLook {
        let m = TrunkRGBA.mix
        let brass = TrunkFill.metal(.brass)
        let chrome = TrunkFill.metal(.chrome)
        let gilt = TrunkFill.metal(.gilt)
        switch model {
        case .leather:
            return TrunkLook(
                model: model, stage: st,
                surface: .radial(inner: m(0x7E4828, 0xA06D45, st), outer: m(0x4E2814, 0x66402A, st),
                                 center: (0.28, 0.18), radius: (1.2, 0.95), outerStop: 0.78),
                texture: .grain, handle: TrunkRGBA(0x2E170A),
                binding: (9, m(0x3A1E0E, 0x4A2C18, st), false), stitch: white(240, 215, 170, 0.45),
                rail: (5, brass), bars: [], barFill: nil,
                straps: .init(x: [84, 252], width: 26, color: TrunkRGBA(0x3A1E0E), edge: white(240, 215, 170, 0.4), buckle: .brass),
                cords: nil, hemp: nil,
                corners: .init(size: 40, fill: brass, rivet: true, round: false), latches: false,
                lock: .init(width: 40, height: 30, fill: brass, round: false, tab: false),
                rivetRows: [], rivetMetal: nil, slatRivets: false, art: nil, plate: nil,
                gloss: [.linear(gradient(172, [(white(255, 240, 220, 0.14), 0), (white(255, 240, 220, 0), 0.30)]))],
                scuff: 0.10, stain: 0, scratch: 0)
        case .canvas:
            let edge = m(0x6B3E1E, 0x80542F, st)
            return TrunkLook(
                model: model, stage: st,
                surface: .canvasStripes(base: m(0xC7B38A, 0xBCA982, st), thin: m(0xB49F74, 0xA8946C, st),
                                        band: m(0x8C3A2C, 0x7A4A3A, st)),
                texture: .weave, handle: TrunkRGBA(0x5A3418),
                binding: (14, edge, false), stitch: white(250, 235, 200, 0.5),
                rail: (8, .linear(gradient(180, [(edge, 0), (TrunkRGBA(0x4A2812), 1)]))), bars: [], barFill: nil,
                straps: .init(x: [84, 252], width: 24, color: m(0x7A4E2A, 0x916440, st), edge: white(250, 235, 200, 0.5), buckle: .brass),
                cords: nil, hemp: nil,
                corners: .init(size: 36, fill: .linear(gradient(135, [(m(0x7A4A26, 0x8E6040, st), 0), (TrunkRGBA(0x4A2812), 1)])),
                               rivet: true, round: false), latches: false,
                lock: .init(width: 36, height: 28, fill: brass, round: false, tab: false),
                rivetRows: [], rivetMetal: nil, slatRivets: false, art: nil, plate: nil,
                gloss: [], scuff: 0, stain: 0.22, scratch: 0)
        case .aluminum:
            return TrunkLook(
                model: model, stage: st,
                surface: .corrugated, texture: .sheen, handle: TrunkRGBA(0x1A1A1A),
                binding: (7, TrunkRGBA(0x8A9198), false), stitch: nil,
                rail: (10, .linear(gradient(180, [(TrunkRGBA(0xF4F6F8), 0), (TrunkRGBA(0x9AA1A8), 0.55), (TrunkRGBA(0xC9CED3), 1)]))),
                bars: [], barFill: nil, straps: nil, cords: nil, hemp: nil,
                corners: .init(size: 34, fill: chrome, rivet: true, round: true), latches: true,
                lock: .init(width: 30, height: 24, fill: chrome, round: false, tab: false),
                rivetRows: [(14, 24), (254, 24)], rivetMetal: .chrome, slatRivets: false, art: nil, plate: nil,
                gloss: [.linear(gradient(175, [(white(255, 255, 255, 0.35), 0), (white(255, 255, 255, 0), 0.26)]))],
                scuff: 0, stain: 0, scratch: st)
        case .steamer:
            let wood = TrunkFill.wood(edge: m(0x8E5A2C, 0xB07A48, st), middle: m(0xB07440, 0xC99560, st))
            return TrunkLook(
                model: model, stage: st,
                surface: .radial(inner: m(0x355441, 0x4A6652, st), outer: m(0x1D3227, 0x2A4033, st),
                                 center: (0.30, 0.20), radius: (1.2, 1.0), outerStop: 0.80),
                texture: .weave, handle: TrunkRGBA(0x3A2010),
                binding: (0, TrunkRGBA(0x000000), false), stitch: nil,
                rail: (12, wood),
                bars: [.init(x: 96, y: nil, size: 18, brass: false), .init(x: 246, y: nil, size: 18, brass: false),
                       .init(x: nil, y: 0, size: 14, brass: false), .init(x: nil, y: 254, size: 14, brass: false)],
                barFill: wood, straps: nil, cords: nil, hemp: nil,
                corners: .init(size: 44, fill: brass, rivet: true, round: false), latches: false,
                lock: .init(width: 46, height: 36, fill: brass, round: false, tab: false),
                rivetRows: [], rivetMetal: nil, slatRivets: true, art: nil, plate: nil,
                gloss: [], scuff: 0.06, stain: 0, scratch: 0)
        case .urushi:
            return TrunkLook(
                model: model, stage: st,
                surface: .radial(inner: m(0x3E100B, 0x6A1E12, st), outer: m(0x140504, 0x2A0A06, st),
                                 center: (0.30, 0.12), radius: (1.3, 1.0), outerStop: 0.70),
                texture: .none, handle: TrunkRGBA(0x1A0605),
                binding: (6, TrunkRGBA(0x0A0202), false), stitch: nil,
                rail: (4, gilt), bars: [], barFill: nil, straps: nil,
                cords: ([92, 254], 14), hemp: nil,
                corners: .init(size: 38, fill: gilt, rivet: false, round: false), latches: false,
                lock: .init(width: 34, height: 34, fill: gilt, round: true, tab: false),
                rivetRows: [], rivetMetal: nil, slatRivets: false, art: .makie, plate: nil,
                gloss: [.linear(gradient(158, [(white(255, 255, 255, 0.32), 0), (white(255, 255, 255, 0.06), 0.22),
                                               (white(255, 255, 255, 0), 0.23)])),
                        .spot(color: white(255, 255, 255, 0.22), center: (0.32, 0.06), radius: (0.70, 0.14))],
                scuff: 0, stain: 0, scratch: 0)
        case .kori:
            let rattan = TrunkFill.rattan(m(0xE2C995, 0xCDB07A, st), m(0xC7A86F, 0xB08F5A, st))
            return TrunkLook(
                model: model, stage: st,
                surface: .wicker(a: m(0xD2B47E, 0xBE9C64, st), b: m(0xB8955E, 0xA07F4C, st), c: m(0xDCC08C, 0xC9A874, st)),
                texture: .none, handle: TrunkRGBA(0x5A3A1E),
                binding: (0, TrunkRGBA(0x000000), false), stitch: nil,
                rail: (14, rattan),
                bars: [.init(x: nil, y: 0, size: 12, brass: false), .init(x: nil, y: 256, size: 12, brass: false)],
                barFill: rattan, straps: nil, cords: nil, hemp: ([88, 256], 12),
                corners: .init(size: 30, fill: .linear(gradient(135, [(m(0x5A3418, 0x6E4626, st), 0), (TrunkRGBA(0x2E1808), 1)])),
                               rivet: false, round: false), latches: false,
                lock: .init(width: 22, height: 30, fill: .linear(gradient(180, [(TrunkRGBA(0x5A3418), 0), (TrunkRGBA(0x2E1808), 1)])),
                            round: false, tab: true),
                rivetRows: [], rivetMetal: nil, slatRivets: false, art: nil, plate: nil,
                gloss: [], scuff: 0, stain: 0, scratch: 0)
        case .sleeper:
            return TrunkLook(
                model: model, stage: st,
                surface: .radial(inner: m(0x6E1C18, 0x8A3326, st), outer: m(0x3A0C0A, 0x4E1A12, st),
                                 center: (0.30, 0.15), radius: (1.2, 0.95), outerStop: 0.78),
                texture: .grain, handle: TrunkRGBA(0x220707),
                binding: (9, TrunkRGBA(0x2A0807), false), stitch: white(230, 200, 150, 0.5),
                rail: (6, brass), bars: [.init(x: nil, y: 254, size: 6, brass: true)], barFill: nil,
                straps: .init(x: [70, 266], width: 24, color: TrunkRGBA(0x2A0807), edge: white(230, 200, 150, 0.45), buckle: .brass),
                cords: nil, hemp: nil,
                corners: .init(size: 42, fill: brass, rivet: true, round: false), latches: false,
                lock: .init(width: 40, height: 30, fill: brass, round: false, tab: false),
                rivetRows: [], rivetMetal: nil, slatRivets: false, art: nil, plate: .brass,
                gloss: [.linear(gradient(170, [(white(255, 230, 220, 0.22), 0), (white(255, 230, 220, 0), 0.32)]))],
                scuff: 0.06, stain: 0, scratch: 0)
        case .clipper:
            return TrunkLook(
                model: model, stage: st,
                surface: .polished, texture: .seams, handle: TrunkRGBA(0x7A4E2A),
                binding: (0, TrunkRGBA(0x000000), false), stitch: nil,
                rail: (6, .linear(gradient(180, [(TrunkRGBA(0x5E666E), 0), (TrunkRGBA(0xC9CED3), 1)]))), bars: [], barFill: nil,
                straps: .init(x: [96, 240], width: 22, color: TrunkRGBA(0x8A5A30), edge: white(255, 240, 215, 0.5), buckle: .chrome),
                cords: nil, hemp: nil,
                corners: .init(size: 30, fill: chrome, rivet: false, round: true), latches: false,
                lock: .init(width: 32, height: 24, fill: chrome, round: false, tab: false),
                rivetRows: [(10, 12), (84, 12), (174, 12), (258, 12)], rivetMetal: .chrome, slatRivets: false,
                art: nil, plate: .chrome, gloss: [], scuff: 0, stain: 0, scratch: st * 0.7)
        case .captain:
            return TrunkLook(
                model: model, stage: st,
                surface: .planks(top: m(0x7E4C26, 0x9A6438, st), bottom: m(0x5A3318, 0x704424, st)),
                texture: .none, handle: TrunkRGBA(0xB9A274),
                binding: (0, TrunkRGBA(0x000000), false), stitch: nil,
                rail: (8, brass),
                bars: [.init(x: 66, y: nil, size: 14, brass: true), .init(x: 280, y: nil, size: 14, brass: true)],
                barFill: nil, straps: nil, cords: nil, hemp: nil,
                corners: .init(size: 46, fill: brass, rivet: true, round: false), latches: false,
                lock: .init(width: 30, height: 26, fill: brass, round: false, tab: false),
                rivetRows: [], rivetMetal: nil, slatRivets: true, art: .compass, plate: nil,
                gloss: [.linear(gradient(170, [(white(255, 230, 200, 0.12), 0), (white(255, 230, 200, 0), 0.30)]))],
                scuff: 0.05, stain: 0, scratch: 0)
        case .starchart:
            return TrunkLook(
                model: model, stage: st,
                surface: .radial(inner: m(0x1C2C50, 0x2A3C62, st), outer: m(0x0B142A, 0x16203A, st),
                                 center: (0.30, 0.18), radius: (1.2, 0.95), outerStop: 0.80),
                texture: .grain, handle: TrunkRGBA(0x08101F),
                binding: (8, TrunkRGBA(0x0A1226), true), stitch: white(201, 166, 107, 0.55),
                rail: (4, brass), bars: [], barFill: nil,
                straps: .init(x: [84, 252], width: 24, color: TrunkRGBA(0x0A1226), edge: white(201, 166, 107, 0.55), buckle: .brass),
                cords: nil, hemp: nil,
                corners: .init(size: 38, fill: brass, rivet: true, round: false), latches: false,
                lock: .init(width: 38, height: 28, fill: brass, round: false, tab: false),
                rivetRows: [], rivetMetal: nil, slatRivets: false, art: .stars, plate: nil,
                gloss: [.linear(gradient(170, [(white(200, 220, 255, 0.12), 0), (white(200, 220, 255, 0), 0.30)]))],
                scuff: 0.05, stain: 0, scratch: 0)
        }
    }

    /// 鋲の並び（列の鋲・桟の上の鋲）。中心と半径
    static func rivets(_ look: TrunkLook) -> [(x: Double, y: Double, r: Double, slat: Bool)] {
        var out: [(x: Double, y: Double, r: Double, slat: Bool)] = []
        for row in look.rivetRows {
            var x = 22.0
            while x <= bodyWidth - 22 {
                out.append((x, row.y, 2, false))
                x += row.step
            }
        }
        if look.slatRivets {
            for bar in look.bars {
                guard let bx = bar.x else { continue }
                for y in [30.0, 100, 170, 240] { out.append((bx + bar.size / 2, y, 2.6, true)) }
            }
        }
        return out
    }

    /// 錠前の上の位置（帯の真ん中に合わせる・柳行李の革の留めは帯の上から垂らす）
    static func lockTop(_ look: TrunkLook) -> Double {
        look.lock.tab ? railY - 4 : railY - look.lock.height / 2 + look.rail.height / 2
    }

    /// 手荷物タグ（モックの3枚。投稿の数で増える・`TrunkAging.tagCount`）
    struct Tag: Equatable {
        let code: String
        /// タグに刷った日（「2025.06.20」・飾りの字。生の日時ではない）
        let printedDay: String
        let x: Double
        let rot: Double
        let bg: TrunkRGBA
        let fg: TrunkRGBA
    }

    static let tags: [Tag] = [
        Tag(code: "HND→HEL", printedDay: "2025.06.20", x: 252, rot: 14, bg: TrunkRGBA(0xEFE6D2), fg: TrunkRGBA(0x1E1E1E)),
        Tag(code: "KIX→BCN", printedDay: "2023.08.02", x: 216, rot: -5, bg: TrunkRGBA(0xF2C9A0), fg: TrunkRGBA(0x3A1E10)),
        Tag(code: "CTS", printedDay: "2019.02.08", x: 278, rot: 26, bg: TrunkRGBA(0xC7D8E2), fg: TrunkRGBA(0x13303F)),
    ]

    /// 手荷物タグの褪せ（モックの `saturate(1 - st * 0.4) sepia(st * 0.25)`）
    static func tagColor(_ color: TrunkRGBA, stage st: Double) -> TrunkRGBA {
        color.filtered(saturate: 1 - st * 0.4, sepia: st * 0.25)
    }

    /// 胴の中で、型を替えても変わらない「縁の色」（3D で箱の側面に塗る・地の暗い方）
    static func sideColor(_ look: TrunkLook) -> TrunkRGBA {
        if look.binding.width > 0 { return look.binding.color }
        switch look.surface {
        case let .radial(_, outer, _, _, _): return outer
        case let .canvasStripes(base, _, _): return base
        case .corrugated, .polished: return TrunkRGBA(0xA9AFB5)
        case let .wicker(_, b, _): return b
        case let .planks(_, bottom): return bottom
        }
    }
}
