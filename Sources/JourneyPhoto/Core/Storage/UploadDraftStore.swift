import Foundation

/// 写真の投稿の下書き（投稿の画面の ×→「下書きに保存」・2026-10-11）。
///
/// 🔴 **閉じると、選んだ写真と書いた題・説明が全部消えていた**（「投稿をやめる」「書き続ける」の
/// 2択だけ）。ストーリーの下書き（`StoryDraftStore`）と同じ考えで、**端末に置く**。
///
/// 2026-10-11 判断: **サーバーの「非公開で投稿」ではなく、端末の下書きにする。** 非公開で上げると
/// 枚数の枠を食い、題・説明・公開範囲・アルバムの選びかけが「投稿済みの写真」になって投稿の画面に
/// 戻らない（編集は写真ごとの別の画面）。端末なら、選んだ写真も欄もそのまま開き直せる。
/// 機種を変えると消えるので、画面でもそう書く。
///
/// - **人ごとに1件**（鍵に userId を入れる）。同じ端末で人が替わっても、前の人の書きかけは見えない
/// - 写真の中身（数MB）は `UserDefaults` に入れない——**ファイルに書いて、名前だけを覚える**
/// - 保存のたびに新しい印（`token`）の名前で全部書いてから記録を差し替える（途中で書けなかったら、
///   前の下書きには触らない。理由は `StoryDraftStore.imageFileName` の注記と同じ）
@MainActor
final class UploadDraftStore {

    /// 1枚ぶん（画像そのものは別のファイル）
    struct Item: Codable, Equatable {
        var imageFile: String
        var fileName: String
        var contentType: String
        var exif: ExifFields?
        var latitude: Double?
        var longitude: Double?
        var takenOn: String?
        var dominantColor: String?
        var title: String
        var caption: String
        var location: String
        /// 写真の位置から自動で入れた地名（`PendingPhoto.photoPlaceName`）。**座標を送るかの決まり**
        /// （`PlaceCoordsRule`）に要るので残す——無いと、戻した地名が「人が書いた地名」になり座標が落ちる
        var photoPlaceName: String?
        /// 入っていた撮影地を本人が空にしたか（`PendingPhoto.locationClearedByUser`）
        var locationClearedByUser: Bool
        var pickedLatitude: Double?
        var pickedLongitude: Double?
        /// 編集のレシピ。**元の写真に掛け直す**（書き出した絵は残さない——編集し直せるように）
        var recipe: PhotoRecipe?

        var coords: Photo.Coords? {
            guard let latitude, let longitude else { return nil }
            return Photo.Coords(lat: latitude, lng: longitude)
        }

        var pickedCoords: Photo.Coords? {
            guard let pickedLatitude, let pickedLongitude else { return nil }
            return Photo.Coords(lat: pickedLatitude, lng: pickedLongitude)
        }
    }

    /// 覚えておくもの（まとめて付く欄も）
    struct Draft: Codable, Equatable {
        var items: [Item]
        var tagsText: String
        var category: String
        var published: Bool
        /// `Audience.rawValue`（知らない値は「全体に公開」で戻す）
        var audience: String
        var song: Photo.Song?
        var selectedAlbumId: String?
        var groupsAsOnePost: Bool
        /// 保存した時刻（ISO8601）
        var savedAt: String
    }

    /// 保存するときに渡す1枚ぶん（画像の中身つき）
    struct ItemInput {
        var imageData: Data
        var item: Item
    }

    /// 保存のたびの印（試験で差し替えて、途中で書けない形を作る）
    var makeToken: () -> String = { String(UUID().uuidString.prefix(8)).lowercased() }

    private let defaults: UserDefaults
    private let directory: URL

    /// - Parameter directory: 画像を置く場所。既定は Application Support
    ///   （利用者に見せるものではなく、端末の掃除で勝手に消えては困る）
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static let keyPrefix = "journey-photo-upload-draft"
    private static let filePrefix = "upload-draft-"

    /// **人ごとの鍵。** ログインしていない人の下書きは作らない（空の userId は nil）
    static func key(for userId: String) -> String? {
        userId.isEmpty ? nil : "\(keyPrefix):\(userId)"
    }

    /// 画像の名前。鍵の文字を16進にするので、人ごとに必ず別の名前になる
    static func imageFileName(forKey key: String, token: String, index: Int) -> String {
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        return "\(filePrefix)\(hex)-\(token)-\(index).jpg"
    }

    private func fileURL(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// 記録から画像の名前だけを読む形（`Draft` の形を変えても、画像の後始末は読める）
    private struct ImageRef: Decodable {
        struct One: Decodable { let imageFile: String }
        let items: [One]
        var files: [String] { items.map(\.imageFile) }
    }

    private func files(atKey key: String) -> [String] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ImageRef.self, from: $0) }?.files ?? []
    }

    /// その人の下書き。**画像が1枚でも消えていたら、無いものとして片づける**
    /// ——欠けたまま戻すと、書いた題が別の写真に付く
    func draft(for userId: String) -> Draft? {
        guard let key = Self.key(for: userId),
              let data = defaults.data(forKey: key) else { return nil }
        guard let saved = try? JSONDecoder().decode(Draft.self, from: data), !saved.items.isEmpty,
              saved.items.allSatisfy({ FileManager.default.fileExists(atPath: fileURL($0.imageFile).path) }) else {
            clear(for: userId)
            return nil
        }
        return saved
    }

    /// 下書きがあるか（開いたときに「下書きを続けますか？」を出すか）
    func hasDraft(for userId: String) -> Bool { draft(for: userId) != nil }

    /// 下書きの画像（並びの順）。**1枚でも読めなければ nil**
    func images(of draft: Draft) -> [Data]? {
        var result: [Data] = []
        for item in draft.items {
            guard let data = try? Data(contentsOf: fileURL(item.imageFile)) else { return nil }
            result.append(data)
        }
        return result
    }

    /// 保存する（前の下書きは置き換える）。**画像を書けなかったら何も変えない**
    /// - Returns: 書けたか（**黙って失敗しない**——画面が知らせを出す）
    @discardableResult
    func save(_ inputs: [ItemInput], fields: Draft, for userId: String) -> Bool {
        guard let key = Self.key(for: userId), !inputs.isEmpty else { return false }
        let token = makeToken()
        let names = inputs.indices.map { Self.imageFileName(forKey: key, token: token, index: $0) }
        let previous = files(atKey: key)
        var written: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (input, name) in zip(inputs, names) {
                try input.imageData.write(to: fileURL(name), options: .atomic)
                written.append(name)
            }
        } catch {
            for name in written { try? FileManager.default.removeItem(at: fileURL(name)) }
            return false
        }
        var saved = fields
        saved.items = zip(inputs, names).map { input, name in
            var item = input.item
            item.imageFile = name
            return item
        }
        guard let data = try? JSONEncoder().encode(saved) else {
            for name in written { try? FileManager.default.removeItem(at: fileURL(name)) }
            return false
        }
        defaults.set(data, forKey: key)
        for name in previous where !names.contains(name) {
            try? FileManager.default.removeItem(at: fileURL(name))
        }
        return true
    }

    /// 捨てる（「下書きを削除」・投稿し終えたとき）。**画像のファイルも消す**
    func clear(for userId: String) {
        guard let key = Self.key(for: userId) else { return }
        for name in files(atKey: key) { try? FileManager.default.removeItem(at: fileURL(name)) }
        defaults.removeObject(forKey: key)
    }

    /// 退会した人の書きかけを消す（`AccountLocalData`）
    func removeData(for userId: String) { clear(for: userId) }
}
