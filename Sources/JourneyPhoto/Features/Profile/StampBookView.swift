import SwiftUI

/// 旅のスタンプ帳の部品（札 #712）: 1つのスタンプ（`StampView`）、帳面の日本地図（`StampBookMap`）、紙の地（`StampPaper`）。
///
/// 2026-11-23 判断（案の頁の模型どおり）:
/// - 帳面は**紙の色の地**（`StampInk.paper`）に朱肉の色で押す。黒い地にスタンプを直に置かない（朱肉の色は黒の上で読めない）。
///   紙の外（画面の地・行・題）は板どおり黒と白、合図は真鍮
/// - スタンプの中の字は絵の一部（旅のトランクの刻印と同じ扱い）。字の大きさは箱に合わせて決まり、Dynamic Type に追従しない。
///   読み上げは字で読む（`StampBookText.accessibility`）
/// - 字の位置は箱 100 の数（`StampLayout`）を、描く大きさに掛けて置く（`scaleEffect` で拡大すると字がにじむため）
/// - 朱肉のかすれ（模型はブラウザの雑音のフィルター）は入れていない。濃さ 90% だけ。実機で見て足すか決める
extension StampInk {
    static func swiftUIColor(_ hex: UInt32) -> Color { ProMarkColors.color(hex) }
}

/// 1つのスタンプ。正方形に収まる大きさで描く
struct StampView: View {
    let stamp: StampBook.Stamp
    /// 傾ける（帳面の中）。大きく見せる札と押す瞬間は傾けない
    var tilted = true

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            StampFace(stamp: stamp, side: side)
                .frame(width: side, height: side)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .rotationEffect(.degrees(tilted ? StampLayout.tilt(stamp.spotId) : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StampBookText.accessibility(stamp))
    }
}

/// スタンプの面（枠・県の形・地名・名前・日付）。`side` は描く一辺（pt）
private struct StampFace: View {
    let stamp: StampBook.Stamp
    let side: CGFloat

    var body: some View {
        let k = side / StampLayout.box
        let ink = StampInk.swiftUIColor(StampInk.color(prefecture: stamp.prefecture))
        let lines = StampLayout.nameLines(stamp.name)
        let nameSize = StampLayout.nameSize(lines)
        let baselines = StampLayout.nameBaselines(count: lines.count, size: nameSize)
        let placeSize = StampLayout.placeSize(stamp)
        ZStack {
            Canvas { ctx, size in
                let k = size.width / StampLayout.box
                StampDrawing.frame(stamp.frame, in: &ctx, k: k, ink: ink)
                StampDrawing.silhouette(stamp, in: &ctx, k: k, ink: ink)
            }
            Text(stamp.placeName)
                .font(.system(size: placeSize * k, weight: .bold))
                .tracking(0.5 * k)
                .lineLimit(1)
                .position(x: 50 * k, y: (StampLayout.placeY(stamp.frame) - placeSize * 0.35) * k)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(Font.custom(JPFont.displayName, fixedSize: nameSize * k))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: 50 * k, y: (baselines[index] - nameSize * 0.36) * k)
            }
            Text(StampBookText.stampDate(stamp.firstDay))
                .font(.system(size: 8 * k, weight: .bold).monospacedDigit())
                .tracking(0.6 * k)
                .lineLimit(1)
                .position(x: 50 * k, y: (StampLayout.dateY(stamp.frame) - 8 * 0.35) * k)
        }
        .foregroundStyle(ink)
        .opacity(0.9)
    }
}

/// スタンプを描く（箱 100 の数に `k` を掛ける）
enum StampDrawing {

    static func frame(_ frame: StampFrame, in ctx: inout GraphicsContext, k: CGFloat, ink: Color) {
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
        }
        var outer = Path()
        var inner = Path()
        switch frame {
        case .nature:
            outer.addEllipse(in: rect(4, 4, 92, 92))
            inner.addEllipse(in: rect(9.5, 9.5, 81, 81))
        case .history:
            for (path, r) in [(0, 47.5), (1, 42.0)] {
                var p = Path()
                let points = StampLayout.octagon(radius: r)
                p.move(to: CGPoint(x: points[0].x * k, y: points[0].y * k))
                for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.x * k, y: point.y * k)) }
                p.closeSubpath()
                if path == 0 { outer = p } else { inner = p }
            }
        case .town:
            outer.addRoundedRect(in: rect(5, 5, 90, 90), cornerSize: CGSize(width: 12 * k, height: 12 * k))
            inner.addRoundedRect(in: rect(10.5, 10.5, 79, 79), cornerSize: CGSize(width: 7 * k, height: 7 * k))
        case .abroad:
            outer.addEllipse(in: rect(3, 12, 94, 76))
            inner.addEllipse(in: rect(8, 17, 84, 66))
        }
        ctx.stroke(outer, with: .color(ink), lineWidth: (frame == .abroad ? 3 : 3.2) * k)
        ctx.stroke(inner, with: .color(ink), lineWidth: 1 * k)
    }

    /// 真ん中の絵: 日本は県の形（同梱の `japan-prefectures.json`）、海外は地球の線
    static func silhouette(_ stamp: StampBook.Stamp, in ctx: inout GraphicsContext, k: CGFloat, ink: Color) {
        if let prefecture = stamp.prefecture {
            guard let piece = PrefectureMapGeometry.bundled?.piece(prefecture),
                  let fit = StampLayout.silhouetteFit(bounds: piece.bounds) else { return }
            var path = Path()
            for polygon in piece.polygons {
                guard let first = polygon.first else { continue }
                func mapped(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: (Double(p.x) * fit.scale + fit.dx) * k, y: (Double(p.y) * fit.scale + fit.dy) * k)
                }
                path.move(to: mapped(first))
                for p in polygon.dropFirst() { path.addLine(to: mapped(p)) }
                path.closeSubpath()
            }
            ctx.fill(path, with: .color(ink.opacity(StampLayout.silhouetteOpacity)))
        } else {
            var globe = Path()
            globe.addEllipse(in: CGRect(x: 33 * k, y: 35 * k, width: 34 * k, height: 34 * k))
            globe.addEllipse(in: CGRect(x: 42.5 * k, y: 35 * k, width: 15 * k, height: 34 * k))
            for (x0, x1, y) in [(33.0, 67.0, 52.0), (36.0, 64.0, 43.0), (36.0, 64.0, 61.0)] {
                globe.move(to: CGPoint(x: x0 * k, y: y * k))
                globe.addLine(to: CGPoint(x: x1 * k, y: y * k))
            }
            ctx.stroke(globe, with: .color(ink.opacity(0.22)), lineWidth: 1.2 * k)
        }
    }
}

/// 紙の地（帳面の表紙・県のページ・大きなスタンプの札）
struct StampPaper<Content: View>: View {
    var top: CGFloat = JPSpace.s
    var bottom: CGFloat = JPSpace.s
    var horizontal: CGFloat = JPSpace.s
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontal)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .frame(maxWidth: .infinity)
            .background(StampInk.swiftUIColor(StampInk.paper), in: RoundedRectangle(cornerRadius: JPRadius.field))
            .foregroundStyle(StampInk.swiftUIColor(StampInk.sumi))
    }
}

/// 帳面の日本地図。スタンプのある県を、その地方の朱肉の色で薄く塗るだけ（回数で段を変えない。
/// 行った県マップの真鍮の段とは別の見た目にして、取り違えないようにする）。押すとその県のページ（`onOpen`）
struct StampBookMap: View {
    let stamped: Set<String>
    var onOpen: ((String) -> Void)?

    /// 地図の縦横の比（単位の空間の大きさ）
    private var aspect: CGFloat {
        guard let size = PrefectureMapGeometry.bundled?.size, size.height > 0 else { return 0.7 }
        return size.width / size.height
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, stamped: stamped)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard let onOpen, let name = Self.prefecture(at: location, size: geo.size),
                      stamped.contains(name) else { return }
                onOpen(name)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StampBookText.mapAccessibility(RegionList.prefectures.filter(stamped.contains)))
        .accessibilityIdentifier("stampBook.map")
    }

    /// 単位の空間 → 描く面の拡大と余白
    private static func fit(_ geometry: PrefectureMapGeometry, size: CGSize) -> (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        let scale = min(size.width / geometry.size.width, size.height / geometry.size.height)
        return (scale, (size.width - geometry.size.width * scale) / 2, (size.height - geometry.size.height * scale) / 2)
    }

    static func prefecture(at point: CGPoint, size: CGSize) -> String? {
        guard let geometry = PrefectureMapGeometry.bundled else { return nil }
        let f = fit(geometry, size: size)
        guard f.scale > 0 else { return nil }
        let unit = CGPoint(x: (point.x - f.dx) / f.scale, y: (point.y - f.dy) / f.scale)
        // 小さな県も指で押せるよう、22pt 以内の近い県を採る（行った県マップと同じ当たり判定）
        return geometry.prefecture(at: unit, tolerance: 22 / f.scale)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, stamped: Set<String>) {
        guard let geometry = PrefectureMapGeometry.bundled else { return }
        let f = fit(geometry, size: size)
        func mapped(_ p: CGPoint) -> CGPoint { CGPoint(x: f.dx + p.x * f.scale, y: f.dy + p.y * f.scale) }
        let paper = StampInk.swiftUIColor(StampInk.paper)
        for name in RegionList.prefectures {
            guard let piece = geometry.piece(name) else { continue }
            var path = Path()
            for polygon in piece.polygons {
                guard let first = polygon.first else { continue }
                path.move(to: mapped(first))
                for p in polygon.dropFirst() { path.addLine(to: mapped(p)) }
                path.closeSubpath()
            }
            let fill = stamped.contains(name)
                ? StampInk.swiftUIColor(StampInk.color(prefecture: name)).opacity(0.72)
                : StampInk.swiftUIColor(StampInk.paperShade)
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(paper), lineWidth: 0.6)
        }
        if let inset = geometry.inset {
            var frame = Path()
            let a = mapped(inset.origin)
            frame.addRoundedRect(in: CGRect(x: a.x, y: a.y, width: inset.width * f.scale, height: inset.height * f.scale),
                                 cornerSize: CGSize(width: 4, height: 4))
            ctx.stroke(frame, with: .color(StampInk.swiftUIColor(StampInk.paperLine)), lineWidth: 0.8)
        }
    }
}

/// 点線の丸（まだ押されていない所）。「ここに押されます」「つぎのひとつ」
struct StampEmptySlot: View {
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(StampInk.swiftUIColor(StampInk.paperLine), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            Text(text)
                .font(JPFont.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(StampInk.swiftUIColor(StampInk.sumiSoft))
                .minimumScaleFactor(0.8)
                .padding(JPSpace.xs)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(JPSpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: "\n", with: ""))
    }
}
