import Foundation

/// ホームの上の札に「この旅をホームに出さない」とした旅行プラン（2026-11-12 owner「旅行プラン当日のやつは
/// ホームに出てくると思うけど、削除するときは旅行プランのページに行かないといけないのめんどくさい」）。
///
/// 2026-11-12 判断:
/// - **端末の中だけで覚える**（サーバーに欄を足さない＝DB の変更をしない）。旅行プランそのものは消さない
/// - 覚えるのは**その旅の日付ごと**（プランの id・出発日・帰着日）。同じプランの日付を替えて次の旅にしたら、
///   また札に出る（「この旅の間だけ」）
/// - 旅が終わったら（帰着日、無ければ出発日を過ぎたら）印は要らないので消す。増え続けない
/// - 人ごとに分ける（同じ端末で人が替わったとき、前の人の印で札を下げない・`OpenedTripBooks` と同じ）
struct HomeHiddenTrips {

    struct Entry: Codable, Equatable {
        let planId: String
        let startDate: String?
        let endDate: String?

        init(planId: String, startDate: String?, endDate: String?) {
            self.planId = planId
            self.startDate = startDate
            self.endDate = endDate
        }

        init(_ plan: TripPlan) {
            self.init(planId: plan.planId, startDate: plan.startDate, endDate: plan.endDate)
        }

        /// この印が、このプランの**今の日付の旅**を指しているか
        func matches(_ plan: TripPlan) -> Bool {
            plan.planId == planId && plan.startDate == startDate && plan.endDate == endDate
        }

        /// 旅が終わったか（帰着日、無ければ出発日が今日より前）。日付の無い印は終わらない（札に出ない形なので害は無い）
        func isOver(today: String) -> Bool {
            guard let last = endDate ?? startDate, !last.isEmpty else { return false }
            return last < today
        }
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let key = "journey-photo-home-hidden-trips"
    /// 増え続けないよう新しい順にこの件数だけ残す（旅が終われば消えるので、ふつうは数件）
    static let limit = 50

    private func key(for userId: String) -> String { "\(Self.key):\(userId)" }

    func entries(for userId: String?) -> [Entry] {
        guard let userId, !userId.isEmpty,
              let data = defaults.data(forKey: key(for: userId)),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    private func save(_ list: [Entry], for userId: String) {
        guard let data = try? JSONEncoder().encode(Array(list.suffix(Self.limit))) else { return }
        defaults.set(data, forKey: key(for: userId))
    }

    /// 出さない印を付ける（同じプランの前の印は置き換える）
    func hide(_ plan: TripPlan, for userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        var list = entries(for: userId).filter { $0.planId != plan.planId }
        list.append(Entry(plan))
        save(list, for: userId)
    }

    /// 印を外す（知らせの「元に戻す」）
    func unhide(planId: String, for userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        save(entries(for: userId).filter { $0.planId != planId }, for: userId)
    }

    /// 終わった旅の印を消す（`today` は `YYYY-MM-DD`・端末の暦）
    func prune(today: String, for userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        let list = entries(for: userId)
        let kept = list.filter { !$0.isOver(today: today) }
        if kept.count != list.count { save(kept, for: userId) }
    }

    /// 退会した人の印を消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }

    /// 札に使うプラン（出さない印の付いた旅と、`excluding` の id を落とす）。`HomeTopCard.cards` に渡す前に通す
    static func visible(_ plans: [TripPlan], hidden: [Entry], excluding: Set<String> = []) -> [TripPlan] {
        plans.filter { plan in
            !excluding.contains(plan.planId) && !hidden.contains { $0.matches(plan) }
        }
    }
}
