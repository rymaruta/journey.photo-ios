import SwiftUI

/// ハイライトを作る・直す（モック2-5 の「新規」）。
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
    @State private var saving = false
    @State private var message: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                pickerSection
                if existing != nil { deleteSection }
                if let message {
                    Section { Text(message).font(.callout).foregroundStyle(Color.red) }
                        .listRowBackground(Color.clear)
                }
            }
            .webScreen()
            .navigationTitle(existing == nil
                             ? L("新しいハイライト", "New highlight")
                             : L("ハイライトを編集", "Edit highlight"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Labels.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Labels.Common.save) { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .task { await load() }
        }
    }

    /// 名前が要る・1件以上入っている・保存中でない。
    /// **サーバーと同じ線**（名前が空なら 400、0件なら 400）
    private var canSave: Bool {
        !saving && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !picked.isEmpty
    }

    private var nameSection: some View {
        Section {
            TextField(L("例: ギリシャ", "e.g. Greece"), text: $title)
                .onChange(of: title) { _, new in
                    // **上限で切る。** 打ち終わってから断られない
                    if new.count > HighlightService.titleMax {
                        title = String(new.prefix(HighlightService.titleMax))
                    }
                }
        } header: {
            Text(L("名前", "Name"))
        } footer: {
            Text(L("\(HighlightService.titleMax)文字まで。マイページの輪の下に出ます。",
                   "Up to \(HighlightService.titleMax) characters. Shown under the circle."))
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var pickerSection: some View {
        Section {
            if loading {
                HStack { ProgressView(); Text(L("読み込み中…", "Loading…")).font(.callout) }
            } else if loadFailed {
                // **空と失敗を分ける。** 一緒にすると、圏外の人に
                // 「1本も残していない」と言うことになる
                Text(L("アーカイブを読み込めませんでした。通信を確かめてください。",
                       "Couldn't load your archive. Check your connection."))
                    .font(.callout)
                    .foregroundStyle(WebTheme.muted2)
            } else if archive.isEmpty {
                Text(L("残したストーリーがまだありません。ストーリーを作るときに「24時間のあとも自分用に残す」を選ぶと、ここに並びます。",
                       "No kept stories yet. Turn on \"Keep it for myself after 24 hours\" when you post a story."))
                    .font(.callout)
                    .foregroundStyle(WebTheme.muted2)
            } else {
                strip
            }
        } header: {
            Text(L("入れるストーリー", "Stories to include"))
        } footer: {
            if !picked.isEmpty {
                Text(L("\(picked.count)件を選んでいます。最初の1件が表紙です。",
                       "\(picked.count) selected. The first one is the cover."))
            }
        }
        .listRowBackground(Color.clear)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(archive) { story in
                    Button {
                        toggle(story.id)
                    } label: {
                        thumbnail(story)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func thumbnail(_ story: Story) -> some View {
        let order = picked.firstIndex(of: story.id)
        return RemoteImage(url: story.imageURL)
            .frame(width: 72, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(order == nil ? Color.white.opacity(0.15) : WebTheme.accentBackground,
                              lineWidth: order == nil ? 1 : 2))
            .overlay(alignment: .topTrailing) {
                // **何番目かを出す。** 並びが再生順なので、順番が見えないと
                // 「入れた・入れていない」しか分からない
                if let order {
                    Text("\(order + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(width: 20, height: 20)
                        .background(WebTheme.accentBackground, in: Circle())
                        .padding(4)
                }
            }
            .accessibilityAddTraits(order == nil ? [] : .isSelected)
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Text(L("このハイライトを削除", "Delete this highlight"))
            }
            .confirmationDialog(L("このハイライトを削除しますか？", "Delete this highlight?"),
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(Labels.Common.delete, role: .destructive) { Task { await remove() } }
                Button(Labels.Common.cancel, role: .cancel) { }
            } message: {
                // **中身は消えない**と言う。消えると思って手が止まるため
                Text(L("輪が消えるだけで、ストーリーはアーカイブに残ります。",
                       "Only the circle goes away — the stories stay in your archive."))
            }
        }
        .listRowBackground(Color.clear)
    }

    private func toggle(_ id: String) {
        if let at = picked.firstIndex(of: id) {
            picked.remove(at: at)
        } else if picked.count < HighlightService.storiesMax {
            picked.append(id)
        }
        // 表紙は**選んだ先頭**。サーバーも並びの中のものしか受け取らない
        coverId = picked.first
    }

    private func load() async {
        loadFailed = false
        do {
            archive = try await environment.highlights.archive()
        } catch {
            loadFailed = true
        }
        if let existing {
            title = existing.title
            // 直すときは、いま入っているものを選び直しておく。
            // **アーカイブから外れたものは選べない**ので落ちる
            // ⚠️ `try? await` を含む if-let は構文検査が読めないので分ける
            let contents: HighlightContents?
            if let userId = auth.userId {
                contents = try? await environment.highlights.contents(userId: userId, id: existing.id)
            } else {
                contents = nil
            }
            if let contents {
                let inArchive = Set(archive.map(\.id))
                picked = contents.items.map(\.id).filter { inArchive.contains($0) }
                // **表紙は必ず並びの中のものにする。** サーバーは並びに
                // 無い表紙を断る（400）ので、アーカイブから外れた写真が
                // 表紙だった輪は、直そうとした瞬間に保存できなくなる
                let cover = contents.coverStoryId
                coverId = (cover != nil && picked.contains(cover!)) ? cover : picked.first
            }
        }
        loading = false
    }

    private func save() async {
        saving = true
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
            message = L("保存できませんでした。もう一度お試しください。",
                        "Couldn't save it. Please try again.")
        }
        saving = false
    }

    private func remove() async {
        guard let existing else { return }
        saving = true
        do {
            try await environment.highlights.delete(id: existing.id)
            dismiss()
        } catch {
            message = L("削除できませんでした。もう一度お試しください。",
                        "Couldn't delete it. Please try again.")
        }
        saving = false
    }
}
