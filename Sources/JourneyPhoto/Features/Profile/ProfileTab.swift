import Foundation

/// プロフィールの表示切り替え（モック2・11: 投稿 / 行きたい場所 / マップ / お気に入り）。
///
/// **年表は外した。** 同じ写真を日付で並べ直すだけの見せ方で、
/// **「旅」の一冊**（`TripBook`——表紙・時間順のページ・足取り）が
/// その役目をより強く果たす。マイページには「旅の記録」への導線が
/// 別にあるので、入口は失われない。
enum ProfileTab: String, CaseIterable, Identifiable {
    case posts
    /// 旅の一冊の棚（`TripBook`）。**本人のページだけ**——以前は写真の上に
    /// 「旅の記録」の札を別に置いていた（整理案 05c でタブへ移した）
    case trips
    /// 行きたいスポット（`WishlistStore`）。**この端末にしか無い**
    case wishlist
    case map
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .posts: return L("投稿", "Posts")
        case .trips: return L("旅の記録", "Trips")
        case .wishlist: return L("行きたい場所", "Want to go")
        case .map: return L("マップ", "Map")
        case .favorites: return L("お気に入り", "Saved")
        }
    }

    var systemImage: String {
        switch self {
        case .posts: return "square.grid.3x3"
        case .trips: return "book.closed"
        case .wishlist: return "heart"
        case .map: return "map"
        case .favorites: return "bookmark"
        }
    }

    /// **行きたい場所とお気に入りは、その端末の持ち主にしか無い。**
    ///
    /// どちらもサーバーに口が無く（`WishlistStore` / `FavoritesStore` は
    /// `UserDefaults`）、他人のぶんは**取りようがない**。以前は他人の
    /// ページにも「お気に入り」の札を出して、押すと「本人だけが見られます」と
    /// 返していた——押しても何も出ない札は、壊れているのと見分けが付かない。
    /// 出さない方が正直。
    ///
    /// **本人のページに「マップ」は出さない**（整理案 05c・2026-09-26）。
    /// 下の札の「マップ」と入口が重なっていた。代わりに「旅の記録」を置く
    /// ——旅の一冊にも足取りの地図がある。他人のページは今まで通り
    static func tabs(isMe: Bool) -> [ProfileTab] {
        isMe ? [.posts, .trips, .wishlist, .favorites] : [.posts, .map]
    }
}
