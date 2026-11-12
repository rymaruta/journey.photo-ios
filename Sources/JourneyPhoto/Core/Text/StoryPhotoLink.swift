import Foundation

/// ストーリーとそこから作った写真の**関係**（2026-11-11 判断・owner「ストーリーとそこから作った写真の関係を明確にして」）。
///
/// - 写真にしたストーリーには「写真にしました ›」の札（押すとその写真へ）
/// - その写真には「ストーリーから作った写真 ›」の札（ストーリーがまだあれば押すと開く・無ければ文字だけ）
/// - 消すときは、関係があれば2つの選び方（既定の選び方は無し・危険の色は両方消える側だけ）:
///   ストーリーの側「写真も一緒に消す」「ストーリーだけ消す」／写真の側「ストーリーも一緒に消す」「写真だけ消す」
/// - サーバーは写真の口 `DELETE /photos/{id}?withStory=1|0` で受ける（`api-user/src/storyKeptDelete.ts`）。
///   ストーリーの側の「写真も一緒に消す」もこの口（`withStory=1`）
/// - 「捨てる」は使わない（`NoDiscardWordingTests`）。札の色は黒地なら真鍮、写真の上なら白
enum StoryPhotoLink {

    static var madeIntoPhoto: String { L("写真にしました", "Made into a photo") }
    static var madeFromStory: String { L("ストーリーから作った写真", "Made from a story") }

    static var deleteWithPhoto: String { L("写真も一緒に消す", "Delete with the photo") }
    static var deleteStoryOnly: String { L("ストーリーだけ消す", "Delete story only") }
    static var deleteWithStory: String { L("ストーリーも一緒に消す", "Delete with the story") }
    static var deletePhotoOnly: String { L("写真だけ消す", "Delete photo only") }

    /// 「写真として残す」を出すか。動画は残せない・もう写真にしていれば出さない（札が代わりに出る）。
    /// **自分用に残すストーリーも残せる**（2026-11-11 から。サーバーが画像を写して切り離す）
    static func canKeep(isVideo: Bool, keptPhotoId: String?) -> Bool {
        !isVideo && (keptPhotoId?.isEmpty ?? true)
    }

    /// 写真にしたストーリーを消す確認の説明。写真のいいね・コメントがあれば数を添える
    static func storyDeleteMessage(likes: Int?, comments: Int?) -> String {
        let head = L("このストーリーから写真を作っています。写真も一緒に消すか選んでください。元に戻せません。",
                     "You made a photo from this story. Choose whether to delete the photo too. This can't be undone.")
        let l = max(likes ?? 0, 0), c = max(comments ?? 0, 0)
        guard l > 0 || c > 0 else { return head }
        let ja = [l > 0 ? "いいね \(l)" : nil, c > 0 ? "コメント \(c)" : nil].compactMap { $0 }.joined(separator: "、")
        let en = [l > 0 ? "\(l) like\(l == 1 ? "" : "s")" : nil,
                  c > 0 ? "\(c) comment\(c == 1 ? "" : "s")" : nil].compactMap { $0 }.joined(separator: " and ")
        return head + L("写真を消すと、\(ja) も消えます。", " Deleting the photo also removes its \(en).")
    }

    /// ストーリーから作った写真を消す確認の説明
    static var photoDeleteMessage: String {
        L("この写真はストーリーから作りました。ストーリーも一緒に消すか選んでください。元に戻せません。",
          "This photo was made from a story. Choose whether to delete the story too. This can't be undone.")
    }

    /// 写真の元のストーリーを、本人のストーリー（いま出ている・自分用に残した棚）から探す。
    /// 写真の側に元の id が無い（公開の一覧から開いた）ときは、ストーリーの `keptAs` で探す
    static func source(of photoId: String, sourceStoryId: String?, in stories: [Story]) -> Story? {
        if let sourceStoryId, let hit = stories.first(where: { $0.id == sourceStoryId }) { return hit }
        return stories.first { $0.keptAs == photoId }
    }
}
