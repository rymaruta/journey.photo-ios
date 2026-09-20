import SwiftUI

struct PhotoDetailView: View {

    let photo: Photo

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var hidden: ModerationStore
    @StateObject private var model: PhotoDetailViewModel
    @State private var showReport = false
    @State private var showDeleteConfirm = false
    @State private var showEdit = false
    @State private var actionError: String?

    init(photo: Photo) {
        self.photo = photo
        // `AppEnvironment` は init で受け取れない（EnvironmentObject は body 以降）
        _model = StateObject(wrappedValue: PhotoDetailViewModel(
            photoId: photo.id,
            social: SocialService(api: APIClient(tokenProvider: CognitoTokenProvider()))
        ))
    }

    private var ownerId: String? { photo.userId ?? photo.uploadedBy }
    private var isMine: Bool { ownerId != nil && ownerId == auth.userId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: photo.detailImageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(photo.accessibilityText)

                VStack(alignment: .leading, spacing: 12) {
                    if !photo.displayTitle.isEmpty {
                        Text(photo.displayTitle)
                            .font(.title3.weight(.semibold))
                    }

                    if let location = photo.location, !location.isEmpty {
                        NavigationLink {
                            TagPhotosView(kind: .location(location))
                        } label: {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(Array(photo.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                    }

                    if let tags = photo.tags, !tags.isEmpty {
                        TagRow(tags: tags)
                    }

                    if let exif = photo.exif {
                        ExifRow(exif: exif)
                    }

                    if let song = photo.song {
                        SongRow(song: song)
                    }

                    Divider().padding(.vertical, 4)

                    socialBar
                    commentSection
                    RelatedPhotosRow(photo: photo)
                }
                .padding(.horizontal, 16)
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
        .sheet(isPresented: $showEdit) {
            NavigationStack { EditPhotoView(photo: photo) }
        }
        .alert("この写真を削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) { Task { await deletePhoto() } }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("元に戻せません。画像そのものも消えます。")
        }
    }

    // MARK: - 操作

    private var menu: some View {
        Menu {
            if let url = photo.detailImageURL {
                ShareLink(item: url) { Label("共有", systemImage: "square.and.arrow.up") }
            }
            if isMine {
                // **Menu の中に NavigationLink を置かない。** メニューの中身は
                // ナビゲーションの外側に出るので押しても進まない。シートで出す
                Button { showEdit = true } label: {
                    Label("編集", systemImage: "pencil")
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("削除", systemImage: "trash")
                }
            } else {
                // **通報とブロックは1タップで届くところに置く**（審査で見られる）
                Button { showReport = true } label: {
                    Label("通報する", systemImage: "flag")
                }
                if let ownerId {
                    Button(role: .destructive) { Task { await block(ownerId) } } label: {
                        Label("この人をブロック", systemImage: "hand.raised")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
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
                    Label("\(model.likes)", systemImage: model.liked ? "heart.fill" : "heart")
                        .foregroundStyle(model.liked ? .pink : .primary)
                }
                .buttonStyle(.plain)

                Label("\(model.commentCount)", systemImage: "bubble.right")
                    .foregroundStyle(.secondary)

                Spacer()

                if let ownerId, !isMine {
                    NavigationLink {
                        UserProfileView(userId: ownerId)
                    } label: {
                        Text(photo.displayName ?? "投稿者")
                            .font(.footnote)
                    }
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
                    TextField("コメントを書く", text: $model.draftComment, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    Button("送信") { Task { await model.postComment() } }
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
                        if comment.uid == auth.userId {
                            Button("削除") { Task { await model.deleteComment(comment) } }
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
            actionError = "ブロックしました。おたがいの投稿が見えなくなります。"
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "ブロックできませんでした"
        }
    }

    private func deletePhoto() async {
        do {
            try await environment.photos.delete(photoId: photo.id)
            actionError = "削除しました。一覧への反映には少し時間がかかります。"
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "削除できませんでした"
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
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground), in: Capsule())
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

    private var items: [Item] {
        let candidates: [(String, String?)] = [
            ("カメラ", exif.camera),
            ("レンズ", exif.lens),
            ("絞り", exif.aperture),
            ("シャッター", exif.exposure),
            ("ISO", exif.iso.map { String($0) }),
            ("焦点距離", exif.focalLength),
        ]
        return candidates.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Item(id: label, value: value)
        }
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack {
                        Text(item.id).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.value)
                    }
                    .font(.caption)
                }
            }
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
