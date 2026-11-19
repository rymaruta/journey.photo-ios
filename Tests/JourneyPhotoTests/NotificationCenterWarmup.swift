#if canImport(UserNotifications) && !os(Linux)
import Foundation
import UserNotifications
import XCTest

/// 単体テストの束が始まる前に、通知の予約を消す呼び出しを1回だけ済ませる（2026-11-19・#647）。
///
/// 🔴 **iOS 27.2 のシミュレーターで、プロセスで最初の `removePendingNotificationRequests` が 44〜85秒戻らない。**
/// 2回目からは 1ms 未満（run 1589: 1本目 44095.0ms、2本目 0.8ms。`UNUserNotificationCenter.current()` は 0.2ms）。
/// 単体テストでは、退会の後始末（`AccountLocalData.remove` → `PassStore.removeData` → `PassBundleNotifier.cancelAll`）を
/// 最初に通る `AccountLocalDataTests` の1本がこれを払い、1本あたりの上限 60秒を超えて落ちた（run 1583、1584）。
/// iOS 26.2 では同じ1本が 0.02〜0.04秒（run 1580、1585）。
///
/// 通るテストは多いので（すれちがいの帳・通知・人の切り替え）、1本だけ外すと次に呼んだテストへ遅さが移る。
/// 束の頭で1回だけ払い、どのテストの上限にも数えない。払った時間はログに出す
/// （`xcodebuild-full.log` の `[test-warmup]`）。
@objc(JPNotificationCenterWarmup)
final class NotificationCenterWarmup: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        let started = Date()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["jp.test.warmup"])
        NSLog("[test-warmup] removePendingNotificationRequests の最初の1回: %.1fms",
              Date().timeIntervalSince(started) * 1000)
    }
}
#endif
