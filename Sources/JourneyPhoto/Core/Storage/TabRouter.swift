import Foundation
import Combine

/// 下の札を外から切り替える道（見出しの自分のアイコン → マイページ）。
///
/// **押した回数で伝える。** 真偽値にすると、マイページから別の札へ移って
/// もう一度押したときに「変わっていない」と見なされて効かない
/// （`NotificationRouter` / `MissionRouter` と同じ理由）。
@MainActor
final class TabRouter: ObservableObject {

    static let shared = TabRouter()

    @Published private(set) var myPageRequests = 0

    func openMyPage() { myPageRequests += 1 }

    /// **ホームを開いたまま、下の「ホーム」をもう一度押した回数。**
    /// ホームのフィードはこれを見て一番上まで戻る（Instagram・X と同じ動き。
    /// owner の依頼・2026-09-25）。回数で伝えるのは上と同じ理由——
    /// 真偽値だと2回目以降に「変わっていない」と見なされて効かない
    @Published private(set) var homeTopRequests = 0

    /// 下の札が押された。**選ばれている札をもう一度押したときだけ**
    /// 合図を出す（別の札から来たときは何もしない＝開き直しで勝手に
    /// 上へ飛ばない）。いまはホームだけが受け取る
    /// **下の「投稿」から出した写真・ストーリーの画面を閉じた回数。**
    ///
    /// 投稿の入口は下の札の「投稿」1つ（整理案 05c でマイページの
    /// 「投稿する」を外した）。そのシートは `RootView` にあり、マイページや
    /// ストーリーの行からは閉じたことが見えない——投稿しても、マイページの
    /// 格子とストーリーの行が引き下げるまで古いままだった。
    /// 回数で伝えるのは上と同じ理由
    @Published private(set) var postSheetsClosed = 0

    func postSheetClosed() { postSheetsClosed += 1 }

    func tabTapped(isHome: Bool, alreadySelected: Bool) {
        guard isHome, alreadySelected else { return }
        homeTopRequests += 1
    }
}
