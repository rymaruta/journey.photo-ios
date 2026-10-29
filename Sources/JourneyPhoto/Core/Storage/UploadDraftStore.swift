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
/// - **人ごとに何件でも**（2026-10-29 判断・#400。鍵に userId と下書きの印を入れる・上限は `DraftLibrary.limit`）。
///   同じ端末で人が替わっても、前の人の書きかけは見えない。以前は人ごとに1件で、保存し直すと前の下書きが
///   置き換わった——その1件は `migrateLegacySaved` で新しい形の1件に移す（失わない）
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
        /// 自動の枠だけ: **本人の下書きの中の同じ1枚の印**（`key`・2026-10-16）。本人の下書きを開いて送る途中で
        /// 終了 →「続きから」で送ったとき、上がった写真を本人の下書きからも外す（残すと次にまた投稿される）
        var savedKey: String? = nil

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
        /// 「この写真を見て撮影」の元の写真（2026-10-14）。無ければ nil。**前の版の下書きには無い**（nil で読む）
        var inspired: InspiredBy.Pick? = nil
        /// 束の印（「1つの投稿にまとめる」の `groupId`・2026-10-16）。途中まで送った束を続きから送るとき、
        /// 同じ束に入れる（新しい印にすると投稿が2つに割れる）。前の版の下書きには無い（nil）
        var groupId: String? = nil
        /// 自動の枠・送信の控えだけ: **開いていた本人の下書きの印**（`Slot.entry` の ID・2026-10-29）。
        /// 続きから戻したとき、その下書きの続きにする（「この下書きを更新」の行き先・上がった写真を外す先）。
        /// 前の版の控えには無い（nil）——そのときは `savedKey` を含む下書きを探す（`entryContaining`）
        var entryId: String? = nil

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

    /// 下書きの枠（2026-10-16 判断）。
    ///
    /// - `saved`: 本人が「下書きに保存」で残したもの（今までの下書き）
    /// - `auto`: **アプリが黙って残す書きかけ**（1件）——裏に回ったとき（`scenePhase == .background`）の
    ///   自動の下書き。本人の下書きを黙って上書きしないよう、**別の鍵・別のファイル名**に置く。
    ///   画面を閉じる（投稿し終えた・やめた・下書きに保存した）と消える。残っていたら、
    ///   アプリが途中で終了した——次に開いたとき「続きから」を出す
    /// - `send(id)`: **送信の控え（投稿ごとに1件）**（2026-10-16 判断）。「投稿する」を押すたびに
    ///   その画面の控えを書き、上がった写真から外れ、空になれば消える。**ほかの枠には触らない**——
    ///   書きかけの枠を共有していた頃は、テーマ・スポットから開いた回の送信が前の書きかけを上書きするか、
    ///   控えを書かずに送るかの二択になった。残っていたら送っている途中でアプリが終了した
    ///   （次の起動で「送れなかった投稿が N 件あります」・`UploadDraftRules.interruptedNotice`）
    ///
    /// - `entry(id)`: **本人の下書きの1件**（2026-10-29 判断・#400）。人ごとに何件でも持つ（上限は
    ///   `DraftLibrary.limit`）。ID は UUID。画像が欠けても下書きごと消さない——一覧が「読めない写真」を
    ///   知らせ、「読めた分で続ける／この下書きを削除」を選ばせる（`draft(for:)` の注記）
    /// - `saved`: 前の版の「人ごとに1件」の鍵（`journey-photo-upload-draft:<userId>`）。**読むのは移すときだけ**
    ///   （`migrateLegacySaved`）。新しく書かない
    enum Slot: Equatable {
        case saved, auto
        case send(String)
        case entry(String)
    }

    let slot: Slot
    private let defaults: UserDefaults
    private let directory: URL

    /// - Parameter directory: 画像を置く場所。既定は Application Support
    ///   （利用者に見せるものではなく、端末の掃除で勝手に消えては困る）
    init(defaults: UserDefaults = .standard, directory: URL? = nil, slot: Slot = .saved) {
        self.defaults = defaults
        self.slot = slot
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static let keyPrefix = "journey-photo-upload-draft"
    private static let filePrefix = "upload-draft-"

    /// **人ごとの鍵。** ログインしていない人の下書きは作らない（空の userId は nil）。
    /// 自動の枠は `journey-photo-upload-draft:auto:<userId>`——前置きが同じなので、
    /// 起動のときの掃除（`sweepOrphans`）は両方の枠の画像を「指されている」と読む
    static func key(for userId: String, slot: Slot = .saved) -> String? {
        guard !userId.isEmpty else { return nil }
        switch slot {
        case .saved: return "\(keyPrefix):\(userId)"
        case .auto: return "\(keyPrefix):auto:\(userId)"
        case .send(let id):
            // 控えの ID は UUID だけ（区切りの「:」を含まない・取り違えない）
            guard UUID(uuidString: id) != nil else { return nil }
            return "\(sendPrefix(for: userId))\(id)"
        case .entry(let id):
            guard UUID(uuidString: id) != nil else { return nil }
            return "\(entryPrefix(for: userId))\(id)"
        }
    }

    /// その人の下書き（`Slot.entry`）の鍵の頭（`journey-photo-upload-draft:entry:<userId>:`）
    static func entryPrefix(for userId: String) -> String { "\(keyPrefix):entry:\(userId):" }

    /// 鍵の頭の後ろが UUID ちょうどなら、その ID（`journalId` と同じ取り違えない読み方）
    private static func uuidSuffix(of key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        let rest = String(key.dropFirst(prefix.count))
        guard let uuid = UUID(uuidString: rest), uuid.uuidString == rest.uppercased() else { return nil }
        return rest
    }

    /// 鍵がその人の下書き（`Slot.entry`）なら、その ID
    static func entryId(fromKey key: String, userId: String) -> String? {
        guard !userId.isEmpty else { return nil }
        return uuidSuffix(of: key, prefix: entryPrefix(for: userId))
    }

    /// その人の下書きの ID（順は決めない・並べるのは `DraftLibrary`）
    func entryIds(for userId: String) -> [String] {
        defaults.dictionaryRepresentation().keys.compactMap { Self.entryId(fromKey: $0, userId: userId) }
    }

    /// 開いている下書きの ID（`Slot.entry` のときだけ）
    var entryId: String? {
        if case .entry(let id) = slot { return id }
        return nil
    }

    /// 🔴 **前の版の「人ごとに1件」の下書きを、新しい形の1件に移す**（2026-10-29・#400）。記録を新しい鍵へ
    /// そのまま移し、前の鍵を消す。画像のファイル名は変えない（記録が同じ名前を指すので、掃除
    /// `sweepOrphans` にも消されない。次に保存し直したとき新しい名前に替わる）。
    /// 何度呼んでも同じ（前の鍵が無ければ何もしない）。
    /// - Returns: 移した下書きの ID（移すものが無ければ nil）
    @discardableResult
    func migrateLegacySaved(for userId: String, newId: String = UUID().uuidString) -> String? {
        guard let legacy = Self.key(for: userId, slot: .saved), let data = defaults.data(forKey: legacy) else {
            return nil
        }
        // 読めない記録は移さない（前の版の `draft(for:)` と同じく片づける）
        guard let saved = try? JSONDecoder().decode(Draft.self, from: data), !saved.items.isEmpty,
              let key = Self.key(for: userId, slot: .entry(newId)) else {
            sibling(.saved).clear(for: userId)
            return nil
        }
        defaults.set(data, forKey: key)
        defaults.removeObject(forKey: legacy)
        return newId
    }

    /// 1枚の印（`Item.key`）を含む、その人の下書きの ID（前の版の自動の枠・控えの `savedKey` から、
    /// どの下書きの続きかを探す）
    func entryContaining(itemKey: String, for userId: String) -> String? {
        entryIds(for: userId).first { id in
            sibling(.entry(id)).draft(for: userId)?.items.contains { $0.key == itemKey } ?? false
        }
    }

    /// その人の送信の控えの鍵の頭（`journey-photo-upload-draft:send:<userId>:`）
    static func sendPrefix(for userId: String) -> String { "\(keyPrefix):send:\(userId):" }

    /// 鍵がその人の送信の控えなら、その ID。**頭の後ろが UUID ちょうどのときだけ**——userId に「:」を
    /// 含む別の人（"a" と "a:b"）の控えを取り違えない
    static func journalId(fromKey key: String, userId: String) -> String? {
        guard !userId.isEmpty else { return nil }
        return uuidSuffix(of: key, prefix: sendPrefix(for: userId))
    }

    /// 同じ置き場の別の枠（送信の控えを開くため）
    func sibling(_ slot: Slot) -> UploadDraftStore {
        let other = UploadDraftStore(defaults: defaults, directory: directory, slot: slot)
        other.writeFiles = writeFiles
        other.makeToken = makeToken
        return other
    }

    /// その人の送信の控え（**古い順**）。中身の読めないもの・画像の欠けたものは片づけて数えない
    func journals(for userId: String) -> [(id: String, draft: Draft)] {
        let ids = defaults.dictionaryRepresentation().keys.compactMap { Self.journalId(fromKey: $0, userId: userId) }
        return ids.compactMap { id in sibling(.send(id)).draft(for: userId).map { (id: id, draft: $0) } }
            .sorted {
                let (a, b) = (Self.savedDate($0.draft.savedAt) ?? .distantPast, Self.savedDate($1.draft.savedAt) ?? .distantPast)
                return a != b ? a < b : $0.id < $1.id
            }
    }

    /// 保存した時刻の書き方（**ミリ秒まで**——同じ秒に2つ送ると古い順が決まらない）
    static func savedAtString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// 保存した時刻を読む（ミリ秒あり・なしの両方。前の版の下書きはミリ秒が無い）
    static func savedDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// 退会: その人の送信の控えを全部（記録と画像）消す。記録から外れた画像も、鍵の16進の頭と
    /// **その後ろの UUID** を確かめて拾う（別の人の画像を消さない）
    func removeAllJournals(for userId: String) {
        for key in defaults.dictionaryRepresentation().keys {
            if let id = Self.journalId(fromKey: key, userId: userId) { sibling(.send(id)).clear(for: userId) }
        }
        guard !userId.isEmpty else { return }
        removeStrayFiles(underKeyPrefix: Self.sendPrefix(for: userId))
    }

    /// 退会: その人の下書き（`Slot.entry`）を全部（記録と画像）消す。記録から外れた画像も、控えと同じく
    /// 鍵の頭と UUID を確かめて拾う（2026-10-29・#400）
    func removeAllEntries(for userId: String) {
        for id in entryIds(for: userId) { sibling(.entry(id)).clear(for: userId) }
        guard !userId.isEmpty else { return }
        removeStrayFiles(underKeyPrefix: Self.entryPrefix(for: userId))
    }

    /// 鍵の頭（その人の控え・下書き）の後ろに **UUID ちょうど** が付いた鍵の画像を消す
    /// （userId に「:」を含む別の人 "a" と "a:b" を取り違えない）
    private func removeStrayFiles(underKeyPrefix keyPrefix: String) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let head = Self.filePrefix + Self.hex(keyPrefix)
        for name in names where name.hasPrefix(head) {
            // 頭の後ろは UUID（36字＝16進で72字）と「-」
            let rest = name.dropFirst(head.count)
            guard rest.count > 73, rest[rest.index(rest.startIndex, offsetBy: 72)] == "-",
                  let id = Self.unhex(String(rest.prefix(72))), UUID(uuidString: id) != nil else { continue }
            try? FileManager.default.removeItem(at: fileURL(name))
        }
    }

    private static func hex(_ text: String) -> String { text.utf8.map { String(format: "%02x", $0) }.joined() }

    private static func unhex(_ hex: String) -> String? {
        var bytes: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func storageKey(_ userId: String) -> String? { Self.key(for: userId, slot: slot) }

    /// 画像の名前。鍵の文字を16進にするので、人ごとに必ず別の名前になる
    static func imageFileName(forKey key: String, token: String, index: Int) -> String {
        "\(filePrefix(forKey: key))\(token)-\(index).jpg"
    }

    /// その人の画像の名前の前置き（`upload-draft-<鍵の16進>-`）。終わりの `-` で、鍵が前方一致する
    /// 別の人（"a" と "ab"）を取り違えない
    static func filePrefix(forKey key: String) -> String {
        "\(filePrefix)\(hex(key))-"
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
    /// ——欠けたまま戻すと、書いた題が別の写真に付く。
    ///
    /// 🔴 **本人の下書き（`Slot.entry`）だけは、欠けても片づけない**（2026-10-29 判断・#400）。以前は
    /// 1枚でも読めないと下書きごと黙って消えていた。一覧が「n枚を読み込めません」と知らせ、
    /// 「読めた分で続ける」（欠けた写真の題は戻さない・`presentItems`）か「この下書きを削除」を選ばせる
    func draft(for userId: String) -> Draft? {
        guard let key = storageKey(userId),
              let data = defaults.data(forKey: key) else { return nil }
        guard let saved = try? JSONDecoder().decode(Draft.self, from: data), !saved.items.isEmpty else {
            clear(for: userId)
            return nil
        }
        if entryId != nil { return saved }
        guard saved.items.allSatisfy({ hasImage($0) }) else {
            clear(for: userId)
            return nil
        }
        return saved
    }

    /// その1枚の画像が端末に在るか
    func hasImage(_ item: Item) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(item.imageFile).path)
    }

    /// 画像の在る写真だけ（並びの順）。「読めた分で続ける」で戻すもの
    func presentItems(_ items: [Item]) -> [Item] { items.filter(hasImage) }

    /// 画像の置き場所（一覧の縮図を読む・大きさを数える）
    func imageURL(_ item: Item) -> URL { fileURL(item.imageFile) }

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
        guard let key = storageKey(userId), !inputs.isEmpty else { return false }
        _ = bump(key)
        let token = makeToken()
        let names = inputs.indices.map { Self.imageFileName(forKey: key, token: token, index: $0) }
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
        return commit(inputs, names: names, fields: fields, key: key)
    }

    /// 保存の回（**鍵ごと**・`save`・`saveInBackground`・`clear`・1枚ずつの書き換えで進む）。
    /// **後から始まった回が勝つ**——先に始まった裏の書き込みが遅れて終わっても、新しい記録・
    /// 1枚ずつ外した記録を古い中身で上書きしない。入れ物（このクラスの1つ）ごとではなく鍵ごとに数える——
    /// 同じ鍵を別の入れ物から触っても（`sibling`・起動の知らせ）同じ数を見る
    private static var generations: [String: Int] = [:]

    private func bump(_ key: String) -> Int {
        let next = (Self.generations[key] ?? 0) + 1
        Self.generations[key] = next
        return next
    }

    /// 画像を書く口（**主スレッドの外で書く**・試験で遅らせて順番を作る）
    var writeFiles: @Sendable ([(Data, URL)]) async throws -> Void = { pairs in
        try await Task.detached(priority: .userInitiated) {
            for (data, url) in pairs { try data.write(to: url, options: .atomic) }
        }.value
    }

    /// `save` と同じことを、**画像の書き込みを主スレッドの外で**する（2026-10-16 判断）。
    /// 送信の控え（最大10枚）と裏に回ったときの自動の書きかけで使う——主スレッドで数十MB書くと、
    /// 「投稿する」を押した直後や裏に回る瞬間に画面が固まる。
    /// 書いている間に新しい保存・`clear` が始まったら、この回の記録は書かない（書いた画像も消す）
    func saveInBackground(_ inputs: [ItemInput], fields: Draft, for userId: String) async -> Bool {
        guard let key = storageKey(userId), !inputs.isEmpty else { return false }
        let mine = bump(key)
        let token = makeToken()
        let names = inputs.indices.map { Self.imageFileName(forKey: key, token: token, index: $0) }
        let urls = names.map { fileURL($0) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await writeFiles(Array(zip(inputs.map(\.imageData), urls)))
        } catch {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            return false
        }
        guard mine == Self.generations[key] else {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            return false
        }
        return commit(inputs, names: names, fields: fields, key: key)
    }

    /// 画像を書き終えた後に記録を差し替え、前の画像を消す（**前の画像は差し替える時点で読む**）
    private func commit(_ inputs: [ItemInput], names: [String], fields: Draft, key: String) -> Bool {
        let previous = files(atKey: key)
        let written = names
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
        guard let key = storageKey(userId), let data = defaults.data(forKey: key),
              var saved = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        let before = saved.items
        change(&saved.items)
        guard saved.items != before else { return }
        // 書いている途中の裏の保存が、外した写真を書き戻さないように
        _ = bump(key)
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

    /// 記録にある下書きから「この写真を見て撮影」の元の写真を外す（付ける1枚の保存が通ったとき）。
    /// 写真と欄はそのまま
    func clearInspired(for userId: String) {
        guard let key = storageKey(userId), let data = defaults.data(forKey: key),
              var saved = try? JSONDecoder().decode(Draft.self, from: data), saved.inspired != nil else { return }
        _ = bump(key)
        saved.inspired = nil
        if let encoded = try? JSONEncoder().encode(saved) { defaults.set(encoded, forKey: key) }
    }

    /// 捨てる（「下書きを削除」・投稿し終えたとき）。**画像のファイルも消す**
    func clear(for userId: String) {
        guard let key = storageKey(userId) else { return }
        // 書いている途中の裏の保存（`saveInBackground`）が、消した後に記録を書き戻さないように
        _ = bump(key)
        for name in files(atKey: key) { try? FileManager.default.removeItem(at: fileURL(name)) }
        defaults.removeObject(forKey: key)
    }

    /// 退会した人の書きかけを消す（`AccountLocalData`）。**記録から外れた画像も**、その人の鍵の
    /// 16進の前置き（`imageFileName`）で拾って消す（書きかけの途中で落ちた回の取りこぼし）
    func removeData(for userId: String) {
        clear(for: userId)
        guard let key = storageKey(userId),
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
