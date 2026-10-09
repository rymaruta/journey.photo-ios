import Foundation

/// 光と天気の知らせ（Pro・2026-10-09）。`GET /user/light-forecast`（`api-user/src/lightForecast.ts`）。
///
/// **ログイン必須・Pro だけ。** Pro でなければ 403、天気の鍵が無ければ 503（読み分けは
/// `LightForecastText.failure(for:)`）。
///
/// `AppEnvironment` には足さない（一覧の画面でしか使わない。呼ぶ側が
/// `LightForecastService(api: environment.api)` で作る）
struct LightForecastService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func fetch() async throws -> LightForecast {
        try await api.authorized(.get, "/user/light-forecast", as: LightForecast.self)
    }
}
