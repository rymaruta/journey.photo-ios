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

    /// 指の下の区分（なぞっている間だけ）。🔴 `@GestureState` にする（2026-11-11 確かめ役の指摘）: スクロールが指を取る・
    /// 電話・タブの切り替えで操作が取り消されると `onEnded` は来ない。`@State` だと塗りと札がなぞった区分のまま残った。
    /// `@GestureState` は取り消しでも必ず nil に戻る
    @GestureState private var traced: String?

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
                .onTapGesture(coordinateSpace: .local) { point in
                    if let area = map.area(at: point, container: size, in: areas) { onSelect(area) }
                }
                // 🔴 **`simultaneousGesture` にする**（2026-11-11・run 1012 の数）: `.gesture` だと地図の上から払っても
                // 画面が流れなかった（地図の y 680.7 → 680.7。同じ回に右の札から払うと 680.7 → 50.3 と流れた＝
                // スクロールは止まっておらず、地図の長押し→引くの操作が指を取っていた）。同時に受ければ、長押しの前に
                // 動いた指はスクロールへ渡る。なぞり始めたら探すの画面がスクロールを止める（`scrollDisabled`）
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: SpotRegionMap.traceDelay)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .updating($traced) { value, state, _ in
                            guard case .second(true, let drag?) = value else { return }
                            // 区分の外（地図の枠の外）へ出た間は、最後の区分のまま
                            if let area = map.area(at: drag.location, container: size, in: areas) { state = area }
                        }
                        .onEnded { value in
                            // 地図の外で離したら取り消し（選ばない・`area(at:)` は枠の外で nil）
                            guard case .second(true, let drag?) = value,
                                  let area = map.area(at: drag.location, container: size, in: areas) else { return }
                            onSelect(area)
                        }
                )
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
