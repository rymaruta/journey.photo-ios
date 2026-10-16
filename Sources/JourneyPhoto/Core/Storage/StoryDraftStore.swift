import Foundation
import Combine

/// ストーリーの下書き（モック4 の「下書き保存」）。
///
/// **1件だけ**（1件の中に並べた写真は全部入る）。ストーリーは24時間で消える一過性のもので、何本も下書きを
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

        /// **2枚目以降。** 以前は表示中の1枚しか残さず、3枚並べて「下書き保存」→
        /// 「保存しました」と出るのに、開き直すと1枚になっていた（2026-09-27 の監査）。
        /// 1枚目は上の欄にそのまま置く——前の版のアプリが読んでも1枚目は戻る。
        /// 前の版が保存した下書きには無い（nil＝1枚だけ）
        var extraShots: [Shot]?
        /// 「自分用に残す」。**戻したときに外れていると、そのまま投稿して24時間で消える**
        /// （ハイライトにも入れられない）。前の版の下書きには無い（nil＝残さない）
        var archive: Bool?
        /// 「返信を許可」。**切ったときだけ `false` を持つ**——前の版の下書きには無い
        /// （nil＝許可。既定と同じ）
        var allowReplies: Bool?
        /// 1枚目の写真の合わせ方（拡大・位置・回し）。合わせていなければ nil
        /// （前の版の下書きにも無い）
        var framing: PhotoFraming?
        /// 1枚目の投票。置いていなければ nil
        var vote: StoryVoteDraft?
        /// 自動の枠だけ: **開いていた本人の下書きの印**（その `savedAt`・2026-10-16）。本人の下書きを開いて
        /// 書いている途中で終了 →「続きから」で投稿したとき、元の下書きも片づける（残すと同じ写真がもう一度出る）
        var basedOn: String? = nil

        var coords: Photo.Coords? {
            guard let latitude, let longitude else { return nil }
            return Photo.Coords(lat: latitude, lng: longitude)
        }

        /// 並びの全部（1枚目＋2枚目以降）。**並びの順がそのまま出る順**
        var shots: [Shot] {
            [Shot(imageFile: imageFile, fileName: fileName, contentType: contentType,
                  latitude: latitude, longitude: longitude, overlays: overlays, framing: framing, vote: vote)]
                + (extraShots ?? [])
        }
    }

    /// 1枚ぶん。文字は写真ごとに持つ（焼き込みが写真ごとに起きるため）
    struct Shot: Codable, Equatable {
        var imageFile: String
        var fileName: String
        var contentType: String
        var latitude: Double?
        var longitude: Double?
        var overlays: [TextOverlay]
        /// 写真の合わせ方。合わせていなければ nil（前の版の下書きにも無い）
        var framing: PhotoFraming?
        /// 投票（写真1枚に1つ）。置いていなければ nil
        var vote: StoryVoteDraft?

        var coords: Photo.Coords? {
            guard let latitude, let longitude else { return nil }
            return Photo.Coords(lat: latitude, lng: longitude)
        }
    }

    /// 保存するときに渡す1枚ぶん（画像の中身つき）
    struct ShotInput {
        var imageData: Data
        var fileName: String
        var contentType: String
        var coords: Photo.Coords?
        var overlays: [TextOverlay]
        var framing: PhotoFraming? = nil
        var vote: StoryVoteDraft? = nil
    }

    @Published private(set) var draft: Draft?

    /// 保存のたびの印（試験で差し替えて、途中で書けない形を作る）
    var makeToken: () -> String = { String(UUID().uuidString.prefix(8)).lowercased() }

    private let defaults: UserDefaults
    private let directory: URL
    private var userId: String?

    /// 下書きの枠（2026-10-16 判断・`UploadDraftStore.Slot` と同じ考え）。
    /// `saved` は本人が「下書き保存」で残したもの、`auto` は**裏に回ったときに黙って残す書きかけ**
    /// （OS にアプリを終了されても消えない）。本人の下書きを黙って上書きしないよう、別の鍵に置く
    enum Slot: Equatable { case saved, auto }
    let slot: Slot

    /// - Parameters:
    ///   - directory: 画像を置く場所。既定は Application Support
    ///     （利用者に見せるものではなく、端末の掃除で勝手に消えては困る）
    init(defaults: UserDefaults = .standard, directory: URL? = nil, slot: Slot = .saved) {
        self.defaults = defaults
        self.slot = slot
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static let key = "journey-photo-story-draft"

    /// 枠ごとの鍵の頭。自動の枠も `journey-photo-story-draft:` で始まる——掃除（`sweepOrphans`）は
    /// どちらの枠からでも両方の画像を「指されている」と読む
    private var base: String { slot == .saved ? Self.key : "\(Self.key):auto" }

    /// **アカウントごとに分ける**（`FavoritesStore` と同じ理由——同じ端末で
    /// 人が変わったとき、前の人の書きかけを見せない）。
    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return base }
        return "\(base):\(userId)"
    }

    func use(userId: String?) {
        self.userId = userId
        draft = load()
        sweepOrphans()
    }

    /// 並びを保存するときの名前。**保存のたびに新しい印（`token`）を付ける。**
    ///
    /// 名前を毎回同じにすると、3枚のうち2枚目で書けなかった（容量不足など）ときに
    /// 1枚目だけ新しい写真に入れ替わり、前の下書きが「新しい写真＋古い文字」に
    /// 化ける（`.atomic` が守るのは1ファイルずつ）。新しい名前に全部書けてから
    /// 記録を差し替え、前の名前を消す。書けなかったら新しく書いたぶんを消して、
    /// 前の下書きには触らない
    ///
    /// 鍵の文字を16進にするので、人ごとに必ず別の名前になる。以前は `hashValue`
    /// （起動のたびに変わる）から作り、前の画像がどこからも指されないまま
    /// 残り続けた（2026-09-26）——いまは記録を差し替えたあとに前の名前を消し、
    /// 取りこぼしは `sweepOrphans` が片づける
    static func imageFileName(forKey key: String, token: String, index: Int) -> String {
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        return "\(filePrefix)\(hex)-\(token)-\(index).jpg"
    }

    private static let filePrefix = "story-draft-"

    /// 下書きの記録から画像の名前だけを読む形
    private struct ImageRef: Decodable {
        struct Extra: Decodable { let imageFile: String }
        let imageFile: String
        let extraShots: [Extra]?

        var files: [String] { [imageFile] + (extraShots ?? []).map(\.imageFile) }
    }

    /// **どの下書きからも指されていない画像を消す**（古い名前で残ったもの）。
    ///
    /// 同じ端末の別の人の下書きは消さない——`UserDefaults` にある下書きを
    /// 全員ぶん読み、指されている名前は残す。
    ///
    /// **読むのは画像の名前だけ**（`ImageRef`）。`Draft` 全体で読むと、
    /// 将来 `Draft` の形を変えたときに読めない記録が「画像を指していない」
    /// 扱いになり、画像だけ消える
    private func sweepOrphans() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let referenced = Set(defaults.dictionaryRepresentation().flatMap { entry -> [String] in
            guard entry.key == Self.key || entry.key.hasPrefix("\(Self.key):"),
                  let data = entry.value as? Data,
                  let saved = try? JSONDecoder().decode(ImageRef.self, from: data) else { return [] }
            return saved.files
        })
        for name in names where name.hasPrefix(Self.filePrefix) && name.hasSuffix(".jpg")
            && !referenced.contains(name) {
            try? FileManager.default.removeItem(at: fileURL(name))
        }
    }

    private func load() -> Draft? {
        guard let data = defaults.data(forKey: key(for: userId)),
              var saved = try? JSONDecoder().decode(Draft.self, from: data) else { return nil }
        // **中身の無い下書きを出さない。** 画像が消えていたら（端末の掃除・
        // 移行）「続きから」を押しても白い画面になる。印ごと片づける
        guard FileManager.default.fileExists(atPath: fileURL(saved.imageFile).path) else {
            // 2枚目以降の画像も残さない（どこからも指されなくなる）
            for shot in saved.extraShots ?? [] {
                try? FileManager.default.removeItem(at: fileURL(shot.imageFile))
            }
            defaults.removeObject(forKey: key(for: userId))
            return nil
        }
        // 2枚目以降は、画像が消えたものだけ外す（1枚目が在れば「続きから」は出せる）
        if let extras = saved.extraShots {
            saved.extraShots = extras.filter { FileManager.default.fileExists(atPath: fileURL($0.imageFile).path) }
        }
        return saved
    }

    private func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// 下書きの画像（1枚目）。読めなければ nil
    func imageData() -> Data? {
        guard let draft else { return nil }
        return try? Data(contentsOf: fileURL(draft.imageFile))
    }

    /// 下書きの並び（画像の中身つき）。**1枚目が読めなければ空**
    /// ——2枚目以降で読めないものは外す（並びの残りは戻す）
    func shotImages() -> [(shot: Shot, data: Data)] {
        guard let draft else { return [] }
        var result: [(shot: Shot, data: Data)] = []
        for (i, shot) in draft.shots.enumerated() {
            guard let data = try? Data(contentsOf: fileURL(shot.imageFile)) else {
                if i == 0 { return [] }
                continue
            }
            result.append((shot: shot, data: data))
        }
        return result
    }

    /// 保存する（1枚だけ）。並びは `save(shots:…)`
    @discardableResult
    func save(imageData: Data, fileName: String, contentType: String,
              coords: Photo.Coords?, caption: String, location: String,
              overlays: [TextOverlay], song: Photo.Song?, durationSec: Int,
              savedAt: String) -> Bool {
        save(shots: [ShotInput(imageData: imageData, fileName: fileName, contentType: contentType,
                               coords: coords, overlays: overlays)],
             caption: caption, location: location, song: song, durationSec: durationSec,
             savedAt: savedAt)
    }

    /// 並びごと保存する。**画像を書けなかったら何も残さない**——道だけ覚えて
    /// 中身が無い状態を作らない
    @discardableResult
    func save(shots inputs: [ShotInput], caption: String, location: String,
              song: Photo.Song?, durationSec: Int, archive: Bool = false, allowReplies: Bool = true,
              basedOn: String? = nil, savedAt: String) -> Bool {
        guard !inputs.isEmpty else { return false }
        saveGeneration += 1
        let storageKey = key(for: userId)
        let token = makeToken()
        let files = inputs.indices.map { Self.imageFileName(forKey: storageKey, token: token, index: $0) }
        var written: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (input, file) in zip(inputs, files) {
                try input.imageData.write(to: fileURL(file), options: .atomic)
                written.append(file)
            }
        } catch {
            // 途中まで書いたぶんを消す。**前の下書きはそのまま**
            for file in written {
                try? FileManager.default.removeItem(at: fileURL(file))
            }
            return false
        }
        return commit(inputs, files: files, storageKey: storageKey, caption: caption, location: location,
                      song: song, durationSec: durationSec, archive: archive, allowReplies: allowReplies,
                      basedOn: basedOn, savedAt: savedAt)
    }

    /// 保存の回（`save`・`saveInBackground`・`clear` で進む）。**後から始まった回が勝つ**
    /// （`UploadDraftStore.saveGeneration` と同じ）
    private var saveGeneration = 0

    /// 画像を書く口（**主スレッドの外で書く**・試験で差し替える）
    var writeFiles: @Sendable ([(Data, URL)]) async throws -> Void = { pairs in
        try await Task.detached(priority: .userInitiated) {
            for (data, url) in pairs { try data.write(to: url, options: .atomic) }
        }.value
    }

    /// `save` と同じことを、画像の書き込みを主スレッドの外で（裏に回ったときの自動の書きかけ・2026-10-16）。
    /// 書いている間に新しい保存・`clear` が始まったら、この回の記録は書かない
    func saveInBackground(shots inputs: [ShotInput], caption: String, location: String,
                          song: Photo.Song?, durationSec: Int, archive: Bool, allowReplies: Bool,
                          basedOn: String?, savedAt: String) async -> Bool {
        guard !inputs.isEmpty else { return false }
        saveGeneration += 1
        let mine = saveGeneration
        let storageKey = key(for: userId)
        let token = makeToken()
        let files = inputs.indices.map { Self.imageFileName(forKey: storageKey, token: token, index: $0) }
        let urls = files.map { fileURL($0) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await writeFiles(Array(zip(inputs.map(\.imageData), urls)))
        } catch {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            return false
        }
        // 書いている間に人が替わった（`use`）・新しい保存や `clear` が始まった
        guard mine == saveGeneration, storageKey == key(for: userId) else {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            return false
        }
        return commit(inputs, files: files, storageKey: storageKey, caption: caption, location: location,
                      song: song, durationSec: durationSec, archive: archive, allowReplies: allowReplies,
                      basedOn: basedOn, savedAt: savedAt)
    }

    /// 画像を書き終えた後に記録を差し替え、前の画像を消す（**前の画像は差し替える時点で読む**）
    private func commit(_ inputs: [ShotInput], files: [String], storageKey: String, caption: String,
                        location: String, song: Photo.Song?, durationSec: Int, archive: Bool,
                        allowReplies: Bool, basedOn: String?, savedAt: String) -> Bool {
        let written = files
        // 前の下書きの画像は、記録を差し替えたあとに消す
        let previous = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(ImageRef.self, from: $0) }?.files ?? []
        let shots = zip(inputs, files).map { input, file in
            Shot(imageFile: file, fileName: input.fileName, contentType: input.contentType,
                 latitude: input.coords?.lat, longitude: input.coords?.lng, overlays: input.overlays,
                 framing: input.framing, vote: input.vote)
        }
        let first = shots[0]
        var saved = Draft(imageFile: first.imageFile, fileName: first.fileName,
                          contentType: first.contentType,
                          latitude: first.latitude, longitude: first.longitude,
                          caption: caption, location: location, overlays: first.overlays,
                          song: song, durationSec: durationSec, savedAt: savedAt,
                          extraShots: shots.count > 1 ? Array(shots.dropFirst()) : nil,
                          archive: archive ? true : nil,
                          allowReplies: allowReplies ? nil : false,
                          framing: first.framing, vote: first.vote)
        saved.basedOn = basedOn
        guard let data = try? JSONEncoder().encode(saved) else {
            for file in written {
                try? FileManager.default.removeItem(at: fileURL(file))
            }
            return false
        }
        defaults.set(data, forKey: storageKey)
        draft = saved
        for name in previous where !files.contains(name) {
            try? FileManager.default.removeItem(at: fileURL(name))
        }
        return true
    }

    /// 退会した人の書きかけを消す（`AccountLocalData`）。**画像のファイルも**
    func removeData(for userId: String) {
        let draftKey = key(for: userId)
        // **記録が指している画像を全部消す**（2枚目以降も）。名前は保存のたびに
        // 変わる（`imageFileName` の印）ので、鍵から決め打ちできない
        if let data = defaults.data(forKey: draftKey),
           let saved = try? JSONDecoder().decode(ImageRef.self, from: data) {
            for file in saved.files {
                try? FileManager.default.removeItem(at: fileURL(file))
            }
        }
        defaults.removeObject(forKey: draftKey)
        if userId == self.userId { draft = nil }
        // 記録から外れて残ったもの（書きかけの途中で落ちた回）はここで拾う
        sweepOrphans()
    }

    /// 捨てる（「捨てる」を押したとき・投稿し終えたとき）。
    /// **画像のファイルも消す**——残すと端末の容量を静かに食う
    func clear() {
        saveGeneration += 1
        for shot in draft?.shots ?? [] {
            try? FileManager.default.removeItem(at: fileURL(shot.imageFile))
        }
        defaults.removeObject(forKey: key(for: userId))
        draft = nil
    }
}
