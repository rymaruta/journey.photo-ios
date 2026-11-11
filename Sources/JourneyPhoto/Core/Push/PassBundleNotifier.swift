import Foundation
import UserNotifications

/// すれちがいの知らせ（端末の中で予約する・2026-10-16・2026-11-10 にすぐ届く形を足した）。
///
/// - **すぐ届く形（既定・2026-11-10）**: 最初の1枚はすぐ鳴らし、その後 `PassExchange.noticeInterval`（15 分）の
///   間に届いた分は、間の終わりに1回だけ鳴らす（`PassExchange.noticeDate`）。識別子は日ごとに1つ
///   （`pass.now.<日>`）で、入れ直すたびに枚数を書き換える（OS は同じ識別子の予約を置き換え、鳴ったときは
///   通知の一覧の前の知らせも置き換える）
/// - **夕方にまとめて**: 予約は**届く日ごとに1つ**（識別子 `pass.bundle.<日>`）。受け取るたびに同じ識別子で
///   入れ直して、枚数を書き換える
/// - **端末の通知の許可だけを見る**（2026-10-16 判断）。すれちがいは本人が設定でオンにした機能で、
///   知らせはその機能の一部。許可が無ければ OS が出さないだけで、カードはホームの札に出る
/// - 知らせの中身に相手の名前・場所・時刻は書かない（ロック画面に出るため）。押した先はどちらも同じ
///   （`kind` が `pass`・`AppDelegate` がホームへ行って束を開く）
enum PassBundleNotifier {

    /// 知らせの種類（`AppDelegate` が押した先を分ける）
    static let kind = "pass"
    static let prefix = "pass.bundle."
    /// すぐ届く形の知らせの識別子の頭（夕方の束と分ける——届き方を替えた日に、片方がもう片方の予約を
    /// 置き換えない）
    static let instantPrefix = "pass.now."

    static func identifier(day: String) -> String { prefix + day }
    static func instantIdentifier(day: String) -> String { instantPrefix + day }

    static func title() -> String { L("カードが届きました", "Cards have arrived") }

    static func body(count: Int) -> String {
        L("今日すれちがった \(count) 人のカードです。束を開いて、めくってみましょう。",
          "\(Plural.count(count, "card")) from people you passed today. Open the bundle and flip through \(count == 1 ? "it" : "them").")
    }

    /// すぐ届く形の本文。数は**まだ開いていない枚数**（束に入っている分）。名前・場所・時刻は書かない
    static func instantBody(count: Int) -> String {
        L("すれちがった人のカードが \(count) 枚届いています。束を開いて、めくってみましょう。",
          "\(Plural.count(count, "card")) from people you passed. Open the bundle and flip through \(count == 1 ? "it" : "them").")
    }

    /// 夕方の束の知らせを予約する（届く時がいまより後のときだけ）
    static func schedule(day: String, at date: Date, count: Int,
                         calendar: Calendar = .current, now: Date = Date()) async {
        guard date > now, count > 0 else { return }
        await add(identifier: identifier(day: day), body: body(count: count), day: day, at: date,
                  calendar: calendar, now: now)
    }

    /// すぐ届く形の知らせ。`date` がいま以前ならすぐ鳴らす（`trigger` なし）、後なら秒まで合わせて予約する
    static func scheduleInstant(day: String, at date: Date, count: Int,
                                calendar: Calendar = .current, now: Date = Date()) async {
        guard count > 0 else { return }
        await add(identifier: instantIdentifier(day: day), body: instantBody(count: count), day: day, at: date,
                  calendar: calendar, now: now)
    }

    private static func add(identifier: String, body: String, day: String, at date: Date,
                            calendar: Calendar, now: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title()
        content.body = body
        content.sound = .default
        content.userInfo = ["kind": kind, "day": day]
        // いま以前は trigger なし（すぐ出す）。後なら秒まで合わせる（分までだと、15 分の間の終わりより
        // 最大 59 秒早く鳴る）
        let trigger: UNNotificationTrigger? = date > now
            ? UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date),
                repeats: false)
            : nil
        do {
            try await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        } catch {
            print("[pass] 知らせを予約できませんでした: \(error)")
        }
    }

    /// まだ鳴っていない、すぐ届く形の知らせを消す（束を開いた——古い枚数で後から鳴らさない）
    static func cancelPendingInstant(calendar: Calendar = .current, now: Date = Date()) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: days(calendar: calendar, now: now).map(instantIdentifier(day:)))
    }

    /// 夕方の束の予約だけを消す（「すぐ」に替えた——まだ届いていなかった分は、その場で届いた扱いにする）
    static func cancelEvening(calendar: Calendar = .current, now: Date = Date()) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: days(calendar: calendar, now: now).map(identifier(day:)))
    }

    /// 予約を全部消す（オフにした・人が替わった・退会）。**今日と次の日の分**を消す
    /// （予約は届く日ごとなので、それより先の日の予約は作られない）。すぐ届く形の分も
    static func cancelAll(calendar: Calendar = .current, now: Date = Date()) {
        let days = days(calendar: calendar, now: now)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: days.map(identifier(day:)) + days.map(instantIdentifier(day:)))
    }

    private static func days(calendar: Calendar, now: Date) -> [String] {
        (0...1).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .map { PassExchange.dayKey($0, calendar: calendar) }
    }
}
