import Foundation

/// ストーリー（24時間で消える投稿）。
struct StoryService {

    private let api: APIClient
    private let uploads: UploadService

    init(api: APIClient) {
        self.api = api
        self.uploads = UploadService(api: api)
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// 一覧。**応答は配列そのもの**（`{ items: [...] }` ではない）。
    /// ブロックした相手・された相手は両向きに落とされて返る。
    func list() async throws -> [Story] {
        try await api.authorized(.get, "/stories", as: [Story].self)
    }

    private struct Created: Decodable { let story: Story? }

    /// 画像を上げてストーリーを作る。
    ///
    /// **`key` は送らない。** サーバーは検証済みの `publicUrl` から導く。
    /// 受け取っていた頃は、自分の正当な URL と一緒に他人のキーを送り、
    /// 自分のストーリーを消すだけで相手のファイルを消せた
    /// （`api-user/src/stories.ts` の注記）。
    @discardableResult
    /// 🔴 **公開範囲は受け取らない。** ストーリーはフォロワーだけが見る
    /// （2026-09-22・owner の判断。`api-user/src/storyVisibility.ts`）。
    /// サーバーは `visibility` を読まないので、送っても何も起きない。
    func create(imageData: Data, caption: String?, location: String?, coords: Photo.Coords?,
                song: Photo.Song? = nil, durationSec: Int? = nil,
                archive: Bool = false) async throws -> Story? {
        let presigned = try await uploads.presign(
            fileName: "story.jpg", fileType: "image/jpeg", fileSize: imageData.count
        )
        do {
            try await uploads.put(data: imageData, to: presigned)
        } catch {
            await uploads.discard(key: presigned.key)
            throw error
        }

        struct Body: Encodable {
            let publicUrl: String
            let caption: String?
            let mediaType: String
            let location: String?
            let coords: Coords?
            /// ストーリーのBGM。**`title` と https の `previewUrl` が要る**
            /// （`stories.ts` はホストまで見て、外部の任意URLを弾く）
            let song: Photo.Song?
            /// 表示秒数。**3〜15**（`stories.ts` が丸める）。既定の5なら送らない
            let durationSec: Int?
            /// 24時間のあとも自分用に残すか。**`true` のときだけ送る**
            /// ——サーバーは `archive === true` だけを見る（`stories.ts`）。
            /// 残したものだけがハイライトに入れられる
            let archive: Bool?
            struct Coords: Encodable { let lat: Double; let lng: Double }
        }
        // 座標は地名とセットのときだけ持つ（名前の無い点は画面に出しようがない）
        let body = Body(
            publicUrl: presigned.publicUrl,
            caption: caption?.isEmpty == true ? nil : caption,
            mediaType: "image",
            location: location?.isEmpty == true ? nil : location,
            coords: (location?.isEmpty == false) ? coords.map { Body.Coords(lat: $0.lat, lng: $0.lng) } : nil,
            song: song,
            durationSec: Self.storedDuration(durationSec),
            archive: archive ? true : nil
        )
        do {
            return try await api.authorized(.post, "/stories", body: body, as: Created.self).story
        } catch {
            await uploads.discard(key: presigned.key)
            throw error
        }
    }

    /// 既定（5秒）なら送らない——サーバーも既定は保存しない
    /// （`stories.ts` の `STORY_DEFAULT_DURATION_SEC`）。
    static let defaultDurationSec = 5
    static let durationRange = 3...15

    static func storedDuration(_ value: Int?) -> Int? {
        guard let value else { return nil }
        let clamped = min(durationRange.upperBound, max(durationRange.lowerBound, value))
        return clamped == defaultDurationSec ? nil : clamped
    }

    func delete(id: String) async throws {
        try await api.authorizedVoid(.delete, "/stories/\(encoded(id))")
    }

    /// 見たことを伝える。**失敗しても画面は止めない**（既読が付かないだけ）。
    func markViewed(id: String) async {
        _ = try? await api.authorizedVoid(.post, "/stories/\(encoded(id))/view")
    }

    /// **応答の鍵は `viewers`**（`users` ではない）。`api-user/src/stories.ts`
    /// の `getStoryViewers` が `{ viewers, count }` を返す。
    struct ViewerList: Decodable { let viewers: [StoryViewer]? }

    /// 見た人の一覧。**本人だけが読める**（他人が叩くと 403）。
    func viewers(id: String) async throws -> [StoryViewer] {
        try await api.authorized(.get, "/stories/\(encoded(id))/viewers", as: ViewerList.self).viewers ?? []
    }

    struct ReplyList: Decodable { let items: [StoryReply]? }

    func replies(id: String) async throws -> [StoryReply] {
        try await api.authorized(.get, "/stories/\(encoded(id))/replies", as: ReplyList.self).items ?? []
    }

    func reply(id: String, text: String) async throws {
        struct Body: Encodable { let text: String }
        try await api.authorizedVoid(.post, "/stories/\(encoded(id))/replies", body: Body(text: text))
    }

    /// 定型の反応。**サーバーが受けるのはこの6つだけ**
    /// （`api-user/src/storyReplies.ts` の `REACTIONS`。一覧に無い絵文字は
    /// 本文として扱われ、上限と切り詰めを通る）。
    static let reactions = ["❤️", "😍", "😂", "😮", "😢", "👏"]

    func react(id: String, emoji: String) async throws {
        struct Body: Encodable { let emoji: String }
        try await api.authorizedVoid(.post, "/stories/\(encoded(id))/replies", body: Body(emoji: emoji))
    }

    /// 24時間で消える前に、自分の写真として残す。
    func keep(id: String) async throws {
        try await api.authorizedVoid(.post, "/stories/\(encoded(id))/keep")
    }
}

struct Story: Decodable, Identifiable, Equatable {
    let id: String
    let src: String
    let userId: String?
    let displayName: String?
    let caption: String?
    let mediaType: String?
    let location: String?
    let coords: Photo.Coords?
    let createdAt: String?
    let expiresAt: String?
    /// **本人にしか返らない**（見た人には落として返る）
    let replyCount: Int?
    /// 投稿者が選んだ表示秒数（3〜15）。**既定の5は保存されないので `nil`**。
    /// 復号していなかった頃は、投稿画面で選んだ秒数が閲覧では一度も効いていなかった
    let durationSec: Int?
    /// 付けた曲（`stories.ts` が保存して返している）。**復号していなかったので、
    /// 曲つきのストーリーでも閲覧画面に曲名が出なかった**
    let song: Photo.Song?

    var imageURL: URL? { URL(string: src) }

    /// 曲の行に出す文字（「曲名 · アーティスト」）。曲が無ければ nil
    var songLine: String? {
        guard let song else { return nil }
        let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? title : "\(title) · \(artist)"
    }
    var isVideo: Bool { mediaType == "video" }

    var authorName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return Labels.Common.unnamedUser
    }
    private enum CodingKeys: String, CodingKey {
        case id, src, userId, displayName, caption, mediaType, location, coords
        case createdAt, expiresAt, replyCount, durationSec, song
    }

    /// **曲だけは壊れていても捨てる。** 一覧は配列1本で復号するので、
    /// 1本の曲の形が崩れていると**全員のストーリーが消える**。曲は飾りなので、
    /// 読めなければ曲なしとして出す
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        src = try c.decode(String.self, forKey: .src)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        coords = try c.decodeIfPresent(Photo.Coords.self, forKey: .coords)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        replyCount = try c.decodeIfPresent(Int.self, forKey: .replyCount)
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
        song = (try? c.decodeIfPresent(Photo.Song.self, forKey: .song)) ?? nil
    }
}

/// ストーリーを見た人。名前を出していない人は `displayName` が無い。
struct StoryViewer: Decodable, Identifiable, Equatable {
    let userId: String
    let displayName: String?
    let deleted: Bool?
    /// 見た時刻（ISO8601）
    let at: String?

    var id: String { userId }

    var name: String {
        if deleted == true { return Labels.Common.deletedUser }
        if let displayName, !displayName.isEmpty { return displayName }
        return Labels.Common.unnamedUser
    }
}

struct StoryReply: Decodable, Identifiable, Equatable {
    /// サーバーが id を持たない回があるので、無ければ相手と時刻で作る
    let rawId: String?
    let uid: String?
    let name: String?
    let text: String?
    /// **定型の反応**（❤️😍😂😮😢👏）。`api-user/src/storyReplies.ts` は
    /// これを `text` ではなく `emoji` に入れて返す——見ていないと**空行**になる
    let emoji: String?
    let t: String?

    var id: String { rawId ?? [(uid ?? ""), (t ?? "")].joined(separator: "|") }

    /// 画面に出す中身。絵文字の反応は `emoji` に入っている。
    var body: String { (text?.isEmpty == false ? text : nil) ?? emoji ?? "" }

    private enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case uid, name, text, emoji, t
    }
}
