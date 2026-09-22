import Foundation

/// 写真の「保存」（ブックマーク）。**いいねとは別物**。
///
/// 🔴 このアプリは長いあいだ、保存にも**いいねの控え**
/// （`FavoritesStore`）を使っていた。同じ入れ物なので:
///
///   - 保存を押すとハートが灯り、いいねの数が1増えて見えた
///   - マイページの「いいねした写真」に、**保存しただけの写真が並んだ**
///
/// サーバーには前から別の口がある（`api-user/src/saves.ts`）ので、
/// そちらに繋ぐ。**保存は人に見せない操作**なので、公開の数は無い。
struct SaveService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private struct SavedList: Decodable { let photoIds: [String] }
    /// 自分が保存した写真の id（新しい順）
    func mySaves() async throws -> [String] {
        try await api.authorized(.get, "/user/saves", as: SavedList.self).photoIds
    }

    // ⚠️ **`GET /user/saves/{id}`（1枚ぶんの問い合わせ）は呼んでいない。**
    // ログインのときに一覧をまとめて取って控えに入れるので、画面ごとに
    // 聞き直す必要が無い。使わない口の薄い包みを置かない
    // （置くと、次の人が「どちらを使うのか」を考えることになる）。

    /// 保存する（冪等）
    func save(photoId: String) async throws {
        try await api.authorizedVoid(.post, "/photos/\(encoded(photoId))/save")
    }

    /// 外す（冪等）
    func unsave(photoId: String) async throws {
        try await api.authorizedVoid(.delete, "/photos/\(encoded(photoId))/save")
    }
}
