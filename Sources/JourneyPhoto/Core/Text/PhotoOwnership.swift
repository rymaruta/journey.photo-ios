import Foundation

/// **その写真が自分のものか**を決めるただ1つの所（2026-11-23 owner「守れていた、ではなく守れるように」・
/// CLAUDE.md「他人の写真は、その人のもの」）。
///
/// 写真の画像を自分の物へ入れる道（ストーリーに載せる・共有カードを作る・編集する・旅の一冊の絵・アイコンやカバー・
/// 旅行プランやスタンプ帳などに写真を入れる）は、ここを通してから作る。`OthersPhotoExportGuardTests` が、
/// 決まった入口がここを呼んでいるか、新しい入口が一覧に無いかを見張る。
///
/// 持ち主は `userId`、無ければ `uploadedBy`（Web の `photo.userId ?? photo.uploadedBy` と同じ）。
/// **分からないときは自分のものではない**（空の id・ログインしていない・持ち主の欄が無い）——安全側に倒す
enum PhotoOwnership {

    /// 写真の持ち主の id（空なら nil）
    static func ownerId(of photo: Photo) -> String? {
        guard let id = photo.userId ?? photo.uploadedBy, !id.isEmpty else { return nil }
        return id
    }

    /// 持ち主の id と自分の id が、どちらも分かっていて同じときだけ真
    static func isMine(ownerId: String?, me: String?) -> Bool {
        guard let ownerId, !ownerId.isEmpty, let me, !me.isEmpty else { return false }
        return ownerId == me
    }

    /// その写真が自分のものか
    static func isMine(photo: Photo, me: String?) -> Bool {
        isMine(ownerId: ownerId(of: photo), me: me)
    }

    /// 自分の写真だけに絞る（候補の一覧を作るとき。持ち主の分からない写真は落とす）
    static func mine(_ photos: [Photo], me: String?) -> [Photo] {
        photos.filter { isMine(photo: $0, me: me) }
    }
}
