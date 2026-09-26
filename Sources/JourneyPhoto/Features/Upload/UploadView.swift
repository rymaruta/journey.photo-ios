import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var joined: JoinedAlbumsStore
    @StateObject private var model: UploadViewModel
    @State private var showCamera = false
    @State private var showSongPicker = false
    @State private var showLibrary = false
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
        // 板 22: 左に ×、右に真鍮の「投稿する」（下の大きいボタンはやめる）
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(WebTheme.foreground)
                }
                .accessibilityLabel(Labels.Common.close)
                // 🔴 **送っている間は閉じさせない。** 閉じても送信は裏で続き、
                // 残りの写真が公開され、失敗の知らせは閉じた画面に書かれていた。
                // 途中でやめるのは送信中の「やめる」（`model.cancel()`）
                .disabled(model.isWorking)
            }
            if auth.userId != nil {
                ToolbarItem(placement: .confirmationAction) { submitButton }
            }
        }
        .interactiveDismissDisabled(model.isWorking)
        .onChange(of: model.didPostAll) { _, posted in
            // **全部上がったときだけ閉じる。** 「待ち行列が空」で見ると、
            // 選び直しの読み込み中（一度空にする）にも閉じてしまい、
            // 打った文字ごと消える
            if posted { dismiss() }
        }
    }

    /// **段ごとに割ってある。** 一本の長い式にすると、Swift の型検査が
    /// 現実的な時間で終わらなくなることがある
    /// （"unable to type-check this expression in reasonable time"）。
    /// 落ちたときに、どの段かがすぐ分かる利点もある。
    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // **知らせは上に。** 投稿は右上で押すので、下に出すと画面の外になる
                progressAndErrors
                strip
                if model.items.count > 1 { groupChoice }
                detailSection
                rowsCard
                tagsAndCategory
                // 板: 本文の最後に 11px の注記
                Text(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。", "Photo metadata (EXIF) is removed on your device before upload. Coordinates are rounded to about 1 km."))
                    .font(.caption2)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
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
        // **まとめて選べる**（Web の投稿画面と同じ）。一度に扱う数は
        // `maxSelection` まで——1枚ずつ題と説明を書く画面なので、
        // 多すぎるとどれを書いているか見失う
        .photosPicker(isPresented: $showLibrary,
                      selection: $model.pickerItems,
                      maxSelectionCount: UploadViewModel.maxSelection,
                      matching: .images,
                      // **前の選択に印を付けて開く。** 無いと毎回まっさらで開き、
                      // 「追加」が選び直しになる（前の写真と打った題が消える）
                      photoLibrary: .shared())
    }

    /// 右上の「投稿する」（板: 真鍮・15pt semibold）。送信中は何枚目かを出す
    private var submitButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            if model.isWorking {
                // **何枚目かを出す。** 5枚選んだときに、進んでいるのか
                // 止まっているのかが分からないのがいちばん不安
                HStack(spacing: 6) {
                    ProgressView().tint(WebTheme.accent)
                    if model.items.count > 1 {
                        Text("\(model.uploadingIndex)/\(model.items.count)")
                            .font(JPFont.mono(13, relativeTo: .footnote))
                    }
                }
            } else if model.isLoadingPicked {
                ProgressView().tint(WebTheme.accent)
            } else {
                Text(L("投稿する", "Post"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(model.canSubmit ? WebTheme.accent : WebTheme.faint)
        .disabled(!model.canSubmit)
        .accessibilityLabel(model.isWorking
                            ? L("送信中 \(model.uploadingIndex) / \(model.items.count) 枚目",
                                "Sending \(model.uploadingIndex) of \(model.items.count)")
                            : (model.items.count > 1
                               ? L("\(model.items.count) 枚を投稿する", "Post \(model.items.count) photos")
                               : L("投稿する", "Post")))
    }

    /// 選んだ写真の帯（板: 96×120・角丸12、右上に外す丸、左下に番号、最後に「追加」）。
    ///
    /// **サーバーは1行＝1枚**で、選んだ枚数ぶんの投稿になる（題も説明も1枚ずつ）。
    /// 「まとめる」は見せ方だけ（`groupChoice`）
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    thumb(item, index: index)
                }
                addTile
            }
            // 外す丸が上と右にはみ出すぶん
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
    }

    private func thumb(_ item: PendingPhoto, index: Int) -> some View {
        Group {
            if let preview = item.preview {
                preview.resizable().aspectRatio(contentMode: .fill)
            } else {
                WebTheme.surface
            }
        }
        .frame(width: 96, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomLeading) {
            Text("\(index + 1)")
                .font(JPFont.mono(10))
                .foregroundStyle(Color.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 3)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(6)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                model.remove(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(Color(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2c / 255.0), in: Circle())
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                    // 押せる範囲は 44pt（見た目は 28pt）
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 送っている間は並びを変えさせない（送る順の番号がずれる）
            .disabled(model.isWorking)
            .offset(x: 14, y: -14)
            .accessibilityLabel(L("\(index + 1)枚目を外す", "Remove photo \(index + 1)"))
        }
    }

    /// 「追加」の点線の枠。**カメラを先に置く**（このアプリがネイティブである
    /// 理由＝4.2 で、旅先でいちばん使う入口でもある）
    private var addTile: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    Label(L("写真を撮る", "Take a photo"), systemImage: "camera")
                }
            }
            Button { showLibrary = true } label: {
                Label(L("ライブラリから選ぶ", "Choose from library"), systemImage: "photo.on.rectangle")
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 20, weight: .regular))
                Text(L("追加", "Add")).font(.caption2)
            }
            .foregroundStyle(WebTheme.muted2)
            .frame(width: 96, height: 120)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(L("写真を追加", "Add photos"))
        // 🔴 **送っている間は足させない。** 足した写真は送信の終わりの `reset()` で
        // 黙って消え、送っている束の印まで変わっていた
        .disabled(model.isWorking)
    }

    /// 「1つの投稿にまとめる／それぞれ別の投稿」（板: 2択・選んでいる側は白）。
    ///
    /// **行は1枚ずつのまま。** まとめても個別ページとサイトマップは変わらない
    /// ——写真1枚＝1ページがこのサイトの検索での面積なので、1行にまとめると
    /// 出せるページが減る。束ねるのは見せ方だけ。
    private var groupChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                segment(L("1つの投稿にまとめる", "Post as one"), selected: model.groupsAsOnePost) {
                    model.groupsAsOnePost = true
                }
                segment(L("それぞれ別の投稿", "Separate posts"), selected: !model.groupsAsOnePost) {
                    model.groupsAsOnePost = false
                }
            }
            .padding(3)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            Text(model.groupsAsOnePost
                 ? L("一覧では1枚のカードにまとまり、左右に送れます（題と説明は1枚ずつ書きます）",
                     "Shown as one card you can swipe (each photo keeps its own title)")
                 : L("それぞれ別の投稿として並びます", "Shown as separate posts"))
                .font(.caption2)
                .foregroundStyle(WebTheme.faint)
                .padding(.horizontal, 4)
        }
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(selected ? WebTheme.accentBackground : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 選んだ写真ごとの欄。**題・説明・撮影地は1枚ずつ**（Web と同じ）。
    private var detailSection: some View {
        ForEach($model.items) { $item in
            VStack(alignment: .leading, spacing: 14) {
                if model.items.count > 1 {
                    JPSectionTitle(L("\(indexOf(item)) 枚目", "Photo \(indexOf(item))"))
                }
                JPField(L("タイトル", "Title")) {
                    TextField(L("例: 高屋神社の雲海", "e.g. Sea of clouds at Takaya"),
                              text: $item.title)
                        .onChange(of: item.title) { _, value in
                            item.title = PostLimits.clamp(value, limit: PostLimits.title)
                        }
                }
                count(item.title, limit: PostLimits.title)
                JPField(L("説明文", "Description"), multiline: true) {
                    TextField(L("どんな写真ですか", "What is this photo about?"),
                              text: $item.caption, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: item.caption) { _, value in
                            item.caption = PostLimits.clamp(value, limit: PostLimits.description)
                        }
                }
                count(item.caption, limit: PostLimits.description)
                VStack(alignment: .leading, spacing: 6) {
                    JPSectionTitle(L("撮影地", "Place"))
                    PlaceSearchField(location: $item.location, coords: $item.pickedCoords)
                }
            }
        }
    }

    /// 上限が近いときだけ文字数を出す。
    ///
    /// **数はいつも出さない。** 書いている最中に数字が目に入ると、
    /// 書ける文章を短く削ってしまう。2割を切ってから出す（`PostLimits`）
    @ViewBuilder
    private func count(_ text: String, limit: Int) -> some View {
        if PostLimits.shouldShowCount(text, limit: limit) {
            Text("\(text.count)/\(limit)")
                .font(JPFont.mono(11))
                .foregroundStyle(text.count >= limit ? WebTheme.danger : WebTheme.faint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, -8)
        }
    }

    /// 見出しに出す番号（1始まり）。並びが変わっても id で引き直す。
    private func indexOf(_ item: PendingPhoto) -> Int {
        (model.items.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
    }

    /// まとめて付く行（板: 札に 曲・入れるアルバム・公開範囲。カテゴリも同じ形で）
    private var rowsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            JPCard {
                songRow
                if !model.albums.isEmpty {
                    JPCardDivider()
                    albumRow
                }
                JPCardDivider()
                audienceRow
                // **選ぶ先が空なら誰にも見えない。** 選びに行く口をここに置く
                if model.published && model.audience == .closeFriends {
                    JPCardDivider()
                    NavigationLink { CloseFriendsView() } label: {
                        JPRowLabel(title: L("親しい友達を選ぶ", "Pick close friends"), systemImage: "star")
                    }
                    .buttonStyle(JPRowButtonStyle())
                }
                JPCardDivider()
                NavigationLink {
                    ScrollView {
                        CategoryField(category: $model.category).padding(16)
                    }
                    .webScreen()
                    .navigationTitle(L("カテゴリ", "Category"))
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    JPRowLabel(title: L("カテゴリ", "Category"), systemImage: "square.grid.2x2",
                               value: model.category.isEmpty ? L("選ぶ", "Choose") : model.category)
                }
                .buttonStyle(JPRowButtonStyle())
            }
            // 付けた曲は試し聴きできる形で出す（アートワーク・アーティスト・再生）
            if let song = model.song {
                SongRow(song: song)
            }
            // 公開範囲の説明（何が起きるかを先に言う）
            Text(model.published
                 ? model.audience.photoNote
                 : L("非公開の写真は、あなた以外には見えません。あとから公開できます。",
                     "Private photos stay yours. You can publish them later."))
                .font(.caption2)
                .foregroundStyle(WebTheme.faint)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var songRow: some View {
        if let song = model.song {
            Menu {
                Button { showSongPicker = true } label: { Label(L("曲を変える", "Change song"), systemImage: "music.note") }
                Button(role: .destructive) { model.song = nil } label: { Label(L("曲を外す", "Remove song"), systemImage: "xmark") }
            } label: {
                JPRowLabel(title: L("曲（任意）", "Song (optional)"), systemImage: "music.note", value: song.title)
            }
            .buttonStyle(JPRowButtonStyle())
        } else {
            Button { showSongPicker = true } label: {
                JPRowLabel(title: L("曲（任意）", "Song (optional)"), systemImage: "music.note",
                           value: L("曲を付ける", "Add a song"))
            }
            .buttonStyle(JPRowButtonStyle())
        }
    }

    private var albumRow: some View {
        Menu {
            Button { model.selectedAlbumId = nil } label: {
                choiceLabel(L("入れない", "None"), selected: model.selectedAlbumId == nil)
            }
            ForEach(model.albums) { album in
                Button { model.selectedAlbumId = album.id } label: {
                    choiceLabel(albumTitle(album), selected: model.selectedAlbumId == album.id)
                }
            }
        } label: {
            JPRowLabel(title: L("入れるアルバム", "Add to album"), systemImage: "rectangle.stack",
                       value: model.albums.first { $0.id == model.selectedAlbumId }.map(albumTitle) ?? L("入れない", "None"))
        }
        .buttonStyle(JPRowButtonStyle())
    }

    private func albumTitle(_ album: Album) -> String {
        album.title.isEmpty ? L("無題のアルバム", "Untitled album") : album.title
    }

    /// 公開範囲（板: 1行。全体・フォロワー・親しい友達・非公開の4択）
    private var audienceRow: some View {
        Menu {
            ForEach(Audience.allCases) { choice in
                Button {
                    model.published = true
                    model.audience = choice
                } label: {
                    choiceLabel(choice.label, selected: model.published && model.audience == choice)
                }
            }
            Button { model.published = false } label: {
                choiceLabel(L("非公開", "Private"), selected: !model.published)
            }
        } label: {
            JPRowLabel(title: L("公開範囲", "Visibility"),
                       systemImage: model.published ? model.audience.systemImage : "lock",
                       value: model.published ? model.audience.label : L("非公開", "Private"))
        }
        .buttonStyle(JPRowButtonStyle())
    }

    /// メニューの1項目（選んでいるものに印）
    @ViewBuilder
    private func choiceLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    /// タグ（まとめて同じものが付く）
    private var tagsAndCategory: some View {
        TagField(tagsText: $model.tagsText)
    }

    /// 送信の途中・失敗の知らせと、残りをやめる口
    @ViewBuilder
    private var progressAndErrors: some View {
        if let error = model.errorMessage {
            Text(error).foregroundStyle(WebTheme.danger).font(.callout)
        }
        if model.isWorking && model.items.count > 1 {
            // **やめられるようにする。** いま上げている1枚は最後まで通す
            // （途中で切ると S3 に迷子が残る）。残りは始めない
            Button(role: .destructive) { model.cancel() } label: {
                Text(L("残りをやめる", "Stop the rest")).jpPillButton(.outline)
            }
            .buttonStyle(.plain)
        }
    }
}
