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
/// - 読み上げ: 地図は1つの要素として名前だけ言う。日本の地方は写真の地方のチップでも同じに選べる
/// - **地方の名前の札**（「近畿 ›」・2026-11-12 owner「ガイドもないし」・Web の #625 とそろえる）: 黒の地・真鍮の細い縁・
///   白い名前・真鍮の「›」。押すとその地方を選ぶ（地図を押したのと同じ）。札は指を受けず（`allowsHitTesting(false)`）、
///   当たりは地図の側（`SpotRegionMap.area(at:)` が札の枠を先に見る）——札の上から長押ししてもなぞれる。
///   選んでいる・なぞっている地方の札は、名前と縁が真鍮になる（Web の `.jm-on`）。札は読み上げから外す（地図が1つの要素）
struct SpotRegionMapView: View {

    let map: SpotRegionMap
    let areas: [SpotMapArea]
    /// 選んでいる区分の id
    let selected: String?
    /// なぞっている区分の id（札もこれに替わる・段は外側のスクロールを止める）。**この画面の `traced` を写すだけ**
    @Binding var tracing: String?
    let onSelect: (String) -> Void
    /// 読み上げのダブルタップ（既定の操作）: いま選んでいる区分の一覧へ進む。地図の真ん中を押したことにして
    /// 区分を勝手に選ばない（確かめ役の指摘・2026-11-11）
    var onActivate: () -> Void = {}

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
                .overlay(alignment: .topLeading) { labels(size: size) }
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
        .accessibilityHint(L("上下に払うと地方を替えられます。ダブルタップで観光スポットの一覧へ進みます",
                             "Swipe up or down to change the region. Double-tap to see the photo spots"))
        .accessibilityAction { onActivate() }
        .accessibilityAdjustableAction { direction in
            if let next = SpotRegionMap.step(selected, in: areas, forward: direction == .increment) { onSelect(next) }
        }
        .accessibilityIdentifier("search.spotIndex.map")
    }

    /// 地方の名前の札。指は地図が受ける（札の枠は `area(at:)` が先に見る）
    private func labels(size: CGSize) -> some View {
        let lit = traced ?? selected
        return ZStack(alignment: .topLeading) {
            ForEach(map.labelFrames(container: size, in: areas)) { item in
                SpotMapLabelChip(text: item.label.text, on: item.label.area == lit)
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// 地図の上の地方の名前の札（「近畿 ›」）。見た目は Web の `.jm-rlabel`（黒 78% の地・真鍮 55% の 1pt の縁・影・白い名前・
/// 真鍮の「›」）。選んでいる・なぞっている地方は名前と縁が真鍮（縁 1.5pt）。
///
/// 2026-11-12 判断: 字は**システムの 12pt semibold**（Web は明朝 14px）。明朝は 18pt 未満に使わない決まり（`JPFont`）で、
/// 段の地図（幅 189）に 18pt の札は入らない。地図の絵の一部なので文字サイズの設定に追従させない（札の幅と置き場を
/// `SpotRegionMap.labelWidth` で決めているため。大きな字の人は、写真の地方のチップと読み上げで同じ地方を選べる）
struct SpotMapLabelChip: View {
    let text: String
    let on: Bool

    /// 地の黒（Web の rgb(0 0 0 / 0.78)）
    nonisolated static let fillOpacity: Double = 0.78
    /// 縁の真鍮（Web の 0.55）
    nonisolated static let edgeOpacity: Double = 0.55

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .foregroundStyle(on ? WebTheme.accent : WebTheme.text)
            Text(verbatim: "›")
                .foregroundStyle(WebTheme.accent)
        }
        .font(.system(size: SpotRegionMap.labelFontSize, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Color.black.opacity(Self.fillOpacity)))
        .overlay(Capsule().strokeBorder(WebTheme.accent.opacity(on ? 1 : Self.edgeOpacity), lineWidth: on ? 1.5 : 1))
        .shadow(color: Color.black.opacity(0.5), radius: 4, y: 2)
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
