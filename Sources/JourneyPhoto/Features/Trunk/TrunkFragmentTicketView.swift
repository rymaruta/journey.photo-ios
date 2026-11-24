import SwiftUI

/// かけらの切符（札 #713・2026-11-23 owner）。5つの切れ端で1枚の切符。持っている数だけ紙で埋まり、残りは線の輪郭。
/// 部品箱の下の帯、トランクの「部品箱」のカード、持っていない部品のシート（交換）、開けた画面（持っている部品）で同じ絵。
/// 紙の色なので黒地の上にもガラスの上にも置ける（形は `TrunkFragmentTicket`）
struct TrunkFragmentTicketView: View {
    /// 埋まっている切れ端（0〜5）
    let filled: Int
    /// 描く幅（高さは幅の 0.44）
    var width: Double = 40
    /// 空いている切れ端の線（黒地は白 40%、ガラスや写真の上は濃く）
    var emptyLine: Color = Color.white.opacity(0.4)

    var body: some View {
        let k = width / TrunkFragmentTicket.width
        let n = TrunkFragmentTicket.filled(filled)
        // 小さい絵（60 未満）は空の線を太い実線に、大きい絵は細い破線に（案の頁）
        let small = width < 60
        ZStack(alignment: .topLeading) {
            ForEach(n..<TrunkFragmentTicket.pieces, id: \.self) { i in
                TrunkFragmentPieceShape(indices: [i])
                    .stroke(emptyLine, style: StrokeStyle(lineWidth: (small ? 1.6 : 0.8) * k,
                                                          dash: small ? [] : [CGFloat(2 * k), CGFloat(1.6 * k)]))
            }
            if n > 0 {
                TrunkFragmentPrint()
                    .frame(width: TrunkFragmentTicket.width, height: TrunkFragmentTicket.height)
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: width, height: width * TrunkFragmentTicket.height / TrunkFragmentTicket.width, alignment: .topLeading)
                    .clipShape(TrunkFragmentPieceShape(indices: Array(0..<n)))
                // 埋まった切れ端の継ぎ目
                if n > 1 {
                    TrunkFragmentSeams(count: n - 1)
                        .stroke(Color(trunk: TrunkRGBA(r: 90, g: 29, b: 27, a: 0.3)), lineWidth: 0.35 * k)
                }
            }
        }
        .frame(width: width, height: width * TrunkFragmentTicket.height / TrunkFragmentTicket.width, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 切れ端1つ（開けた画面で札の切符へ飛ぶもの・投稿のお礼で届いたもの）。幅 `size`、高さ 1.6 倍（案の頁の `onePiece`）
struct TrunkFragmentPieceView: View {
    let index: Int
    var size: Double = 40
    /// 落とす影（札の中の小さい印では消す）
    var shadow = true

    var body: some View {
        let i = max(0, min(TrunkFragmentTicket.pieces - 1, index))
        let k = size / 26
        let left = Double(i) * 20 - 2
        TrunkFragmentPrint()
            .frame(width: TrunkFragmentTicket.width, height: TrunkFragmentTicket.height)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: TrunkFragmentTicket.width * k, height: TrunkFragmentTicket.height * k, alignment: .topLeading)
            .clipShape(TrunkFragmentPieceShape(indices: [i], scale: k))
            .offset(x: -left * k, y: 2 * k)
            .frame(width: size, height: size * 1.6, alignment: .topLeading)
            .clipped()
            .shadow(color: Color.black.opacity(shadow ? 0.7 : 0), radius: shadow ? 8 : 0, x: 0, y: shadow ? 6 : 0)
            .accessibilityHidden(true)
    }
}

/// 切れ端の輪郭（いくつか合わせた形）。座標は 100×44 の箱を描く面の幅に合わせる（`scale` を渡せば固定の倍率）
struct TrunkFragmentPieceShape: Shape {
    let indices: [Int]
    var scale: Double? = nil

    func path(in rect: CGRect) -> Path {
        let k = scale ?? Double(rect.width) / TrunkFragmentTicket.width
        var path = Path()
        for i in indices {
            let pts = TrunkFragmentTicket.piece(i)
            for (j, p) in pts.enumerated() {
                let pt = CGPoint(x: Double(rect.minX) + p.x * k, y: Double(rect.minY) + p.y * k)
                if j == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }
        return path
    }
}

/// 埋まった切れ端の間の裂け目の線
private struct TrunkFragmentSeams: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        let k = Double(rect.width) / TrunkFragmentTicket.width
        var path = Path()
        for x in TrunkFragmentTicket.cuts.prefix(count) {
            for (j, p) in TrunkFragmentTicket.cutLine(x).enumerated() {
                let pt = CGPoint(x: Double(rect.minX) + p.x * k, y: Double(rect.minY) + p.y * k)
                if j == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
        }
        return path
    }
}

/// 切符の刷り（100×44 の箱で描く・紙、上下の赤茶の帯と真鍮の細線、JOURNEY と通し番号、右の穴）。
/// 刷った字は絵の一部（固定の大きさ・読み上げから外す。板 06「きっぷの表と裏」は固定でよい）
private struct TrunkFragmentPrint: View {
    var body: some View {
        let ink = Color(trunk: TrunkFragmentTicket.ink)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
                    Path { $0.addRect(CGRect(x: x, y: y, width: w, height: h)) }
                }
                func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
                    Path { $0.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)) }
                }
                let w = TrunkFragmentTicket.width, h = TrunkFragmentTicket.height
                ctx.fill(rect(0, 0, w, h), with: .color(Color(trunk: TrunkFragmentTicket.paper)))
                ctx.fill(rect(0, 0, w, h), with: .linearGradient(
                    Gradient(colors: [Color(trunk: TrunkFragmentTicket.paperLight), Color(trunk: TrunkFragmentTicket.paperShade)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
                // 薄い丸い印
                ctx.stroke(circle(76, 24, 13), with: .color(ink.opacity(0.09)), lineWidth: 0.6)
                ctx.stroke(circle(76, 24, 10), with: .color(ink.opacity(0.07)), style: StrokeStyle(lineWidth: 0.4, dash: [1, 1.2]))
                // 上の帯と真鍮の細線、下の帯
                ctx.fill(rect(0, 0, w, 7), with: .color(ink))
                ctx.fill(rect(0, 7, w, 1), with: .color(WebTheme.accent))
                ctx.fill(rect(0, 9, w, 0.4), with: .color(ink.opacity(0.5)))
                ctx.fill(rect(0, 40, w, 0.5), with: .color(WebTheme.accent))
                ctx.fill(rect(0, 40.5, w, 3.5), with: .color(ink))
                // 字の上の線と、真ん中のひし形
                var rule = Path()
                rule.move(to: CGPoint(x: 26, y: 17)); rule.addLine(to: CGPoint(x: 41.5, y: 17))
                rule.move(to: CGPoint(x: 50.5, y: 17)); rule.addLine(to: CGPoint(x: 66, y: 17))
                ctx.stroke(rule, with: .color(ink.opacity(0.55)), lineWidth: 0.5)
                var diamond = Path()
                diamond.move(to: CGPoint(x: 46, y: 14.6)); diamond.addLine(to: CGPoint(x: 48.4, y: 17))
                diamond.addLine(to: CGPoint(x: 46, y: 19.4)); diamond.addLine(to: CGPoint(x: 43.6, y: 17))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(Color(trunk: TrunkRGBA(0xB8955A))))
                // 改札の穴
                ctx.fill(circle(88, 24, 3.2), with: .color(Color(trunk: TrunkRGBA(0x2B1B17))))
                ctx.stroke(circle(88, 24, 3.9), with: .color(ink.opacity(0.5)), lineWidth: 0.5)
            }
            Text(verbatim: "JOURNEY")
                .font(.custom(JPFont.displayName, fixedSize: 12))
                .tracking(1.5)
                .foregroundStyle(ink)
                .fixedSize()
                .position(x: 46.75, y: 27)
            Text(verbatim: "No. 0012")
                .font(.system(size: 3.6).monospacedDigit())
                .tracking(0.8)
                .foregroundStyle(ink.opacity(0.75))
                .fixedSize()
                .position(x: 46.4, y: 35.8)
        }
        .frame(width: TrunkFragmentTicket.width, height: TrunkFragmentTicket.height)
        .accessibilityHidden(true)
    }
}
