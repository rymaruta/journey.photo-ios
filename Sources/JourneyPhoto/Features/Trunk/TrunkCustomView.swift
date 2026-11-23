import SwiftUI

/// 好きなデザインで作る（札 #706・2026-11-23 owner 承認「推奨でお願い」・案「トランクのステッカー案」）。
///
/// 閉じる（左上）→ 眉ラベル → 明朝の見出し「好きなデザインで作る」→ 大きいラベル（後ろに真鍮の淡い光）→
/// 「字は投稿の土地と季節のまま」→ 形・色・絵のタブ（選んでいるタブは真鍮の字と下線・`TrunkKindTab`）→
/// 5列の札（**どの札も、そのラベルにその形・色・絵を当てた絵**で見せる。押す前に何が起きるか分かる）→
/// 主ボタン（届いた画面から: 「このデザインで貼る」・手持ちから: 「このデザインにする」）→ 副「おまかせで組み直す」。
///
/// - 開いたときは今の図柄にいちばん近い組（`TrunkLabelDesign.customStart`）。選ばずに主ボタンを押してもよい（既定で正しく動く）
/// - 字（地名）・傾き・刷りのずれ・箔は選ばせない（2026-11-23 owner）。箔押しのラベルは色のタブで一言だけ言う
/// - 閉じても回数は使わない（主ボタンを押したときだけサーバーへ）
/// - 画面では「カスタム」と言わない（`TrunkRerollCustomTests`）
///
/// 写真の無い画面なので、主ボタンは真鍮の塗り＋墨（CLAUDE.md「写真の無い画面の主ボタン」・`TrunkButtonFace.Kind.main`）
struct TrunkCustomView: View {
    @ObservedObject var model: TrunkViewModel
    let labelId: String
    /// 届いた画面から開いた（作ったら、そのまま貼る）
    var sticks: Bool = false
    /// 作り終えた（`sticks` のときは貼れたかどうか）。届いた画面が閉じるのに使う
    var onDone: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var toasts: ToastCenter

    enum Tab: CaseIterable { case shape, palette, art }

    @State private var tab: Tab = .shape
    @State private var picked: TrunkLabelCustom?
    /// 「おまかせで組み直す」を押した回数（組み直しの種を進める）
    @State private var shuffles = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    private var label: TrunkLabel? { model.state?.pocket.first { $0.id == labelId } }

    var body: some View {
        ZStack(alignment: .top) {
            TrunkStyle.stageBackground(centerY: 0.30)
            VStack(spacing: 0) {
                HStack {
                    SheetCloseButton(onContent: true)
                        .accessibilityIdentifier("trunk.custom.close")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 56)
                if let label {
                    content(label)
                } else {
                    Spacer()
                    EmptyState(icon: nil, message: L("ラベルが見つかりませんでした。", "That label wasn\u{2019}t found."))
                    Spacer()
                }
            }
        }
        .onAppear { if picked == nil, let label { picked = TrunkLabelDesign.customStart(for: label) } }
        .overlay(alignment: .top) { ToastOverlay() }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.custom")
    }

    private func content(_ label: TrunkLabel) -> some View {
        let choice = picked ?? TrunkLabelDesign.customStart(for: label)
        let preview = label.withCustom(choice)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text(TrunkText.customEyebrow)
                        .font(JPFont.eyebrow)
                        .tracking(11 * 0.12)
                        .foregroundStyle(WebTheme.accent)
                        .padding(.top, 4)
                    Text(TrunkText.customTitle)
                        .font(JPFont.display(22, relativeTo: .title2))
                        .foregroundStyle(WebTheme.text)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    ZStack {
                        TrunkStyle.glow(width: 330, height: 200)
                        TrunkLabelThumb(label: preview, maxWidth: 230, maxHeight: 150, rot: -3)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(TrunkLabelDesign.accessibilityLabel(preview))
                            .accessibilityAddTraits(.isImage)
                    }
                    .frame(height: 200)
                    .padding(.top, 8)
                    Text(TrunkText.customFixedNote)
                        .font(JPFont.footnote)
                        .foregroundStyle(TrunkStyle.faint)
                        .multilineTextAlignment(.center)
                    tabs
                        .padding(.top, 12)
                    grid(label, choice: choice)
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
            }
            actions(label, choice: choice)
        }
    }

    private func title(_ t: Tab) -> String {
        switch t {
        case .shape: return TrunkText.customShapeTab
        case .palette: return TrunkText.customPaletteTab
        case .art: return TrunkText.customArtTab
        }
    }

    private func count(_ t: Tab) -> Int {
        switch t {
        case .shape: return TrunkLabelDesign.customShapes.count
        case .palette: return TrunkLabelDesign.customPalettes.count
        case .art: return TrunkLabelDesign.customArts.count
        }
    }

    /// 形・色・絵のタブ（部品箱と同じ `TrunkKindTab`・選んでいるタブは真鍮の字と下線）
    private var tabs: some View {
        HStack(spacing: JPSpace.l) {
            ForEach(Tab.allCases, id: \.self) { t in
                TrunkKindTab(title: title(t), count: "\(count(t))", selected: tab == t) { tab = t }
                    .accessibilityIdentifier("trunk.custom.tab.\(t)")
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    /// 札の名前（読み上げ・番号ではなく名前で言う）
    private func name(_ index: Int) -> String {
        switch tab {
        case .shape: return TrunkText.shapeName(TrunkLabelDesign.customShapes[index])
        case .palette: return TrunkText.paletteName(index)
        case .art: return TrunkText.artName(TrunkLabelDesign.customArts[index])
        }
    }

    /// 選んだ形・色・絵を当てた組
    private func applying(_ index: Int, to c: TrunkLabelCustom) -> TrunkLabelCustom {
        switch tab {
        case .shape: return TrunkLabelCustom(shape: index, palette: c.palette, art: c.art)
        case .palette: return TrunkLabelCustom(shape: c.shape, palette: index, art: c.art)
        case .art: return TrunkLabelCustom(shape: c.shape, palette: c.palette, art: index)
        }
    }

    private func isPicked(_ index: Int, _ c: TrunkLabelCustom) -> Bool {
        switch tab {
        case .shape: return c.shape == index
        case .palette: return c.palette == index
        case .art: return c.art == index
        }
    }

    @ViewBuilder
    private func grid(_ label: TrunkLabel, choice: TrunkLabelCustom) -> some View {
        if tab == .palette && TrunkLabelDesign.spec(for: label).foil {
            // 箔押しは色が箔のまま（選ばせても絵が変わらない札を並べない）
            Text(TrunkText.customFoilNote)
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityIdentifier("trunk.custom.foil")
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<count(tab), id: \.self) { index in
                    option(label, index: index, choice: choice)
                }
            }
        }
    }

    private func option(_ label: TrunkLabel, index: Int, choice: TrunkLabelCustom) -> some View {
        let on = isPicked(index, choice)
        let sample = label.withCustom(applying(index, to: choice))
        return Button {
            picked = applying(index, to: choice)
        } label: {
            TrunkLabelThumb(label: sample, maxWidth: 52, maxHeight: 40, rot: 0)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .trunkCard(radius: 10)
                .overlay {
                    if on { RoundedRectangle(cornerRadius: 10).strokeBorder(WebTheme.accent, lineWidth: 2) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TrunkText.customOptionAccessibility(tab: title(tab), name: name(index)))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("trunk.custom.option")
    }

    private func actions(_ label: TrunkLabel, choice: TrunkLabelCustom) -> some View {
        VStack(spacing: 8) {
            if let error = model.actionError {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("trunk.custom.error")
            }
            Button { Task { await finish(label, choice: choice) } } label: {
                TrunkButtonFace(title: TrunkText.customDoneTitle(sticks: sticks), kind: .main)
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
            .accessibilityIdentifier("trunk.custom.done")
            Button {
                shuffles += 1
                picked = TrunkLabelDesign.customShuffle(seed: label.seed &+ shuffles)
            } label: {
                TrunkButtonFace(title: TrunkText.customShuffleTitle, kind: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.custom.shuffle")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// 作る（届いた画面からは、そのまま貼る）。失敗したら閉じずに一言（`actionError`）
    private func finish(_ label: TrunkLabel, choice: TrunkLabelCustom) async {
        guard await model.makeCustom(label.id, choice) else { return }
        if sticks {
            let stuck = await model.stick(label.id)
            onDone?(stuck)
            dismiss()
            return
        }
        toasts.show(TrunkText.customMade)
        onDone?(true)
        dismiss()
    }
}
