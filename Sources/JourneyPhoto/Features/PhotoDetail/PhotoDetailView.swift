import SwiftUI

struct PhotoDetailView: View {

    let photo: Photo
    /// 公開の一覧から開いたか。**個別ページが在るかの判断に使う**
    /// ——投稿直後の写真はまだページが無い（`PhotoLink`）
    var fromPublicFeed: Bool = true
    /// 同じ一覧に並んでいた写真。大きく見るときに左右へ送るのに使う
    var context: [Photo] = []

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PhotoDetailViewModel
    @State private var showReport = false
    @State private var showDeleteConfirm = false
    @State private var showEdit = false
    @State private var showViewer = false
    @State private var actionError: String?
    /// 編集して保存したあとの姿。**`photo` は `let` で書き換えられない**
    /// ——編集シートを閉じても題も説明も古いままだった（保存はできていた
    /// ので、戻って入り直すまで「保存されていない」ように見えた）
    @State private var edited: Photo?
    /// 下段の切り替え（モック6）。コメントが既定
    @State private var tab: PhotoDetailTab = .comments
    /// 「この場所のスポット」の行き先。**台帳にも写真にも辿り着けたときだけ入る**
    @State private var spotLead: SpotLead?
    @State private var isFollowing = false
    @State private var isFollowWorking = false
    /// 同じ投稿の中で、いま見ている1枚（モック6-1 の送り）
    @State private var heroPage = 0

    /// スポット詳細に渡すもの一式。台帳の1件と、突き合わせる公開写真と、
    /// 近くのスポットを出すための台帳全体
    private struct SpotLead {
        let spot: Spot
        let photos: [Photo]
        let ledger: [Spot]
    }

    /// 画面に描く1枚。編集していれば新しい方。
    private var shown: Photo { edited ?? photo }

    init(photo: Photo, fromPublicFeed: Bool = true, context: [Photo] = []) {
        self.photo = photo
        self.fromPublicFeed = fromPublicFeed
        self.context = context
        // `AppEnvironment` は init で受け取れない（EnvironmentObject は body 以降）
        _model = StateObject(wrappedValue: PhotoDetailViewModel(
            photoId: photo.id,
            social: SocialService(api: APIClient(tokenProvider: CognitoTokenProvider()))
        ))
    }

    /// 大きく見るときに送れる並び。**渡されていなければこの1枚だけ**
    /// ——「送れるはずなのに送れない」より、送りが出ない方がまし。
    var siblings: [Photo] { context.isEmpty ? [photo] : context }

    private var ownerId: String? { photo.userId ?? photo.uploadedBy }
    private var isMine: Bool { ownerId != nil && ownerId == auth.userId }

    // **段ごとに割ってある。** 一本の長い `ScrollView { … }` にすると、Swift の
    // 型検査が現実的な時間で終わらなくなることがある
    // （"unable to type-check this expression in reasonable time"）。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageButton
                details
            }
            .padding(.bottom, 32)
        }
        // **入力欄は画面の下に貼る**（モック6）。コメント欄が本文の
        // 途中にあると、長い説明の写真では入力欄まで辿り着く前に
        // 書く気が失せる。`safeAreaInset` はスクロールの底の余白も
        // 足してくれるので、最後のコメントが入力欄の下に隠れない
        .safeAreaInset(edge: .bottom) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
        .task(id: auth.userId) {
            model.setSignedIn(auth.userId != nil)
            await model.load()
        }
        .task(id: shown.spotId) { await loadSpotLead() }
        .task(id: ownerId) {
            await model.loadOwner(ownerId, profiles: environment.profiles)
            // **フォローしているかは、その人を見に行かずに知りたい。**
            // 自分のフォロー一覧から引く（相手のページを開かずに済む）
            guard let me = auth.userId, let ownerId, me != ownerId else { return }
            let ids = (try? await environment.social.myFollowingIds()) ?? []
            isFollowing = ids.contains(ownerId)
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(photoId: photo.id, ownerId: ownerId)
        }
        // **閉じたら引き直す。** 保存はできているのに画面が古いままだと、
        // 保存できていないように見える
        .sheet(isPresented: $showEdit, onDismiss: { Task { await reloadPhoto() } }) {
            NavigationStack { EditPhotoView(photo: shown) }
        }
        .fullScreenCover(isPresented: $showViewer) {
            PhotoViewerView(
                photos: siblings,
                index: siblings.firstIndex(where: { $0.id == photo.id }) ?? 0,
                isLiked: model.liked,
                isSignedIn: auth.userId != nil,
                onDoubleTapLike: { Task { await model.toggleLike() } }
            )
        }
        .alert(L("この写真を削除しますか？", "Delete this photo?"), isPresented: $showDeleteConfirm) {
            Button(Labels.Common.delete, role: .destructive) { Task { await deletePhoto() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("元に戻せません。画像そのものも消えます。", "This cannot be undone. The image file is deleted too."))
        }
    }

    /// 押すと大きく見る（隣の写真へも送れる）。
    ///
    /// **同じ投稿が2枚以上なら、ここで左右に送れる**（モック6-1 の「1/10」）。
    /// 束は `groupId` が作る——行は1枚ずつのままなので、個別ページは変わらない
    @ViewBuilder
    private var imageButton: some View {
        let group = PhotoGroups.siblings(of: shown, in: siblings)
        if group.count > 1 {
            ZStack(alignment: .topTrailing) {
                TabView(selection: $heroPage) {
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, item in
                        Button {
                            showViewer = true
                        } label: {
                            RemoteImage(url: item.detailImageURL, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(item.accessibilityText)
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .aspectRatio(4.0 / 3.0, contentMode: .fit)

                Text("\(min(heroPage + 1, group.count))/\(group.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(12)
                    .allowsHitTesting(false)
            }
        } else {
            Button {
                showViewer = true
            } label: {
                RemoteImage(url: shown.detailImageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(shown.accessibilityText)
            }
            .buttonStyle(.plain)
        }
    }

    /// **Web の写真ページ（`app/photo/[id]/PhotoPageClient.tsx`）と同じ順・同じ寸法。**
    ///
    ///     題        text-2xl font-bold
    ///     カテゴリ   丸チップ（bg-white/10・ring-white/10・text-xs・white/70）
    ///     説明      text-sm/base・white/80・段落の間は mt-3
    ///     撮影地     丸チップ（ピンは sky-400）
    ///     タグ      小さい丸チップ（white/50）
    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleText
            authorRow
            paragraphs
            locationLink
            spotLink
            metaRows
            Divider().padding(.vertical, 4)
            socialBar
            tabPicker
            tabContent
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var titleText: some View {
        let category = shown.category.map { Labels.Category.name($0) } ?? ""
        if !shown.displayTitle.isEmpty || !category.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !shown.displayTitle.isEmpty {
                    // **題は写真の次に来る主役。** 28 → 34pt の太字
                    Text(shown.displayTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineSpacing(2)
                }
                if !category.isEmpty {
                    NavigationLink {
                        TagPhotosView(kind: .category(shown.category ?? ""))
                    } label: {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(WebTheme.muted2)
                            .webChip(prominent: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var locationLink: some View {
        if let location = shown.location, !location.isEmpty {
            NavigationLink {
                TagPhotosView(kind: .location(location))
            } label: {
                // **札（チップ）をやめた。** 題のすぐ下に置くと、
                // 丸い背景が題の邪魔をする。素の行の方が写真に近い
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle")
                    Text(location)
                        .lineLimit(1)
                }
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.65))
                .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    /// 「この場所のスポット」（モック6 の撮影地の行に添える導線）。
    ///
    /// **台帳に無ければ出さない。** 写真の `spotId` は撮影者が付けたものだが、
    /// 台帳から消えていることも、台帳自体が取れないこともある。
    /// 行き先（`SpotDetailView`）は突き合わせる写真も要るので、
    /// それが引けなかった回も出さない——「この場所の写真（0）」と
    /// 見せるより、行を出さない方が正直。
    ///
    /// 行の文字は台帳の名前。写真の `location` と綴りが違うことがあるので、
    /// 一般語（「この場所」）ではなく**行き先の名前**を出す
    @ViewBuilder
    private var spotLink: some View {
        if let lead = spotLead {
            NavigationLink {
                SpotDetailView(spot: lead.spot, photos: lead.photos, ledger: lead.ledger)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lead.spot.name)
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.65))
                            .lineLimit(1)
                        Text(L("撮影スポットの詳細", "Photo spot details"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.muted2)
                }
                .foregroundStyle(Color.white.opacity(0.65))
                .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    /// 説明。Web は `text-white/80` に `leading-relaxed`、段落の間は `mt-3`
    private var paragraphs: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(shown.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.callout)
                    .lineSpacing(4)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 作者（モック6-2）。アバター・名前・@ユーザー名・フォロー。
    ///
    /// **@ユーザー名は取れたときだけ。** 写真の行は表示名しか持っていない
    /// ので、投稿者の公開プロフィールを1回だけ引く。取れなければ名前だけ
    /// ——「@」だけの行を作らない。
    ///
    /// **認証バッジは出さない**（モックにはあるが、サーバーに判定が無い）。
    @ViewBuilder
    private var authorRow: some View {
        if let ownerId {
            HStack(spacing: 10) {
                NavigationLink {
                    UserProfileView(userId: ownerId)
                } label: {
                    HStack(spacing: 10) {
                        RemoteImage(url: UserProfile.profileAssetURL(
                            userId: ownerId, suffix: nil, cacheBust: nil),
                                    placeholderSymbol: "person.crop.circle.fill")
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.owner?.name ?? shown.displayName ?? L("投稿者", "Poster"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                                .lineLimit(1)
                            if let username = model.owner?.username, !username.isEmpty {
                                Text("@\(username)")
                                    .font(.caption)
                                    .foregroundStyle(WebTheme.faint)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                if !isMine, auth.userId != nil {
                    followButton(ownerId)
                }
            }
            // 撮影日時と撮影地は作者の下に1行で（モック6-2）
            if let line = takenLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
            }
        }
    }

    /// 「2024年5月12日 ・ サントリーニ島, ギリシャ」。**持っているものだけ**
    private var takenLine: String? {
        let place = (shown.location ?? "").trimmingCharacters(in: .whitespaces)
        let day = shown.date ?? ""
        let parts = [day, place].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    private func followButton(_ userId: String) -> some View {
        Button {
            Task { await toggleFollow(userId) }
        } label: {
            Text(isFollowing ? L("フォロー中", "Following") : L("フォロー", "Follow"))
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(isFollowing ? AnyShapeStyle(WebTheme.surface)
                                        : AnyShapeStyle(WebTheme.accentBackground),
                            in: Capsule())
                .foregroundStyle(isFollowing ? WebTheme.foreground : WebTheme.accentText)
        }
        .buttonStyle(.plain)
        .disabled(isFollowWorking)
        .opacity(isFollowWorking ? 0.5 : 1)
    }

    /// **返ってきた状態を使う。** 自分で反転すると、失敗した回に
    /// 画面だけフォロー中になる
    private func toggleFollow(_ userId: String) async {
        guard !isFollowWorking else { return }
        isFollowWorking = true
        defer { isFollowWorking = false }
        if isFollowing {
            let result = try? await environment.social.unfollow(userId: userId)
            if let result { isFollowing = result.following }
        } else {
            let result = try? await environment.social.follow(userId: userId)
            if let result { isFollowing = result.following }
        }
    }

    @ViewBuilder
    private var metaRows: some View {
        if let tags = shown.tags, !tags.isEmpty {
            TagRow(tags: tags)
        }
        if let exif = shown.exif {
            ExifRow(exif: exif)
        }
        if let song = shown.song {
            SongRow(song: song)
        }
    }

    // MARK: - 操作

    private var menu: some View {
        Menu {
            // **共有するのは画像ではなくページ。** 生の画像を送ると、
            // 受け取った人に題も説明も撮影地も出ない。
            // モック6 の SNS 別ボタン（Instagram・X・LINE…）は作らない
            // ——各社の URL スキームを `LSApplicationQueriesSchemes` に
            // 登録し、入っていないアプリの分を隠す仕掛けが要る。標準の
            // 共有シートなら入っているアプリだけが並ぶ
            if let url = PhotoLink.url(photoId: photo.id,
                                       isPublished: fromPublicFeed && shown.published != false) {
                ShareLink(item: url) { Label(L("共有", "Share"), systemImage: "square.and.arrow.up") }
            }
            if isMine {
                // **Menu の中に NavigationLink を置かない。** メニューの中身は
                // ナビゲーションの外側に出るので押しても進まない。シートで出す
                Button { showEdit = true } label: {
                    Label(L("編集", "Edit"), systemImage: "pencil")
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label(Labels.Common.delete, systemImage: "trash")
                }
            } else {
                // **通報とブロックは1タップで届くところに置く**（審査で見られる）
                Button { showReport = true } label: {
                    Label(L("通報する", "Report"), systemImage: "flag")
                }
                if let ownerId {
                    Button(role: .destructive) { Task { await block(ownerId) } } label: {
                        Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .webToolbarIcon()
                .accessibilityLabel(L("この写真の操作", "More actions"))
        }
    }

    private var socialBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    Task {
                        await model.toggleLike()
                        // 端末側のハートも合わせる（圏外でも一覧が出る）
                        favorites.set(photo.id, favorite: model.liked)
                    }
                } label: {
                    // **いちばん押されるボタンがいちばん小さかった。**
                    // 既定の字のままで 20pt ほどしか無く、指では狙いにくい
                    Label("\(model.likes)", systemImage: model.liked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(model.liked ? .pink : WebTheme.muted)
                        .webTappable()
                }
                .buttonStyle(.plain)

                // 吹き出しを押すとコメントの札へ。**数は取れたときだけ**
                // ——読み込み前・圏外に「0」を出すと「まだ無い」と読まれる
                Button {
                    tab = .comments
                } label: {
                    if let count = model.commentCount {
                        Label("\(count)", systemImage: "bubble.right")
                            .font(.title2)
                            .foregroundStyle(WebTheme.faint)
                            .webTappable()
                    } else {
                        Image(systemName: "bubble.right")
                            .font(.title2)
                            .foregroundStyle(WebTheme.faint)
                            .webTappable()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PhotoDetailTab.comments.label(commentCount: model.commentCount))

                // **保存**（端末に覚える。サーバーのいいねとは別）
                Button {
                    favorites.toggle(photo.id)
                } label: {
                    Image(systemName: favorites.contains(photo.id) ? "bookmark.fill" : "bookmark")
                        .font(.title2)
                        .foregroundStyle(favorites.contains(photo.id) ? WebTheme.foreground : WebTheme.faint)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("保存", "Save"))

                // **シェア**（配るのは画像ではなくページ）
                if let url = PhotoLink.url(photoId: photo.id,
                                           isPublished: fromPublicFeed && shown.published != false) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .foregroundStyle(WebTheme.faint)
                            .webTappable()
                    }
                }

                Spacer()
            }
            if let message = model.errorMessage ?? actionError {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    /// 下段の札（モック6: コメント（N） / 関連写真）。
    /// 一覧の絞り込みや `UserProfileView` と同じ `Picker(.segmented)`
    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(PhotoDetailTab.allCases) { item in
                Text(item.label(commentCount: model.commentCount)).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .comments:
            commentSection
        case .related:
            RelatedPhotosRow(photo: shown, showsHeading: false)
        }
    }

    /// 画面の下に貼る入力欄。**ログイン中で、コメントの札を開いているときだけ**
    /// ——関連写真を見ている下に「コメントを書く」が居座ると、何への
    /// コメントか分からなくなる
    @ViewBuilder
    private var composer: some View {
        if auth.userId != nil, tab == .comments {
            HStack(spacing: 8) {
                TextField(L("コメントを書く", "Write a comment"), text: $model.draftComment, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await model.postComment() }
                } label: {
                    Image(systemName: "paperplane")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.send)
                .disabled(model.isPosting || model.draftComment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(WebTheme.background)
        }
    }

    @ViewBuilder
    private var commentSection: some View {
        if model.comments.isEmpty {
            // **空の理由を分ける。** 引けなかった回に「まだありません」と
            // 出すと、書いてあるコメントが消えたように見える
            if model.commentsUnavailable {
                Text(L("コメントを読み込めませんでした", "Couldn't load comments"))
                    .font(.callout)
                    .foregroundStyle(WebTheme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else if model.commentCount == 0 {
                Text(L("まだコメントはありません", "No comments yet"))
                    .font(.callout)
                    .foregroundStyle(WebTheme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.comments) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        // **退会した人にはプロフィールへの導線を出さない**
                        if comment.isFromDeletedUser {
                            Text(comment.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        } else {
                            NavigationLink {
                                UserProfileView(userId: comment.uid)
                            } label: {
                                Text(comment.name).font(.caption.weight(.semibold))
                            }
                        }
                        Spacer()
                        // **写真の持ち主も消せる。** サーバーは持ち主にも
                        // 許している（`comments.ts` の `ownerId !== uid`）のに、
                        // アプリは自分が書いたぶんしか出していなかった
                        // ——UGC のアプリは「不快な書き込みを持ち主が取り除ける」
                        // ことを審査（1.2）で見られる
                        if comment.uid == auth.userId || isMine {
                            Button(Labels.Common.delete) { Task { await model.deleteComment(comment) } }
                                .font(.caption2)
                        }
                    }
                    Text(comment.text).font(.callout)
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// 「この場所のスポット」の行き先を揃える。
    ///
    /// 台帳（`SpotService`）は取れなければ空を返すので、`spotId` が
    /// 引き当たらなければ行は出ない。**本番の台帳は 2026-09-21 時点で
    /// 0件・`spotId` を持つ写真も 0/30** なので、いまはどの写真でも出ない
    private func loadSpotLead() async {
        spotLead = nil
        guard let spotId = shown.spotId, !spotId.isEmpty else { return }
        let ledger = await environment.spots.fetchSpots()
        guard let spot = SpotDirectory.spot(id: spotId, in: ledger) else { return }
        guard let photos = try? await environment.gallery.fetchPhotos() else { return }
        spotLead = SpotLead(spot: spot, photos: photos, ledger: ledger)
    }

    private func block(_ userId: String) async {
        do {
            try await environment.moderation.block(userId: userId)
            // 押したあと実際に消す（公開一覧は静的なので端末で落とす）
            hidden.block(userId)
            await environment.gallery.setHidden(
                userIds: hidden.blockedUserIds,
                photoIds: hidden.reportedPhotoIds
            )
            actionError = L("ブロックしました。おたがいの投稿が見えなくなります。", "Blocked. You won't see each other's posts.")
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }

    /// 編集の帰りに、自分の一覧から1枚だけ引き直す。
    ///
    /// **引けなくても画面は壊さない**（圏外なら古いまま出す方がまし）。
    private func reloadPhoto() async {
        guard isMine else { return }
        guard let fresh = try? await environment.photos.myPhoto(id: photo.id) else { return }
        edited = fresh
    }

    private func deletePhoto() async {
        do {
            try await environment.photos.delete(photoId: photo.id)
            // **消した写真の画面に留まらせない。** 残ると、もう無いものを
            // 編集したり、もう一度削除を押したりできてしまう
            dismiss()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}

private struct TagRow: View {
    let tags: [String]
    var body: some View {
        // 横に流さず折り返す。タグは59種あり、長い並びは画面外に出る
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                NavigationLink {
                    TagPhotosView(kind: .tag(tag))
                } label: {
                    // Web: `bg-white/5 ring-1 ring-white/10 text-xs text-white/50`
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .webChip()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 撮影情報の札。
///
/// **提案どおりの二段構え**（2026-09-21・owner から絵で）:
///
///     撮影情報                              📷
///     絞り        シャッター      ISO
///     f/1.8       1/277s         64        ← 大きく（28pt）
///     ──────────────────────────
///     CAMERA
///     Apple iPhone 16 Pro Max              ← 22pt
///     LENS
///     iPhone 16 Pro Max back triple camera
///     FOCAL LENGTH
///     7mm
///
/// **撮った条件（絞り・シャッター・ISO）を主役にする。** 写真を見て
/// 「どう撮ったか」を知りたい人がまず探すのはこの3つで、機材名は
/// その次。以前は6項目を同じ大きさで並べていたので、**どれも目に
/// 入らなかった**。
private struct ExifRow: View {
    let exif: Photo.Exif

    /// **畳んでおく。** 指示書 7-3:「一般ユーザーにとって情報が多すぎない
    /// よう、折りたたみ可能な撮影情報セクションにまとめてください」。
    /// 写真を見に来た人には要らないが、**カメラ好きには外せない**ので
    /// 消しはしない。開いた状態は画面を離れるまで覚える
    @State private var expanded = false

    /// 機種名。**`CameraName.deduped` を通す**——保存済みの値には
    /// メーカー名が二重に残っている行があり（実データ）、そのまま出すと
    /// 「Hasselblad Hasselblad X2D II 100C」と画面に見える
    var camera: String? { CameraName.deduped(exif.camera) }

    private struct Item: Identifiable {
        let id: String
        let value: String
    }

    /// 上段（大きく出す3つ）。**無いものは詰める**——空の柱を立てない
    private var primary: [Item] {
        [
            (L("絞り", "Aperture"), exif.aperture),
            (L("シャッター", "Shutter"), exif.exposure),
            ("ISO", exif.iso.map { String($0) }),
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Item(id: label, value: value)
        }
    }

    /// 下段（機材）。長い値があるので縦に積む
    private var secondary: [Item] {
        [
            (L("カメラ", "CAMERA"), camera),
            (L("レンズ", "LENS"), exif.lens),
            (L("焦点距離", "FOCAL LENGTH"), exif.focalLength),
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Item(id: label, value: value)
        }
    }

    var body: some View {
        if !primary.isEmpty || !secondary.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack {
                        Text(L("撮影情報", "Shot with"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(WebTheme.foreground)
                        Spacer()
                        Image(systemName: "camera")
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.4))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.muted2)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? L("撮影情報を閉じる", "Hide camera info")
                                             : L("撮影情報を開く", "Show camera info"))

                if expanded, !primary.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(primary) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.id)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.5))
                                Text(item.value)
                                    // **ここがいちばん読まれる。** 28pt の太字
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(WebTheme.foreground)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if expanded, !primary.isEmpty, !secondary.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 16) {
                    ForEach(secondary) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.id.uppercased())
                                .font(.subheadline)
                                .tracking(0.8)
                                .foregroundStyle(Color.white.opacity(0.5))
                            // **機材だけリンクにする**（`/camera/*` の集約がある）
                            if item.id == L("カメラ", "CAMERA"), let camera {
                                NavigationLink {
                                    TagPhotosView(kind: .camera(camera))
                                } label: {
                                    Text(item.value)
                                        .font(.title3)
                                        .foregroundStyle(WebTheme.foreground)
                                        .underline(true, color: Color.white.opacity(0.25))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(item.value)
                                    .font(.title3)
                                    .foregroundStyle(WebTheme.foreground)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
