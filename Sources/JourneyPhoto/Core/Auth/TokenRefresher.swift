import Foundation

/// ID トークンの**強制更新を1本にまとめる**。
///
/// 401 を受けた要求は、それぞれトークンを取り直してから1回だけやり直す
/// （`APIClient.send`）。画面を開くと口が何本も同時に走るので、期限が切れた瞬間は
/// それらが**一斉に** 401 になる。1本ずつ Cognito に取り直しに行くと、同じ更新トークンで
/// 何本も並行して更新を頼むことになる——1本が走っている間に来た呼び手は、
/// 新しく始めずにその答えを待つ。
///
/// `APIClient` は画面ごとに別の実体がある（`PhotoDetailView`・`UploadView` など）ので、
/// まとめるのは `APIClient` の中ではなく、ここ（`AuthGateway` が1つだけ持つ）。
actor TokenRefresher {

    private let fetch: @Sendable () async throws -> String?
    private var inFlight: Task<String?, Error>?
    /// いま答えを待っている呼び手の数（試験が「全員そろった」を待つのに使う）
    private(set) var waiting = 0

    /// - Parameter fetch: 本当に取り直す処理。nil は「ログインが切れていて取り直せない」
    init(fetch: @escaping @Sendable () async throws -> String?) {
        self.fetch = fetch
    }

    func refresh() async throws -> String? {
        let task: Task<String?, Error>
        if let inFlight {
            task = inFlight
        } else {
            let fetch = self.fetch
            task = Task { try await fetch() }
            inFlight = task
        }
        waiting += 1
        let result = await task.result
        waiting -= 1
        // 終わった1本だけを外す（その間に次の1本が始まっていれば残す）
        if inFlight == task { inFlight = nil }
        return try result.get()
    }
}
