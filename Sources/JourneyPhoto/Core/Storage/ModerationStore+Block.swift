import Foundation

extension ModerationStore {
    /// ブロックして、**その場で見えなくする**（審査 1.2）。
    ///
    /// サーバーに送り、端末の控えに入れ、公開一覧（静的 JSON）から落とす。
    /// 写真詳細とホームのカードから呼ぶ。**プロフィール・ストーリー・通報シートは
    /// まだ同じ手順を個別に書いている**（寄せていない）——直すときは全部見ること。
    func blockAndHide(_ userId: String, environment: AppEnvironment) async throws {
        try await environment.moderation.block(userId: userId)
        block(userId)
        await environment.gallery.setHidden(userIds: blockedUserIds, photoIds: reportedPhotoIds)
    }
}
