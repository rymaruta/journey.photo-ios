import SwiftUI

// 作り直しの候補の列とボタン（札 #706・2026-11-23 owner 承認）。**届いた画面と手持ちの画面で同じ部品を使う**
// （画面ごとに見た目を割らない）。目印は `idPrefix`（`trunk.arrived` / `trunk.pocket`）＋ `.candidate` などで付ける。
//
// - 候補の列: 最初の1枚と、作り直した1回目〜3回目の4つの枠。空いた枠は「あと何回作れるか」を形で見せる。
//   押すとその場でサーバーへ（`reroll/choose`）。列の下に一行（作る前は「作り直すと、ここに候補が並びます」、
//   作ったあとは「押すと、前の図柄に戻せます」）
// - ボタン: 「作り直す　あと N 回」（真鍮の線・44）。使い切った・圏外は一言に替える。届かなかったら「もう一度作り直す」と
//   「作り直せませんでした。回数は減っていません」（断りなら断りの言葉・`TrunkViewModel.actionError`）

/// 候補の列
struct TrunkCandidatesRow: View {
    @ObservedObject var model: TrunkViewModel
    let label: TrunkLabel
    /// 作り直しを頼んでいる最中（次の枠に回る印を出す）
    let rolling: Bool
    let idPrefix: String

    var body: some View {
        if TrunkText.redoStep(model.state, label: label) != .hidden {
            let choices = label.choices
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach(0...TrunkLabel.rerollMax, id: \.self) { index in
                        if index < choices.count {
                            candidate(choices[index], index: index)
                        } else {
                            emptySlot(index, spinning: rolling && index == choices.count)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L("図柄の候補", "Design options"))
                Text(TrunkText.candidatesHint(rerolls: label.rerolls))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.faint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 26)
                    .accessibilityIdentifier("\(idPrefix).candidatesHint")
            }
        }
    }

    private func candidate(_ seed: Int, index: Int) -> some View {
        let on = seed == label.seed
        return Button {
            Task { await model.choose(label.id, seed: seed) }
        } label: {
            TrunkLabelThumb(label: label.withSeed(seed), maxWidth: 58, maxHeight: 44, rot: 0)
                .frame(width: 72, height: 60)
                .trunkCard(radius: 10)
                .overlay {
                    if on { RoundedRectangle(cornerRadius: 10).strokeBorder(WebTheme.accent, lineWidth: 2) }
                }
                .overlay(alignment: .bottom) {
                    Text(TrunkText.candidateCaption(index))
                        .font(JPFont.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? WebTheme.accent : TrunkStyle.faint)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: 18)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .accessibilityLabel(TrunkText.candidateAccessibility(index))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("\(idPrefix).candidate")
    }

    private func emptySlot(_ index: Int, spinning: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(WebTheme.hairline, lineWidth: 1)
            .frame(width: 72, height: 60)
            .overlay {
                if spinning {
                    ProgressView().tint(WebTheme.accent)
                } else {
                    Text("\(index)")
                        .font(JPFont.number(12, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(TrunkStyle.faint)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrunkText.candidateEmptyAccessibility(index))
    }
}

/// 作り直すボタン（使い切った・圏外・届かなかったの一言を含む）
struct TrunkRedoButton: View {
    @ObservedObject var model: TrunkViewModel
    let label: TrunkLabel
    let offline: Bool
    @Binding var rolling: Bool
    @Binding var failed: Bool
    let idPrefix: String

    var body: some View {
        switch TrunkText.redoStep(model.state, label: label) {
        case .hidden:
            EmptyView()
        case .usedUp:
            Text(TrunkText.redoUsedUp)
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.faint)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("\(idPrefix).redoUsedUp")
        case .ready(let left):
            VStack(spacing: 8) {
                if offline {
                    Text(TrunkText.redoOffline)
                        .font(JPFont.footnote)
                        .foregroundStyle(TrunkStyle.faint)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("\(idPrefix).redoOffline")
                } else if failed, !model.lastWriteRefused {
                    // 届かなかった（断りではない）: 同じ回を送り直すので、回数は減らない
                    Text(TrunkText.redoFailed)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("\(idPrefix).redoFailed")
                }
                Button { Task { await redo() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "dice")
                            .font(.callout)
                            .accessibilityHidden(true)
                        Text(TrunkText.redoTitle(left: left, again: failed))
                    }
                    .jpCapsuleFace(font: .subheadline.weight(.semibold), text: WebTheme.accent, fill: Color.clear,
                                   border: WebTheme.accent.opacity(0.55), fullWidth: true,
                                   minHeight: JPHeight.secondaryButton, textInset: nil)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.busy || rolling || offline)
                .opacity(offline ? 0.4 : 1)
                .accessibilityLabel(TrunkText.redoAccessibility(left: left))
                .accessibilityIdentifier("\(idPrefix).reroll")
            }
        }
    }

    /// 作り直す（何回目かを添えてサーバーへ）。届かなければボタンを「もう一度作り直す」にする
    private func redo() async {
        rolling = true
        failed = false
        let done = await model.reroll(label.id)
        rolling = false
        failed = !done
    }
}
