import Foundation

/// 旅行プラン（`/user/trips`）。**本人だけが読める**
/// （サーバーは JWT の `sub` からしか行を作らない・`api-user/src/tripPlans.ts`）。
///
/// **書き込みの応答は、書いたあとの一覧。** 画面は自分で足し引きせず、
/// 返ってきた一覧をそのまま映す（Web の `useTripPlans` と同じ判断——
/// 断られた回に嘘の状態を残さない）。
///
/// **端末に控えを持たない。** 同じ端末を使う別の人に見えるため
/// （Web も持たない）。
struct TripPlanService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 上限。**サーバーと対**（`TRIPS_MAX` ほか）。超えるとサーバーが
    /// 403 で**断る**（古い方を黙って落とさない）。画面はその言い分をそのまま出す
    static let plansMax = 50
    static let titleMax = 100
    static let daysMax = 60
    static let itemsPerDayMax = 20

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    func list() async throws -> [TripPlan] {
        try await api.authorized(.get, "/user/trips", as: TripPlanList.self).plans
    }

    private struct CreateBody: Encodable { let title: String }

    func create(title: String) async throws -> [TripPlan] {
        try await api.authorized(.post, "/user/trips", body: CreateBody(title: title), as: TripPlanList.self).plans
    }

    /// **送った項目だけが差し替わる**（サーバーは無い鍵を「触らない」と読む）。
    /// 日付を空にしたいときは空文字を送る（サーバーが消す）
    struct Patch: Encodable, Equatable {
        var title: String?
        var startDate: String?
        var endDate: String?
        var days: [TripDay]?
    }

    func update(planId: String, _ patch: Patch) async throws -> [TripPlan] {
        try await api.authorized(.put, "/user/trips/\(encoded(planId))", body: patch, as: TripPlanList.self).plans
    }

    func delete(planId: String) async throws -> [TripPlan] {
        try await api.authorized(.delete, "/user/trips/\(encoded(planId))", as: TripPlanList.self).plans
    }
}
