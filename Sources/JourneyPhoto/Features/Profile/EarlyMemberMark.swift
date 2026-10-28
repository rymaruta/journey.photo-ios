import SwiftUI

/// 初期メンバーの印（名前の横の真鍮の盾＋墨の星・2026-10-28 owner の決定）。
///
/// **出すかどうかはサーバーが決める**（プロフィールの `earlyMark`・`UserProfile.showsEarlyMark`）。
/// 資格は初期ユーザーのバッジで、既定で付き、本人が外せる。既定で出るのは名前の横に
/// 公式の印・Pro マーク・選んだバッジのどれも出ていない人だけ（サーバーの `showsEarlyMark`）。
///
/// 形は公式の封印と同じ「単色の真鍮 ＋ 墨のアイコン」。公式（封印）・Pro（丸）と**輪郭で
/// 見分ける**ために盾にした（名前を伏せた比べで 16px でも取り違えなかった）。座標は Web の
/// `photo-gallery/app/components/EarlyMemberMark.tsx` と同じ 24 の升目（`EarlyMemberMarkGeometry`）
struct EarlyMemberMark: View {
    /// 印の高さ（pt）。文字サイズの設定による拡大は呼ぶ側で済ませておく
    let side: Double

    var body: some View {
        ZStack {
            EarlyMemberMarkShape(part: .shield).fill(WebTheme.accent)
            EarlyMemberMarkShape(part: .star).fill(WebTheme.accentText)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EarlyMemberMarkGeometry.label)
    }
}

/// 印の形（24 の升目）。テストで形を見張れるように画面から分けてある
enum EarlyMemberMarkGeometry {
    static var label: String { L("初期からのメンバー", "Early member") }

    enum Step: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case quad(control: CGPoint, to: CGPoint)
        case close
    }

    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    /// 盾（Web: `M12 0.9L21.1 4Q21.8 4.2 21.8 5V11.2Q21.8 18.9 12.35 23Q12 23.15 11.65 23Q2.2 18.9 2.2 11.2V5Q2.2 4.2 2.9 4Z`）
    static let shield: [Step] = [
        .move(p(12, 0.9)), .line(p(21.1, 4)), .quad(control: p(21.8, 4.2), to: p(21.8, 5)),
        .line(p(21.8, 11.2)), .quad(control: p(21.8, 18.9), to: p(12.35, 23)),
        .quad(control: p(12, 23.15), to: p(11.65, 23)), .quad(control: p(2.2, 18.9), to: p(2.2, 11.2)),
        .line(p(2.2, 5)), .quad(control: p(2.2, 4.2), to: p(2.9, 4)), .close,
    ]

    /// 角を丸めた五つの星。盾は下が尖るぶん重心が上にあるので、0.5 上げてある
    static let star: [Step] = [
        .move(p(11.8, 5.46)), .quad(control: p(12, 4.95), to: p(12.2, 5.46)),
        .line(p(13.57, 9.01)), .quad(control: p(13.76, 9.52), to: p(14.31, 9.55)),
        .line(p(18.11, 9.76)), .quad(control: p(18.66, 9.79), to: p(18.23, 10.13)),
        .line(p(15.28, 12.53)), .quad(control: p(14.85, 12.88), to: p(14.99, 13.41)),
        .line(p(15.97, 17.08)), .quad(control: p(16.11, 17.61), to: p(15.65, 17.31)),
        .line(p(12.46, 15.25)), .quad(control: p(12, 14.95), to: p(11.54, 15.25)),
        .line(p(8.35, 17.31)), .quad(control: p(7.89, 17.61), to: p(8.03, 17.08)),
        .line(p(9.01, 13.41)), .quad(control: p(9.15, 12.88), to: p(8.72, 12.53)),
        .line(p(5.77, 10.13)), .quad(control: p(5.34, 9.79), to: p(5.89, 9.76)),
        .line(p(9.69, 9.55)), .quad(control: p(10.24, 9.52), to: p(10.43, 9.01)), .close,
    ]
}

/// 24 の升目の形を、渡された枠いっぱいに描く
struct EarlyMemberMarkShape: Shape {
    enum Part { case shield, star }
    let part: Part

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * k) / 2
        let oy = rect.minY + (rect.height - 24 * k) / 2
        func at(_ q: CGPoint) -> CGPoint { CGPoint(x: ox + q.x * k, y: oy + q.y * k) }
        var path = Path()
        for step in part == .shield ? EarlyMemberMarkGeometry.shield : EarlyMemberMarkGeometry.star {
            switch step {
            case .move(let q): path.move(to: at(q))
            case .line(let q): path.addLine(to: at(q))
            case .quad(let c, let q): path.addQuadCurve(to: at(q), control: at(c))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
