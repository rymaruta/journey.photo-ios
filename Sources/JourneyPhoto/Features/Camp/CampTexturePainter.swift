#if canImport(SceneKit)
import UIKit

/// 島の素材に貼る絵（板 Camp の `<pattern>`: 芝の目・帆布の織り目・木目・樹皮・土の粒・岩のすじ）を描く。
///
/// 板は SVG の模様を面に重ねていた。SceneKit では素材の拡散色の絵にする（色ごと焼き込む）。
/// 縫い目・地層の線・ファスナーの点線も、板では線だったものをここで絵に描く（実装の指定「回すときの注意」:
/// 細い線を形にすると数が増えるので、絵の中の線にした）。
/// 描いた絵は色ごとに覚えておく（季節を変えるたびに描き直さない）
@MainActor
enum CampTexturePainter {

    private static var cache: [String: UIImage] = [:]

    /// 板の単位 1 あたりの画素
    static let pixelsPerUnit: CGFloat = 6.4

    nonisolated static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func draw(_ key: String, _ size: CGSize, opaque: Bool = true,
                             _ body: (CGContext, CGSize) -> Void) -> UIImage {
        if let hit = cache[key] { return hit }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            body(ctx.cgContext, size)
        }
        cache[key] = image
        return image
    }

    /// 素材の絵（色つき）。無ければ nil（色だけで塗る）
    static func image(_ texture: CampTexture, color base: UInt32, images: CampCutoutImages) -> UIImage? {
        switch texture {
        case .grass: return grass(base)
        case .soil: return soil(base)
        case .rock: return rock(base)
        case .weave: return weave(base)
        case .fly: return fly(base)
        case .tentFront: return tentFront(base)
        case .bark: return bark(base)
        case .grain: return grain(base)
        case .map: return map(base)
        case let .cutout(id, layer): return images(id, layer) ?? paperPlaceholder()
        }
    }

    // MARK: - 芝・土・岩（島の壁の u は周 40 単位で 1 枚・v は厚み 24）

    /// 芝の目（板の `grass` 模様: 5 × 4 の升に 3 本の短い筋）
    static func grass(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        return draw("grass-\(base)", CGSize(width: 40 * unit, height: 40 * unit)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            g.setStrokeColor(color(0x1D2A10, 0.5).cgColor)
            g.setLineWidth(0.5 * unit)
            g.setLineCap(.round)
            for y in stride(from: CGFloat(0), to: 40, by: 4) {
                for x in stride(from: CGFloat(0), to: 40, by: 5) {
                    for (dx, y0, y1) in [(0.5, 4.0, 1.2), (2.4, 4.0, 0.6), (4.0, 4.0, 1.8)] as [(CGFloat, CGFloat, CGFloat)] {
                        g.move(to: CGPoint(x: (x + dx) * unit, y: (y + y0) * unit))
                        g.addLine(to: CGPoint(x: (x + dx + 0.5) * unit, y: (y + y1) * unit))
                    }
                }
            }
            g.strokePath()
        }
    }

    /// 土の壁（板の `soil` 模様の粒と、地層の線 3 本を y 9 / 14 / 19 に）
    static func soil(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        let h = 24 * unit
        return draw("soil-\(base)", CGSize(width: 40 * unit, height: h)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            for y in stride(from: CGFloat(0), to: 24, by: 7) {
                for x in stride(from: CGFloat(0), to: 40, by: 9) {
                    g.setFillColor(color(0x000000, 0.35 * 0.9).cgColor)
                    g.fillEllipse(in: CGRect(x: (x + 2 - 0.7) * unit, y: (y + 2 - 0.7) * unit, width: 1.4 * unit, height: 1.4 * unit))
                    g.setFillColor(color(0xFFFFFF, 0.12 * 0.9).cgColor)
                    g.fillEllipse(in: CGRect(x: (x + 6.5 - 0.9) * unit, y: (y + 5 - 0.9) * unit, width: 1.8 * unit, height: 1.8 * unit))
                    g.setFillColor(color(0x000000, 0.4 * 0.9).cgColor)
                    g.fillEllipse(in: CGRect(x: (x + 5 - 0.4) * unit, y: (y + 1 - 0.4) * unit, width: 0.8 * unit, height: 0.8 * unit))
                }
            }
            // 地層の線（板: y 9 は明るく 0.8・14 は暗く 0.7・19 は明るく 0.6）
            for (y, c, a, w) in [(9.0, 0xFFE6BE, 0.16, 0.8), (14.0, 0x000000, 0.35, 0.7), (19.0, 0xFFE6BE, 0.12, 0.6)]
                as [(CGFloat, UInt32, CGFloat, CGFloat)] {
                g.setStrokeColor(color(c, a).cgColor)
                g.setLineWidth(w * unit)
                g.move(to: CGPoint(x: 0, y: y * unit))
                var x: CGFloat = 0
                while x <= 40 {
                    g.addLine(to: CGPoint(x: x * unit, y: (y + 0.35 * sin(x * 0.7)) * unit))
                    x += 1
                }
                g.strokePath()
            }
        }
    }

    /// 岩のすじ（板の `rock` 模様: 14 × 10 の升にぎざぎざの線と明るい点）
    static func rock(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        return draw("rock-\(base)", CGSize(width: 28 * unit, height: 20 * unit)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            g.setLineWidth(0.6 * unit)
            for y in stride(from: CGFloat(0), to: 20, by: 10) {
                for x in stride(from: CGFloat(0), to: 28, by: 14) {
                    g.setStrokeColor(color(0x000000, 0.35 * 0.8).cgColor)
                    g.move(to: CGPoint(x: x * unit, y: (y + 6) * unit))
                    g.addLine(to: CGPoint(x: (x + 5) * unit, y: (y + 4) * unit))
                    g.addLine(to: CGPoint(x: (x + 9) * unit, y: (y + 7) * unit))
                    g.addLine(to: CGPoint(x: (x + 14) * unit, y: (y + 5) * unit))
                    g.strokePath()
                    g.setFillColor(color(0xFFFFFF, 0.1 * 0.8).cgColor)
                    g.fillEllipse(in: CGRect(x: (x + 9) * unit, y: (y + 1) * unit, width: 2 * unit, height: 2 * unit))
                }
            }
        }
    }

    // MARK: - 帆布（織り目 3 × 3・縫い目・裾の帯・扉のファスナー）

    private static func weaveLines(_ g: CGContext, _ s: CGSize, unit: CGFloat, strength: CGFloat) {
        g.setLineWidth(0.55 * unit)
        g.setStrokeColor(color(0x000000, 0.45 * strength).cgColor)
        var y: CGFloat = 0.75 * unit
        while y < s.height {
            g.move(to: CGPoint(x: 0, y: y))
            g.addLine(to: CGPoint(x: s.width, y: y))
            y += 1.5 * unit
        }
        g.strokePath()
        g.setLineWidth(0.4 * unit)
        g.setStrokeColor(color(0xFFFFFF, 0.3 * strength).cgColor)
        var x: CGFloat = 0.75 * unit
        while x < s.width {
            g.move(to: CGPoint(x: x, y: 0))
            g.addLine(to: CGPoint(x: x, y: s.height))
            x += 1.5 * unit
        }
        g.strokePath()
    }

    /// 帆布の織り目（妻壁 48 × 38 単位・扉布・椅子の布）
    static func weave(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        return draw("weave-\(base)", CGSize(width: 48 * unit, height: 38 * unit)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            weaveLines(g, s, unit: unit, strength: 0.2)
        }
    }

    /// 扉のある妻壁（u = (x + 24) / 48・v = −y / 38）。扉の縁のファスナー（点線）と、妻壁の縁の濃い線
    static func tentFront(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        let w = 48 * unit, h = 38 * unit
        return draw("front-\(base)", CGSize(width: w, height: h)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            weaveLines(g, s, unit: unit, strength: 0.2)
            func p(_ lx: Double, _ ly: Double) -> CGPoint {
                CGPoint(x: CGFloat((lx + CampTentSpec.halfWidth) / (2 * CampTentSpec.halfWidth)) * w,
                        y: CGFloat(-ly / CampTentSpec.height) * h)
            }
            // 妻壁の縁（板: 0.8・30% 暗く）
            g.setStrokeColor(color(CampMaterials.mix(base, 0x000000, 0.3)).cgColor)
            g.setLineWidth(1.6 * unit)
            g.move(to: p(-CampTentSpec.halfWidth, 0))
            g.addLine(to: p(0, CampTentSpec.wallTop))
            g.addLine(to: p(CampTentSpec.halfWidth, 0))
            g.strokePath()
            // 扉の縁のファスナー（板: #3a2a1a・0.5・点線 0.6）。扉の縁から少し外
            g.setStrokeColor(color(0x3A2A1A).cgColor)
            g.setLineWidth(0.5 * unit)
            g.setLineDash(phase: 0, lengths: [0.6 * unit, 0.6 * unit])
            g.move(to: p(-CampTentSpec.doorHalf - 0.8, 0))
            g.addLine(to: p(0, CampTentSpec.doorTop - 0.9))
            g.addLine(to: p(CampTentSpec.doorHalf + 0.8, 0))
            g.strokePath()
        }
    }

    /// フライ（u は長さ 66 単位・v は裾 0 → 棟 1）。縫い目（横 2 本・縦 2 本と明るい縫い糸の点線）と裾の濃い帯
    static func fly(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        let w = 66 * unit, h = 47 * unit
        return draw("fly-\(base)", CGSize(width: w, height: h)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            weaveLines(g, s, unit: unit, strength: 0.2)
            // 裾の濃い帯（板: フライの色を 40% 暗くした 1.8 の線）
            g.setFillColor(color(CampMaterials.mix(base, 0x000000, 0.4)).cgColor)
            g.fill(CGRect(x: 0, y: 0, width: w, height: 1.8 * unit))
            // 横の縫い目（v = 1/3・2/3）
            g.setStrokeColor(color(0x000000, 0.22).cgColor)
            g.setLineWidth(0.45 * unit)
            for k in [1.0, 2.0] as [CGFloat] {
                g.move(to: CGPoint(x: 0, y: h * k / 3))
                g.addLine(to: CGPoint(x: w, y: h * k / 3))
            }
            g.strokePath()
            // 縦の縫い目（u = 0.4・0.8）と、明るい縫い糸
            for u in [0.4, 0.8] as [CGFloat] {
                g.setStrokeColor(color(0x000000, 0.25).cgColor)
                g.setLineWidth(0.5 * unit)
                g.setLineDash(phase: 0, lengths: [])
                g.move(to: CGPoint(x: w * u, y: 0))
                g.addLine(to: CGPoint(x: w * u, y: h))
                g.strokePath()
                g.setStrokeColor(color(0xFFF0D2, 0.45).cgColor)
                g.setLineWidth(0.35 * unit)
                g.setLineDash(phase: 0, lengths: [0.9 * unit, 0.9 * unit])
                g.move(to: CGPoint(x: w * u + 0.6 * unit, y: 0))
                g.addLine(to: CGPoint(x: w * u + 0.6 * unit, y: h))
                g.strokePath()
            }
            g.setLineDash(phase: 0, lengths: [])
        }
    }

    // MARK: - 木（樹皮・木目）と地図

    /// 樹皮の縦の筋（板の `bark` 模様 4 × 10）
    static func bark(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        return draw("bark-\(base)", CGSize(width: 16 * unit, height: 20 * unit)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            g.setStrokeColor(color(0x000000, 0.5 * 0.7).cgColor)
            g.setLineWidth(0.5 * unit)
            for x0 in stride(from: CGFloat(0), to: 16, by: 4) {
                for y0 in stride(from: CGFloat(0), to: 20, by: 10) {
                    for (a, b, c) in [(1.0, 1.6, 0.6), (3.0, 3.5, 2.6)] as [(CGFloat, CGFloat, CGFloat)] {
                        g.move(to: CGPoint(x: (x0 + a) * unit, y: y0 * unit))
                        g.addCurve(to: CGPoint(x: (x0 + a + 0.2) * unit, y: (y0 + 10) * unit),
                                   control1: CGPoint(x: (x0 + b) * unit, y: (y0 + 3) * unit),
                                   control2: CGPoint(x: (x0 + c) * unit, y: (y0 + 6) * unit))
                    }
                }
            }
            g.strokePath()
        }
    }

    /// 木目（板の `grain` 模様 40 × 6）
    static func grain(_ base: UInt32) -> UIImage {
        let unit = pixelsPerUnit
        return draw("grain-\(base)", CGSize(width: 40 * unit, height: 12 * unit)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            g.setStrokeColor(color(0x2A1608, 0.7 * 0.55).cgColor)
            g.setLineWidth(0.5 * unit)
            for y0 in [0.0, 6.0] as [CGFloat] {
                g.move(to: CGPoint(x: 0, y: (y0 + 1.5) * unit))
                g.addCurve(to: CGPoint(x: 40 * unit, y: (y0 + 1.4) * unit), control1: CGPoint(x: 10 * unit, y: (y0 + 0.8) * unit),
                           control2: CGPoint(x: 20 * unit, y: (y0 + 2.4) * unit))
                g.move(to: CGPoint(x: 0, y: (y0 + 4.2) * unit))
                g.addCurve(to: CGPoint(x: 40 * unit, y: (y0 + 4) * unit), control1: CGPoint(x: 12 * unit, y: (y0 + 3.6) * unit),
                           control2: CGPoint(x: 26 * unit, y: (y0 + 5) * unit))
            }
            g.strokePath()
        }
    }

    /// 机の上の、道を描いた地図（板: 赤の点線の道・青い線）
    static func map(_ base: UInt32) -> UIImage {
        draw("map-\(base)", CGSize(width: 96, height: 72)) { g, s in
            g.setFillColor(color(base).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
            g.setStrokeColor(color(0xB9452A).cgColor)
            g.setLineWidth(3)
            g.setLineDash(phase: 0, lengths: [6, 5])
            g.move(to: CGPoint(x: 8, y: 22))
            g.addLine(to: CGPoint(x: 38, y: 34))
            g.addLine(to: CGPoint(x: 70, y: 28))
            g.addLine(to: CGPoint(x: 82, y: 56))
            g.strokePath()
            g.setLineDash(phase: 0, lengths: [])
            g.setStrokeColor(color(0x6A8AA8).cgColor)
            g.setLineWidth(3.5)
            g.move(to: CGPoint(x: 4, y: 52))
            g.addLine(to: CGPoint(x: 44, y: 68))
            g.strokePath()
        }
    }

    // MARK: - 光と輪

    /// 柔らかく光る輪（板の `warm`: #ffe0a0 .95 → #ffab55 .45（30%）→ #ff8a30 0）
    static func warmGlow() -> UIImage {
        draw("warm", CGSize(width: 128, height: 128), opaque: false) { g, s in
            let colors = [color(0xFFE0A0, 0.95).cgColor, color(0xFFAB55, 0.45).cgColor, color(0xFF8A30, 0).cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 1])
            else { return }
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: s.width / 2, options: [])
        }
    }

    /// 置く前の影（楕円・ぼかし 6・黒 45%）
    static func softShadow() -> UIImage {
        draw("softShadow", CGSize(width: 128, height: 128), opaque: false) { g, s in
            let colors = [color(0x000000, 0.45).cgColor, color(0x000000, 0.3).cgColor, color(0x000000, 0).cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.62, 1])
            else { return }
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: s.width / 2 - 1, options: [])
        }
    }

    /// 置く場所の点線の輪（#F3DCA6・太さ 1.4・点線 3 / 2.4）。輪は絵の縁いっぱい
    static func placeRing(rx: Double, rz: Double) -> UIImage {
        let unit: CGFloat = 4
        let w = CGFloat(rx * 2) * unit + 8, h = CGFloat(rz * 2) * unit + 8
        return draw("ring-\(rx)-\(rz)", CGSize(width: w, height: h), opaque: false) { g, _ in
            g.setStrokeColor(color(0xF3DCA6).cgColor)
            g.setLineWidth(1.4 * unit)
            g.setLineDash(phase: 0, lengths: [3 * unit, 2.4 * unit])
            g.strokeEllipse(in: CGRect(x: 4, y: 4, width: w - 8, height: h - 8))
        }
    }

    /// 火の粉・煙の粒（丸くぼけた白）
    static func softDot() -> UIImage {
        draw("dot", CGSize(width: 32, height: 32), opaque: false) { g, s in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: s.width / 2, options: [])
        }
    }

    /// 炎の 3 層（板の `flame` の path をそのまま・幅 68 × 高さ 100 の枠・下の真ん中が根元）
    static func flame(layer: Int) -> UIImage {
        draw("flame-\(layer)", CGSize(width: 136, height: 200), opaque: false) { g, _ in
            g.translateBy(x: 68, y: 200)
            g.scaleBy(x: 2, y: 2)
            let path = UIBezierPath()
            switch layer {
            case 0:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addCurve(to: CGPoint(x: -18, y: -52), controlPoint1: CGPoint(x: -30, y: -4), controlPoint2: CGPoint(x: -34, y: -30))
                path.addCurve(to: CGPoint(x: -6, y: -50), controlPoint1: CGPoint(x: -14, y: -38), controlPoint2: CGPoint(x: -6, y: -40))
                path.addCurve(to: CGPoint(x: 4, y: -100), controlPoint1: CGPoint(x: -6, y: -70), controlPoint2: CGPoint(x: 6, y: -84))
                path.addCurve(to: CGPoint(x: 30, y: -36), controlPoint1: CGPoint(x: 20, y: -78), controlPoint2: CGPoint(x: 34, y: -62))
                path.addCurve(to: CGPoint(x: 0, y: 0), controlPoint1: CGPoint(x: 28, y: -16), controlPoint2: CGPoint(x: 18, y: -2))
                color(0xE2572B, 0.85).setFill()
            case 1:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addCurve(to: CGPoint(x: -10, y: -38), controlPoint1: CGPoint(x: -20, y: -3), controlPoint2: CGPoint(x: -22, y: -22))
                path.addCurve(to: CGPoint(x: 0, y: -40), controlPoint1: CGPoint(x: -6, y: -28), controlPoint2: CGPoint(x: 0, y: -30))
                path.addCurve(to: CGPoint(x: 10, y: -72), controlPoint1: CGPoint(x: 2, y: -54), controlPoint2: CGPoint(x: 10, y: -60))
                path.addCurve(to: CGPoint(x: 18, y: -18), controlPoint1: CGPoint(x: 22, y: -54), controlPoint2: CGPoint(x: 24, y: -34))
                path.addCurve(to: CGPoint(x: 0, y: 0), controlPoint1: CGPoint(x: 14, y: -6), controlPoint2: CGPoint(x: 8, y: 0))
                color(0xFFAD42).setFill()
            default:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addCurve(to: CGPoint(x: -4, y: -24), controlPoint1: CGPoint(x: -10, y: -2), controlPoint2: CGPoint(x: -11, y: -14))
                path.addCurve(to: CGPoint(x: 3, y: -30), controlPoint1: CGPoint(x: -1, y: -18), controlPoint2: CGPoint(x: 3, y: -22))
                path.addCurve(to: CGPoint(x: 8, y: -4), controlPoint1: CGPoint(x: 10, y: -22), controlPoint2: CGPoint(x: 12, y: -10))
                path.addCurve(to: CGPoint(x: 0, y: 0), controlPoint1: CGPoint(x: 6, y: -1), controlPoint2: CGPoint(x: 3, y: 0))
                color(0xFFF3C4).setFill()
            }
            path.close()
            path.fill()
        }
    }

    /// 紙の絵が読めないときの代わり（生成りの紙）
    static func paperPlaceholder() -> UIImage {
        draw("paper", CGSize(width: 16, height: 16)) { g, s in
            g.setFillColor(color(0xF7F4EC).cgColor)
            g.fill(CGRect(origin: .zero, size: s))
        }
    }

    /// 映り込みの空（板の `env`: 上・地平・地面の近く・地面の下）。金属が黒く沈まないように
    static func environment(_ time: CampTime, season: CampSeason) -> UIImage {
        let env: [UInt32]
        switch time {
        case .morning: env = [0x7C98B4, 0xF0DCC0, 0x7A7258, 0x2E2A22]
        case .day: env = [0x4F7AA2, 0xD9E6EE, 0x6C7A52, 0x2A3020]
        case .evening: env = [0x2E3A5C, 0xF0A466, 0x6A4A36, 0x22180F]
        case .night: env = [0x0B1424, 0x1E2C48, 0x141A22, 0x06080B]
        }
        return draw("env-\(time.rawValue)-\(season.rawValue)", CGSize(width: 256, height: 128)) { g, s in
            let colors = env.map { color($0).cgColor } as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 0.52, 1])
            else { return }
            g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
        }
    }
}
#endif
