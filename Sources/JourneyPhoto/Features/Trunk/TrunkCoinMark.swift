import SwiftUI

/// 羅針盤の硬貨（札 #716・2026-11-23 owner 採用）。**どの画面の硬貨もこの1つ**（カプセルの機械の数の行と重ねた硬貨・
/// トランクのカード・部品箱の帯・届いた画面の札・はじめての硬貨とお礼の硬貨・カバーのお誘い）。
///
/// 黒地に、面ごとに明暗をつけた真鍮の羅針盤。縁のギザと内輪、北の印、縁の目盛りは大きさの段で足す（`TrunkCoinGeometry`）。
/// 描き方: 縁、ギザ、黒い面は `Canvas` で1枚に描き、星（針）だけを別の層にして `rotationEffect` で揺らす。
/// 内輪、目盛り、光の帯、外の線はその上の `Canvas`（案の頁の SVG と同じ重なり）。光は左上の1つ。
/// 0枚は白 10% の影絵（`empty`・持っていない部品の影と同じ決まり）。`tilt` で手前へ倒すと楕円になり、下に厚みの帯が出る
struct TrunkCoinMark: View {
    var size: Double = 26
    /// 手前へ倒す角度（度）。0 は正面
    var tilt: Double = 0
    /// 星（針）の向き（度）。揺れる針はここに角度を渡す
    var turn: Double = 0
    /// 影絵（0枚）
    var empty = false
    /// 縁の光（手に取ったとき・もらったとき）。経った秒。nil なら描かない
    var rimLight: Double? = nil

    private var g: TrunkCoinGeometry { TrunkCoinGeometry(size: size, tilt: tilt) }

    var body: some View {
        let g = self.g
        ZStack(alignment: .top) {
            // 厚みの帯（倒したときだけ・面の下にずらして見せる）
            if g.edgeDepth > 0 {
                Circle()
                    .fill(empty ? AnyShapeStyle(Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity))
                                : AnyShapeStyle(LinearGradient(colors: [Color(trunk: TrunkRGBA(0x7E6438)), Color(trunk: TrunkRGBA(0x3E301A))],
                                                               startPoint: .leading, endPoint: .trailing)))
                    .frame(width: g.size, height: g.size)
                    .scaleEffect(x: 1, y: g.squash, anchor: .top)
                    .frame(width: g.size, height: g.size * g.squash, alignment: .top)
                    .offset(x: 0, y: g.edgeDepth)
            }
            face(g)
                .frame(width: g.size, height: g.size)
                .scaleEffect(x: 1, y: g.squash, anchor: .top)
                .frame(width: g.size, height: g.size * g.squash, alignment: .top)
        }
        .frame(width: g.size, height: g.drawnHeight, alignment: .top)
        .shadow(color: Color.black.opacity(g.shadowRadius > 0 && !empty ? 0.6 : 0), radius: g.shadowRadius, x: 0, y: g.shadowY)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func face(_ g: TrunkCoinGeometry) -> some View {
        if empty {
            // 0枚: 形だけの影絵（色と質感は出さない）
            Circle().fill(Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity))
        } else {
            ZStack {
                TrunkCoinBase(geometry: g)
                TrunkCoinNeedle(geometry: g)
                    .rotationEffect(.degrees(turn))
                TrunkCoinOver(geometry: g)
                if let rimLight {
                    TrunkCoinRimLight(elapsed: rimLight)
                }
            }
        }
    }
}

/// 100 の箱の座標を描く面へ
private struct TrunkCoinBox {
    let k: Double
    init(_ size: CGSize) { k = Double(size.width) / 100 }
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    func circle(_ r: Double) -> Path {
        Path { $0.addEllipse(in: CGRect(x: (50 - r) * k, y: (50 - r) * k, width: r * 2 * k, height: r * 2 * k)) }
    }
    /// 中心から角度（+x から時計回り・度）の方向に r の点
    func polar(_ r: Double, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return p(50 + r * cos(a), 50 + r * sin(a))
    }
}

private enum TrunkCoinInk {
    static func c(_ hex: UInt32) -> Color { Color(trunk: TrunkRGBA(hex)) }
    static let shine = c(0xFFF1C4), pale = c(0xF2DFAE), brass = WebTheme.accent, mid = c(0x8A6B39), shade = c(0x6E5630)
    static let line = Color(trunk: TrunkRGBA(r: 60, g: 40, b: 15, a: 0.45))
    static let knurl = Color(trunk: TrunkRGBA(r: 60, g: 40, b: 15, a: 0.35))
    static let pin = c(0x0C0C0D)
    /// 星と内輪の真鍮（左上 #F2DFAE → 右下 #6E5630）
    static var metal: Gradient { Gradient(stops: [Gradient.Stop(color: pale, location: 0), Gradient.Stop(color: shade, location: 1)]) }
}

/// 縁（真鍮の段）、ギザ、黒い面（動かない層）
private struct TrunkCoinBase: View {
    let geometry: TrunkCoinGeometry

    var body: some View {
        let g = geometry
        Canvas { ctx, size in
            let b = TrunkCoinBox(size)
            let full = b.p(100, 100)
            ctx.fill(b.circle(50), with: .linearGradient(
                Gradient(stops: [Gradient.Stop(color: TrunkCoinInk.shine, location: 0),
                                 Gradient.Stop(color: TrunkCoinInk.brass, location: 0.45),
                                 Gradient.Stop(color: TrunkCoinInk.shade, location: 1)]),
                startPoint: .zero, endPoint: full))
            if g.knurlCount > 0 {
                var knurl = Path()
                for i in 0..<g.knurlCount {
                    let deg = Double(i) * 360 / Double(g.knurlCount)
                    knurl.move(to: b.polar(TrunkCoinGeometry.knurlInner, deg))
                    knurl.addLine(to: b.polar(TrunkCoinGeometry.knurlOuter, deg))
                }
                ctx.stroke(knurl, with: .color(TrunkCoinInk.knurl), lineWidth: 0.8 * b.k)
            }
            // 黒い面（左上が少し明るい）
            ctx.fill(b.circle(TrunkCoinGeometry.faceRadius), with: .radialGradient(
                Gradient(stops: [Gradient.Stop(color: TrunkCoinInk.c(0x2C2C30), location: 0),
                                 Gradient.Stop(color: TrunkCoinInk.c(0x101012), location: 0.6),
                                 Gradient.Stop(color: TrunkCoinInk.c(0x050506), location: 1)]),
                center: b.p(40.4, 35.6), startRadius: 0, endRadius: 68 * b.k))
        }
    }
}

/// 星（針）。中心で回す層
struct TrunkCoinNeedle: View {
    let geometry: TrunkCoinGeometry

    var body: some View {
        let g = geometry
        Canvas { ctx, size in
            let b = TrunkCoinBox(size)
            let metal = GraphicsContext.Shading.linearGradient(TrunkCoinInk.metal, startPoint: .zero, endPoint: b.p(100, 100))
            func star(_ s: TrunkCoinGeometry.Star) -> Path {
                var path = Path()
                for (i, pt) in TrunkCoinGeometry.starPoints(s).enumerated() {
                    if i == 0 { path.move(to: b.p(pt.x, pt.y)) } else { path.addLine(to: b.p(pt.x, pt.y)) }
                }
                path.closeSubpath()
                return path
            }
            var back = ctx
            back.opacity = TrunkCoinGeometry.backStar.opacity
            back.fill(star(TrunkCoinGeometry.backStar), with: metal)
            if let flat = g.flatStar {
                ctx.fill(star(flat), with: metal)
            }
            for arm in g.arms {
                // 腕の先・左の根元・中心（明るい面）と、先・右の根元・中心（暗い面）
                let a = arm.angle * .pi / 180
                func rot(_ x: Double, _ y: Double) -> CGPoint {
                    let dx = x - 50, dy = y - 50
                    return b.p(50 + dx * cos(a) - dy * sin(a), 50 + dx * sin(a) + dy * cos(a))
                }
                var light = Path()
                light.move(to: rot(50, 50 - arm.length)); light.addLine(to: rot(50 - arm.width, 50 - arm.width))
                light.addLine(to: rot(50, 50)); light.closeSubpath()
                var dark = Path()
                dark.move(to: rot(50, 50 - arm.length)); dark.addLine(to: rot(50 + arm.width, 50 - arm.width))
                dark.addLine(to: rot(50, 50)); dark.closeSubpath()
                ctx.fill(light, with: .color(TrunkCoinInk.c(arm.cardinal ? 0xFFF1C4 : 0xE2C687)))
                ctx.fill(dark, with: .color(TrunkCoinInk.c(arm.cardinal ? 0x8A6B39 : 0x7A5E30)))
            }
            if g.hubRadius > 0 {
                ctx.fill(b.circle(g.hubRadius), with: metal)
            }
            ctx.fill(b.circle(g.pinRadius), with: .color(TrunkCoinInk.pin))
        }
    }
}

/// 面の縁の線、内輪、北の印、縁の目盛り、光の帯、外の暗い線（動かない層・星の上）
private struct TrunkCoinOver: View {
    let geometry: TrunkCoinGeometry

    var body: some View {
        let g = geometry
        Canvas { ctx, size in
            let b = TrunkCoinBox(size)
            let metal = GraphicsContext.Shading.linearGradient(TrunkCoinInk.metal, startPoint: .zero, endPoint: b.p(100, 100))
            ctx.stroke(b.circle(TrunkCoinGeometry.faceRadius), with: .color(TrunkCoinInk.line), lineWidth: 1.2 * b.k)
            if g.showsInnerRing {
                var ring = ctx
                ring.opacity = 0.8
                ring.stroke(b.circle(TrunkCoinGeometry.innerRing), with: metal, lineWidth: 1.6 * b.k)
                ctx.stroke(b.circle(31.5), with: .color(Color(trunk: TrunkRGBA(r: 255, g: 241, b: 196, a: 0.25))), lineWidth: 0.7 * b.k)
            }
            if g.showsNorthMark {
                var north = Path()
                north.move(to: b.p(50, 5.5)); north.addLine(to: b.p(53.4, 12.5)); north.addLine(to: b.p(46.6, 12.5))
                north.closeSubpath()
                ctx.fill(north, with: .color(TrunkCoinInk.c(0x1A1206)))
            }
            if g.tickCount > 0 {
                var ticks = ctx
                ticks.opacity = 0.85
                for i in 0..<g.tickCount {
                    let deg = Double(i) * 360 / Double(g.tickCount)
                    var tick = Path()
                    tick.move(to: b.polar(TrunkCoinGeometry.tickInner(i), deg))
                    tick.addLine(to: b.polar(TrunkCoinGeometry.tickOuter, deg))
                    ticks.stroke(tick, with: .color(TrunkCoinInk.brass), lineWidth: TrunkCoinGeometry.tickWidth(i) * b.k)
                }
            }
            // 真鍮の光: 左上から斜めに差す帯（縁の内だけ）
            var sheen = ctx
            sheen.clip(to: b.circle(50))
            sheen.fill(Path { $0.addRect(CGRect(x: 0, y: 0, width: size.width, height: size.height)) }, with: .linearGradient(
                Gradient(stops: [Gradient.Stop(color: Color.white.opacity(0), location: 0.18),
                                 Gradient.Stop(color: Color.white.opacity(0.38), location: 0.32),
                                 Gradient.Stop(color: Color.white.opacity(0), location: 0.46)]),
                startPoint: .zero, endPoint: b.p(100, 100)))
            ctx.stroke(b.circle(49), with: .color(TrunkCoinInk.line), lineWidth: g.outlineWidth * b.k)
        }
        .allowsHitTesting(false)
    }
}

/// 縁を光がひと回り（24 本の弧を順に点ける・透明度だけ）
private struct TrunkCoinRimLight: View {
    let elapsed: Double

    var body: some View {
        Canvas { ctx, size in
            let b = TrunkCoinBox(size)
            for i in 0..<24 {
                let o = TrunkMotion.rimLightOpacity(arc: i, elapsed: elapsed)
                guard o > 0.01 else { continue }
                var arc = Path()
                // 北から時計回り（+x から -90°）
                arc.addArc(center: b.p(50, 50), radius: 46.5 * b.k,
                           startAngle: .degrees(Double(i) * 15 - 6 - 90), endAngle: .degrees(Double(i) * 15 + 6 - 90), clockwise: false)
                var c = ctx
                c.opacity = o
                c.stroke(arc, with: .color(Color(trunk: TrunkRGBA(0xFFF6DA))), style: StrokeStyle(lineWidth: 3 * b.k, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 手に取ったとき・もらったときの硬貨（針が揺れて北で止まり、光が縁をひと回り）。`trigger` が変わるたびに1回。
/// 動きを減らす設定では揺らさない（止まった硬貨のまま）
struct TrunkCoinPickUp: View {
    var size: Double
    var tilt: Double = 0
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { ctx in
            let t = start.map { ctx.date.timeIntervalSince($0) }
            TrunkCoinMark(size: size, tilt: tilt,
                          turn: t.map { TrunkMotion.needleAngle(elapsed: $0) } ?? 0,
                          rimLight: size >= TrunkCoinGeometry.largeFrom ? t : nil)
        }
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            let began = Date()
            start = began
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.pickUpSeconds * 1_000_000_000))
                if start == began { start = nil }
            }
        }
    }
}

/// 大きい硬貨の絵（はじめての硬貨・お礼の硬貨の手前の1枚）。ゆっくり左右に傾いて光り（7 秒）、押すと針が揺れる。
/// 動きを減らす設定では傾けない
struct TrunkCoinShowcase: View {
    var size: Double
    @State private var picks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: TrunkMotion.tiltSeconds) / TrunkMotion.tiltSeconds
            // 0 → 50% → 100% を ease-in-out で行って戻る（rotateY -24 → 24、rotateX 6 → -4）
            let half = p < 0.5 ? TrunkBezier.easeInOut.value(p * 2) : TrunkBezier.easeInOut.value((1 - p) * 2)
            TrunkCoinPickUp(size: size, trigger: picks)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : -24 + 48 * half), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 6 - 10 * half), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        }
        .contentShape(Circle())
        .onTapGesture { picks += 1 }
        .sensoryFeedback(.impact(weight: .light), trigger: picks)
        .accessibilityHidden(true)
    }
}

/// 重ねた硬貨（カプセルの機械の数の行）。手元の枚数だけ倒した硬貨を重ね（5枚まで描き、数は字で）、0枚は影絵。
/// `liftTop`: いちばん上の1枚を隠す（入れ口へ飛んでいる間）
struct TrunkCoinStackView: View {
    let coins: Int
    var size: Double = 26
    var liftTop = false

    var body: some View {
        let n = TrunkCoinStack.drawn(coins)
        let one = TrunkCoinGeometry(size: size, tilt: TrunkCoinStack.tilt).drawnHeight
        let step = TrunkCoinStack.step(size: size)
        let h = TrunkCoinStack.height(coins: coins, size: size)
        ZStack(alignment: .topLeading) {
            ForEach(0..<n, id: \.self) { i in
                TrunkCoinMark(size: size, tilt: TrunkCoinStack.tilt, empty: TrunkCoinStack.isEmpty(coins))
                    .offset(x: TrunkCoinStack.xShift(i), y: h - one - Double(i) * step)
                    .opacity(liftTop && i == n - 1 && !TrunkCoinStack.isEmpty(coins) ? 0 : 1)
            }
        }
        .frame(width: size + 2, height: h, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
