import SwiftUI

/// プロフィール（マイページ・人のページ）の札の行「絵と字」（`ProfileTabBar` の `iconColumns`）。
///
/// **2026-11-13 owner 承認（#187・Artifact「マイページのタブの案」の案 B「絵と字」）。**
/// - 幅を札の数で**等しく割る**（自分のページは4つ・人のページは2つ）。印 20 の下に名前 12、間 3、高さ 56
/// - 選んだ札は真鍮の塗りの印と真鍮の字 600、ほかは text-3 の線の印と字 500（札を置く地は黒——真鍮は黒地の上だけ）
/// - 真鍮の線 2pt・角丸 1・長さは列の幅から左右 8 を引いた長さ・札の下端。下に白 8% の線（今と同じ）
/// - **払っている間、線が指に付いてくる**（中身の横の量 `ProfileTabDrag` を見て、隣の列へ寄せる・`underlineRect`）。
///   離すと選び替えと一緒にばねで収まる。「視差効果を減らす」では指に付けず、置くだけ
/// - 名前が1行に入らなければ決めた所で2行に折る（「行きたい／場所」・`PagedTab.tabTitleWrapped`）。
///   2行でも列に入らない（とても大きい字）ときは、列を名前の幅にして横に送る並び（字は縮めない・切らない）
///
/// 2026-11-13 判断: 印は列の上端からそろえる（資料の模型は上下の真ん中寄せで、1つの札だけ2行に折れると印の高さが
/// 列ごとにずれる）。標準の字では資料と同じ位置（上 8）になる
struct ProfileTabColumnRow<Tab: PagedTab>: View {

    let tabs: [Tab]
    @Binding var selection: Tab
    /// 中身の横の量（払っている間に線を寄せる）
    @ObservedObject var drag: ProfileTabDrag
    let movesContent: Bool
    let spoken: (Tab) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 行の幅（横に送る並びの列の最小の幅・線を寄せる割合の分母の控え）
    @State private var rowWidth: CGFloat = 0

    private var selectedIndex: Int { tabs.firstIndex(of: selection) ?? 0 }

    /// 払いの進み具合（-1〜1）。「視差効果を減らす」では 0（線は指に付けない）
    private var progress: CGFloat {
        guard !reduceMotion else { return 0 }
        return ProfileTabColumnStyle.progress(offset: drag.offset, pageWidth: drag.width > 0 ? drag.width : rowWidth)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(scrolls: false)
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    row(scrolls: true)
                        // UI テストの記録（Debug・`-JPPreviewTabSwipeProbe` のときだけ値を控える）: 横の送りの位置
                        // （contentOffset.x ＝ 並びの左端が送りの枠からどれだけ左へ出たか）
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .scrollView).minX
                        } action: { minX in
                            ProfileTabSwipeLog.shared.horizontal(Double(-minX))
                        }
                }
                .onChange(of: selection) { _, next in
                    withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                        reader.scrollTo(next.tabIdentifier, anchor: .center)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { rowWidth = $0 }
    }

    private func row(scrolls: Bool) -> some View {
        ProfileTabColumnsLayout(selected: selectedIndex, progress: progress,
                                minimumColumn: scrolls ? rowWidth / CGFloat(max(tabs.count, 1)) : nil) {
            ForEach(tabs, id: \.self) { option in
                cell(option, scrolls: scrolls).id(option.tabIdentifier)
            }
            RoundedRectangle(cornerRadius: ProfileTabStyle.underlineRadius)
                .fill(WebTheme.accent)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func cell(_ option: Tab, scrolls: Bool) -> some View {
        let selected = selection == option
        return Button {
            if movesContent {
                withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                    selection = option
                }
            } else {
                selection = option
            }
        } label: {
            VStack(spacing: ProfileTabColumnStyle.iconLabelSpacing) {
                Image(systemName: ProfileTabColumnStyle.symbol(option.tabSymbol ?? "circle", selected: selected))
                    .font(.system(size: ProfileTabColumnStyle.iconSize))
                    .frame(width: ProfileTabColumnStyle.iconBox, height: ProfileTabColumnStyle.iconBox)
                    .accessibilityHidden(true)
                // 1行に入れば1行、入らなければ決めた所で2行（どちらも縮めない・切らない）。横に送る並びは1行
                ViewThatFits(in: .horizontal) {
                    label(option.tabTitle, selected: selected)
                    if !scrolls, let wrapped = option.tabTitleWrapped {
                        label(wrapped, selected: selected)
                    }
                }
            }
            .padding(.top, ProfileTabColumnStyle.topPadding)
            .padding(.bottom, ProfileTabColumnStyle.bottomPadding)
            .padding(.horizontal, scrolls ? ProfileTabColumnStyle.scrollPadding : ProfileTabColumnStyle.labelPadding)
            .frame(maxWidth: .infinity, minHeight: ProfileTabColumnStyle.height, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        // 字と印の色（選んだ・押している）は今の札と同じ部品で 0.15 秒（押している間は白 95%）
        .buttonStyle(ProfileTabPressStyle(selected: selected))
        .accessibilityLabel(spoken(option))
        .accessibilityValue(ProfileTabStyle.position(of: option, in: tabs) ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**・識別子は今の札と同じ
        .accessibilityIdentifier(option.tabIdentifier)
    }

    /// 名前。**幅は太字で測る**（選ぶたびに折り方が変わらないように）。大きさの変わる字（`.caption` ＝ 12 から伸びる）
    private func label(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(ProfileTabColumnStyle.font(selected: true))
            .multilineTextAlignment(.center)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                Text(text)
                    .font(ProfileTabColumnStyle.font(selected: selected))
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
    }
}

/// 札を等しい幅の列に並べ、最後の子（真鍮の線）を選んだ列の下端に置く。
///
/// - 等しく割る並び（`minimumColumn` が nil）: 理想の幅は「いちばん広い札（2行に折った幅）× 札の数」。
///   `ViewThatFits` はこれが入るときだけこの並びを選ぶ（入らなければ横に送る並び）
/// - 横に送る並び: 札ごとに名前の幅（最小は行の幅の等分）
struct ProfileTabColumnsLayout: Layout {

    let selected: Int
    let progress: CGFloat
    var minimumColumn: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cells = subviews.dropLast()
        guard !cells.isEmpty else { return .zero }
        let widths = columnWidths(cells: cells, available: proposal.width.map { CGFloat($0) })
        let height = zip(cells, widths).map { cell, width in
            cell.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }.max() ?? 0
        return CGSize(width: widths.reduce(0, +), height: max(height, ProfileTabColumnStyle.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cells = subviews.dropLast()
        guard !cells.isEmpty, let underline = subviews.last else { return }
        let widths = columnWidths(cells: cells, available: bounds.width)
        var rects: [CGRect] = []
        var x = bounds.minX
        for (cell, width) in zip(cells, widths) {
            let rect = CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
            cell.place(at: rect.origin, proposal: ProposedViewSize(width: rect.width, height: rect.height))
            rects.append(rect)
            x += width
        }
        let line = ProfileTabColumnStyle.underlineRect(columns: rects, selected: selected, progress: progress)
        underline.place(at: line.origin, proposal: ProposedViewSize(width: line.width, height: line.height))
    }

    /// 列の幅。等しく割る並びは `ProfileTabColumnStyle.columnWidths`、横に送る並びは札ごとの理想の幅（最小は等分）
    private func columnWidths(cells: LayoutSubviews.SubSequence, available: CGFloat?) -> [CGFloat] {
        if let minimumColumn {
            return cells.map { max(minimumColumn, $0.sizeThatFits(.unspecified).width) }
        }
        // 札がいちばん狭くなれる幅（2行に折った名前・印の大きい方＋左右）。幅 0 を渡すと `ViewThatFits` は最後の形を返す
        let narrowest = cells.map { $0.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width }
        return ProfileTabColumnStyle.columnWidths(count: cells.count, available: available,
                                                  narrowest: narrowest.max() ?? 0)
    }
}

/// 案 B「絵と字」の値と計算（2026-11-13 owner 承認 #187）。Linux のテストで見張るため `nonisolated static` で持つ
/// （`ProfileTabColumnTests`）
enum ProfileTabColumnStyle {
    /// 札の行の高さ（当たりも 56）。今の字の札（48）から 8 高い
    nonisolated static let height: CGFloat = 56
    /// 印の大きさ（字の大きさ）と、印を置く枠
    nonisolated static let iconSize: CGFloat = 20
    nonisolated static let iconBox: CGFloat = 22
    /// 印と名前の間
    nonisolated static let iconLabelSpacing: CGFloat = 3
    /// 列の中の上下の余白（上は資料の真ん中寄せの位置 8・下 8）
    nonisolated static let topPadding: CGFloat = 8
    nonisolated static let bottomPadding: CGFloat = 8
    /// 名前の左右の余白（等しく割る並び）と、横に送る並びの札の左右
    nonisolated static let labelPadding: CGFloat = 2
    nonisolated static let scrollPadding: CGFloat = 12
    /// 線を列の幅から左右それぞれ引く量
    nonisolated static let underlineInset: CGFloat = 8

    /// 列の幅。**等しく割る**。幅が分からない（理想の幅を聞かれた）ときは「いちばん狭くなれる札 × 数」
    nonisolated static func columnWidths(count: Int, available: CGFloat?, narrowest: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let column = available.map { $0 / CGFloat(count) } ?? narrowest
        return Array(repeating: column, count: count)
    }

    /// 払いの進み具合（-1〜1）。指を左へ払う（中身が左へずれる・offset < 0）と右隣へ向かう（正）
    nonisolated static func progress(offset: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return 0 }
        return max(-1, min(1, -offset / pageWidth))
    }

    /// 真鍮の線の置き場。選んだ列から、進み具合の分だけ隣の列へ寄せる（位置も長さも）。隣が無い向きは選んだ列のまま
    nonisolated static func underlineRect(columns: [CGRect], selected: Int, progress: CGFloat) -> CGRect {
        guard columns.indices.contains(selected) else { return .zero }
        func line(_ column: CGRect) -> CGRect {
            CGRect(x: column.minX + underlineInset, y: column.maxY - JPStroke.emphasis,
                   width: max(0, column.width - underlineInset * 2), height: JPStroke.emphasis)
        }
        let from = line(columns[selected])
        let step = progress > 0 ? 1 : (progress < 0 ? -1 : 0)
        guard step != 0, columns.indices.contains(selected + step) else { return from }
        let to = line(columns[selected + step])
        let t = min(1, abs(progress))
        return CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY,
                      width: from.width + (to.width - from.width) * t, height: from.height)
    }

    /// 印の名前。選んだ札は塗りの印（`.fill`）、ほかは線の印
    nonisolated static func symbol(_ name: String, selected: Bool) -> String {
        selected ? name + ".fill" : name
    }

    /// 名前の字（選んだ 600＝semibold・ほか 500＝medium。どちらも 12＝caption から伸びる）
    static func font(selected: Bool) -> Font {
        JPFont.caption.weight(selected ? .semibold : .medium)
    }
}
