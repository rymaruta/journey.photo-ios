import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var joined: JoinedAlbumsStore
    @StateObject private var model: UploadViewModel
    @State private var showCamera = false
    @State private var showSongPicker = false
    @Environment(\.dismiss) private var dismiss

    /// 最初から入れておくタグ（今日のテーマの「参加する」から来たとき）。
    /// **入れるだけで、消せる**——決めつけない
    private let initialTag: String?

    init(initialTag: String? = nil) {
        self.initialTag = initialTag
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
        .navigationTitle(L("新規投稿", "New post"))
        .navigationBarTitleDisplayMode(.inline)
        // **閉じる口を置く。** シートで出しているので、下に払う以外の
        // 出口が無いと戻れないと思う人が出る
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.cancel) { dismiss() }
            }
        }
        .onChange(of: model.didPostAll) { _, posted in
            // **全部上がったときだけ閉じる。** 「待ち行列が空」で見ると、
            // 選び直しの読み込み中（一度空にする）にも閉じてしまい、
            // 打った文字ごと消える
            if posted { dismiss() }
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
        .webScreen()
        .task(id: joined.entries) { await model.loadAlbums(joined: joined.entries) }
        .onAppear {
            // **今日のテーマから来たときだけ。** 既に何か打っていれば触らない
            if let initialTag, model.tagsText.isEmpty { model.tagsText = initialTag }
        }
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
            // 選んだ写真の帯（モック8-1）。**1枚ずつ外せる**
            if model.items.count > 1 {
                selectedStrip
            }
        } footer: {
            Text(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。", "Photo metadata (EXIF) is removed on your device before upload. Coordinates are rounded to about 1 km."))
        }
        .listRowBackground(Color.clear)
    }

    /// 選んだ写真の帯。
    ///
    /// **モックは「1つの投稿に10枚」だが、ここは違う。** サーバーは
    /// 1行＝1枚で、**選んだ枚数ぶんの投稿**になる（題も説明も1枚ずつ）。
    /// 帯の上にそう書く——見た目だけ真似て、できないことを匂わせない。
    private var selectedStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("選んだ写真 \(model.items.count)枚（**それぞれ別の投稿**になります）",
                   "\(model.items.count) photos — each becomes its own post"))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let preview = item.preview {
                                    preview.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    WebTheme.surface
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomLeading) {
                                Text("\(index + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6), in: Capsule())
                                    .padding(4)
                            }

                            Button {
                                model.remove(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("\(index + 1)枚目を外す", "Remove photo \(index + 1)"))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
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
                labeled(L("タイトル", "Title"), required: true,
                        text: item.title, limit: PostLimits.title) {
                    TextField(L("例: 高屋神社の雲海", "e.g. Sea of clouds at Takaya"),
                              text: $item.title)
                        .onChange(of: item.title) { _, value in
                            item.title = PostLimits.clamp(value, limit: PostLimits.title)
                        }
                }
                labeled(L("説明文", "Description"), required: false,
                        text: item.caption, limit: PostLimits.description) {
                    TextField(L("どんな写真ですか", "What is this photo about?"),
                              text: $item.caption, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: item.caption) { _, value in
                            item.caption = PostLimits.clamp(value, limit: PostLimits.description)
                        }
                }
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
            .listRowBackground(Color.clear)
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
        .listRowBackground(Color.clear)
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
        .listRowBackground(Color.clear)
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
            .listRowBackground(Color.clear)
        }
    }

    /// 公開設定。**切り替えではなく2択**（提案の絵）。
    /// トグル1つだと「いまどちらなのか」を言葉で確かめられない。
    private var publishSection: some View {
        Section {
            HStack(spacing: 10) {
                publishChoice(L("公開", "Public"),
                              note: L("みんなに見てもらえる", "Everyone can see it"),
                              systemImage: "globe", selected: model.published) {
                    model.published = true
                }
                publishChoice(L("非公開", "Private"),
                              note: L("自分だけが見られる", "Only you can see it"),
                              systemImage: "lock", selected: !model.published) {
                    model.published = false
                }
            }
        } header: {
            Text(L("公開設定", "Visibility"))
        } footer: {
            Text(model.published
                 ? L("公開すると、数分後にサイトの個別ページとサイトマップにも載ります。",
                     "Once published, it appears on the site within a few minutes.")
                 : L("非公開の写真は、あなた以外には見えません。あとから公開できます。",
                     "Private photos stay yours. You can publish them later."))
        }
        .listRowBackground(Color.clear)
    }

    private func publishChoice(_ title: String, note: String, systemImage: String,
                               selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? WebTheme.foreground : Color.clear, lineWidth: 2))
            .foregroundStyle(WebTheme.foreground)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 見出し＋必須の印＋（上限が近いときだけ）文字数。
    ///
    /// **数はいつも出さない。** 書いている最中に数字が目に入ると、
    /// 書ける文章を短く削ってしまう。2割を切ってから出す（`PostLimits`）
    @ViewBuilder
    private func labeled<Field: View>(_ title: String, required: Bool, text: String,
                                      limit: Int, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(required ? L("必須", "Required") : L("任意", "Optional"))
                    .font(.caption)
                    .foregroundStyle(required ? WebTheme.muted2 : WebTheme.faint)
                Spacer()
                if PostLimits.shouldShowCount(text, limit: limit) {
                    Text("\(text.count)/\(limit)")
                        .font(.caption)
                        .foregroundStyle(text.count >= limit ? .pink : WebTheme.faint)
                }
            }
            field()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = model.errorMessage {
            Section {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                Task { await model.submit() }
            } label: {
                if model.isLoadingPicked {
                    HStack { ProgressView(); Text(L("読み込んでいます…", "Loading…")) }
                } else if model.isWorking {
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
                    // **提案の絵の白い大ボタン。** 画面でいちばん強い場所を
                    // 「投稿する」に渡す
                    Text(model.items.count > 1
                         ? L("\(model.items.count) 枚を投稿する", "Post \(model.items.count) photos")
                         : L("投稿する", "Post"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(model.canSubmit ? WebTheme.accentBackground : WebTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(model.canSubmit ? WebTheme.accentText : WebTheme.faint)
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmit)

            if model.isWorking && model.items.count > 1 {
                // **やめられるようにする。** いま上げている1枚は最後まで通す
                // （途中で切ると S3 に迷子が残る）。残りは始めない
                Button(role: .destructive) { model.cancel() } label: {
                    Text(L("残りをやめる", "Stop the rest"))
                }
            }
        }
        .listRowBackground(Color.clear)
    }
}
