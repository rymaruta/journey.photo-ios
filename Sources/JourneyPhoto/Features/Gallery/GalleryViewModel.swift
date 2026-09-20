import Foundation

@MainActor
final class GalleryViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded([Photo])
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    private let gallery: PublicGalleryService

    init(gallery: PublicGalleryService) {
        self.gallery = gallery
    }

    func load() async {
        // 再読み込みのときに画面を空にしない（読み込み中の白画面を挟まない）
        if case .loaded = state {} else { state = .loading }
        do {
            let photos = try await gallery.fetchPhotos()
            state = .loaded(sorted(photos))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? "読み込めませんでした")
        }
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
