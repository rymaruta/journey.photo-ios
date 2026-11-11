import Foundation

// Linux では URLSession が別モジュールに居る（`DailyQuizService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// みんなの「行きたい」（2026-11-11・`SpotWants`）。読むのは静的な JSON（`app/data/spot-wants.json`・
/// 毎日1回の集計が書く）、送るのは未認証の口（`POST /spots/wants`）。
///
/// 読んだ中身は**起動のあいだ覚える**（毎日1回しか変わらない）。読めない・無い回は nil（画面は何も出さない）
actor SpotWantsService {

    private let api: APIClient
    private let session: URLSession
    private let url: @Sendable () -> URL
    private var memo: SpotWants.File??

    init(api: APIClient, session: URLSession? = nil,
         url: @escaping @Sendable () -> URL = { AppConfig.siteBaseURL.appendingPathComponent("app/data/spot-wants.json") }) {
        self.api = api
        self.url = url
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            self.session = URLSession(configuration: config)
        }
    }

    /// 今月の数。取れなかった回は覚えない（次に開いたときにもう一度読む）
    func file() async -> SpotWants.File? {
        if let memo { return memo }
        guard let (data, response) = try? await session.data(from: url()),
              let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else {
            // 無い（まだ集計していない）は「無い」と覚える
            if http.statusCode == 404 || http.statusCode == 403 { memo = .some(nil) }
            return nil
        }
        let decoded = SpotWants.decode(data)
        memo = .some(decoded)
        return decoded
    }

    private struct Body: Encodable { let device: String; let slugs: [String] }
    private struct Counted: Decodable { let counted: Int }

    /// 送る。送れたら true（数えたかどうかはサーバーが決める・上限や月1回で数えないこともある）
    func send(device: String, keys: [String]) async -> Bool {
        guard !keys.isEmpty else { return true }
        do {
            _ = try await api.anonymous(.post, "/spots/wants", body: Body(device: device, slugs: keys), as: Counted.self)
            return true
        } catch {
            return false
        }
    }
}

/// 送る順番の口（払う画面・撮影スポットの頁から呼ぶ）
@MainActor
enum SpotWantSender {

    /// 「行きたい」を1つ控える。`SpotWants.batch` 件たまったら送る
    static func want(_ slug: String, service: SpotWantsService, queue: SpotWantQueue = SpotWantQueue()) {
        if queue.add(slug: slug) >= SpotWants.batch { flush(service: service, queue: queue) }
    }

    /// まだ送っていなければ外す（ひとつ戻した）
    static func unwant(_ slug: String, queue: SpotWantQueue = SpotWantQueue()) {
        queue.remove(slug: slug)
    }

    /// 控えを送る（最大 `SpotWants.sendMax` 件ずつ）。送れたものだけ外す
    static func flush(service: SpotWantsService, queue: SpotWantQueue = SpotWantQueue()) {
        let keys = Array(queue.queued.prefix(SpotWants.sendMax))
        guard !keys.isEmpty else { return }
        let device = queue.deviceId
        Task {
            if await service.send(device: device, keys: keys) {
                queue.removeSent(keys)
            }
        }
    }
}
