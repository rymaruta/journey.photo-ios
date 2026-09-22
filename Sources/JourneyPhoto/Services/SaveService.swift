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
    private struct SavedOne: Decodable { let saved: Bool }

    /// 自分が保存した写真の id（新しい順）
    func mySaves() async throws -> [String] {
        try await api.authorized(.get, "/user/saves", as: SavedList.self).photoIds
    }

    /// この写真を保存しているか
    func isSaved(photoId: String) async throws -> Bool {
        try await api.authorized(.get, "/user/saves/\(encoded(photoId))", as: SavedOne.self).saved
    }

    /// 保存する（冪等）
    func save(photoId: String) async throws {
        try await api.authorizedVoid(.post, "/photos/\(encoded(photoId))/save")
    }

    /// 外す（冪等）
    func unsave(photoId: String) async throws {
        try await api.authorizedVoid(.delete, "/photos/\(encoded(photoId))/save")
    }
}
