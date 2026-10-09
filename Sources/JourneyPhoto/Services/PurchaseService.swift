import Foundation

/// Pro の購入をサーバーへ渡す口（`POST /user/purchases`・第2段階）。
///
/// StoreKit が署名した取引（JWS）をそのまま送る。サーバーは Apple の署名を確かめ、
/// `appAccountToken` が本人の印（`AppAccountToken`）と合うかを見てから、Pro・サポーターの番号・
/// メダルを付ける。**権利を決めるのはサーバー**——アプリは送るだけで、Pro の印は
/// プロフィールの `pro` を読み直して出す。
struct PurchaseService {
    let api: APIClient

    /// 送る形（サーバーと同じ名前）
    struct Body: Encodable, Equatable {
        let signedTransaction: String
    }

    /// 取引を1件送る。結果は「終えてよいか」の判断に使う（`PurchaseDelivery`）。
    ///
    /// 200 の本文は公開プロフィール（`pro`・`supporter`・`badges`）だが、**読まない**——
    /// 画面は自分のプロフィールを読み直して出す（`AuthStore.noteProfileChanged`）
    func submit(signedTransaction jws: String) async -> PurchaseDelivery.Result {
        let errorBody = APIErrorBody()
        do {
            // 失敗の本文（`{ error, code }`）を受け取る（`APIClient.errorBodySink`）
            try await APIClient.$errorBodySink.withValue(errorBody) {
                try await api.authorizedVoid(.post, "/user/purchases", body: Body(signedTransaction: jws))
            }
            return PurchaseDelivery.Result(.accepted)
        } catch let error as APIError {
            if case .server(let status, let message) = error {
                // 理由はサーバーの `code` で見る（403 別のアカウント・ファミリー共有／409 ほかのアカウント）
                return PurchaseDelivery.Result(PurchaseDelivery.outcome(statusCode: status), message: message,
                                               refusal: PurchaseDelivery.refusal(statusCode: status,
                                                                                 code: APIClient.errorCode(from: errorBody.data)))
            }
            // 圏外・ログインしていない・応答が読めない → あとでやり直す
            return PurchaseDelivery.Result(.retryLater)
        } catch {
            return PurchaseDelivery.Result(.retryLater)
        }
    }
}
