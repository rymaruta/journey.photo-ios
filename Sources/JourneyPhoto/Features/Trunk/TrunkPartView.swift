import SwiftUI
import AudioToolbox

/// 部品1点（モック Part.dc.html・96×96 の枠・2026-10-17 次の版）。手順は `TrunkPartDrawing`、
/// ここは上から順に Canvas で塗り、字だけを SwiftUI の字で重ねる。
///
/// **金属・紙・布に刷った物として描く**（字は Dynamic Type で伸ばさない）。読み上げは呼ぶ側が付ける
struct TrunkPartView: View {
    let part: TrunkPart
    /// 置く大きさ（96 の枠をこの幅に）
    var size: Double = 96
    /// 部品の落とす影（モックの `drop-shadow(0 4px 4px rgba(0,0,0,0.55))`）
    var shadow = true

    var body: some View {
        let ops = TrunkPartDrawing.ops(part)
        let k = size / TrunkPartDrawing.size
        ZStack(alignment: .topLeading) {
            // 大きく置いてもぼけないよう、Canvas は置く大きさで描いて中で縮める
            Canvas { ctx, _ in
                ctx.scaleBy(x: k, y: k)
                TrunkPartRenderer.draw(ops, in: &ctx)
            }
            .frame(width: size, height: size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(TrunkPartDrawing.textColumns(ops).enumerated()), id: \.offset) { _, column in
                    TrunkPartTextColumnView(column: column)
                }
            }
            .frame(width: TrunkPartDrawing.size, height: TrunkPartDrawing.size, alignment: .topLeading)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: size, height: size, alignment: .topLeading)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .shadow(color: Color.black.opacity(shadow ? 0.55 : 0), radius: 2 * k, x: 0, y: 4 * k)
        .accessibilityHidden(true)
    }
}

/// 部品の塗り（トランクの持ち手・角・錠前を部品の面で塗る・`PartsOnTrunk`）
struct TrunkPartPaintView: View {
    let paint: TrunkPartPaint

    var body: some View {
        Canvas { ctx, size in
            TrunkPartRenderer.paint(paint, TrunkRect(x: 0, y: 0, w: Double(size.width), h: Double(size.height)), in: &ctx)
        }
        .allowsHitTesting(false)
    }
}

/// 字の並び（紙のタグ・ワッペンの刺繍・鍵の札・錠前の数字）
private struct TrunkPartTextColumnView: View {
    let column: TrunkPartTextColumn

    var body: some View {
        let c = column.transform.apply(SVGPath.Point(x: column.box.midX, y: column.box.midY))
        VStack(spacing: 0) {
            ForEach(Array(column.items.enumerated()), id: \.offset) { _, item in
                switch item {
                case let .text(t, top):
                    Text(t.text)
                        .font(TrunkPartRenderer.font(t))
                        .tracking(t.size * t.tracking)
                        .foregroundStyle(Color(trunk: t.color))
                        .multilineTextAlignment(.center)
                        .lineLimit(t.maxLines)
                        .minimumScaleFactor(0.6)
                        .shadow(color: Color(trunk: t.shadow ?? TrunkRGBA(r: 0, g: 0, b: 0, a: 0)), radius: 0, x: 0, y: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, top)
                case let .bar(color, opacity, height, inset, top):
                    TrunkStripes(angle: 90, period: 5, bands: [(0, 1, color), (2, 4, color)])
                        .frame(height: height)
                        .opacity(opacity)
                        .padding(.horizontal, inset)
                        .padding(.top, top)
                case .space(let h):
                    Color.clear.frame(height: h)
                }
            }
        }
        .frame(width: column.box.w, height: column.box.h, alignment: column.alignTop ? .top : .center)
        .scaleEffect(column.transform.scale)
        .rotationEffect(.degrees(column.transform.rotation))
        .position(x: c.x, y: c.y)
    }
}

/// 手順を Canvas に塗る（`TrunkPartDrawing` の手順・`TrunkPartPaint` の塗り）
enum TrunkPartRenderer {

    static func font(_ t: TrunkPartText) -> Font {
        if t.mincho {
            // 明朝は同梱の Bold だけ（800 も 700 もこれ）
            return t.tabular ? Font.custom(JPFont.displayName, fixedSize: t.size).monospacedDigit()
                : Font.custom(JPFont.displayName, fixedSize: t.size)
        }
        let f = Font.system(size: t.size, weight: t.heavy ? .heavy : .bold)
        return t.tabular ? f.monospacedDigit() : f
    }

    static func draw(_ ops: [TrunkPartOp], in ctx: inout GraphicsContext) {
        for op in ops {
            switch op {
            case let .fill(segments, paint, bounds, evenOdd):
                var c = ctx
                c.clip(to: TrunkPaint.path(segments), style: FillStyle(eoFill: evenOdd))
                self.paint(paint, bounds, in: &c)
            case let .stroke(segments, color, width, dash, round):
                ctx.stroke(TrunkPaint.path(segments), with: .color(Color(trunk: color)),
                           style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt,
                                              lineJoin: round ? .round : .miter, dash: dash.map { CGFloat($0) }))
            case let .group(children, t, clip):
                var c = ctx
                c.translateBy(x: t.tx, y: t.ty)
                c.rotate(by: .degrees(t.rotation))
                c.scaleBy(x: t.scale, y: t.scale)
                if let clip { c.clip(to: TrunkPaint.path(clip)) }
                draw(children, in: &c)
            case .text:
                // 字は SwiftUI の字で重ねる（`TrunkPartTextColumnView`）
                break
            }
        }
    }

    private static func rectPath(_ r: TrunkRect) -> Path {
        TrunkPaint.path(SVGPath.rect(x: r.x, y: r.y, w: r.w, h: r.h))
    }

    private static func point(_ r: TrunkRect, _ u: (x: Double, y: Double)) -> CGPoint {
        CGPoint(x: r.x + u.x * r.w, y: r.y + u.y * r.h)
    }

    private static func stops(_ list: [TrunkStop]) -> Gradient {
        Gradient(stops: list.map { Gradient.Stop(color: Color(trunk: $0.color), location: $0.location) })
    }

    /// 塗りを四角に（CSS の background を、その要素の枠に）
    static func paint(_ paint: TrunkPartPaint, _ r: TrunkRect, in ctx: inout GraphicsContext) {
        guard r.w > 0, r.h > 0 else { return }
        switch paint {
        case .solid(let color):
            ctx.fill(rectPath(r), with: .color(Color(trunk: color)))
        case .metal(let metal):
            linear(metal.gradient, r, in: &ctx)
        case .linear(let g):
            linear(g, r, in: &ctx)
        case .glow(let g):
            let cx = r.x + g.cx * r.w, cy = r.y + g.cy * r.h
            var rx = g.rx * r.w, ry = g.ry * r.h
            if g.farthestCorner {
                let far = farthestCorner(r, cx, cy)
                rx = far
                ry = far
            }
            guard rx > 0, ry > 0 else { return }
            var c = ctx
            c.translateBy(x: cx, y: cy)
            c.scaleBy(x: 1, y: ry / rx)
            let local = TrunkRect(x: r.x - cx, y: (r.y - cy) * rx / ry, w: r.w, h: r.h * rx / ry)
            c.fill(rectPath(local), with: .radialGradient(stops(g.stops), center: CGPoint(x: 0, y: 0),
                                                          startRadius: 0, endRadius: rx))
        case let .stripes(angle, period, bands):
            stripes(angle: angle, period: period, bands: bands, r, in: &ctx)
        case .dots(let d):
            var path = Path()
            let radius = (d.inner + d.outer) / 2
            var y = r.y + d.cy
            // 升の中心が枠の外でも、点の一部が中に入るなら描く（左上の升の前から）
            if d.cy > d.tile / 2 { y -= d.tile }
            while y - radius < r.maxY {
                var x = r.x + d.cx - (d.cx > d.tile / 2 ? d.tile : 0)
                while x - radius < r.maxX {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += d.tile
                }
                y += d.tile
            }
            var c = ctx
            c.clip(to: rectPath(r))
            c.fill(path, with: .color(Color(trunk: d.color)))
        case let .rings(rcx, rcy, period, from, color):
            let cx = r.x + rcx * r.w, cy = r.y + rcy * r.h
            let far = farthestCorner(r, cx, cy)
            var c = ctx
            c.clip(to: rectPath(r))
            var radius = from + (period - from) / 2
            while radius - (period - from) / 2 < far {
                c.stroke(TrunkPaint.path(SVGPath.circle(cx: cx, cy: cy, r: radius)), with: .color(Color(trunk: color)),
                         lineWidth: period - from)
                radius += period
            }
        case let .checker(a, b, tile):
            ctx.fill(rectPath(r), with: .color(Color(trunk: b)))
            var path = Path()
            let half = tile / 2
            var y = r.y
            while y < r.maxY {
                var x = r.x
                while x < r.maxX {
                    // 円錐の 0〜25%（右上）と 50〜75%（左下）
                    path.addRect(CGRect(x: x + half, y: y, width: half, height: half))
                    path.addRect(CGRect(x: x, y: y + half, width: half, height: half))
                    x += tile
                }
                y += tile
            }
            var c = ctx
            c.clip(to: rectPath(r))
            c.fill(path, with: .color(Color(trunk: a)))
        case let .seigaiha(base, line):
            ctx.fill(rectPath(r), with: .color(Color(trunk: base)))
            let tw = 26.0, th = 13.0
            var y = r.y
            while y < r.maxY {
                var x = r.x
                while x < r.maxX {
                    var c = ctx
                    c.clip(to: rectPath(TrunkRect(x: x, y: y, w: tw, h: th)))
                    let cx = x + tw / 2, cy = y + th
                    for (inner, outer) in [(6.5, 8.0), (11.5, 13.0)] {
                        c.stroke(TrunkPaint.path(SVGPath.circle(cx: cx, cy: cy, r: (inner + outer) / 2)),
                                 with: .color(Color(trunk: line)), lineWidth: outer - inner)
                    }
                    x += tw
                }
                y += th
            }
        case .layers(let list):
            // CSS は先頭がいちばん上
            for layer in list.reversed() { self.paint(layer, r, in: &ctx) }
        }
    }

    /// 点からいちばん遠い角までの長さ（CSS の `farthest-corner`）
    private static func farthestCorner(_ r: TrunkRect, _ cx: Double, _ cy: Double) -> Double {
        let dx = max(abs(r.x - cx), abs(r.maxX - cx))
        let dy = max(abs(r.y - cy), abs(r.maxY - cy))
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func linear(_ g: TrunkGradient, _ r: TrunkRect, in ctx: inout GraphicsContext) {
        let e = TrunkGradient.endpoints(angle: g.angle, width: r.w, height: r.h)
        ctx.fill(rectPath(r), with: .linearGradient(stops(g.stops), startPoint: point(r, e.start), endPoint: point(r, e.end)))
    }

    /// `repeating-linear-gradient`（CSS の線の長さ・始まりの位置まで同じ）
    private static func stripes(angle: Double, period: Double, bands: [TrunkPartBand], _ r: TrunkRect,
                                in ctx: inout GraphicsContext) {
        guard period > 0 else { return }
        let rad = angle * .pi / 180
        let length = abs(r.w * sin(rad)) + abs(r.h * cos(rad))
        let reach = (r.w * r.w + r.h * r.h).squareRoot()
        var c = ctx
        c.clip(to: rectPath(r))
        c.translateBy(x: r.midX, y: r.midY)
        c.rotate(by: .degrees(angle))
        // 線の始まり（p = 0）は y = length / 2。手前の周期から描き始める
        var p = -(((reach - length) / 2 / period).rounded(.up) + 1) * period
        var paths: [Path] = Array(repeating: Path(), count: bands.count)
        while p < reach + period {
            for (i, band) in bands.enumerated() {
                let top = length / 2 - (p + band.to), bottom = length / 2 - (p + band.from)
                paths[i].addRect(CGRect(x: -reach, y: top, width: reach * 2, height: bottom - top))
            }
            p += period
        }
        for (i, band) in bands.enumerated() {
            c.fill(paths[i], with: .color(Color(trunk: band.color)))
        }
    }
}

/// 旅のトランクの手ざわりの音（貼る・ハンドルの目盛り・カプセルが落ちる・2026-10-17）。
/// **消音の切り替えに従う**（端末の効果音）。音の番号は iOS のキーボードの「こつ」と同じ系統
@MainActor
enum TrunkSound {
    /// ハンドルの目盛り
    static func tick() { AudioServicesPlaySystemSound(1104) }
    /// ラベルを貼った
    static func stick() { AudioServicesPlaySystemSound(1306) }
    /// カプセルが落ちた
    static func drop() { AudioServicesPlaySystemSound(1103) }
}
