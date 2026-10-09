import SwiftUI

/// Pro の画面の線の絵（板 63 の4つの利点・板 43 の設定の行）。24 の升目の座標を板の SVG から写した。
///
/// どれも線（stroke）だけで描く。太さと色は呼ぶ側（板: 案内は白 1.8・設定は真鍮 1.7）
enum ProIcon: String, CaseIterable {
    /// 作例を重ねて撮る（カメラ）
    case overlay
    /// 光と天気の知らせ（地平線と日の出）
    case light
    /// 電波なしで使える旅（ピン）
    case offline
    /// Pro マークと Pro 限定の章（菱形の中の星）
    case chapter
    /// サポーター証（カード）
    case card
    /// 名前の横のバッジ（リボンのメダル）
    case medal

    /// 24 の升目の線を `side` の大きさに
    @MainActor
    func path(side: Double) -> Path {
        let k = side / 24
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        func circle(_ cx: Double, _ cy: Double, _ r: Double) -> CGRect {
            CGRect(x: (cx - r) * k, y: (cy - r) * k, width: r * 2 * k, height: r * 2 * k)
        }
        return Path { path in
            switch self {
            case .overlay:
                // M4 8h3l2-2h6l2 2h3v11H4z ・ 中心 (12,14) 半径 3.5 の丸
                path.move(to: p(4, 8))
                path.addLine(to: p(7, 8))
                path.addLine(to: p(9, 6))
                path.addLine(to: p(15, 6))
                path.addLine(to: p(17, 8))
                path.addLine(to: p(20, 8))
                path.addLine(to: p(20, 19))
                path.addLine(to: p(4, 19))
                path.closeSubpath()
                path.addEllipse(in: circle(12, 14, 3.5))
            case .light:
                // M3 18h18 ・ M7 18a5 5 0 0 1 10 0 ・ M12 6v3 ・ M5 10l2 2 ・ M19 10l-2 2
                path.move(to: p(3, 18))
                path.addLine(to: p(21, 18))
                path.move(to: p(7, 18))
                path.addArc(center: p(12, 18), radius: 5 * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                path.move(to: p(12, 6))
                path.addLine(to: p(12, 9))
                path.move(to: p(5, 10))
                path.addLine(to: p(7, 12))
                path.move(to: p(19, 10))
                path.addLine(to: p(17, 12))
            case .offline:
                // M12 21s-6-5.6-6-11a6 6 0 0 1 12 0c0 5.4-6 11-6 11z ・ 中心 (12,10) 半径 2.5 の丸
                path.move(to: p(12, 21))
                path.addCurve(to: p(6, 10), control1: p(12, 21), control2: p(6, 15.4))
                path.addArc(center: p(12, 10), radius: 6 * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                path.addCurve(to: p(12, 21), control1: p(18, 15.4), control2: p(12, 21))
                path.closeSubpath()
                path.addEllipse(in: circle(12, 10, 2.5))
            case .chapter:
                // M12 3.5 20.5 12 12 20.5 3.5 12Z ・ 4つの二次曲線の星
                path.move(to: p(12, 3.5))
                path.addLine(to: p(20.5, 12))
                path.addLine(to: p(12, 20.5))
                path.addLine(to: p(3.5, 12))
                path.closeSubpath()
                path.move(to: p(12, 7.5))
                path.addQuadCurve(to: p(16.5, 12), control: p(12, 12))
                path.addQuadCurve(to: p(12, 16.5), control: p(12, 12))
                path.addQuadCurve(to: p(7.5, 12), control: p(12, 12))
                path.addQuadCurve(to: p(12, 7.5), control: p(12, 12))
                path.closeSubpath()
            case .card:
                // rect x3 y5.5 18×13 角 2.5 ・ M3 10h18 ・ M7 15h4
                path.addRoundedRect(in: CGRect(x: 3 * k, y: 5.5 * k, width: 18 * k, height: 13 * k),
                                    cornerSize: CGSize(width: 2.5 * k, height: 2.5 * k))
                path.move(to: p(3, 10))
                path.addLine(to: p(21, 10))
                path.move(to: p(7, 15))
                path.addLine(to: p(11, 15))
            case .medal:
                // 中心 (12,14) 半径 6 の丸 ・ M8.5 3l3.5 5 3.5-5
                path.addEllipse(in: circle(12, 14, 6))
                path.move(to: p(8.5, 3))
                path.addLine(to: p(12, 8))
                path.addLine(to: p(15.5, 3))
            }
        }
    }
}

/// 線の絵を1つ置く
struct ProIconView: View {
    let icon: ProIcon
    var side: Double = 20
    var color: Color = .white
    var lineWidth: Double = 1.8

    var body: some View {
        icon.path(side: side)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * side / 24, lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
