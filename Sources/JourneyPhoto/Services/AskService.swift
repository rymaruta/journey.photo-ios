import Foundation

/// 「AI に頼む」のサーバーの口（`POST /user/trip-ai`・photo-gallery `api-user/src/tripAi.ts`・札 #652）。
///
/// - `reserve`: **答える前に1回取る**（端末の AI の回も、サーバーの AI の回も）。旅行プランの AI も同じ口（`kind: "trip"`）。
///   取れたら `AskUsage`（今日と今月の残り、サーバーの AI を使ってよいか）。取れなければ 429 `{reason}`
/// - `ask`: サーバーの AI で答える（Pro で、端末の AI が無い iPhone だけ）。送るのは打った文と直前の2往復と、
///   アプリが選んだ公開の観光スポットの行だけ。**現在地、行きたい場所、旅行プランは送らない**
///
/// 2026-11-20 判断: 口の形はサーバーの担当が同時に作っている（#652 の最新のコメント）。形が違えば `decoding` で
/// 落ち、アプリは AI を使わない答え（言葉の表）に倒れる（行き止まりにしない）
struct AskService {

    enum Kind: String, Encodable { case ask, trip }
    enum Via: String, Encodable { case device, server }

    enum Failure: Error, Equatable {
        /// 回数を使い切った・休んでいる（429 の `reason`）
        case limit(AskLimitReason)
        case signedOut
        /// 圏外・サーバーが答えない
        case unavailable
    }

    /// 直前の往復（サーバーの AI の文脈。2往復まで）
    struct Turn: Encodable, Equatable {
        let question: String
        let answer: String
    }

    struct ServerAnswer: Decodable, Equatable {
        let answer: String
        let general: Bool
    }

    private struct ReserveRequest: Encodable {
        let action = "reserve"
        let kind: Kind
        let via: Via
    }

    private struct AskRequest: Encodable {
        let action = "ask"
        let text: String
        let history: [Turn]
        let sources: [TripAIService.Candidate]
    }

    private struct LimitBody: Decodable { let reason: String? }

    /// 試験の差し替え口（nil なら本物のサーバー）
    var reserveOverride: (@Sendable (Kind, Via) async throws -> AskUsage)?
    var askOverride: (@Sendable (String, [Turn], [OfficialSpot]) async throws -> ServerAnswer)?

    private let api: APIClient?

    init(api: APIClient?) { self.api = api }

    /// サーバーの AI に送る往復の数
    static let historyTurns = 2
    /// サーバーの AI に送る観光スポットの行の数
    static let maxSources = 10

    func reserve(kind: Kind, via: Via) async throws -> AskUsage {
        if let reserveOverride { return try await reserveOverride(kind, via) }
        if AskFixture.isOn { return try AskFixture.reserve(kind: kind, via: via) }
        return try await call(ReserveRequest(kind: kind, via: via), as: AskUsage.self)
    }

    func ask(text: String, history: [Turn], sources: [OfficialSpot]) async throws -> ServerAnswer {
        if let askOverride { return try await askOverride(text, history, sources) }
        if AskFixture.isOn { return AskFixture.serverAnswer }
        let body = AskRequest(text: AskQuery.clipped(text),
                              history: Array(history.suffix(Self.historyTurns)).map {
                                  Turn(question: AskQuery.clipped($0.question), answer: String($0.answer.prefix(600)))
                              },
                              sources: sources.prefix(Self.maxSources).map(TripAIService.Candidate.init))
        return try await call(body, as: ServerAnswer.self)
    }

    private func call<T: Decodable>(_ body: any Encodable, as type: T.Type) async throws -> T {
        guard let api else { throw Failure.unavailable }
        let sink = APIErrorBody()
        do {
            return try await APIClient.$errorBodySink.withValue(sink) {
                try await api.authorized(.post, "/user/trip-ai", body: body, as: type)
            }
        } catch let error as APIError {
            switch error {
            case .notAuthenticated: throw Failure.signedOut
            case .unreachable: throw Failure.unavailable
            case .server(let status, _) where status == 429:
                throw Failure.limit(Self.reason(from: sink.data))
            case .server(let status, _) where status == 401: throw Failure.signedOut
            default: throw Failure.unavailable
            }
        }
    }

    /// 429 の本文の `reason`。読めなければ今日の分（いちばん控えめな言い方）
    static func reason(from data: Data?) -> AskLimitReason {
        guard let data, let body = try? JSONDecoder().decode(LimitBody.self, from: data),
              let raw = body.reason, let reason = AskLimitReason(rawValue: raw) else { return .day }
        return reason
    }
}

/// UI テストの見本（`-JPAskFixture YES`・Debug のときだけ）。サーバーへは送らない。
/// `-JPAskFixtureMode` で状態を替える: `usedUpDay`・`usedUpMonth`・`global`（取れない）、`pro`（Pro）、無ければ無料で今日あと2回
enum AskFixture {
    static let key = "JPAskFixture"
    static let modeKey = "JPAskFixtureMode"

    static var isOn: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }

    static var mode: String {
        #if DEBUG
        return isOn ? (UserDefaults.standard.string(forKey: modeKey) ?? "") : ""
        #else
        return ""
        #endif
    }

    static func reserve(kind: AskService.Kind, via: AskService.Via) throws -> AskUsage {
        switch mode {
        case "usedUpDay": throw AskService.Failure.limit(.day)
        case "usedUpMonth": throw AskService.Failure.limit(.month)
        case "global": throw AskService.Failure.limit(.global)
        case "pro":
            return AskUsage(tier: "pro", kind: kind.rawValue, day: .init(used: 1, limit: AskLimits.proDay, remaining: 19),
                            month: .init(used: 1, limit: AskLimits.proMonth, remaining: 299, resetsOn: TripAIText.nextReset()),
                            serverAllowed: true)
        default:
            return AskUsage(tier: "free", kind: kind.rawValue, day: .init(used: 1, limit: AskLimits.freeDay, remaining: 2),
                            month: .init(used: 3, limit: AskLimits.freeMonth, remaining: 7, resetsOn: TripAIText.nextReset()),
                            serverAllowed: false)
        }
    }

    /// この iPhone に端末の AI があると見せるか（`noDevice` で無い iPhone の形）
    static var deviceAI: Bool { mode != "noDevice" }

    /// 端末の AI の見本の答え（AI を呼ばない。台帳と使い方の頁から決まった形で返す・`silent` は答えない）
    static func deviceResult(_ question: String, library: AskLibrary) -> AskDevice.Result? {
        guard mode != "silent" else { return nil }
        let reading = SearchSentence.readByTable(question)
        let intent = AskQuery.intent(question, reading: reading)
        let query = AskLibrary.query(reading: reading, intent: intent, sentence: question, spots: library.spots)
        if intent.howTo, let page = AskHelpPages.matching(question).first {
            return .init(text: page.lines.joined(separator: "\n"), general: false, picks: [], photoIds: [],
                         sources: [.init(kind: .help, label: L("使い方の頁「\(page.title)」", "Help: \(page.title)"))])
        }
        if intent.spots {
            let picks = library.pickSpots(query)
            return .init(text: L("観光スポットの案内から、合う所を選びました。", "Picked matching spots from the guides."),
                         general: false, picks: picks, photoIds: [],
                         sources: [.init(kind: .spots, label: L("観光スポットの台帳", "Tourist spot list"))])
        }
        return .init(text: L("太陽は画面の端に置き、明るさを少し下げると、空の色が残ります。", "Keep the sun near the edge and lower the exposure a little to keep the sky's color."),
                     general: true, picks: [], photoIds: [], sources: [])
    }

    static var serverAnswer: AskService.ServerAnswer {
        .init(answer: L("夕方の案内がある観光スポットを近い順に選びました。", "Picked spots with evening notes, nearest first."), general: false)
    }
}
