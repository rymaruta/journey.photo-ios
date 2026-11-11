import SwiftUI

/// ハイライトを作る・直す（モック2-5 の「新規」）。
///
/// **2026-11-12 判断（設計の案「ストーリーのデザイン 残り」04・HighlightPlayer・MyPage の輪に合わせる）**:
/// 設定の表（Form）の形をやめ、上にマイページで出る輪（88）と名前（明朝 18 の中央寄せ・「2/30」）、
/// 下に残したストーリーの 3 列の格子（すき間 2・選んだ順の数を右上・表紙に「表紙」）。
/// 表紙は輪か「表紙を変える」を押して、選んだものだけが並ぶシートで1枚選ぶ（以前は選べず、外して選び直すしかなかった）。
/// 空のときは「ストーリーを作る」で作る画面へ（以前は文だけで作りに行く口が無かった）。保存中は保存が回る印に替わる
///
/// **材料はアーカイブだけ。** 24時間のあとも残したストーリーしか
/// 入れられない（サーバーが `archive: true` の行しか受け取らない
/// ——`api-user/src/highlights.ts` の `checkStories`）。だから、
/// アーカイブが空のときは**作らせずに、残し方を教える**。
struct HighlightEditorView: View {

    /// 直すとき。`nil` なら新規
    let existing: Highlight?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var archive: [Story] = []
    /// 選んだ順を覚える。**並びがそのまま再生順**になる（サーバーは
    /// 受け取った並びのまま保存して返す）
    @State private var picked: [String] = []
    @State private var coverId: String?
    @State private var loading = true
    @State private var loadFailed = false
    /// 直そうとしたハイライトが**もう無い**（404）。再試行を出さない
    @State private var gone = false
    @State private var saving = false
    @State private var message: String?
    @State private var showDeleteConfirm = false
    /// 開いたときの姿（`HighlightService.leave`）。直すときは読み込んだ中身で置き換える
    @State private var opened: HighlightService.Draft
    @State private var showLeaveConfirm = false
    /// 表紙を選ぶシート・空から作りに行く作る画面（2026-11-12）
    @State private var showCoverPicker = false
    @State private var showComposer = false
    @State private var coverTick = 0

    /// 上の輪の大きさ（設計の案 04: 88）
    static let ringSide: CGFloat = 88

    init(existing: Highlight?) {
        self.existing = existing
        // 直すときの並びは読み込むまで空（読み込めたら `load` が入れ直す）
        _opened = State(initialValue: HighlightService.Draft(title: existing?.title ?? "", picked: [], coverId: nil))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    head
                    if let message {
                        // 保存・削除の失敗は名前のすぐ下に（板 06「起きた所のすぐ上」。保存は上の段なので、その下で最も近い所）
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.danger)
                            .padding(.horizontal, JPSpace.m)
                            .padding(.top, JPSpace.s)
                            .accessibilityIdentifier("highlightEditor.message")
                    }
                    stories
                        .padding(.top, JPSpace.xl)
                    if existing != nil { deleteRow }
                }
                .padding(.bottom, JPSpace.screenEnd)
            }
            .background(WebTheme.background)
            .webScreen()
            // 🔴 **選んだストーリー・打った名前を黙って捨てさせない**（`HighlightService.leave`・
            // バグ探し 2026-10-03）。変更がある間は下へ引いても閉じず、「キャンセル」で確かめる
            // （ストーリー作成・写真の編集と同じ `unsavedCloseGuard`）。保存・削除の最中は閉じない
            .unsavedCloseGuard(leave, isPresented: $showLeaveConfirm,
                               title: L("変更を保存しますか？", "Save your changes?"),
                               canSave: canSave,
                               saveTitle: L("保存して閉じる", "Save and close"),
                               discardTitle: L("保存せずに閉じる", "Close without saving"),
                               message: L("保存しないで閉じると、選んだストーリーと名前は残りません。",
                                          "If you close without saving, your picks and name will be lost."),
                               onSave: {
                                   // 右上の「保存」と同じ門。成功したら `save` が閉じる
                                   guard canSave else { return }
                                   saving = true
                                   Task { await save() }
                               },
                               onDiscard: { dismiss() })
            .navigationTitle(existing == nil
                             ? L("新しいハイライト", "New highlight")
                             : L("ハイライトを編集", "Edit highlight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                        // 保存・削除の最中は閉じさせない（`DeleteAccountView` と同じ形）
                    Button(Labels.Common.cancel) {
                        switch leave {
                        case .now: dismiss()
                        case .confirm: showLeaveConfirm = true
                        case .wait: break
                        }
                    }
                    .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        // 保存している間は回る印に替える（二度押しを受けない）
                        ProgressView().tint(.white)
                            .accessibilityLabel(L("保存しています", "Saving"))
                    } else {
                        Button(Labels.Common.save) {
                            // 🔴 **門は押したその場で閉じる。** `saving` を Task の中で立てて
                            // いたので、描き直しの前に2回押すと同じハイライトが2つできた
                            guard canSave else { return }
                            saving = true
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .accessibilityIdentifier("highlightEditor.save")
                    }
                }
            }
            .sheet(isPresented: $showCoverPicker) { coverPicker }
            // 空のとき「ストーリーを作る」。作る画面は画面いっぱい（#406・`StoryComposerPresentationTests`）。
            // 閉じたら残したストーリーを読み直す（「24時間後も自分用に残す」で残した1本が並ぶ）
            .fullScreenCover(isPresented: $showComposer, onDismiss: { Task { await load() } }) {
                NavigationStack {
                    StoryComposerView(startsWithCamera: StoryCameraView.isAvailable)
                }
            }
            .task { await load() }
        }
    }

    /// 決まりは `HighlightService.canSave`（読み込みに失敗している間は押せない）
    private var canSave: Bool {
        HighlightService.canSave(title: title, picked: picked, saving: saving,
                                 loading: loading, loadFailed: loadFailed)
    }

    /// 「キャンセル」・下へ引くの扱い（`HighlightService.leave`）
    private var leave: UnsavedLeave {
        HighlightService.leave(opened: opened,
                               now: HighlightService.Draft(title: title, picked: picked, coverId: coverId),
                               saving: saving)
    }

    // MARK: - 上（輪・表紙・名前）

    /// マイページで出る輪と名前を、仕上がりのまま上に置く（2026-11-12 判断・設計の案 04）。
    /// 輪か「表紙を変える」を押すと、選んだものだけが並ぶシートで表紙を選ぶ
    private var head: some View {
        VStack(spacing: JPSpace.xs) {
            Button {
                if !picked.isEmpty { showCoverPicker = true }
            } label: {
                ring(side: Self.ringSide)
            }
            .buttonStyle(.plain)
            .disabled(picked.isEmpty)
            .accessibilityLabel(L("表紙", "Cover"))
            .accessibilityHint(picked.isEmpty ? "" : L("押すと表紙を変えます", "Opens the cover picker"))
            .accessibilityIdentifier("highlightEditor.ring")
            // 表紙を変える（黒地の上のリンクなので真鍮）。選んだものが無い間は場所だけ残す（輪と名前が跳ねない）
            Button(L("表紙を変える", "Change cover")) { showCoverPicker = true }
                .font(JPFont.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.accent)
                .buttonStyle(.plain)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
                .padding(.vertical, -8)
                .opacity(picked.isEmpty ? 0 : 1)
                .disabled(picked.isEmpty)
                .accessibilityHidden(picked.isEmpty)
                .accessibilityIdentifier("highlightEditor.changeCover")
            nameField
                .padding(.top, JPSpace.xs)
        }
        .padding(.top, JPSpace.s)
        .padding(.horizontal, JPSpace.m)
    }

    /// 輪（マイページの輪の形: 写真のまわりに白 50% の細い輪・黒のすき間・白 14% の髪線）
    private func ring(side: CGFloat) -> some View {
        let outer: CGFloat = side + 10
        let gap: CGFloat = side + 8
        return ZStack {
            Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: JPStroke.hairline)
                .frame(width: outer, height: outer)
            Circle().fill(Color.black).frame(width: gap, height: gap)
            Group {
                if let story = coverStory {
                    StoryPoster(story: story)
                } else {
                    // 表紙がまだ無い（何も選んでいない）
                    ZStack {
                        WebTheme.sheet
                        Image(systemName: "photo.on.rectangle")
                            .font(Font.title3)
                            .foregroundStyle(WebTheme.text3)
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
        }
        .frame(width: outer, height: outer)
    }

    /// 表紙にしているストーリー
    private var coverStory: Story? {
        guard let coverId else { return nil }
        return archive.first { $0.id == coverId }
    }

    /// 名前の欄（明朝 18 の中央寄せ・下に髪線・右に「2/30」）
    private var nameField: some View {
        ZStack(alignment: .trailing) {
            TextField(L("名前", "Name"), text: $title)
                .font(JPFont.rowTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(WebTheme.text)
                .padding(.horizontal, 40)
                .frame(minHeight: WebTheme.minTapTarget)
                .onChange(of: title) { old, new in
                    // **上限で止める。** サーバーと同じく UTF-16 の単位で数える
                    // （`HIGHLIGHT_TITLE_MAX`）。字の数では絵文字の名前が黙って切られた
                    let kept = PostLimits.limited(old: old, new: new, limit: HighlightService.titleMax)
                    if kept != new { title = kept }
                }
                .accessibilityLabel(L("名前", "Name"))
                .accessibilityHint(L("\(HighlightService.titleMax)文字まで。マイページの輪の下に出ます。",
                                     "Up to \(HighlightService.titleMax) characters. Shown under the circle."))
                .accessibilityIdentifier("highlightEditor.name")
            Text(HighlightService.titleCount(title))
                .font(JPFont.mono(12, relativeTo: .caption))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: 260)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.line).frame(height: JPStroke.hairline)
        }
    }

    // MARK: - 残したストーリー

    @ViewBuilder
    private var stories: some View {
        if loading {
            VStack(spacing: JPSpace.s) {
                eyebrow
                JPLoadingState(kind: .grid)
            }
        } else if gone {
            EmptyState(title: L("このハイライトはもうありません", "This highlight no longer exists"),
                       message: L("消されたか、見られなくなりました。", "It was deleted or is no longer available."))
        } else if loadFailed {
            // **空と失敗を分ける。** 一緒にすると、圏外の人に
            // 「1本も残していない」と言うことになる。
            // 直すときは、いま入っている並びが取れなかった回もここ（上の `canSave`）
            ErrorBanner(title: L("ストーリーを読み込めませんでした", "Couldn't load your stories"),
                        message: L("通信を確かめて、もう一度お試しください。読み込めるまで保存できません。",
                                   "Check your connection and try again. You can save once they load."),
                        retry: { Task { await load() } })
        } else if archive.isEmpty {
            // 空の状態の型。今は文だけで、作りに行く口が無かった——「ストーリーを作る」を置く
            EmptyState(title: L("残したストーリーがまだありません", "No kept stories yet"),
                       message: L("ストーリーを投稿するときに「24時間後も自分用に残す」を入れると、ここに並びます。",
                                  "Turn on \"Keep for me after 24 hours\" when you post a story and it will show up here."),
                       actionTitle: L("ストーリーを作る", "Make a story"),
                       actionIdentifier: "highlightEditor.makeStory") { showComposer = true }
        } else {
            VStack(spacing: JPSpace.s) {
                eyebrow
                grid
            }
        }
    }

    /// 「残したストーリー ——— 3件を選択」（眉ラベルは黒地の上なので真鍮）
    private var eyebrow: some View {
        JPEyebrowLine(L("残したストーリー", "Kept stories"),
                      trailing: picked.isEmpty ? nil : L("\(picked.count)件を選択", "\(picked.count) selected"))
            .padding(.horizontal, JPSpace.m)
    }

    /// 3 列・すき間 2 の格子（縦長 9:16）。選んだ順の数を右上に、表紙には左下に「表紙」
    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(archive) { story in
                Button {
                    toggle(story.id)
                } label: {
                    cell(story)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cell(_ story: Story) -> some View {
        let order = picked.firstIndex(of: story.id)
        // 動画は絵として読めない（壊れた絵になる）ので、動画の印を出す部品を使う
        return Color.clear
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay { StoryPoster(story: story) }
            .clipped()
            .overlay {
                // 選んだものは内側に白 3 の縁（写真の上なので白）
                if order != nil {
                    Rectangle().strokeBorder(WebTheme.accentBackground, lineWidth: 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if let day = HighlightService.dayLabel(story.createdAt) {
                    Text(day)
                        .font(JPFont.mono(12, medium: true, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .jpPhotoTextShadow()
                        .padding(JPSpace.xs)
                }
            }
            .overlay(alignment: .topTrailing) {
                // **何番目かを出す。** 並びが再生順なので、順番が見えないと
                // 「入れた・入れていない」しか分からない。選んでいないものは白の丸の縁だけ
                Group {
                    if let order {
                        Text("\(order + 1)")
                            .font(JPFont.mono(13, medium: true, relativeTo: .footnote))
                            .foregroundStyle(WebTheme.accentText)
                            .lineLimit(1)
                            // 1桁は 24pt の丸、2・3桁（最大 100 件）は中身に合わせて横に伸ばす
                            .padding(.horizontal, 5)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(WebTheme.accentBackground, in: Capsule())
                    } else {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            .background(Circle().fill(Color.black.opacity(0.2)))
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(JPSpace.xs)
            }
            .overlay(alignment: .bottomLeading) {
                if story.id == coverId {
                    Text(L("表紙", "Cover"))
                        .font(JPFont.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, JPSpace.xs)
                        .frame(minHeight: 24)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(JPSpace.xs)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HighlightService.cellLabel(day: HighlightService.dayLabel(story.createdAt),
                                                           order: order.map { $0 + 1 },
                                                           isCover: story.id == coverId))
            .accessibilityAddTraits(order == nil ? .isButton : [.isButton, .isSelected])
    }

    // MARK: - 表紙を選ぶ

    /// 選んだものだけが並ぶシート。1 枚押すと輪に入り、「完了」で閉じる
    private var coverPicker: some View {
        NavigationStack {
            VStack(spacing: JPSpace.m) {
                ring(side: 112)
                    .padding(.top, JPSpace.s)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(picked.enumerated()), id: \.element) { index, id in
                            if let story = archive.first(where: { $0.id == id }) {
                                Button {
                                    coverId = id
                                    coverTick += 1
                                } label: {
                                    StoryPoster(story: story)
                                        .frame(width: 64, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
                                        .overlay {
                                            if id == coverId {
                                                RoundedRectangle(cornerRadius: JPRadius.s)
                                                    .strokeBorder(Color.white, lineWidth: 2)
                                            }
                                        }
                                        .overlay(alignment: .topLeading) {
                                            Text("\(index + 1)")
                                                .font(JPFont.mono(12, medium: true, relativeTo: .caption))
                                                .foregroundStyle(.white)
                                                .jpPhotoTextShadow()
                                                .padding(6)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("\(index + 1)件目", "Item \(index + 1)"))
                                .accessibilityAddTraits(id == coverId ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }
                    .padding(.horizontal, JPSpace.l)
                }
                Text(L("選んだストーリーの中から1枚", "Choose one of the stories you picked"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WebTheme.sheet)
            .webScreen()
            .navigationTitle(L("表紙", "Cover"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完了", "Done")) { showCoverPicker = false }
                        .accessibilityIdentifier("highlightEditor.coverDone")
                }
            }
            .sensoryFeedback(.selection, trigger: coverTick)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 削除

    /// 下の赤い字の行と、消えないものの説明（危険の色はテーマの赤・系統の赤を行に出さない）
    private var deleteRow: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            VStack(spacing: 2) {
                Text(L("このハイライトを削除", "Delete this highlight"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.danger)
                // **中身は消えない**と言う。消えると思って手が止まるため
                Text(L("輪が消えるだけで、ストーリーはアーカイブに残ります", "Only the circle goes away — the stories stay in your archive"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, JPSpace.m)
        .padding(.top, JPSpace.xl)
        // 保存・削除の最中は押せない（保存と削除が同時に走らない）
        .disabled(saving)
        .accessibilityIdentifier("highlightEditor.delete")
        .confirmationDialog(L("このハイライトを削除しますか？", "Delete this highlight?"),
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(Labels.Common.delete, role: .destructive) { Task { await remove() } }
            Button(Labels.Common.cancel, role: .cancel) { }
        } message: {
            Text(L("輪が消えるだけで、ストーリーはアーカイブに残ります。",
                   "Only the circle goes away — the stories stay in your archive."))
        }
    }

    private func toggle(_ id: String) {
        if let at = picked.firstIndex(of: id) {
            picked.remove(at: at)
        } else if picked.count < HighlightService.storiesMax {
            picked.append(id)
        }
        // 表紙は**いまの表紙が残っていればそのまま**・外したら先頭。サーバーも並びの中のものしか受け取らない
        coverId = HighlightService.cover(keeping: coverId, in: picked)
    }

    private func load() async {
        loading = true
        loadFailed = false
        gone = false
        do {
            archive = try await environment.highlights.archive()
        } catch {
            loadFailed = true
        }
        if let existing {
            // 「もう一度試す」で打ちかけの名前を戻さない（最初の1回だけ入れる）
            if title.isEmpty { title = existing.title }
            // 直すときは、いま入っているものを選び直しておく。
            // **アーカイブから外れたものは選べない**ので落ちる
            // ⚠️ `try? await` を含む if-let は構文検査が読めないので分ける
            // ⚠️ catch の中で await しない（Xcode 26.3 のコンパイラが落ちる）
            var contents: HighlightContents?
            if let userId = auth.userId {
                do {
                    contents = try await environment.highlights.contents(userId: userId, id: existing.id)
                } catch {
                    gone = HighlightService.isGone(error)
                }
            }
            // **いまの並びが取れなければ保存させない**（`canSave` の注記）
            if contents == nil { loadFailed = true }
            if let contents {
                // 名前は**いまの中身**から（一覧の行は開いたときの古い名前で、名前を変えた
                // 後に開き直すと古い名前が入り、そのまま保存すると元に戻った）。打ちかけは触らない
                if title == existing.title, !contents.title.isEmpty { title = contents.title }
                let inArchive = Set(archive.map(\.id))
                picked = contents.items.map(\.id).filter { inArchive.contains($0) }
                // **表紙は必ず並びの中のものにする。** サーバーは並びに
                // 無い表紙を断る（400）ので、アーカイブから外れた写真が
                // 表紙だった輪は、直そうとした瞬間に保存できなくなる
                let cover = contents.coverStoryId
                coverId = HighlightService.cover(keeping: cover, in: picked)
                // 比べる元は**読み込んだ中身**（打ちかけの名前ではなく、サーバーの名前）
                opened = HighlightService.Draft(title: contents.title.isEmpty ? existing.title : contents.title,
                                                picked: picked, coverId: coverId)
            }
        }
        loading = false
    }

    /// 呼ぶ前に `saving` を立てておくこと（ボタンが同期で立てる）
    private func save() async {
        message = nil
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let existing {
                try await environment.highlights.update(id: existing.id, title: name,
                                                        storyIds: picked, coverStoryId: coverId)
            } else {
                try await environment.highlights.create(title: name, storyIds: picked,
                                                        coverStoryId: coverId)
            }
            dismiss()
        } catch {
            // サーバーの断り文を出す（上限・アーカイブに無い など）
            message = HighlightService.failureMessage(
                for: error,
                fallback: L("保存できませんでした。もう一度お試しください。",
                            "Couldn't save it. Please try again."))
        }
        saving = false
    }

    private func remove() async {
        guard let existing else { return }
        saving = true
        do {
            try await environment.highlights.delete(id: existing.id)
            dismiss()
        } catch where HighlightService.isGone(error) {
            // **もう無い（404）は消せたのと同じ。** サーバーは本体が無くても
            // 自分の一覧からは外してから 404 を返す（`highlights.ts` の `deleteHighlight`）
            dismiss()
        } catch {
            message = HighlightService.failureMessage(
                for: error,
                fallback: L("削除できませんでした。もう一度お試しください。",
                            "Couldn't delete it. Please try again."))
        }
        saving = false
    }
}
