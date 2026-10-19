import SwiftUI

/// 図鑑の部品の絵（板 CampDex の 120 × 96 の SVG をそのまま描く）。
///
/// まだ持っていない部品は**白 10% の一色の影絵**（形だけ・色と質感は出さない。旅のトランクの部品箱と同じ
/// owner の決まり `TrunkPartsBoxText.missingShadowOpacity`・2026-10-17）。影絵には足元の影（濃さ 0.6 未満の形）を入れない
struct CampPartArtView: View {
    let id: String
    var silhouette = false

    var body: some View {
        if silhouette {
            Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity)
                .mask { CampPartArtCanvas(elements: CampDexArt.elements(for: id), solid: true) }
                .aspectRatio(CGFloat(CampDexArt.viewBox.x / CampDexArt.viewBox.y), contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            CampPartArtCanvas(elements: CampDexArt.elements(for: id), solid: false)
                .aspectRatio(CGFloat(CampDexArt.viewBox.x / CampDexArt.viewBox.y), contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}

/// 絵を描く面（`solid` は影絵の型: 全部を白で塗り、足元の影を外す）
struct CampPartArtCanvas: View {
    let elements: [CampArtElement]
    let solid: Bool

    var body: some View {
        Canvas { context, size in
            let k = Double(size.width) / CampDexArt.viewBox.x
            for e in elements {
                if solid && e.opacity < 0.6 { continue }
                let path = Self.path(e.shape, k: k)
                var ctx = context
                ctx.opacity = solid ? 1 : e.opacity
                if let fill = e.fill {
                    ctx.fill(path, with: solid ? .color(.white) : Self.shading(fill, bounds: e.bounds, k: k))
                }
                if let stroke = e.stroke {
                    let style = StrokeStyle(lineWidth: e.strokeWidth * k, lineCap: .round, lineJoin: .round,
                                            dash: e.dash.map { CGFloat($0 * k) })
                    ctx.stroke(path, with: solid ? .color(.white) : Self.shading(stroke, bounds: e.bounds, k: k), style: style)
                }
            }
        }
    }

    static func path(_ shape: CampArtElement.Shape, k: Double) -> Path {
        switch shape {
        case .path(let segments):
            return TrunkPaint.path(segments.map { scale($0, k) })
        case let .ellipse(cx, cy, rx, ry):
            var p = Path()
            p.addEllipse(in: CGRect(x: (cx - rx) * k, y: (cy - ry) * k, width: 2 * rx * k, height: 2 * ry * k))
            return p
        case let .rect(x, y, w, h, rx):
            var p = Path()
            p.addRoundedRect(in: CGRect(x: x * k, y: y * k, width: w * k, height: h * k),
                             cornerSize: CGSize(width: rx * k, height: rx * k))
            return p
        }
    }

    private static func scale(_ s: SVGPath.Segment, _ k: Double) -> SVGPath.Segment {
        func m(_ p: SVGPath.Point) -> SVGPath.Point { SVGPath.Point(x: p.x * k, y: p.y * k) }
        switch s {
        case .move(let p): return .move(m(p))
        case .line(let p): return .line(m(p))
        case let .cubic(c1, c2, to): return .cubic(c1: m(c1), c2: m(c2), to: m(to))
        case let .quad(c, to): return .quad(c: m(c), to: m(to))
        case .close: return .close
        }
    }

    /// 塗り（色か、板の階調を形の枠に合わせて）
    static func shading(_ paint: CampArtPaint, bounds b: (x: Double, y: Double, w: Double, h: Double), k: Double)
        -> GraphicsContext.Shading {
        switch paint {
        case .color(let hex):
            return .color(CampPalette.color(hex))
        case .gradient(let name):
            guard let g = CampDexArt.gradients[name] else { return .color(.black) }
            let gradient = Gradient(stops: g.stops.map { Gradient.Stop(color: CampPalette.color($0.1, $0.2), location: $0.0) })
            switch g.kind {
            case let .linear(x1, y1, x2, y2):
                return .linearGradient(gradient,
                                       startPoint: CGPoint(x: (b.x + x1 * b.w) * k, y: (b.y + y1 * b.h) * k),
                                       endPoint: CGPoint(x: (b.x + x2 * b.w) * k, y: (b.y + y2 * b.h) * k))
            case let .radial(cx, cy, r):
                return .radialGradient(gradient, center: CGPoint(x: (b.x + cx * b.w) * k, y: (b.y + cy * b.h) * k),
                                       startRadius: 0, endRadius: CGFloat(r * max(b.w, b.h) * k))
            }
        }
    }
}
