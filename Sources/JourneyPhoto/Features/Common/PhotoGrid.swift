import SwiftUI

/// 写真の一覧。**等間隔の格子をやめ、強弱のあるリズムで組む**
/// （`EditorialLayout`——大きい1枚 → 2枚 → 2枚 の繰り返し）。
///
/// 角は丸め（18）、題は写真の上に重ねる。Web の「黒地・写真が主役」は
/// そのままに、組みだけ iOS らしくする。
struct PhotoGrid<Destination: View>: View {

    let photos: [Photo]
    /// 先頭の大きい1枚に撮影地・投稿者・いいねを重ねるか（板 12）。
    /// 集約の一覧だけが使う——ホームの一覧は1枚ごとに別の帯を持つ
    var captionsLead = false
    @ViewBuilder let destination: (Photo) -> Destination

    /// 1つの投稿に2枚以上入っている写真。**この並びの中で数える**
    /// ——兄弟が見えていないのに「複数枚」と出さない
    private var multiple: Set<String> { PhotoGroups.multiPhotoIds(photos) }

    /// 段どうし・段の中の隙間
    private let gap: CGFloat = 10

    var body: some View {
        VStack(spacing: gap) {
            ForEach(EditorialLayout.rows(photos)) { row in
                switch row {
                case .hero(let photo):
                    if captionsLead && photo.id == photos.first?.id {
                        NavigationLink {
                            destination(photo)
                        } label: {
                            PhotoTile(photo: photo, aspect: 16.0 / 10.0,
                                      isMultiple: multiple.contains(photo.id))
                                .overlay(alignment: .bottom) { LeadCaption(photo: photo) }
                                .clipShape(RoundedRectangle(cornerRadius: PhotoTile.corner))
                        }
                        .buttonStyle(.plain)
                    } else {
                        link(photo, aspect: 16.0 / 10.0)
                    }
                case .pair(let first, let second):
                    if let second {
                        HStack(spacing: gap) {
                            link(first, aspect: 1)
                            link(second, aspect: 1)
                        }
                    } else {
                        // **相方が無い段は1枚で横いっぱい。**
                        // 半分だけ写真がある段を作らない
                        link(first, aspect: 16.0 / 10.0)
                    }
                }
            }
        }
        .padding(.horizontal, gap)
    }

    private func link(_ photo: Photo, aspect: CGFloat) -> some View {
        NavigationLink {
            destination(photo)
        } label: {
            PhotoTile(photo: photo, aspect: aspect, isMultiple: multiple.contains(photo.id))
        }
        .buttonStyle(.plain)
    }
}

/// 先頭の大きい1枚の字（板 12）。撮影地を大きく、その下に @投稿者、右にいいね。
///
/// **いいねが 0 のときは出さない**（`SearchGrid` と同じ——「まだ誰も押して
/// いない」は探している人に要らず、写真の邪魔になる）。
/// **何も書くものが無い写真には帯を出さない。**
private struct LeadCaption: View {

    let photo: Photo
    @EnvironmentObject private var likeCounts: LikeCountStore

    var body: some View {
        let headline = CollectionScreen.leadHeadline(photo)
        let author = CollectionScreen.leadAuthor(photo)
        let likes = LiveLikes.base(for: photo, stored: likeCounts.entry(for: photo.id)) ?? 0
        if headline != nil || author != nil || likes > 0 {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let headline {
                        Text(headline)
                            .font(JPFont.cardTitle)
                            .foregroundStyle(WebTheme.foreground)
                            .lineLimit(2)
                    }
                    if let author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(WebTheme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if likes > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                        Text("\(likes)")
                    }
                    .font(JPFont.mono(11))
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L("いいね \(likes)", "\(likes) likes"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 48)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
    }
}

/// 1枚ぶん。
struct PhotoTile: View {

    let photo: Photo
    var aspect: CGFloat = 1
    /// 1つの投稿に2枚以上入っているか（モック2-7 の格子の右上の印）。
    /// **呼ぶ側が並びの中で数えた結果**を受け取る——写真1枚では決められない
    var isMultiple = false

    /// 角の丸み。iOS の今の作法に寄せて大きめ
    static let corner: CGFloat = 18

    var body: some View {
        // **枠の形は「空の四角」で決める。**
        //
        // 写真そのものに `.aspectRatio(_, contentMode: .fill)` を掛けると、
        // 枠を決める側が居ないので**写真がセルからはみ出して隣に重なる**
        // （実機の絵で確認。staging には写真が無く、空の格子では
        //  一度も見えなかった壊れ方）。**先に場所を取り**、
        // そこへ写真を流し込んでから切り抜く。
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.corner))
            .overlay(RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Self.corner))
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .topTrailing) { multipleMark }
            .accessibilityLabel(photo.accessibilityText)
    }

    /// 複数枚の印。**束ねた写真が2枚以上この並びに在るときだけ**
    @ViewBuilder
    private var multipleMark: some View {
        if isMultiple {
            Image(systemName: "square.on.square")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white)
                .shadow(radius: 3)
                .padding(10)
                .accessibilityLabel(L("複数枚の投稿", "Multiple photos"))
        }
    }

    /// **題も分類も無い写真には帯を出さない。** 空の黒帯が乗るだけで、
    /// 写真が欠けて見える
    @ViewBuilder
    private var caption: some View {
        let title = photo.displayTitle
        let category = photo.category.map { Labels.Category.name($0) } ?? ""
        if !title.isEmpty || !category.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if !category.isEmpty {
                    // 分類は小さく、字間を開けて上に置く（見出しの上の肩書き）
                    Text(category.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: PhotoTile.corner))
        }
    }
}

/// 決まった縦横比の枠に写真を流し込む（一覧以外の小さい格子で使う）。
///
/// **写真そのものに `.aspectRatio(_, contentMode: .fill)` を掛けない。**
/// 枠を決める側が居ないので、写真がセルからはみ出して隣に重なる。
struct PhotoFrame: View {

    let photo: Photo
    var aspect: CGFloat = 1
    var corner: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .contentShape(RoundedRectangle(cornerRadius: corner))
    }
}
