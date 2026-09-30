import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var joined: JoinedAlbumsStore
    @StateObject private var model: UploadViewModel
    @State private var showCamera = false
    @State private var showSongPicker = false
    @State private var showLibrary = false
    @State private var appliedInitialSpot = false
    /// 「書きかけを捨てて閉じますか？」
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    /// 最初から入れておくタグ（今日のテーマの「参加する」から来たとき）。
    /// **入れるだけで、消せる**——決めつけない
    private let initialTag: String?
    /// スポットの画面から開いたときの行き先
    private let initialSpot: UploadSpotTarget?
    /// スポットのページに並ぶ形で1枚上がるたび・全部上がって閉じるときに呼ぶ。
    /// 渡すのは**スポットのページに並ぶ形で上がった枚数**（スポットの画面が
    /// 「投稿しました」を出すか決める）。**何度呼ばれても同じ結果になる受け手に渡す**
    private let onPosted: ((Int) -> Void)?

    init(initialTag: String? = nil, spot: UploadSpotTarget? = nil, onPosted: ((Int) -> Void)? = nil) {
        self.initialTag = initialTag
        self.initialSpot = spot
        self.onPosted = onPosted
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
                // 🔴 **書きかけを黙って捨てない**（2026-09-30）。選んだ写真と書いた題・説明が
                // 確認なしで消えていた。写真を選び始めたら一度聞く（旅行プランの日程と同じ判断）
                Button {
                    if model.hasDraft { confirmDiscard = true } else { dismiss() }
                } label: {
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
        // 書きかけがある間は、下へ払っても閉じない（× で確かめてから）
        .interactiveDismissDisabled(model.isWorking || model.hasDraft)
        .confirmationDialog(L("書きかけの投稿を捨てて閉じますか？", "Discard this post?"),
                            isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L("捨てて閉じる", "Discard"), role: .destructive) { dismiss() }
            Button(L("書き続ける", "Keep editing"), role: .cancel) { }
        } message: {
            Text(L("選んだ写真と、書いた題・説明は残りません。",
                   "The photos you picked and what you wrote won't be kept."))
        }
        // **上がった時点で知らせる。** × や下に払って閉じる時点で知らせると、
        // 一部だけ上がった・曲だけ付かなかったまま下に払って閉じた回が漏れる
        .onChange(of: model.postedToSpot) { _, n in
            if n > 0 { onPosted?(n) }
        }
        .onChange(of: model.didPostAll) { _, posted in
            // **全部上がったときだけ閉じる。** 「待ち行列が空」で見ると、
            // 選び直しの読み込み中（一度空にする）にも閉じてしまい、
            // 打った文字ごと消える
            if posted {
                onPosted?(model.postedToSpot)
                dismiss()
            }
        }
    }

    /// **段ごとに割ってある。** 一本の長い式にすると、Swift の型検査が
    /// 現実的な時間で終わらなくなることがある
    /// （"unable to type-check this expression in reasonable time"）。
    /// 落ちたときに、どの段かがすぐ分かる利点もある。
    /// どのスポットの写真として上げるか。**外せる**（普通の投稿に戻る）。
    /// 撮影地は写真ごとに直せるが、スポットの紐付けは全部の写真に同じものが付く
    private func spotBanner(_ spot: UploadSpotTarget) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(WebTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("撮影スポットの写真として投稿", "Posting to a photo spot"))
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
                Text(spot.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                model.removeSpot()
            } label: {
                Text(L("外す", "Remove"))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 送っている間は外せない——送信は1枚ごとに `spot` を読むので、束の途中で紐付けが割れる
            .disabled(model.isWorking)
            .accessibilityLabel(L("撮影スポットの紐付けを外す", "Don't link to this spot"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // **知らせは上に。** 投稿は右上で押すので、下に出すと画面の外になる
                progressAndErrors
                if let spot = model.spot { spotBanner(spot) }
                strip
                if model.items.count > 1 { groupChoice }
                detailSection
                rowsCard
                tagsAndCategory
                // 板: 本文の最後に注記（板は 11px だが、本文系の最小は 12pt）
                Text(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。", "Photo metadata (EXIF) is removed on your device before upload. Coordinates are rounded to about 1 km."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .webScreen()
        .task(id: joined.entries) { await model.loadAlbums(joined: joined.entries) }
        .onAppear {
            // 投稿で「アルバムが無い」と分かったら、端末の控えからも外す
            model.onAlbumGone = { [joined] id in joined.forget(id: id) }
            // **今日のテーマから来たときだけ、一度だけ。** 既に何か打っていれば触らない。
            // 選択画面などから戻ると onAppear はまた呼ばれるので、印が無いと
            // 利用者が空にしたタグがまた入る（印は model が持つ・送ったあとの reset で下ろす）
            model.initialTag = initialTag
            model.applyInitialTag()
            // **一度だけ入れる**（外したあとに戻さない）
            if let initialSpot, !appliedInitialSpot {
                appliedInitialSpot = true
                model.spot = initialSpot
            }
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
            // 外す丸の当たり（44pt）が上に 14pt はみ出すぶん。6 だと上の 8pt が
            // ScrollView の枠の外に出て押せなかった（縦 約36pt）
            .padding(.top, 14)
            .padding(.trailing, 6)
        }
        // 帯の見た目の位置は前のまま（上の余白を 6 → 14 にした 8pt を詰める）
        .padding(.top, -8)
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
                .font(JPFont.mono(12))
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
                Text(L("追加", "Add")).font(.caption)
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
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .padding(.horizontal, 4)
        }
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                // 押せるものは 44pt
                .frame(maxWidth: .infinity, minHeight: 44)
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
                        .onChange(of: item.title) { old, value in
                            let kept = PostLimits.limited(old: old, new: value, limit: PostLimits.title)
                            if kept != value { item.title = kept }
                        }
                }
                count(item.title, limit: PostLimits.title)
                JPField(L("説明文", "Description"), multiline: true) {
                    TextField(L("どんな写真ですか", "What is this photo about?"),
                              text: $item.caption, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: item.caption) { old, value in
                            let kept = PostLimits.limited(old: old, new: value, limit: PostLimits.description)
                            if kept != value { item.caption = kept }
                        }
                }
                count(item.caption, limit: PostLimits.description)
                VStack(alignment: .leading, spacing: 6) {
                    JPSectionTitle(L("撮影地", "Place"))
                    PlaceSearchField(location: $item.location, coords: $item.pickedCoords,
                                     near: item.prepared.coords, offersSpots: true)
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
            // 数え方はサーバーと同じ（`PostLimits.length`）——字で数えると、止まったのに
            // 「150/200」のように余っている数が出る
            Text("\(PostLimits.length(text))/\(limit)")
                .font(JPFont.mono(12))
                .foregroundStyle(PostLimits.length(text) >= limit ? WebTheme.danger : WebTheme.faint)
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
                // **送っている間は変えさせない**（公開範囲・カテゴリ・タグも同じ）。
                // 送信は1枚ごとにその時点の値を読むので、同じ束で割れる
                // （Web の AudiencePicker disabled={uploading} と同じ）。
                // アルバムは送信中に選び直せる作り（`onAlbumGone`）なので止めない
                songRow
                    .disabled(model.isWorking)
                if !model.albums.isEmpty {
                    JPCardDivider()
                    albumRow
                }
                JPCardDivider()
                audienceRow
                    .disabled(model.isWorking)
                // **選ぶ先が空なら誰にも見えない。** 選びに行く口をここに置く
                if model.published && model.audience == .closeFriends {
                    JPCardDivider()
                    NavigationLink { CloseFriendsView() } label: {
                        JPRowLabel(title: L("親しい友達を選ぶ", "Pick close friends"), systemImage: "star")
                    }
                    .buttonStyle(JPRowButtonStyle())
                    // **送っている間は積ませない。** 積んだ画面は変更が無いとき「払って閉じてよい」
                    // （`unsavedLeaveGuard`）を出すので、このシートの「送信中は払って閉じない」を
                    // 打ち消すおそれがある（どちらが勝つかは SwiftUI 任せ）
                    .disabled(model.isWorking)
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
                .disabled(model.isWorking)
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
                .font(.caption)
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
            .disabled(model.isWorking)
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
