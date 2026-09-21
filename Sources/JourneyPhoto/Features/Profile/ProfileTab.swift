import Foundation

/// プロフィールの表示切り替え（モック11: 投稿 / マップ / お気に入り）。
///
/// **年表は外した。** 同じ写真を日付で並べ直すだけの見せ方で、
/// **「旅」の一冊**（`TripBook`——表紙・時間順のページ・足取り）が
/// その役目をより強く果たす。マイページには「旅の記録」への導線が
/// 別にあるので、入口は失われない。
enum ProfileTab: String, CaseIterable, Identifiable {
    case posts
    case map
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .posts: return L("投稿", "Posts")
        case .map: return L("マップ", "Map")
        case .favorites: return L("お気に入り", "Saved")
        }
    }

    var systemImage: String {
        switch self {
        case .posts: return "square.grid.3x3"
        case .map: return "map"
        case .favorites: return "bookmark"
        }
    }
}
