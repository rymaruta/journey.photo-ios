import Foundation

/// 最後に取れた公開写真の一覧を端末に残す。
///
/// **圏外で「読み込めませんでした」だけを出さないため。** Web 側の
/// Service Worker は「ページはネットワーク優先、落ちたときだけ控えを出す」
/// という形にしてある（`public/sw.js`）。同じ考え方をアプリにも置く:
/// 取れたら必ず上書き、取れなかったときだけ前回のぶんを出す。
struct PhotoSnapshotStore {

    private let url: URL

    init(fileName: String = "photos-snapshot.json") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.url = caches.appendingPathComponent(fileName)
    }

    func save(_ data: Data) {
        // 失敗しても何も言わない（控えが取れないだけで、本筋は動いている）
        try? data.write(to: url, options: .atomic)
    }

    func load() -> [Photo]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 控えの側も1行の型違いで全部消さない（`LenientPhotoList` の理由）
        return try? JSONDecoder.api.decode(LenientPhotoList.self, from: data).photos
    }
}
