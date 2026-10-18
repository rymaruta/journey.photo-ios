import Foundation
import UserNotifications

/// すれちがいの束の知らせ（夕方 18 時に1回・端末の中で予約する・2026-10-16）。
///
/// - 予約は**届く日ごとに1つ**（識別子 `pass.bundle.<日>`）。受け取るたびに同じ識別子で入れ直して、
///   枚数を書き換える（OS は同じ識別子の予約を置き換える）
/// - **端末の通知の許可だけを見る**（2026-10-16 判断）。すれちがいは本人が設定でオンにした機能で、
///   知らせはその機能の一部。許可が無ければ OS が出さないだけで、カードはホームの札に出る
/// - 知らせの中身に相手の名前・場所は書かない（ロック画面に出るため）
enum PassBundleNotifier {

    /// 知らせの種類（`AppDelegate` が押した先を分ける）
    static let kind = "pass"
    static let prefix = "pass.bundle."

    static func identifier(day: String) -> String { prefix + day }

    static func title() -> String { L("カードが届きました", "Cards have arrived") }

    static func body(count: Int) -> String {
        L("今日すれちがった \(count) 人のカードです。束を開いて、めくってみましょう。",
          "\(count) cards from people you passed today. Open the bundle and flip through them.")
    }

    static func schedule(day: String, at date: Date, count: Int,
                         calendar: Calendar = .current, now: Date = Date()) async {
        guard date > now, count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title()
        content.body = body(count: count)
        content.sound = .default
        content.userInfo = ["kind": kind, "day": day]
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        do {
            try await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: identifier(day: day), content: content, trigger: trigger))
        } catch {
            print("[pass] 知らせを予約できませんでした: \(error)")
        }
    }

    /// 予約を全部消す（オフにした・人が替わった・退会）。**今日と次の日の分**を消す
    /// （予約は届く日ごとなので、それより先の日の予約は作られない）
    static func cancelAll(calendar: Calendar = .current, now: Date = Date()) {
        let days = (0...1).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .map { identifier(day: PassExchange.dayKey($0, calendar: calendar)) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: days)
    }
}
