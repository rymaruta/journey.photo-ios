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

/// 写真の出典の行（`TopCardFace.creditLine`・2026-11-14）の寸法を測る（`PreviewSession.layoutProbe` のときだけ）。
///
/// 値は `credit title=… avail=<行の幅> needs=<形ごとの要る幅> tail=<「 / ライセンス」の要る幅> head=<頭＋…の要る幅>
/// form=<入った形の番号 1〜 か cut> headVisible=<yes|no> text=<全文>`。
/// 入る形の決め方は `ViewThatFits` と同じ（1行に組んだ幅が行の幅以下の最初の形）。どれも入らない（cut）ときは、
/// 作者に残る幅（行の幅 − ライセンスの分）に「頭＋…」が入るかを `headVisible` に出す
struct TopCardCreditProbe: ViewModifier {
    let title: String
    let credit: TopCardCredit

    @State private var avail: CGFloat = 0
    @State private var widths: [CGFloat] = []

    private var lines: [String] { credit.wholeLines + [credit.licenseTail, credit.head + "…"] }

    func body(content: Content) -> some View {
        if PreviewSession.layoutProbe {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { avail = $0 }
                .background(alignment: .leading) {
                    TopCardLineWidths(lines: lines) { widths = $0 }
                }
                .preference(key: TopCardProbeKey.self, value: [describe()])
        } else {
            content
        }
    }

    private func describe() -> String {
        let count = credit.wholeLines.count
        let needs = Array(widths.prefix(count))
        let tail = widths.count > count ? widths[count] : 0
        let head = widths.count > count + 1 ? widths[count + 1] : 0
        let form = needs.firstIndex { $0 <= avail + 0.5 }
        let headVisible = widths.count == lines.count && (form != nil || avail - tail + 0.5 >= head)
        return String(format: "credit title=%@ avail=%.1f needs=%@ tail=%.1f head=%.1f form=%@ headVisible=%@ text=%@",
                      title, avail, needs.map { String(format: "%.1f", $0) }.joined(separator: ","), tail, head,
                      form.map { String($0 + 1) } ?? "cut", headVisible ? "yes" : "no", credit.spoken)
    }
}

/// 字の1行ずつの幅を測って渡す（見えない・事実取りだけ）
private struct TopCardLineWidths: View {
    let lines: [String]
    let report: ([CGFloat]) -> Void

    @State private var widths: [Int: CGFloat] = [:]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(JPFont.caption)
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        widths[index] = width
                        if widths.count == lines.count {
                            report((0..<lines.count).map { widths[$0] ?? 0 })
                        }
                    }
            }
        }
        .hidden()
    }
}
