import Foundation

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

    /// 絞り込みに出すカテゴリ。**写真が1枚もない種類は出さない**
    /// （押しても空になるボタンを置かない）
    private(set) var categories: [String] = []

    private let gallery: PublicGalleryService

    init(gallery: PublicGalleryService) {
        self.gallery = gallery
    }

    func load() async {
        // 再読み込みのときに画面を空にしない（読み込み中の白画面を挟まない）
        if case .loaded = state {} else { state = .loading }
        do {
            let photos = try await gallery.fetchPhotos()
            all = sorted(photos)
            categories = Self.categories(in: all)
            state = .loaded(filtered())
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? "読み込めませんでした")
        }
    }

    /// いま出している一覧。絞り込みを変えたら読み直さずに掛け替える。
    private var all: [Photo] = []

    func select(category: String?) {
        self.category = category
        state = .loaded(filtered())
    }

    private func filtered() -> [Photo] {
        guard let category else { return all }
        return all.filter { $0.category == category }
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

    /// 新しい順。`createdAt` は欠けている写真があるので、無い行は末尾へ送る
    /// （Web 側 `lib/utils/photoOrder.ts` と同じ考え方）。
    private func sorted(_ photos: [Photo]) -> [Photo] {
        photos.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.id < rhs.id
            }
        }
    }
}
