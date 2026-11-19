import Foundation
import UserNotifications

/// 通知の予約を消す呼び出しを、**主スレッドの外の1本の列**で順に流す（2026-11-19・#647）。
///
/// 🔴 **iOS 27.2 のシミュレーターで、プロセスで最初の `removePendingNotificationRequests` が 44〜85秒戻らない**
/// （run 1588 で 84377ms、1589 で 44095ms、2回目からは 1ms 未満）。主スレッドで呼んでいた
/// `SeasonReminderScheduler` の取り消しが、起動の直後に主スレッドを 44316.8ms 止めていた（run 1592、
/// 主スレッドの記録の遅い行 227 のうち 135 行がここ）。列で消すと、その行は 0 になった（run 1594）。
///
/// 予約を入れる側は `drained()` を待ってから入れる。**同じ識別子を「消す → 入れる」順は崩れない**
/// （列は1本で、前に積んだ取り消しが終わってから `drained()` が戻る）
enum PendingNotificationRemoval {
    /// UI テストのときだけ、システムの通知の窓口に触らない（`-JPNoSystemNotifications YES`・UI テストの `XCUIApplication.jp()` が渡す）。
    ///
    /// iOS 27.2 のシミュレーターでは窓口の最初の呼び出しが 44〜120秒戻らず（run 1588〜1596）、その間に主スレッドで触った所が
    /// 止まり、DM の試験が落ちた。主スレッドの外へ移したあとも、DM の試験のあとでアプリを終わらせる操作が 71〜216秒戻らない回が
    /// あった（run 1594、1597。DM の試験が最後まで進んだ回の3回中2回）。UI テストでは通知の許可を出しておらず、予約・バッジ・
    /// 届いた通知の操作は画面の確かめに関わらないので、窓口を呼ばない
    static let disabled = UserDefaults.standard.bool(forKey: "JPNoSystemNotifications")

    private static let queue = DispatchQueue(label: "jp.notification.pending-removal", qos: .utility)

    /// 予約を消す。呼んだ所は待たない（消すのは列の中で順に）
    static func remove(_ identifiers: [String]) {
        guard !identifiers.isEmpty, !disabled else { return }
        queue.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    /// それまでに積んだ取り消しが全部終わるまで待つ（主スレッドは止めない）
    static func drained() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { done.resume() }
        }
    }
}
