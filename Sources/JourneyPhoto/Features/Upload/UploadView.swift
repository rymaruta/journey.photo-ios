import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model: UploadViewModel
    @State private var showCamera = false
    @State private var showSongPicker = false

    init() {
        // AppEnvironment を init で受け取れない（EnvironmentObject は body 以降）
        // ため、ここでは既定の組み立てを使う
        let api = APIClient(tokenProvider: CognitoTokenProvider())
        _model = StateObject(wrappedValue: UploadViewModel(
            uploads: UploadService(api: api),
            albums: AlbumService(api: api),
            photos: PhotoService(api: api)
        ))
    }

    var body: some View {
        Group {
            if auth.userId == nil {
                SignInView(reason: "写真を投稿するにはログインしてください")
            } else {
                form
            }
        }
        .navigationTitle("投稿")
    }

    private var form: some View {
        Form {
            Section {
                if let preview = model.previewImage {
                    preview
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                }
                // **カメラを先に置く。** このアプリがネイティブである理由
                // （4.2）で、旅先でいちばん使う入口でもある
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("写真を撮る", systemImage: "camera")
                    }
                }
                PhotosPicker(selection: $model.pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(model.previewImage == nil ? "写真を選ぶ" : "別の写真を選ぶ", systemImage: "photo.badge.plus")
                }
            } footer: {
                Text("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。")
            }

            Section("この写真について") {
                TextField("題（例: 高屋神社の雲海）", text: $model.title)
                TextField("説明", text: $model.caption, axis: .vertical)
                    .lineLimit(3...8)
                PlaceSearchField(location: $model.location, coords: $model.pickedCoords)
                TextField("タグ（カンマ区切り）", text: $model.tagsText)
                    .textInputAutocapitalization(.never)
            }

            Section("曲（任意）") {
                if let song = model.song {
                    SongRow(song: song)
                    Button("曲を外す") { model.song = nil }
                        .font(.caption)
                        .buttonStyle(.borderless)
                } else {
                    Button {
                        showSongPicker = true
                    } label: {
                        Label("曲を付ける", systemImage: "music.note")
                    }
                }
            }

            if !model.albums.isEmpty {
                Section("アルバム") {
                    Picker("入れるアルバム", selection: $model.selectedAlbumId) {
                        Text("入れない").tag(String?.none)
                        ForEach(model.albums) { album in
                            Text(album.title.isEmpty ? "無題のアルバム" : album.title)
                                .tag(String?.some(album.id))
                        }
                    }
                }
            }

            Section {
                Toggle("すぐ公開する", isOn: $model.published)
            } footer: {
                Text("公開すると、数分後にサイトの個別ページとサイトマップにも載ります。")
            }

            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }

            // **投稿できたことを言う。** 何も出ないと、送れたのか分からず
            // 二重に押される
            if model.savedPhoto != nil {
                Section {
                    Label("投稿しました。サイトへの反映には数分かかります。",
                          systemImage: "checkmark.circle")
                        .font(.callout)
                }
            }

            Section {
                Button {
                    Task { await model.submit() }
                } label: {
                    if model.isWorking {
                        HStack { ProgressView(); Text("送信中…") }
                    } else {
                        Text("投稿する")
                    }
                }
                .disabled(!model.canSubmit)
            }
        }
        .task { await model.loadAlbums() }
        .sheet(isPresented: $showSongPicker) {
            NavigationStack {
                SongPickerView { song in model.song = song }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                model.accept(capturedJPEG: data)
            }
            .ignoresSafeArea()
        }
    }
}
