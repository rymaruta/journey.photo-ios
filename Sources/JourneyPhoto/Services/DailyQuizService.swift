import Foundation

// Linux では URLSession が別モジュールに居る（`OfficialSpotService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 今日の一問（`app/data/quiz/<日付>.json`）を読む。**API ではなく静的な JSON**。
///
/// 「まだ読んでいる」「その日の問題が無い」「読めなかった」を混ぜない:
///
///  - 404 ・中身が決まりに合わない → `.none`（その日は「まだありません」）
///  - 圏外・5xx・HTML（キャプティブポータル）→ **投げる**（画面は「読めませんでした」と再読み込み）
///
/// 取れた問題は日付ごとに覚える（ホームの札と画面で2回取りに行かない）。**控えは端末に残さない**——
/// 1日で古くなり、圏外で昨日の問題を出す意味が無い
actor DailyQuizService {

    enum Result: Equatable {
        case ready(DailyQuiz)
        case none
    }

    private let session: URLSession
    private let urlFor: @Sendable (String) -> URL
    private var memo: [String: DailyQuiz] = [:]

    init(session: URLSession? = nil, urlFor: @escaping @Sendable (String) -> URL = { AppConfig.quizURL(date: $0) }) {
        self.urlFor = urlFor
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            // 覚えるのは自分で（`memo`）。URLSession の控えに昨日の中身を残さない
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    func fetch(date: String) async throws -> Result {
        if let hit = memo[date] { return .ready(hit) }
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            (data, response) = try await session.data(from: urlFor(date))
        } catch {
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("HTTP 応答ではありません")
        }
        if http.statusCode == 404 { return .none }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: "")
        }
        // 200 の HTML（ホテル・空港の Wi-Fi のログイン画面）は「無い」ではなく「読めなかった」
        if Self.isHTML(http) {
            throw APIError.decoding("今日の一問の応答が HTML でした")
        }
        guard let quiz = DailyQuiz.parse(data, date: date) else { return .none }
        memo[date] = quiz
        return .ready(quiz)
    }

    private static func isHTML(_ response: HTTPURLResponse) -> Bool {
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, name.lowercased() == "content-type",
                  let type = value as? String else { continue }
            return type.lowercased().hasPrefix("text/html")
        }
        return false
    }
}
