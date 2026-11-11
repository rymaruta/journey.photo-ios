import SwiftUI

/// 探すの「撮影スポット」の段の**日本地図**（札 #524 の続き・2026-11-11 owner）。地方を押すと選ぶ。
///
/// - 形は「行った県」の地図と同じ `PrefectureMapGeometry`（`PrefectureMapGeometry.bundled`）。拡大・移動はしない
///   （段の中の小さな地図。県はこの先の一覧で選ぶ）
/// - **ひと押し**で地方を選ぶ（押した点の県の地方・当たりは `SpotRegionMap.region`）。
///   **長押し（0.25 秒・Web と同じ）でなぞる**: 指の下の地方が塗られ、札がその地方に替わる。離すと選ぶ。
///   地図の外で離すと取り消し（Web と同じ）。なぞる前に動かした指は画面のスクロールに渡す（長押しが先）
/// - 塗り: 選んでいる・なぞっている地方は真鍮（黒地の上なので可・CLAUDE.md）。撮影スポットのある県は白 14%、
///   無い県は白 5%（押しても何もしない）。県の境は黒 0.6pt。沖縄は左上の挿入図（細い枠）
/// - 読み上げ: 地図は1つの要素として名前だけ言う。**同じことが上の地方のチップでできる**（チップと地図の選択は1つ）
struct SpotRegionMapView: View {

    let geometry: PrefectureMapGeometry
    let groups: [SpotPrefectureIndex.Group]
    /// 選んでいる地方
    let selected: String?
    /// なぞっている地方（札もこれに替わる）
    @Binding var tracing: String?
    let onSelect: (String) -> Void

    /// 撮影スポットのある県の地（白の割合）
    nonisolated static let coveredWhite: Double = 0.14
    /// 撮影スポットの無い県の地（白の割合）
    nonisolated static let emptyWhite: Double = 0.05
    /// 県の境（黒）
    nonisolated static let edgeWidth: CGFloat = 0.6

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { ctx, _ in draw(&ctx, size: size) }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    if let region = SpotRegionMap.region(at: point, container: size, geometry: geometry, groups: groups) {
                        onSelect(region)
                    }
                }
                .gesture(
                    LongPressGesture(minimumDuration: SpotRegionMap.traceDelay)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value else { return }
                            if let region = SpotRegionMap.region(at: drag.location, container: size,
                                                                 geometry: geometry, groups: groups) {
                                tracing = region
                            }
                        }
                        .onEnded { value in
                            defer { tracing = nil }
                            guard case .second(true, let drag?) = value, let traced = tracing else { return }
                            // 地図の外で離したら取り消し（選ばない）
                            guard CGRect(origin: .zero, size: size).contains(drag.location) else { return }
                            onSelect(traced)
                        }
                )
        }
        .sensoryFeedback(.selection, trigger: tracing)
        // 地図は1つの要素として名前だけ言う（県・地方の形は読ませない）。選ぶのは上の地方のチップでも同じ
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("日本地図。地方を押すと選べます。上の地方のボタンでも選べます",
                              "Map of Japan. Tap a region to choose it, or use the region buttons above"))
        .accessibilityIdentifier("search.spotIndex.map")
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let viewport = VisitedMapViewport()
        let content = geometry.size
        let lit = SpotRegionMap.highlighted(tracing ?? selected)
        let covered = SpotRegionMap.covered(groups)
        func mapped(_ p: CGPoint) -> CGPoint { viewport.screenPoint(forUnit: p, content: content, container: size) }
        for piece in geometry.pieces {
            var path = Path()
            for polygon in piece.polygons {
                guard let first = polygon.first else { continue }
                path.move(to: mapped(first))
                for p in polygon.dropFirst() { path.addLine(to: mapped(p)) }
                path.closeSubpath()
            }
            let fill: Color = lit.contains(piece.prefecture) ? WebTheme.accent
                : Color.white.opacity(covered.contains(piece.prefecture) ? Self.coveredWhite : Self.emptyWhite)
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(Color.black), lineWidth: Self.edgeWidth)
        }
        // 沖縄の挿入図の枠（細い線）
        if let inset = geometry.inset {
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
