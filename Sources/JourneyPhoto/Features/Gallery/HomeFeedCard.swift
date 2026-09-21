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
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// この人をフォローしているか。**外から渡される**（一覧が持っている）
    @State private var isFollowing = false
    @State private var isFollowWorking = false
    /// 一覧が持っているフォロー先。開いたときに合わせる
    var following: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                PhotoDetailView(photo: photo)
            } label: {
                Color.clear
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: photo.detailImageURL, alignment: photo.gridAlignment)
                    }
                    // **題と撮影地は写真の上に置く**（提案の絵）。
                    // 下に並べるより、どの写真の話か迷わない
                    .overlay(alignment: .bottomLeading) { titleOverlay }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            author

            if !caption.isEmpty {
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

    /// 写真に重ねる題と撮影地。**暗くするのは下だけ**（全面に膜を
    /// 掛けると写真が濁る）
    @ViewBuilder
    private var titleOverlay: some View {
        let title = photo.displayTitle
        let place = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty || !place.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !title.isEmpty {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(2)
                }
                if !place.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                        Text(place).lineLimit(1)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
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
                            userId: userId, suffix: nil, cacheBust: nil))
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(photo.displayName ?? L("投稿者", "Poster"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(WebTheme.faint)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
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
                favorites.toggle(photo.id)
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
                favorites.toggle(photo.id)
            } label: {
                Label {
                    Text(L("保存", "Save"))
                } icon: {
                    Image(systemName: favorites.contains(photo.id) ? "bookmark.fill" : "bookmark")
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

    /// 出すいいねの数。**押した瞬間に 1 足す**（サーバーの数は詳細で直る）
    private var likeCount: Int {
        let base = photo.likes ?? 0
        return liked ? base + 1 : base
    }

    /// 「日本・風景写真」にあたる行。撮影地と分類から作る
    private var subtitle: String {
        let place = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = photo.category.map { Labels.Category.name($0) } ?? ""
        return [place, category].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 説明の1段落目。無ければ題で代える
    private var caption: String {
        if let first = photo.paragraphs.first, !first.isEmpty { return first }
        return photo.displayTitle
    }
}
