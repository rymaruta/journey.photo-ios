import Foundation

/// カテゴリの札に出す代表写真（モック9 の丸いチップ）。
///
/// **その分類の中でいちばん人気の1枚**を使う。決め打ちの絵を持たないので、
/// 写真が増えれば札の顔も変わる——**中身と札が食い違わない**。
///
/// 1枚も無い分類は札にしない（押しても空になるチップを置かない）。
enum CategoryCovers {

    struct Item: Identifiable, Equatable {
        /// 保存されている分類の値（`CategoryChoices.all` の1つ）
        let category: String
        let cover: Photo
        let count: Int
        var id: String { category }
    }

    static func items(in photos: [Photo]) -> [Item] {
        CategoryChoices.all.compactMap { choice in
            let matched = photos.filter { CategoryChoices.isChosen(current: $0.category ?? "", choice: choice) }
            guard let cover = GallerySort.popular.apply(matched).first else { return nil }
            return Item(category: choice, cover: cover, count: matched.count)
        }
    }
}
