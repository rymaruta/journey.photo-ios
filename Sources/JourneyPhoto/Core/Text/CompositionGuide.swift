import Foundation

/// 「構図を重ねて撮る」（Pro・2026-10-10 owner「有名な構図からマイナーな構図まで欲しい」）の、
/// 画面を持たない決まり。線の形はすべてここで計算し、Linux の試験で見張る。
///
/// 画面は `Features/Spots/ComposeGuideView.swift`（撮る画面）・`CompositionOverlay.swift`（線を描く）・
/// `CompositionPicker.swift`（構図のシート）。覚えておく値は `Core/Storage/CompositionPreferences.swift`。
///
/// **座標**: 撮れる範囲（撮る画面の 3:4 の枠）の左上を (0,0)・右下を (1,1) にした自前の座標
/// （`GuidePoint`）。y は下向き。`aspect` は枠の**幅÷高さ**（縦持ちの 3:4 なら 0.75）。
/// 「ピクセルの上で 45°」「正方形」のように縦横比で形が変わるものは、幅 `aspect`・高さ 1 の
/// 面で計算してから 0〜1 に戻す。
///
/// **線は写真に焼き込まない**（撮る画面の重ねだけ。撮った写真には何も入らない・`ComposeCamera` の注記）。
enum CompositionGuide {

    /// 黄金比 φ
    static let phi = (1 + 5.0.squareRoot()) / 2

    // MARK: - 線の濃さ

    /// 構図の線の濃さ（シートの下のスライダー）。白 1pt の線を、映像に埋もれず写真を邪魔しない範囲で
    static let lineOpacityRange: ClosedRange<Double> = 0.15...0.7
    /// 既定（板の三分割の線は白 35%）
    static let defaultLineOpacity = 0.35

    /// 範囲の内側に収める。数でない値は既定に戻す
    static func clampedLineOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultLineOpacity }
        return min(max(value, lineOpacityRange.lowerBound), lineOpacityRange.upperBound)
    }

    // MARK: - よく使う（最近の構図）

    /// 最近の構図の数（シートのいちばん上の段）
    static let recentLimit = 4

    /// 選んだ構図を最近の先頭に足す。**重ねて並べない**・上限 4
    static func recents(adding kind: CompositionKind, to list: [CompositionKind]) -> [CompositionKind] {
        Array(([kind] + list.filter { $0 != kind }).prefix(recentLimit))
    }

    // MARK: - 線

    /// 構図の線（0〜1 の座標）。向きの番号が範囲の外なら内側へ戻す。
    /// - Parameter aspect: 枠の幅÷高さ（0 以下・数でないときは 3:4 とみなす）
    static func marks(_ kind: CompositionKind, variant: Int, aspect: Double) -> [GuideMark] {
        let r = validAspect(aspect)
        let v = kind.normalizedVariant(variant)
        let dashed = kind.section == .shape
        let raw = rawMarks(kind, variant: v, aspect: r)
        return raw.map { dashed && !$0.isFill ? $0.withDash() : $0 }
    }

    /// 切り出し枠（比率の枠・ルート長方形）。枠の無い構図は nil。枠の中のいちばん大きい、中央に置いた長方形
    static func cropRect(_ kind: CompositionKind, variant: Int, aspect: Double) -> GuideRect? {
        let r = validAspect(aspect)
        guard let ratio = cropRatio(kind, variant: kind.normalizedVariant(variant), frameAspect: r) else { return nil }
        return centeredRect(ratio: ratio, frameAspect: r)
    }

    /// 縦横比（幅÷高さ）`ratio` の、枠いっぱいで中央の長方形
    static func centeredRect(ratio: Double, frameAspect r: Double) -> GuideRect {
        if ratio >= r {
            // 横長: 幅いっぱい・高さを縮める
            let h = r / ratio
            return GuideRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
        let w = ratio / r
        return GuideRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
    }

    /// 黄金螺旋の渦の中心（目を置く所）
    static func spiralEye(variant: Int) -> GuidePoint {
        let v = CompositionKind.goldenSpiral.normalizedVariant(variant)
        let eye = GuidePoint(x: 1 / (1 + 1 / (phi * phi)), y: 1 - 1 / (1 + 1 / (phi * phi)))
        return spiralTransform(v).apply(eye)
    }

    /// 黄金三角形の垂線の足（2つ）。目を置く所
    static func goldenTriangleFeet(variant: Int, aspect: Double) -> [GuidePoint] {
        let r = validAspect(aspect)
        let feet = goldenFeet(aspect: r)
        return CompositionKind.goldenTriangle.normalizedVariant(variant) == 0
            ? [feet.rising1, feet.rising2] : [feet.falling1, feet.falling2]
    }

    // MARK: - 水準器

    /// 水平とみなす傾き（度）。これより小さければ線を太くする
    static let levelToleranceDegrees = 1.0

    /// 端末の重力（CoreMotion の `gravity` の x・y）から、画面の上で水平線を回す角度（度・時計回りが正）。
    /// 縦に立てて水平なら 0、右へ傾けると負（画面の上で水平線は反時計回りに見える）
    static func levelAngle(gravityX: Double, gravityY: Double) -> Double? {
        guard gravityX.isFinite, gravityY.isFinite, abs(gravityX) + abs(gravityY) > 0.2 else { return nil }
        // 端末を時計回りに θ 傾けると gravity ≈ (sin θ, -cos θ)。画面の上の水平線は -θ
        return -atan2(gravityX, -gravityY) * 180 / .pi
    }

    /// 水平か（縦持ち・横持ちのどちらでも、直角の倍数から 1° 以内）
    static func isLevel(_ degrees: Double) -> Bool {
        guard degrees.isFinite else { return false }
        let m = abs(degrees).truncatingRemainder(dividingBy: 90)
        return min(m, 90 - m) < levelToleranceDegrees
    }

    /// 水準器の線。真ん中の線（端末の傾きで回る）と、左右の端の短い目盛り（動かない）
    static func levelMarks(aspect: Double, degrees: Double) -> [GuideMark] {
        let r = validAspect(aspect)
        let a = (degrees.isFinite ? degrees : 0) * .pi / 180
        // 長さはピクセルの上で短辺の 0.7（回しても枠からはみ出さない）
        let half = min(r, 1) * 0.35
        let cx = r / 2, cy = 0.5
        let dx = cos(a) * half, dy = sin(a) * half
        let line = GuideMark(.segment(px(cx - dx, cy - dy, r), px(cx + dx, cy + dy, r)), bold: isLevel(degrees))
        let ticks = [
            GuideMark(.segment(GuidePoint(x: 0.04, y: 0.5), GuidePoint(x: 0.12, y: 0.5))),
            GuideMark(.segment(GuidePoint(x: 0.88, y: 0.5), GuidePoint(x: 0.96, y: 0.5))),
        ]
        return [line] + ticks
    }

    // MARK: - 読み上げ

    static func accessibilityLabel(_ kind: CompositionKind?) -> String {
        L("構図、\(kind?.name ?? noneName)", "Composition, \(kind?.englishName ?? "None")")
    }

    static func variantAccessibilityLabel(_ kind: CompositionKind, variant: Int) -> String {
        L("向き、\(kind.variantName(variant))", "Orientation, \(kind.variantEnglishName(variant))")
    }

    /// 「なし」の名前
    static var noneName: String { L("なし", "None") }

    // MARK: - 中身

    static func validAspect(_ aspect: Double) -> Double {
        aspect.isFinite && aspect > 0.05 && aspect < 20 ? aspect : 0.75
    }

    /// 幅 r・高さ 1 の面の点を 0〜1 に戻す
    private static func px(_ x: Double, _ y: Double, _ r: Double) -> GuidePoint {
        GuidePoint(x: x / r, y: y)
    }

    private static func seg(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> GuideMark {
        GuideMark(.segment(GuidePoint(x: x1, y: y1), GuidePoint(x: x2, y: y2)))
    }

    private static func vline(_ x: Double) -> GuideMark { seg(x, 0, x, 1) }
    private static func hline(_ y: Double) -> GuideMark { seg(0, y, 1, y) }

    private static func grid(columns: Int, rows: Int) -> [GuideMark] {
        (1..<max(columns, 1)).map { vline(Double($0) / Double(columns)) }
            + (1..<max(rows, 1)).map { hline(Double($0) / Double(rows)) }
    }

    private static var thirds: [GuideMark] { grid(columns: 3, rows: 3) }
    private static var bothDiagonals: [GuideMark] { [seg(0, 0, 1, 1), seg(0, 1, 1, 0)] }

    private static func point(_ x: Double, _ y: Double) -> GuideMark {
        GuideMark(.point(GuidePoint(x: x, y: y)))
    }

    private static func closed(_ points: [(Double, Double)]) -> GuideMark {
        GuideMark(.polyline(points.map { GuidePoint(x: $0.0, y: $0.1) }, closed: true))
    }

    private static func open(_ points: [(Double, Double)]) -> GuideMark {
        GuideMark(.polyline(points.map { GuidePoint(x: $0.0, y: $0.1) }, closed: false))
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func rawMarks(_ kind: CompositionKind, variant v: Int, aspect r: Double) -> [GuideMark] {
        switch kind {
        // 定番の分割
        case .thirds, .iphone:
            return thirds
        case .halves:
            return [vline(0.5), hline(0.5)]
        case .symmetry:
            return v == 0 ? [vline(0.5)] : [hline(0.5)]
        case .hinomaru:
            // 中心に短辺の 1/3 の円（ピクセルの上で真円）と小さな十字
            let radius = min(r, 1) / 6
            let rx = radius / r, ry = radius
            let t = radius * 0.3
            return [GuideMark(.ellipse(GuideRect(x: 0.5 - rx, y: 0.5 - ry, width: rx * 2, height: ry * 2))),
                    seg(0.5 - t / r, 0.5, 0.5 + t / r, 0.5), seg(0.5, 0.5 - t, 0.5, 0.5 + t)]
        case .horizon:
            return [hline(v == 0 ? 2.0 / 3 : 1.0 / 3)]
        case .grid4:
            return grid(columns: 4, rows: 4)
        case .squareGrid:
            // 縦は 6 等分、横はピクセルの上で正方形になる間隔
            let step = r / 6
            var marks = (1..<6).map { vline(Double($0) / 6) }
            var y = step
            while y < 1 - 1e-6 {
                marks.append(hline(y))
                y += step
            }
            return marks
        case .tianzige:
            let inset = 0.03
            return [closed([(inset, inset * r), (1 - inset, inset * r), (1 - inset, 1 - inset * r), (inset, 1 - inset * r)]),
                    vline(0.5), hline(0.5)]
        case .mizige:
            return [vline(0.5), hline(0.5)] + bothDiagonals

        // 黄金比
        case .phiGrid:
            let a = 1 / (phi * phi), b = 1 / phi
            return [vline(a), vline(b), hline(a), hline(b)]
        case .goldenSpiral:
            let t = spiralTransform(v)
            return spiralSquares().map { t.apply(GuideMark(.arc(center: $0.arcCenter, rx: $0.side / phi, ry: $0.side,
                                                                  start: $0.arcStart + .pi / 2, end: $0.arcStart))) }
        case .fibonacciGrid:
            let t = spiralTransform(v)
            return spiralSquares().map { t.apply(GuideMark(.segment($0.cut.0, $0.cut.1))) }
        case .goldenTriangle:
            let f = goldenFeet(aspect: r)
            if v == 0 {
                return [seg(0, 1, 1, 0), GuideMark(.segment(GuidePoint(x: 0, y: 0), f.rising1)),
                        GuideMark(.segment(GuidePoint(x: 1, y: 1), f.rising2))]
            }
            return [seg(0, 0, 1, 1), GuideMark(.segment(GuidePoint(x: 1, y: 0), f.falling1)),
                    GuideMark(.segment(GuidePoint(x: 0, y: 1), f.falling2))]

        // 対角・幾何
        case .diagonals:
            switch v {
            case 0: return [seg(0, 0, 1, 1)]
            case 1: return [seg(0, 1, 1, 0)]
            default: return bothDiagonals
            }
        case .thirdsDiagonals:
            return thirds + bothDiagonals
        case .diagonal45:
            return [(0.0, 0.0, 1.0, 1.0), (r, 0, -1, 1), (0, 1, 1, -1), (r, 1, -1, -1)].map { c in
                let end = rayExit(fromX: c.0, y: c.1, dx: c.2, dy: c.3, aspect: r)
                return GuideMark(.segment(px(c.0, c.1, r), px(end.0, end.1, r)))
            }
        case .obliqueThirds:
            // アプリ独自: 対角線に平行な線で枠を斜めに三等分（両向き）。名の通った構図ではない
            return [seg(0, 2.0 / 3, 2.0 / 3, 0), seg(1.0 / 3, 1, 1, 1.0 / 3),
                    seg(1.0 / 3, 0, 1, 2.0 / 3), seg(0, 1.0 / 3, 2.0 / 3, 1)]
        case .dynamicSymmetry:
            return dynamicSymmetry(aspect: r)
        case .armature:
            let rhombus = [seg(0.5, 0, 1, 0.5), seg(1, 0.5, 0.5, 1), seg(0.5, 1, 0, 0.5), seg(0, 0.5, 0.5, 0)]
            let corners = [seg(0, 0, 1, 0.5), seg(0, 0, 0.5, 1), seg(1, 0, 0, 0.5), seg(1, 0, 0.5, 1),
                           seg(0, 1, 1, 0.5), seg(0, 1, 0.5, 0), seg(1, 1, 0, 0.5), seg(1, 1, 0.5, 0)]
            return bothDiagonals + rhombus + corners
        case .rootRectangle:
            guard let crop = cropRect(kind, variant: v, aspect: r) else { return [] }
            let inner = dynamicSymmetry(aspect: r * crop.width / crop.height).map { $0.mapped(into: crop) }
            return [GuideMark(.dimOutside(crop)), GuideMark(.roundedRect(crop, corner: 0))] + inner

        // 配置と形（線は破線・`marks`）
        case .triangle:
            let pts = [(0.5, 0.18), (0.84, 0.8), (0.16, 0.8)]
            let shape = v == 0 ? pts : pts.map { ($0.0, 1 - $0.1) }
            return [closed(shape)] + shape.map { point($0.0, $0.1) }
        case .radial:
            let origins = [(0.5, 0.5), (1.0 / 3, 1.0 / 3), (2.0 / 3, 1.0 / 3), (1.0 / 3, 2.0 / 3), (2.0 / 3, 2.0 / 3)]
            let o = origins[v]
            let ox = o.0 * r, oy = o.1
            let rays = (0..<8).map { i -> GuideMark in
                let a = Double(i) * .pi / 4
                let end = rayExit(fromX: ox, y: oy, dx: cos(a), dy: sin(a), aspect: r)
                return GuideMark(.segment(GuidePoint(x: o.0, y: o.1), px(end.0, end.1, r)))
            }
            return rays + [point(o.0, o.1)]
        case .tunnel:
            return [GuideMark(.ellipse(GuideRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76))), point(0.5, 0.5)]
        case .frameWithin:
            let inset = 0.12
            return [GuideMark(.roundedRect(GuideRect(x: inset, y: inset, width: 1 - inset * 2, height: 1 - inset * 2),
                                           corner: 0.05))]
        case .negativeSpace:
            let spots = [(2.0 / 3, 2.0 / 3), (1.0 / 3, 2.0 / 3), (2.0 / 3, 1.0 / 3), (1.0 / 3, 1.0 / 3)]
            let c = spots[v]
            let side = min(r, 1) * 0.12
            let w = side / r, h = side
            return [GuideMark(.roundedRect(GuideRect(x: c.0 - w / 2, y: c.1 - h / 2, width: w, height: h), corner: 0)),
                    point(c.0, c.1)]
        case .lShape:
            let base = [(0.22, 0.14), (0.22, 0.8), (0.86, 0.8)]
            return [open(flip(base, x: v == 1 || v == 3, y: v >= 2))]
        case .zShape:
            return [open(flip([(0.16, 0.22), (0.84, 0.22), (0.16, 0.78), (0.84, 0.78)], x: v == 1, y: false))]
        case .sCurve:
            let p = flip([(0.35, 0.06), (0.95, 0.3), (0.05, 0.7), (0.65, 0.94)], x: v == 1, y: false)
            return [GuideMark(.bezier(from: GuidePoint(x: p[0].0, y: p[0].1), control1: GuidePoint(x: p[1].0, y: p[1].1),
                                      control2: GuidePoint(x: p[2].0, y: p[2].1), to: GuidePoint(x: p[3].0, y: p[3].1)))]
        case .cCurve:
            let p = flip([(0.72, 0.14), (0.08, 0.1), (0.08, 0.9), (0.72, 0.86)], x: v == 1, y: false)
            return [GuideMark(.bezier(from: GuidePoint(x: p[0].0, y: p[0].1), control1: GuidePoint(x: p[1].0, y: p[1].1),
                                      control2: GuidePoint(x: p[2].0, y: p[2].1), to: GuidePoint(x: p[3].0, y: p[3].1)))]

        // 比率の枠
        case .square, .ratio4x5, .ratio9x16, .ratio16x9, .otherRatios:
            guard let crop = cropRect(kind, variant: v, aspect: r) else { return [] }
            var marks = [GuideMark(.dimOutside(crop)), GuideMark(.roundedRect(crop, corner: 0))]
            if kind == .square {
                marks += [seg(0.5, crop.y, 0.5, crop.maxY), seg(crop.x, 0.5, crop.maxX, 0.5)]
            }
            return marks

        // 機種の格子
        case .grid6x4:
            // 6×4 は横長の枠の並び。縦の枠では回して 4 列×6 段
            return r < 1 ? grid(columns: 4, rows: 6) : grid(columns: 6, rows: 4)
        case .level:
            return levelMarks(aspect: r, degrees: 0)
        }
    }

    private static func flip(_ pts: [(Double, Double)], x: Bool, y: Bool) -> [(Double, Double)] {
        pts.map { (x ? 1 - $0.0 : $0.0, y ? 1 - $0.1 : $0.1) }
    }

    /// 比率の枠の縦横比（幅÷高さ）。まとめた1項目（3:2・2:1・XPan・√2）は枠の向きに合わせる
    private static func cropRatio(_ kind: CompositionKind, variant v: Int, frameAspect r: Double) -> Double? {
        let portrait = r < 1
        func oriented(_ ratio: Double) -> Double { portrait ? 1 / ratio : ratio }
        switch kind {
        case .square: return 1
        case .ratio4x5: return 4.0 / 5
        case .ratio9x16: return 9.0 / 16
        case .ratio16x9: return 16.0 / 9
        case .otherRatios: return oriented([3.0 / 2, 2.0, 65.0 / 24, 2.0.squareRoot()][v])
        case .rootRectangle: return oriented(2.0.squareRoot())
        default: return nil
        }
    }

    /// 幅 r・高さ 1 の面で、(x, y) から向き (dx, dy) に進んで枠を出る点
    static func rayExit(fromX x: Double, y: Double, dx: Double, dy: Double, aspect r: Double) -> (Double, Double) {
        var t = Double.infinity
        if dx > 1e-12 { t = min(t, (r - x) / dx) }
        if dx < -1e-12 { t = min(t, -x / dx) }
        if dy > 1e-12 { t = min(t, (1 - y) / dy) }
        if dy < -1e-12 { t = min(t, -y / dy) }
        guard t.isFinite, t >= 0 else { return (x, y) }
        return (min(max(x + dx * t, 0), r), min(max(y + dy * t, 0), 1))
    }

    /// 黄金三角形の垂線の足（0〜1）。
    /// - rising1: 左上の角から、左下→右上の対角線へ下ろした足 (1/(1+r²), r²/(1+r²))
    /// - rising2: 右下の角から、同じ対角線へ下ろした足
    /// - falling1: 右上の角から、左上→右下の対角線へ。falling2: 左下の角から
    struct GoldenFeet {
        let rising1, rising2, falling1, falling2: GuidePoint
    }

    static func goldenFeet(aspect r: Double) -> GoldenFeet {
        let k = 1 / (1 + r * r)
        let a = GuidePoint(x: k, y: 1 - k)
        return GoldenFeet(rising1: a, rising2: GuidePoint(x: 1 - a.x, y: 1 - a.y),
                          falling1: GuidePoint(x: 1 - a.x, y: a.y), falling2: GuidePoint(x: a.x, y: 1 - a.y))
    }

    /// ダイナミックシンメトリー: 対角線2本と、各角から向かいの対角線に直交する線（逆対角）4本。
    /// 目（交わる点）は黄金三角形の足と同じ4点
    static func dynamicSymmetry(aspect r: Double) -> [GuideMark] {
        // ピクセルの上: 左下→右上の対角線の向き (r, -1)。それに直交する向き (1, r)
        let corners: [(Double, Double, Double, Double)] = [
            (0, 0, 1, r),      // 左上 → 右下へ（左下→右上の対角線に直交）
            (r, 1, -1, -r),    // 右下 → 左上へ
            (r, 0, -1, r),     // 右上 → 左下へ（左上→右下の対角線に直交）
            (0, 1, 1, -r),     // 左下 → 右上へ
        ]
        let reciprocals = corners.map { c -> GuideMark in
            let end = rayExit(fromX: c.0, y: c.1, dx: c.2, dy: c.3, aspect: r)
            return GuideMark(.segment(px(c.0, c.1, r), px(end.0, end.1, r)))
        }
        let f = goldenFeet(aspect: r)
        let eyes = [f.rising1, f.rising2, f.falling1, f.falling2].map { GuideMark(.point($0)) }
        return bothDiagonals + reciprocals + eyes
    }

    // MARK: 黄金螺旋

    /// 螺旋の正方形1つ（φ×1 の横長の黄金長方形を 0〜1 に引き伸ばした座標）
    struct SpiralSquare {
        let side: Double
        let arcCenter: GuidePoint
        /// 弧の終わりの角度（始まりはこれ ＋90°。外から渦へ向かって角度が減る向きに描く——前の弧の終わりが次の始まり）
        let arcStart: Double
        /// 正方形と残りの長方形の境の線（フィボナッチ格子）
        let cut: (GuidePoint, GuidePoint)
    }

    /// 切り出す正方形の数
    static let spiralSteps = 10

    /// φ×1 の黄金長方形（横長）を、左・下・右・上の順に正方形で切っていく。渦は右上（`spiralEye` の 0 番の前）
    static func spiralSquares() -> [SpiralSquare] {
        var x0 = 0.0, y0 = 0.0, x1 = phi, y1 = 1.0
        var out: [SpiralSquare] = []
        func n(_ x: Double, _ y: Double) -> GuidePoint { GuidePoint(x: x / phi, y: y) }
        for i in 0..<spiralSteps {
            let s = min(x1 - x0, y1 - y0)
            switch i % 4 {
            case 0: // 左を切る。弧の中心は右上の角
                out.append(SpiralSquare(side: s, arcCenter: n(x0 + s, y0), arcStart: .pi / 2,
                                        cut: (n(x0 + s, y0), n(x0 + s, y1))))
                x0 += s
            case 1: // 下を切る。弧の中心は左上の角
                out.append(SpiralSquare(side: s, arcCenter: n(x0, y1 - s), arcStart: 0,
                                        cut: (n(x0, y1 - s), n(x1, y1 - s))))
                y1 -= s
            case 2: // 右を切る。弧の中心は左下の角
                out.append(SpiralSquare(side: s, arcCenter: n(x1 - s, y1), arcStart: -.pi / 2,
                                        cut: (n(x1 - s, y0), n(x1 - s, y1))))
                x1 -= s
            default: // 上を切る。弧の中心は右下の角
                out.append(SpiralSquare(side: s, arcCenter: n(x1, y0 + s), arcStart: .pi,
                                        cut: (n(x0, y0 + s), n(x1, y0 + s))))
                y0 += s
            }
        }
        return out
    }

    /// 螺旋の向き（8通り）。0〜3 は縦長（φ の長い辺が縦）、4〜7 は横長。
    /// それぞれ 反転なし・左右・上下・両方
    static func spiralTransform(_ variant: Int) -> GuideTransform {
        let v = min(max(variant, 0), 7)
        return GuideTransform(transpose: v < 4, flipX: v % 4 == 1 || v % 4 == 3, flipY: v % 4 >= 2)
    }
}

// MARK: - 座標と線の型

/// 0〜1 の点（左上が原点・y は下向き）
struct GuidePoint: Equatable {
    var x: Double
    var y: Double
}

/// 0〜1 の長方形
struct GuideRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

/// 線の形
enum GuideShape: Equatable {
    case segment(GuidePoint, GuidePoint)
    case polyline([GuidePoint], closed: Bool)
    /// 楕円の弧（枠に引き伸ばした円の弧）。角度はラジアン・x 軸から y（下）へ回る向き
    case arc(center: GuidePoint, rx: Double, ry: Double, start: Double, end: Double)
    case ellipse(GuideRect)
    /// 角丸の長方形。`corner` はピクセルの上で短辺に対する丸みの割合
    case roundedRect(GuideRect, corner: Double)
    /// 小さな塗りの点（目を置く所）
    case point(GuidePoint)
    case bezier(from: GuidePoint, control1: GuidePoint, control2: GuidePoint, to: GuidePoint)
    /// この長方形の外を暗くする（切り出し枠）
    case dimOutside(GuideRect)
}

/// 線1本（形・破線か・太いか）
struct GuideMark: Equatable {
    let shape: GuideShape
    var dashed = false
    var bold = false

    init(_ shape: GuideShape, dashed: Bool = false, bold: Bool = false) {
        self.shape = shape
        self.dashed = dashed
        self.bold = bold
    }

    /// 塗るもの（点・暗がり）。破線にしない
    var isFill: Bool {
        switch shape {
        case .point, .dimOutside: return true
        default: return false
        }
    }

    func withDash() -> GuideMark { GuideMark(shape, dashed: true, bold: bold) }

    /// 試験用: 形の上の点（弧は細かく刻む・曲線は制御点も）
    var samplePoints: [GuidePoint] {
        switch shape {
        case .segment(let a, let b): return [a, b]
        case .polyline(let pts, _): return pts
        case .arc(let c, let rx, let ry, let start, let end):
            return (0...16).map { i in
                let t = start + (end - start) * Double(i) / 16
                return GuidePoint(x: c.x + rx * cos(t), y: c.y + ry * sin(t))
            }
        case .ellipse(let r), .dimOutside(let r), .roundedRect(let r, _):
            return [GuidePoint(x: r.x, y: r.y), GuidePoint(x: r.maxX, y: r.maxY)]
        case .point(let p): return [p]
        case .bezier(let a, let c1, let c2, let b): return [a, c1, c2, b]
        }
    }

    /// 0〜1 の線を、枠の中の長方形 `rect` の中へ写す（ルート長方形の中のダイナミックシンメトリー）
    func mapped(into rect: GuideRect) -> GuideMark {
        func m(_ p: GuidePoint) -> GuidePoint { GuidePoint(x: rect.x + p.x * rect.width, y: rect.y + p.y * rect.height) }
        func mr(_ r: GuideRect) -> GuideRect {
            GuideRect(x: rect.x + r.x * rect.width, y: rect.y + r.y * rect.height,
                      width: r.width * rect.width, height: r.height * rect.height)
        }
        let s: GuideShape
        switch shape {
        case .segment(let a, let b): s = .segment(m(a), m(b))
        case .polyline(let pts, let c): s = .polyline(pts.map(m), closed: c)
        case .arc(let c, let rx, let ry, let a, let b): s = .arc(center: m(c), rx: rx * rect.width, ry: ry * rect.height, start: a, end: b)
        case .ellipse(let r): s = .ellipse(mr(r))
        case .roundedRect(let r, let k): s = .roundedRect(mr(r), corner: k)
        case .point(let p): s = .point(m(p))
        case .bezier(let a, let c1, let c2, let b): s = .bezier(from: m(a), control1: m(c1), control2: m(c2), to: m(b))
        case .dimOutside(let r): s = .dimOutside(mr(r))
        }
        return GuideMark(s, dashed: dashed, bold: bold)
    }
}

/// 向きの変換（入れ替え→左右→上下の順）。黄金螺旋・フィボナッチ格子の 8 通り
struct GuideTransform: Equatable {
    var transpose: Bool
    var flipX: Bool
    var flipY: Bool

    func apply(_ p: GuidePoint) -> GuidePoint {
        var q = transpose ? GuidePoint(x: p.y, y: p.x) : p
        if flipX { q.x = 1 - q.x }
        if flipY { q.y = 1 - q.y }
        return q
    }

    func apply(_ angle: Double) -> Double {
        var t = transpose ? .pi / 2 - angle : angle
        if flipX { t = .pi - t }
        if flipY { t = -t }
        return t
    }

    func apply(_ mark: GuideMark) -> GuideMark {
        let s: GuideShape
        switch mark.shape {
        case .segment(let a, let b): s = .segment(apply(a), apply(b))
        case .arc(let c, let rx, let ry, let start, let end):
            s = .arc(center: apply(c), rx: transpose ? ry : rx, ry: transpose ? rx : ry,
                     start: apply(start), end: apply(end))
        case .point(let p): s = .point(apply(p))
        case .polyline(let pts, let closed): s = .polyline(pts.map(apply), closed: closed)
        default: s = mark.shape
        }
        return GuideMark(s, dashed: mark.dashed, bold: mark.bold)
    }
}

// MARK: - 構図の一覧

/// 構図の段（シートの見出し）。「よく使う」は最近の構図で、種類ではない
enum CompositionSection: String, CaseIterable, Identifiable {
    case classic, golden, diagonal, shape, ratio, device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return L("定番の分割", "Classic divisions")
        case .golden: return L("黄金比", "Golden ratio")
        case .diagonal: return L("対角・幾何", "Diagonals & geometry")
        case .shape: return L("配置と形", "Placement & shapes")
        case .ratio: return L("比率の枠", "Aspect frames")
        case .device: return L("機種の格子", "Camera grids")
        }
    }

    /// 段へ飛ぶチップの短い名前
    var chip: String {
        switch self {
        case .classic: return L("定番", "Classic")
        case .golden: return L("黄金比", "Golden")
        case .diagonal: return L("対角", "Diagonal")
        case .shape: return L("形", "Shapes")
        case .ratio: return L("比率", "Ratios")
        case .device: return L("機種", "Cameras")
        }
    }

    var kinds: [CompositionKind] { CompositionKind.allCases.filter { $0.section == self } }
}

/// 難しさ（札の下の 12pt）
enum CompositionDifficulty: Int, Equatable {
    case basic, intermediate, advanced

    var label: String {
        switch self {
        case .basic: return L("定番", "Basic")
        case .intermediate: return L("中級", "Intermediate")
        case .advanced: return L("上級", "Advanced")
        }
    }
}

/// 構図の種類（37）。**rawValue は端末に覚える値**——名前を変えても rawValue は変えない
enum CompositionKind: String, CaseIterable, Identifiable {
    // 定番の分割
    case thirds, halves, symmetry, hinomaru, horizon, grid4, squareGrid, tianzige, mizige
    // 黄金比
    case phiGrid, goldenSpiral, fibonacciGrid, goldenTriangle
    // 対角・幾何
    case diagonals, thirdsDiagonals, diagonal45, obliqueThirds, dynamicSymmetry, armature, rootRectangle
    // 配置と形
    case triangle, radial, tunnel, frameWithin, negativeSpace, lShape, zShape, sCurve, cCurve
    // 比率の枠
    case square, ratio4x5, ratio9x16, ratio16x9, otherRatios
    // 機種の格子
    case grid6x4, iphone, level

    var id: String { rawValue }

    /// 既定（何も覚えていないとき）
    static let defaultKind: CompositionKind = .thirds

    var section: CompositionSection {
        switch self {
        case .thirds, .halves, .symmetry, .hinomaru, .horizon, .grid4, .squareGrid, .tianzige, .mizige: return .classic
        case .phiGrid, .goldenSpiral, .fibonacciGrid, .goldenTriangle: return .golden
        case .diagonals, .thirdsDiagonals, .diagonal45, .obliqueThirds, .dynamicSymmetry, .armature, .rootRectangle:
            return .diagonal
        case .triangle, .radial, .tunnel, .frameWithin, .negativeSpace, .lShape, .zShape, .sCurve, .cCurve: return .shape
        case .square, .ratio4x5, .ratio9x16, .ratio16x9, .otherRatios: return .ratio
        case .grid6x4, .iphone, .level: return .device
        }
    }

    /// 日本語の名前（英語の画面では英語の名前）
    var name: String { L(japaneseName, englishName) }

    var japaneseName: String {
        switch self {
        case .thirds: return "三分割"
        case .halves: return "二分割・十字"
        case .symmetry: return "シンメトリー"
        case .hinomaru: return "日の丸"
        case .horizon: return "水平線"
        case .grid4: return "4×4"
        case .squareGrid: return "方眼"
        case .tianzige: return "田字格"
        case .mizige: return "米字格"
        case .phiGrid: return "ファイグリッド"
        case .goldenSpiral: return "黄金螺旋"
        case .fibonacciGrid: return "フィボナッチ格子"
        case .goldenTriangle: return "黄金三角形"
        case .diagonals: return "対角線"
        case .thirdsDiagonals: return "3×3＋対角"
        case .diagonal45: return "45°の対角"
        case .obliqueThirds: return "斜めの三分割"
        case .dynamicSymmetry: return "ダイナミックシンメトリー"
        case .armature: return "アーマチュア"
        case .rootRectangle: return "ルート長方形"
        case .triangle: return "三角"
        case .radial: return "放射線"
        case .tunnel: return "トンネル"
        case .frameWithin: return "額縁"
        case .negativeSpace: return "余白"
        case .lShape: return "L字"
        case .zShape: return "Z字"
        case .sCurve: return "S字"
        case .cCurve: return "C字"
        case .square: return "1:1"
        case .ratio4x5: return "4:5"
        case .ratio9x16: return "9:16"
        case .ratio16x9: return "16:9"
        case .otherRatios: return "3:2・2:1・XPan・√2"
        case .grid6x4: return "6×4"
        case .iphone: return "iPhone 標準"
        case .level: return "水準器"
        }
    }

    var englishName: String {
        switch self {
        case .thirds: return "Rule of thirds"
        case .halves: return "Halves / cross"
        case .symmetry: return "Symmetry"
        case .hinomaru: return "Centered (Hinomaru)"
        case .horizon: return "Horizon"
        case .grid4: return "4×4 grid"
        case .squareGrid: return "Square grid"
        case .tianzige: return "Tian grid"
        case .mizige: return "Mi grid"
        case .phiGrid: return "Phi grid"
        case .goldenSpiral: return "Golden spiral"
        case .fibonacciGrid: return "Fibonacci grid"
        case .goldenTriangle: return "Golden triangles"
        case .diagonals: return "Diagonals"
        case .thirdsDiagonals: return "Thirds + diagonals"
        case .diagonal45: return "45° diagonals"
        case .obliqueThirds: return "Oblique thirds"
        case .dynamicSymmetry: return "Dynamic symmetry"
        case .armature: return "Armature"
        case .rootRectangle: return "Root rectangle"
        case .triangle: return "Triangle"
        case .radial: return "Radial lines"
        case .tunnel: return "Tunnel"
        case .frameWithin: return "Frame within a frame"
        case .negativeSpace: return "Negative space"
        case .lShape: return "L shape"
        case .zShape: return "Z shape"
        case .sCurve: return "S curve"
        case .cCurve: return "C curve"
        case .square: return "1:1"
        case .ratio4x5: return "4:5"
        case .ratio9x16: return "9:16"
        case .ratio16x9: return "16:9"
        case .otherRatios: return "3:2 · 2:1 · XPan · √2"
        case .grid6x4: return "6×4 grid"
        case .iphone: return "iPhone default"
        case .level: return "Level"
        }
    }

    /// 案内の札の一言
    var tip: String {
        switch self {
        case .thirds, .iphone:
            return L("主役を線の交わる点に。地平線は上か下の線に", "Put the subject on an intersection, the horizon on a line")
        case .halves:
            return L("真ん中で分けて、左右か上下を対に", "Split at the center and pair the halves")
        case .symmetry:
            return L("線を軸に、左右（上下）を鏡のように", "Mirror both sides across the line")
        case .hinomaru:
            return L("主役を円の中へ。周りは静かに", "Put the subject in the circle; keep the rest quiet")
        case .horizon:
            return L("地平線を線に合わせ、空か地面を広く", "Line up the horizon; give the sky or ground more room")
        case .grid4:
            return L("細かい格子で、傾きと間隔をそろえる", "Use the fine grid to keep lines straight and even")
        case .squareGrid:
            return L("正方形の目で、建物や並びの傾きを見る", "Check verticals and rows against the squares")
        case .tianzige:
            return L("十字と外枠で、真ん中と四隅の釣り合いを", "Balance the center and corners with the cross")
        case .mizige:
            return L("十字と対角で、中心へ向かう線を探す", "Find lines that run to the center")
        case .phiGrid:
            return L("三分割より少し中寄りの交点に主役を", "Place the subject a little nearer the center than thirds")
        case .goldenSpiral:
            return L("渦の中心に主役を。流れは渦に沿って", "Put the subject at the eye; let the flow follow the curve")
        case .fibonacciGrid:
            return L("小さい四角へ向かって、だんだん主役へ", "Lead the eye into the smallest square")
        case .goldenTriangle:
            return L("対角の流れに、垂線の足で主役を置く", "Run the flow on the diagonal; subject where the lines meet")
        case .diagonals:
            return L("斜めの線に道や稜線を合わせて動きを", "Lay roads or ridges on the diagonal for movement")
        case .thirdsDiagonals:
            return L("交点と対角を両方使って奥行きを", "Use intersections and diagonals together for depth")
        case .diagonal45:
            return L("角から 45° の線に、斜めのものを沿わせる", "Align slanted lines with the 45° guides")
        case .obliqueThirds:
            return L("斜めの帯で三つに分ける（アプリ独自の線）", "Split the frame into slanted thirds (an app-made guide)")
        case .dynamicSymmetry:
            return L("線の交わる点に主役、線に沿って流れを", "Put subjects where lines cross; run lines along the guides")
        case .armature:
            return L("14 本の線のどれかに、形や視線を乗せる", "Rest shapes and gazes on any of the 14 lines")
        case .rootRectangle:
            return L("√2 の枠で切る前提で、交点に主役を", "Shoot for a √2 crop; subject on a crossing")
        case .triangle:
            return L("3つの点（奇数）で、安定か緊張の三角を", "Three points make a steady or tense triangle")
        case .radial:
            return L("線が集まる所に主役。道や光の筋を合わせる", "Let roads or light rays converge on the subject")
        case .tunnel:
            return L("トンネルや木の枝で、主役を囲む", "Surround the subject with an arch or branches")
        case .frameWithin:
            return L("窓や門を額縁にして、奥の主役を見せる", "Use a window or gate as a frame for the subject")
        case .negativeSpace:
            return L("主役は小さく、残りは広い余白に", "Keep the subject small and the space wide")
        case .lShape, .zShape, .sCurve, .cCurve:
            return L("線に合わせるより、形の流れを探す", "Look for the flow of the shape rather than matching the line")
        case .square, .ratio4x5, .ratio9x16, .ratio16x9, .otherRatios:
            return L("明るい枠の中だけで構図を決める", "Compose inside the bright frame only")
        case .grid6x4:
            return L("カメラの 6×4 の格子で、間隔をそろえる", "Even out spacing with the camera's 6×4 grid")
        case .level:
            return L("線が太くなったら水平", "The line thickens when you're level")
        }
    }

    var difficulty: CompositionDifficulty {
        switch self {
        case .thirds, .halves, .symmetry, .hinomaru, .horizon, .grid4, .diagonals, .square, .ratio4x5, .ratio9x16,
             .ratio16x9, .iphone, .level, .tunnel, .frameWithin:
            return .basic
        case .squareGrid, .tianzige, .mizige, .phiGrid, .thirdsDiagonals, .diagonal45, .triangle, .radial,
             .negativeSpace, .lShape, .zShape, .sCurve, .cCurve, .otherRatios, .grid6x4, .goldenSpiral, .obliqueThirds:
            return .intermediate
        case .fibonacciGrid, .goldenTriangle, .dynamicSymmetry, .armature, .rootRectangle:
            return .advanced
        }
    }

    /// 向きの名前（日本語・英語）。1つしか無い構図は空
    private var variantNames: [(String, String)] {
        switch self {
        case .symmetry: return [("縦", "Vertical"), ("横", "Horizontal")]
        case .horizon: return [("空を広く", "More sky"), ("地面を広く", "More ground")]
        case .goldenSpiral, .fibonacciGrid:
            // 0〜3 は縦長・4〜7 は横長（`CompositionGuide.spiralTransform`）。名前は渦の位置
            return (0..<8).map { v in
                let eye = CompositionGuide.spiralTransform(v).apply(
                    GuidePoint(x: 1 / (1 + 1 / (CompositionGuide.phi * CompositionGuide.phi)),
                               y: 1 - 1 / (1 + 1 / (CompositionGuide.phi * CompositionGuide.phi))))
                let ja = (eye.x < 0.5 ? "左" : "右") + (eye.y < 0.5 ? "上" : "下")
                let en = (eye.y < 0.5 ? "Top " : "Bottom ") + (eye.x < 0.5 ? "left" : "right")
                return v < 4 ? (ja, en) : ("\(ja)・横長", "\(en), wide")
            }
        case .goldenTriangle: return [("右上がり", "Rising"), ("右下がり", "Falling")]
        case .diagonals: return [("バロック", "Baroque"), ("シニスター", "Sinister"), ("両方", "Both")]
        case .triangle: return [("正", "Upright"), ("逆", "Inverted")]
        case .radial:
            return [("中心", "Center"), ("左上", "Top left"), ("右上", "Top right"), ("左下", "Bottom left"),
                    ("右下", "Bottom right")]
        case .negativeSpace:
            return [("右下", "Bottom right"), ("左下", "Bottom left"), ("右上", "Top right"), ("左上", "Top left")]
        case .lShape: return [("L", "L"), ("逆L", "Reversed L"), ("上下逆", "Upside down"), ("回転", "Rotated")]
        case .zShape: return [("Z", "Z"), ("逆Z", "Reversed Z")]
        case .sCurve: return [("S", "S"), ("逆S", "Reversed S")]
        case .cCurve: return [("C", "C"), ("逆C", "Reversed C")]
        case .otherRatios: return [("3:2", "3:2"), ("2:1", "2:1"), ("XPan 65:24", "XPan 65:24"), ("√2", "√2")]
        default: return []
        }
    }

    /// 向きの数（1 なら「向き」のボタンを出さない）
    var variantCount: Int { max(variantNames.count, 1) }
    var hasVariants: Bool { variantCount > 1 }

    func normalizedVariant(_ v: Int) -> Int { min(max(v, 0), variantCount - 1) }

    func variantName(_ v: Int) -> String {
        guard hasVariants else { return "" }
        let n = variantNames[normalizedVariant(v)]
        return L(n.0, n.1)
    }

    func variantEnglishName(_ v: Int) -> String {
        guard hasVariants else { return "" }
        return variantNames[normalizedVariant(v)].1
    }

    /// 次の向き（最後の次は最初）
    func nextVariant(after v: Int) -> Int { (normalizedVariant(v) + 1) % variantCount }
}
