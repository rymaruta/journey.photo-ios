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
    /// ホームのフィード（おすすめ / フォロー中 / 新着）。
    /// **範囲と並びの組に名前を付けたもの**（`HomeFeed`）
    @Published private(set) var feed: HomeFeed = .recommended
    /// 選んでいるタグ。**複数選べて、全部を持つ写真だけが残る**
    /// （Web の `selectedTags` と同じ）
    @Published private(set) var selectedTags: [String] = []
    /// 打った文字。題・説明・撮影地・タグを見る
    @Published var query: String = "" { didSet { state = .loaded(filtered()) } }
    /// 出す範囲（自分 / フォロー中 / すべて）。**選んでいるフィードが決める**（`HomeFeed.scope`）
    @Published private(set) var scope: GalleryScope = .all
    /// フォローしている人。`following` のときだけ要る
    /// フォロー先。**カードのフォローボタンにも渡す**（モック1）
    private(set) var followingIds: Set<String> = []
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

    /// 自分の写真。**今日のテーマに参加したかの判定に使う。**
    ///
    /// 公開一覧（静的 JSON）ではなく**API から読む**——投稿したばかりの
    /// 写真は再ビルドまで公開一覧に載らないので、公開一覧だけを見ると
    /// 「参加したのに参加済みにならない」が数分続く。
    @Published private(set) var myPhotos: [Photo] = []

    func loadMyPhotos(_ photos: PhotoService, viewerId: String?) async {
        guard viewerId != nil else {
            myPhotos = []
            return
        }
        myPhotos = (try? await photos.myPhotos()) ?? []
    }

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
    /// **範囲はいま選んでいるフィードが決める**（指示書のホームは
    /// おすすめ／フォロー中／新着）。以前はここで「自分」へ倒していたが、
    /// それだと**押したフィードが即座に打ち消される**。
    ///
    /// **フォロー中は未ログインだと中身が無い。** 絞れないので
    /// 「おすすめ」へ戻す（空の画面に置き去りにしない）。
    func use(viewerId: String?, following: Set<String>) {
        self.viewerId = viewerId
        self.followingIds = following
        if viewerId == nil && feed.needsSignIn { feed = .recommended }
        scope = feed.scope
        sort = feed.sort
        if case .loaded = state { state = .loaded(filtered()) }
    }

    private func filtered() -> [Photo] {
        let inScope = scope.photos(all, viewerId: viewerId, followingIds: followingIds)
        // **チップは、いまの範囲にある写真から作る。** 全体から作ると
        // 「自分」に切り替えたときに**自分の写真に無いカテゴリ**が並び、
        // 押すと空になる（押しても空になるボタンを置かない）
        categories = Self.categories(in: inScope)
        // 範囲を変えて、選んでいたカテゴリが消えたら絞りも外す
        if let category, !categories.contains(where: { CategoryChoices.isChosen(current: $0, choice: category) }) {
            self.category = nil
            return inScope
        }
        guard let category else {
            return PhotoQuery.photos(
                PhotoQuery.photos(inScope, withAllTags: selectedTags),
                matching: query
            )
        }
        // 綴りではなく鍵で比べる（`建築` を押したら `architecture` も出る）
        let key = CategoryChoices.key(category)
        return PhotoQuery.photos(
            PhotoQuery.photos(
                inScope.filter { CategoryChoices.key($0.category ?? "") == key },
                withAllTags: selectedTags
            ),
            matching: query
        )
    }

    /// 出てくる順に、重複を落として並べる。**件数の多い順にしない**
    /// ——並びが日によって変わると、押す場所を覚えられない
    static func categories(in photos: [Photo]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        // **日英を畳んでから数える。** 実データには `architecture` と `建築`、
        // `landscape` と `風景` が両方ある（30枚中の実測）。生の値で
        // 並べると**同じ「建築」のチップが2つ出て、押すと結果も割れる**
        // ——Web は `slugify(_, "category")` で畳んでいる。
        // **代表は最初に出てきた綴り**（どちらを押しても同じ結果になる）
        for category in photos.compactMap(\.category) where !category.isEmpty {
            if seen.insert(CategoryChoices.key(category)).inserted { result.append(category) }
        }
        return result.sorted { Labels.Category.name($0) < Labels.Category.name($1) }
    }

    /// 並びは `GallerySort` に置いてある（画面を持たない層なので
    /// Linux 上の `swift test` で検証できる）。
    private func sorted(_ photos: [Photo]) -> [Photo] {
        sort.apply(photos)
    }

    /// タグのチップ。**押し直すと外れる**（カテゴリと同じ約束）
    func toggle(tag: String) {
        let key = TagChoices.key(tag)
        if let index = selectedTags.firstIndex(where: { TagChoices.key($0) == key }) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
        state = .loaded(filtered())
    }

    /// 絞り込みに出すタグ。
    ///
    /// **決まった20語だけ**（`TagChoices.all`）。owner の指示:
    /// 「タグみたいなの多すぎる／フィンランドみたいな個別なのは候補に
    /// 置きたくない」。以前は写真に付いている語をそのまま多い順に出して
    /// いたので、`finland`・`helsinki` のような**その旅にしか出てこない
    /// 固有名詞**が候補に並んでいた（次の写真で押す相手ではない）。
    ///
    /// **1枚も無い語は出さない。** 押しても空になるチップを置かない。
    var tags: [String] {
        let present = Set(all.flatMap { $0.tags ?? [] }.map { TagChoices.key($0) })
        return TagChoices.all.filter { present.contains(TagChoices.key($0)) }
    }

    /// フィードを選ぶ。**範囲と並びを一緒に切り替える**。
    ///
    /// **`use(viewerId:following:)` は呼ばない。** あちらは範囲を
    /// 「自分」に倒すので、押したフィードが即座に打ち消される
    /// （組み込んだ直後に踏んだ）。
    func select(feed: HomeFeed, viewerId: String?) {
        self.feed = feed
        self.scope = feed.scope
        self.sort = feed.sort
        self.viewerId = viewerId
        all = feed.arrange(all)
        state = .loaded(filtered())
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
