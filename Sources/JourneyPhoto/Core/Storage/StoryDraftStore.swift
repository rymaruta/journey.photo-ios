import Foundation
import Combine

/// ストーリーの下書き（モック4 の「下書き保存」）。
///
/// **1件だけ。** ストーリーは24時間で消える一過性のもので、何本も下書きを
/// 貯める使い方をしない。2件目を保存したら1件目は上書きする——
/// 一覧を作ると「どれが最新か」を選ばせることになる。
///
/// **サーバーには無い。** `api-user` のストーリーは投稿の口しか持たない
/// （下書きの概念があるのは写真の方）。だから端末に置く。機種を変えると
/// 消えるので、画面でもそう書くこと。
///
/// 写真の中身（数MB）は `UserDefaults` に入れない——起動のたびに丸ごと
/// 読まれる。**ファイルに書いて、道だけを覚える。**
@MainActor
final class StoryDraftStore: ObservableObject {

    /// 覚えておくもの。画像そのものは別のファイル（`imageFile`）。
    ///
    /// **`exif` は覚えない。** ストーリーは EXIF を送らない（`create` が
    /// 受け取るのは画像・キャプション・撮影地・座標・曲・秒数だけ）ので、
    /// 戻しても使い道が無い。
    struct Draft: Codable, Equatable {
        var imageFile: String
        var fileName: String
        var contentType: String
        var latitude: Double?
        var longitude: Double?
        var caption: String
        var location: String
        var overlays: [TextOverlay]
        var song: Photo.Song?
        var durationSec: Int
        /// 保存した時刻（ISO8601）。「いつの下書きか」を出すため
        var savedAt: String

        var coords: Photo.Coords? {
            guard let latitude, let longitude else { return nil }
            return Photo.Coords(lat: latitude, lng: longitude)
        }
    }

    @Published private(set) var draft: Draft?

    private let defaults: UserDefaults
    private let directory: URL
    private var userId: String?

    /// - Parameters:
    ///   - directory: 画像を置く場所。既定は Application Support
    ///     （利用者に見せるものではなく、端末の掃除で勝手に消えては困る）
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static let key = "journey-photo-story-draft"

    /// **アカウントごとに分ける**（`FavoritesStore` と同じ理由——同じ端末で
    /// 人が変わったとき、前の人の書きかけを見せない）。
    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.key }
        return "\(Self.key):\(userId)"
    }

    func use(userId: String?) {
        self.userId = userId
        draft = load()
    }

    private func load() -> Draft? {
        guard let data = defaults.data(forKey: key(for: userId)),
              let saved = try? JSONDecoder().decode(Draft.self, from: data) else { return nil }
        // **中身の無い下書きを出さない。** 画像が消えていたら（端末の掃除・
        // 移行）「続きから」を押しても白い画面になる。印ごと片づける
        guard FileManager.default.fileExists(atPath: fileURL(saved.imageFile).path) else {
            defaults.removeObject(forKey: key(for: userId))
            return nil
        }
        return saved
    }

    private func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// 下書きの画像。読めなければ nil
    func imageData() -> Data? {
        guard let draft else { return nil }
        return try? Data(contentsOf: fileURL(draft.imageFile))
    }

    /// 保存する。**画像を書けなかったら何も残さない**——道だけ覚えて
    /// 中身が無い状態を作らない
    @discardableResult
    func save(imageData: Data, fileName: String, contentType: String,
              coords: Photo.Coords?, caption: String, location: String,
              overlays: [TextOverlay], song: Photo.Song?, durationSec: Int,
              savedAt: String) -> Bool {
        let file = "story-draft-\(abs(key(for: userId).hashValue)).jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try imageData.write(to: fileURL(file))
        } catch {
            return false
        }
        let saved = Draft(imageFile: file, fileName: fileName, contentType: contentType,
                          latitude: coords?.lat, longitude: coords?.lng,
                          caption: caption, location: location, overlays: overlays,
                          song: song, durationSec: durationSec, savedAt: savedAt)
        guard let data = try? JSONEncoder().encode(saved) else { return false }
        defaults.set(data, forKey: key(for: userId))
        draft = saved
        return true
    }

    /// 捨てる（「捨てる」を押したとき・投稿し終えたとき）。
    /// **画像のファイルも消す**——残すと端末の容量を静かに食う
    func clear() {
        if let draft {
            try? FileManager.default.removeItem(at: fileURL(draft.imageFile))
        }
        defaults.removeObject(forKey: key(for: userId))
        draft = nil
    }
}
