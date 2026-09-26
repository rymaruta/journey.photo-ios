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

    @EnvironmentObject private var favorites: FavoritesStore
    /// サーバーが答えたいいねの数（詳細画面で押したぶんもここに来る）
    @EnvironmentObject private var likeCounts: LikeCountStore
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    /// 「…」のブロック（審査 1.2・写真詳細と同じ中身）
    @State private var showBlockConfirm = false
    /// この人をフォローしているか。**外から渡される**（一覧が持っている）
    @State private var isFollowing = false
    @State private var isFollowWorking = false
    @State private var showUnfollowConfirm = false
    /// 一覧が持っているフォロー先。開いたときに合わせる
    var following: Set<String> = []
    /// 同じ投稿の写真（`photo` を含む）。2枚以上なら送れるようにする
    var siblings: [Photo] = []
    /// 「通報する」を押したとき。**シートは一覧（`GalleryView`）が出す。**
    /// カードに付けると、通報で一覧が読み直されてカードごと消え、
    /// 「受け付けました」やブロック失敗の文言を見る前にシートが閉じる
    var onReport: (Photo) -> Void = { _ in }

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
                    .font(JPFont.rowTitle)
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
                    .font(JPFont.mono(12, medium: true))
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
        // **実機の絵の道しるべ。** 「一覧の1枚目」を位置で探すと、
        // 今日のテーマの「参加する」に当たって**ログイン画面を
        // 『写真の詳細』として撮って**いた（run 49 の絵で判明）
        .accessibilityIdentifier("feed.photo")
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
                            .foregroundStyle(WebTheme.accent)
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
                            Text(AuthorName.shown(profile: nil, photoDisplayName: photo.displayName))
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
            moreMenu
        }
    }

    /// 「…」。🔴 **押しても何も起きなかった**——押したときの処理を誰も渡して
    /// いなかった（`onMore` の既定は空）。審査メモの「各写真の『…』から通報・
    /// ブロックできる」が、最初に見るホームで成り立っていなかった。
    /// 中身は写真詳細の「…」と同じ。**自分の写真には出さない**（編集は詳細で）
    @ViewBuilder
    private var moreMenu: some View {
        if photo.userId == nil || photo.userId != auth.userId {
            Menu {
                Button { onReport(currentPhoto) } label: {
                    Label(L("通報する", "Report"), systemImage: "flag")
                }
                if photo.userId != nil {
                    Button(role: .destructive) { showBlockConfirm = true } label: {
                        Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WebTheme.muted2)
                    .webTappable()
            }
            .accessibilityLabel(L("この写真の操作", "More actions"))
            .confirmationDialog(L("この人をブロックしますか？", "Block this person?"),
                                isPresented: $showBlockConfirm, titleVisibility: .visible) {
                Button(L("ブロック", "Block"), role: .destructive) { Task { await block() } }
            } message: {
                Text(L("おたがいの投稿・ストーリー・通知が見えなくなります。", "You won't see each other's posts, stories, or notifications."))
            }
        }
    }

    /// いま出している1枚（束なら送った先）
    private var currentPhoto: Photo {
        shown.indices.contains(page) ? shown[page] : photo
    }

    private func block() async {
        guard let ownerId = photo.userId else { return }
        do {
            try await hidden.blockAndHide(ownerId, environment: environment)
            toasts.show(L("ブロックしました", "Blocked"))
        } catch {
            toasts.show((error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block"),
                        kind: .failure)
        }
    }

    /// フォロー（モック1）。**自分の写真には出さない**し、
    /// 未ログインでも出さない（押しても 401 になるだけ）
    @ViewBuilder
    private var followButton: some View {
        if let ownerId = photo.userId, let me = auth.userId, ownerId != me {
            Button {
                // 外すときだけ確認を挟む（`unfollowConfirmation`）
                if isFollowing { showUnfollowConfirm = true } else { Task { await toggleFollow(ownerId) } }
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
            .unfollowConfirmation(isPresented: $showUnfollowConfirm) {
                Task { await toggleFollow(ownerId) }
            }
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
    /// **数は一覧の `likes`**——`PublicGalleryService` がいまの数
    /// （管理 API の `GET /photos`）に差し替えたもの。押したら、答えが
    /// 返るまでの間だけ ±1 して、返ったらサーバーの数を出す（`LiveLikes`）
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
                .foregroundStyle(WebTheme.foreground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("いいね", "Like"))
            // 色で分けるのをやめたので、押したかどうかは形と読み上げで伝える
            .accessibilityAddTraits(liked ? .isSelected : [])

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

    /// いいね。**サーバーへ送る。**
    ///
    /// 🔴 ここは長いあいだ端末の控えを反転するだけで、**押しても
    /// サーバーには一度も届いていなかった**（詳細画面を開くと
    /// 押していない状態に戻る）。控えは送れたときだけ合わせる。
    private func toggleLike() async {
        // **答えを待っている間は押させない。** 二度目が古い `liked` を見て
        // 逆向きに飛ぶと、ハートと数が押した結果と食い違う（詳細画面の
        // `isLiking` と同じ）
        guard pendingDelta == 0 else { return }
        let wasLiked = liked
        // 先に画面を変える（押した手応えを待たせない）
        favorites.set(photo.id, favorite: !wasLiked)
        pendingDelta = wasLiked ? -1 : 1
        defer { pendingDelta = 0 }
        do {
            let result = wasLiked
                ? try await environment.social.unlike(photoId: photo.id)
                : try await environment.social.like(photoId: photo.id)
            // **返ってきた数と状態を使う。** 自分で数えない。
            // 数を返さない答えなら、押したあとに見えていた数で止める
            likeCounts.set(photo.id, count: result.likes ?? likeCount)
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

    /// 押して答えを待っている間だけの ±1。**答えが来たら 0 に戻す**
    @State private var pendingDelta = 0

    /// 出すいいねの数。
    ///
    /// 土台は、押した答え（`LikeCountStore`・ここで押した回も詳細で押した回も
    /// 入る）と一覧の数（いまの数に差し替え済み）の**新しい方**。
    /// 待っている間だけ ±1 を足す。
    ///
    /// 🔴 以前は「端末でいいね済みなら一覧の数に +1」だった。一覧の数には
    /// **自分のいいねが既に入っている**ので、押したことのある写真は
    /// いつも1つ多く出ていた（しかも一覧の数はサイトを建てた時点の古い数）。
    private var likeCount: Int {
        LiveLikes.displayCount(base: LiveLikes.base(for: photo, stored: likeCounts.entry(for: photo.id)),
                               pendingDelta: pendingDelta)
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
