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

    /// パスに入れる ID。**英数字・`-`・`_` 以外は要求を出さずに失敗にする**（`PathID`）
    private func encoded(_ value: String) throws -> String {
        try PathID.segment(value)
    }

    private struct SavedList: Decodable { let photoIds: [String] }
    /// 自分が保存した写真の id（新しい順）
    func mySaves() async throws -> [String] {
        try await api.authorized(.get, "/user/saves", as: SavedList.self).photoIds
    }

    private struct MySave: Decodable { let saved: Bool }

    /// この写真を保存しているか（`GET /user/saves/{id}`・公開状態を見ない）。
    ///
    /// 画面ごとの状態はログインのときにまとめて取った控えで足りるので、
    /// **ここは `save` の 404 の確かめにだけ使う**
    func isSaved(photoId: String) async throws -> Bool {
        try await api.authorized(.get, "/user/saves/\(encoded(photoId))", as: MySave.self).saved
    }

    /// 保存する（冪等）。
    ///
    /// **404 は「保存できなかった」とは限らない**（`saves.ts`）。見えなくなった写真でも、
    /// 前から保存していた回は `{error, saved: true}` の 404 が返る。失敗と読んで画面を
    /// 未保存に戻すと、サーバーには残ったまま**解除の導線が出ない**。本文は `APIError` に
    /// 載らないので、404 のときは印を聞き直し、保存済みなら成功として返る
    func save(photoId: String) async throws {
        // ⚠️ catch の中で await しない（Xcode 26.3 のコンパイラが落ちる）
        let failure: Error?
        do {
            try await api.authorizedVoid(.post, "/photos/\(encoded(photoId))/save")
            failure = nil
        } catch {
            failure = error
        }
        guard let failure else { return }
        guard SocialService.isNotFound(failure), (try? await isSaved(photoId: photoId)) == true else { throw failure }
    }

    /// 外す（冪等）
    func unsave(photoId: String) async throws {
        try await api.authorizedVoid(.delete, "/photos/\(encoded(photoId))/save")
    }
}
