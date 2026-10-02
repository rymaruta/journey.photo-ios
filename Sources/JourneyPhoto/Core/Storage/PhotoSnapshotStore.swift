import Foundation

/// 最後に取れた公開写真の一覧を端末に残す。
///
/// **圏外で「読み込めませんでした」だけを出さないため。** Web 側の
/// Service Worker は「ページはネットワーク優先、落ちたときだけ控えを出す」
/// という形にしてある（`public/sw.js`）。同じ考え方をアプリにも置く:
/// 取れたら必ず上書き、取れなかったときだけ前回のぶんを出す。
struct PhotoSnapshotStore {

    private let url: URL
    /// 中身と同じ回の版の印（`ETag`・`Last-Modified`）。条件付きの取得に使う（`ConditionalGet`）
    let validators: ValidatorStore

    init(fileName: String = "photos-snapshot.json") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.url = caches.appendingPathComponent(fileName)
        self.validators = ValidatorStore(snapshotURL: url)
    }

    /// 中身と、その応答の版の印を書く。**印の無い応答なら印は残さない**
    /// （前の回の印を残すと、304 で違う中身を出す）
    func save(_ data: Data, validator: HTTPValidator? = nil) {
        validators.saveSnapshot(data, to: url, validator: validator)
    }

    func load() -> [Photo]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 控えの側も1行の型違いで全部消さない（`LenientPhotoList` の理由）
        return try? JSONDecoder.api.decode(LenientPhotoList.self, from: data).photos
    }
}
