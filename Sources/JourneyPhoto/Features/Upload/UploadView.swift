import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var joined: JoinedAlbumsStore
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
            photos: PhotoService(api: api),
            discovery: DiscoveryService(api: api)
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
        .onChange(of: model.items.isEmpty) { _, empty in
            // **全部上がったら閉じる。** 途中で落ちたぶんは待ち行列に残るので、
            // 閉じずにその場でやり直せる（Web も落ちた枚数を残して伝える）
            if empty && model.savedPhoto != nil { dismiss() }
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
            sharedSection
            songSection
            albumSection
            publishSection
            errorSection
            submitSection
        }
        .task(id: joined.entries) { await model.loadAlbums(joined: joined.entries) }
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
            // **カメラを先に置く。** このアプリがネイティブである理由
            // （4.2）で、旅先でいちばん使う入口でもある
            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label(L("写真を撮る", "Take a photo"), systemImage: "camera")
                }
            }
            // **まとめて選べる**（Web の投稿画面と同じ）。一度に扱う数は
            // `maxSelection` まで——1枚ずつ題と説明を書く画面なので、
            // 多すぎるとどれを書いているか見失う
            PhotosPicker(selection: $model.pickerItems,
                         maxSelectionCount: UploadViewModel.maxSelection,
                         matching: .images,
                         photoLibrary: .shared()) {
                Label(model.items.isEmpty ? L("写真を選ぶ", "Choose photos")
                                          : L("選び直す", "Choose again"),
                      systemImage: "photo.badge.plus")
            }
        } footer: {
            Text(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。", "Photo metadata (EXIF) is removed on your device before upload. Coordinates are rounded to about 1 km."))
        }
    }

    /// 選んだ写真ごとの欄。**題・説明・撮影地は1枚ずつ**（Web と同じ）。
    @ViewBuilder
    private var detailSection: some View {
        ForEach($model.items) { $item in
            Section {
                if let preview = item.preview {
                    preview
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                }
                TextField(L("題（例: 高屋神社の雲海）", "Title (e.g. Sea of clouds at Takaya)"), text: $item.title)
                TextField(L("説明", "Description"), text: $item.caption, axis: .vertical)
                    .lineLimit(3...8)
                PlaceSearchField(location: $item.location, coords: $item.pickedCoords)
                if model.items.count > 1 {
                    Button(role: .destructive) {
                        model.remove(item.id)
                    } label: {
                        Label(L("この写真を外す", "Remove this photo"), systemImage: "trash")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            } header: {
                Text(model.items.count > 1
                     ? L("\(indexOf(item) ) 枚目", "Photo \(indexOf(item))")
                     : L("この写真について", "About this photo"))
            }
        }
    }

    /// 見出しに出す番号（1始まり）。並びが変わっても id で引き直す。
    private func indexOf(_ item: PendingPhoto) -> Int {
        (model.items.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
    }

    /// まとめて同じものが付く欄（タグ・カテゴリ）。
    private var sharedSection: some View {
        Section(L("まとめて付ける", "Applied to all")) {
            TagField(tagsText: $model.tagsText)
            CategoryField(category: $model.category)
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
                    HStack {
                        ProgressView()
                        // **何枚目かを出す。** 5枚選んだときに、進んでいるのか
                        // 止まっているのかが分からないのがいちばん不安
                        Text(model.items.count > 1
                             ? L("送信中… \(model.uploadingIndex) / \(model.items.count) 枚目",
                                 "Sending… \(model.uploadingIndex) of \(model.items.count)")
                             : L("送信中…", "Sending…"))
                    }
                } else {
                    Text(model.items.count > 1
                         ? L("\(model.items.count) 枚を投稿する", "Post \(model.items.count) photos")
                         : L("投稿する", "Post"))
                }
            }
            .disabled(!model.canSubmit)

            if model.isWorking && model.items.count > 1 {
                // **やめられるようにする。** いま上げている1枚は最後まで通す
                // （途中で切ると S3 に迷子が残る）。残りは始めない
                Button(role: .destructive) { model.cancel() } label: {
                    Text(L("残りをやめる", "Stop the rest"))
                }
            }
        }
    }
}
