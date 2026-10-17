import SwiftUI

/// 旅のラベル1枚（モック Label.dc.html をそのまま写す・2026-10-17）。
///
/// 重ね方はモックと同じ: 刷りの色の地 → 紙（粒・斜めの光）→ 内の縁（刷りの色 60%）→ 内の紙 →
/// 角の擦れとしみ → 絵と3行の字（真ん中の字は差し色で刷りがずれる）→ めくれ。全体を形で切り、
/// 切符は左右を半円に欠き、影を落として傾ける。褪せ（彩度・セピア・明るさ）は色そのものに畳む
/// （`TrunkLabelLayout.faded`）。大きさ・字の大きさ・余白はすべて `TrunkLabelLayout` の式。
///
/// **紙に刷った物として描く**（字は Dynamic Type で伸ばさない・画面の言語でも変えない）。
/// 中身は読み上げの1行で伝える（呼ぶ側が `accessibilityLabel` を付ける）。
struct TrunkLabelView: View {
    let spec: TrunkLabelSpec
    let w: Double
    let h: Double
    var age: Double = 0
    /// 下の通し番号の行（届いた画面の大きいラベルの日付）
    var serial: String?

    init(spec: TrunkLabelSpec, w: Double, h: Double, age: Double = 0, serial: String? = nil) {
        self.spec = spec
        self.w = w
        self.h = h
        self.age = age
        self.serial = serial
    }

    /// ラベルから描く（決まった図柄・`TrunkLabelDesign.spec`）
    init(label: TrunkLabel, w: Double, h: Double, age: Double = 0, rot: Double? = nil, serial: String? = nil) {
        let spec = TrunkLabelDesign.spec(for: label)
        self.init(spec: rot.map { spec.rotated($0) } ?? spec, w: w, h: h, age: age, serial: serial)
    }

    private var layout: TrunkLabelLayout { TrunkLabelLayout(w: w, h: h, spec: spec, age: age) }

    var body: some View {
        let l = layout
        let fg = l.faded(spec.fg)
        ZStack {
            outline(0).fill(Color(trunk: fg))
            paper.clipShape(outline(l.border1))
            outline(l.border2).fill(Color(trunk: fg).opacity(0.6))
            paper.clipShape(outline(l.innerPaper))
            wear.clipShape(outline(0))
            content
            if l.showsCurl { curl }
        }
        .frame(width: w, height: h)
        .modifier(TrunkTicketMask(active: spec.shape == .ticket, notch: l.ticketNotch))
        // 細かい粒と重ねを1枚の絵にしてから影を落とす（手持ちの格子に何十枚も並ぶので軽くする）
        .drawingGroup()
        .shadow(color: Color.black.opacity(0.55), radius: l.shadowBlur / 2, x: 0, y: l.shadowY)
        .rotationEffect(.degrees(spec.rot))
        .accessibilityHidden(true)
    }

    private func outline(_ inset: Double) -> TrunkLabelOutline {
        TrunkLabelOutline(shape: spec.shape, inset: inset)
    }

    /// 紙（地の色・粒・斜めの光）。箔押しは金の斜めのグラデーション
    private var paper: some View {
        let l = layout
        return ZStack {
            if spec.foil {
                TrunkPaint.linear(TrunkGradient(angle: 125, stops: [
                    TrunkStop(color: TrunkRGBA(0x8A6B32), location: 0), TrunkStop(color: TrunkRGBA(0xF3DFA2), location: 0.22),
                    TrunkStop(color: TrunkRGBA(0xB8913F), location: 0.40), TrunkStop(color: TrunkRGBA(0xFFF1C4), location: 0.52),
                    TrunkStop(color: TrunkRGBA(0xA07C38), location: 0.68), TrunkStop(color: TrunkRGBA(0xE9CF8C), location: 0.84),
                    TrunkStop(color: TrunkRGBA(0x7E5F27), location: 1),
                ]), w: w, h: h, fade: l.faded)
            } else {
                Color(trunk: l.faded(spec.bg))
            }
            TrunkGrain.paper
            // linear-gradient(160deg, rgba(255,255,255,0.22), rgba(255,255,255,0) 42%, rgba(0,0,0,0.12))
            TrunkPaint.linear(TrunkGradient(angle: 160, stops: [
                TrunkStop(color: TrunkRGBA(r: 255, g: 255, b: 255, a: 0.22), location: 0),
                TrunkStop(color: TrunkRGBA(r: 255, g: 255, b: 255, a: 0), location: 0.42),
                TrunkStop(color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.12), location: 1),
            ]), w: w, h: h)
        }
    }

    /// 角の擦れ（白っぽい）と、しみ（茶色）。古びるほど濃い
    private var wear: some View {
        let a = layout.age
        return ZStack {
            TrunkSpot(color: TrunkRGBA(r: 255, g: 248, b: 230, a: a * 0.55), x: w * 0.06, y: h * 0.10, rx: w * 0.28, ry: h * 0.20)
            TrunkSpot(color: TrunkRGBA(r: 255, g: 248, b: 230, a: a * 0.5), x: w * 0.94, y: h * 0.88, rx: w * 0.24, ry: h * 0.18)
            TrunkSpot(color: TrunkRGBA(r: 40, g: 25, b: 10, a: a * 0.3), x: w * 0.72, y: h * 0.04, rx: w * 0.16, ry: h * 0.10)
            TrunkSpot(color: TrunkRGBA(r: 40, g: 25, b: 10, a: a * 0.25), x: w * 0.20, y: h * 0.92, rx: w * 0.10, ry: h * 0.08)
        }
        .frame(width: w, height: h)
    }

    private var content: some View {
        let l = layout
        let fg = Color(trunk: l.faded(spec.fg))
        let ac = l.faded(spec.ac)
        return VStack(spacing: 0) {
            if let art = spec.art {
                TrunkArtCanvas(strokes: TrunkArtwork.strokes(art), viewBox: TrunkArtwork.labelViewBox,
                               fg: l.faded(spec.fg), bg: l.faded(spec.bg), ac: ac)
                    .frame(width: l.artWidth, height: l.artHeight)
                    .padding(.bottom, l.artGap)
            }
            Text(spec.t1)
                .font(.custom(JPFont.displayName, fixedSize: l.t1Size))
                .tracking(l.t1Size * 0.22)
                .lineLimit(1)
                .fixedSize()
            Text(spec.t2)
                .font(.custom(JPFont.displayName, fixedSize: l.t2Size))
                .lineLimit(1)
                .fixedSize()
                // 刷りのずれ（差し色の影を少しずらす・モックの text-shadow）
                .shadow(color: Color(trunk: ac.alpha(0x88 / 255.0)), radius: 0,
                        x: l.misregistration, y: l.misregistration * 0.6)
                .padding(.top, l.t2Top)
            Text(spec.t3)
                .font(.custom(JPFont.displayName, fixedSize: l.t3Size))
                .tracking(l.t3Size * 0.14)
                .lineLimit(1)
                .fixedSize()
                .opacity(0.9)
                .padding(.top, l.t3Top)
            if let serial {
                Text(serial)
                    .font(.system(size: l.serialSize).monospacedDigit())
                    .tracking(l.serialSize * 0.1)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, l.serialTop)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, l.padX)
        .padding(.bottom, l.padBottom)
        .frame(width: w, height: h)
    }

    /// 端のめくれ（右下の三角・紙の裏の明るい色と影）
    private var curl: some View {
        let l = layout
        return ZStack(alignment: .bottomTrailing) {
            Color.clear
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 0),
                                   Gradient.Stop(color: Color.clear, location: 0.49),
                                   Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 250, g: 244, b: 228, a: 0.95)), location: 0.51),
                                   Gradient.Stop(color: Color.black.opacity(0.3), location: 1)],
                           startPoint: .bottomTrailing, endPoint: .topLeading)
                .frame(width: l.curlSize, height: l.curlSize)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 2))
                .padding(.trailing, l.curlInset.right)
                .padding(.bottom, l.curlInset.bottom)
        }
        .frame(width: w, height: h)
    }
}

/// ラベルの輪郭（楕円・角丸・多角形）。`inset` だけ内側に縮めた同じ形
struct TrunkLabelOutline: Shape {
    let shape: TrunkLabelShape
    var inset: Double = 0

    func path(in rect: CGRect) -> Path {
        let x = Double(rect.minX) + inset, y = Double(rect.minY) + inset
        let w = max(0, Double(rect.width) - inset * 2), h = max(0, Double(rect.height) - inset * 2)
        switch shape.outline {
        case .ellipse:
            return TrunkPaint.path(SVGPath.ellipse(cx: x + w / 2, cy: y + h / 2, rx: w / 2, ry: h / 2))
        case .rounded(let r):
            return TrunkPaint.path(SVGPath.rect(x: x, y: y, w: w, h: h, r: r))
        case .polygon(let points):
            var segments: [SVGPath.Segment] = []
            for (i, p) in points.enumerated() {
                let pt = SVGPath.Point(x: x + p.x * w, y: y + p.y * h)
                segments.append(i == 0 ? .move(pt) : .line(pt))
            }
            segments.append(.close)
            return TrunkPaint.path(segments)
        }
    }
}

/// 切符の左右の半円の切り欠き（モックの `mask`）。切符でなければ何もしない
private struct TrunkTicketMask: ViewModifier {
    let active: Bool
    let notch: Double

    func body(content: Content) -> some View {
        if active {
            content.mask { TrunkTicketShape(notch: notch).fill(Color.black) }
        } else {
            content
        }
    }
}

/// 四角から左右の真ん中を半円に欠いた形
struct TrunkTicketShape: Shape {
    let notch: Double

    func path(in rect: CGRect) -> Path {
        let w = Double(rect.width), h = Double(rect.height), r = notch, k = 0.5522847498 * notch
        let cy = h / 2
        let segments: [SVGPath.Segment] = [
            .move(SVGPath.Point(x: 0, y: 0)),
            .line(SVGPath.Point(x: w, y: 0)),
            .line(SVGPath.Point(x: w, y: cy - r)),
            // 右の半円（内へ）
            .cubic(c1: SVGPath.Point(x: w - k, y: cy - r), c2: SVGPath.Point(x: w - r, y: cy - k), to: SVGPath.Point(x: w - r, y: cy)),
            .cubic(c1: SVGPath.Point(x: w - r, y: cy + k), c2: SVGPath.Point(x: w - k, y: cy + r), to: SVGPath.Point(x: w, y: cy + r)),
            .line(SVGPath.Point(x: w, y: h)),
            .line(SVGPath.Point(x: 0, y: h)),
            .line(SVGPath.Point(x: 0, y: cy + r)),
            // 左の半円（内へ）
            .cubic(c1: SVGPath.Point(x: k, y: cy + r), c2: SVGPath.Point(x: r, y: cy + k), to: SVGPath.Point(x: r, y: cy)),
            .cubic(c1: SVGPath.Point(x: r, y: cy - k), c2: SVGPath.Point(x: k, y: cy - r), to: SVGPath.Point(x: 0, y: cy - r)),
            .close,
        ]
        return TrunkPaint.path(SVGPath.translate(segments, dx: Double(rect.minX), dy: Double(rect.minY)))
    }
}
