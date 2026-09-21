import Foundation

/// プッシュ通知の宛先をサーバーに預ける。
///
/// **端末は1人に何台もある。** サーバーは Set で持つので（`devices.ts`）、
/// 同じトークンを何度登録しても増えない——起動のたびに登録してよい。
struct PushService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 端末を登録する。`POST /user/devices`
    func register(token: String) async throws {
        struct Body: Encodable { let token: String }
        try await api.authorizedVoid(.post, "/user/devices", body: Body(token: token))
    }

    /// 端末を外す。`DELETE /user/devices`
    ///
    /// **ログアウトの前に呼ぶ。** あとだと認証が通らず、外せないまま
    /// 次にその端末を使う別の人へ通知が飛ぶ。
    func unregister(token: String) async throws {
        struct Body: Encodable { let token: String }
        try await api.authorizedVoid(.delete, "/user/devices", body: Body(token: token))
    }
}
