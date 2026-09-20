import SwiftUI
import PhotosUI

/// ストーリーを投稿する。24時間で消える。
struct StoryComposerView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var prepared: ImagePreparer.Prepared?
    @State private var preview: Image?
    @State private var caption = ""
    @State private var location = ""
    @State private var showCamera = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let preview {
                    preview
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
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
        .navigationTitle(L("ストーリー", "Story"))
        .navigationBarTitleDisplayMode(.inline)
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
                imageData: prepared.data,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                coords: prepared.coords
            )
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("投稿できませんでした", "Couldn't post")
        }
    }
}
