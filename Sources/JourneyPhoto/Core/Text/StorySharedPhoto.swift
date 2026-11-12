import Foundation

/// **ストーリーで紹介された写真を開く**（2026-11-11・札 #541 の ①）。見る画面の「写真を見る」が使う。
///
/// 紹介できるのは全体に公開した写真だけ（`api-user/src/storyPhotoShare.ts`）なので、写真の中身は
/// **取り直した公開の一覧から引き当てる**（控えの一覧は使わない）。そのうえで、**開く前にサーバーへ確かめる**
/// （`verified`・コメントの読み口がいまの公開・範囲・削除を見る）。どちらかで外れたら開かずに知らせる
/// （空の詳細・もう見られない写真を開かない）。持ち主とのあいだのブロックは端末でも見る。
/// 写真がもう見られないストーリーは、サーバーが本人以外にはそもそも返さない
enum StorySharedPhoto {

    static func find(_ id: String, in feed: [Photo]?) -> Photo? {
        guard PathID.isSafe(id) else { return nil }
        return feed?.first { $0.id == id }
    }

    /// 開いてよい写真。一覧に無い・持ち主をブロックしている（どちら向きでも端末が知っているぶん）・
    /// サーバーの確かめ（`check`）が通らない（断られた・読めなかった）なら nil（「今は開けません」）
    static func verified(_ id: String, in feed: [Photo]?, blocked: Set<String>,
                         check: (String) async throws -> Void) async -> Photo? {
        guard let photo = find(id, in: feed) else { return nil }
        if let owner = photo.userId ?? photo.uploadedBy, blocked.contains(owner) { return nil }
        do {
            try await check(photo.id)
        } catch {
            return nil
        }
        return photo
    }

    static let unavailableMessage = L("この写真は今は開けません", "This photo can't be opened right now")

    /// 「24時間後も自分用に残す」の出し方（誰に見せるのシート）。
    ///
    /// **紹介した写真だけが残らない**（サーバーも紹介の1枚には `archive` を書かない・作る画面も1枚ずつ外す）。
    /// 全部が紹介の1枚なら切り替えを出さない。混ぜたときは出して、紹介の写真は残らないと添える
    enum KeepToggle: Equatable {
        case hidden
        case shown(note: String?)
    }

    static func keepToggle(sharedFlags: [Bool]) -> KeepToggle {
        if !sharedFlags.isEmpty, sharedFlags.allSatisfy({ $0 }) { return .hidden }
        return .shown(note: sharedFlags.contains(true) ? keepSkipsSharedNote : nil)
    }

    static let keepSkipsSharedNote = L("紹介した写真は残りません", "Shared photos aren't kept")
}
