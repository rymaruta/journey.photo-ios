import SwiftUI

/// 構図の線を描く（2026-10-10・「構図を重ねて撮る」）。線の形は `CompositionGuide.marks` が決め、ここは描くだけ。
///
/// - 線は白・1pt・黒 25% の影（明るい空でも暗い森でも見える）。形の段（L字・S字など）は破線、
///   水準器が水平のときだけ太く
/// - 切り出し枠の外は黒 40% で暗くする。**重ね順は 映像 → 作例 → 構図の線 → 暗がり**（枠の外の線も沈む）
/// - 指を受けない（映像の左右の払い・シャッターを邪魔しない）。読み上げにも出さない
///   （選んでいる構図は「構図」の行が読む）
/// - **写真には焼き込まない**（重ねて見せるだけ・`ComposeCamera` の注記）
struct CompositionOverlay: View {

    let kind: CompositionKind
    var variant = 0
    /// 線の濃さ（0.15〜0.7・`CompositionGuide.lineOpacityRange`）
    var lineOpacity = CompositionGuide.defaultLineOpacity
    /// 水準器の傾き（度）。水準器でなければ使わない
    var levelDegrees: Double = 0
    var lineWidth = 1.0
    /// 黒 25% の影（構図のシートの小さな絵では付けない）
    var shadowed = true

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width), h = Double(geo.size.height)
            let marks = kind == .level
                ? CompositionGuide.levelMarks(aspect: w / max(h, 1), degrees: levelDegrees)
                : CompositionGuide.marks(kind, variant: variant, aspect: w / max(h, 1))
            let color = Color.white.opacity(CompositionGuide.clampedLineOpacity(lineOpacity))
            ZStack {
                ZStack {
                    Self.path(marks, layer: .solid, width: w, height: h)
                        .stroke(color, lineWidth: lineWidth)
                    Self.path(marks, layer: .dashed, width: w, height: h)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [6, 5]))
                    Self.path(marks, layer: .bold, width: w, height: h)
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth * 2.5, lineCap: .round))
                    Self.path(marks, layer: .points, width: w, height: h)
                        .fill(color)
                }
                .shadow(color: Color.black.opacity(shadowed ? 0.25 : 0), radius: 1, x: 0, y: 0)
                // 切り出し枠の外の暗がり（線より上）
                Self.path(marks, layer: .dim, width: w, height: h)
                    .fill(Color.black.opacity(0.4))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 描く層（線の引き方ごとに分けて描く）
    enum Layer {
        case solid, dashed, bold, points, dim
    }

    /// 線の集まりを、幅 `width`・高さ `height` の枠の `Path` にする
    static func path(_ marks: [GuideMark], layer: Layer, width w: Double, height h: Double) -> Path {
        func p(_ g: GuidePoint) -> CGPoint { CGPoint(x: g.x * w, y: g.y * h) }
        func r(_ g: GuideRect) -> CGRect { CGRect(x: g.x * w, y: g.y * h, width: g.width * w, height: g.height * h) }
        let picked = marks.filter { mark in
            switch layer {
            case .points: if case .point = mark.shape { return true } else { return false }
            case .dim: if case .dimOutside = mark.shape { return true } else { return false }
            case .bold: return !mark.isFill && mark.bold
            case .dashed: return !mark.isFill && !mark.bold && mark.dashed
            case .solid: return !mark.isFill && !mark.bold && !mark.dashed
            }
        }
        return Path { path in
            for mark in picked {
                switch mark.shape {
                case .segment(let a, let b):
                    path.move(to: p(a))
                    path.addLine(to: p(b))
                case .polyline(let pts, let closed):
                    guard let first = pts.first else { continue }
                    path.move(to: p(first))
                    for pt in pts.dropFirst() { path.addLine(to: p(pt)) }
                    if closed { path.closeSubpath() }
                case .arc(let c, let rx, let ry, let start, let end):
                    // 枠に引き伸ばした円の弧（楕円）。細かく刻んで線でつなぐ
                    let steps = 24
                    for i in 0...steps {
                        let t = start + (end - start) * Double(i) / Double(steps)
                        let pt = CGPoint(x: (c.x + rx * cos(t)) * w, y: (c.y + ry * sin(t)) * h)
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                case .ellipse(let e):
                    path.addEllipse(in: r(e))
                case .roundedRect(let rect, let corner):
                    let k = corner * min(rect.width * w, rect.height * h)
                    path.addRoundedRect(in: r(rect), cornerSize: CGSize(width: k, height: k))
                case .point(let c):
                    let d = 6.0
                    path.addEllipse(in: CGRect(x: c.x * w - d / 2, y: c.y * h - d / 2, width: d, height: d))
                case .bezier(let a, let c1, let c2, let b):
                    path.move(to: p(a))
                    path.addCurve(to: p(b), control1: p(c1), control2: p(c2))
                case .dimOutside(let crop):
                    // 枠の外の4つの帯（上・下・左・右）
                    let c = r(crop)
                    path.addRect(CGRect(x: 0, y: 0, width: w, height: Double(c.minY)))
                    path.addRect(CGRect(x: 0, y: Double(c.maxY), width: w, height: max(h - Double(c.maxY), 0)))
                    path.addRect(CGRect(x: 0, y: Double(c.minY), width: Double(c.minX), height: Double(c.height)))
                    path.addRect(CGRect(x: Double(c.maxX), y: Double(c.minY), width: max(w - Double(c.maxX), 0),
                                        height: Double(c.height)))
                }
            }
        }
    }
}

/// 構図の小さな絵（3:4・「構図」の行と構図のシートの札）。`kind` が nil なら「なし」（斜線の入った枠）
struct CompositionThumbnail: View {
    let kind: CompositionKind?
    var variant = 0
    var cornerRadius = 4.0

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let kind {
                CompositionOverlay(kind: kind, variant: variant, lineOpacity: 0.7, levelDegrees: 0, shadowed: false)
            } else {
                Image(systemName: "nosign")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(WebTheme.faint)
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
