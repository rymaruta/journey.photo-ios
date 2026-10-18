import Foundation

// 部品1点の描き方（モック Part.dc.html の CSS と SVG を、96×96 の枠の「描く手順」に写したもの・2026-10-17）。
//
// 画面（`Features/Trunk/TrunkPartView.swift`）は手順を上から順に描くだけ。形・位置・色の計算は全部ここ
// （Linux でテストできるように）。**同じ部品なら必ず同じ手順**（乱数・時刻を使わない）。
//
// 写し方の決まり（2026-10-17 判断）:
// - `border … transparent` ＋ `mask-composite: exclude` の輪・U の字は、外の形から内の形を抜く（even-odd）
// - CSS の角丸は、辺より大きい半径を CSS と同じ比で縮める（`cssRect`）
// - 影（`drop-shadow`）は部品全体に1つ（画面の側）。内側の影は上の 1px の光と下の暗がりだけ写す
// - 字は SwiftUI の字で描く（`TrunkPartTextColumn`）。高さの見積もりは CSS の `line-height: normal` を 1.2 とする

/// 四角（pt）
struct TrunkRect: Equatable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }
    var maxX: Double { x + w }
    var maxY: Double { y + h }

    func inset(_ d: Double) -> TrunkRect { TrunkRect(x: x + d, y: y + d, w: max(0, w - 2 * d), h: max(0, h - 2 * d)) }

    /// 2つの四角が重なるか（辺が触れるだけなら重ならない）
    func intersects(_ o: TrunkRect) -> Bool { x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY }

    /// 点 `(px, py)` を中心に `degrees` 回した四角の外接の四角（SwiftUI の `rotationEffect` と同じ向き・y が下）
    func rotated(_ degrees: Double, aroundX px: Double, y py: Double) -> TrunkRect {
        let rad = degrees * .pi / 180
        let c = cos(rad), s = sin(rad)
        let pts = [(x, y), (maxX, y), (maxX, maxY), (x, maxY)].map { p -> (Double, Double) in
            let dx = p.0 - px, dy = p.1 - py
            return (px + dx * c - dy * s, py + dx * s + dy * c)
        }
        let xs = pts.map(\.0), ys = pts.map(\.1)
        let x0 = xs.min() ?? x, y0 = ys.min() ?? y
        return TrunkRect(x: x0, y: y0, w: (xs.max() ?? maxX) - x0, h: (ys.max() ?? maxY) - y0)
    }
}

/// 字1つ（紙や金属に刷った字。Dynamic Type で伸ばさない）
struct TrunkPartText: Equatable {
    let text: String
    let size: Double
    /// 800 なら heavy、700 なら bold
    let heavy: Bool
    /// 明朝（モックの部品の既定の字）。false ならシステム
    let mincho: Bool
    /// 字間（em）
    let tracking: Double
    let color: TrunkRGBA
    var tabular = false
    /// 行の高さ（字の大きさに対する倍率）
    var lineHeight = 1.2
    /// 折り返す行数の上限
    var maxLines = 2
    /// 字の下の影（ワッペンの刺繍の字）
    var shadow: TrunkRGBA?
}

/// 字の並び（縦に積む・真ん中に揃える）
struct TrunkPartTextColumn: Equatable {
    enum Item: Equatable {
        case text(TrunkPartText, top: Double)
        /// 手荷物タグのバーコード（色・不透明度・高さ・左右の余白・上の余白）
        case bar(TrunkRGBA, opacity: Double, height: Double, inset: Double, top: Double)
        /// 空き（ワッペンの絵の場所）
        case space(Double)
    }

    /// 並べる枠（`transform` の中の座標）
    let box: TrunkRect
    /// 上から積む（false なら枠の真ん中に）
    let alignTop: Bool
    let items: [Item]
    let transform: TrunkPartTransform
}

/// 置き方（ずらす → 回す → 縮める の順。回すのはずらした点を中心に）
struct TrunkPartTransform: Equatable {
    var tx: Double = 0
    var ty: Double = 0
    var rotation: Double = 0
    var scale: Double = 1

    static let identity = TrunkPartTransform()

    /// 外の置き方の中に入れる（`outer` のあとに `self`）
    func within(_ outer: TrunkPartTransform) -> TrunkPartTransform {
        let rad = outer.rotation * .pi / 180
        let x = tx * outer.scale, y = ty * outer.scale
        return TrunkPartTransform(tx: outer.tx + x * cos(rad) - y * sin(rad),
                                  ty: outer.ty + x * sin(rad) + y * cos(rad),
                                  rotation: outer.rotation + rotation, scale: outer.scale * scale)
    }

    /// 点を置き方で動かす
    func apply(_ p: SVGPath.Point) -> SVGPath.Point {
        let rad = rotation * .pi / 180
        let x = p.x * scale, y = p.y * scale
        return SVGPath.Point(x: tx + x * cos(rad) - y * sin(rad), y: ty + x * sin(rad) + y * cos(rad))
    }
}

/// 描く手順
indirect enum TrunkPartOp: Equatable {
    /// 形を塗りで塗る（塗りの向き・大きさは `bounds` で決める）
    case fill([SVGPath.Segment], TrunkPartPaint, bounds: TrunkRect, evenOdd: Bool)
    case stroke([SVGPath.Segment], TrunkRGBA, width: Double, dash: [Double], round: Bool)
    /// まとめて置く（`clip` は置いた中の座標）
    case group([TrunkPartOp], TrunkPartTransform, clip: [SVGPath.Segment]?)
    case text(TrunkPartTextColumn)
}

// MARK: - 形の道具

enum TrunkShapes {

    private static let k = 0.5522847498

    /// CSS の角丸の四角（半径は 左上・右上・右下・左下。横と縦を別に持てる・辺より大きければ同じ比で縮める）
    static func cssRect(_ r: TrunkRect, rx: [Double], ry: [Double]? = nil) -> [SVGPath.Segment] {
        let ry = ry ?? rx
        guard rx.count == 4, ry.count == 4, r.w > 0, r.h > 0 else { return SVGPath.rect(x: r.x, y: r.y, w: r.w, h: r.h) }
        var f = 1.0
        for (sum, side) in [(rx[0] + rx[1], r.w), (rx[3] + rx[2], r.w), (ry[0] + ry[3], r.h), (ry[1] + ry[2], r.h)] where sum > side {
            f = min(f, side / sum)
        }
        let a = rx.map { $0 * f }, b = ry.map { $0 * f }
        func p(_ x: Double, _ y: Double) -> SVGPath.Point { SVGPath.Point(x: x, y: y) }
        let x0 = r.x, y0 = r.y, x1 = r.maxX, y1 = r.maxY
        var out: [SVGPath.Segment] = [.move(p(x0 + a[0], y0)), .line(p(x1 - a[1], y0))]
        if a[1] > 0 || b[1] > 0 {
            out.append(.cubic(c1: p(x1 - a[1] * (1 - k), y0), c2: p(x1, y0 + b[1] * (1 - k)), to: p(x1, y0 + b[1])))
        }
        out.append(.line(p(x1, y1 - b[2])))
        if a[2] > 0 || b[2] > 0 {
            out.append(.cubic(c1: p(x1, y1 - b[2] * (1 - k)), c2: p(x1 - a[2] * (1 - k), y1), to: p(x1 - a[2], y1)))
        }
        out.append(.line(p(x0 + a[3], y1)))
        if a[3] > 0 || b[3] > 0 {
            out.append(.cubic(c1: p(x0 + a[3] * (1 - k), y1), c2: p(x0, y1 - b[3] * (1 - k)), to: p(x0, y1 - b[3])))
        }
        out.append(.line(p(x0, y0 + b[0])))
        if a[0] > 0 || b[0] > 0 {
            out.append(.cubic(c1: p(x0, y0 + b[0] * (1 - k)), c2: p(x0 + a[0] * (1 - k), y0), to: p(x0 + a[0], y0)))
        }
        out.append(.close)
        return out
    }

    static func rect(_ r: TrunkRect, _ radius: Double = 0) -> [SVGPath.Segment] {
        cssRect(r, rx: [radius, radius, radius, radius])
    }

    static func ellipse(_ r: TrunkRect) -> [SVGPath.Segment] {
        SVGPath.ellipse(cx: r.midX, cy: r.midY, rx: r.w / 2, ry: r.h / 2)
    }

    static func circle(_ cx: Double, _ cy: Double, _ radius: Double) -> [SVGPath.Segment] {
        SVGPath.circle(cx: cx, cy: cy, r: radius)
    }

    /// 割合（0〜1）で書いた多角形を枠に
    static func polygon(_ r: TrunkRect, _ points: [(Double, Double)]) -> [SVGPath.Segment] {
        guard let first = points.first else { return [] }
        var out: [SVGPath.Segment] = [.move(SVGPath.Point(x: r.x + first.0 * r.w, y: r.y + first.1 * r.h))]
        for pt in points.dropFirst() { out.append(.line(SVGPath.Point(x: r.x + pt.0 * r.w, y: r.y + pt.1 * r.h))) }
        out.append(.close)
        return out
    }

    /// CSS の `border-radius: R R 0 0` に `border: t solid transparent; border-bottom: none` を抜いた U の字
    /// （外の形と内の形を並べる・even-odd で塗る）
    static func arch(_ r: TrunkRect, radius: Double, thickness t: Double) -> [SVGPath.Segment] {
        let outer = cssRect(r, rx: [radius, radius, 0, 0])
        // 外の半径は辺に合わせて縮んだあと（CSS は内の半径＝外の半径 − 縁の太さ）
        let scaled = min(radius, r.w / 2, r.h)
        let inner = TrunkRect(x: r.x + t, y: r.y + t, w: max(0, r.w - 2 * t), h: max(0, r.h - t))
        let ir = max(0, scaled - t)
        return outer + cssRect(inner, rx: [ir, ir, 0, 0])
    }

    /// 丸い輪（外の円と内の円・even-odd）
    static func ring(_ cx: Double, _ cy: Double, outer: Double, inner: Double) -> [SVGPath.Segment] {
        circle(cx, cy, outer) + circle(cx, cy, inner)
    }

    /// 下の開いた U の線（持ち手の縫い目・CSS の `border-bottom: none` の破線）
    static func openTop(_ r: TrunkRect, radius: Double) -> [SVGPath.Segment] {
        let f = min(1, r.w / (radius * 2), r.h / radius)
        let a = radius * f
        func p(_ x: Double, _ y: Double) -> SVGPath.Point { SVGPath.Point(x: x, y: y) }
        return [.move(p(r.x, r.maxY)), .line(p(r.x, r.y + a)),
                .cubic(c1: p(r.x, r.y + a * (1 - k)), c2: p(r.x + a * (1 - k), r.y), to: p(r.x + a, r.y)),
                .line(p(r.maxX - a, r.y)),
                .cubic(c1: p(r.maxX - a * (1 - k), r.y), c2: p(r.maxX, r.y + a * (1 - k)), to: p(r.maxX, r.y + a)),
                .line(p(r.maxX, r.maxY))]
    }

    /// 並びの外接の四角（テストで「枠の中に収まる」を見る）
    static func bounds(_ segments: [SVGPath.Segment]) -> TrunkRect? {
        var xs: [Double] = [], ys: [Double] = []
        for s in segments {
            switch s {
            case .move(let p), .line(let p): xs.append(p.x); ys.append(p.y)
            case let .cubic(c1, c2, to): xs += [c1.x, c2.x, to.x]; ys += [c1.y, c2.y, to.y]
            case let .quad(c, to): xs += [c.x, to.x]; ys += [c.y, to.y]
            case .close: break
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return TrunkRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}

// MARK: - 部品の描き方

enum TrunkPartDrawing {

    /// 描く枠（モックの 96×96）
    static let size: Double = 96

    private static func white(_ a: Double) -> TrunkRGBA { TrunkRGBA(r: 255, g: 255, b: 255, a: a) }
    private static func black(_ a: Double) -> TrunkRGBA { TrunkRGBA(r: 0, g: 0, b: 0, a: a) }

    /// 金具の上の白い光（`radial-gradient(circle at x y, rgba(255,255,255,a), rgba(255,255,255,0) end)`）
    static func shine(_ a: Double, at cx: Double, _ cy: Double, end: Double) -> TrunkPartPaint {
        .glow(TrunkPartGlow(stops: [TrunkStop(color: white(a), location: 0), TrunkStop(color: white(0), location: end)],
                            cx: cx, cy: cy, rx: 1, ry: 1, farthestCorner: true))
    }

    /// 上の 1px の光（`inset 0 1px 0 rgba(255,255,255,a)`）を形の中に
    private static func topLight(_ shape: [SVGPath.Segment], _ box: TrunkRect, _ a: Double) -> TrunkPartOp {
        .group([.fill(TrunkShapes.rect(TrunkRect(x: box.x, y: box.y, w: box.w, h: 1)), .solid(white(a)),
                      bounds: box, evenOdd: false)], .identity, clip: shape)
    }

    /// 下の暗がり（`inset 0 -3px 6px rgba(0,0,0,a)` を、下 6px のグラデーションで）
    private static func bottomShade(_ shape: [SVGPath.Segment], _ box: TrunkRect, _ a: Double) -> TrunkPartOp {
        let band = TrunkRect(x: box.x, y: box.maxY - 6, w: box.w, h: 6)
        return .group([.fill(TrunkShapes.rect(band),
                             .linear(TrunkGradient(angle: 180, stops: [TrunkStop(color: black(0), location: 0),
                                                                       TrunkStop(color: black(a), location: 1)])),
                             bounds: band, evenOdd: false)], .identity, clip: shape)
    }

    /// 1点の手順（同じ部品なら必ず同じ）
    static func ops(_ part: TrunkPart) -> [TrunkPartOp] { ops(part.look) }

    static func ops(_ look: TrunkPartLook) -> [TrunkPartOp] {
        switch look {
        case .handle(let h): return handle(h)
        case .corner(let c): return corner(c)
        case .lock(let l): return lock(l)
        case .lining(let paint): return lining(paint)
        case .tag(let t): return tag(t)
        case .pin(let p): return pin(p)
        case .patch(let p): return patch(p)
        case .charm(let c): return charm(c)
        case .key(let k): return key(k)
        }
    }

    // MARK: 持ち手

    static func handle(_ h: TrunkPartLook.Handle) -> [TrunkPartOp] {
        let tw = h.width
        let box = TrunkRect(x: 14, y: 18, w: 68, h: 56)
        var out: [TrunkPartOp] = [.fill(TrunkShapes.arch(box, radius: 36, thickness: tw), h.paint, bounds: box, evenOdd: true)]
        if h.stitch {
            // `left: 14 + tw/2 - 1; top: 18 + tw/2 - 1; width: 68 - tw + 2; height: 56 - tw/2`・1.2px の破線（線の真ん中は 0.6 内）
            let s = TrunkRect(x: 14 + tw / 2 - 1 + 0.6, y: 18 + tw / 2 - 1 + 0.6, w: 68 - tw + 2 - 1.2, h: 56 - tw / 2 - 0.6)
            out.append(.stroke(TrunkShapes.openTop(s, radius: 32), TrunkRGBA(r: 250, g: 230, b: 190, a: 0.6),
                               width: 1.2, dash: [3.6, 2.4], round: false))
        }
        for x in [10, 86 - tw - 8] {
            let clip = TrunkRect(x: x, y: 64, w: tw + 8, h: 18)
            out.append(.fill(TrunkShapes.rect(clip, 3), .metal(h.clip), bounds: clip, evenOdd: false))
        }
        return out
    }

    // MARK: 角金具

    static func cornerShape(_ box: TrunkRect) -> [SVGPath.Segment] {
        // 角丸 22 4 4 4 の四角を、L の字の多角形（`polygon(0 0, 100% 0, 100% 34%, 34% 34%, 34% 100%, 0 100%)`）で切る。
        // 角丸は枠の大きさ（96 の枠の 72）に比べて縮める（トランクに付けた小さい角金具でも同じ形・#305）
        let arm = box.w * 0.34
        let u = box.w / 72
        let big = 22 * u, small = 4 * u
        let k = 0.5522847498
        func p(_ x: Double, _ y: Double) -> SVGPath.Point { SVGPath.Point(x: box.x + x, y: box.y + y) }
        return [.move(p(0, big)), .cubic(c1: p(0, big * (1 - k)), c2: p(big * (1 - k), 0), to: p(big, 0)),
                .line(p(box.w - small, 0)),
                .cubic(c1: p(box.w - small * (1 - k), 0), c2: p(box.w, small * (1 - k)), to: p(box.w, small)),
                .line(p(box.w, arm)), .line(p(arm, arm)), .line(p(arm, box.h)),
                .line(p(small, box.h)),
                .cubic(c1: p(small * (1 - k), box.h), c2: p(0, box.h - small * (1 - k)), to: p(0, box.h - small)),
                .close]
    }

    /// 彫りの模様（モックの `eng`）
    static func engraving(_ e: TrunkCornerEngrave) -> TrunkPartPaint? {
        switch e {
        case .none: return nil
        case .karakusa: return .rings(cx: 0.2, cy: 0.2, period: 6, from: 5, color: TrunkRGBA(r: 60, g: 40, b: 15, a: 0.35))
        case .lines: return .stripes(angle: 45, period: 5, bands: [TrunkPartBand(from: 4, to: 5, color: TrunkRGBA(r: 60, g: 40, b: 15, a: 0.3))])
        case .hammer:
            return .layers([.dots(TrunkPartDots(color: white(0.35), tile: 7, center: 3.5, inner: 1, outer: 1.6)),
                            .dots(TrunkPartDots(color: black(0.2), tile: 7, center: 6.5, inner: 1, outer: 1.6))])
        }
    }

    static func corner(_ c: TrunkPartLook.Corner) -> [TrunkPartOp] {
        corner(c, box: TrunkRect(x: 12, y: 12, w: 72, h: 72))
    }

    /// トランクに付けたとき、穴と鋲をこれより小さくしない（角金具は 30〜46 に縮む・#305「縮んでも潰れない」）
    static let mountedMinHole: Double = 1.6
    static let mountedMinRivet: Double = 1.8

    /// 角金具を枠 `box` に描く（96 の枠では 12・12 から 72 角）。**トランクの角に付けたときも同じ L の字・透かし・
    /// 鋲で描く**（#305: 前は塗りだけを型の角の札に塗り、形と透かしと鋲が出なかった）。
    /// 縮めると穴と鋲は `mountedMin…` で止め、鋲は L の腕からはみ出さないよう内へ寄せる
    static func corner(_ c: TrunkPartLook.Corner, box: TrunkRect) -> [TrunkPartOp] {
        let u = box.w / 72
        let arm = box.w * 0.34
        let shape = cornerShape(box)
        var inner: [TrunkPartOp] = [.fill(shape, c.paint, bounds: box, evenOdd: false)]
        if let eng = engraving(c.engrave) { inner.append(.fill(shape, eng, bounds: box, evenOdd: false)) }
        if c.pierce {
            // 透かし: 14px の穴と、box-shadow の 18px・36px 先の小さい穴（広がり −3・−4）
            for (x, y, r) in [(13.0, 13.0, 7.0), (31, 13, 4), (49, 13, 3), (13, 31, 4), (13, 49, 3)] {
                let radius = u < 1 ? max(mountedMinHole, r * u) : r
                inner.append(.fill(TrunkShapes.circle(box.x + x * u, box.y + y * u, radius), .solid(TrunkRGBA(0x000000)),
                                   bounds: box, evenOdd: false))
            }
        }
        inner.append(topLight(shape, box, 0.4))
        var out: [TrunkPartOp] = [.group(inner, .identity, clip: shape)]
        if c.rivets {
            // 鋲の真ん中（96 の枠の 24・24／70・22／22・70 を、枠の左上からの距離に）
            for (x, y) in [(12.0, 12.0), (58, 10), (10, 58)] {
                let rr = u < 1 ? max(mountedMinRivet, 3.5 * u) : 3.5
                var cx = x * u, cy = y * u
                // 腕の太さ（34%）に収める（縮めて鋲だけ止めたとき）
                if cx > arm { cy = min(cy, arm - rr - 0.4) }
                if cy > arm { cx = min(cx, arm - rr - 0.4) }
                let r = TrunkRect(x: box.x + cx - rr, y: box.y + cy - rr, w: rr * 2, h: rr * 2)
                out.append(.fill(TrunkShapes.ellipse(r), rivetPaint(c.rivetMetal), bounds: r, evenOdd: false))
            }
        }
        return out
    }

    /// 角の鋲（`radial-gradient(circle at 35% 35%, #FFF8E0, M[metal][2] 70%)`）
    static func rivetPaint(_ metal: TrunkPartMetal) -> TrunkPartPaint {
        .glow(TrunkPartGlow(stops: [TrunkStop(color: TrunkRGBA(0xFFF8E0), location: 0),
                                    TrunkStop(color: metal.tones.dark, location: 0.7)],
                            cx: 0.35, cy: 0.35, rx: 1, ry: 1, farthestCorner: true))
    }

    // MARK: 錠前

    /// 錠前の胴の枠（モックの `bodyCss`）
    static func lockBody(_ shape: TrunkPartLockShape) -> (box: TrunkRect, radius: Double, round: Bool) {
        switch shape {
        case .plate: return (TrunkRect(x: 22, y: 26, w: 52, h: 46), 7, false)
        case .round: return (TrunkRect(x: 22, y: 22, w: 52, h: 52), 26, true)
        case .padlock: return (TrunkRect(x: 20, y: 40, w: 56, h: 44), 9, false)
        case .dial: return (TrunkRect(x: 18, y: 22, w: 60, h: 52), 8, false)
        case .twin: return (TrunkRect(x: 14, y: 30, w: 30, h: 40), 6, false)
        }
    }

    static func lockPaint(_ metal: TrunkPartMetal) -> TrunkPartPaint {
        .layers([shine(0.35, at: 0.35, 0.3, end: 0.45), .metal(metal)])
    }

    static func lock(_ l: TrunkPartLook.Lock) -> [TrunkPartOp] {
        var out: [TrunkPartOp] = []
        if l.shape == .padlock {
            let s = TrunkRect(x: 32, y: 14, w: 32, h: 34)
            out.append(.fill(TrunkShapes.arch(s, radius: 18, thickness: 7), .metal(.silver), bounds: s, evenOdd: true))
        }
        let body = lockBody(l.shape)
        let shape = body.round ? TrunkShapes.ellipse(body.box) : TrunkShapes.rect(body.box, body.radius)
        var inner: [TrunkPartOp] = [.fill(shape, lockPaint(l.metal), bounds: body.box, evenOdd: false),
                                    bottomShade(shape, body.box, 0.3), topLight(shape, body.box, 0.5)]
        let b = body.box
        if l.shape == .dial {
            // 回す輪（内の影 6px の白 15% と 2px の焦げ茶 50%）
            inner.append(.stroke(TrunkShapes.circle(b.x + 26, b.y + 26, 15), white(0.15), width: 6, dash: [], round: false))
            inner.append(.stroke(TrunkShapes.circle(b.x + 26, b.y + 26, 17), TrunkRGBA(r: 60, g: 40, b: 15, a: 0.5),
                                 width: 2, dash: [], round: false))
            var digits: [TrunkPartTextColumn.Item] = []
            for (i, n) in ["0", "4", "2"].enumerated() {
                let cell = TrunkRect(x: b.x + 42, y: b.y + 6 + Double(i) * 13, w: 14, h: 12)
                inner.append(.fill(TrunkShapes.rect(cell, 2), .solid(TrunkRGBA(0x0E0E10)), bounds: cell, evenOdd: false))
                digits.append(.text(TrunkPartText(text: n, size: 9, heavy: false, mincho: false, tracking: 0,
                                                  color: TrunkRGBA(0xE3C98F), tabular: true, lineHeight: 12 / 9, maxLines: 1),
                                    top: i == 0 ? 0 : 1))
            }
            inner.append(.text(TrunkPartTextColumn(box: TrunkRect(x: b.x + 42, y: b.y + 6, w: 14, h: 38), alignTop: true,
                                                   items: digits, transform: .identity)))
        }
        if let emblem = l.emblem {
            let top = l.shape == .padlock ? 4.0 : 6.0
            inner.append(.group(emblemOps(emblem, ink: l.metal.ink),
                                TrunkPartTransform(tx: b.midX, ty: b.y + top + 17), clip: nil))
        }
        if l.shape != .dial && l.shape != .twin {
            let bottom = l.shape == .padlock ? 9.0 : 7.0
            let hole = TrunkRect(x: b.midX - 3, y: b.maxY - bottom - 10, w: 6, h: 10)
            inner.append(.fill(TrunkShapes.cssRect(hole, rx: [3, 3, 1, 1]), .solid(TrunkRGBA(r: 20, g: 12, b: 4, a: 0.85)),
                               bounds: hole, evenOdd: false))
        }
        out.append(.group(inner, .identity, clip: nil))
        if l.shape == .twin {
            let t = TrunkRect(x: 52, y: 30, w: 30, h: 40)
            let ts = TrunkShapes.rect(t, 6)
            out.append(.group([.fill(ts, lockPaint(l.metal), bounds: t, evenOdd: false), topLight(ts, t, 0.5)],
                              .identity, clip: nil))
        }
        return out
    }

    /// 錠前の彫り（モックの SVG・viewBox -17 -17 34 34）
    static func emblemOps(_ e: TrunkLockEmblem, ink: TrunkRGBA) -> [TrunkPartOp] {
        func stroke(_ d: String, _ w: Double, round: Bool = false) -> TrunkPartOp {
            .stroke(SVGPath.parse(d), ink, width: w, dash: [], round: round)
        }
        func fill(_ segments: [SVGPath.Segment]) -> TrunkPartOp {
            .fill(segments, .solid(ink), bounds: TrunkRect(x: -17, y: -17, w: 34, h: 34), evenOdd: false)
        }
        func circle(_ r: Double, _ w: Double) -> TrunkPartOp { .stroke(TrunkShapes.circle(0, 0, r), ink, width: w, dash: [], round: false) }
        switch e {
        case .kiku:
            return [circle(13, 1.1),
                    stroke("M0 -13 C4 -6 4 -6 0 0 C-4 -6 -4 -6 0 -13 Z M13 0 C6 4 6 4 0 0 C6 -4 6 -4 13 0 Z M0 13 C-4 6 -4 6 0 0 C4 6 4 6 0 13 Z M-13 0 C-6 -4 -6 -4 0 0 C-6 4 -6 4 -13 0 Z M9 -9 C4 -6 4 -6 0 0 C6 -4 6 -4 9 -9 Z M9 9 C6 4 6 4 0 0 C4 6 4 6 9 9 Z M-9 9 C-4 6 -4 6 0 0 C-6 4 -6 4 -9 9 Z M-9 -9 C-6 -4 -6 -4 0 0 C-4 -6 -4 -6 -9 -9 Z", 1.1)]
        case .compass:
            let d = "M0 -13 L3 -3 L0 0 L-3 -3 Z M0 13 L3 3 L0 0 L-3 3 Z M-13 0 L-3 -3 L0 0 L-3 3 Z M13 0 L3 -3 L0 0 L3 3 Z"
            return [circle(13, 1.1), fill(SVGPath.parse(d)), stroke(d, 1.1)]
        case .helm:
            return [circle(9, 1.4), circle(3, 1.4),
                    stroke("M0 -15 V15 M-15 0 H15 M-10.6 -10.6 L10.6 10.6 M10.6 -10.6 L-10.6 10.6", 1.4, round: true)]
        case .train:
            return [fill(SVGPath.parse("M-13 6 V-2 H-4 V-8 H4 V-2 H10 L14 2 V6 Z")),
                    fill(TrunkShapes.circle(-8, 8, 3)), fill(TrunkShapes.circle(2, 8, 3)), fill(TrunkShapes.circle(10, 8.5, 2.4))]
        case .sakura:
            return [stroke("M0 -13 C5 -10 5 -5 0 -2 C-5 -5 -5 -10 0 -13 Z M12.4 -4 C11 1 6 3 1.9 -0.6 C4 -5.5 9 -7 12.4 -4 Z M7.6 10.5 C2.6 11 0 7 1.2 1.7 C6.4 1.6 9.6 5.6 7.6 10.5 Z M-7.6 10.5 C-9.6 5.6 -6.4 1.6 -1.2 1.7 C0 7 -2.6 11 -7.6 10.5 Z M-12.4 -4 C-9 -7 -4 -5.5 -1.9 -0.6 C-6 3 -11 1 -12.4 -4 Z", 1.1),
                    fill(TrunkShapes.circle(0, 0, 1.6))]
        case .wave:
            return [stroke("M-14 4 A7 7 0 0 1 0 4 A7 7 0 0 1 14 4 M-10 4 A3 3 0 0 1 -4 4 M4 4 A3 3 0 0 1 10 4 M-7 -4 A7 7 0 0 1 7 -4 M-3 -4 A3 3 0 0 1 3 -4", 1.1)]
        case .star:
            return [stroke("M0 -13 L3.8 -4 L13 -4 L5.6 1.6 L8.4 11 L0 5.4 L-8.4 11 L-5.6 1.6 L-13 -4 L-3.8 -4 Z", 1.2)]
        case .shell:
            return [stroke("M-13 6 A13 13 0 0 1 13 6 L0 12 Z", 1.1),
                    stroke("M0 12 L-9 -3 M0 12 L-4 -6 M0 12 L0 -7 M0 12 L4 -6 M0 12 L9 -3", 1.1)]
        }
    }

    // MARK: 内張り

    static func lining(_ paint: TrunkPartPaint) -> [TrunkPartOp] {
        let box = TrunkRect(x: 10, y: 10, w: 76, h: 76)
        let shape = TrunkShapes.rect(box, 6)
        let fold = TrunkRect(x: box.maxX - 26, y: box.maxY - 26, w: 26, h: 26)
        let foldPaint = TrunkPartPaint.linear(TrunkGradient(angle: 315, stops: [
            TrunkStop(color: black(0), location: 0.48), TrunkStop(color: black(0.35), location: 0.5),
            TrunkStop(color: white(0.18), location: 0.6), TrunkStop(color: black(0.15), location: 1),
        ]))
        return [.group([.fill(shape, paint, bounds: box, evenOdd: false),
                        .fill(TrunkShapes.rect(fold), foldPaint, bounds: fold, evenOdd: false),
                        .stroke(TrunkShapes.rect(box.inset(0.5), 5.5), black(0.2), width: 1, dash: [], round: false)],
                       .identity, clip: shape)]
    }

    // MARK: 手荷物タグ

    /// 札の角丸（モックの `r`）
    static func tagRadii(_ shape: TrunkTagShape) -> [Double] {
        switch shape {
        case .paper: return [4, 4, 6, 6]
        case .leather: return [10, 10, 10, 10]
        case .brass: return [8, 8, 8, 8]
        case .wood: return [6, 6, 6, 6]
        case .ticket: return [3, 3, 3, 3]
        }
    }

    static func tag(_ t: TrunkPartLook.Tag) -> [TrunkPartOp] {
        // 紐（`left: 46; top: 2; 3×22; rotate(8deg)`）
        let string: TrunkPartOp = .group([.fill(TrunkShapes.rect(TrunkRect(x: -1.5, y: -11, w: 3, h: 22), 1.5), .solid(t.string),
                                                bounds: TrunkRect(x: -1.5, y: -11, w: 3, h: 22), evenOdd: false)],
                                         TrunkPartTransform(tx: 47.5, ty: 13, rotation: 8), clip: nil)
        // 札（`left: 22; top: 16; 52×72; rotate(-6deg)`）。中の座標は札の真ん中が 0
        let local = TrunkRect(x: -26, y: -36, w: 52, h: 72)
        let shape = TrunkShapes.cssRect(local, rx: tagRadii(t.shape))
        let leather = t.shape == .leather
        let grain = TrunkPartPaint.dots(leather
            ? TrunkPartDots(color: black(0.18), tile: 4, center: 2, inner: 0.7, outer: 1.2)
            : TrunkPartDots(color: black(0.06), tile: 3, center: 1.5, inner: 0.6, outer: 0.9))
        var body: [TrunkPartOp] = [.fill(shape, .layers([grain, t.paint]), bounds: local, evenOdd: false)]
        if leather {
            body.append(.stroke(TrunkShapes.cssRect(local.inset(1.5), rx: [8.5, 8.5, 8.5, 8.5]), black(0.2),
                                width: 3, dash: [], round: false))
        }
        // 穴（8px・上 6・下 4・縁 2px）
        let paperish = t.shape == .paper || t.shape == .ticket
        body.append(.stroke(TrunkShapes.circle(0, local.y + 10, 5), paperish ? TrunkRGBA(0xB89A62) : black(0.3),
                            width: 2, dash: [], round: false))
        body.append(.fill(TrunkShapes.circle(0, local.y + 10, 4), .solid(TrunkRGBA(0x0B0B0B)),
                          bounds: TrunkRect(x: -4, y: local.y + 6, w: 8, h: 8), evenOdd: false))
        var items: [TrunkPartTextColumn.Item] = [
            .text(TrunkPartText(text: t.t1, size: 8, heavy: true, mincho: false, tracking: 0.06, color: t.fg), top: 0),
            .text(TrunkPartText(text: t.t2, size: 11, heavy: true, mincho: true, tracking: 0, color: t.fg, lineHeight: 1.15), top: 3),
        ]
        if paperish { items.append(.bar(t.fg, opacity: 0.75, height: 6, inset: 7, top: 5)) }
        // 字の枠（穴の下から・左右 3 の余白）
        body.append(.text(TrunkPartTextColumn(box: TrunkRect(x: local.x + 3, y: local.y + 18, w: local.w - 6, h: local.h - 18),
                                              alignTop: true, items: items, transform: .identity)))
        return [string, .group(body, TrunkPartTransform(tx: 48, ty: 52, rotation: -6), clip: shape)]
    }

    // MARK: ピンバッジ

    static func pinShape(_ shape: TrunkPinShape, _ r: TrunkRect) -> [SVGPath.Segment] {
        switch shape {
        case .circle: return TrunkShapes.ellipse(r)
        case .square: return TrunkShapes.rect(r, 12 * r.w / 64)
        case .banner: return TrunkShapes.polygon(r, [(0, 0), (1, 0), (1, 1), (0.5, 0.8), (0, 1)])
        case .shield:
            // `polygon(0 0, 100% 0, 100% 60%, 50% 100%, 0 60%)` に上の角丸 6
            let c = 6 * r.w / 64, k = 0.5522847498
            func p(_ x: Double, _ y: Double) -> SVGPath.Point { SVGPath.Point(x: r.x + x, y: r.y + y) }
            return [.move(p(c, 0)), .line(p(r.w - c, 0)), .cubic(c1: p(r.w - c * (1 - k), 0), c2: p(r.w, c * (1 - k)), to: p(r.w, c)),
                    .line(p(r.w, r.h * 0.6)), .line(p(r.w / 2, r.h)), .line(p(0, r.h * 0.6)), .line(p(0, c)),
                    .cubic(c1: p(0, c * (1 - k)), c2: p(c * (1 - k), 0), to: p(c, 0)), .close]
        }
    }

    static func pin(_ p: TrunkPartLook.Pin) -> [TrunkPartOp] {
        let rim = TrunkRect(x: 16, y: 16, w: 64, h: 64)
        let enamelBox = rim.inset(4)
        let rimShape = pinShape(p.shape, rim)
        let enamelShape = pinShape(p.shape, enamelBox)
        let icon = SVGPath.parse(p.icon.d)
        return [
            .fill(rimShape, .metal(p.metal), bounds: rim, evenOdd: false),
            .fill(enamelShape, .layers([shine(0.25, at: 0.35, 0.3, end: 0.5), .solid(p.enamel)]), bounds: enamelBox, evenOdd: false),
            .group([.fill(icon, .solid(p.ink), bounds: TrunkRect(x: -20, y: -20, w: 40, h: 40), evenOdd: false),
                    .stroke(icon, p.metal.darkTone, width: 1.6, dash: [], round: true)],
                   TrunkPartTransform(tx: 48, ty: 48), clip: nil),
            .fill(rimShape, .linear(TrunkGradient(angle: 140, stops: [TrunkStop(color: white(0.45), location: 0),
                                                                      TrunkStop(color: white(0), location: 0.32)])),
                  bounds: rim, evenOdd: false),
        ]
    }

    // MARK: ワッペン

    /// ワッペンの枠と角丸（モックの `sh`）
    static func patchBox(_ shape: TrunkPatchShape) -> (box: TrunkRect, rx: [Double], ellipse: Bool) {
        switch shape {
        case .circle: return (TrunkRect(x: 13, y: 13, w: 70, h: 70), [], true)
        case .oval: return (TrunkRect(x: 8, y: 19, w: 80, h: 58), [], true)
        case .rect: return (TrunkRect(x: 9, y: 20, w: 78, h: 56), [8, 8, 8, 8], false)
        case .shield: return (TrunkRect(x: 15, y: 11, w: 66, h: 74), [10, 10, 40, 40], false)
        }
    }

    /// ワッペンの字の大きさ（`Math.min(9, 58 / Math.max(4, t.length) * 1.25).toFixed(1)`）
    static func patchTextSize(_ text: String) -> Double {
        let raw = min(9, 58 / Double(max(4, text.count)) * 1.25)
        return (raw * 10).rounded() / 10
    }

    static func patch(_ p: TrunkPartLook.Patch) -> [TrunkPartOp] {
        let info = patchBox(p.shape)
        let box = info.box
        func shape(_ inset: Double) -> [SVGPath.Segment] {
            if info.ellipse { return TrunkShapes.ellipse(box.inset(inset)) }
            // 内の角丸は外 − 縁（CSS の決まり・辺に合わせて縮めたあとの値から引く）
            var f = 1.0
            for (sum, side) in [(info.rx[0] + info.rx[1], box.w), (info.rx[3] + info.rx[2], box.w),
                                (info.rx[0] + info.rx[3], box.h), (info.rx[1] + info.rx[2], box.h)] where sum > side {
                f = min(f, side / sum)
            }
            return TrunkShapes.cssRect(box.inset(inset), rx: info.rx.map { max(0, $0 * f - inset) })
        }
        let inner = box.inset(5)
        let cloth = TrunkPartPaint.layers([
            .stripes(angle: 45, period: 3, bands: [TrunkPartBand(from: 0, to: 1, color: white(0.06))]),
            .stripes(angle: -45, period: 3, bands: [TrunkPartBand(from: 0, to: 1, color: black(0.08))]),
            .solid(p.bg),
        ])
        let size = patchTextSize(p.text)
        let lineH = size * 1.2
        let total = 26 + 2 + lineH
        let top = inner.midY - total / 2
        let icon = SVGPath.parse(p.icon.d)
        let clip = TrunkShapes.rect(TrunkRect(x: -17, y: -13, w: 34, h: 26))
        return [
            .fill(shape(0), .solid(p.border), bounds: box, evenOdd: false),
            .fill(shape(5), cloth, bounds: inner, evenOdd: false),
            .stroke(shape(1), white(0.25), width: 2, dash: [4, 3], round: false),
            .stroke(shape(0.5), black(0.2), width: 1, dash: [], round: false),
            .group([.fill(icon, .solid(p.thread), bounds: TrunkRect(x: -17, y: -13, w: 34, h: 26), evenOdd: false),
                    .stroke(icon, black(0.35), width: 0.8, dash: [1.2, 0.8], round: false)],
                   TrunkPartTransform(tx: inner.midX, ty: top + 13), clip: clip),
            .text(TrunkPartTextColumn(box: TrunkRect(x: inner.x, y: top + 28, w: inner.w, h: lineH), alignTop: true,
                                      items: [.text(TrunkPartText(text: p.text, size: size, heavy: true, mincho: true,
                                                                  tracking: 0.08, color: p.thread, maxLines: 1,
                                                                  shadow: black(0.35)), top: 0)],
                                      transform: .identity)),
        ]
    }

    // MARK: チャーム

    static func charm(_ c: TrunkPartLook.Charm) -> [TrunkPartOp] {
        let ringBox = TrunkRect(x: 39, y: 4, w: 18, h: 18)
        let chain = TrunkRect(x: 46, y: 20, w: 4, h: 16)
        let icon = SVGPath.parse(c.icon.d)
        let iconBox = TrunkRect(x: -20, y: -20, w: 40, h: 40)
        return [
            .fill(TrunkShapes.ring(ringBox.midX, ringBox.midY, outer: 9, inner: 6), .metal(c.ringMetal), bounds: ringBox, evenOdd: true),
            .fill(TrunkShapes.rect(chain, 2),
                  .stripes(angle: 180, period: 4, bands: [TrunkPartBand(from: 0, to: 3, color: c.ringMetal.midTone),
                                                          TrunkPartBand(from: 3, to: 4, color: c.ringMetal.darkTone)]),
                  bounds: chain, evenOdd: false),
            // 56×56 の SVG（viewBox -20 -20 40 40）を `left: 20; top: 32` に・傾けて
            .group([.fill(icon, .solid(c.fill), bounds: iconBox, evenOdd: false),
                    .stroke(icon, c.metal.darkTone, width: 1.2, dash: [], round: true),
                    .group([.stroke(icon, white(0.55 * 0.7), width: 0.8, dash: [], round: true)],
                           TrunkPartTransform(tx: -0.6, ty: -0.6), clip: nil)],
                   TrunkPartTransform(tx: 48, ty: 60, rotation: c.rot, scale: 56.0 / 40), clip: nil),
        ]
    }

    // MARK: ホテルの鍵

    static func fobShape(_ fob: TrunkKeyFob, _ r: TrunkRect) -> [SVGPath.Segment] {
        switch fob {
        case .diamond: return TrunkShapes.polygon(r, [(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)])
        case .oval: return TrunkShapes.ellipse(r)
        case .tear:
            // `border-radius: 50% 50% 50% 50% / 30% 30% 70% 70%`
            return TrunkShapes.cssRect(r, rx: [r.w / 2, r.w / 2, r.w / 2, r.w / 2],
                                       ry: [r.h * 0.3, r.h * 0.3, r.h * 0.7, r.h * 0.7])
        case .rect: return TrunkShapes.rect(r, 6)
        }
    }

    static func key(_ k: TrunkPartLook.Key) -> [TrunkPartOp] {
        let bow = TrunkRect(x: 10, y: 8, w: 22, h: 22)
        let shaft = TrunkRect(x: 28, y: 16, w: 46, h: 6)
        let bit = TrunkRect(x: 62, y: 20, w: 12, h: 12)
        let link = TrunkRect(x: 18, y: 28, w: 6, h: 14)
        let fob = TrunkRect(x: 4, y: 40, w: 34, h: 50)
        let metal = TrunkPartPaint.metal(k.metal)
        let t1 = TrunkPartText(text: k.t1, size: 5.5, heavy: true, mincho: false, tracking: 0.08, color: k.ink, maxLines: 1)
        let no = TrunkPartText(text: k.no, size: 14, heavy: true, mincho: true, tracking: 0, color: k.ink, tabular: true,
                               lineHeight: 1.1, maxLines: 1)
        return [
            .fill(TrunkShapes.ring(bow.midX, bow.midY, outer: 11, inner: 6), metal, bounds: bow, evenOdd: true),
            .fill(TrunkShapes.rect(shaft, 3), metal, bounds: shaft, evenOdd: false),
            .fill(TrunkShapes.polygon(bit, [(0, 0), (1, 0), (1, 1), (0.7, 1), (0.7, 0.5), (0.4, 0.5), (0.4, 1), (0, 1)]),
                  metal, bounds: bit, evenOdd: false),
            .fill(TrunkShapes.rect(link, 2),
                  .stripes(angle: 180, period: 4, bands: [TrunkPartBand(from: 0, to: 3, color: k.metal.midTone),
                                                          TrunkPartBand(from: 3, to: 4, color: k.metal.darkTone)]),
                  bounds: link, evenOdd: false),
            .fill(fobShape(k.fob, fob), .layers([shine(0.4, at: 0.35, 0.25, end: 0.45), k.fobPaint]), bounds: fob, evenOdd: false),
            .text(TrunkPartTextColumn(box: fob, alignTop: false, items: [.text(t1, top: 0), .text(no, top: 0)], transform: .identity)),
        ]
    }

    // MARK: 字の置き場（画面が字を重ねる所）

    /// 手順の中の字を、外の置き方を畳んで取り出す（画面は Canvas の上に字を重ねる）
    static func textColumns(_ ops: [TrunkPartOp], _ outer: TrunkPartTransform = .identity) -> [TrunkPartTextColumn] {
        var out: [TrunkPartTextColumn] = []
        for op in ops {
            switch op {
            case .group(let children, let t, _):
                out += textColumns(children, t.within(outer))
            case .text(let column):
                out.append(TrunkPartTextColumn(box: column.box, alignTop: column.alignTop, items: column.items,
                                               transform: column.transform.within(outer)))
            case .fill, .stroke:
                break
            }
        }
        return out
    }

    /// 手順が実際に塗る所の外接の四角（96 の枠の座標・置き方を畳んで・線は太さの半分を足す・字は字の枠）。
    /// トランクに吊るす部品どうしが重ならないかを、枠（96×96）ではなく描いた中身で見る（#305）
    static func contentBounds(_ ops: [TrunkPartOp], _ outer: TrunkPartTransform = .identity) -> TrunkRect? {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func add(_ p: SVGPath.Point, pad: Double) {
            minX = min(minX, p.x - pad); maxX = max(maxX, p.x + pad)
            minY = min(minY, p.y - pad); maxY = max(maxY, p.y + pad)
        }
        func add(_ segments: [SVGPath.Segment], _ t: TrunkPartTransform, pad: Double) {
            for s in segments {
                switch s {
                case .move(let p), .line(let p): add(t.apply(p), pad: pad)
                case let .cubic(c1, c2, to): for p in [c1, c2, to] { add(t.apply(p), pad: pad) }
                case let .quad(c, to): for p in [c, to] { add(t.apply(p), pad: pad) }
                case .close: break
                }
            }
        }
        func add(_ r: TrunkRect?) {
            guard let r else { return }
            add(SVGPath.Point(x: r.x, y: r.y), pad: 0)
            add(SVGPath.Point(x: r.maxX, y: r.maxY), pad: 0)
        }
        for op in ops {
            switch op {
            case let .fill(segments, _, _, _):
                add(segments, outer, pad: 0)
            case let .stroke(segments, _, width, _, _):
                add(segments, outer, pad: width / 2 * outer.scale)
            case let .group(children, t, _):
                add(contentBounds(children, t.within(outer)))
            case .text(let column):
                let t = column.transform.within(outer)
                let b = column.box
                add([.move(SVGPath.Point(x: b.x, y: b.y)), .line(SVGPath.Point(x: b.maxX, y: b.y)),
                     .line(SVGPath.Point(x: b.maxX, y: b.maxY)), .line(SVGPath.Point(x: b.x, y: b.maxY))], t, pad: 0)
            }
        }
        guard minX.isFinite, minY.isFinite else { return nil }
        return TrunkRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    /// 読み上げの名前（「錠前 · 菊」）
    static func accessibilityLabel(_ part: TrunkPart) -> String {
        "\(part.kind.title) · \(part.name)"
    }
}

// MARK: - トランクに付けた部品（モック PartsOnTrunk・Equip）

/// 付けている部品を台帳から引いたもの（知らない id は無いものとして扱う）
struct TrunkFittings: Equatable {
    let handle: TrunkPart?
    let corner: TrunkPart?
    let lock: TrunkPart?
    let tag: TrunkPart?
    let charm: TrunkPart?
    let key: TrunkPart?
    let pins: [TrunkPart]
    let patches: [TrunkPart]

    static let none = TrunkFittings(.none)

    init(_ e: TrunkEquipped) {
        func one(_ id: String?, _ kind: TrunkPartKind) -> TrunkPart? {
            id.flatMap(TrunkPartCatalog.part).flatMap { $0.kind == kind ? $0 : nil }
        }
        handle = one(e.handle, .handle)
        corner = one(e.corner, .corner)
        lock = one(e.lock, .lock)
        tag = one(e.tag, .tag)
        charm = one(e.charm, .charm)
        key = one(e.key, .key)
        pins = e.pins.compactMap(TrunkPartCatalog.part).filter { $0.kind == .pin }.prefix(TrunkPartKind.pin.capacity).map { $0 }
        patches = e.patches.compactMap(TrunkPartCatalog.part).filter { $0.kind == .patch }
            .prefix(TrunkPartKind.patch.capacity).map { $0 }
    }

    var isEmpty: Bool {
        handle == nil && corner == nil && lock == nil && tag == nil && charm == nil && key == nil && pins.isEmpty && patches.isEmpty
    }

    /// 持ち手の面と太さ（モックの `P.handle`・`P.handleW || 10`）。2026-10-17 判断: 太さは部品の太さを
    /// トランクの持ち手（高さ 36）に合わせて 10 で止める（籐・樹脂・黒檀は 12〜15 だが、持ち手の輪が潰れる）
    var handlePaint: (paint: TrunkPartPaint, thickness: Double)? {
        guard let handle, case .handle(let h) = handle.look else { return nil }
        return (h.paint, min(10, h.width))
    }

    /// 角の面（モックの `P.corner`＝彫りの模様を上に重ねた金属）
    var cornerPaint: TrunkPartPaint? {
        guard let corner, case .corner(let c) = corner.look else { return nil }
        if let eng = TrunkPartDrawing.engraving(c.engrave) { return .layers([eng, c.paint]) }
        return c.paint
    }

    /// 錠前の金属（モックの `P.lock`。持ち手の付け根・尾錠も同じ金属になる）
    var lockMetal: TrunkPartMetal? {
        guard let lock, case .lock(let l) = lock.look else { return nil }
        return l.metal
    }

    /// 付けた角金具の形（L の字・彫り・透かし・鋲。トランクの角にも部品1点の絵と同じ形で描く・#305）
    var cornerLook: TrunkPartLook.Corner? {
        guard let corner, case .corner(let c) = corner.look else { return nil }
        return c
    }

    /// 錠前の部品を縮める割合の幅（型の錠前の高さに胴の高さを合わせる。小さすぎると彫り・数字が潰れ、
    /// 大きすぎると帯からはみ出す）
    static let lockMountScale: ClosedRange<Double> = 0.55...0.8

    /// 付けた錠前を、部品1点の絵（96 の枠）を縮めてトランクの錠前の場所に置く（#305）。
    /// 返すのは縮めた枠の一辺と左上（胴 360×268 の座標）。錠前の胴の真ん中（双子は2枚の真ん中）を型の錠前の真ん中に。
    /// 前は部品の金属で型の錠前を塗るだけで、南京錠・ダイヤル・双子の形も紋も出なかった
    func lockMount(_ look: TrunkLook) -> (side: Double, x: Double, y: Double)? {
        guard let lock, case .lock(let l) = lock.look else { return nil }
        let body = TrunkPartDrawing.lockBody(l.shape).box
        let all = TrunkPartDrawing.contentBounds(TrunkPartDrawing.lock(l)) ?? body
        let k = min(Self.lockMountScale.upperBound, max(Self.lockMountScale.lowerBound, look.lock.height / body.h))
        let cx = 180.0, cy = TrunkLooks.lockTop(look) + look.lock.height / 2
        return (TrunkPartDrawing.size * k, cx - all.midX * k, cy - body.midY * k)
    }

    /// 吊るす部品の紐（立体で、上の面の持ち手から正面の上の縁まで渡す・#305）の太さと色。部品の紐・鎖の色と太さを
    /// 縮みに合わせて（手荷物タグは紐、チャームは鎖、鍵は輪）
    static func cord(_ p: Placement) -> (width: Double, color: TrunkRGBA)? {
        switch p.part.look {
        case .tag(let t): return (3 * p.scale, t.string)
        case .charm(let c): return (4 * p.scale, c.ringMetal.midTone)
        case .key(let k): return (6 * p.scale, k.metal.midTone)
        default: return nil
        }
    }

    /// トランクの上に重ねる部品（ピン・ワッペン・チャーム・鍵・タグ）
    struct Placement: Equatable {
        let part: TrunkPart
        /// 縮めた枠の左上（360×300 の絵の座標）
        let x: Double
        let y: Double
        let scale: Double
        let rot: Double
        /// 回す中心（枠の割合）
        let anchorX: Double
        let anchorY: Double
        /// 胴に付く（3D の箱の表にも描く）。false は持ち手から吊るすもの
        let onBody: Bool

        /// 縮めた枠の一辺
        var side: Double { TrunkPartDrawing.size * scale }

        /// 吊るす点（回す中心・360×300 の絵の座標）。吊るす部品は紐・輪・鍵の頭がここに来る
        var hangX: Double { x + anchorX * side }
        var hangY: Double { y + anchorY * side }

        /// 縮めて回したあとの、描いた中身の外接の四角（360×300 の絵の座標・#305 の重なりの見張り）
        var frame: TrunkRect {
            let b = TrunkPartDrawing.contentBounds(TrunkPartDrawing.ops(part))
                ?? TrunkRect(x: 0, y: 0, w: TrunkPartDrawing.size, h: TrunkPartDrawing.size)
            let scaled = TrunkRect(x: x + b.x * scale, y: y + b.y * scale, w: b.w * scale, h: b.h * scale)
            return scaled.rotated(rot, aroundX: hangX, y: hangY)
        }
    }

    /// 吊るす部品の置き場（#305 の 2026-10-18 判断）。
    ///
    /// 板 Equip のチャーム（112,26）と鍵（196,30）は、ラベルからできる手荷物タグ（x 216・252・278・`TrunkLooks.tagSlots`）
    /// と、後から足した部品の手荷物タグ（84,34）に重なっていた（鳥居のチャームが「FIRST CLASS」の札に、鍵が行き先の
    /// タグに）。**ラベルのタグは持ち手の右に吊るす**（板 Trunk のまま）ので、部品は持ち手の左から真ん中へ
    /// 「部品のタグ → 鍵 → チャーム」の順に並べ、どの組み合わせ（部品のある・なし × ラベルのタグ 0〜3 枚）でも
    /// 描いた中身が交わらないようにする（`TrunkPartsTests.testHangingNeverOverlaps`）。
    /// - 部品のタグ: 持ち手の左の外に吊るす（ラベルのタグを右の外に吊るすのと対に）
    /// - 鍵: 持ち手の左の付け根（120〜140）から、鍵の頭（96 の枠の 21）で吊るす
    /// - チャーム: 持ち手の真ん中寄り（右のラベルのタグの手前まで）
    /// 縮み・傾きは板のまま（タグ 0.5・−12°、チャーム 0.6・6°、鍵 0.62・−10°）
    enum Hang {
        /// `(左, 上, 縮み, 傾き, 中心x, 中心y)`（板 Equip と同じ書き方・トランクは上 20）
        static let tag = (left: 26.0, top: 34.0, scale: 0.5, rot: -12.0, ax: 0.5, ay: 0.0)
        static let key = (left: 96.0, top: 30.0, scale: 0.62, rot: -10.0, ax: 21.0 / 96, ay: 0.0)
        static let charm = (left: 142.0, top: 26.0, scale: 0.6, rot: 6.0, ax: 0.5, ay: 0.0)
    }

    /// 重ねる部品の置き場（モック Equip の `left`・`top`・`transform` を 360×300 の絵へ）。
    /// CSS の `transform-origin` を残すため、縮めた枠の左上をここで出す
    var placements: [Placement] {
        // モック Equip はトランクを上 20 に置く。`(左, 上, 縮み, 傾き, 中心x, 中心y)`
        func place(_ part: TrunkPart, _ left: Double, _ top: Double, _ s: Double, _ rot: Double,
                   _ ax: Double, _ ay: Double, body: Bool) -> Placement {
            let box = TrunkPartDrawing.size
            return Placement(part: part, x: left + ax * box * (1 - s), y: top - 20 + ay * box * (1 - s), scale: s, rot: rot,
                             anchorX: ax, anchorY: ay, onBody: body)
        }
        var out: [Placement] = []
        // ピン: 左のベルトに縦に（モックの 2 つは 132・186。3つ目は同じ間で下へ・2026-10-17 判断）
        for (i, pin) in pins.enumerated() {
            out.append(place(pin, 92, 132 + Double(i) * 54, 0.52, 0, 0, 0, body: true))
        }
        // ワッペン: 右下（モック）・2つ目は左下（モックに無い・2026-10-17 判断）
        for (i, patch) in patches.enumerated() {
            out.append(i == 0 ? place(patch, 252, 224, 0.58, -8, 0, 0, body: true)
                              : place(patch, 18, 216, 0.58, 7, 0, 0, body: true))
        }
        // 吊るす部品（手荷物タグ・チャーム・鍵）: 重ならない置き場（`Hang`・#305）
        if let tag { let h = Hang.tag; out.append(place(tag, h.left, h.top, h.scale, h.rot, h.ax, h.ay, body: false)) }
        if let charm { let h = Hang.charm; out.append(place(charm, h.left, h.top, h.scale, h.rot, h.ax, h.ay, body: false)) }
        if let key { let h = Hang.key; out.append(place(key, h.left, h.top, h.scale, h.rot, h.ax, h.ay, body: false)) }
        return out
    }
}
