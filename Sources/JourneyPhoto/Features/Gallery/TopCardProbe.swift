import SwiftUI

/// **UI テストの事実取りだけ**（`PreviewSession.layoutProbe`・`-JPPreviewLayoutProbe YES`・Debug のみ・2026-11-14）。
///
/// ホームの上の札（`TopCardFace`）の小さい行（出典）が、何pt の幅に・何pt 要る字を入れているか、札の背は何pt かを
/// 値に出す。札は1つの読み上げの要素（`.accessibilityElement(children: .combine)`）で、ボタンの中でもあるので、
/// 中に見えない要素を置いても UI テストの木に出ない。そこで札の中で測った値を `TopCardProbeKey` で上へ渡し、
/// 札の並びの外（`HomeTopCardView`）で1つの `LayoutProbe`（`home.topCard.probe`）に出す。
/// 字が切れたかは画面の木から取れないので、推定でなく数で見る（CLAUDE.md「推定で直さない」）
struct TopCardProbeKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

/// 札の小さい行の寸法を測る（`PreviewSession.layoutProbe` のときだけ。ふだんは何も足さない）
struct TopCardDetailProbe: ViewModifier {
    let title: String
    let detail: String

    @State private var avail: CGFloat = 0
    @State private var need: CGFloat = 0

    func body(content: Content) -> some View {
        if PreviewSession.layoutProbe {
            content
                // 渡された幅（切れていればこの幅に詰めて出ている）
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { avail = $0 }
                // 全文を1行に組んだときに要る幅
                .background(alignment: .leading) {
                    Text(detail)
                        .font(JPFont.caption)
                        .lineLimit(1)
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { need = $0 }
                }
                .preference(key: TopCardProbeKey.self,
                            value: [String(format: "detail title=%@ avail=%.1f need=%.1f cut=%@ text=%@",
                                           title, avail, need, need > avail + 0.5 ? "yes" : "no", detail)])
        } else {
            content
        }
    }
}

/// 札の背を測る（`PreviewSession.layoutProbe` のときだけ）
struct TopCardHeightProbe: ViewModifier {
    let title: String

    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        if PreviewSession.layoutProbe {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .transformPreference(TopCardProbeKey.self) { values in
                    values.append(String(format: "card title=%@ height=%.1f", title, height))
                }
        } else {
            content
        }
    }
}
