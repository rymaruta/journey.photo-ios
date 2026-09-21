import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded([Photo])
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    /// 選ばれているカテゴリ。nil は「すべて」
    @Published var category: String?
    /// 並び替え。**Web の `FilterBar` と同じ3つ**（新しい順／古い順／人気順）
    @Published var sort: GallerySort = .new
    /// 出す範囲（自分 / フォロー中 / すべて）。**ログイン中の既定は「自分」**
    @Published private(set) var scope: GalleryScope = .all
    /// フォローしている人。`following` のときだけ要る
    private var followingIds: Set<String> = []
    private var viewerId: String?

    /// 絞り込みに出すカテゴリ。**写真が1枚もない種類は出さない**
    /// （押しても空になるボタンを置かない）
    @Published private(set) var categories: [String] = []

    /// 公開一覧の出どころ。**`let` にしない。**
    ///
    /// `@StateObject` の初期化時には `EnvironmentObject` を読めないので、
    /// 画面が出てから本物（`AppEnvironment.gallery`）に差し替える。
    /// 自前の `PublicGalleryService()` を持ったままだと、
    /// `setHidden` は環境側の1つにしか届かず、**ブロックした相手の写真が
    /// ギャラリーから一生消えない**（再起動しても消えない）。
    private var gallery: PublicGalleryService

    init(gallery: PublicGalleryService = PublicGalleryService()) {
        self.gallery = gallery
    }

    /// 画面が出たら、環境が持っている1つに繋ぎ直す。
    func use(gallery: PublicGalleryService) {
        self.gallery = gallery
    }

    /// - Parameter force: 控えを無視して取り直す（引き下げ更新）。
    func load(force: Bool = false) async {
        // 再読み込みのときに画面を空にしない（読み込み中の白画面を挟まない）
        if case .loaded = state {} else { state = .loading }
        do {
            let photos = try await gallery.fetchPhotos(force: force)
            all = sorted(photos)
            state = .loaded(filtered())
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? Labels.Common.loadFailed)
        }
    }

    /// いま出している一覧。絞り込みを変えたら読み直さずに掛け替える。
    private var all: [Photo] = []

    func select(category: String?) {
        self.category = category
        state = .loaded(filtered())
    }

    func select(scope: GalleryScope) {
        self.scope = scope
        state = .loaded(filtered())
    }

    /// フォローしている人だけ入れ替える。
    ///
    /// **`use(viewerId:following:)` を使い回さない**——あちらは範囲を
    /// 既定へ倒すので、「フォロー中」を選んだ直後に「自分」へ戻ってしまう。
    func refreshFollowing(_ following: Set<String>) {
        self.followingIds = following
        if case .loaded = state { state = .loaded(filtered()) }
    }

    /// ログイン状態が決まったら呼ぶ。
    ///
    /// **未ログインとログアウトは「すべて」に戻す。** 絞れないので絞らない
    /// （Web も同じ——検索の着地点はみんなの写真）。
    /// ログインしたら「自分」へ倒す（owner の指示）。
    func use(viewerId: String?, following: Set<String>) {
        self.viewerId = viewerId
        self.followingIds = following
        scope = viewerId == nil ? .all : .mine
        if case .loaded = state { state = .loaded(filtered()) }
    }

    private func filtered() -> [Photo] {
        let inScope = scope.photos(all, viewerId: viewerId, followingIds: followingIds)
        // **チップは、いまの範囲にある写真から作る。** 全体から作ると
        // 「自分」に切り替えたときに**自分の写真に無いカテゴリ**が並び、
        // 押すと空になる（押しても空になるボタンを置かない）
        categories = Self.categories(in: inScope)
        // 範囲を変えて、選んでいたカテゴリが消えたら絞りも外す
        if let category, !categories.contains(category) {
            self.category = nil
            return inScope
        }
        guard let category else { return inScope }
        return inScope.filter { $0.category == category }
    }

    /// 出てくる順に、重複を落として並べる。**件数の多い順にしない**
    /// ——並びが日によって変わると、押す場所を覚えられない
    static func categories(in photos: [Photo]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for category in photos.compactMap(\.category) where !category.isEmpty {
            if seen.insert(category).inserted { result.append(category) }
        }
        return result.sorted()
    }

    /// 並びは `GallerySort` に置いてある（画面を持たない層なので
    /// Linux 上の `swift test` で検証できる）。
    private func sorted(_ photos: [Photo]) -> [Photo] {
        sort.apply(photos)
    }

    func select(sort: GallerySort) {
        self.sort = sort
        all = sort.apply(all)
        state = .loaded(filtered())
    }

    /// トップに出す「おすすめ」。**絞り込みが掛かっているときは出さない**
    /// ——絞った結果の上に別の並びが出ると、何を見ているのか分からなくなる
    var featured: [FeaturedGroups.Group] {
        guard category == nil else { return [] }
        return FeaturedGroups.groups(from: all)
    }
}
