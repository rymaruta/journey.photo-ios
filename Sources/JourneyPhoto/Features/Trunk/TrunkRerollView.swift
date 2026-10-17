import SwiftUI

/// 図柄を作り直す（Pro・月3回・モック Reroll.dc.html・2026-10-17）。
///
/// 開いたら作り直しを1回使い（同じラベルの選びかけがあればそれを出す＝回数を使わない）、
/// サーバーが出した候補3つと「いまの」図柄から選ぶ。選んで「この図柄にする」で決まる。
/// **選ばずに閉じても候補は残る**（サーバーの `pendingReroll`）——次に開くと同じ候補が出る。
struct TrunkRerollView: View {
    @ObservedObject var model: TrunkViewModel
    let labelId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter
    /// 選んでいる種（nil は最初の候補）
    @State private var chosenSeed: Int?
    @State private var starting = true

    private var label: TrunkLabel? { model.state?.pocket.first { $0.id == labelId } }

    private var candidates: [Int] {
        guard let pending = model.state?.pendingReroll, pending.labelId == labelId else { return [] }
        return Array(pending.seeds.prefix(3))
    }

    var body: some View {
        ZStack(alignment: .top) {
            TrunkStyle.stageBackground(centerY: 0.40)
            VStack(spacing: 0) {
                header
                if let label {
                    content(label)
                } else {
                    Spacer()
                    EmptyState(message: L("ラベルが見つかりませんでした。", "That label wasn\u{2019}t found."))
                    Spacer()
                }
            }
        }
        .task {
            // 開いたら1回だけ作り直す（選びかけがあればそれを出す）
            guard starting else { return }
            await model.reroll(labelId)
            chosenSeed = candidates.first
            starting = false
        }
        .accessibilityIdentifier("trunk.reroll")
    }

    private var header: some View {
        ZStack {
            Text(L("図柄を作り直す", "Redo the design"))
                .font(.headline)
                .foregroundStyle(WebTheme.text)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text(Labels.Common.close)
                        .font(.body)
                        .foregroundStyle(WebTheme.text)
                        .padding(.horizontal, 10)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.reroll.close")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 56)
    }

    private func content(_ label: TrunkLabel) -> some View {
        let options = [label.seed] + candidates
        let seed = chosenSeed ?? candidates.first ?? label.seed
        return VStack(spacing: 0) {
            TrunkProTag(height: 22)
                .padding(.top, 10)
            Text(TrunkText.rerollLead)
                .font(.subheadline)
                .lineSpacing(5)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 10)
            ZStack {
                TrunkStyle.glow(width: 330, height: 240)
                let preview = label.withSeed(seed)
                TrunkLabelThumb(label: preview, maxWidth: 240, maxHeight: 168, rot: -3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(TrunkLabelDesign.accessibilityLabel(preview))
                    .accessibilityAddTraits(.isImage)
            }
            .frame(height: 250)
            .padding(.top, 12)
            if starting && candidates.isEmpty {
                ProgressView()
                    .tint(WebTheme.muted2)
                    .frame(height: 96)
                    .padding(.top, 16)
            } else if candidates.isEmpty {
                Text(model.actionError ?? TrunkText.refusal(code: "noRerollsLeft", fallback: ""))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
            } else {
                Text(L("候補から選ぶ", "Choose a design"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                HStack(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        candidate(label.withSeed(option), caption: index == 0 ? L("いまの", "Current") : L("案 \(index)", "Option \(index)"),
                                  checked: option == seed) { chosenSeed = option }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L("図柄の候補", "Design options"))
            }
            Spacer(minLength: 12)
            footer(label, seed: seed)
        }
    }

    private func candidate(_ label: TrunkLabel, caption: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                TrunkLabelThumb(label: label, maxWidth: 66, maxHeight: 62, rot: 0)
                    .padding(.top, 6)
                Spacer(minLength: 0)
                Text(caption)
                    .font(.system(size: 12, weight: checked ? .bold : .regular))
                    .foregroundStyle(checked ? WebTheme.accent : TrunkStyle.faint)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if checked { RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.accent, lineWidth: 2) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption == L("いまの", "Current") ? L("いまの図柄", "Current design") : caption)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityIdentifier("trunk.reroll.option")
    }

    private func footer(_ label: TrunkLabel, seed: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(L("今月の作り直し ", "Redos this month: "))
                Text(TrunkText.rerollsLeft(model.state?.rerollsLeft ?? 0))
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text)
                Text(L("（毎月 3 回 · 繰り越しなし）", " (3 a month · no carry-over)"))
            }
            .font(JPFont.footnote)
            .foregroundStyle(TrunkStyle.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Button {
                Task {
                    if await model.choose(label.id, seed: seed) {
                        toasts.show(L("図柄を決めました", "Design chosen"))
                        dismiss()
                    }
                }
            } label: {
                TrunkButtonFace(title: L("この図柄にする", "Use this design"))
            }
            .buttonStyle(.plain)
            .disabled(candidates.isEmpty || model.busy)
            .opacity(candidates.isEmpty ? 0.4 : 1)
            .accessibilityIdentifier("trunk.reroll.choose")
            if let error = model.actionError, !candidates.isEmpty {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
            }
            Text(TrunkText.rerollNote)
                .font(.caption)
                .lineSpacing(4)
                .foregroundStyle(TrunkStyle.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
}
