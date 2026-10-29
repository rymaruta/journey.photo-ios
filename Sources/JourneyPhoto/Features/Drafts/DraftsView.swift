import SwiftUI
import UIKit

/// 下書きの一覧（2026-10-29・#400「下書きを複数持つ」・モック 9JzQWmYxF14BmUiZ9yWbe8）。
///
/// - **縦長 4:5 の3列の格子が既定**（owner「インスタみたいに3かける3で」）。右上の切り替えで行の一覧にも
///   できる（選んだほうを人ごとに覚える `DraftViewPreference`）。格子と行は「表示の切替」なので
///   繋がったセグメント、「すべて／投稿／ストーリー」は「絞り込み」なので独立の丸チップ（板 03）
/// - **マスの印はすべて白**（写真の上なので真鍮は置かない）: 左上に投稿／ストーリー（自動の書きかけは
///   「自動保存」）、右下に枚数、左下に期限が近いストーリーの「あと n 日」（黒 60% の丸に白）、右上に
///   読めない写真ありの「!」（危険の色の丸に白）。題・撮影地・日時はマスに出さず、**長押し**で出す
///   （浮く縮図の下に詳細・操作は 続きから編集／複製／削除）。読み上げは全部を1つの名前で読む
/// - 「選ぶ」で複数選んで「n件を削除」→ 約6秒「元に戻す」。**画像のファイルを消すのはその後**
///   （`DraftLibrary.hide` / `finalize`）
/// - 上の帯「n / 20件 · 容量 · この端末にだけ保存」（押すと説明のシート）
/// - 0件・読み込み中・読めなかった（「0件」と分ける・板 06）・英語（`DraftsText` の `L()`）
struct DraftsView: View {

    /// どこから開いたか
    enum Presentation: Equatable {
        /// マイページから積んだ（戻るは左上の矢印）
        case pushed
        /// 作る画面からシートで開いた（左上の「閉じる」）
        case sheet
    }

    let presentation: Presentation
    /// 開いたときの絞り込み（ストーリーの作る画面からは「ストーリー」）
    var initialFilter: DraftLibrary.Kind? = nil
    /// 🔴 **いっぱいで保存できない書きかけから来た**（「下書きを整理する」）。選ぶ状態で開き、
    /// 「1件以上削除すると、いまの書きかけを保存できます。」の帯を出す。開く操作は出さない
    /// （書きかけを残したまま別の下書きを開くと、書きかけが行き場を失う）
    var tidying: Bool = false
    /// 下書きを開く（一覧を閉じるのは呼び手）
    let onOpen: (DraftLibrary.Entry) -> Void
    /// 0件の「写真を選ぶ」
    var onChoosePhotos: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var library = DraftLibrary.shared
    @ObservedObject private var tabRouter = TabRouter.shared
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case loading, loaded, failed }

    @State private var phase: Phase = .loading
    @State private var entries: [DraftLibrary.Entry] = []
    @State private var filter: DraftLibrary.Kind?
    @State private var layout: DraftViewPreference.Layout = .grid
    @State private var selecting = false
    /// 選んだ順（マスの番号は選んだ順・モック）
    @State private var selection: [String] = []
    @State private var confirmDelete: [String]?
    @State private var showAbout = false
    /// 読めない写真のある下書きを開こうとした
    @State private var missingTarget: DraftLibrary.Entry?
    /// 「元に戻す」を待っている削除
    @State private var pendingUndo: [String]?
    @State private var undoTask: Task<Void, Never>?
    /// 複製できなかったなどの一言（起きた所のすぐ上・板 06）
    @State private var notice: String?
    @State private var appliedInitial = false

    private var userId: String { auth.userId ?? "" }
    private var now: Date { library.now() }

    private var visible: [DraftLibrary.Entry] {
        entries.filter { filter == nil || $0.kind == filter }
    }

    private var savedCount: Int { entries.filter { !$0.isAuto }.count }

    var body: some View {
        content
            .webScreen()
            .navigationTitle(selecting ? DraftsText.selectionTitle(selection.count) : DraftsText.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(selecting || presentation == .sheet)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .overlay(alignment: .bottom) { undoBar }
            .onAppear {
                if !appliedInitial {
                    appliedInitial = true
                    filter = initialFilter
                    layout = DraftViewPreference().layout(for: auth.userId)
                    if tidying { selecting = true }
                }
            }
            .task(id: library.revision) { await reload() }
            // 作る画面を閉じたら読み直す（保存し直した・投稿して外れた）
            .onChange(of: tabRouter.postSheetsClosed) { _, _ in Task { await reload() } }
            // 一覧を閉じたら、元に戻すを待っていた削除を済ませる（画像を消す）
            .onDisappear { finishPendingDelete() }
            .confirmationDialog(DraftsText.deleteConfirmTitle(confirmDelete?.count ?? 0),
                                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button(DraftsText.delete, role: .destructive) {
                    if let ids = confirmDelete { delete(ids) }
                    confirmDelete = nil
                }
                Button(Labels.Common.cancel, role: .cancel) { confirmDelete = nil }
            } message: {
                Text(DraftsText.deleteConfirmMessage)
            }
            .confirmationDialog(DraftsText.missingTitle(missingTarget?.missingCount ?? 0),
                                isPresented: Binding(get: { missingTarget != nil }, set: { if !$0 { missingTarget = nil } }),
                                titleVisibility: .visible) {
                if let target = missingTarget {
                    if target.readableCount > 0 {
                        Button(DraftsText.continueWithRest(target.readableCount)) {
                            missingTarget = nil
                            onOpen(target)
                        }
                    }
                    Button(DraftsText.deleteThisDraft, role: .destructive) {
                        missingTarget = nil
                        confirmDelete = [target.id]
                    }
                }
                Button(Labels.Common.cancel, role: .cancel) { missingTarget = nil }
            } message: {
                if let target = missingTarget {
                    Text(DraftsText.missingMessage(total: target.photoCount, missing: target.missingCount))
                }
            }
            .sheet(isPresented: $showAbout) {
                DraftsAboutSheet(count: savedCount, megabytes: DraftLibrary.megabytes(entries))
            }
            .accessibilityIdentifier("drafts.list")
    }

    // MARK: 中身

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ScrollView { skeleton }
                .scrollDisabled(true)
        case .failed:
            failedState
        case .loaded:
            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        bands
                        chips
                        if !selecting { storageRow }
                        viewRow
                        if let notice { noticeLine(notice) }
                        if visible.isEmpty {
                            Text(DraftsText.noneOfKind)
                                .font(JPFont.body)
                                .foregroundStyle(WebTheme.text2)
                                .frame(maxWidth: .infinity)
                                .padding(.top, JPSpace.emptyTop)
                        } else if layout == .grid {
                            grid
                        } else {
                            rows
                        }
                    }
                    .padding(.bottom, JPSpace.screenEnd)
                }
            }
        }
    }

    /// 期限が近い（あしたまでに消える）ストーリーの帯と、いっぱいの帯（真鍮 8% の地に真鍮の字・黒地の上）
    @ViewBuilder
    private var bands: some View {
        if tidying && DraftLibrary.isFull(count: savedCount) {
            band(symbol: "info.circle", text: DraftsText.limitBand)
        }
        let soon = entries.filter { entry in
            DraftLibrary.daysLeft(kind: entry.kind, savedAt: entry.savedAt, now: now).map { $0 <= 1 } ?? false
        }.count
        if soon > 0 && !selecting {
            band(symbol: "clock", text: DraftsText.expiringBand(soon))
        }
    }

    private func band(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
            Image(systemName: symbol)
                .font(JPFont.footnote)
                .accessibilityHidden(true)
            Text(text)
                .font(JPFont.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(WebTheme.accent)
        .padding(.horizontal, JPSpace.s)
        .padding(.vertical, 10)
        .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .padding(.horizontal, JPSpace.m)
        .padding(.vertical, JPSpace.xxs)
    }

    /// 絞り込み（すべて／投稿／ストーリー）。独立の丸チップ（板 03）
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JPSpace.xs) {
                chip(nil)
                chip(.post)
                chip(.story)
            }
            .padding(.horizontal, JPSpace.m)
        }
        .padding(.vertical, -PillChip.tapSlack)
        .padding(.top, JPSpace.xxs)
        .padding(.bottom, JPSpace.xs)
        .accessibilityLabel(L("絞り込み", "Filter"))
    }

    private func chip(_ kind: DraftLibrary.Kind?) -> some View {
        PillChip(title: DraftsText.filter(kind),
                 count: entries.filter { kind == nil || $0.kind == kind }.count,
                 selected: filter == kind) {
            filter = kind
            // 絞り込みで見えなくなったものは選んだままにしない（見えないまま消さない）
            if selecting {
                selection = selection.filter { id in visible.contains { $0.id == id } }
            }
        }
        .accessibilityIdentifier("drafts.filter.\(kind?.rawValue ?? "all")")
    }

    /// 「n / 20件 · 容量 · この端末にだけ保存」（押すと説明のシート）
    private var storageRow: some View {
        Button { showAbout = true } label: {
            HStack(spacing: JPSpace.xs) {
                Image(systemName: "iphone")
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
                Text(DraftsText.storageLine(count: savedCount, megabytes: DraftLibrary.megabytes(entries)))
                    .font(JPFont.number(JPTypeScale.caption, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(WebTheme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "info.circle")
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, JPSpace.s)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, JPSpace.m)
        .padding(.top, JPSpace.xxs)
        .padding(.bottom, JPSpace.xs)
        .accessibilityHint(DraftsText.aboutTitle)
        .accessibilityIdentifier("drafts.storage")
    }

    /// 案内の一言と、格子／行の切り替え（繋がったセグメント）
    private var viewRow: some View {
        HStack(spacing: JPSpace.xs) {
            Text(selecting ? "" : (layout == .grid ? DraftsText.gridHint : DraftsText.rowsHint))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                layoutButton(.grid, symbol: "square.grid.3x3.fill", label: L("格子", "Grid"))
                layoutButton(.rows, symbol: "list.bullet", label: L("行の一覧", "List"))
            }
            .padding(2)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.leading, JPSpace.m)
        .padding(.trailing, JPSpace.m)
        .padding(.bottom, 6)
    }

    private func layoutButton(_ value: DraftViewPreference.Layout, symbol: String, label: String) -> some View {
        Button {
            layout = value
            DraftViewPreference().set(value, for: auth.userId)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(layout == value ? WebTheme.text : WebTheme.text3)
                .frame(width: WebTheme.minTapTarget, height: 40)
                .background(layout == value ? WebTheme.surface8 : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(layout == value ? .isSelected : [])
        .accessibilityIdentifier("drafts.layout.\(value.rawValue)")
    }

    private func noticeLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(JPFont.footnote)
        .foregroundStyle(WebTheme.danger)
        .padding(.horizontal, JPSpace.m)
        .padding(.bottom, JPSpace.xs)
    }

    // MARK: 格子

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(visible) { entry in
                gridCell(entry)
            }
        }
    }

    @ViewBuilder
    private func gridCell(_ entry: DraftLibrary.Entry) -> some View {
        let position = selection.firstIndex(of: entry.id)
        let face = DraftGridCell(entry: entry, now: now, selecting: selecting,
                                 selectedNumber: position.map { $0 + 1 })
        if selecting {
            Button { toggle(entry) } label: { face }
                .buttonStyle(.plain)
                .accessibilityLabel(DraftsText.accessibility(entry, now: now))
                .accessibilityAddTraits(position != nil ? .isSelected : [])
                .accessibilityIdentifier("drafts.cell")
        } else {
            Button { open(entry) } label: { face }
                .buttonStyle(.plain)
                .accessibilityLabel(DraftsText.accessibility(entry, now: now))
                .accessibilityIdentifier("drafts.cell")
                // 長押し: 浮く縮図の下に題・撮影地・日時・期限、操作は 続きから編集／複製／削除
                // （系統のメニュー。削除は系統の赤のまま——CLAUDE.md「メニューは系統の部品なのでそのまま」）
                .contextMenu {
                    actions(entry)
                } preview: {
                    DraftPreviewCard(entry: entry, now: now)
                }
        }
    }

    @ViewBuilder
    private func actions(_ entry: DraftLibrary.Entry) -> some View {
        if !tidying {
            Button { open(entry) } label: {
                Label(DraftsText.continueEditing, systemImage: "pencil")
            }
        }
        Button { duplicate(entry) } label: {
            Label(DraftsText.duplicate, systemImage: "plus.square.on.square")
        }
        .disabled(DraftLibrary.isFull(count: savedCount) || entry.readableCount == 0)
        Button(role: .destructive) { confirmDelete = [entry.id] } label: {
            Label(DraftsText.delete, systemImage: "trash")
        }
    }

    // MARK: 行

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                DraftRow(entry: entry, now: now, selecting: selecting,
                         selected: selection.contains(entry.id),
                         onTap: { selecting ? toggle(entry) : open(entry) }) {
                    Menu {
                        actions(entry)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WebTheme.text2)
                            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("ほかの操作", "More"))
                }
                .overlay(alignment: .top) {
                    if index > 0 { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
                }
            }
        }
    }

    // MARK: 状態

    private var skeleton: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(0..<12, id: \.self) { _ in
                WebTheme.surface4
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
            }
        }
        .padding(.top, 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DraftsText.loading)
    }

    private var emptyState: some View {
        VStack(spacing: JPSpace.s) {
            Text(DraftsText.emptyTitle)
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(DraftsText.emptyMessage)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onChoosePhotos {
                // 写真の無い画面の主ボタン（真鍮の塗り＋墨・CLAUDE.md）
                Button(action: onChoosePhotos) {
                    Text(DraftsText.emptyAction).jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 240)
                .padding(.top, JPSpace.xs)
                .accessibilityIdentifier("drafts.empty.choose")
            }
        }
        .padding(.horizontal, JPSpace.section)
        .padding(.top, JPSpace.emptyTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drafts.empty")
    }

    /// 読めなかった（「0件」と分ける・板 06）。下書きは消えていないと言い、もう一度試す
    private var failedState: some View {
        VStack(spacing: JPSpace.s) {
            Text(DraftsText.errorTitle)
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                Text(DraftsText.errorMessage).fixedSize(horizontal: false, vertical: true)
            }
            .font(JPFont.footnote)
            .foregroundStyle(WebTheme.danger)
            Button { Task { await reload(showLoading: true) } } label: {
                Text(DraftsText.retry).jpPillButton(.outline)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, JPSpace.section)
        .padding(.top, JPSpace.emptyTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 上と下のバー

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    selecting = false
                    selection = []
                    // 整理しに来た回は「キャンセル」で作る画面へ戻る
                    if tidying { dismiss() }
                } label: {
                    Text(Labels.Common.cancel).font(.body).foregroundStyle(WebTheme.text)
                }
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { selectAll() } label: {
                    Text(DraftsText.selectAll).font(.body).foregroundStyle(WebTheme.text)
                }
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                .disabled(visible.isEmpty)
            }
        } else {
            if presentation == .sheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text(Labels.Common.close).font(.body).foregroundStyle(WebTheme.text)
                    }
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .accessibilityIdentifier("drafts.close")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // ヘッダーの文字アクション＝黒地の上なので真鍮（板 04）
                Button {
                    selection = []
                    selecting = true
                } label: {
                    Text(DraftsText.select)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(entries.isEmpty || phase != .loaded ? WebTheme.text3 : WebTheme.accent)
                }
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                .disabled(entries.isEmpty || phase != .loaded)
                .accessibilityIdentifier("drafts.select")
            }
        }
    }

    /// 選んでいる間の下の段（件数・写真の枚数と「n件を削除」——危険の色・画面の行なので系統の赤にしない）
    @ViewBuilder
    private var bottomBar: some View {
        if selecting {
            HStack(spacing: JPSpace.s) {
                Text(DraftsText.selectionCaption(drafts: selection.count, photos: selectedPhotos))
                    .font(JPFont.number(JPTypeScale.caption, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(WebTheme.text3)
                Spacer(minLength: 0)
                Button { confirmDelete = selection } label: {
                    Text(DraftsText.deleteButton(selection.count))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WebTheme.danger.opacity(selection.isEmpty ? 0.35 : 1))
                        .padding(.horizontal, JPSpace.xs)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("drafts.deleteSelected")
            }
            .padding(.horizontal, JPSpace.m)
            .padding(.vertical, JPSpace.xs)
            .background(WebTheme.card.opacity(0.96))
            .overlay(alignment: .top) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
        }
    }

    private var selectedPhotos: Int {
        selection.reduce(0) { sum, id in sum + (entries.first { $0.id == id }?.photoCount ?? 0) }
    }

    /// 削除のあとの「元に戻す」（約6秒）。成功の印は緑、ボタンは真鍮（黒い札の上）
    @ViewBuilder
    private var undoBar: some View {
        if let ids = pendingUndo {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WebTheme.success)
                    .accessibilityHidden(true)
                Text(DraftsText.deleted(ids.count))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { undo() } label: {
                    Text(DraftsText.undo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("drafts.undo")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(WebTheme.surface6, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
            .padding(.horizontal, JPSpace.s)
            .padding(.bottom, JPSpace.l)
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: 操作

    private func reload(showLoading: Bool = false) async {
        if showLoading { phase = .loading }
        // 読み込み中の骨格を一度描いてから読む（縮図の読み込みは各マスが後ろで）
        await Task.yield()
        guard library.storageReadable() else {
            phase = .failed
            return
        }
        entries = library.entries(for: userId, sendingStoryStamp: StoryUploadCenter.shared.pendingDraftStamp)
        selection = selection.filter { id in entries.contains { $0.id == id } }
        phase = .loaded
    }

    private func open(_ entry: DraftLibrary.Entry) {
        guard !tidying else { return }
        if entry.missingCount > 0 {
            missingTarget = entry
            return
        }
        onOpen(entry)
    }

    private func toggle(_ entry: DraftLibrary.Entry) {
        if let index = selection.firstIndex(of: entry.id) {
            selection.remove(at: index)
        } else {
            selection.append(entry.id)
        }
    }

    private func selectAll() {
        let ids = visible.map(\.id)
        if ids.allSatisfy(selection.contains) {
            selection = []
        } else {
            for id in ids where !selection.contains(id) { selection.append(id) }
        }
    }

    private func duplicate(_ entry: DraftLibrary.Entry) {
        notice = nil
        if library.duplicate(entry.id, kind: entry.kind, for: userId) == nil {
            notice = DraftsText.duplicateFailed
        }
    }

    /// 削除（一覧から隠す）→ 約6秒「元に戻す」→ 本当に消す
    private func delete(_ ids: [String]) {
        // 前の削除の「元に戻す」は締め切る（積まない）
        finishPendingDelete()
        library.hide(ids)
        selection = []
        selecting = tidying && DraftLibrary.isFull(count: savedCount - ids.count) ? true : false
        pendingUndo = ids
        let owner = userId
        undoTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(DraftLibrary.undoSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            library.finalize(ids, for: owner)
            if pendingUndo == ids { pendingUndo = nil }
        }
    }

    private func undo() {
        guard let ids = pendingUndo else { return }
        undoTask?.cancel()
        undoTask = nil
        pendingUndo = nil
        library.undo(ids)
    }

    private func finishPendingDelete() {
        guard let ids = pendingUndo else { return }
        undoTask?.cancel()
        undoTask = nil
        pendingUndo = nil
        library.finalize(ids, for: userId)
    }
}

// MARK: - 部品

/// 格子の1マス（縦 4:5・角なし・印は白）
struct DraftGridCell: View {
    let entry: DraftLibrary.Entry
    let now: Date
    let selecting: Bool
    /// 選んだ順の番号（選んでいなければ nil）
    let selectedNumber: Int?

    /// 印の影（写真の上の白を読めるように）
    private static let markShadow = Color.black.opacity(0.8)

    var body: some View {
        let days = DraftLibrary.daysLeft(kind: entry.kind, savedAt: entry.savedAt, now: now)
        Color.clear
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay { DraftCover(url: entry.cover) }
            .clipped()
            .overlay {
                // ストーリーは縮図の上に置いた文字も見せる（明朝・白・影）。モックは明朝 13 だが、
                // 板（02 書体）の明朝の下限 18（rowTitle）に合わせた（2026-10-29 判断）
                if entry.kind == .story && !entry.title.isEmpty && entry.cover != nil {
                    Text(entry.title)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.7), radius: 3)
                        .padding(.horizontal, 6)
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    Image(systemName: entry.kind == .story ? "clock" : "photo")
                    if entry.isAuto { Text(L("自動保存", "Auto")) }
                }
                .font(JPFont.caption.weight(.semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Self.markShadow, radius: 2, y: 1)
                .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                if entry.photoCount > 1 {
                    HStack(spacing: 3) {
                        Image(systemName: "square.on.square")
                        Text("\(entry.photoCount)")
                    }
                    .font(JPFont.number(JPTypeScale.caption, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.white)
                    .shadow(color: Self.markShadow, radius: 2, y: 1)
                    .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if DraftLibrary.showsDaysLeft(days), let days {
                    Text(DraftsText.daysLeftShort(days))
                        .font(JPFont.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    selectMark
                } else if entry.missingCount > 0 {
                    // 読めない写真がある（危険の色の丸に白の「!」・形でも伝える）
                    Text("!")
                        .font(JPFont.caption.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 22, height: 22)
                        .background(WebTheme.danger, in: Circle())
                        .padding(6)
                }
            }
            .overlay {
                if selectedNumber != nil {
                    Rectangle().fill(Color.white.opacity(0.12))
                    Rectangle().strokeBorder(WebTheme.accentBackground, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
    }

    /// 選ぶ丸（白の縁・選ぶと白の塗りに墨で選んだ順の番号）
    private var selectMark: some View {
        ZStack {
            Circle()
                .fill(selectedNumber == nil ? Color.black.opacity(0.25) : WebTheme.accentBackground)
            Circle()
                .strokeBorder(selectedNumber == nil ? Color.white : WebTheme.accentBackground, lineWidth: 1.5)
            if let selectedNumber {
                Text("\(selectedNumber)")
                    .font(JPFont.number(JPTypeScale.caption, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(WebTheme.accentText)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .padding(6)
    }
}

/// 行の1件（縮図・題（明朝）・撮影地・種類と枚数・日時・期限・読めない写真）
private struct DraftRow<Trailing: View>: View {
    let entry: DraftLibrary.Entry
    let now: Date
    let selecting: Bool
    let selected: Bool
    let onTap: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let days = DraftLibrary.daysLeft(kind: entry.kind, savedAt: entry.savedAt, now: now)
        HStack(spacing: JPSpace.s) {
            Button(action: onTap) {
                HStack(spacing: JPSpace.s) {
                    if selecting {
                        ZStack {
                            Circle().fill(selected ? WebTheme.accentBackground : Color.clear)
                            Circle().strokeBorder(selected ? WebTheme.accentBackground : Color.white.opacity(0.6), lineWidth: 1.5)
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(WebTheme.accentText)
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    Color.clear
                        .frame(width: entry.kind == .story ? 42 : 56, height: 56)
                        .overlay { DraftCover(url: entry.cover) }
                        .clipShape(RoundedRectangle(cornerRadius: entry.kind == .story ? 8 : JPRadius.s))
                    VStack(alignment: .leading, spacing: 2) {
                        // 題は明朝（モックは 17・板の明朝の下限 18＝rowTitle に合わせた）
                        Text(DraftsText.title(entry))
                            .font(JPFont.rowTitle)
                            .foregroundStyle(entry.title.isEmpty ? WebTheme.text3 : WebTheme.text)
                            .lineLimit(1)
                        if !entry.place.isEmpty && !selecting {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin").accessibilityHidden(true)
                                Text(entry.place).lineLimit(1)
                            }
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text2)
                        }
                        detailLine(days: days)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DraftsText.accessibility(entry, now: now))
            .accessibilityAddTraits(selecting && selected ? .isSelected : [])
            .accessibilityIdentifier("drafts.row")
            if !selecting { trailing() }
        }
        .padding(.leading, JPSpace.m)
        .padding(.trailing, JPSpace.xs)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
    }

    /// 種類・枚数・日時（灰の等幅数字）、自動の書きかけ・期限（真鍮・黒地の上）・読めない写真（危険の色）
    private func detailLine(days: Int?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { detailParts(days: days) }
            VStack(alignment: .leading, spacing: 2) { detailParts(days: days) }
        }
        .font(JPFont.number(JPTypeScale.caption, weight: .regular, relativeTo: .caption))
    }

    @ViewBuilder
    private func detailParts(days: Int?) -> some View {
        Text(DraftsText.kindAndPhotos(entry)).foregroundStyle(WebTheme.text3)
        Text(DraftsText.saved(entry.savedAt, now: now)).foregroundStyle(WebTheme.text3)
        if entry.isAuto { Text(DraftsText.autoNote).foregroundStyle(WebTheme.text3) }
        if DraftLibrary.showsDaysLeft(days), let days {
            Text(DraftsText.daysLeftLong(days)).foregroundStyle(WebTheme.accent)
        }
        if entry.missingCount > 0 {
            Text(DraftsText.missing(entry.missingCount)).foregroundStyle(WebTheme.danger)
        }
    }
}

/// 長押しで浮く縮図と詳細（題・撮影地・種類・枚数・日時・期限・読めない写真）
private struct DraftPreviewCard: View {
    let entry: DraftLibrary.Entry
    let now: Date

    var body: some View {
        let days = DraftLibrary.daysLeft(kind: entry.kind, savedAt: entry.savedAt, now: now)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 280, height: 350)
                .overlay { DraftCover(url: entry.cover) }
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(DraftsText.title(entry))
                    .font(JPFont.rowTitle)
                    .foregroundStyle(entry.title.isEmpty ? WebTheme.text3 : WebTheme.text)
                    .lineLimit(2)
                if !entry.place.isEmpty {
                    Text(entry.place).font(JPFont.footnote).foregroundStyle(WebTheme.text2)
                }
                Text("\(DraftsText.kindAndPhotos(entry)) · \(DraftsText.saved(entry.savedAt, now: now))")
                    .font(JPFont.number(JPTypeScale.caption, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(WebTheme.text3)
                if DraftLibrary.showsDaysLeft(days), let days {
                    Text(DraftsText.daysLeftLong(days)).font(JPFont.caption).foregroundStyle(WebTheme.accent)
                }
                if entry.missingCount > 0 {
                    Text(DraftsText.missing(entry.missingCount)).font(JPFont.caption).foregroundStyle(WebTheme.danger)
                }
            }
            .padding(JPSpace.s)
            .frame(width: 280, alignment: .leading)
        }
        .background(WebTheme.card)
    }
}

/// 縮図（下書きの写しの JPEG を小さくして読む・読めるまで骨格の色・読めなければ割れた写真の印）
struct DraftCover: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            WebTheme.surface4
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if url == nil || failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(WebTheme.text3)
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = DraftCoverCache.shared.image(for: url) {
                image = cached
                return
            }
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let jpeg = try? Data(contentsOf: url) else { return nil }
                return ImagePreparer.makeThumbnail(fromJPEG: jpeg)
            }.value
            guard !Task.isCancelled else { return }
            if let data, let loaded = UIImage(data: data) {
                DraftCoverCache.shared.store(loaded, for: url)
                image = loaded
            } else {
                failed = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// 縮図の控え（画像の名前は保存のたびに変わるので、古い絵を出し続けることは無い）
@MainActor
final class DraftCoverCache {
    static let shared = DraftCoverCache()
    private var images: [URL: UIImage] = [:]
    private var order: [URL] = []
    /// 持っておく枚数（20件＋並べ替えの余り）
    private let capacity = 48

    func image(for url: URL) -> UIImage? { images[url] }

    func store(_ image: UIImage, for url: URL) {
        if images[url] == nil { order.append(url) }
        images[url] = image
        while order.count > capacity {
            images[order.removeFirst()] = nil
        }
    }
}

/// 「下書きについて」（端末だけ・ログアウトしても消えない・期限・件数と容量）
struct DraftsAboutSheet: View {
    let count: Int
    let megabytes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(DraftsText.aboutTitle)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    SheetCloseButton()
                }
                .padding(.bottom, JPSpace.s)
                ForEach(Array(DraftsText.facts(count: count, megabytes: megabytes).enumerated()), id: \.offset) { index, fact in
                    HStack(alignment: .top, spacing: JPSpace.s) {
                        Image(systemName: fact.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(WebTheme.text2)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.headline)
                                .font(JPFont.body)
                                .foregroundStyle(WebTheme.text)
                            Text(fact.detail)
                                .font(JPFont.footnote)
                                .foregroundStyle(WebTheme.text3)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, JPSpace.s)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
                    }
                }
                Button { dismiss() } label: {
                    Text(DraftsText.gotIt).jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .padding(.top, JPSpace.s)
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.l)
            .padding(.bottom, JPSpace.xl)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(WebTheme.sheet)
    }
}
