import Foundation

/// ホームのフィード（おすすめ / フォロー中 / 新着）。
///
/// **指示書 5-2 の約束**:「バックエンドが対応していないフィードを、
/// 実装済みであるかのように表示しない」。いまの API にできることで作る。
///
///     おすすめ … **推薦の口は無い。** owner が選んだ `featured` を先に、
///                残りをいいねの多い順。先頭10枠に新しい投稿を混ぜる（`HomeFreshMix`）。**規則は画面にも出す**
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
            return L("選ばれた写真と、よく見られている写真、新しい投稿から",
                     "Featured photos, the most liked ones and new posts")
        case .following, .latest:
            return nil
        }
    }

    /// 切り替えの下に「おすすめ」の横並び（カテゴリごと・`FeaturedSections`）を出すか。
    ///
    /// **「おすすめ」のときだけ**（2026-10-11 判断）。横並びは選ばれた写真＝おすすめの中身。
    /// 「フォロー中」「新着」でも出していたので、切り替えても結果がずっと下に出て、
    /// 押して何が変わったか見えなかった
    var showsFeatured: Bool { self == .recommended }

    /// 「いまの季節のスポット」の段を写真の一覧の中に出すか（#417 ④・2026-10-30 owner 採用）。
    /// **「おすすめ」のときだけ**——フォロー中・新着では出さない（2026-10-11「切り替えの下には選んだフィードの中身だけ」に沿う。
    /// 段は全員向けの作例なので「おすすめ」の中身）
    var showsSeasonShelf: Bool { self == .recommended }

    /// 段の前に置く写真（束）の数。**大1→2→2 のひと回り**（`EditorialLayout.rows`: 大きい段のあと2枚の段が2つ）。
    /// ひと回りの切れ目で割るので、段の後ろの写真も大きい1枚から始まり、並びのリズムは変わらない
    static let seasonShelfAfter = 5

    /// 写真（束）の並びを、段の前（ひと回り）と後ろに割る
    static func splitForSeasonShelf<T>(_ items: [T]) -> (lead: [T], rest: [T]) {
        let count = min(seasonShelfAfter, items.count)
        return (Array(items.prefix(count)), Array(items.dropFirst(count)))
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
    ///
    /// 新しい投稿を混ぜるのは**ここではない**（`mixesFresh`・札 #537 の確かめ役・2026-11-11）。混ぜるのは
    /// 絞り込み（カテゴリ・タグ・打った文字）とブロック・通報を落とした**後**の一覧（`HomeFeedPageMemo.make`）。
    /// 前で混ぜると、絞って落ちた写真の分だけ枠がずれ、新しい投稿が 2・5・8 番目に来ない（Web の `useGallery` は後で混ぜる）
    func arrange(_ photos: [Photo]) -> [Photo] {
        let sorted = sort.apply(photos)
        guard self == .recommended else { return sorted }
        let picked = sorted.filter { $0.featured == true }
        let rest = sorted.filter { $0.featured != true }
        return picked + rest
    }

    /// **先頭 10 枠のうち 2・5・8 番目に、72 時間以内の新しい投稿を混ぜるか**（`HomeFreshMix`・札 #537 案1・2026-11-11 判断）。
    /// 「おすすめ」だけ。いいね順だけだと、投稿したばかりの写真は14番目より後ろに沈んでいた
    var mixesFresh: Bool { self == .recommended }
}

/// ホームのフィードの切り替えも、マイページと同じ下線の札（`ProfileTabBar`・`ProfileTabPager`・2026-10-31 #426）。
/// 目印は今までの `home.feed.<名前>`（UI テストと画面写真の道しるべ）
extension HomeFeed: PagedTab {
    var tabTitle: String { label }
    var tabIdentifier: String { "home.feed.\(rawValue)" }
}
