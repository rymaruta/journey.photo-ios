import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

/// ストーリーを投稿する。24時間で消える。
struct StoryComposerView: View {

    @EnvironmentObject private var environment: AppEnvironment
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

            Section {
                TextField(L("ひとこと", "Caption"), text: $caption)
                TextField(L("撮影地（任意）", "Place (optional)"), text: $location)
            } footer: {
                // 座標は地名とセットのときだけ送る（名前の無い点は画面に出しようがない）
                Text(L("撮影地を入れると、写真に残っていた位置（約1kmに丸めたもの）も一緒に送ります。", "Adding a place also sends the photo's rounded coordinates (about 1 km)."))
            }

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
        }
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
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("投稿できませんでした", "Couldn't post")
        }
    }
}
