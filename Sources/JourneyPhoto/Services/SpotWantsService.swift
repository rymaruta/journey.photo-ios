import Foundation

// Linux では URLSession が別モジュールに居る（`DailyQuizService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// みんなの「行きたい」（2026-11-11・`SpotWants`）。読むのは静的な JSON（`app/data/spot-wants.json`・
/// 毎日1回の集計が書く）、送るのは未認証の口（`POST /spots/wants`）。
///
/// 読んだ中身は**その日のあいだ覚える**（集計は毎日1回）。日をまたいだら読み直す（月が替わった数を前の月のまま出さない）。
/// 読めない・無い（404/403）回は覚えない——次に開いたときにもう一度読む（2026-11-11 確かめ役の指摘 11）
actor SpotWantsService {

    private let api: APIClient
    private let session: URLSession
    private let url: @Sendable () -> URL
    /// 読めた中身と、読んだ日（日本時間の "YYYY-MM-DD"）
    private var memo: (day: String, file: SpotWants.File)?
    private let today: @Sendable () -> String

    init(api: APIClient, session: URLSession? = nil,
         url: @escaping @Sendable () -> URL = { AppConfig.siteBaseURL.appendingPathComponent("app/data/spot-wants.json") },
         today: @escaping @Sendable () -> String = { DailyQuiz.today() }) {
        self.api = api
        self.url = url
        self.today = today
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            self.session = URLSession(configuration: config)
        }
    }

    /// 今月の数。読めた中身はその日のあいだ覚える。取れなかった・無かった回は覚えない
    func file() async -> SpotWants.File? {
        let day = today()
        if let memo, memo.day == day { return memo.file }
        guard let (data, response) = try? await session.data(from: url()),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = SpotWants.decode(data) else { return nil }
        memo = (day, decoded)
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
