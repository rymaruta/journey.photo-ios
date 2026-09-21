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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
        .task(id: auth.userId) {
            model.setSignedIn(auth.userId != nil)
            await model.load()
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

    /// 押すと大きく見る（隣の写真へも送れる）
    private var imageButton: some View {
        Button {
            showViewer = true
        } label: {
            RemoteImage(url: shown.detailImageURL, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(shown.accessibilityText)
        }
        .buttonStyle(.plain)
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
            paragraphs
            locationLink
            metaRows
            Divider().padding(.vertical, 4)
            socialBar
            commentSection
            RelatedPhotosRow(photo: shown)
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
                    Text(shown.displayTitle)
                        .font(.title.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
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
                HStack(spacing: 6) {
                    // Web はピンだけ色を持たせている（`text-sky-400`）
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))
                    Text(location)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
                .font(.subheadline)
                .webChip()
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
            // 受け取った人に題も説明も撮影地も出ない
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
                        .font(.title3)
                        .foregroundStyle(model.liked ? .pink : WebTheme.muted)
                        .webTappable()
                }
                .buttonStyle(.plain)

                Label("\(model.commentCount)", systemImage: "bubble.right")
                    .font(.title3)
                    .foregroundStyle(WebTheme.faint)
                    .frame(minHeight: WebTheme.minTapTarget)

                Spacer()

                if let ownerId, !isMine {
                    // Web の `ProfileLink`: 丸いアバター（`ring-white/20`）＋
                    // 名前。名前だけだと、誰の写真か一目で分からない
                    NavigationLink {
                        UserProfileView(userId: ownerId)
                    } label: {
                        HStack(spacing: 8) {
                            RemoteImage(url: UserProfile.profileAssetURL(
                                userId: ownerId, suffix: nil, cacheBust: nil))
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            Text(shown.displayName ?? L("投稿者", "Poster"))
                                .font(.footnote)
                                .foregroundStyle(WebTheme.faint)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let message = model.errorMessage ?? actionError {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if auth.userId != nil {
                HStack {
                    TextField(L("コメントを書く", "Write a comment"), text: $model.draftComment, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    Button(Labels.Common.send) { Task { await model.postComment() } }
                        .disabled(model.isPosting || model.draftComment.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

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

private struct ExifRow: View {
    let exif: Photo.Exif

    /// タプルには KeyPath を張れないので（`\.0` は書けない）、
    /// `ForEach` の id 用に小さな型を置く
    private struct Item: Identifiable {
        let id: String
        let value: String
    }

    /// 機種名。**`CameraName.deduped` を通す**——保存済みの値には
    /// メーカー名が二重に残っている行があり（実データ）、そのまま出すと
    /// 「Hasselblad Hasselblad X2D II 100C」と画面に見える
    var camera: String? { CameraName.deduped(exif.camera) }

    private var items: [Item] {
        let candidates: [(String, String?)] = [
            (L("レンズ", "Lens"), exif.lens),
            (L("絞り", "Aperture"), exif.aperture),
            (L("シャッター", "Shutter"), exif.exposure),
            ("ISO", exif.iso.map { String($0) }),
            (L("焦点距離", "Focal length"), exif.focalLength),
        ]
        return candidates.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Item(id: label, value: value)
        }
    }

    /// 2つずつ並べたときの1行。**レンズだけは横いっぱい**（長いので）
    private struct Row: Identifiable {
        let id: String
        let first: Item
        let second: Item?
        let wide: Bool
    }

    private var rows: [Row] {
        var result: [Row] = []
        var queue = items
        while let first = queue.first {
            queue.removeFirst()
            // レンズは機種名がまるごと入ることがあるので横いっぱい
            if first.id == L("レンズ", "Lens") {
                result.append(Row(id: first.id, first: first, second: nil, wide: true))
                continue
            }
            let second = queue.first
            if second != nil { queue.removeFirst() }
            result.append(Row(id: first.id, first: first, second: second, wide: false))
        }
        return result
    }

    @ViewBuilder
    private func spec(_ label: String, _ value: String, underlined: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.5))
            Text(value)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .underline(underlined, color: Color.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        if !items.isEmpty || camera != nil {
            // **Web の `ExifSpecs` と同じ「札」。**
            //
            //     rounded-2xl bg-white/5 ring-1 ring-white/10 p-4
            //     見出し  10px・字間広め・大文字・white/50
            //     値      13px・white/85
            //     並び    2列。**長い値（レンズ）は横いっぱい**
            //
            // 以前は「見出し 左 / 値 右」の1行ずつで、レンズ名
            // （`iPhone 16 Pro Max back triple camera 6.765mm f/1.78`）が
            // 画面の端から端まで詰まって読めなかった（実機の絵で確認）
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "camera")
                        .font(.caption2)
                    Text(L("撮影情報", "CAMERA"))
                        .font(.caption2)
                        .tracking(1.5)
                }
                .foregroundStyle(Color.white.opacity(0.5))

                if let camera {
                    // **機材だけリンクにする**（`/camera/*` の集約がある）
                    NavigationLink {
                        TagPhotosView(kind: .camera(camera))
                    } label: {
                        spec(L("カメラ", "Camera"), camera, underlined: true)
                    }
                    .buttonStyle(.plain)
                }

                // 短い値は2つずつ並べる（Web の `grid-cols-2`）
                ForEach(rows) { row in
                    if row.wide {
                        spec(row.first.id, row.first.value)
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            spec(row.first.id, row.first.value)
                            if let second = row.second {
                                spec(second.id, second.value)
                            } else {
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .padding(.top, 8)
        }
    }
}

/// タグを折り返して並べる。iOS 17 の `Layout` で書く（`LazyVGrid` だと
/// 文字数の違うタグが不自然に伸びる）。
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
