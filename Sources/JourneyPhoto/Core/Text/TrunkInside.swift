import Foundation

// トランクの中身（板「旅のトランク」の行「トランクの中身（次の版）」・2026-10-18 owner 承認）。
//
// 板: TrunkOpen（ふたを開ける）・Inside（部品: トランクの中）・InsideHold（中身を手に取る）・
// InsideEmpty（空のトランク）・InsideModels（型ごとの中）・Linings（内張りの布）。
// **SwiftUI を読まない層**（Linux でテストする）。画面は `Features/Trunk/TrunkOpenView.swift`・`TrunkInsideView.swift`。
//
// ふたは**前開き**（2026-10-18 決定）: 下の辺が蝶番で、ふたは手前へ倒れる。開けた姿は胴が上
// （内ポケットに会員証・仕切りに乗車券）・倒れたふたが下（ふたの裏にメダルの台 8 枠）。
// 中に入れるのは本物の持ち物だけ——メダル＝持っているバッジ（`BadgeCatalog.owned`）、会員証＝サポーター証
// （**Pro のときだけ**）、乗車券＝すれちがい帳に綴じたカード。

// MARK: - ふたの開き具合

enum TrunkLid {

    /// 指で引き下ろす長さ（この長さで 0 → 1・板の 320）
    static let dragDistance: Double = 320
    /// 舞台の大きさ（板 TrunkOpen の 390×584）。狭い画面では縮めて置く
    static let stageWidth: Double = 390
    static let stageHeight: Double = 584
    /// 胴（とふた）の左（舞台の真ん中に 360 を置く）
    static let bodyLeft: Double = 15
    /// 胴の高さ（ふたも同じ）
    static let bodyHeight: Double = TrunkLooks.bodyHeight
    /// 遠近（板の perspective 820px を SwiftUI の 0〜1 に）
    static let perspective: Double = 0.48
    /// 寄せる速さ（板の 0.55s cubic-bezier(.2,.75,.25,1)）
    static let settleDuration: Double = 0.55

    /// 指を動かしたあとの開き具合（0〜1 に収める）。下へ引くと開く
    static func dragged(from start: Double, dy: Double) -> Double {
        clamp(start + dy / dragDistance)
    }

    /// 指を離したら近い方へ（半分より開いていれば開き切る）
    static func settled(_ p: Double) -> Double { p > 0.5 ? 1 : 0 }

    /// 「ふたを開ける／閉じる」のボタンを押したあと
    static func toggled(_ p: Double) -> Double { p >= 0.5 ? 0 : 1 }

    /// ふたの倒れた角度（度・0 で閉じ、180 で開き切る）
    static func angle(_ p: Double) -> Double { 180 * clamp(p) }

    /// 胴の上の位置（閉じると舞台の真ん中寄り、開くと上へ上がり、倒れたふたの場所を空ける）
    static func baseTop(_ p: Double) -> Double { 184 - 144 * clamp(p) }

    /// ふたの裏が見えるか（90° を越えたら裏）
    static func showsInside(_ p: Double) -> Bool { angle(p) > 90 }

    /// 錠前の板の起き具合（開け始めの 0〜10% で起き切る。留め金が外れる）
    static func claspProgress(_ p: Double) -> Double { min(1, max(0, p) / 0.1) }

    /// 錠前の板の起きる角度（度）
    static func claspAngle(_ p: Double) -> Double { 140 * claspProgress(p) }

    /// 倒れていく表の陰（濃さ）
    static func lidShade(_ p: Double) -> Double { min(1, clamp(p) * 1.8) * 0.45 }

    /// ふたの裏の陰（開き切ると無い）
    static func innerShade(_ p: Double) -> Double { max(0, 1 - clamp(p)) * 0.9 }

    /// 蝶番が見えるか（半分より開いたら）
    static func hingesVisible(_ p: Double) -> Bool { p > 0.55 }

    /// 開き切ったか（中身を押せる）
    static func isOpen(_ p: Double) -> Bool { p >= 0.999 }

    static func percent(_ p: Double) -> Int { Int((clamp(p) * 100).rounded()) }

    static func percentText(_ p: Double) -> String { "\(percent(p))%" }

    /// 読み上げの値（「開き具合 38%」）
    static func accessibilityValue(_ p: Double) -> String {
        L("開き具合 \(percent(p))%", "Open \(percent(p))%")
    }

    /// 読み上げの「増やす・減らす」で動かす量
    static func stepped(_ p: Double, up: Bool) -> Double { clamp(p + (up ? 0.25 : -0.25)) }

    /// 下の一言（板 TrunkOpen の `hint`）
    static func hint(_ p: Double) -> String {
        if p <= 0.02 { return L("ふたを手前へ引き下ろすと開きます", "Pull the lid down towards you to open it") }
        if p >= 0.98 { return L("メダル・会員証・乗車券を押すと、手に取れます", "Tap a medal, card or ticket to pick it up") }
        return L("指を離すと、近い方へ開くか閉じます", "Let go and it opens or closes, whichever is nearer")
    }

    static func toggleTitle(_ p: Double) -> String {
        p >= 0.5 ? L("ふたを閉じる", "Close the lid") : L("ふたを開ける", "Open the lid")
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

// MARK: - 型ごとの中（板 InsideModels）

/// 内張りの布（名前と塗り）
struct TrunkLining: Equatable {
    let name: String
    let paint: TrunkPartPaint
    /// 付けた内張りの部品（型の既定なら nil）
    let partId: String?
}

/// 1つの型の中の作り（縁＝胴の素材・既定の内張り・ふたの裏のメダルの台・仕切り・蝶番の金属）
struct TrunkInsideLook: Equatable {
    let model: TrunkModel
    /// 縁（胴の素材）
    let rim: TrunkPartPaint
    /// 型の既定の内張り
    let defaultLining: TrunkLining
    let panel: TrunkPartPaint
    let panelName: String
    let divider: TrunkPartPaint
    let dividerName: String
    /// 縫い目の色（縫い目の無い型は nil）
    let stitch: TrunkRGBA?
    /// 蝶番の金属
    let metal: TrunkPartPaint
    /// 金の縁（漆・星図）
    let gildEdge: Bool
    /// 仕切りの真鍮の帯（寝台列車・船長）
    let brassBand: Bool
}

enum TrunkInsideLooks {

    // 塗りの道具（板 Inside の CSS をそのまま写す）

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> TrunkRGBA {
        TrunkRGBA(r: r, g: g, b: b, a: a)
    }

    private static func linear(_ angle: Double, _ stops: [(TrunkRGBA, Double)]) -> TrunkPartPaint {
        .linear(TrunkGradient(angle: angle, stops: stops.map { TrunkStop(color: $0.0, location: $0.1) }))
    }

    private static func hex(_ angle: Double, _ stops: [(UInt32, Double)]) -> TrunkPartPaint {
        linear(angle, stops.map { (TrunkRGBA($0.0), $0.1) })
    }

    /// `radial-gradient(<rx> <ry> at <cx> <cy>, a 0%, b <stop>)`
    private static func radial(_ a: UInt32, _ b: UInt32, stop: Double, cx: Double, cy: Double, rx: Double, ry: Double) -> TrunkPartPaint {
        .glow(TrunkPartGlow(stops: [TrunkStop(color: TrunkRGBA(a), location: 0), TrunkStop(color: TrunkRGBA(b), location: stop)],
                            cx: cx, cy: cy, rx: rx, ry: ry, farthestCorner: false))
    }

    /// 革の粒（4px の升に黒 20%・白 5% の点を半升ずらして）
    static let grain: [TrunkPartPaint] = [
        .dots(TrunkPartDots(color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.20), tile: 4, center: 2, inner: 0.7, outer: 1.3)),
        .dots(TrunkPartDots(color: TrunkRGBA(r: 255, g: 255, b: 255, a: 0.05), tile: 4, center: 4, inner: 0.7, outer: 1.3)),
    ]

    /// 布の織り
    private static let weave: [TrunkPartPaint] = [
        .stripes(angle: 0, period: 3, bands: [TrunkPartBand(from: 0, to: 1, color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.07))]),
        .stripes(angle: 90, period: 3, bands: [TrunkPartBand(from: 0, to: 1, color: TrunkRGBA(r: 255, g: 255, b: 255, a: 0.06))]),
    ]

    private static func grained(_ base: TrunkPartPaint) -> TrunkPartPaint { .layers(grain + [base]) }

    /// 縦の木目（板の `wood(a, b)`）
    private static func wood(_ a: UInt32, _ b: UInt32) -> TrunkPartPaint {
        .layers([.stripes(angle: 90, period: 11, bands: [TrunkPartBand(from: 0, to: 1, color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.10)),
                                                          TrunkPartBand(from: 5, to: 6, color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.06))]),
                 hex(90, [(a, 0), (b, 0.5), (a, 1)])])
    }

    /// 横の木目（板の `woodH(a, b)`）
    private static func woodH(_ a: UInt32, _ b: UInt32) -> TrunkPartPaint {
        .layers([.stripes(angle: 0, period: 11, bands: [TrunkPartBand(from: 0, to: 1, color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.10)),
                                                         TrunkPartBand(from: 5, to: 6, color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.06))]),
                 hex(0, [(a, 0), (b, 0.5), (a, 1)])])
    }

    /// 柳の編み目（板の `kori`）
    private static let kori: TrunkPartPaint = .layers([
        .stripes(angle: 90, period: 6, bands: [TrunkPartBand(from: 0, to: 1, color: TrunkRGBA(r: 60, g: 35, b: 10, a: 0.22))]),
        .stripes(angle: 0, period: 9, bands: [TrunkPartBand(from: 0, to: 4, color: TrunkRGBA(0xCDB07A)),
                                              TrunkPartBand(from: 4, to: 5, color: TrunkRGBA(0xB08F5A)),
                                              TrunkPartBand(from: 5, to: 9, color: TrunkRGBA(0xD8BC88))]),
    ])

    static let brass: TrunkPartPaint = .metal(.brass)
    static let chrome: TrunkPartPaint = hex(135, [(0xFFFFFF, 0), (0xC9CED3, 0.30), (0x8A9198, 0.62), (0xDADEE2, 1)])
    static let gilt: TrunkPartPaint = hex(135, [(0xF6E3A6, 0), (0xD4AF5A, 0.45), (0x7E5F22, 1)])

    private static func lining(_ ja: String, _ en: String, _ paint: TrunkPartPaint) -> TrunkLining {
        TrunkLining(name: L(ja, en), paint: paint, partId: nil)
    }

    // swiftlint:disable:next function_body_length
    static func look(_ model: TrunkModel) -> TrunkInsideLook {
        let white = TrunkRGBA(r: 255, g: 255, b: 255, a: 0.10)
        switch model {
        case .leather:
            return TrunkInsideLook(
                model: model,
                rim: grained(radial(0x9C643C, 0x6A3E22, stop: 0.78, cx: 0.28, cy: 0.18, rx: 1.2, ry: 0.95)),
                defaultLining: lining("生成りの綾織", "Natural twill", .layers([
                    .stripes(angle: 45, period: 5, bands: [TrunkPartBand(from: 0, to: 2, color: rgba(120, 95, 60, 0.12))]),
                    .solid(TrunkRGBA(0xE3D6BA))])),
                panel: grained(hex(180, [(0x5E3219, 0), (0x44220F, 1)])), panelName: L("茶の革の台", "Brown leather tray"),
                divider: grained(hex(90, [(0x3A1E0E, 0), (0x6A3E22, 0.5), (0x3A1E0E, 1)])),
                dividerName: L("革の仕切り", "Leather divider"),
                stitch: rgba(240, 215, 170, 0.5), metal: brass, gildEdge: false, brassBand: false)
        case .canvas:
            return TrunkInsideLook(
                model: model,
                rim: .stripes(angle: 90, period: 18, bands: [TrunkPartBand(from: 0, to: 8, color: TrunkRGBA(0xC2AE86)),
                                                             TrunkPartBand(from: 8, to: 9, color: TrunkRGBA(0xAF9A70)),
                                                             TrunkPartBand(from: 9, to: 16, color: TrunkRGBA(0xC2AE86)),
                                                             TrunkPartBand(from: 16, to: 18, color: TrunkRGBA(0x864232))]),
                defaultLining: lining("生成りの帆布", "Natural canvas", .layers(weave + [.solid(TrunkRGBA(0xD8C9A6))])),
                panel: grained(hex(180, [(0x84562F, 0), (0x6B4022, 1)])), panelName: L("厚革の台", "Thick leather tray"),
                divider: grained(hex(90, [(0x5A3418, 0), (0x84562F, 0.5), (0x5A3418, 1)])),
                dividerName: L("厚革の仕切り", "Thick leather divider"),
                stitch: rgba(250, 235, 200, 0.55), metal: brass, gildEdge: false, brassBand: false)
        case .aluminum:
            return TrunkInsideLook(
                model: model,
                rim: .stripes(angle: 180, period: 9, bands: [TrunkPartBand(from: 0, to: 7, color: TrunkRGBA(0xDADEE2)),
                                                             TrunkPartBand(from: 7, to: 8, color: TrunkRGBA(0xA9AFB5)),
                                                             TrunkPartBand(from: 8, to: 9, color: TrunkRGBA(0xF1F3F5))]),
                defaultLining: lining("灰のフェルト", "Grey felt", .layers([
                    .dots(TrunkPartDots(color: rgba(255, 255, 255, 0.06), tile: 3, center: 1.5, inner: 0.6, outer: 1)),
                    .solid(TrunkRGBA(0x34373C))])),
                panel: .layers([.dots(TrunkPartDots(color: rgba(255, 255, 255, 0.05), tile: 4, center: 2, inner: 0.8, outer: 1.2)),
                                .solid(TrunkRGBA(0x1A1B1E))]),
                panelName: L("黒い緩衝材（型抜き）", "Black foam (cut-out)"),
                divider: hex(90, [(0x8A9198, 0), (0xEEF0F2, 0.45), (0xA9AFB5, 1)]),
                dividerName: L("アルミの仕切り板", "Aluminium divider"),
                stitch: nil, metal: chrome, gildEdge: false, brassBand: false)
        case .steamer:
            return TrunkInsideLook(
                model: model,
                rim: wood(0x9A6634, 0xB9834E),
                defaultLining: lining("船旅の紙張り（小花）", "Voyage paper (small flowers)", .layers([
                    .dots(TrunkPartDots(color: rgba(46, 93, 80, 0.38), tile: 14, center: 7, inner: 2, outer: 2.5)),
                    .dots(TrunkPartDots(color: rgba(184, 70, 58, 0.32), tile: 14, center: 14, inner: 1.5, outer: 2)),
                    .solid(TrunkRGBA(0xEADFC4))])),
                panel: woodH(0x8E5A2C, 0xA8723E), panelName: L("木の盆", "Wooden tray"),
                divider: wood(0x8E5A2C, 0xB07440), dividerName: L("木の桟の仕切り", "Wooden slat divider"),
                stitch: nil, metal: brass, gildEdge: false, brassBand: false)
        case .urushi:
            return TrunkInsideLook(
                model: model,
                rim: radial(0x3E100B, 0x140504, stop: 0.70, cx: 0.30, cy: 0.12, rx: 1.3, ry: 1.0),
                defaultLining: lining("朱の漆", "Vermilion lacquer",
                                      radial(0xB03822, 0x6A1A10, stop: 0.80, cx: 0.30, cy: 0.20, rx: 1.2, ry: 0.9)),
                panel: .layers([linear(160, [(white, 0), (white.alpha(0), 0.40)]), .solid(TrunkRGBA(0x121010))]),
                panelName: L("黒の正絹の台・金の縁", "Black silk tray, gold edge"),
                divider: hex(90, [(0x0A0202, 0), (0x2A0A06, 0.5), (0x0A0202, 1)]),
                dividerName: L("黒漆の板・金の縁", "Black lacquer board, gold edge"),
                stitch: nil, metal: gilt, gildEdge: true, brassBand: false)
        case .kori:
            let sashiko = TrunkPartBand(from: 0, to: 1, color: rgba(255, 255, 255, 0.10))
            return TrunkInsideLook(
                model: model,
                rim: kori,
                defaultLining: lining("柳の編み目", "Woven willow", kori),
                panel: .layers([.stripes(angle: 45, period: 7, bands: [sashiko]), .stripes(angle: -45, period: 7, bands: [sashiko]),
                                .solid(TrunkRGBA(0x24324A))]),
                panelName: L("藍の刺し子の台", "Indigo sashiko tray"),
                divider: .stripes(angle: 0, period: 4, bands: [TrunkPartBand(from: 0, to: 3, color: TrunkRGBA(0xE2C995)),
                                                               TrunkPartBand(from: 3, to: 4, color: TrunkRGBA(0xC7A86F))]),
                dividerName: L("籐の仕切り", "Rattan divider"),
                stitch: rgba(240, 232, 210, 0.55), metal: hex(180, [(0x5A3418, 0), (0x2E1808, 1)]),
                gildEdge: false, brassBand: false)
        case .sleeper:
            return TrunkInsideLook(
                model: model,
                rim: grained(radial(0x842A20, 0x4A1610, stop: 0.78, cx: 0.30, cy: 0.15, rx: 1.2, ry: 0.95)),
                defaultLining: lining("臙脂のモケット（座席の布）", "Crimson moquette (seat cloth)", .layers([
                    .stripes(angle: 90, period: 4, bands: [TrunkPartBand(from: 0, to: 1, color: rgba(0, 0, 0, 0.14))]),
                    radial(0x7E2428, 0x4E1216, stop: 0.80, cx: 0.30, cy: 0.20, rx: 1.2, ry: 0.9)])),
                panel: grained(hex(180, [(0x2E0A08, 0), (0x1E0605, 1)])), panelName: L("黒革の台", "Black leather tray"),
                divider: grained(hex(90, [(0x2A0807, 0), (0x5A1612, 0.5), (0x2A0807, 1)])),
                dividerName: L("革の仕切り・真鍮の帯", "Leather divider, brass band"),
                stitch: rgba(230, 200, 150, 0.5), metal: brass, gildEdge: false, brassBand: true)
        case .clipper:
            let quilt = TrunkPartBand(from: 0, to: 1, color: rgba(0, 0, 0, 0.20))
            return TrunkInsideLook(
                model: model,
                rim: hex(100, [(0x8E969E, 0), (0xE9EDF0, 0.20), (0xB7BEC5, 0.38), (0xF7F9FA, 0.52), (0x9AA2AA, 0.72), (0xD4D9DD, 1)]),
                defaultLining: lining("灰青のキルト", "Blue-grey quilt", .layers([
                    .stripes(angle: 45, period: 18, bands: [quilt]), .stripes(angle: -45, period: 18, bands: [quilt]),
                    hex(180, [(0x66778A, 0), (0x4E5E70, 1)])])),
                panel: grained(hex(180, [(0x2E343C, 0), (0x1E2228, 1)])), panelName: L("紺鼠の革の台", "Slate leather tray"),
                divider: .layers([.dots(TrunkPartDots(color: TrunkRGBA(0xD2D6DA), tile: 12, center: 5, inner: 1.5, outer: 2.2)),
                                  hex(90, [(0x8E969E, 0), (0xE9EDF0, 0.45), (0xA9AFB5, 1)])]),
                dividerName: L("鋲留めのアルミ板", "Riveted aluminium plate"),
                stitch: rgba(255, 240, 215, 0.45), metal: chrome, gildEdge: false, brassBand: false)
        case .captain:
            return TrunkInsideLook(
                model: model,
                rim: .layers([.stripes(angle: 91, period: 9, bands: [TrunkPartBand(from: 0, to: 2, color: rgba(0, 0, 0, 0.10))]),
                              hex(180, [(0x8C5A30, 0), (0x643C1E, 1)])]),
                defaultLining: lining("生成りの帆布", "Natural canvas", .layers(weave + [.solid(TrunkRGBA(0xDCCDA8))])),
                panel: woodH(0x7A4A26, 0x946038), panelName: L("チークの盆", "Teak tray"),
                divider: wood(0x6E4222, 0x946038), dividerName: L("チークの仕切り・真鍮の帯", "Teak divider, brass band"),
                stitch: nil, metal: brass, gildEdge: false, brassBand: true)
        case .starchart:
            return TrunkInsideLook(
                model: model,
                rim: grained(radial(0x283A62, 0x121C38, stop: 0.80, cx: 0.30, cy: 0.18, rx: 1.2, ry: 0.95)),
                defaultLining: lining("紺の絹", "Navy silk", .layers([
                    linear(160, [(rgba(255, 255, 255, 0.08), 0), (rgba(255, 255, 255, 0), 0.35)]),
                    hex(180, [(0x22305A, 0), (0x121A36, 1)])])),
                panel: grained(hex(180, [(0x0C1530, 0), (0x08101F, 1)])),
                panelName: L("紺の革の台・金の押し線", "Navy leather tray, gold tooling"),
                divider: grained(hex(90, [(0x0A1226, 0), (0x1C2C50, 0.5), (0x0A1226, 1)])),
                dividerName: L("紺の革の仕切り・金の縁", "Navy leather divider, gold edge"),
                stitch: rgba(201, 166, 107, 0.6), metal: brass, gildEdge: true, brassBand: false)
        }
    }

    /// 張っている内張り。**内張りの部品を付けていればその布**（台と仕切りは型のまま・板 Linings）、
    /// 無ければ型の既定の内張り（板 InsideModels）
    static func lining(model: TrunkModel, equipped: TrunkEquipped) -> TrunkLining {
        if let id = equipped.lining, let part = TrunkPartCatalog.part(id), case .lining(let paint) = part.look {
            return TrunkLining(name: part.name, paint: paint, partId: part.id)
        }
        return look(model).defaultLining
    }
}

// MARK: - 中に入れるもの

/// ふたの裏のメダルの台の1枠
enum TrunkMedalSlot: Equatable {
    case medal(EarnedBadge)
    /// 留めきれないメダルの数（最後の枠・「ほか N」）
    case more(Int)
    /// 空いている枠（点線の凹み）
    case empty
}

/// 持ち上げた中身
enum TrunkHeld: Equatable {
    case medal(EarnedBadge)
    /// 留めきれないメダル（扇に3枚・「バッジの棚で見る」）
    case more
    case card
    case tickets
}

struct TrunkInsideContents: Equatable {
    /// 持っているメダル（台帳の順・知らない鍵は落としてある）
    let medals: [EarnedBadge]
    /// 会員証を入れるか（**Pro のときだけ**）
    let showsCard: Bool
    /// すれちがい帳に綴じた乗車券の枚数
    let ticketCount: Int

    /// ふたの裏に留められるメダルの数（板の 8 枠）
    static let medalSlots = 8
    /// 内ポケット・仕切りに見せる乗車券の束の枚数
    static let ticketStack = 3

    init(medals: [EarnedBadge], showsCard: Bool, ticketCount: Int) {
        self.medals = medals
        self.showsCard = showsCard
        self.ticketCount = max(0, ticketCount)
    }

    /// 本物の持ち物から作る。メダルは `BadgeCatalog.owned`（台帳の順・絵の無い鍵は出さない）、
    /// 会員証は Pro のときだけ（サポーターの印が残っていても、Pro をやめていたら入れない）
    init(badges: BadgeSet, isPro: Bool, ticketCount: Int) {
        self.init(medals: BadgeCatalog.owned(badges), showsCard: isPro, ticketCount: ticketCount)
    }

    /// 留めきれないメダルの数（9枚以上なら、7枚を留めて残りを「ほか N」）
    var overflow: Int { medals.count > Self.medalSlots ? medals.count - (Self.medalSlots - 1) : 0 }

    /// 留めきれず「ほか N」に入るメダル
    var hiddenMedals: [EarnedBadge] { overflow > 0 ? Array(medals.dropFirst(Self.medalSlots - 1)) : [] }

    /// 8 枠（左上から右へ・2段）
    var slots: [TrunkMedalSlot] {
        (0..<Self.medalSlots).map { i in
            if overflow > 0, i == Self.medalSlots - 1 { return .more(overflow) }
            return medals.indices.contains(i) ? .medal(medals[i]) : .empty
        }
    }

    /// 何も入っていない（空のトランク・板 InsideEmpty）
    var isEmpty: Bool { medals.isEmpty && !showsCard && ticketCount == 0 }

    /// 縫い付けの札（ふたの裏）
    var medalTab: String { medals.isEmpty ? L("メダル", "Medals") : L("メダル \(medals.count)", "Medals \(medals.count)") }

    /// 縫い付けの札（仕切り）
    var ticketTab: String { ticketCount > 0 ? L("乗車券 \(ticketCount)", "Tickets \(ticketCount)") : L("乗車券", "Tickets") }

    /// 「中身を手に取る」で最初に持ち上げるもの（メダル → 会員証 → 乗車券）
    var firstItem: TrunkHeld? {
        if let first = medals.first { return .medal(first) }
        if showsCard { return .card }
        if ticketCount > 0 { return .tickets }
        return nil
    }

    /// トランクの中の読み上げ（「革の旅行鞄の中。内張りは紺の天鵞絨。メダル 10 枚、会員証、乗車券 12 枚」）
    func accessibilityLabel(model: TrunkModel, lining: TrunkLining) -> String {
        var items: [String] = [medals.isEmpty ? L("メダルはまだありません", "no medals yet")
                                              : L("メダル \(medals.count) 枚", "\(medals.count) medals")]
        if showsCard { items.append(L("会員証", "member card")) }
        if ticketCount > 0 { items.append(L("乗車券 \(ticketCount) 枚", "\(ticketCount) tickets")) }
        let name = TrunkText.info(model).name
        return L("\(name)の中。内張りは\(lining.name)。\(items.joined(separator: "、"))",
                 "Inside the \(name). Lined with \(lining.name). \(items.joined(separator: ", "))")
    }

    /// メダルの枠の読み上げ
    static func slotLabel(_ slot: TrunkMedalSlot) -> String {
        switch slot {
        case .medal(let badge):
            let name = BadgeCatalog.fullName(badge.key, tier: badge.tier)
            return L("メダル: \(name)", "Medal: \(name)")
        case .more(let n): return L("ほかのメダル \(n) 枚", "\(n) more medals")
        case .empty: return L("空いている枠", "Empty slot")
        }
    }

    /// 乗車券の束の読み上げ
    var ticketLabel: String { L("すれちがいの乗車券 \(ticketCount) 枚", "\(ticketCount) pass tickets") }

    // MARK: 持ち上げたとき（板 InsideHold）

    func title(_ held: TrunkHeld) -> String {
        switch held {
        case .medal(let badge): return BadgeCatalog.fullName(badge.key, tier: badge.tier)
        case .more: return L("ほかのメダル \(overflow) 枚", "\(overflow) more medals")
        case .card: return L("サポーター証", "Supporter card")
        case .tickets: return L("すれちがいの乗車券", "Pass tickets")
        }
    }

    func subtitle(_ held: TrunkHeld) -> String {
        switch held {
        case .medal:
            return L("押すと、表と裏を指で回して見られます", "Open it to turn it over in your fingers")
        case .more:
            let shown = hiddenMedals.prefix(3).map { BadgeCatalog.name($0.key) }
            let names = shown.joined(separator: L("・", ", ")) + (hiddenMedals.count > 3 ? L(" ほか", " and more") : "")
            return L("\(names)。ふたの裏に留められるのは \(Self.medalSlots) 枚までです",
                     "\(names). The lid holds up to \(Self.medalSlots) medals")
        case .card:
            return L("内ポケットから出しました。押すと表と裏を回せます", "Taken from the inner pocket. Open it to turn it over")
        case .tickets:
            return L("旅先ですれちがった人から届いた \(ticketCount) 枚。帳を開くと、全部を綴じた順に見られます",
                     "\(ticketCount) tickets from people you passed on your travels. Open the book to see them all in order")
        }
    }

    /// 出口のボタンの名前
    func actionTitle(_ held: TrunkHeld) -> String {
        switch held {
        case .medal: return L("メダルを回して見る", "Turn the medal")
        case .more: return L("バッジの棚で見る", "See them on the badge shelf")
        case .card: return L("サポーター証を開く", "Open the supporter card")
        case .tickets: return L("すれちがい帳を開く", "Open the pass book")
        }
    }

    static var putBackTitle: String { L("トランクに戻す", "Put it back") }

    /// 扇に重ねて見せる、留めきれないメダル（3枚）
    var fanMedals: [EarnedBadge] { Array(hiddenMedals.prefix(3)) }
}

// MARK: - 空のトランク（板 InsideEmpty）

enum TrunkInsideEmpty {

    struct Row: Equatable {
        enum Shape: Equatable { case medal, card, ticket }
        let shape: Shape
        let title: String
        let detail: String
    }

    /// 手に入れ方の3行
    static var rows: [Row] {
        [Row(shape: .medal, title: L("メダル · ふたの裏", "Medals · inside the lid"),
             detail: L("写真を1枚投稿すると「最初の一枚」が届きます", "Post one photo and \u{201C}First photo\u{201D} arrives")),
         Row(shape: .card, title: L("会員証 · 内ポケット", "Member card · inner pocket"),
             detail: L("Pro になると、サポーター証がここに入ります", "With Pro, your supporter card goes here")),
         Row(shape: .ticket, title: L("乗車券 · 仕切り", "Tickets · divider"),
             detail: L("旅先ですれちがった人の乗車券が、ここに入ります", "Tickets from people you pass on your travels go here"))]
    }

    static var actionTitle: String { L("写真を投稿する", "Post a photo") }
}
