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
        sweepOrphans()
    }

    /// 画像の置き場の名前。**鍵から毎回同じ名前を作る。**
    ///
    /// 以前は `hashValue` から作っていたが、Swift の文字列の `hashValue` は
    /// **起動のたびに変わる**。起動をまたいで保存し直すと別の名前で書かれ、
    /// 前の画像はどこからも指されないまま端末に残り続けた（数MBずつ・
    /// 2026-09-26 のバグ探し）。鍵の文字を16進にするので、人ごとに必ず別の名前になる
    static func imageFileName(forKey key: String) -> String {
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        return "\(filePrefix)\(hex).jpg"
    }

    private static let filePrefix = "story-draft-"

    /// **どの下書きからも指されていない画像を消す**（古い名前で残ったもの）。
    ///
    /// 同じ端末の別の人の下書きは消さない——`UserDefaults` にある下書きを
    /// 全員ぶん読み、指されている名前は残す
    private func sweepOrphans() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let referenced = Set(defaults.dictionaryRepresentation().compactMap { entry -> String? in
            guard entry.key == Self.key || entry.key.hasPrefix("\(Self.key):"),
                  let data = entry.value as? Data,
                  let saved = try? JSONDecoder().decode(Draft.self, from: data) else { return nil }
            return saved.imageFile
        })
        for name in names where name.hasPrefix(Self.filePrefix) && name.hasSuffix(".jpg")
            && !referenced.contains(name) {
            try? FileManager.default.removeItem(at: fileURL(name))
        }
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
        let file = Self.imageFileName(forKey: key(for: userId))
        // 前の下書きが別の名前（`hashValue` 時代）なら、書き終えたあとに消す
        let previous = defaults.data(forKey: key(for: userId))
            .flatMap { try? JSONDecoder().decode(Draft.self, from: $0) }?.imageFile
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
        if let previous, previous != file {
            try? FileManager.default.removeItem(at: fileURL(previous))
        }
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
