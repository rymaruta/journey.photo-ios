import Foundation

/// 投稿の入口で選べるもの（下の「投稿」で開く一覧・空の画面の「次の一手」・`TabRouter.openPost`）。
///
/// 2026-11-18 判断（案 B1「投稿の入口」・owner 採用）: **選ぶシート（前の `PostSheet`・2026-11-12 #187 の形）はやめた。**
/// 下の「投稿」を押したらすぐ写真の一覧（`CreateFlowView`）。シートにあった入口は一覧の上と中へ移した
/// （`CreateFlowRules`）。ここに残るのは、一覧から閉じて別の画面へ渡すものと、外から入口を開く種類
enum PostEntry {
    /// 写真を投稿（一覧を投稿で開く）
    case photo
    /// ストーリー（一覧をストーリーで開く）
    case story
    /// カメラで撮って、その1枚で投稿へ（`CameraPicker`・撮った1枚は構図を重ねて撮ったあとと同じ道）
    case camera
    /// 端末の写真ライブラリから旅を見つけて、まとめて投稿（`LibraryTripFlowView`・一覧の上のチップ）
    case trip
    /// 構図を重ねて撮る（作例なし・2026-10-10 owner・カメラの隣のマス）。2026-10-17 判断（owner）: 全員無料
    case composition
    /// 下書きの一覧（一覧の上の「下書き n」・1件を選ぶと続きから開く・`TabRouter.openDraft`）
    case drafts

    /// 下書きの件数（投稿・ストーリーの合計）。ログインしていなければ 0
    @MainActor
    static func draftCount(userId: String?) -> Int {
        guard let userId else { return 0 }
        return DraftLibrary.shared.count(for: userId, kind: .post) + DraftLibrary.shared.count(for: userId, kind: .story)
    }
}

/// 空の画面の「次の一手」から投稿の流れを開いてよいか（`TabRouter.openPost`・2026-10-16）。
/// **ほかの投稿の画面（旅の写真・投稿・ストーリー・投稿の入口・カメラ）が出ていたら開かない**——
/// 重ねると iOS が遷移を取りこぼすか、書きかけの上に別の画面が出る
enum PostRequestGate {
    nonisolated static func opens(busy: [Bool]) -> Bool { !busy.contains(true) }
}
