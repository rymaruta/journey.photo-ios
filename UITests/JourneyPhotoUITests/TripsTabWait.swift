import XCTest

/// マイページの「旅の記録」のタブを押したあと、中の行が出るまで待つ（UI テストの共通の助け・2026-10-28）。
///
/// 🔴 旅の記録のタブが「読み込み中」のまま 15 秒を越えることがある（PR #390 の検証 run 728: 3 回目の起動で
/// タブの中身が「読み込み中」のまま行が出なかった）。長めに待ち、出なければタブを押し直してもう一度待つ。
/// `ScreenshotTests.openTripsRow`（e3bdc76d）で入れた待ち方を、`CriticalFlowTests` でも同じ形で使う（写しを作らない）
enum TripsTabWait {

    /// 1回目・押し直したあとに待つ秒数
    static let firstWait: TimeInterval = 30
    static let secondWait: TimeInterval = 30

    /// `row` が出るまで待つ。1回目で出なければ `tripsTab` を押し直す（押し直す前に `onRetap` を呼ぶ）。出たら true
    static func waitForRow(_ row: XCUIElement, tripsTab: XCUIElement, onRetap: () -> Void = {}) -> Bool {
        if !row.waitForExistence(timeout: firstWait), tripsTab.exists, tripsTab.isHittable {
            onRetap()
            tripsTab.tap()
        }
        return row.waitForExistence(timeout: secondWait)
    }
}
