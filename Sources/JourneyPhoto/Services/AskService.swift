import Foundation

/// 「AI に頼む」のサーバーの口（`POST /user/trip-ai`・photo-gallery `api-user/src/tripAi.ts`・札 #652）。
///
/// - `reserve`: **答える前に1回取る**（端末の AI の回も、サーバーの AI の回も）。旅行プランの AI も同じ口（`kind: "trip"`）。
///   取れたら `AskUsage`（今日と今月の残り、サーバーの AI を使ってよいか）。取れなければ 429 `{reason}`
/// - `ask`: サーバーの AI で答える（Pro で、端末の AI が無い iPhone だけ）。送るのは打った文と直前の2往復と、
///   アプリが選んだ公開の観光スポットの行だけ。**現在地、行きたい場所、旅行プランは送らない**
///
/// 口の形は #652 のサーバーの担当のコメント（2026-11-20 10:51・11:28、journey.photo-web #694〜#697 で本番に出た）に合わせた:
/// - reserve → 200 QuotaView、429 `{reason, code:"limit", quota}`、403 `{reason:"proOnly"}`（無料の人の via:"server"）
/// - ask `{text, history:[{q,a}], sources:[{kind:"spot",…,note} | {kind:"help",title,body}]}`（8件まで）
///   → `{answer, general, refused, quota}`。403 proOnly、429、502、422
/// - reserve(via:"server") で取った回は、次の ask が使う（二重に数えない）
/// 形が違えば `decoding` で落ち、アプリは AI を使わない答え（言葉の表）に倒れる（行き止まりにしない）
struct AskService {

    enum Kind: String, Encodable { case ask, trip }
    enum Via: String, Encodable { case device, server }

    enum Failure: Error, Equatable {
        /// 回数を使い切った・休んでいる（429 の `reason` と、あれば `quota`）
        case limit(AskLimitReason, AskUsage?)
        case signedOut
        /// 圏外・サーバーが答えない（502 も）
        case unavailable
        /// サーバーの AI は Pro だけ（403 `proOnly`）。言葉の表で答える
        case proOnly
    }

    /// 直前の往復（サーバーの AI の文脈。2往復まで）。送る形は `{"q","a"}`
    struct Turn: Encodable, Equatable {
        let question: String
        let answer: String
        private enum CodingKeys: String, CodingKey { case question = "q", answer = "a" }
    }

    struct ServerAnswer: Decodable, Equatable {
        let answer: String
        let general: Bool
        /// サーバーが断った（呼ぶ前の断り・AI の断り・答えの前の見張り）。`answer` は断りの1行
        var refused: Bool = false
        /// 答えたあとの回数
        var quota: AskUsage? = nil
        /// 答えの種類と頭の文（2026-11-21 判断・札 #675 の答えの形）。**今のサーバーは返さない**（返す形はサーバーの担当に別に頼む）。
        /// 無ければ `answer` の文から頭の文を作り、札の有無でアプリが形を決める（今のまま）
        var kind: String? = nil
        var lead: String? = nil

        init(answer: String, general: Bool, refused: Bool = false, quota: AskUsage? = nil, kind: String? = nil, lead: String? = nil) {
            self.answer = answer
            self.general = general
            self.refused = refused
            self.quota = quota
            self.kind = kind
            self.lead = lead
        }

        private enum CodingKeys: String, CodingKey { case answer, general, refused, quota, kind, lead }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            answer = try c.decode(String.self, forKey: .answer)
            general = (try? c.decode(Bool.self, forKey: .general)) ?? false
            refused = (try? c.decode(Bool.self, forKey: .refused)) ?? false
            quota = try? c.decode(AskUsage.self, forKey: .quota)
            kind = try? c.decode(String.self, forKey: .kind)
            lead = try? c.decode(String.self, forKey: .lead)
        }
    }

    /// サーバーの AI に渡す行（公開の物だけ）。観光スポットの行か、使い方の頁の抜き書き
    enum Source: Encodable, Equatable {
        case spot(name: String, area: String, category: String, seasons: [String], times: [String], note: String?)
        case help(title: String, body: String)

        init(_ spot: OfficialSpot) {
            let c = TripAIService.Candidate(spot)
            let note = AskLibrary.guide(for: spot, query: .init()) ?? spot.seasons.first?.text ?? spot.times.first?.text
            self = .spot(name: c.name, area: c.area, category: c.category, seasons: c.seasons, times: c.times,
                         note: note.map { String($0.prefix(200)) })
        }

        init(_ page: AskHelpPage) {
            self = .help(title: page.title, body: String(page.lines.joined(separator: "\n").prefix(400)))
        }

        private enum CodingKeys: String, CodingKey { case kind, name, area, category, seasons, times, note, title, body }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .spot(name, area, category, seasons, times, note):
                try c.encode("spot", forKey: .kind)
                try c.encode(name, forKey: .name)
                try c.encode(area, forKey: .area)
                try c.encode(category, forKey: .category)
                try c.encode(seasons, forKey: .seasons)
                try c.encode(times, forKey: .times)
                try c.encodeIfPresent(note, forKey: .note)
            case let .help(title, body):
                try c.encode("help", forKey: .kind)
                try c.encode(title, forKey: .title)
                try c.encode(body, forKey: .body)
            }
        }
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
        let sources: [Source]
    }

    private struct LimitBody: Decodable { let reason: String?; let quota: AskUsage? }

    /// 試験の差し替え口（nil なら本物のサーバー）
    var reserveOverride: (@Sendable (Kind, Via) async throws -> AskUsage)?
    var askOverride: (@Sendable (String, [Turn], [OfficialSpot]) async throws -> ServerAnswer)?

    private let api: APIClient?

    init(api: APIClient?) { self.api = api }

    /// サーバーの AI に送る往復の数
    static let historyTurns = 2
    /// サーバーの AI に送る行の数（観光スポットと使い方の頁の合計。サーバーは 8 件まで）
    static let maxSources = 8

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
                              sources: Self.sources(text: text, spots: sources))
        return try await call(body, as: ServerAnswer.self)
    }

    /// 送る行: 使い方の頁（質問に合うもの）を先に、残りを観光スポットで埋める。合わせて 8 件まで
    static func sources(text: String, spots: [OfficialSpot]) -> [Source] {
        let help = AskHelpPages.matching(text).map(Source.init)
        return Array((help + spots.map(Source.init)).prefix(maxSources))
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
                throw Failure.limit(Self.reason(from: sink.data), Self.quota(from: sink.data))
            case .server(let status, _) where status == 401: throw Failure.signedOut
            case .server(let status, _) where status == 403 || status == 422:
                // 403 `proOnly`（無料の人のサーバーの AI）。旅行プランの plan は 422 `pro_only`
                if Self.reasonText(from: sink.data) == "proOnly" || APIClient.errorCode(from: sink.data) == "pro_only" {
                    throw Failure.proOnly
                }
                throw Failure.unavailable
            default: throw Failure.unavailable
            }
        }
    }

    static func reasonText(from data: Data?) -> String? {
        guard let data else { return nil }
        return (try? JSONDecoder().decode(LimitBody.self, from: data))?.reason
    }

    /// 429 の本文の `quota`（帯の数に使う）
    static func quota(from data: Data?) -> AskUsage? {
        guard let data else { return nil }
        return (try? JSONDecoder().decode(LimitBody.self, from: data))?.quota
    }

    /// 429 の本文の `reason`。読めなければ今日の分（いちばん控えめな言い方）
    static func reason(from data: Data?) -> AskLimitReason {
        guard let data, let body = try? JSONDecoder().decode(LimitBody.self, from: data),
              let raw = body.reason, let reason = AskLimitReason(rawValue: raw) else { return .day }
        return reason
    }
}

/// UI テストの見本（`-JPAskFixture YES`・Debug のときだけ）。サーバーへは送らない。
/// `-JPAskFixtureMode` で状態を替える: `usedUpDay`・`usedUpMonth`・`global`（取れない）、`pro`（Pro）、無ければ無料で今日あと2回。
/// `one` は1か所の答え（札1枚を広く）、`bullets` は箇条の答え（札 #663）
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
        case "usedUpDay": throw AskService.Failure.limit(.day, nil)
        case "usedUpMonth": throw AskService.Failure.limit(.month, nil)
        case "global": throw AskService.Failure.limit(.global, nil)
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
                         sources: [.init(kind: .help, label: L("使い方の頁「\(page.title)」", "Help: \(page.title)"))], kind: "steps")
        }
        if intent.spots, mode == "bullets" {
            // 1.1.107 の実機で出た形（札 #663）: 長い前置きと「- 名前: 説明」の箇条。札に無い名前（「架空の岬」）も混ぜる
            let picks = library.pickSpots(query)
            var lines = [L("観光スポットの情報から、合う所を選びました。どこも案内に見どころがあります。季節を変えると、ほかの所も出ます。ゆっくり選んでください。",
                           "Picked matching spots from the guides. Each has highlights in its notes. Try another season to see more.")]
            for p in picks.prefix(3) {
                lines.append("- \(p.spot.name): " + L("案内にある景色を、朝の光で撮れます。", "You can shoot the view in its notes in morning light."))
            }
            lines.append("- " + L("架空の岬: 台帳に無い所です。", "Imaginary Cape: not in the list."))
            return .init(text: lines.joined(separator: "\n"), general: false, picks: picks, photoIds: [],
                         sources: [.init(kind: .spots, label: AskText.spotsSource)], kind: "cards")
        }
        if intent.spots, mode == "one" {
            // 1か所の答え（札1枚を広く・札 #675 の答えの形）
            let picks = Array(library.pickSpots(query).prefix(1))
            return .init(text: L("秋の朝がいちばん向いています。人の少ない早い時間が静かに撮れます。", "Autumn mornings suit it best."),
                         general: false, picks: picks, photoIds: [],
                         sources: [.init(kind: .spots, label: AskText.spotsSource)], kind: "cards")
        }
        if intent.spots {
            let picks = library.pickSpots(query)
            return .init(text: L("観光スポットの案内から、合う所を選びました。", "Picked matching spots from the guides."),
                         general: false, picks: picks, photoIds: [],
                         sources: [.init(kind: .spots, label: AskText.spotsSource)], kind: "cards")
        }
        return .init(text: L("太陽は画面の端に置き、明るさを少し下げると、空の色が残ります。", "Keep the sun near the edge and lower the exposure a little to keep the sky's color."),
                     general: true, picks: [], photoIds: [], sources: [], kind: "text")
    }

    static var serverAnswer: AskService.ServerAnswer {
        .init(answer: L("夕方の案内がある観光スポットを近い順に選びました。", "Picked spots with evening notes, nearest first."), general: false)
    }
}
