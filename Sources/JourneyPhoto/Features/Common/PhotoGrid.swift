import SwiftUI

/// 写真の一覧。**等間隔の格子をやめ、強弱のあるリズムで組む**
/// （`EditorialLayout`——大きい1枚 → 2枚 → 2枚 の繰り返し）。
///
/// 角は丸め（18）、題は写真の上に重ねる。Web の「黒地・写真が主役」は
/// そのままに、組みだけ iOS らしくする。
struct PhotoGrid<Destination: View>: View {

    let photos: [Photo]
    @ViewBuilder let destination: (Photo) -> Destination

    /// 段どうし・段の中の隙間
    private let gap: CGFloat = 10

    var body: some View {
        VStack(spacing: gap) {
            ForEach(EditorialLayout.rows(photos)) { row in
                switch row {
                case .hero(let photo):
                    link(photo, aspect: 16.0 / 10.0)
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
            PhotoTile(photo: photo, aspect: aspect)
        }
        .buttonStyle(.plain)
    }
}

/// 1枚ぶん。
struct PhotoTile: View {

    let photo: Photo
    var aspect: CGFloat = 1

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
            .accessibilityLabel(photo.accessibilityText)
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
