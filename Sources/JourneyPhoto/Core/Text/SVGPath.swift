import Foundation

/// SVG の `d`（線の書き方）を、直線と3次の曲線の並びに読み直す（旅のトランク・2026-10-17）。
///
/// モックのラベルとトランクの絵は SVG で描いてある。**手で写し替えると数字を取り違える**ので、
/// 文字のまま持ち、ここで読む。画面は並びをそのまま `Path` に移すだけ。
///
/// 読むのは `M L H V C S Q T A Z`（大文字＝絶対座標・小文字＝相対座標。小文字はキャンプ場の部品の絵・2026-10-18）。
/// 弧（`A`）は SVG の決まり（端点から中心への変換・半径が足りなければ広げる）で
/// 90° 以下の3次の曲線に分ける。
enum SVGPath {

    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    enum Segment: Equatable {
        case move(Point)
        case line(Point)
        case cubic(c1: Point, c2: Point, to: Point)
        case quad(c: Point, to: Point)
        case close
    }

    static func parse(_ d: String) -> [Segment] {
        let tokens = tokenize(d)
        var out: [Segment] = []
        var i = 0
        var command: Character = "M"
        var current = Point(x: 0, y: 0)
        var start = current

        func number() -> Double? {
            guard i < tokens.count, case .number(let v) = tokens[i] else { return nil }
            i += 1
            return v
        }
        func point() -> Point? {
            guard let x = number(), let y = number() else { return nil }
            return Point(x: x, y: y)
        }

        // 直前の曲線の制御点（S・T の映し返し）
        var lastCubic: Point?
        var lastQuad: Point?
        while i < tokens.count {
            if case .command(let c) = tokens[i] {
                command = c
                i += 1
                if c == "Z" || c == "z" {
                    out.append(.close)
                    current = start
                    lastCubic = nil
                    lastQuad = nil
                    continue
                }
            }
            // 小文字は相対座標（今の点からの差）。キャンプ場の部品の絵（板 CampDex・2026-10-18）が使う
            let relative = command.isLowercase && command != "a"
            func at(_ p: Point) -> Point { relative ? Point(x: current.x + p.x, y: current.y + p.y) : p }
            let upper = Character(command.uppercased())
            var cubic: Point?
            var quad: Point?
            switch command == "a" ? "a" : upper {
            case "M":
                guard let p = point().map(at) else { return out }
                out.append(.move(p))
                current = p
                start = p
                // 続く座標は直線（SVG の決まり）
                command = relative ? "l" : "L"
            case "L":
                guard let p = point().map(at) else { return out }
                out.append(.line(p))
                current = p
            case "H":
                guard let x = number() else { return out }
                current = Point(x: relative ? current.x + x : x, y: current.y)
                out.append(.line(current))
            case "V":
                guard let y = number() else { return out }
                current = Point(x: current.x, y: relative ? current.y + y : y)
                out.append(.line(current))
            case "C":
                guard let c1 = point().map(at), let c2 = point().map(at), let p = point().map(at) else { return out }
                out.append(.cubic(c1: c1, c2: c2, to: p))
                current = p
                cubic = c2
            case "S":
                guard let c2 = point().map(at), let p = point().map(at) else { return out }
                let c1 = lastCubic.map { Point(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                out.append(.cubic(c1: c1, c2: c2, to: p))
                current = p
                cubic = c2
            case "Q":
                guard let c = point().map(at), let p = point().map(at) else { return out }
                out.append(.quad(c: c, to: p))
                current = p
                quad = c
            case "T":
                guard let p = point().map(at) else { return out }
                let c = lastQuad.map { Point(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                out.append(.quad(c: c, to: p))
                current = p
                quad = c
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let large = number(), let sweep = number(), let p = point() else { return out }
                out += arc(from: current, to: p, rx: rx, ry: ry, rotation: rotation,
                           largeArc: large != 0, sweep: sweep != 0)
                current = p
            case "a":
                // 相対の弧（部品の汽車の車輪 `a3 3 0 1 0 0.1 0`・2026-10-17）。端点だけが今の点からの差
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let large = number(), let sweep = number(), let d = point() else { return out }
                let p = Point(x: current.x + d.x, y: current.y + d.y)
                out += arc(from: current, to: p, rx: rx, ry: ry, rotation: rotation,
                           largeArc: large != 0, sweep: sweep != 0)
                current = p
            default:
                // 知らない命令はそこで止める（描けるところまで）
                return out
            }
            lastCubic = cubic
            lastQuad = quad
        }
        return out
    }

    /// 並びをずらす（SVG の `translate` の代わり）
    static func translate(_ segments: [Segment], dx: Double, dy: Double) -> [Segment] {
        func m(_ p: Point) -> Point { Point(x: p.x + dx, y: p.y + dy) }
        return segments.map {
            switch $0 {
            case .move(let p): return .move(m(p))
            case .line(let p): return .line(m(p))
            case let .cubic(c1, c2, to): return .cubic(c1: m(c1), c2: m(c2), to: m(to))
            case let .quad(c, to): return .quad(c: m(c), to: m(to))
            case .close: return .close
            }
        }
    }

    // MARK: 丸と四角（SVG の `<circle>`・`<rect>` を同じ並びにする）

    /// 円（`<circle cx cy r>`）。90° ずつの4本の曲線
    static func circle(cx: Double, cy: Double, r: Double) -> [Segment] {
        ellipse(cx: cx, cy: cy, rx: r, ry: r)
    }

    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> [Segment] {
        let k = 0.5522847498
        return [
            .move(Point(x: cx + rx, y: cy)),
            .cubic(c1: Point(x: cx + rx, y: cy + ry * k), c2: Point(x: cx + rx * k, y: cy + ry), to: Point(x: cx, y: cy + ry)),
            .cubic(c1: Point(x: cx - rx * k, y: cy + ry), c2: Point(x: cx - rx, y: cy + ry * k), to: Point(x: cx - rx, y: cy)),
            .cubic(c1: Point(x: cx - rx, y: cy - ry * k), c2: Point(x: cx - rx * k, y: cy - ry), to: Point(x: cx, y: cy - ry)),
            .cubic(c1: Point(x: cx + rx * k, y: cy - ry), c2: Point(x: cx + rx, y: cy - ry * k), to: Point(x: cx + rx, y: cy)),
            .close,
        ]
    }

    /// 四角（`<rect x y width height rx>`）
    static func rect(x: Double, y: Double, w: Double, h: Double, r: Double = 0) -> [Segment] {
        guard r > 0 else {
            return [.move(Point(x: x, y: y)), .line(Point(x: x + w, y: y)), .line(Point(x: x + w, y: y + h)),
                    .line(Point(x: x, y: y + h)), .close]
        }
        let r = min(r, w / 2, h / 2)
        let k = 0.5522847498 * r
        return [
            .move(Point(x: x + r, y: y)),
            .line(Point(x: x + w - r, y: y)),
            .cubic(c1: Point(x: x + w - r + k, y: y), c2: Point(x: x + w, y: y + r - k), to: Point(x: x + w, y: y + r)),
            .line(Point(x: x + w, y: y + h - r)),
            .cubic(c1: Point(x: x + w, y: y + h - r + k), c2: Point(x: x + w - r + k, y: y + h), to: Point(x: x + w - r, y: y + h)),
            .line(Point(x: x + r, y: y + h)),
            .cubic(c1: Point(x: x + r - k, y: y + h), c2: Point(x: x, y: y + h - r + k), to: Point(x: x, y: y + h - r)),
            .line(Point(x: x, y: y + r)),
            .cubic(c1: Point(x: x, y: y + r - k), c2: Point(x: x + r - k, y: y), to: Point(x: x + r, y: y)),
            .close,
        ]
    }

    // MARK: 弧（SVG 1.1 の付録 F.6.5・F.6.6）

    static func arc(from p0: Point, to p1: Point, rx: Double, ry: Double, rotation: Double,
                    largeArc: Bool, sweep: Bool) -> [Segment] {
        if p0 == p1 { return [] }
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0 else { return [.line(p1)] }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        // 半径が足りなければ広げる
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : (max(0, num) / den).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let pieces = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(pieces)
        let t = 4.0 / 3.0 * tan(step / 4)
        var out: [Segment] = []
        var a = theta1
        func onEllipse(_ angle: Double) -> (x: Double, y: Double, dx: Double, dy: Double) {
            let ca = cos(angle), sa = sin(angle)
            let x = cx + rx * ca * cosPhi - ry * sa * sinPhi
            let y = cy + rx * ca * sinPhi + ry * sa * cosPhi
            // 接線の向き（角度で微分）
            let dx = -rx * sa * cosPhi - ry * ca * sinPhi
            let dy = -rx * sa * sinPhi + ry * ca * cosPhi
            return (x, y, dx, dy)
        }
        for k in 0..<pieces {
            let b = a + step
            let s = onEllipse(a), e = onEllipse(b)
            let end = k == pieces - 1 ? p1 : Point(x: e.x, y: e.y)
            out.append(.cubic(c1: Point(x: s.x + t * s.dx, y: s.y + t * s.dy),
                              c2: Point(x: e.x - t * e.dx, y: e.y - t * e.dy), to: end))
            a = b
        }
        return out
    }

    // MARK: 字句

    private enum Token { case command(Character), number(Double) }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        func flush() {
            if !buffer.isEmpty, let v = Double(buffer) { tokens.append(.number(v)) }
            buffer = ""
        }
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush()
                tokens.append(.command(ch))
            } else if ch == "-" {
                // 「10-5」は2つの数（前が指数の e のときだけ続ける）
                if let last = buffer.last, last == "e" || last == "E" {
                    buffer.append(ch)
                } else {
                    flush()
                    buffer.append(ch)
                }
            } else if ch == "." {
                // 「.5.5」は 0.5 と 0.5
                if buffer.contains(".") { flush() }
                buffer.append(ch)
            } else if ch.isNumber || ch == "e" || ch == "E" {
                buffer.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }
}
