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

    /// 作るときに送る題。**サーバーと同じく UTF-16 の単位で数えて、字の途中では切らない**
    /// （`sanitizeText(title, TRIP_TITLE_MAX)`）。字の数で切っていたので、絵文字60個の題は
    /// 60字として全部送られ、サーバーが黙って50個に切っていた
    static func titleToSend(_ raw: String) -> String {
        PostLimits.clamp(raw.trimmingCharacters(in: .whitespacesAndNewlines), limit: titleMax)
    }
    static let daysMax = 60
    static let itemsPerDayMax = 20
    /// 項目に添えるひとこと（`TRIP_NOTE_MAX`）。入れる画面は `TripPlanDetailView` の項目の「…」
    /// （2026-09-30・規則は `TripPlanEdit.setNote`）。Web にはまだ無い
    static let noteMax = 200

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// 上限で断られた（サーバーの `TripLimitError`）。**言い分をそのまま出す**。
    ///
    /// サーバーは上限を **403** で返す（50件・1プランの予算・行ぜんぶの予算）。
    /// 以前は `APIError` が 403 を「権限がありません…お問い合わせください」に
    /// 置き換えていたので、**本文があるときだけ**ここで包み直していた。今は
    /// `APIError` も本文を出す（2026-09-27 #2）ので見え方は同じ。型は画面が使うので残す
    ///
    /// ⚠️ **呼ぶ側は `as? APIError` で読まない。** `(error as? LocalizedError)?.errorDescription`
    /// で読む（`APIError` ではないので、`as? APIError` だと断り文が「読み込めませんでした」に化ける）
    struct Refused: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    private func refusing<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch let APIError.server(status, message) where status == 403 && !message.isEmpty {
            throw Refused(message: message)
        }
    }

    func list() async throws -> [TripPlan] {
        try await api.authorized(.get, "/user/trips", as: TripPlanList.self).plans
    }

    /// 無い項目（nil）は送らない。サーバーは作るときも日程・日付を読む（`createTrip`）
    private struct CreateBody: Encodable {
        let title: String
        var startDate: String?
        var endDate: String?
        var days: [TripDay]?
    }

    /// 作る。**日程・日付も同じ1回で送る**——作ってから別に送ると、2回目で落ちた回に
    /// 空のプランが残る（行きたい場所から作る下書き・`TripPickerDraftView`）
    func create(title: String, days: [TripDay]? = nil,
                startDate: String? = nil, endDate: String? = nil) async throws -> [TripPlan] {
        let body = CreateBody(title: title, startDate: startDate, endDate: endDate, days: days)
        return try await refusing {
            try await api.authorized(.post, "/user/trips", body: body, as: TripPlanList.self).plans
        }
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
        try await refusing {
            try await api.authorized(.put, "/user/trips/\(encoded(planId))", body: patch, as: TripPlanList.self).plans
        }
    }

    func delete(planId: String) async throws -> [TripPlan] {
        try await api.authorized(.delete, "/user/trips/\(encoded(planId))", as: TripPlanList.self).plans
    }
}
