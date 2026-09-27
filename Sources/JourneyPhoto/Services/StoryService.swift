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

    /// 上げ終えた画像。**送り直しで二重に出さないための目印**（`StoryUploadCenter` が
    /// 1本ごとに覚え、端末にも書く）
    struct UploadedMedia: Codable, Equatable {
        let key: String
        let publicUrl: String
        /// 上げた時刻。**古い目印は使わない**（`isFresh`）
        var uploadedAt: Date?

        /// 目印を使ってよいか。一覧（`GET /stories`）は期限内の行しか返さないので、
        /// 24時間を過ぎると「出ていたか」を確かめられない。しかも期限切れの掃除や
        /// 削除で画像の実体は消えている——古い目印で行を作ると、壊れた画像の
        /// 1本がフォロワーに出る。**少し手前（23時間）で上げ直しに切り替える**
        func isFresh(now: Date = Date()) -> Bool {
            guard let uploadedAt else { return false }
            return now.timeIntervalSince(uploadedAt) < 23 * 60 * 60
        }
    }

    /// 1本を出す（裏の係 `StoryUploadCenter` から呼ぶ）。
    ///
    /// 🔴 **送り直しで2本にしない。** サーバーは行の id を毎回新しく作る
    /// （`story-${randomUUID()}`・`stories.ts`）ので、行を作る要求が届いたのに
    /// 返事だけ落ちた回（圏外・タイムアウト・504）に送り直すと必ず2本になっていた。
    /// そこで:
    ///
    /// 1. 上げ終えた画像を `record` で覚えてもらう
    /// 2. 行を作る要求が**サーバーに断られた**（4xx）ときだけ画像を片づけ、目印を消す
    /// 3. **届いたか分からない**失敗（通信・5xx・応答の読み違い）では画像を残す
    /// 4. 送り直しで目印があれば、**先に一覧を読んで同じ画像の自分の1本を探す**。
    ///    在れば出せていたので何もしない。無ければ上げ直さずに行だけ作る
    func post(_ job: StoryUploadCenter.Job, ownerId: String,
              record: @escaping @MainActor (UploadedMedia?) -> Void) async throws {
        let media: UploadedMedia
        if let uploaded = job.uploaded {
            // **目印があれば、古くても先に一覧で探す**（期限内の1本がまだ出ていれば
            // 二重になる）。一覧を読めなければ投げる（出たか分からないまま行を作らない）
            let listed = try await list()
            if listed.contains(where: { Self.isSameMedia($0, uploaded, ownerId: ownerId) }) { return }
            if uploaded.isFresh() {
                media = uploaded
            } else {
                // 古い目印の画像は使わない（掃除で実体が消えている）。片づけてから上げ直す
                // ——使われている鍵はサーバーが消さない（`discardUpload` が 409）
                await uploads.discard(key: uploaded.key)
                await record(nil)
                media = try await upload(imageData: job.imageData)
                await record(media)
            }
        } else {
            media = try await upload(imageData: job.imageData)
            await record(media)
        }
        do {
            _ = try await createRecord(media, caption: job.caption, location: job.location,
                                       coords: job.coords, song: job.song,
                                       durationSec: job.durationSec, archive: job.archive)
        } catch {
            if case .server(let status, _)? = error as? APIError, (400..<500).contains(status) {
                // 断られた＝行は出来ていない。画像を片づけ、次は上げ直す
                await uploads.discard(key: media.key)
                await record(nil)
            }
            throw error
        }
    }

    /// その1本が、覚えておいた画像で出た自分のストーリーか。
    ///
    /// サーバーは `src` を `publicUrl` から導いた鍵で作り直す（`canonicalUploadUrl`
    /// ——配信元の URL に差し替える）ので、URL をそのまま比べずに**道（＝鍵）で比べる**
    static func isSameMedia(_ story: Story, _ media: UploadedMedia, ownerId: String) -> Bool {
        guard story.userId == ownerId, let url = URL(string: story.src) else { return false }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return !path.isEmpty && path == media.key
    }

    /// 画像を上げる（置き場所をもらって本体を置く）。置けなかったら片づけて投げる
    func upload(imageData: Data) async throws -> UploadedMedia {
        let presigned = try await uploads.presign(
            fileName: "story.jpg", fileType: "image/jpeg", fileSize: imageData.count
        )
        do {
            try await uploads.put(data: imageData, to: presigned)
        } catch {
            await uploads.discard(key: presigned.key)
            throw error
        }
        return UploadedMedia(key: presigned.key, publicUrl: presigned.publicUrl, uploadedAt: Date())
    }

    /// 上げた画像でストーリーの行を作る。**失敗しても画像は片づけない**
    /// （届いたか分からない回に片づけると、出来ていた1本の画像が消える。
    /// 片づけるかは呼び手 `post` が失敗の種類で決める）。
    ///
    /// **`key` は送らない。** サーバーは検証済みの `publicUrl` から導く。
    /// 受け取っていた頃は、自分の正当な URL と一緒に他人のキーを送り、
    /// 自分のストーリーを消すだけで相手のファイルを消せた
    /// （`api-user/src/stories.ts` の注記）。
    ///
    /// 🔴 **公開範囲は受け取らない。** ストーリーはフォロワーだけが見る
    /// （2026-09-22・owner の判断。`api-user/src/storyVisibility.ts`）。
    /// サーバーは `visibility` を読まないので、送っても何も起きない。
    @discardableResult
    func createRecord(_ media: UploadedMedia, caption: String?, location: String?,
                      coords: Photo.Coords?, song: Photo.Song? = nil, durationSec: Int? = nil,
                      archive: Bool = false) async throws -> Story? {
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
            publicUrl: media.publicUrl,
            caption: caption?.isEmpty == true ? nil : caption,
            mediaType: "image",
            location: location?.isEmpty == true ? nil : location,
            coords: (location?.isEmpty == false) ? coords.map { Body.Coords(lat: $0.lat, lng: $0.lng) } : nil,
            song: song,
            durationSec: Self.storedDuration(durationSec),
            archive: archive ? true : nil
        )
        return try await api.authorized(.post, "/stories", body: body, as: Created.self).story
    }

    /// 捨てた送信の画像を片づける。**使われている鍵はサーバーが消さない**
    /// （`upload.ts` の `discardUpload` は保存済みの写真とストーリーの鍵を残す）ので、
    /// 実は出来ていた1本の画像を消してしまうことは無い
    func discardUpload(key: String) async {
        await uploads.discard(key: key)
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
    /// 返信（♡ も含む）を受けるか。**`false` のときだけ入って返る**（既定の「受ける」は
    /// 保存されない・`stories.ts`）。読んでいなかった頃は、Web で「返信を許可」を
    /// 切った投稿にも返信欄と ♡ が出て、送ると 403 で断られていた
    let allowReplies: Bool?

    var imageURL: URL? { URL(string: src) }

    /// 返信欄と ♡ を出すか（Web の `item?.allowReplies !== false` と同じ）
    var acceptsReplies: Bool { allowReplies != false }

    /// 曲の行に出す文字（「曲名 · アーティスト」）。曲が無ければ nil
    /// **作成画面の曲の札と同じ文字**（`SongSticker.text`。2か所で作ると片方だけ変わる）
    var songLine: String? {
        song.flatMap(SongSticker.text(for:))
    }
    var isVideo: Bool { mediaType == "video" }

    var authorName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return Labels.Common.unnamedUser
    }
    private enum CodingKeys: String, CodingKey {
        case id, src, userId, displayName, caption, mediaType, location, coords
        case createdAt, expiresAt, replyCount, durationSec, song, allowReplies
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
        // 形が崩れていても一覧ごと落とさない（読めなければ既定＝受ける）
        allowReplies = (try? c.decodeIfPresent(Bool.self, forKey: .allowReplies)) ?? nil
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

    /// 定型の反応（♡ など）か。**返信の数・一覧には数えない**
    /// ——反応の画面（`StoryInsightsView`）の「いいね」と「返信」の分け方と同じ
    var isReaction: Bool { emoji?.isEmpty == false }

    private enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case uid, name, text, emoji, t
    }
}

extension Array where Element == StoryReply {
    /// 文章の返信だけ（反応を除く）
    var textReplies: [StoryReply] { filter { !$0.isReaction } }
    /// 反応（いいね）の数。**1人1つに数える**——サーバーは反応を1件ずつ足し
    /// （1人10件まで・`storyReplies.ts`）、♡ を3回押した人が「いいね 3」になって
    /// いた（反応の一覧は1人1行なので数と並びが合わなかった）。相手の分からない
    /// 反応（`uid` が無い）は1件ずつ数える
    var reactionCount: Int {
        let reactions = filter(\.isReaction)
        let people = Set(reactions.compactMap(\.uid))
        return people.count + reactions.filter { $0.uid == nil }.count
    }
}
