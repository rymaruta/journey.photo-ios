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

    /// 写真がもう見えない（404）が、**自分の保存は残っている**。
    ///
    /// サーバーはこの回、404 の本文に `saved: true` を添える（`saves.ts` の
    /// `savePhoto`）。捨てて「保存できなかった」と巻き戻すと、サーバーには
    /// 保存が在るのにしおりが空になり、**開いている間は外す導線が出ない**。
    struct GoneButSaved: LocalizedError {
        var errorDescription: String? {
            L("この写真はもう公開されていません（保存は残っています）",
              "This photo is no longer available (it's still in your saves)")
        }
    }

    private struct SavedState: Decodable { let saved: Bool }

    /// 保存する（冪等）
    ///
    /// - Throws: 写真が見えないが保存は残っている回は `GoneButSaved`。
    ///   呼び出し側はしおりを「保存済み」に合わせる
    func save(photoId: String) async throws {
        do {
            try await api.authorizedVoid(.post, "/photos/\(encoded(photoId))/save")
        } catch APIError.server(let status, let message) where status == 404 {
            // `APIClient` は失敗の本文を `error` の文しか残さないので、
            // 保存が残っているかは**マーカーに聞き直す**（`GET /user/saves/{id}`
            // ——サーバーが 404 に添える `saved` と同じ `hasMarker` が答える）。
            // 聞けなかった回は元の失敗をそのまま返す（保存済みと言い張らない）
            let state = try? await api.authorized(.get, "/user/saves/\(encoded(photoId))", as: SavedState.self)
            if state?.saved == true { throw GoneButSaved() }
            throw APIError.server(status: status, message: message)
        }
    }

    /// 外す（冪等）
    func unsave(photoId: String) async throws {
        try await api.authorizedVoid(.delete, "/photos/\(encoded(photoId))/save")
    }
}
