import SwiftUI

/// ホームの1枚（フィードの札）。
///
/// **提案の絵（owner・2026-09-21）どおりの縦1列。**
///
///     ┌───────────────────────┐
///     │        写真（大きく）        │
///     └───────────────────────┘
///     ◎ photographer          …
///       日本・風景写真
///     ♡  💬  ↗              🔖
///     旅先で出会った、忘れられない夕暮れ。
///
/// **格子をやめた理由。** 2列の格子は「並んでいる」だけで、1枚ずつの
/// 写真が小さい。写真が主役のアプリなら、1枚を大きく見せて、撮った人と
/// 言葉まで一緒に読ませた方がいい。
struct HomeFeedCard: View {

    let photo: Photo
    /// 「…」を押したとき（通報・ブロックなど）
    var onMore: () -> Void = {}

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// この人をフォローしているか。**外から渡される**（一覧が持っている）
    @State private var isFollowing = false
    @State private var isFollowWorking = false
    /// 一覧が持っているフォロー先。開いたときに合わせる
    var following: Set<String> = []
    /// 同じ投稿の写真（`photo` を含む）。2枚以上なら送れるようにする
    var siblings: [Photo] = []

    /// いま出している1枚（送りの位置）
    @State private var page = 0

    /// 出す写真たち。**渡されなければこの1枚だけ**
    private var shown: [Photo] {
        siblings.isEmpty ? [photo] : siblings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // **作者は写真の上**（モック1）。誰の一枚かを先に伝える
            author

            photoArea

            // **題は写真の下**（モック1）。写真に重ねていたが、モックは
            // 重ねず、説明と同じ塊で読ませる
            if !photo.displayTitle.isEmpty {
                Text(photo.displayTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
            }
            if !caption.isEmpty, caption != photo.displayTitle {
                Text(caption)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(3)
            }
            tags
            actions
        }
        .padding(.horizontal, 16)
        // **下をしっかり空ける。** タグの行がタブバーに隠れかけていた
        // （実機の絵で確認）。カード同士の境目も見えやすくなる
        .padding(.bottom, 20)
        .onAppear {
            if let ownerId = photo.userId { isFollowing = following.contains(ownerId) }
        }
    }

    /// 写真。**同じ投稿が2枚以上なら左右に送れる**（モック6 の「1/10」）。
    /// 1枚だけなら送りの飾りは出さない（送る先が無い）
    @ViewBuilder
    private var photoArea: some View {
        let photos = shown
        ZStack(alignment: .topTrailing) {
            if photos.count > 1 {
                TabView(selection: $page) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, item in
                        link(to: item, in: photos).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .aspectRatio(4.0 / 5.0, contentMode: .fit)

                Text("\(min(page + 1, photos.count))/\(photos.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(12)
                    .allowsHitTesting(false)
            } else {
                link(to: photo, in: photos)
            }
        }
    }

    private func link(to item: Photo, in context: [Photo]) -> some View {
        NavigationLink {
            PhotoDetailView(photo: item, context: context)
        } label: {
            Color.clear
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: item.detailImageURL, alignment: item.gridAlignment)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    /// タグ。**押すとそのタグの写真へ**（提案の絵の青い `#長崎`）
    @ViewBuilder
    private var tags: some View {
        let list = Array((photo.tags ?? []).prefix(4))
        if !list.isEmpty {
            HStack(spacing: 10) {
                ForEach(list, id: \.self) { tag in
                    NavigationLink {
                        TagPhotosView(kind: .tag(tag))
                    } label: {
                        Text("#\(tag)")
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.42, green: 0.68, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    /// 撮った人。**名前の下に「どこの・何の写真か」を添える**
    /// （提案の絵の「日本・風景写真」にあたる）
    private var author: some View {
        HStack(spacing: 10) {
            if let userId = photo.userId {
                NavigationLink {
                    UserProfileView(userId: userId)
                } label: {
                    HStack(spacing: 10) {
                        RemoteImage(url: UserProfile.profileAssetURL(
                            userId: userId, suffix: nil, cacheBust: nil),
                                    placeholderSymbol: "person.crop.circle.fill")
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(photo.displayName ?? L("投稿者", "Poster"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                            if !subtitle.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.caption2)
                                    Text(subtitle).lineLimit(1)
                                }
                                .font(.caption)
                                .foregroundStyle(WebTheme.faint)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 6)
            // **いつ出されたか**（モック1 の「3時間前」）。読めなければ出さない
            if let ago = StoryPlayback.ago(from: photo.createdAt) {
                Text(ago)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(1)
            }
            followButton
            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WebTheme.muted2)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("この写真の操作", "More actions"))
        }
    }

    /// フォロー（モック1）。**自分の写真には出さない**し、
    /// 未ログインでも出さない（押しても 401 になるだけ）
    @ViewBuilder
    private var followButton: some View {
        if let ownerId = photo.userId, let me = auth.userId, ownerId != me {
            Button {
                Task { await toggleFollow(ownerId) }
            } label: {
                Text(isFollowing ? L("フォロー中", "Following") : L("フォロー", "Follow"))
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(isFollowing ? AnyShapeStyle(WebTheme.surface)
                                            : AnyShapeStyle(Color.clear),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(
                        isFollowing ? Color.clear : Color.white.opacity(0.35), lineWidth: 1))
                    .foregroundStyle(WebTheme.foreground)
            }
            .buttonStyle(.plain)
            .disabled(isFollowWorking)
        }
    }

    private func toggleFollow(_ userId: String) async {
        guard !isFollowWorking else { return }
        isFollowWorking = true
        defer { isFollowWorking = false }
        // **返ってきた状態を使う。** 自分で反転すると、失敗した回に
        // 画面だけフォロー中になる
        if isFollowing {
            let result = try? await environment.social.unfollow(userId: userId)
            if let result { isFollowing = result.following }
        } else {
            let result = try? await environment.social.follow(userId: userId)
            if let result { isFollowing = result.following }
        }
    }

    /// いいね・コメント・保存・共有。**数も出す**（提案の絵）。
    /// 押せる大きさは 44pt を守る。
    ///
    /// **数は「サーバーが知っている数」ではない。** 公開 JSON の `likes`
    /// はビルド時の値なので、**自分が押したぶんだけ即座に足す**
    /// （詳細画面を開けば、サーバーの数で描き直される）
    private var actions: some View {
        HStack(spacing: 22) {
            Button {
                Task { await toggleLike() }
            } label: {
                Label {
                    Text("\(likeCount)")
                } icon: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                }
                .foregroundStyle(liked ? .pink : WebTheme.foreground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("いいね", "Like"))

            NavigationLink {
                PhotoDetailView(photo: photo)
            } label: {
                Label {
                    Text(L("コメント", "Comments"))
                } icon: {
                    Image(systemName: "bubble.right")
                }
                .foregroundStyle(WebTheme.foreground)
            }
            .buttonStyle(.plain)

            Spacer()

            // **保存＝端末に覚えるお気に入り**（モック1 の 🔖）。
            // いいねはサーバー、保存は手元、と役割が違う
            Button {
                Task { await toggleSave() }
            } label: {
                Label {
                    Text(L("保存", "Save"))
                } icon: {
                    Image(systemName: savedPhotos.contains(photo.id) ? "bookmark.fill" : "bookmark")
                }
                .foregroundStyle(WebTheme.foreground)
            }
            .buttonStyle(.plain)

            if let url = PhotoLink.url(photoId: photo.id, isPublished: photo.published != false) {
                ShareLink(item: url) {
                    Label {
                        Text(L("シェア", "Share"))
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(WebTheme.foreground)
                }
            }
        }
        .font(.subheadline)
        .frame(minHeight: WebTheme.minTapTarget)
    }

    private var liked: Bool { favorites.contains(photo.id) }

    /// 押した回にサーバーが答えた数。**答えが来るまでは nil**
    @State private var serverLikes: Int?

    /// いいね。**サーバーへ送る。**
    ///
    /// 🔴 ここは長いあいだ端末の控えを反転するだけで、**押しても
    /// サーバーには一度も届いていなかった**（詳細画面を開くと
    /// 押していない状態に戻る）。控えは送れたときだけ合わせる。
    private func toggleLike() async {
        let wasLiked = liked
        // 先に画面を変える（押した手応えを待たせない）
        favorites.set(photo.id, favorite: !wasLiked)
        do {
            let result = wasLiked
                ? try await environment.social.unlike(photoId: photo.id)
                : try await environment.social.like(photoId: photo.id)
            // **返ってきた数と状態を使う。** 自分で数えない
            if let likes = result.likes { serverLikes = likes }
            favorites.set(photo.id, favorite: result.liked)
        } catch {
            // **届かなかったら戻す。** 画面だけ「いいね済み」にしない
            favorites.set(photo.id, favorite: wasLiked)
        }
    }

    /// 保存。**いいねとは別の入れ物**（`saves#<uid>`）。
    /// 以前は同じ控えを使っていたので、保存を押すとハートが灯っていた。
    private func toggleSave() async {
        let wasSaved = savedPhotos.contains(photo.id)
        savedPhotos.set(photo.id, saved: !wasSaved)
        do {
            if wasSaved {
                try await environment.saves.unsave(photoId: photo.id)
            } else {
                try await environment.saves.save(photoId: photo.id)
            }
        } catch {
            savedPhotos.set(photo.id, saved: wasSaved)
        }
    }

    /// 出すいいねの数。**押した瞬間に 1 足す**（サーバーの数は詳細で直る）
    /// 出すいいねの数。
    ///
    /// **サーバーが答えた数があれば、それを出す**（押した回に返ってくる）。
    /// 無い間は静的 JSON の値に、押した手応えぶんだけ足す。
    ///
    /// ⚠️ **足した数は厳密ではない。** 前に押したぶんは JSON の値に
    /// 既に入っているので、その写真では1多く見える。押せばサーバーの数に
    /// 直るし、詳細画面でも直る——**数の出どころを1つに寄せられない**
    /// のは、一覧が静的 JSON で来るため。
    private var likeCount: Int {
        if let known = serverLikes { return known }
        let base = photo.likes ?? 0
        return liked ? base + 1 : base
    }

    /// 「日本・風景写真」にあたる行。撮影地と分類から作る
    /// 名前の下の1行。**撮影地だけ**（モック1）。分類まで並べると、
    /// 撮影地の無い写真では分類だけが「場所」の位置に出て紛らわしい
    private var subtitle: String {
        (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 説明の1段落目。無ければ題で代える
    private var caption: String {
        if let first = photo.paragraphs.first, !first.isEmpty { return first }
        return photo.displayTitle
    }
}
