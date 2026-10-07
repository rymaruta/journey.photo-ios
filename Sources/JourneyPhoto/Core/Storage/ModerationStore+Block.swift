import Foundation

extension ModerationStore {
    /// ブロックして、**その場で見えなくする**（審査 1.2）。
    ///
    /// サーバーに送り、端末の控えに入れ、公開一覧（静的 JSON）から落とす。
    /// 写真詳細とホームのカードから呼ぶ。**プロフィール・ストーリー・通報シートは
    /// まだ同じ手順を個別に書いている**（寄せていない）——直すときは全部見ること。
    func blockAndHide(_ userId: String, environment: AppEnvironment) async throws {
        let owner = self.owner
        try await environment.moderation.block(userId: userId)
        block(userId, for: owner)
        await environment.gallery.setHidden(snapshot)
    }
}

extension ModerationStore {
    /// 自分で消した・非公開にした写真を、**その場で**公開一覧から落とす（`markGone`）。
    ///
    /// サーバーの答えが返った**後に**呼ぶ（失敗した回に落とすと、消えていない写真が
    /// 見えなくなる）。`owner` は送る**前に**取った `self.owner`——待っている間に
    /// 人が替わっていたら書かない。`blockAndHide` と同じく、控えに入れてから
    /// 公開一覧へ渡す。画面は `revision` を見て読み直す（ブロック・通報と同じ道）
    /// `deleted` は消した回だけ true（非公開にしただけの回と分ける・`deletedPhotoIds`）
    func hideGone(_ photoId: String, for owner: String?, environment: AppEnvironment,
                  deleted: Bool = false) async {
        markGone(photoId, for: owner, deleted: deleted)
        await environment.gallery.setHidden(snapshot)
    }

    /// 公開に戻した写真の印を外す（`unmarkGone`）。一覧に戻るのは、サイトの建て直しで
    /// `photos.json` に載ってから
    func unhideGone(_ photoId: String, for owner: String?, environment: AppEnvironment) async {
        unmarkGone(photoId, for: owner)
        await environment.gallery.setHidden(snapshot)
    }
}
