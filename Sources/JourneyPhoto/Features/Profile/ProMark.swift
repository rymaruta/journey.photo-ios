import SwiftUI

/// Pro マーク（名前の横・板 ProMarkOptions・2026-10-09）。
///
/// **Pro 会員にだけ出す**（`UserProfile.isPro`）。いまは誰も Pro ではないが、立てば出る。
/// 形は本人が選ぶ（名前の横の画面）: 絞り羽根（既定）か PRO の札。
///
/// 素材の `marks/pro-mark-*.svg` の形を SwiftUI で描く（24 の升目の座標をそのまま写した）。
/// 真鍮の印は**黒い地の上だけ**に置く（名前の行は黒地。写真の上には置かない）。
/// 15pt を切ったら線を太らせた小さい版（`ProMarkFit.isSmall`）。
///
/// **どの大きさでも光る真鍮の1つの形**（2026-10-16 owner「Pro のデザインが画面によって違う」）。
/// v2（2026-10-14）では小さい版だけ真鍮の単色・PRO の札は真鍮の塗りに墨の字にしていたが、
/// 写真の詳細・コメント（小さい）とプロフィール（大きい）で別の印に見えたので、光る真鍮にそろえた。
/// 小さい版で変えるのは**線の太さと穴の形だけ**（`ProMarkGeometry`・形は同じ）
struct ProMark: View {

    let style: ProMarkStyle
    /// 印の高さ（pt）。文字サイズの設定による拡大は呼ぶ側で済ませておく
    let side: Double

    var body: some View {
        Group {
            switch style {
            case .iris:
                ProMarkIris(side: side, small: ProMarkFit.isSmall(side: side))
            case .plate:
                ProMarkPlate(side: side, small: ProMarkFit.isSmall(side: side))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Pro 会員", "Pro member"))
    }
}

/// 印の色（素材の SVG の値）
enum ProMarkColors {
    /// 真鍮の丸の上から下（`#F3DCA6 → #C9A66B → #9A7A45`）
    static let irisStops: [(UInt32, Double)] = [(0xF3DCA6, 0), (0xC9A66B, 0.5), (0x9A7A45, 1)]
    /// 札の縁と字の、左から右へ光る真鍮
    static let sheenStops: [(UInt32, Double)] = [
        (0x9A7A45, 0), (0xF6E3B4, 0.3), (0xC9A66B, 0.55), (0xFFF1CC, 0.8), (0x8E6F40, 1),
    ]
    /// 羽根と絞りの穴の墨
    static let ink: UInt32 = 0x1A140A
    /// 札の地
    static let plate: UInt32 = 0x0C0C0D
    /// 丸の内側の細い光
    static let highlight: UInt32 = 0xFFF4D6

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    static func stops(_ list: [(UInt32, Double)]) -> [Gradient.Stop] {
        list.map { Gradient.Stop(color: color($0.0), location: $0.1) }
    }
}

/// 絞り羽根の幾何（24 の升目）。テストで形を見張れるように画面から分けてある
enum ProMarkGeometry {
    /// 真鍮の丸の半径
    static let discRadius: Double = 11.2
    /// 内側の細い光の輪の半径（大きい版だけ）
    static let highlightRadius: Double = 10.4

    /// 絞りの穴（六角形）の頂点。小さい版は穴を大きく
    static func aperture(small: Bool) -> [CGPoint] {
        small
            ? [CGPoint(x: 12, y: 7.8), CGPoint(x: 15.64, y: 9.9), CGPoint(x: 15.64, y: 14.1),
               CGPoint(x: 12, y: 16.2), CGPoint(x: 8.36, y: 14.1), CGPoint(x: 8.36, y: 9.9)]
            : [CGPoint(x: 12, y: 8.4), CGPoint(x: 15.12, y: 10.2), CGPoint(x: 15.12, y: 13.8),
               CGPoint(x: 12, y: 15.6), CGPoint(x: 8.88, y: 13.8), CGPoint(x: 8.88, y: 10.2)]
    }

    /// 羽根の線の外の端（頂点ごとに1本・大小共通）
    static let bladeEnds: [CGPoint] = [
        CGPoint(x: 21.89, y: 6.74), CGPoint(x: 21.50, y: 17.94), CGPoint(x: 11.61, y: 23.19),
        CGPoint(x: 2.11, y: 17.26), CGPoint(x: 2.50, y: 6.06), CGPoint(x: 12.39, y: 0.81),
    ]

    /// 羽根の線の太さ。小さい版は太く（細い線は 14pt 以下で消える）
    static func bladeWidth(small: Bool) -> Double { small ? 1.6 : 1.05 }

    static func scaled(_ point: CGPoint, by k: Double) -> CGPoint {
        CGPoint(x: Double(point.x) * k, y: Double(point.y) * k)
    }
}

/// 絞り羽根（既定）。真鍮の丸に墨の六角の穴と6本の羽根
private struct ProMarkIris: View {
    let side: Double
    let small: Bool

    var body: some View {
        let k = side / 24
        let ink = ProMarkColors.color(ProMarkColors.ink)
        let disc = ProMarkGeometry.discRadius * 2 * k
        ZStack {
            // どの大きさでも光る真鍮（2026-10-16・画面ごとに印が違って見えた）
            Circle()
                .fill(LinearGradient(stops: ProMarkColors.stops(ProMarkColors.irisStops),
                                     startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 0.4, y: 1)))
                .frame(width: disc, height: disc)
            // 羽根の線。丸い端が丸の外へはみ出さないよう丸で切る
            blades(k)
                .stroke(ink, style: StrokeStyle(lineWidth: ProMarkGeometry.bladeWidth(small: small) * k,
                                                lineCap: .round))
                .frame(width: side, height: side)
                .clipShape(Circle())
            aperture(k)
                .fill(ink)
                .frame(width: side, height: side)
            Circle()
                .stroke(ProMarkColors.color(ProMarkColors.highlight).opacity(0.5), lineWidth: 0.6 * k)
                .frame(width: ProMarkGeometry.highlightRadius * 2 * k,
                       height: ProMarkGeometry.highlightRadius * 2 * k)
        }
        .frame(width: side, height: side)
    }

    private func aperture(_ k: Double) -> Path {
        Path { path in
            let points = ProMarkGeometry.aperture(small: small).map { ProMarkGeometry.scaled($0, by: k) }
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    private func blades(_ k: Double) -> Path {
        Path { path in
            let starts = ProMarkGeometry.aperture(small: small)
            for (start, end) in zip(starts, ProMarkGeometry.bladeEnds) {
                path.move(to: ProMarkGeometry.scaled(start, by: k))
                path.addLine(to: ProMarkGeometry.scaled(end, by: k))
            }
        }
    }
}

/// PRO の札。丸い墨の札に真鍮の縁と字（太めのシステムの書体）
private struct ProMarkPlate: View {
    let side: Double
    let small: Bool

    var body: some View {
        let k = side / 24
        let sheen = LinearGradient(stops: ProMarkColors.stops(ProMarkColors.sheenStops),
                                   startPoint: .leading, endPoint: .trailing)
        // 写真詳細の 13pt の名前では小さい版が約 11.5pt。旧 36:24 の幅では
        // 「PRO」の両端と縁が接近するため、文字の周りに余白を確保する。
        let line = (small ? 1.9 : 1.3) * k
        let width = ProMarkFit.width(side: side, style: .plate)
        let height = (small ? 22 : 18) * k + line
        ZStack {
            // どの大きさでも墨の札に光る真鍮の縁と字（2026-10-16・画面ごとに印が違って見えた）
            Capsule()
                .fill(ProMarkColors.color(ProMarkColors.plate))
                .overlay(Capsule().strokeBorder(sheen, lineWidth: line))
                .frame(width: width, height: height)
            Text("PRO")
                // 大きさは呼ぶ側で文字サイズの設定に合わせ済み（ここで二重に伸ばさない）
                // 小さい版は字を太らせて読める形を保つ（線と同じく太さだけ変える）
                .font(.system(size: (small ? 13.5 : 11) * k, weight: small ? .heavy : .bold))
                .tracking(0.6 * k)
                .foregroundStyle(sheen)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: ProMarkFit.width(side: side, style: .plate), height: side)
    }
}
