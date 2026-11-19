import Foundation
import UserNotifications

/// 見頃のお知らせの予約を入れ替える（`SeasonReminder`）。**端末の中だけ**——サーバーには何も送らない。
///
///  - **許可を新しく求めない。** 通知を受け取る設定（`PushCenter.isEnabled`）がオンで、端末の許可も
///    あるときだけ予約する。どちらかが無ければ、前の予約も消す（設定で切った人に鳴らさない）
///  - 予約は識別子1つ（`SeasonReminder.identifier`）。入れ替えるたびに前の予約を消してから入れる
///  - 同じ中身なら入れ直さない（ホームに戻るたびに予約の出し入れをしない）
@MainActor
final class SeasonReminderScheduler {
    static let shared = SeasonReminderScheduler()

    private let add: (UNNotificationRequest) async throws -> Void
    private let removePending: ([String]) async -> Void
    /// 最後に入れた中身（同じなら入れ直さない）。nil は「入れていない」
    private(set) var scheduled: SeasonReminder.Plan?
    /// 最後に積んだ入れ替え。**入れ替えは1本ずつ順に**——重なると、古い回の後始末が新しい回の予約を消し、
    /// 消えたのに「入れてある」と覚えて二度と入れ直さなかった（5c79dfd のレビュー）
    private var tail: Task<Void, Never>?

    init(add: @escaping (UNNotificationRequest) async throws -> Void = { try await UNUserNotificationCenter.current().add($0) },
         removePending: @escaping ([String]) async -> Void = { ids in
             // 🔴 **主スレッドで消さない**（2026-11-19・#647）。iOS 27.2 のシミュレーターで、起動の直後のここが
             // 主スレッドを 44316.8ms 止めていた（run 1592）。列で消し、消し終わるのを待ってから `add` に進む
             PendingNotificationRemoval.remove(ids)
             await PendingNotificationRemoval.drained()
         }) {
        self.add = add
        self.removePending = removePending
    }

    /// - Parameter allowed: 受け取る設定がオンで、端末の許可があるか
    func reschedule(_ plan: SeasonReminder.Plan?, allowed: Bool) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await self.apply(plan, allowed: allowed)
        }
        tail = task
        await task.value
    }

    private func apply(_ plan: SeasonReminder.Plan?, allowed: Bool) async {
        guard allowed, let wanted = plan else {
            // **入れない回は毎回消す**（安い）。覚えている中身はメモリだけなので、起動し直したあと
            // 「前に入れていない」と思い込んで、ログアウト・通知オフの前に入れた予約を残していた
            await removePending([SeasonReminder.identifier])
            scheduled = nil
            return
        }
        guard wanted != scheduled else { return }
        await removePending([SeasonReminder.identifier])
        scheduled = nil
        let content = UNMutableNotificationContent()
        content.title = wanted.title
        content.body = wanted.body
        content.sound = .default
        // 押した先の綴り（`SeasonReminder.destination`・2026-11-15 札 #618）
        content.userInfo = ["kind": SeasonReminder.kind, "season": wanted.season, SeasonReminder.slugsKey: wanted.slugs]
        let trigger = UNCalendarNotificationTrigger(dateMatching: wanted.fireAt, repeats: false)
        do {
            try await add(UNNotificationRequest(identifier: SeasonReminder.identifier, content: content, trigger: trigger))
            scheduled = wanted
        } catch {
            // 入れられなかった回は「入れていない」のまま（次に呼ばれたときにやり直す）
            print("[season-reminder] 予約できませんでした: \(error)")
        }
    }
}
