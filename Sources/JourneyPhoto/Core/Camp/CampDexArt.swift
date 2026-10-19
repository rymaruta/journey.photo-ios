import Foundation

// 図鑑の部品の絵（板 CampDex の 120 × 96 の SVG）を読む。線（path の d）は既存の `SVGPath` で読む。
//
// 板の注記は「部品の絵は SceneKit で 1 個ずつ回して撮った静止画を一覧に使う」だが、板の 3D に形がある部品は
// 9 個だけ（付箋「部品の Camp の値」）。残りの 87 個を板の絵と違う形で作ると図鑑が板からずれるので、
// **96 個とも板の絵をそのまま描く**（2026-10-18 判断）。読むのは path / ellipse / circle / rect と、
// 塗り・線・濃さ・破線・板の 10 の階調（`dxchrome` ほか）だけ。

/// 塗り方
enum CampArtPaint: Equatable, Sendable {
    case color(UInt32)
    /// 板の階調（`dxchrome` など）
    case gradient(String)
}

/// 絵の形 1 つ
struct CampArtElement: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        /// 線（既存の `SVGPath` で読んだ並び。旅のトランクの絵と同じ道具）
        case path([SVGPath.Segment])
        case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
        case rect(x: Double, y: Double, w: Double, h: Double, rx: Double)
    }

    var shape: Shape
    var fill: CampArtPaint?
    var stroke: CampArtPaint?
    var strokeWidth: Double = 1
    var opacity: Double = 1
    var dash: [Double] = []

    /// 形を囲む四角（階調を形に合わせる・SVG の objectBoundingBox）
    var bounds: (x: Double, y: Double, w: Double, h: Double) {
        switch shape {
        case let .ellipse(cx, cy, rx, ry): return (cx - rx, cy - ry, 2 * rx, 2 * ry)
        case let .rect(x, y, w, h, _): return (x, y, w, h)
        case .path(let ops):
            var pts: [CampVec2] = []
            for op in ops {
                switch op {
                case .move(let p), .line(let p): pts.append(CampVec2(p.x, p.y))
                case let .cubic(a, b, c): pts += [a, b, c].map { CampVec2($0.x, $0.y) }
                case let .quad(a, b): pts += [a, b].map { CampVec2($0.x, $0.y) }
                case .close: break
                }
            }
            guard let f = pts.first else { return (0, 0, 0, 0) }
            var lo = f, hi = f
            for p in pts {
                lo = CampVec2(min(lo.x, p.x), min(lo.y, p.y))
                hi = CampVec2(max(hi.x, p.x), max(hi.y, p.y))
            }
            return (lo.x, lo.y, hi.x - lo.x, hi.y - lo.y)
        }
    }
}

/// 板の階調（CampDex の `<defs>`）
struct CampArtGradient: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// 形の枠の中で (x1, y1) → (x2, y2)
        case linear(x1: Double, y1: Double, x2: Double, y2: Double)
        /// 形の枠の中の中心 (cx, cy)・半径 r
        case radial(cx: Double, cy: Double, r: Double)
    }

    let kind: Kind
    /// (位置, 色, 濃さ)
    let stops: [(Double, UInt32, Double)]

    static func == (a: CampArtGradient, b: CampArtGradient) -> Bool {
        a.kind == b.kind && a.stops.count == b.stops.count
            && zip(a.stops, b.stops).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
    }
}

enum CampDexArt {

    /// 絵の枠（板: 120 × 96）
    static let viewBox = CampVec2(120, 96)

    static let gradients: [String: CampArtGradient] = [
        "dxchrome": .init(kind: .linear(x1: 0, y1: 0, x2: 0, y2: 1),
                          stops: [(0, 0xF7F8F9, 1), (0.42, 0x9A9EA3, 1), (0.55, 0xE8E9EB, 1), (1, 0x5D6166, 1)]),
        "dxbrass": .init(kind: .linear(x1: 0, y1: 0, x2: 0, y2: 1),
                         stops: [(0, 0xF6E3B0, 1), (0.45, 0xC9A66B, 1), (0.7, 0x6E5530, 1), (1, 0xD8B97E, 1)]),
        "dxrubber": .init(kind: .linear(x1: 0, y1: 0, x2: 0, y2: 1), stops: [(0, 0x3A3A3D, 1), (1, 0x0C0C0D, 1)]),
        "dxblack": .init(kind: .linear(x1: 0, y1: 0, x2: 0, y2: 1), stops: [(0, 0x46484D, 1), (1, 0x141416, 1)]),
        "dxwood": .init(kind: .linear(x1: 0, y1: 0, x2: 1, y2: 1), stops: [(0, 0xC08A55, 1), (1, 0x7A5230, 1)]),
        "dxwoodD": .init(kind: .linear(x1: 0, y1: 0, x2: 1, y2: 1), stops: [(0, 0x8A5C34, 1), (1, 0x4A3018, 1)]),
        "dxcanvas": .init(kind: .linear(x1: 0, y1: 0, x2: 0, y2: 1), stops: [(0, 0xF2ECDC, 1), (1, 0xC2B79E, 1)]),
        "dxpaint": .init(kind: .linear(x1: 0, y1: 0, x2: 0, y2: 1), stops: [(0, 0x7A828C, 1), (1, 0x3A3F47, 1)]),
        "dxglass": .init(kind: .linear(x1: 0, y1: 0, x2: 1, y2: 1),
                         stops: [(0, 0x6F8AA0, 1), (0.5, 0x24323E, 1), (1, 0x0F161C, 1)]),
        "dxsheen": .init(kind: .linear(x1: 0, y1: 0, x2: 1, y2: 1),
                         stops: [(0.2, 0xFFFFFF, 0), (0.42, 0xFFFFFF, 0.35), (0.55, 0xFFFFFF, 0)]),
        "dxshade": .init(kind: .linear(x1: 0, y1: 0, x2: 0, y2: 1), stops: [(0, 0x000000, 0), (1, 0x000000, 0.45)]),
        "dxglow": .init(kind: .radial(cx: 0.5, cy: 0.5, r: 0.5),
                        stops: [(0, 0xFFE2A6, 0.95), (0.4, 0xFFB35C, 0.35), (1, 0xFF9A3C, 0)]),
        "dxleaf": .init(kind: .radial(cx: 0.35, cy: 0.3, r: 0.8), stops: [(0, 0x8FAE55, 1), (1, 0x2C4A22, 1)]),
        "dxball": .init(kind: .radial(cx: 0.35, cy: 0.3, r: 0.75),
                        stops: [(0, 0xFFFFFF, 0.7), (0.4, 0xFFFFFF, 0), (1, 0x000000, 0.35)]),
    ]

    /// 部品の絵（板の id か、`camp.` 付きの id）
    static func elements(for id: String) -> [CampArtElement] {
        let board = id.hasPrefix(CampCatalog.prefix) ? String(id.dropFirst(CampCatalog.prefix.count)) : id
        guard let source = sources[board] else { return [] }
        return parse(source)
    }

    // MARK: - 読む

    /// SVG の中身（`<path …/>` の並び）を読む
    static func parse(_ source: String) -> [CampArtElement] {
        var out: [CampArtElement] = []
        var rest = Substring(source)
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].firstIndex(of: ">") else { break }
            let tag = rest[rest.index(after: open)..<close]
            rest = rest[rest.index(after: close)...]
            if tag.hasPrefix("/") { continue }
            let name = tag.prefix { $0.isLetter }
            let attrs = attributes(String(tag.dropFirst(name.count)))
            func num(_ k: String) -> Double { Double(attrs[k] ?? "") ?? 0 }
            let shape: CampArtElement.Shape
            switch name {
            case "path": shape = .path(SVGPath.parse(attrs["d"] ?? ""))
            case "ellipse": shape = .ellipse(cx: num("cx"), cy: num("cy"), rx: num("rx"), ry: num("ry"))
            case "circle": shape = .ellipse(cx: num("cx"), cy: num("cy"), rx: num("r"), ry: num("r"))
            case "rect": shape = .rect(x: num("x"), y: num("y"), w: num("width"), h: num("height"), rx: num("rx"))
            default: continue
            }
            var e = CampArtElement(shape: shape)
            // SVG の既定: 塗りは黒・線は無し
            e.fill = attrs["fill"].map(paint) ?? .color(0x000000)
            e.stroke = attrs["stroke"].flatMap { $0 == "none" ? nil : paint($0) }
            if let w = attrs["stroke-width"].flatMap(Double.init) { e.strokeWidth = w }
            if let o = attrs["opacity"].flatMap(Double.init) { e.opacity = o }
            if let d = attrs["stroke-dasharray"] { e.dash = d.split(separator: " ").compactMap { Double($0) } }
            if attrs["fill"] == "none" { e.fill = nil }
            out.append(e)
        }
        return out
    }

    static func attributes(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var rest = Substring(text)
        while let eq = rest.firstIndex(of: "=") {
            let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
            let afterEq = rest[rest.index(after: eq)...]
            guard let q1 = afterEq.firstIndex(of: "\"") else { break }
            let valueStart = afterEq.index(after: q1)
            guard let q2 = afterEq[valueStart...].firstIndex(of: "\"") else { break }
            out[key] = String(afterEq[valueStart..<q2])
            rest = afterEq[afterEq.index(after: q2)...]
        }
        return out
    }

    /// 色（#rgb・#rrggbb・url(#…)）
    static func paint(_ v: String) -> CampArtPaint? {
        if v == "none" { return nil }
        if v.hasPrefix("url(#") {
            return .gradient(String(v.dropFirst(5).dropLast()))
        }
        guard v.hasPrefix("#") else { return .color(0x000000) }
        var hex = String(v.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        return .color(UInt32(hex, radix: 16) ?? 0)
    }
}
