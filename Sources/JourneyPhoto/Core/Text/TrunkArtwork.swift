import Foundation

// ラベルとトランクの絵（モック Label.dc.html の 22 の絵・Trunk.dc.html の金蒔絵・羅針盤・星図）。
// **SVG の書き方を文字のまま写した**（数字を手で書き換えない）。画面は `SVGPath` で読んで描く。

/// 絵の1筆（塗るか、線を引くか）
struct TrunkArtStroke: Equatable {
    /// どの色で描くか。ラベルは刷りの色・紙の地・差し色、トランクの絵は決まった色
    enum Ink: Equatable {
        case fg, bg, ac
        case fixed(TrunkRGBA)
    }

    enum Paint: Equatable {
        case fill
        /// `dashed` はモックの `stroke-dasharray="4 4"`（空の便の点線だけ）
        case stroke(width: Double, round: Bool, dashed: Bool)
    }

    let segments: [SVGPath.Segment]
    let ink: Ink
    let paint: Paint
    let opacity: Double

    init(_ segments: [SVGPath.Segment], _ ink: Ink, _ paint: Paint = .fill, opacity: Double = 1) {
        self.segments = segments
        self.ink = ink
        self.paint = paint
        self.opacity = opacity
    }

    init(_ d: String, _ ink: Ink, _ paint: Paint = .fill, opacity: Double = 1) {
        self.init(SVGPath.parse(d), ink, paint, opacity: opacity)
    }
}

enum TrunkArtwork {

    private typealias S = TrunkArtStroke

    private static func circle(_ cx: Double, _ cy: Double, _ r: Double, _ ink: S.Ink,
                               _ paint: S.Paint = .fill, opacity: Double = 1) -> S {
        S(SVGPath.circle(cx: cx, cy: cy, r: r), ink, paint, opacity: opacity)
    }

    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ ink: S.Ink, r: Double = 0) -> S {
        S(SVGPath.rect(x: x, y: y, w: w, h: h, r: r), ink)
    }

    private static func line(_ width: Double, round: Bool = false, dashed: Bool = false) -> S.Paint {
        .stroke(width: width, round: round, dashed: dashed)
    }

    /// ラベルの絵の枠（モックの `viewBox="0 0 120 48"`）
    static let labelViewBox = (w: 120.0, h: 48.0)

    // swiftlint:disable:next function_body_length
    static func strokes(_ art: TrunkLabelArt) -> [TrunkArtStroke] {
        switch art {
        case .fuji:
            return [circle(88, 16, 9, .ac),
                    S("M8 46 L48 10 L56 14 L64 10 L112 46 Z", .fg),
                    S("M40 17 L48 10 L56 14 L64 10 L72 17 L64 15 L58 20 L52 15 L46 20 Z", .bg)]
        case .pagoda:
            return [rect(58, 2, 4, 8, .fg),
                    S("M42 12 L78 12 L72 9 L48 9 Z M38 22 L82 22 L75 18 L45 18 Z M34 33 L86 33 L78 28 L42 28 Z M30 45 L90 45 L81 39 L39 39 Z", .fg),
                    rect(52, 12, 16, 6, .ac), rect(49, 22, 22, 6, .ac), rect(46, 33, 28, 6, .ac)]
        case .wave:
            return [S("M0 46 C12 30 26 22 40 26 C30 30 30 38 40 40 C52 30 64 14 86 16 C74 20 70 30 78 34 C90 26 104 26 120 34 L120 48 L0 48 Z", .fg),
                    S("M44 38 C52 32 58 30 64 31 M80 32 C88 28 96 28 104 31", .bg, line(2, round: true)),
                    circle(22, 12, 7, .ac)]
        case .sun:
            return [S("M30 40 A30 30 0 0 1 90 40 Z", .ac),
                    S("M60 4 L60 0 M38 10 L35 6 M82 10 L85 6 M24 22 L19 20 M96 22 L101 20", .ac, line(3, round: true)),
                    rect(0, 40, 120, 3, .fg), rect(18, 45, 84, 2, .fg)]
        case .skyline:
            return [S("M58 46 L60 2 L62 46 Z M52 46 L60 22 L68 46 Z", .fg),
                    S("M4 46 V30 H16 V24 H26 V46 Z M30 46 V34 H44 V46 Z M76 46 V28 H88 V20 H96 V46 Z M100 46 V32 H116 V46 Z", .fg),
                    circle(98, 10, 5, .ac)]
        case .snow:
            return [S("M60 4 V44 M42 14 L78 34 M42 34 L78 14", .fg, line(3, round: true)),
                    S("M54 8 L60 14 L66 8 M54 40 L60 34 L66 40", .fg, line(3, round: true)),
                    circle(22, 18, 3, .ac), circle(98, 30, 3, .ac), circle(16, 38, 2, .ac)]
        case .aurora:
            return [S("M0 26 C20 6 40 30 60 12 C80 -2 100 22 120 8", .ac, line(6), opacity: 0.9),
                    S("M0 34 C24 18 42 38 64 22 C84 10 100 30 120 20", .ac, line(3), opacity: 0.6),
                    S("M0 48 L14 36 L22 42 L34 30 L46 42 L58 34 L72 44 L86 32 L100 42 L120 36 L120 48 Z", .fg)]
        case .plane:
            return [S("M14 26 L100 22 C110 22 112 26 104 28 L64 30 L46 46 L38 46 L48 30 L26 31 L18 38 L12 38 L16 28 Z", .fg),
                    S("M58 22 L44 6 L52 6 L74 22 Z", .fg),
                    S("M0 40 C30 36 50 44 80 40", .ac, line(2, dashed: true))]
        case .ship:
            return [S("M8 32 L112 32 L100 44 L18 44 Z", .fg),
                    rect(24, 22, 68, 10, .fg),
                    rect(38, 8, 10, 14, .ac), rect(58, 8, 10, 14, .ac), rect(78, 12, 8, 10, .ac),
                    S("M0 47 C10 44 20 50 30 47 C40 44 50 50 60 47 C70 44 80 50 90 47 C100 44 110 50 120 47", .fg, line(1.5))]
        case .train:
            return [S("M12 38 V22 H40 V12 H60 V22 H84 L96 30 V38 Z", .fg),
                    rect(66, 8, 8, 14, .fg),
                    circle(26, 40, 6, .ac), circle(50, 40, 6, .ac), circle(78, 41, 5, .ac),
                    S("M70 6 C78 -2 92 4 100 0 C108 -2 114 2 120 0", .fg, line(3), opacity: 0.6),
                    rect(0, 46, 120, 2, .fg)]
        case .torii:
            return [S("M18 8 C40 12 80 12 102 8 L100 14 C80 17 40 17 20 14 Z", .ac),
                    rect(26, 20, 68, 4, .ac),
                    rect(34, 14, 6, 34, .ac), rect(80, 14, 6, 34, .ac),
                    S("M0 44 C20 38 40 42 60 40 C80 38 100 42 120 38 L120 48 L0 48 Z", .fg, opacity: 0.5)]
        case .sakura:
            return [circle(30, 24, 12, .ac), circle(60, 16, 9, .ac), circle(88, 26, 11, .ac),
                    circle(30, 24, 3, .fg), circle(60, 16, 2.5, .fg), circle(88, 26, 3, .fg),
                    S("M4 44 C30 36 60 46 116 36", .fg, line(3, round: true))]
        case .maple:
            return [S("M60 2 L66 16 L80 10 L74 24 L90 26 L76 34 L80 44 L64 38 L62 48 L58 48 L56 38 L40 44 L44 34 L30 26 L46 24 L40 10 L54 16 Z", .ac)]
        case .lighthouse:
            return [S("M54 12 H66 L70 46 H50 Z", .fg),
                    rect(52, 22, 16, 4, .bg), rect(51, 34, 18, 4, .bg),
                    S("M56 4 H64 V12 H56 Z", .ac),
                    S("M64 8 L118 0 L118 16 Z M56 8 L2 0 L2 16 Z", .ac, opacity: 0.45),
                    S("M0 47 C20 44 40 48 60 46 C80 44 100 48 120 46", .fg, line(2))]
        case .moon:
            return [S("M70 4 A20 20 0 1 0 86 34 A16 16 0 1 1 70 4 Z", .ac),
                    circle(24, 10, 1.8, .ac), circle(40, 22, 1.4, .ac), circle(104, 12, 1.6, .ac),
                    S("M0 48 V38 H10 V30 H18 V40 H30 V34 H40 V48 Z M92 48 V36 H102 V28 H110 V40 H120 V48 Z", .fg)]
        case .star:
            return [S("M60 2 L66 18 L84 18 L70 28 L76 46 L60 35 L44 46 L50 28 L36 18 L54 18 Z", .ac),
                    circle(24, 30, 2, .fg), circle(98, 14, 2, .fg)]
        case .rain:
            return [S("M34 24 C30 24 26 20 28 15 C30 10 36 9 40 11 C42 4 52 1 60 4 C66 0 78 2 80 10 C88 9 94 15 92 22 Z", .fg),
                    S("M38 30 L34 40 M50 30 L46 42 M62 30 L58 40 M74 30 L70 42 M86 30 L82 40", .ac, line(2.4, round: true))]
        case .fog:
            return [S("M30 26 L48 8 L60 18 L70 10 L92 26 Z", .fg, opacity: 0.55),
                    S("M8 28 H70 M80 28 H112 M18 36 H50 M60 36 H104 M4 44 H84 M92 44 H116", .ac, line(3, round: true))]
        case .cloud:
            return [S("M20 22 L40 6 L52 16 L64 4 L90 22 Z", .fg),
                    S("M0 34 C10 24 22 26 28 30 C34 22 48 22 54 30 C62 22 78 24 82 30 C90 24 104 24 120 32 L120 48 L0 48 Z", .ac)]
        case .camera:
            return [rect(34, 12, 52, 32, .fg, r: 4),
                    rect(44, 6, 16, 8, .fg, r: 2),
                    circle(60, 28, 11, .bg), circle(60, 28, 7, .ac),
                    circle(78, 18, 2.4, .ac)]
        case .globe:
            return [circle(60, 24, 20, .fg, line(3)),
                    S("M40 24 H80 M60 4 C50 12 50 36 60 44 M60 4 C70 12 70 36 60 44", .fg, line(2)),
                    S("M92 10 L96 16 L103 17 L98 22 L99 29 L92 26 L86 29 L87 22 L82 17 L89 16 Z", .ac)]
        case .firework:
            return [S("M60 22 L60 4 M60 22 L76 10 M60 22 L80 24 M60 22 L74 36 M60 22 L46 36 M60 22 L40 24 M60 22 L44 10", .ac,
                      line(2.4, round: true)),
                    circle(60, 2, 2, .ac), circle(78, 9, 2, .ac), circle(82, 24, 2, .ac), circle(38, 24, 2, .ac), circle(42, 9, 2, .ac),
                    S("M0 48 L0 42 C30 40 90 40 120 42 L120 48 Z", .fg)]
        }
    }

    // MARK: トランクの絵（胴の 360×268 の上）

    private static let gold = TrunkRGBA(0xD9B566)
    private static let goldDot = TrunkRGBA(0xE3C27A)

    static func strokes(_ art: TrunkArt) -> [TrunkArtStroke] {
        switch art {
        case .makie:
            let waves = S("M-10 230 C20 205 50 205 70 222 C55 214 44 222 50 232 C70 214 100 208 124 226 C108 218 98 226 104 236 C126 218 158 212 182 230 C166 222 156 230 162 240 C184 222 216 216 240 234 C224 226 214 234 220 244 C242 226 274 220 298 238 C282 230 272 238 278 248 C300 230 332 224 370 244",
                          .fixed(gold), line(1.4), opacity: 0.95)
            let swell1 = S("M-10 250 C30 232 70 236 100 250 C130 236 170 232 200 250 C230 236 270 232 300 250 C330 236 350 236 370 248",
                           .fixed(gold), line(1.4), opacity: 0.95 * 0.7)
            let swell2 = S("M-10 262 C30 248 70 252 100 262 C130 248 170 248 200 262 C230 248 270 248 300 262 C330 250 350 250 370 260",
                           .fixed(gold), line(1.4), opacity: 0.95 * 0.5)
            let dots: [(Double, Double, Double)] = [(40, 120, 1.2), (62, 134, 0.9), (300, 110, 1.3), (318, 128, 0.8),
                                                    (276, 140, 1), (90, 150, 0.8), (210, 118, 0.9), (150, 140, 1.1)]
            return [waves, swell1, swell2]
                + dots.map { circle($0.0, $0.1, $0.2, .fixed(goldDot)) }
                + [circle(300, 44, 16, .fixed(gold), line(1.2)),
                   S("M300 28 C306 36 306 52 300 60 C294 52 294 36 300 28 Z M284 44 C292 38 308 38 316 44 C308 50 292 50 284 44 Z",
                     .fixed(gold), line(1.2))]
        case .compass:
            // 中心 (180, 40) に置く（モックの `translate(180 40)`）
            func at(_ d: String) -> [SVGPath.Segment] { SVGPath.translate(SVGPath.parse(d), dx: 180, dy: 40) }
            return [circle(180, 40, 27, .fixed(TrunkRGBA(0xC9A66B)), line(2)),
                    circle(180, 40, 22, .fixed(TrunkRGBA(0x8E7040)), line(1)),
                    S(at("M0 -26 L5 -5 L0 0 L-5 -5 Z"), .fixed(TrunkRGBA(0xE3C98F))),
                    S(at("M0 26 L5 5 L0 0 L-5 5 Z"), .fixed(TrunkRGBA(0x8E7040))),
                    S(at("M-26 0 L-5 -5 L0 0 L-5 5 Z"), .fixed(TrunkRGBA(0x8E7040))),
                    S(at("M26 0 L5 -5 L0 0 L5 5 Z"), .fixed(TrunkRGBA(0xE3C98F))),
                    S(at("M-14 -14 L-2 -3 M14 -14 L2 -3 M-14 14 L-2 3 M14 14 L2 3"), .fixed(TrunkRGBA(0xC9A66B)), line(1.2)),
                    circle(180, 40, 2.2, .fixed(TrunkRGBA(0x3A2A14)))]
        case .stars:
            let lineInk = TrunkArtStroke.Ink.fixed(TrunkRGBA(0xC9A66B))
            let lines = ["M40 36 L96 58 L150 30 L212 52 L268 24 L322 46",
                         "M96 58 L120 104 L190 118 L246 96 L268 24",
                         "M190 118 L178 176 L240 206 L300 182 L246 96",
                         "M120 104 L70 168 L120 222"].map { S($0, lineInk, line(0.9), opacity: 0.85) }
            let stars: [(Double, Double, Double)] = [(40, 36, 2), (96, 58, 2.6), (150, 30, 1.8), (212, 52, 2.2), (268, 24, 3),
                                                     (322, 46, 1.8), (120, 104, 2.4), (190, 118, 2), (246, 96, 2.6),
                                                     (178, 176, 2), (240, 206, 2.8), (300, 182, 2), (70, 168, 2.2), (120, 222, 1.8)]
            return lines + stars.map { circle($0.0, $0.1, $0.2, .fixed(TrunkRGBA(0xE3C98F))) }
        }
    }

}
