import SwiftUI

/// 探すの「撮影スポット」の段の**地図**（札 #524 の続き・2026-11-11 owner）。区分を押すと選ぶ。
/// **地図の型（`SpotRegionMap`）に依らない**——形・区分は型から読む。いまは日本地図（地方）だけ。
///
/// - 拡大・移動はしない（段の中の小さな地図。県はこの先の一覧で選ぶ）
/// - **ひと押し**で区分を選ぶ（押した点の片の区分・当たりは `SpotRegionMap.area(at:)`）。
///   **長押し（0.25 秒・Web と同じ）でなぞる**: 指の下の区分が塗られ、札がその区分に替わる。離すと選ぶ。
///   地図の外で離すと取り消し（Web と同じ）。なぞる前に動かした指は画面のスクロールに渡す（長押しが先）
/// - 塗り: 選んでいる・なぞっている区分は真鍮（黒地の上なので可・CLAUDE.md）。撮影スポットのある片は白 14%、
///   無い片は白 5%（押しても何もしない）。片の境は黒 0.6pt。日本の沖縄は左上の挿入図（細い枠）
/// - 読み上げ: 地図は1つの要素として名前だけ言う。日本の地方は上の地方のチップでも同じに選べる
struct SpotRegionMapView: View {

    let map: SpotRegionMap
    let areas: [SpotMapArea]
    /// 選んでいる区分の id
    let selected: String?
    /// なぞっている区分の id（札もこれに替わる・段は外側のスクロールを止める）。**この画面の `traced` を写すだけ**
    @Binding var tracing: String?
    let onSelect: (String) -> Void

    /// なぞる操作の状態（`SpotMapTrace`）。取り消し（スクロール・電話・タブの切り替え・画面を離れた）でも必ず空に戻る
    /// （UIKit の長押しが `.cancelled` を届け、外したときも取り消しとして終える・`SpotMapTraceCatcher`）
    @State private var trace = SpotMapTrace()
    private var traced: String? { trace.area }

    /// 撮影スポットのある片の地（白の割合）
    nonisolated static let coveredWhite: Double = 0.14
    /// 撮影スポットの無い片の地（白の割合）
    nonisolated static let emptyWhite: Double = 0.05
    /// 片の境（黒）
    nonisolated static let edgeWidth: CGFloat = 0.6

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { ctx, _ in draw(&ctx, size: size) }
                .contentShape(Rectangle())
                // ひと押し（SwiftUI の押す操作は画面のスクロールを止めない・run 1022 の「tap」の回で 680.7 → 325.3）
                .onTapGesture(coordinateSpace: .local) { point in
                    if let area = map.area(at: point, container: size, in: areas) { onSelect(area) }
                }
                // なぞる（長押し 0.25 秒 → 引く）。UIKit の長押しを縦の送りに付ける（`SpotMapTraceCatcher` の注記）
                .background {
                    SpotMapTraceCatcher(delay: SpotRegionMap.traceDelay) { point, began in
                        let area = map.area(at: point, container: size, in: areas)
                        _ = trace.handle(began ? .began(area) : .changed(area))
                    } onEnd: { point in
                        if let picked = trace.handle(.ended(map.area(at: point, container: size, in: areas))) {
                            onSelect(picked)
                        }
                    } onCancel: {
                        _ = trace.handle(.cancelled)
                    }
                }
        }
        .onChange(of: traced) { _, now in tracing = now }
        .onDisappear { tracing = nil }
        // 区分が替わったときだけ鳴らす（離して nil に戻るときは鳴らさない・確かめ役の指摘）
        .sensoryFeedback(.selection, trigger: traced) { _, now in now != nil }
        // 地図は1つの要素: 名前・いま選んでいる区分（値）・上下の払いで区分を替える（上のボタンでも選べる）
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(map.title)の地図", "Map of \(map.title)"))
        .accessibilityValue(areas.first { $0.id == selected }?.title ?? "")
        .accessibilityHint(L("上下に払うと区分を替えられます", "Swipe up or down to change the area"))
        .accessibilityAdjustableAction { direction in
            if let next = SpotRegionMap.step(selected, in: areas, forward: direction == .increment) { onSelect(next) }
        }
        .accessibilityIdentifier("search.spotIndex.map")
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let viewport = VisitedMapViewport()
        let content = map.shapes.size
        let lit = SpotRegionMap.highlighted(traced ?? selected, in: areas)
        let covered = SpotRegionMap.covered(areas)
        func mapped(_ p: CGPoint) -> CGPoint { viewport.screenPoint(forUnit: p, content: content, container: size) }
        for piece in map.shapes.mapPieces {
            var path = Path()
            for polygon in piece.polygons {
                guard let first = polygon.first else { continue }
                path.move(to: mapped(first))
                for p in polygon.dropFirst() { path.addLine(to: mapped(p)) }
                path.closeSubpath()
            }
            let fill: Color = lit.contains(piece.name) ? WebTheme.accent
                : Color.white.opacity(covered.contains(piece.name) ? Self.coveredWhite : Self.emptyWhite)
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(Color.black), lineWidth: Self.edgeWidth)
        }
        // 挿入図の枠（日本の沖縄・細い線）
        if let inset = map.shapes.inset {
            let a = mapped(inset.origin), b = mapped(CGPoint(x: inset.maxX, y: inset.maxY))
            var frame = Path()
            frame.addRect(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
            ctx.stroke(frame, with: .color(WebTheme.hairline), lineWidth: JPStroke.hairline)
        }
    }
}

/// 段の「写真｜地図」の切り替え（`ProfileTabBar` の札・2026-11-11 owner「タブ切り替えとかでもいいから縦に長くならないように」）
enum SpotIndexMode: String, CaseIterable, PagedTab {
    case photos, map

    var tabTitle: String {
        switch self {
        case .photos: return L("写真", "Photos")
        case .map: return L("地図", "Map")
        }
    }

    var tabIdentifier: String { "search.spotIndex.mode.\(rawValue)" }
}
