import Foundation

/// 光と天気の知らせ（Pro・2026-10-09）。`GET /user/light-forecast`（`api-user/src/lightForecast.ts`）。
///
/// **ログイン必須・Pro だけ。** Pro でなければ 403、天気の鍵が無ければ 503（読み分けは
/// `LightForecastText.failure(for:)`）。
///
/// `AppEnvironment` には足さない（一覧の画面でしか使わない。呼ぶ側が
/// `LightForecastService(api: environment.api)` で作る）
struct LightForecastService {

    let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// **端末の HTTP 控えを使わずに読む**（2026-10-09 判断）。サーバーは
    /// `Cache-Control: private, max-age=600` で返すので、そのままだと URLSession が10分のあいだ
    /// 控えを返す——「行きたい」を足して戻っても、引っぱって読み直しても、前の一覧（空なら
    /// 「行きたい場所がまだありません」）のまま変わらなかった。予報はサーバーが1時間控えているので、
    /// 毎回取りに行っても WeatherKit を余計には叩かない
    func fetch() async throws -> LightForecast {
        try await api.authorized(.get, "/user/light-forecast", cachePolicy: .reloadIgnoringLocalCacheData,
                                 as: LightForecast.self)
    }
}
