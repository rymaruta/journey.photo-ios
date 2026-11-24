import SwiftUI

/// 旅の道具の荷札（札 #714・2026-11-23 owner 決定・案の頁「荷札」）。
///
/// 高さ 44pt（見た目も押せる高さも同じ）。左の角を 8pt 斜めに落とし、右の角は 7pt の丸。左から 11pt の所に
/// 直径 7pt の穴（黒、白 22% の輪）。地は #1C1C1E から #161617 への薄い濃淡、縁は白 20%。
/// 字は 15pt の太さ 600、白 95%。件数は名前の右 6pt に板の件数バッジ（`CountBadge`・真鍮はここだけ）。
/// 大きな字では札が伸び、6字を超えると2行に折る
struct TripToolTag: View {

    let title: String
    var badge: Int? = nil
    /// 名前の右に添える小さな絵（スタンプ帳の最近の3つ・`StampBookEntry.recentAccessory`）。読み上げは呼び手が値で言う。
    /// 2026-11-23 判断（1.2.0 の統合）: 縦の行の右にあった最近の3つを、荷札でも同じ部品で出す（高さ 32pt で札の 44pt に収まる）
    var accessory: AnyView? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    /// 札どうしの間と、右の端を黒へ溶かす幅
    nonisolated static let spacing: CGFloat = 10
    nonisolated static let edgeFade: CGFloat = 18
    nonisolated static let height: CGFloat = 44
    /// 名前の左（穴と斜めの角の分）と右
    nonisolated static let leadingInset: CGFloat = 24
    nonisolated static let trailingInset: CGFloat = 13
    nonisolated static let chamfer: CGFloat = 8
    nonisolated static let cornerRadius: CGFloat = 7
    nonisolated static let holeDiameter: CGFloat = 7
    /// 穴の中心の、左の端からの位置
    nonisolated static let holeCenterX: CGFloat = 11
    /// 地の濃淡（上 #1C1C1E → 下 #161617・面の段から読む）と縁
    nonisolated static let faceTop: UInt32 = BrandPalette.surface4
    nonisolated static let faceBottom: UInt32 = BrandPalette.surface2
    nonisolated static let edgeOpacity = 0.20
    nonisolated static let holeRingOpacity = 0.22
    nonisolated static let textOpacity = 0.95
    /// 大きな字で2行に折る字の数
    nonisolated static let wrapCharacters = 6

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(Self.textOpacity))
                .lineLimit(large ? 2 : 1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: !large || title.count <= Self.wrapCharacters, vertical: true)
                .frame(maxWidth: large && title.count > Self.wrapCharacters ? 6 * 22 : nil, alignment: .leading)
            if let badge {
                CountBadge(count: badge, maximum: 99)
            }
            if let accessory {
                accessory
            }
        }
        .padding(.leading, Self.leadingInset)
        .padding(.trailing, Self.trailingInset)
        .padding(.vertical, large ? 11 : 0)
        .frame(minHeight: Self.height)
        .background {
            ZStack(alignment: .leading) {
                TripToolTagShape()
                    .fill(LinearGradient(colors: [WebTheme.surface4, WebTheme.sheet],
                                         startPoint: .top, endPoint: .bottom))
                TripToolTagShape()
                    .stroke(Color.white.opacity(Self.edgeOpacity), lineWidth: JPStroke.hairline)
                Circle()
                    .fill(Color.black)
                    .frame(width: Self.holeDiameter, height: Self.holeDiameter)
                    .overlay(Circle().stroke(Color.white.opacity(Self.holeRingOpacity), lineWidth: 1.5))
                    .padding(.leading, Self.holeCenterX - Self.holeDiameter / 2)
            }
        }
        .contentShape(TripToolTagShape())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.map { L("\(title)、新しいものが\($0)件", "\(title), \($0) new") } ?? title)
        .accessibilityAddTraits(.isButton)
    }
}

/// 荷札の形（左の2つの角を斜めに落とし、右の2つの角を丸める）
struct TripToolTagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = min(TripToolTag.chamfer, rect.height / 2)
        let r = min(TripToolTag.cornerRadius, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}

/// 荷札を押したとき（案の頁）: 指が触れた瞬間に明るくなり（先に反応が見える）、少し遅れて穴を軸に 1° だけ傾いて縮む。
/// 離すとばねで戻る。動きを減らす設定では明るくなるだけ。
/// 軽い触覚1回は**押しが決まったときだけ**（`TripToolTapFeedback`）。ここで鳴らすと、押してから列の横の送りに移った指でも鳴った
struct TripToolTagStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 傾きと縮み（穴を軸に）
    nonisolated static let pressedAngle = -1.0
    nonisolated static let pressedScale = 0.98
    nonisolated static let pressedBrightness = 0.12

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let anchor = UnitPoint(x: 0, y: 0.5)
        return configuration.label
            .brightness(pressed ? Self.pressedBrightness : 0)
            .animation(nil, value: pressed)
            .rotationEffect(.degrees(pressed && !reduceMotion ? Self.pressedAngle : 0), anchor: anchor)
            .scaleEffect(pressed && !reduceMotion ? Self.pressedScale : 1, anchor: anchor)
            .animation(pressed ? .easeOut(duration: 0.1).delay(0.04) : .spring(response: 0.3, dampingFraction: 0.55),
                       value: pressed)
    }
}

/// 荷札の触覚（軽い1回）。**押しが決まった（指を離して開く）ときだけ鳴らす**——押したまま列の横の送り・縦の送りに
/// 移った指は押しが取り消され、ここは呼ばれない（2026-11-23 確かめ役の指摘）
struct TripToolTapFeedback: ViewModifier {
    @State private var taps = 0

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded { taps += 1 })
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
