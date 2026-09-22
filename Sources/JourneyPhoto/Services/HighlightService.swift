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
}

private struct HighlightList: Decodable { let highlights: [Highlight] }

/// 輪ひとつぶん（一覧に出る形）。
struct Highlight: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    /// 入っているストーリーの数。**数えた値**（サーバーが並びの長さを返す）
    let count: Int?
    /// 表紙の絵。消えた行を落とした結果、**1枚も残っていないことがある**
    let cover: String?

    var coverURL: URL? { cover.flatMap(URL.init(string:)) }
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
