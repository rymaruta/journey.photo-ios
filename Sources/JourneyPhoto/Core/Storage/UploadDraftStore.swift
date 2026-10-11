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
        /// この1枚の印（保存のときに付ける）。投稿が上がった写真を**1枚ずつ**下書きから外すのに使う
        var key: String? = nil
        /// 🔴 **送り始めた（届いたか分からない）。** 送る直前に立て、上がったら1枚ごと外し、
        /// 届いていないと分かったら下ろす（`UploadViewModel.submit`）。送っている途中でアプリが落ちた・
        /// 届いたか分からないまま閉じた写真は立ったまま残り、**開き直しても戻さない**（2026-10-11 判断・
        /// `UploadDraftStore.restorable`）——戻すと、届いていた写真がもう一度投稿される
        var inFlight: Bool? = nil

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
        /// 撮影スポットの紐付け（スポットの画面から開いた投稿）。無ければ nil
        var spot: Spot? = nil

        /// スポットの紐付け（`UploadSpotTarget` の写し）
        struct Spot: Codable, Equatable {
            var spotId: String
            var name: String
            var latitude: Double?
            var longitude: Double?
        }
    }

    /// 開き直す写真と、届いたか分からないので外す写真の数（`Item.inFlight` の注記）
    static func restorable(_ draft: Draft) -> (items: [Item], dropped: Int) {
        let items = draft.items.filter { $0.inFlight != true }
        return (items, draft.items.count - items.count)
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
        "\(filePrefix(forKey: key))\(token)-\(index).jpg"
    }

    /// その人の画像の名前の前置き（`upload-draft-<鍵の16進>-`）。終わりの `-` で、鍵が前方一致する
    /// 別の人（"a" と "ab"）を取り違えない
    static func filePrefix(forKey key: String) -> String {
        "\(filePrefix)\(key.utf8.map { String(format: "%02x", $0) }.joined())-"
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

    /// 写真の画像（並びの順）。**1枚でも読めなければ nil**
    func images(of items: [Item]) -> [Data]? {
        var result: [Data] = []
        for item in items {
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
            if item.key == nil { item.key = UUID().uuidString }
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

    /// 記録を読み、1枚ずつの書き換えをして書き戻す（画像は書き換えない）。最後の1枚が外れたら下書きごと消す
    private func update(for userId: String, _ change: (inout [Item]) -> Void) {
        guard let key = Self.key(for: userId), let data = defaults.data(forKey: key),
              var saved = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        let before = saved.items
        change(&saved.items)
        guard saved.items != before else { return }
        let kept = Set(saved.items.map(\.imageFile))
        if saved.items.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let encoded = try? JSONEncoder().encode(saved) {
            defaults.set(encoded, forKey: key)
        } else {
            return
        }
        for item in before where !kept.contains(item.imageFile) {
            try? FileManager.default.removeItem(at: fileURL(item.imageFile))
        }
    }

    /// 🔴 **投稿が上がった1枚を外す**（上がるたびにすぐ・2026-10-11）。束の終わりまで待つと、途中で
    /// アプリが落ちたときに上がった写真が下書きに残り、開き直して二重に投稿していた
    func removeItem(key itemKey: String, for userId: String) {
        update(for: userId) { $0.removeAll { $0.key == itemKey } }
    }

    /// 送り始めた（`true`）・届いていないと分かった（`false`）の印（`Item.inFlight`）
    func setInFlight(_ inFlight: Bool, key itemKey: String, for userId: String) {
        update(for: userId) { items in
            for i in items.indices where items[i].key == itemKey { items[i].inFlight = inFlight ? true : nil }
        }
    }

    /// 捨てる（「下書きを削除」・投稿し終えたとき）。**画像のファイルも消す**
    func clear(for userId: String) {
        guard let key = Self.key(for: userId) else { return }
        for name in files(atKey: key) { try? FileManager.default.removeItem(at: fileURL(name)) }
        defaults.removeObject(forKey: key)
    }

    /// 退会した人の書きかけを消す（`AccountLocalData`）。**記録から外れた画像も**、その人の鍵の
    /// 16進の前置き（`imageFileName`）で拾って消す（書きかけの途中で落ちた回の取りこぼし）
    func removeData(for userId: String) {
        clear(for: userId)
        guard let key = Self.key(for: userId),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let prefix = Self.filePrefix(forKey: key)
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: fileURL(name))
        }
    }

    /// **どの下書きからも指されていない画像を消す**（起動のとき・`StoryDraftStore.sweepOrphans` と同じ形）。
    /// 保存の途中で落ちた回・前の名前の消し損ねが残り、端末の容量を静かに食う。
    /// 同じ端末の別の人の下書きは消さない——全員ぶんの記録を読み、指されている名前は残す
    func sweepOrphans() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let referenced = Set(defaults.dictionaryRepresentation().flatMap { entry -> [String] in
            guard entry.key.hasPrefix("\(Self.keyPrefix):"), let data = entry.value as? Data,
                  let saved = try? JSONDecoder().decode(ImageRef.self, from: data) else { return [] }
            return saved.files
        })
        for name in names where name.hasPrefix(Self.filePrefix) && name.hasSuffix(".jpg")
            && !referenced.contains(name) {
            try? FileManager.default.removeItem(at: fileURL(name))
        }
    }
}
