import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model: UploadViewModel
    @State private var showCamera = false
    @State private var showSongPicker = false
    @Environment(\.dismiss) private var dismiss

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
            if auth.isResolving {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.userId == nil {
                SignInView(reason: L("写真を投稿するにはログインしてください", "Sign in to post a photo"))
            } else {
                form
            }
        }
        .navigationTitle(L("投稿", "Post"))
        // **閉じる口を置く。** シートで出しているので、下に払う以外の
        // 出口が無いと戻れないと思う人が出る
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.close) { dismiss() }
            }
        }
        .onChange(of: model.savedPhoto?.id) { _, id in
            // 投稿できたら閉じる。**マイページが読み直して、その写真が並ぶ**
            // ——それが何よりの手応えになる
            if id != nil { dismiss() }
        }
    }

    /// **段ごとに割ってある。** 一本の長い `Form { … }` にすると、
    /// Swift の型検査が現実的な時間で終わらなくなることがある
    /// （"unable to type-check this expression in reasonable time"）。
    /// 落ちたときに、どの段かがすぐ分かる利点もある。
    private var form: some View {
        Form {
            pickerSection
            detailSection
            songSection
            albumSection
            publishSection
            errorSection
            submitSection
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

    private var pickerSection: some View {
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
                    Label(L("写真を撮る", "Take a photo"), systemImage: "camera")
                }
            }
            PhotosPicker(selection: $model.pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(model.previewImage == nil ? L("写真を選ぶ", "Choose a photo") : L("別の写真を選ぶ", "Choose another photo"), systemImage: "photo.badge.plus")
            }
        } footer: {
            Text(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。", "Photo metadata (EXIF) is removed on your device before upload. Coordinates are rounded to about 1 km."))
        }
    }

    private var detailSection: some View {
        Section(L("この写真について", "About this photo")) {
            TextField(L("題（例: 高屋神社の雲海）", "Title (e.g. Sea of clouds at Takaya)"), text: $model.title)
            TextField(L("説明", "Description"), text: $model.caption, axis: .vertical)
                .lineLimit(3...8)
            PlaceSearchField(location: $model.location, coords: $model.pickedCoords)
            TextField(L("タグ（カンマ区切り）", "Tags (comma separated)"), text: $model.tagsText)
                .textInputAutocapitalization(.never)
        }
    }

    private var songSection: some View {
        Section(L("曲（任意）", "Song (optional)")) {
            if let song = model.song {
                SongRow(song: song)
                Button(L("曲を外す", "Remove song")) { model.song = nil }
                    .font(.caption)
                    .buttonStyle(.borderless)
            } else {
                Button {
                    showSongPicker = true
                } label: {
                    Label(L("曲を付ける", "Add a song"), systemImage: "music.note")
                }
            }
        }
    }

    @ViewBuilder
    private var albumSection: some View {
        if !model.albums.isEmpty {
            Section(Labels.Navigation.albums) {
                Picker(L("入れるアルバム", "Add to album"), selection: $model.selectedAlbumId) {
                    Text(L("入れない", "None")).tag(String?.none)
                    ForEach(model.albums) { album in
                        Text(album.title.isEmpty ? L("無題のアルバム", "Untitled album") : album.title)
                            .tag(String?.some(album.id))
                    }
                }
            }
        }
    }

    private var publishSection: some View {
        Section {
            Toggle(L("すぐ公開する", "Publish now"), isOn: $model.published)
        } footer: {
            Text(L("公開すると、数分後にサイトの個別ページとサイトマップにも載ります。", "Once published, it appears on the site within a few minutes."))
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = model.errorMessage {
            Section {
                Text(error).foregroundStyle(.red).font(.callout)
            }
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                Task { await model.submit() }
            } label: {
                if model.isWorking {
                    HStack { ProgressView(); Text(L("送信中…", "Sending…")) }
                } else {
                    Text(L("投稿する", "Post"))
                }
            }
            .disabled(!model.canSubmit)
        }
    }
}
