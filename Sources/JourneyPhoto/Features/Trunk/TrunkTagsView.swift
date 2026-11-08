import SwiftUI

/// 手荷物タグを自分で選ぶ画面（2026-11-08 owner 承認・札 #501・デザイナーのモック案A「貼ったラベルから、タグごとに選ぶ」）。
///
/// トランクの画面の行「手荷物タグ n / m 枚」から入る。上に「いまのタグ」、下に枠ごとの行。行を押すと、
/// 貼ったラベルから1つ選ぶシート（`TrunkTagPickerSheet`）が開く。絵の中のタグは約 42pt で押す大きさに足りないので、
/// 絵は押せるようにせず、行から入る。何を出すか・どの行を押せるかは `TrunkTagText`、並べ方は `TrunkLooks.tagSlotResults`。
/// 状態は 読み込み中・失敗・圏外・空（ラベルなし）・同じ地名・地名なし（板 v2 の4つの状態＋モックの6状態）。
struct TrunkTagsView: View {
    @ObservedObject var model: TrunkViewModel
    /// 「ラベルを貼る」を開く（トランクの画面の貼る画面）
    var onStick: () -> Void = {}

    @EnvironmentObject private var connectivity: Connectivity
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sheet: SlotRef?

    /// シートを開く枠（0 始まり）
    struct SlotRef: Identifiable, Equatable {
        let id: Int
    }

    var body: some View {
        content
            .webScreen()
            .navigationTitle(TrunkTagText.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $sheet) { ref in
                TrunkTagPickerSheet(model: model, slot: ref.id, onStick: {
                    sheet = nil
                    onStick()
                })
            }
    }

    @ViewBuilder
    private var content: some View {
        if let state = model.state {
            loaded(state)
        } else {
            switch model.phase {
            case .failed(let message):
                ErrorBanner(title: L("トランクを開けませんでした", "Couldn\u{2019}t open your trunk"), message: message,
                            retry: { Task { await model.load(offline: connectivity.isOffline) } })
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("trunk.tags.failed")
            case .offline:
                ErrorBanner(title: TrunkTagText.offlineTitle, message: TrunkTagText.offlineMessage,
                            retry: { Task { await model.load(offline: connectivity.isOffline) } })
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("trunk.tags.offline")
            case .loading, .loaded:
                VStack(spacing: 8) {
                    JPLoadingState(kind: .rows).padding(.horizontal, 20)
                    Text(TrunkTagText.loadingNote)
                        .font(JPFont.footnote)
                        .foregroundStyle(TrunkStyle.faint)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                .padding(.top, 24)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("trunk.tags.loading")
            }
        }
    }

    private func loaded(_ state: TrunkState) -> some View {
        let posts = state.posts ?? 0
        let results = TrunkLooks.tagSlotResults(stuck: state.stuck, posts: posts, picks: state.tagPicks)
        let stage = TrunkAging.stage(posts: posts)
        return ScrollView {
            VStack(spacing: 0) {
                if connectivity.isOffline {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TrunkTagText.offlineTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                        Text(TrunkTagText.offlineMessage)
                            .font(JPFont.footnote)
                            .foregroundStyle(TrunkStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("trunk.tags.offlineNote")
                }
                if let error = model.actionError {
                    failureLine(error)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                Text(TrunkTagText.intro)
                    .font(.subheadline)
                    .foregroundStyle(TrunkStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                Text(TrunkTagText.nowEyebrow)
                    .font(JPFont.eyebrow)
                    .tracking(11 * 0.12)
                    .foregroundStyle(WebTheme.accent)
                    .padding(.bottom, 10)
                nowTags(results, stage: stage)
                    .padding(.bottom, 16)
                slotRows(state, results: results, posts: posts, stage: stage)
                Text(TrunkTagText.footer)
                    .font(.caption)
                    .foregroundStyle(TrunkStyle.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.tags.screen")
    }

    /// 失敗の一言（危険の色・丸に！の印・起きた所のすぐ上に出す・板 06）
    private func failureLine(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(JPFont.footnote)
        .foregroundStyle(WebTheme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trunk.tags.error")
    }

    /// いまのタグ（3つの枠を並べる。空き・吊るせない枠は点線）
    private func nowTags(_ results: [TrunkLooks.TagSlotResult], stage: Double) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                if let tag = result.tag {
                    TrunkTagView(tag: tag, stage: stage)
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: TrunkLooks.tagWidth, height: TrunkLooks.tagHeight)
                        .overlay {
                            Text(TrunkTagText.emptySlot)
                                .font(.caption)
                                .foregroundStyle(TrunkStyle.faint)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nowAccessibility(results))
    }

    private func nowAccessibility(_ results: [TrunkLooks.TagSlotResult]) -> String {
        let names = results.compactMap { r -> String? in
            let name = TrunkTagText.placeName(r.label)
            return r.tag == nil || name.isEmpty ? nil : name
        }
        return names.isEmpty ? TrunkTagText.nowEyebrow : "\(TrunkTagText.nowEyebrow): \(names.joined(separator: "、"))"
    }

    private func slotRows(_ state: TrunkState, results: [TrunkLooks.TagSlotResult], posts: Int, stage: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.offset) { i, result in
                if i > 0 { TrunkStyle.line.frame(height: 1) }
                slotRow(i, result, posts: posts, stage: stage)
            }
        }
        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func slotRow(_ slot: Int, _ result: TrunkLooks.TagSlotResult, posts: Int, stage: Double) -> some View {
        if TrunkTagText.isOpen(result) {
            Button { sheet = SlotRef(id: slot) } label: {
                slotRowFace(slot, result, posts: posts, stage: stage, chevron: true)
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TrunkTagText.slotTitle(slot, result))、\(TrunkTagText.slotNote(slot, result, posts: posts))")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("trunk.tags.slot.\(slot)")
        } else {
            // まだ吊るせない枠: 押せない。鍵の絵ではなく文字で（板: 3枚目は鍵ではなく文字で示す）
            slotRowFace(slot, result, posts: posts, stage: stage, chevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(TrunkTagText.slotTitle(slot, result))、\(TrunkTagText.slotNote(slot, result, posts: posts))")
                .accessibilityIdentifier("trunk.tags.slot.\(slot)")
        }
    }

    private func slotRowFace(_ slot: Int, _ result: TrunkLooks.TagSlotResult, posts: Int, stage: Double, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let tag = result.tag {
                    TrunkTagView(tag: tag, stage: stage)
                        .scaleEffect(0.8)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: TrunkLooks.tagWidth * 0.8, height: TrunkLooks.tagHeight * 0.8)
                }
            }
            .frame(width: 56, height: TrunkLooks.tagHeight * 0.8 + 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(TrunkTagText.slotTitle(slot, result))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(TrunkTagText.slotNote(slot, result, posts: posts))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(TrunkStyle.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 88)
        .contentShape(Rectangle())
    }
}

/// 載せるラベルを選ぶシート（モックの「3. 載せるラベルを選ぶ」と状態）。
///
/// 行を押す＝選ぶ（まだ保存しない）。「完了」で保存して閉じる。「おまかせに戻す」「タグを外す」は押したらすぐ保存する。
/// 保存できなかったら選んだ内容を残したまま、起きた所の上に失敗を出し、「もう一度」と「保存せずに閉じる」を出す
/// （圏外のときも同じ。電波が戻れば「もう一度」で保存できる）。
struct TrunkTagPickerSheet: View {
    @ObservedObject var model: TrunkViewModel
    /// 0 始まりの枠
    let slot: Int
    var onStick: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: TrunkTagPick?
    /// 保存できなかった選び（「もう一度」で送り直す）
    @State private var failed: TrunkTagPick?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sheetTitle)
                .font(JPFont.display(19, relativeTo: .headline))
                .foregroundStyle(WebTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            if let state = model.state {
                sheetBody(state)
            } else {
                loading
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(WebTheme.sheet)
        .presentationCornerRadius(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.tags.sheet")
    }

    private var sheetTitle: String { L("\(slot + 1)枚目に載せるラベル", "Label for tag \(slot + 1)") }

    private var loading: some View {
        VStack(spacing: 8) {
            JPLoadingState(kind: .rows).padding(.horizontal, 20)
            Text(TrunkTagText.loadingNote)
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.faint)
        }
        .padding(.top, 16)
        .accessibilityIdentifier("trunk.tags.sheet.loading")
    }

    @ViewBuilder
    private func sheetBody(_ state: TrunkState) -> some View {
        let candidates = TrunkTagText.candidates(stuck: state.stuck, posts: state.posts ?? 0, picks: state.tagPicks, slot: slot)
        if !candidates.contains(where: { $0.availability != .noPlace }) {
            emptyBody
        } else {
            Text(TrunkTagText.sheetNote)
                .font(.caption)
                .foregroundStyle(TrunkStyle.muted)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        row(candidate, selected: isSelected(candidate))
                        TrunkStyle.line.frame(height: 1).padding(.leading, 20)
                    }
                    if candidates.contains(where: { if case .usedInSlot = $0.availability { return true } else { return false } }) {
                        Text(TrunkTagText.sameNameNote)
                            .font(.caption)
                            .foregroundStyle(TrunkStyle.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                    }
                }
            }
            footer(state)
        }
    }

    /// 選んでいる印: 触ったあとは触った行、触る前はいま載っている行
    private func isSelected(_ candidate: TrunkTagText.Candidate) -> Bool {
        if let draft {
            if case .label(let id) = draft { return id == candidate.id }
            return false
        }
        return candidate.availability == .current
    }

    private func row(_ candidate: TrunkTagText.Candidate, selected: Bool) -> some View {
        Button {
            failed = nil
            model.actionError = nil
            draft = .label(candidate.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? WebTheme.accent : Color.white.opacity(0.3), lineWidth: 2)
                        .background(Circle().fill(selected ? WebTheme.accent : Color.clear))
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(WebTheme.accentText)
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                TrunkLabelThumb(label: candidate.label, maxWidth: 52, maxHeight: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TrunkTagText.candidateTitle(candidate))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    Text(TrunkTagText.candidateNote(candidate, selected: selected))
                        .font(JPFont.footnote)
                        .foregroundStyle(TrunkStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .opacity(candidate.isEnabled ? 1 : 0.75)
            .contentShape(Rectangle())
        }
        .buttonStyle(JPRowButtonStyle())
        .disabled(!candidate.isEnabled || model.busy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrunkTagText.candidateAccessibility(candidate, selected: selected))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("trunk.tags.pick.\(candidate.id)")
    }

    /// 足元: 失敗（あれば）・おまかせに戻す／タグを外す・完了
    private func footer(_ state: TrunkState) -> some View {
        VStack(spacing: 10) {
            if let failedPick = failed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TrunkTagText.saveFailedTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(TrunkTagText.failureMessage(model.actionError))
                                .font(JPFont.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(WebTheme.danger)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("trunk.tags.sheet.error")
                    Button { commit(failedPick) } label: {
                        TrunkButtonFace(title: TrunkTagText.retry, kind: .main, height: 50, size: 15)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    .accessibilityIdentifier("trunk.tags.retry")
                    Button { dismiss() } label: {
                        TrunkButtonFace(title: TrunkTagText.closeWithoutSaving, kind: .secondary, height: 44, size: 15)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trunk.tags.discard")
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { quickButtons(state) }
                    VStack(spacing: 10) { quickButtons(state) }
                }
                Button { finish(state) } label: {
                    TrunkButtonFace(title: TrunkTagText.done, kind: .main, height: 50, size: 15)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .accessibilityIdentifier("trunk.tags.done")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func quickButtons(_ state: TrunkState) -> some View {
        Button { commit(.auto) } label: {
            TrunkButtonFace(title: TrunkTagText.backToAuto, kind: .secondary, height: 44, size: 14)
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .accessibilityIdentifier("trunk.tags.auto")
        Button { commit(.removed) } label: {
            TrunkButtonFace(title: TrunkTagText.removeTag, kind: .secondary, height: 44, size: 14)
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .accessibilityIdentifier("trunk.tags.remove")
    }

    /// 貼ったラベルがまだ無い（地名のあるラベルが1枚も無い）
    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            EmptyState(title: TrunkTagText.emptyTitle, message: TrunkTagText.emptyMessage)
            Button { onStick() } label: {
                TrunkButtonFace(title: TrunkTagText.stickAction, kind: .main, height: 50, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.tags.stick")
            Button { dismiss() } label: {
                TrunkButtonFace(title: TrunkTagText.close, kind: .secondary, height: 44, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.tags.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.tags.sheet.empty")
    }

    /// 「完了」: 選んでいなければそのまま閉じる。選んでいれば保存する
    private func finish(_ state: TrunkState) {
        guard let draft else { dismiss(); return }
        commit(draft)
    }

    /// 保存する。成功したら閉じる。失敗したら選びを残して「もう一度」を出す
    private func commit(_ pick: TrunkTagPick) {
        guard let state = model.state else { return }
        failed = nil
        guard !model.busy else { return }
        let picks = TrunkTagText.picks(replacing: slot, with: pick, in: state.tagPicks, stuck: state.stuck)
        Task {
            if await model.setTagPicks(picks) {
                dismiss()
            } else if model.actionError != nil {
                // 通信・断りで失敗したときだけ「保存できませんでした」を出す（書き込み中・未対応の false は出さない）
                failed = pick
            }
        }
    }
}
