import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

/// ストーリーを投稿する。24時間で消える。
struct StoryComposerView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var drafts: StoryDraftStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var prepared: ImagePreparer.Prepared?
    @State private var preview: Image?
    /// 写真の上に置いた文字。**投稿するときに画像へ焼き込む**
    /// （サーバーの `caption` は文字列1本で、位置を持てない）
    @State private var overlays: [TextOverlay] = []
    @State private var caption = ""
    @State private var location = ""
    @State private var showCamera = false
    @State private var isWorking = false
    /// ストーリーのBGM（30秒の試聴だけ）と、表示秒数
    @State private var song: Photo.Song?
    @State private var durationSec = StoryService.defaultDurationSec
    @State private var showSongPicker = false
    @State private var message: String?
    /// 前に書きかけて閉じたもの。**開いた直後に一度だけ尋ねる**
    @State private var showRestore = false

    var body: some View {
        Form {
            Section {
                if let preview {
                    // **写真の上を直接つまんで文字を置く。**
                    // 入力欄で座標を打たせない
                    TextOverlayEditor(preview: preview, overlays: $overlays)
                }
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: {
                        Label(L("写真を撮る", "Take a photo"), systemImage: "camera")
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(preview == nil ? L("写真を選ぶ", "Choose a photo") : L("別の写真を選ぶ", "Choose another photo"), systemImage: "photo.badge.plus")
                }
            } footer: {
                Text(L("ストーリーは24時間で消えます。撮影情報（EXIF）は端末で取り除いてから送ります。", "Stories disappear after 24 hours. Photo metadata is removed on your device."))
            }
            .listRowBackground(Color.clear)

            Section {
                TextField(L("ひとこと", "Caption"), text: $caption)
                TextField(L("撮影地（任意）", "Place (optional)"), text: $location)
            } footer: {
                // 座標は地名とセットのときだけ送る（名前の無い点は画面に出しようがない）
                Text(L("撮影地を入れると、写真に残っていた位置（約1kmに丸めたもの）も一緒に送ります。", "Adding a place also sends the photo's rounded coordinates (about 1 km)."))
            }
            .listRowBackground(Color.clear)

            // **`Section(_:content:footer:)` は本物の SwiftUI に無い**
            // （題付きは `init(_:content:)` だけ）。header / footer で書く
            Section {
                if let song {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.callout)
                            if let artist = song.artist, !artist.isEmpty {
                                Text(artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(L("外す", "Remove")) { self.song = nil }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                } else {
                    Button { showSongPicker = true } label: {
                        Label(L("曲を付ける", "Add a song"), systemImage: "music.note")
                    }
                }
                Stepper(value: $durationSec, in: StoryService.durationRange) {
                    Text(L("表示 \(durationSec) 秒", "\(durationSec) seconds"))
                }
            } header: {
                Text(L("音と長さ", "Sound and length"))
            } footer: {
                // 3秒未満は読み切れず、15秒を超えると見る側が飽きる（Web と同じ範囲）
                Text(L("3〜15秒。曲は30秒の試聴だけを使います。",
                       "3–15 seconds. Songs use the 30-second preview only."))
            }
            .listRowBackground(Color.clear)

            if let message {
                Section { Text(message).font(.callout) }
            }

            Section {
                Button {
                    Task { await post() }
                } label: {
                    if isWorking {
                        HStack { ProgressView(); Text(L("送信中…", "Sending…")) }
                    } else {
                        Text(L("ストーリーに投稿", "Post story"))
                    }
                }
                .disabled(isWorking || prepared == nil)
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
        .sheet(isPresented: $showSongPicker) {
            NavigationStack {
                SongPickerView { picked in song = picked }
            }
        }
        .navigationTitle(L("ストーリー", "Story"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.close) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // **写真が無ければ下書きにできない。** 文字だけ残しても
                // 「続きから」で出すものが無い
                Button(L("下書き保存", "Save draft")) { saveDraft() }
                    .disabled(prepared == nil || isWorking)
            }
        }
        // **開いた直後に一度だけ尋ねる。** 黙って書きかけを復元すると、
        // 新しく作りにきた人が前の写真に驚く
        .onAppear {
            drafts.use(userId: auth.userId)
            if drafts.draft != nil, prepared == nil { showRestore = true }
        }
        .alert(L("書きかけの下書きがあります", "You have a saved draft"), isPresented: $showRestore) {
            Button(L("続きから", "Continue")) { restoreDraft() }
            Button(L("捨てる", "Discard"), role: .destructive) { drafts.clear() }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("この端末に残しておいたものです。続きから編集できます。",
                   "Kept on this device. You can pick up where you left off."))
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in accept(data) }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            Task { await load(item) }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let data = try? await item.loadTransferable(type: Data.self)
        guard let data else {
            message = L("写真を読み込めませんでした", "Couldn't load the photo")
            return
        }
        accept(data)
    }

    private func accept(_ data: Data) {
        do {
            let prepared = try ImagePreparer.prepare(data: data, fileName: "story")
            self.prepared = prepared
            self.preview = UIImage(data: prepared.data).map { Image(uiImage: $0) }
            // **写真を選び直したら文字は外す。** 別の写真に前の文字が
            // 残ると、置いた場所の意味が変わる
            self.overlays = []
            self.message = nil
        } catch {
            self.prepared = nil
            self.preview = nil
            message = (error as? LocalizedError)?.errorDescription ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }

    /// 下書きにする。**焼き込む前の文字のまま残す**
    /// ——焼いてしまうと位置も色も直せなくなる（投稿と同じ片道になる）
    private func saveDraft() {
        guard let prepared else { return }
        let ok = drafts.save(
            imageData: prepared.data,
            fileName: prepared.fileName,
            contentType: prepared.contentType,
            coords: prepared.coords,
            caption: caption,
            location: location,
            overlays: overlays,
            song: song,
            durationSec: durationSec,
            savedAt: ISO8601DateFormatter().string(from: Date())
        )
        // **書けなかったことを黙らない。** 「保存しました」とだけ出して
        // 実際は消えている、が いちばん困る
        message = ok
            ? L("下書きに保存しました（この端末にだけ残ります）", "Saved as a draft on this device")
            : L("下書きを保存できませんでした（端末の空き容量を確かめてください）",
                "Couldn't save the draft — check your device's free space")
        if ok { dismiss() }
    }

    /// 「続きから」。**画像が読めなければ何も戻さない**
    private func restoreDraft() {
        guard let draft = drafts.draft, let data = drafts.imageData() else {
            drafts.clear()
            message = L("下書きの写真を読み込めませんでした", "Couldn't load the draft photo")
            return
        }
        prepared = ImagePreparer.Prepared(data: data, fileName: draft.fileName,
                                          contentType: draft.contentType,
                                          // EXIF は下書きに残していない（ストーリーは送らない）
                                          exif: nil, coords: draft.coords, takenOn: nil)
        preview = UIImage(data: data).map { Image(uiImage: $0) }
        overlays = draft.overlays
        caption = draft.caption
        location = draft.location
        song = draft.song
        durationSec = draft.durationSec
        message = nil
    }

    private func post() async {
        guard let prepared else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            _ = try await environment.stories.create(
                // **焼き込んでから送る。** 文字が無ければ元のデータを
                // そのまま渡す（読み書きの往復で画質を落とさない）
                imageData: TextOverlayRenderer.burn(overlays, into: prepared.data),
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                coords: prepared.coords,
                song: song,
                durationSec: durationSec
            )
            // 出したら下書きは要らない（残すと次に開いたときにまた尋ねる）
            drafts.clear()
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("投稿できませんでした", "Couldn't post")
        }
    }
}
