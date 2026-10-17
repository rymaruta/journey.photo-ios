import SwiftUI

/// 手持ちのラベル（モック Pocket.dc.html・上限つき・2026-10-17）。
///
/// 上の札: まだ貼っていないラベルの数と上限の棒・いっぱいの間の説明・Pro の案内。
/// 格子は3列（#121212 の札 104・選んでいる札は真鍮の 2pt の縁と右上のチェック）。
/// 下の帯: 選んでいるラベル → 貼る（真鍮の塗り）・作り直す（PRO）・削除（危険の字）。
/// **「捨てる」とは言わない**（削除）。削除は確認してから（戻せない）。
struct TrunkPocketView: View {
    @ObservedObject var model: TrunkViewModel

    @EnvironmentObject private var toasts: ToastCenter
    @State private var selectedId: String?
    @State private var confirmDelete = false
    @State private var rerollTarget: TrunkLabel?
    @State private var showPaywall = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        Group {
            if let state = model.state {
                content(state)
            } else {
                JPLoadingState(kind: .rows)
            }
        }
        .webScreen()
        .navigationTitle(L("手持ちのラベル", "Label pocket"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("このラベルを削除しますか？", "Delete this label?"), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button(Labels.Common.delete, role: .destructive) { Task { await deleteSelected() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("削除したラベルは戻せません。同じ写真のラベルは、もう一度は届きません。",
                   "A deleted label can\u{2019}t be restored, and the same photo won\u{2019}t bring it again."))
        }
        .fullScreenCover(item: $rerollTarget) { label in
            TrunkRerollView(model: model, labelId: label.id)
        }
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            // 買えたかもしれない: 上限（150 枚）と作り直しを読み直す
            Task { await model.refreshAfterPaywall() }
        }) { PaywallView() }
        // 知らせは `RootView` の全体の知らせで出る（押して進む画面なので重ねない・2026-10-17 の読み直し）
    }

    private func content(_ state: TrunkState) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(state)
                if let error = model.actionError {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if state.pocket.isEmpty {
                    EmptyState(title: L("手持ちのラベルはありません", "Your pocket is empty"),
                               message: L("写真を投稿すると、お礼のラベルがここに届きます。",
                                          "Post a photo and a thank-you label will arrive here."))
                        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("trunk.pocket.empty")
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(state.pocket) { label in cell(label) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // 下の帯の高さぶん空ける
            .padding(.bottom, state.pocket.isEmpty ? 24 : 150)
        }
        .overlay(alignment: .bottom) {
            if !state.pocket.isEmpty { actionBar(state) }
        }
    }

    /// 上の札（数・棒・説明・Pro の案内）
    private func header(_ state: TrunkState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("まだ貼っていないラベル", "Not stuck yet"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(state.pocket.count))
                        .font(JPFont.number(22, weight: .semibold, relativeTo: .title2))
                        .foregroundStyle(WebTheme.text)
                    Text(L(" / \(state.limit) 枚", " / \(state.limit)"))
                        .font(JPFont.mono(15, relativeTo: .subheadline))
                        .foregroundStyle(TrunkStyle.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(state.limit) 枚のうち \(state.pocket.count) 枚",
                                      "\(state.pocket.count) of \(state.limit)"))
            }
            TrunkPocketBar(count: state.pocket.count, limit: state.limit)
                .padding(.top, 10)
            Text(TrunkText.pocketNote)
                .font(JPFont.footnote)
                .lineSpacing(4)
                .foregroundStyle(TrunkStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if !state.isPro {
                Button { showPaywall = true } label: {
                    HStack(spacing: 8) {
                        TrunkProTag()
                        Text(TrunkText.proPocketLink)
                            .font(.subheadline)
                            .underline()
                            .foregroundStyle(WebTheme.accent)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("trunk.pocket.pro")
            }
        }
        .padding(16)
        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 16))
    }

    private func cell(_ label: TrunkLabel) -> some View {
        let selected = selectedId == label.id
        return Button {
            selectedId = selected ? nil : label.id
        } label: {
            TrunkLabelThumb(label: label, maxWidth: 92, maxHeight: 76)
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.accent, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WebTheme.accentText)
                            .frame(width: 22, height: 22)
                            .background(WebTheme.accent, in: Circle())
                            .overlay(Circle().strokeBorder(Color.black, lineWidth: 2).padding(-2))
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TrunkLabelDesign.accessibilityLabel(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("trunk.pocket.cell")
    }

    /// 下の帯（選んでいるラベル・貼る・作り直す・削除）
    private func actionBar(_ state: TrunkState) -> some View {
        let selected = state.pocket.first { $0.id == selectedId }
        return VStack(spacing: 10) {
            Text(selected.map { L("\(TrunkLabelDesign.caption($0)) を選んでいます", "\(TrunkLabelDesign.caption($0)) selected") }
                 ?? L("ラベルを選んでください", "Choose a label"))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    guard let selected else { return }
                    Task {
                        if await model.stick(selected.id) {
                            selectedId = nil
                            toasts.show(L("トランクに貼りました", "Stuck on your trunk"))
                        }
                    }
                } label: {
                    TrunkButtonFace(title: L("貼る", "Stick"), size: 15)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.pocket.stick")
                Button {
                    guard let selected else { return }
                    if state.isPro { rerollTarget = selected } else { showPaywall = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(L("作り直す", "Redo"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        TrunkProTag()
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(TrunkStyle.line, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("作り直す（Pro）", "Redo (Pro)"))
                .accessibilityIdentifier("trunk.pocket.reroll")
                Button {
                    guard selected != nil else { return }
                    confirmDelete = true
                } label: {
                    TrunkButtonFace(title: Labels.Common.delete, kind: .danger, size: 15)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.pocket.delete")
            }
            .disabled(selected == nil || model.busy)
            .opacity(selected == nil ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        // 下の帯の地（上は透けて、22% から黒・家のバーの下まで）
        .background(alignment: .top) {
            LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0), location: 0),
                                   Gradient.Stop(color: Color.black, location: 0.22),
                                   Gradient.Stop(color: Color.black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func deleteSelected() async {
        guard let id = selectedId else { return }
        if await model.remove(id) {
            selectedId = nil
            toasts.show(L("ラベルを削除しました", "Label deleted"))
        }
    }
}
