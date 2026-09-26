import Foundation

extension ModerationStore {
    /// ブロックして、**その場で見えなくする**（審査 1.2）。
    ///
    /// サーバーに送り、端末の控えに入れ、公開一覧（静的 JSON）から落とす。
    /// **写真詳細とホームのカードの2か所から呼ぶ**——同じ手順を2か所に書くと、
    /// 片方だけ直して黙ってずれる。
    func blockAndHide(_ userId: String, environment: AppEnvironment) async throws {
        try await environment.moderation.block(userId: userId)
        block(userId)
        await environment.gallery.setHidden(userIds: blockedUserIds, photoIds: reportedPhotoIds)
    }
}
