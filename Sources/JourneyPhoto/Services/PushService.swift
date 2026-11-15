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

    /// このアプリが持っている通知の文言の段（サーバーの `devices.ts` の `PUSH_KEYS_LATEST`・2026-11-15 札 #618）。
    ///
    /// サーバーは通知の文を鍵（`NOTIF_COMMENT_REPLY` など）で送り、端末が `Localizable.strings` で引く。
    /// **鍵を持たない古いアプリは鍵の文字列をそのまま出す**ので、サーバーは段を名乗った端末にだけ新しい鍵を送る。
    /// 段 2 = `NOTIF_COMMENT_REPLY`・`NOTIF_STORY_MENTION`・`NOTIF_STORY_SHARE` を持つ（`NotificationTextTests` が見る）。
    /// **鍵を足して段を上げるときは、サーバーの段と一緒に上げる**
    static let pushKeys = 2

    /// 端末を登録する。`POST /user/devices`
    func register(token: String) async throws {
        struct Body: Encodable {
            let token: String
            /// 文言の段（上）。古いサーバーは読まない
            let pushKeys: Int
        }
        try await api.authorizedVoid(.post, "/user/devices", body: Body(token: token, pushKeys: Self.pushKeys))
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
