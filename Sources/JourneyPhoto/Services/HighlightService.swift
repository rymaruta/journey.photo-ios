import Foundation

/// ストーリーハイライト（モック2-5）。
///
/// **アーカイブしたストーリーを束ねて、マイページに輪として並べる。**
/// 中身はストーリーそのものなので、**見られるのは本人とフォロワーだけ**
/// （`api-user/src/highlights.ts` の `canSeeHighlights`）。
/// 追っていない人には**0件**が返る——エラーではないので、画面は
/// 「まだ無い」と同じ絵にする（赤い1行を出さない）。
struct HighlightService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 名前の長さの上限。**サーバーと対**（`HIGHLIGHT_TITLE_MAX`）。
    /// ずれると、入れ終わってから 400 で断られる
    static let titleMax = 30
    /// 1つに入れられるストーリーの数（`STORIES_PER_HIGHLIGHT`）
    static let storiesMax = 100
    /// 1人が持てる輪の数（`HIGHLIGHTS_PER_USER`）
    static let perUser = 20

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// その人の輪の一覧。**追っていなければ空**（404 ではない）
    func list(userId: String) async throws -> [Highlight] {
        try await api.authorized(.get, "/highlights/\(encoded(userId))", as: HighlightList.self).highlights
    }

    /// 輪の中身。**追っていない人には 404**（在ることも教えない）
    func contents(userId: String, id: String) async throws -> HighlightContents {
        try await api.authorized(.get, "/highlights/\(encoded(userId))/\(encoded(id))", as: HighlightContents.self)
    }

    /// 自分のアーカイブ（24時間で消えたあとも本人だけ見られるストーリー）。
    /// **輪に入れられるのはここに在るものだけ**
    func archive() async throws -> [Story] {
        try await api.authorized(.get, "/stories/archive", as: [Story].self)
    }

    private struct Created: Decodable { let highlight: Highlight? }
    private struct Body: Encodable {
        let title: String
        let storyIds: [String]
        /// 表紙。**並びの中のどれか**でなければサーバーが断る
        let coverStoryId: String?
    }

    @discardableResult
    func create(title: String, storyIds: [String], coverStoryId: String?) async throws -> Highlight? {
        try await api.authorized(.post, "/highlights",
                                 body: Body(title: title, storyIds: storyIds, coverStoryId: coverStoryId),
                                 as: Created.self).highlight
    }

    @discardableResult
    func update(id: String, title: String, storyIds: [String], coverStoryId: String?) async throws -> Highlight? {
        try await api.authorized(.put, "/highlights/\(encoded(id))",
                                 body: Body(title: title, storyIds: storyIds, coverStoryId: coverStoryId),
                                 as: Created.self).highlight
    }

    func delete(id: String) async throws {
        try await api.authorizedVoid(.delete, "/highlights/\(encoded(id))")
    }

    /// 編集画面の「保存」を押せるか。名前が要る・1件以上入っている（**サーバーと
    /// 同じ線**——名前が空なら 400、0件なら 400）・保存中でない。
    ///
    /// 🔴 **読み込みに失敗している間は押せない。** 直すときは、いま入っている
    /// 並び（contents）が取れないと選択が空のまま始まる。そこで1件選んで
    /// 保存すると、サーバーは並びを**丸ごと置き換える**（`highlights.ts` の
    /// `SET storyIds = :ids`）ので、元の並びが消える
    static func canSave(title: String, picked: [String], saving: Bool,
                        loading: Bool, loadFailed: Bool) -> Bool {
        !saving && !loading && !loadFailed
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !picked.isEmpty
    }

    /// 選び直したあとの表紙。🔴 **いまの表紙がまだ並びに在れば変えない**——選び直す
    /// たびに先頭へ替えていたので、直すだけで表紙が黙って替わった。外したときだけ
    /// 先頭にする（サーバーも省いたときは先頭・並びに無いものは断る——`highlights.ts` の `pickCover`）
    static func cover(keeping current: String?, in picked: [String]) -> String? {
        if let current, picked.contains(current) { return current }
        return picked.first
    }

    /// 選んだ数と表紙の一文。**表紙は何件目かで言う**（直すときはサーバーが持つ
    /// 表紙を引き継ぐので、「最初の1件」とは限らない）
    static func pickedNote(picked: [String], coverId: String?) -> String {
        let at = coverId.flatMap { picked.firstIndex(of: $0) } ?? 0
        return L("\(picked.count)件を選んでいます。表紙: \(at + 1)件目",
                 "\(picked.count) selected. Cover: #\(at + 1)")
    }

    /// **そのハイライトはもう無い**（404）。消された・持ち主が退会した・
    /// フォローを外して見えなくなった、のどれも `highlights.ts` は 404 で返す。
    /// 押し直しても直らないので、画面は「通信を確かめて」と言わず再試行も出さない
    static func isGone(_ error: Error) -> Bool {
        if case .server(404, _)? = error as? APIError { return true }
        return false
    }

    /// 保存・削除に失敗したときに出す一文。
    ///
    /// **サーバーの断り文をそのまま出す。** `highlights.ts` は、選択が空・
    /// アーカイブに無い・表紙が並びに無い（400）、見つからない（404）、
    /// 20個の上限（403）を、どれも直し方の分かる本文つきで返す。
    /// 以前はどれも「もう一度お試しください」にしていたので、上限に
    /// 当たった人が何度押しても同じ文だった。
    ///
    /// 403 も本文を出す——ここの 403 は上限で、`APIError` の汎用の
    /// 「権限がありません」ではない。401・通信の失敗は `APIError` の文に任せる
    static func failureMessage(for error: Error, fallback: String) -> String {
        if case .server(let status, let message)? = error as? APIError,
           status != 401, !message.isEmpty {
            return message
        }
        return (error as? LocalizedError)?.errorDescription ?? fallback
    }
}

private struct HighlightList: Decodable { let highlights: [Highlight] }

/// 輪ひとつぶん（一覧に出る形）。
struct Highlight: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    /// 入っているストーリーの数。**数えた値**（サーバーが並びの長さを返す）
    let count: Int?
    /// 表紙。消えた行を落とした結果、**1枚も残っていないことがある**
    let cover: Cover?

    private enum CodingKeys: String, CodingKey { case id, title, count, cover }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        // **表紙の形が崩れていても、一覧ごと落とさない**（表紙を伏せるだけ）——
        // 形の食い違いで輪が1つも出なかったのがこの直しの発端
        cover = (try? c.decodeIfPresent(Cover.self, forKey: .cover)) ?? nil
    }

    /// 🔴 **サーバーは表紙を `{src, mediaType}` で返す**（`highlights.ts` の `resolveCover`・
    /// Web も `h.cover.src` で読む）。文字列として読んでいたので、表紙のある輪が1つでも
    /// あると**一覧ごと読めず、ハイライトが1つも出なかった**。古い形（文字列）も読む
    struct Cover: Decodable, Equatable {
        let src: String
        let mediaType: String?

        var isVideo: Bool { mediaType?.hasPrefix("video") ?? false }

        init(src: String, mediaType: String? = nil) {
            self.src = src
            self.mediaType = mediaType
        }

        private enum CodingKeys: String, CodingKey { case src, mediaType }

        init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.init(src: text)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(src: try c.decode(String.self, forKey: .src),
                      mediaType: try c.decodeIfPresent(String.self, forKey: .mediaType))
        }
    }

    /// 表紙の絵。**動画の表紙は絵として読めないので出さない**（地の円にする）
    var coverURL: URL? {
        guard let cover, !cover.isVideo else { return nil }
        return URL(string: cover.src)
    }
    /// 名前が空のまま保存されることはないが、古い行に備えて空は伏せる
    var displayTitle: String { title.isEmpty ? L("ハイライト", "Highlight") : title }
}

/// 輪の中身。
struct HighlightContents: Decodable, Equatable {
    let id: String
    let title: String
    let coverStoryId: String?
    let items: [Story]
}
