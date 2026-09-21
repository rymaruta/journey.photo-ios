import SwiftUI

/// 写真の格子。**Web の `GalleryGrid.tsx` と同じ組み方**
/// （`grid-cols-2 gap-1`・4:3・下に黒のグラデーションで題と分類）。
///
/// **2か所に書かない。** 以前はトップ（`GalleryView`）と集約
/// （`TagPhotosView`）が別々に格子を書いていて、トップだけ直すと
/// **同じアプリの中で見た目が割れた**。
struct PhotoGrid<Destination: View>: View {

    let photos: [Photo]
    @ViewBuilder let destination: (Photo) -> Destination

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: WebTheme.gridSpacing),
        count: WebTheme.gridColumns
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: WebTheme.gridSpacing) {
            ForEach(photos) { photo in
                NavigationLink {
                    destination(photo)
                } label: {
                    PhotoTile(photo: photo)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 1枚ぶん。角は丸めない（Web も丸めていない）。
struct PhotoTile: View {

    let photo: Photo

    var body: some View {
        // **枠の形は「空の四角」で決める。**
        //
        // 写真そのものに `.aspectRatio(_, contentMode: .fill)` を掛けると、
        // 枠を決める側が居ないので**写真がセルからはみ出して隣に重なる**
        // （実機の絵で確認。staging には写真が無く、空の格子では
        //  一度も見えなかった壊れ方）。**先に 4:3 の場所を取り**、
        // そこへ写真を流し込んでから切り抜く。
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { caption }
            .accessibilityLabel(photo.accessibilityText)
    }

    /// **題も分類も無い写真には帯を出さない。** 空の黒帯が乗るだけで、
    /// 写真が欠けて見える
    @ViewBuilder
    private var caption: some View {
        let title = photo.displayTitle
        let category = photo.category.map { Labels.Category.name($0) } ?? ""
        if !title.isEmpty || !category.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                }
                if !category.isEmpty {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }
}

/// 決まった縦横比の枠に写真を流し込む。
///
/// **写真そのものに `.aspectRatio(_, contentMode: .fill)` を掛けない。**
/// 枠を決める側が居ないので、写真がセルからはみ出して隣に重なる
/// （実機の絵で確認）。**先に場所を取ってから**流し込む。
struct PhotoFrame: View {

    let photo: Photo
    var aspect: CGFloat = 1

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
            }
            .clipped()
            .contentShape(Rectangle())
    }
}
