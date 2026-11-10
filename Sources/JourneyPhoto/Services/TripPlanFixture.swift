import Combine
import Foundation

/// UI テストで旅行プランの日程を動かすための**見本のプラン**（Debug のときだけ・2026-11-10 札 #521）。
///
/// 起動の指定 `-JPTripPlanFixture YES` で、旅行プランの口（`TripPlanService`）が**サーバーへ送らず**、
/// 端末の中の見本のプランを読み書きする。見本の利用者（`-JPPreviewUserId`）は鍵を持たず `/user/trips` が読めないので、
/// これが無いと日程の画面・区間のシート・「旅行プランに入れる」のシートを撮れない。
///
/// - 見本: 「金沢・福井の旅」（出発は今日の 30 日後・2 日・5 か所・時間帯の案内あり・金沢 → 千里浜の遠い区間あり）と
///   「函館の旅」（日付なし・1 日・1 か所）
/// - 書き込み（`update`）は端末の中の見本を書き換え、**送った回数**（`sends`）を数える。日程の画面は Debug のときだけ
///   この数を見える所に出す（自動保存が「手を止めてからまとめて送る」かを UI テストで数で確かめる）
/// - `-JPTripPlanFixtureOffline YES`: 日程の画面を圏外として扱う（送らない・移動の見込みを聞かない）
/// - `-JPTripPlanFixtureFail YES`: 書き込みを断る（「まだ送れていません」を撮る）
///
/// 🔴 **Release では必ず効かない**（`isOn` などは `#if DEBUG` の外では false）
enum TripPlanFixture {

    static let key = "JPTripPlanFixture"
    static let offlineKey = "JPTripPlanFixtureOffline"
    static let failKey = "JPTripPlanFixtureFail"

    static var isOn: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }

    static var offline: Bool {
        #if DEBUG
        return isOn && UserDefaults.standard.bool(forKey: offlineKey)
        #else
        return false
        #endif
    }

    static var failing: Bool {
        #if DEBUG
        return isOn && UserDefaults.standard.bool(forKey: failKey)
        #else
        return false
        #endif
    }

    /// 見本のプラン。台帳に在る撮影スポットの鍵（`content/spots.json` の石川県・福井県）
    static func initialPlans(today: Date) -> [TripPlan] {
        let start = TripPlanText.calendar.date(byAdding: .day, value: 30, to: today) ?? today
        let end = TripPlanText.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let kanazawa = TripPlan(
            planId: "fixture-kanazawa", title: "金沢・福井の旅",
            startDate: TripPlanText.ymd(start), endDate: TripPlanText.ymd(end),
            days: [
                TripDay(items: [
                    .spot(spotId: "sp_64ff5284da9e", note: nil),   // ひがし茶屋街（夜明け・朝）
                    .spot(spotId: "sp_346663d421dc", note: nil),   // 金沢城公園（朝・夕方の斜光・夜）
                    .spot(spotId: "sp_4e69d634a874", note: nil),   // 千里浜なぎさドライブウェイ（遠い区間・夕方の斜光）
                ]),
                TripDay(items: [
                    .spot(spotId: "sp_55aafc4eff86", note: nil),   // 越前海岸 呼鳥門（夕方の斜光）
                    .spot(spotId: "sp_6cfe84e90826", note: nil),   // 越前岬（夕方の斜光・重なり）
                ]),
            ],
            createdAt: "2026-11-10T00:00:00Z", updatedAt: "2026-11-10T00:00:00Z")
        let hakodate = TripPlan(planId: "fixture-hakodate", title: "函館の旅",
                                days: [TripDay(items: [.location(slug: "函館", note: nil)])],
                                createdAt: "2026-11-01T00:00:00Z", updatedAt: "2026-11-01T00:00:00Z")
        return [kanazawa, hakodate]
    }
}

/// 見本のプランの置き場（端末の中・アプリを閉じれば消える）
actor TripPlanFixtureStore {
    static let shared = TripPlanFixtureStore()

    private var plans: [TripPlan]?
    private var version = 0
    /// 書き込み（`update`）を受けた回数
    private var sends = 0

    private func current() -> [TripPlan] {
        if let plans { return plans }
        let made = TripPlanFixture.initialPlans(today: Date())
        plans = made
        return made
    }

    /// 本番と同じく取り消しを見る（本番は `RequestLimiter.acquire` が `Task.checkCancellation`・確かめ役の指摘）
    func list() throws -> [TripPlan] {
        try Task.checkCancellation()
        return current()
    }

    func create(title: String, days: [TripDay]?, startDate: String?, endDate: String?) -> [TripPlan] {
        version += 1
        let plan = TripPlan(planId: "fixture-new-\(version)", title: title, startDate: startDate, endDate: endDate,
                            days: days ?? [], createdAt: Self.stamp(version), updatedAt: Self.stamp(version))
        plans = [plan] + current()
        return current()
    }

    func update(planId: String, _ patch: TripPlanService.Patch) throws -> [TripPlan] {
        try Task.checkCancellation()
        if TripPlanFixture.failing {
            throw TripPlanService.Refused(message: L("見本: 書き込みを断りました。", "Sample: the write was refused."))
        }
        version += 1
        var list = current()
        guard let i = list.firstIndex(where: { $0.planId == planId }) else { return list }
        let old = list[i]
        func date(_ new: String?, _ was: String?) -> String? {
            guard let new else { return was }
            return new.isEmpty ? nil : new
        }
        list[i] = TripPlan(planId: old.planId, title: patch.title ?? old.title,
                           startDate: date(patch.startDate, old.startDate), endDate: date(patch.endDate, old.endDate),
                           days: patch.days ?? old.days, createdAt: old.createdAt, updatedAt: Self.stamp(version))
        plans = list
        sends += 1
        let count = sends
        Task { @MainActor in TripPlanFixtureCounter.shared.sends = count }
        return list
    }

    func delete(planId: String) -> [TripPlan] {
        plans = current().filter { $0.planId != planId }
        return current()
    }

    private static func stamp(_ n: Int) -> String {
        String(format: "2026-11-10T00:00:%02dZ", min(n, 59))
    }
}

/// 送った回数（日程の画面が Debug のときだけ出す）
@MainActor
final class TripPlanFixtureCounter: ObservableObject {
    static let shared = TripPlanFixtureCounter()
    @Published var sends = 0
}
