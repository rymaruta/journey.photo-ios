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
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            author
            actions

            if !caption.isEmpty {
                Text(caption)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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

    /// いいね・コメント・共有・保存。**押せる大きさを守る**（44pt）
    private var actions: some View {
        HStack(spacing: 20) {
            Button {
                favorites.toggle(photo.id)
            } label: {
                Image(systemName: favorites.contains(photo.id) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.contains(photo.id) ? .pink : WebTheme.foreground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("いいね", "Like"))

            NavigationLink {
                PhotoDetailView(photo: photo)
            } label: {
                Image(systemName: "bubble.right")
                    .foregroundStyle(WebTheme.foreground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("コメント", "Comments"))

            if let url = PhotoLink.url(photoId: photo.id, isPublished: photo.published != false) {
                ShareLink(item: url) {
                    Image(systemName: "paperplane")
                        .foregroundStyle(WebTheme.foreground)
                }
                .accessibilityLabel(L("共有", "Share"))
            }

            Spacer()
        }
        .font(.system(size: 22, weight: .regular))
        .frame(minHeight: WebTheme.minTapTarget)
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
