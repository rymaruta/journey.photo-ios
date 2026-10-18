import SwiftUI

// 旅のトランクの描く部品（モック Trunk・Label の CSS を SwiftUI に移すための小さな道具・2026-10-17）。
// 色と数は `Core/Text/TrunkDesign.swift`・`TrunkLabelDesign.swift`、絵は `TrunkArtwork.swift`。

extension Color {
    /// トランクの色（0〜255 の RGB と不透明度）
    nonisolated init(trunk c: TrunkRGBA) {
        self = Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255).opacity(c.a)
    }
}

enum TrunkPaint {

    /// CSS の `linear-gradient(<角度>deg, …)` を、描く面の大きさに合わせた始まりと終わりで
    static func linear(_ g: TrunkGradient, w: Double, h: Double, fade: (TrunkRGBA) -> TrunkRGBA = { $0 }) -> LinearGradient {
        let e = TrunkGradient.endpoints(angle: g.angle, width: w, height: h)
        return LinearGradient(stops: g.stops.map { Gradient.Stop(color: Color(trunk: fade($0.color)), location: $0.location) },
                              startPoint: UnitPoint(x: e.start.x, y: e.start.y),
                              endPoint: UnitPoint(x: e.end.x, y: e.end.y))
    }

    /// 金具の 135° のグラデーション
    static func metal(_ metal: TrunkMetal, stage st: Double, w: Double, h: Double) -> LinearGradient {
        linear(TrunkGradient(angle: 135, stops: metal.stops(st)), w: w, h: h)
    }

    /// 書き方の並びを `Path` に
    static func path(_ segments: [SVGPath.Segment]) -> Path {
        var p = Path()
        for s in segments {
            switch s {
            case .move(let pt): p.move(to: CGPoint(x: pt.x, y: pt.y))
            case .line(let pt): p.addLine(to: CGPoint(x: pt.x, y: pt.y))
            case let .cubic(c1, c2, to):
                p.addCurve(to: CGPoint(x: to.x, y: to.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
            case let .quad(c, to):
                p.addQuadCurve(to: CGPoint(x: to.x, y: to.y), control: CGPoint(x: c.x, y: c.y))
            case .close: p.closeSubpath()
            }
        }
        return p
    }
}

/// 塗りの面（真鍮・クローム・金箔・木・籐・グラデーション）。大きさを知って CSS と同じ向きで塗る
struct TrunkFillView: View {
    let fill: TrunkFill
    let stage: Double
    let w: Double
    let h: Double

    var body: some View {
        switch fill {
        case .metal(let metal):
            ZStack {
                TrunkPaint.metal(metal, stage: stage, w: w, h: h)
                if metal.hasEngraving {
                    // 金箔の彫り目（`repeating-linear-gradient(45deg, rgba(0,0,0,0.12) 0 1px, transparent 1px 3px)`）
                    TrunkStripes(angle: 45, period: 3, bands: [(0, 1, TrunkRGBA(r: 0, g: 0, b: 0, a: 0.12))])
                }
            }
        case .solid(let c):
            Color(trunk: c)
        case .linear(let g):
            TrunkPaint.linear(g, w: w, h: h)
        case let .wood(edge, middle):
            // 縦の木目（`repeating-linear-gradient(90deg, rgba(0,0,0,0.10) 0 1px, transparent 1px 5px,
            // rgba(0,0,0,0.06) 5px 6px, transparent 6px 11px)`）＋左右から中央へのグラデーション
            ZStack {
                LinearGradient(stops: [Gradient.Stop(color: Color(trunk: edge), location: 0),
                                       Gradient.Stop(color: Color(trunk: middle), location: 0.5),
                                       Gradient.Stop(color: Color(trunk: edge), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                TrunkStripes(angle: 90, period: 11, bands: [(0, 1, TrunkRGBA(r: 0, g: 0, b: 0, a: 0.10)),
                                                             (5, 6, TrunkRGBA(r: 0, g: 0, b: 0, a: 0.06))])
            }
        case let .rattan(a, b):
            // 籐の縁（`repeating-linear-gradient(90deg, a 0 3px, b 3px 4px)`）
            ZStack {
                Color(trunk: a)
                TrunkStripes(angle: 90, period: 4, bands: [(3, 4, b)])
            }
        }
    }
}

/// CSS の `repeating-linear-gradient` の縞（角度は 0=横縞・90=縦縞・そのほかは回した縞）。
/// `bands` は1周期の中の (始まり, 終わり, 色)。塗らない所は透ける
struct TrunkStripes: View {
    let angle: Double
    let period: Double
    let bands: [(Double, Double, TrunkRGBA)]

    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width), h = Double(size.height)
            // 回した縞は対角線ぶん広く描いて回す（中心で回す）
            let reach = (w * w + h * h).squareRoot()
            ctx.translateBy(x: w / 2, y: h / 2)
            // CSS の 0deg は「下から上」へ進む＝縞は横。SwiftUI の回転で縞の向きを合わせる
            ctx.rotate(by: .degrees(angle))
            for band in bands {
                ctx.fill(stripePath(reach: reach, band: band), with: .color(Color(trunk: band.2)))
            }
        }
        .allowsHitTesting(false)
    }

    /// 1つの色の縞を全部まとめた形（下端から周期ごと）
    private func stripePath(reach: Double, band: (Double, Double, TrunkRGBA)) -> Path {
        var p = Path()
        var start = 0.0
        let half = reach / 2
        while start < reach {
            // 下端（+half）から上へ: 周期の始まり start に band.0〜band.1 を塗る
            let bottom = half - start - band.0
            let top = half - start - band.1
            p.addRect(CGRect(x: -half, y: top, width: reach, height: bottom - top))
            start += period
        }
        return p
    }
}

/// 粒（CSS の `radial-gradient(color r1, transparent r2) x y / tile tile`）。点の中心は升の真ん中＋ずらし
struct TrunkGrain: View {
    /// 点の色・升の大きさ・点の半径・ずらし
    let dots: [(color: TrunkRGBA, tile: Double, radius: Double, offset: Double)]

    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width), h = Double(size.height)
            for dot in dots {
                var p = Path()
                var y = dot.tile / 2 + dot.offset
                while y - dot.radius < h {
                    var x = dot.tile / 2 + dot.offset
                    while x - dot.radius < w {
                        p.addEllipse(in: CGRect(x: x - dot.radius, y: y - dot.radius, width: dot.radius * 2, height: dot.radius * 2))
                        x += dot.tile
                    }
                    y += dot.tile
                }
                ctx.fill(p, with: .color(Color(trunk: dot.color)))
            }
        }
        .allowsHitTesting(false)
    }

    /// ラベルの紙の粒（3px の升に、茶の点と白の点を半升ずらして）
    static let paper = TrunkGrain(dots: [(TrunkRGBA(r: 70, g: 45, b: 20, a: 0.10), 3, 0.75, 0),
                                         (TrunkRGBA(r: 255, g: 255, b: 255, a: 0.09), 3, 0.75, 1.5)])
    /// 革の粒（4px の升）
    static let leather = TrunkGrain(dots: [(TrunkRGBA(r: 0, g: 0, b: 0, a: 0.20), 4, 1.0, 0),
                                           (TrunkRGBA(r: 255, g: 255, b: 255, a: 0.05), 4, 1.0, 2)])
}

/// CSS の `radial-gradient(<rx> <ry> at <x> <y>, color, transparent)`。中心から楕円の縁へ消える光やしみ
struct TrunkSpot: View {
    let color: TrunkRGBA
    /// 中心（pt）と半径（pt）
    let x: Double
    let y: Double
    let rx: Double
    let ry: Double
    /// 色が残る所（0〜1）。`transparent 70%` なら 0.7
    var fadeEnd: Double = 1

    var body: some View {
        EllipticalGradient(stops: [Gradient.Stop(color: Color(trunk: color), location: 0),
                                   Gradient.Stop(color: Color(trunk: color.alpha(0)), location: fadeEnd)],
                           center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: max(0.1, rx * 2), height: max(0.1, ry * 2))
            .position(x: x, y: y)
            .allowsHitTesting(false)
    }
}

/// SVG の絵を、枠（viewBox）に合わせて縮めて描く（`preserveAspectRatio` の既定＝真ん中に収める）
struct TrunkArtCanvas: View {
    let strokes: [TrunkArtStroke]
    let viewBox: (w: Double, h: Double)
    var fg: TrunkRGBA = TrunkRGBA(0x000000)
    var bg: TrunkRGBA = TrunkRGBA(0xFFFFFF)
    var ac: TrunkRGBA = TrunkRGBA(0x000000)
    /// 収めずに枠の外まで描く（トランクの胴の絵は胴と同じ大きさ）
    var fit = true

    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width), h = Double(size.height)
            let k = fit ? min(w / viewBox.w, h / viewBox.h) : w / viewBox.w
            ctx.translateBy(x: (w - viewBox.w * k) / 2, y: (h - viewBox.h * k) / 2)
            ctx.scaleBy(x: k, y: k)
            for stroke in strokes {
                let color: TrunkRGBA
                switch stroke.ink {
                case .fg: color = fg
                case .bg: color = bg
                case .ac: color = ac
                case .fixed(let c): color = c
                }
                let shading = GraphicsContext.Shading.color(Color(trunk: color.alpha(color.a * stroke.opacity)))
                let path = TrunkPaint.path(stroke.segments)
                switch stroke.paint {
                case .fill:
                    ctx.fill(path, with: shading)
                case let .stroke(width, round, dashed):
                    ctx.stroke(path, with: shading,
                               style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt, dash: dashed ? [4, 4] : []))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
