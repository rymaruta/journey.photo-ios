import Foundation

/// ホームのフィード（おすすめ / フォロー中 / 新着）。
///
/// **指示書 5-2 の約束**:「バックエンドが対応していないフィードを、
/// 実装済みであるかのように表示しない」。いまの API にできることで作る。
///
///     おすすめ … **推薦の口は無い。** owner が選んだ `featured` を先に、
///                残りをいいねの多い順。**規則は画面にも出す**
///                （「何で並んでいるか分からない」を作らない）
///     フォロー中 … `/user/following` の人の写真だけ。**要ログイン**
///     新着     … `createdAt` の新しい順
///
/// 並べ替えそのものは `GallerySort` に、範囲は `GalleryScope` にある。
/// ここは**その2つの組み合わせに名前を付ける**層。
enum HomeFeed: String, CaseIterable, Identifiable {
    case recommended, following, latest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: return L("おすすめ", "For you")
        case .following: return L("フォロー中", "Following")
        case .latest: return L("新着", "Latest")
        }
    }

    /// 画面に出す注釈。**推薦の仕組みがあるように見せない**
    var note: String? {
        switch self {
        case .recommended:
            return L("選ばれた写真と、よく見られている写真から",
                     "Featured photos and the most liked ones")
        case .following, .latest:
            return nil
        }
    }

    /// ログインしていないと中身が出ない側か。
    /// **出しっぱなしにはする**——押せば「ログインしてください」に着き、
    /// そこから入れる（タブごと隠すと、入口そのものが見つからない）
    var needsSignIn: Bool { self == .following }

    var scope: GalleryScope {
        switch self {
        case .following: return .following
        case .recommended, .latest: return .all
        }
    }

    var sort: GallerySort {
        switch self {
        case .recommended: return .popular
        case .following, .latest: return .new
        }
    }

    /// おすすめの並び。**owner が選んだ写真（`featured`）を先に**、
    /// 残りはいいねの多い順（`sort` が受け持つ）。
    func arrange(_ photos: [Photo]) -> [Photo] {
        let sorted = sort.apply(photos)
        guard self == .recommended else { return sorted }
        let picked = sorted.filter { $0.featured == true }
        let rest = sorted.filter { $0.featured != true }
        return picked + rest
    }
}
