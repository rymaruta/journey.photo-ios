import Foundation

/// AI で旅行プランを作るサーバーの口（`POST /user/trip-ai`・photo-gallery `api-user/src/tripAi.ts`・札 #621）。
///
/// - `status`: 今月の回数（無料 30・Pro と管理者 300。上限はサーバーが決める）
/// - `count`: 端末の AI で作った回を数える（無料の人だけ数える。Pro と管理者は数えない）
/// - `plan`: サーバーの AI（Amazon Bedrock・東京）で組む。候補の番号から選ぶだけ。送る前に同意を確かめる（`AIServerConsent`）
///
/// 上限は 429、読み取れなかった回は 422、AI が答えなかった回は 502（どれも回数は減らない）
struct TripAIService {

    struct Usage: Decodable, Equatable {
        /// free | pro | admin
        let tier: String
        let used: Int
        let limit: Int
        let remaining: Int
        let resetsOn: String
        /// 端末の AI の回も数えるか（無料の人だけ true）
        let countsDevice: Bool
    }

    struct Candidate: Encodable, Equatable {
        let name: String
        let area: String
        let category: String
        let seasons: [String]
        let times: [String]

        init(_ spot: OfficialSpot) {
            name = String(spot.name.prefix(60))
            area = [spot.region?.prefecture, spot.region?.city].compactMap { $0 }.joined(separator: " ")
            category = spot.category ?? ""
            seasons = spot.seasonKeys
            times = spot.timeKeys
        }
    }

    enum Failure: Error, Equatable {
        /// 今月の回数を使い切った
        case limit
        /// 頼みを読み取れなかった（回数は減らない）
        case unreadable
        /// AI が答えなかった・圏外（回数は減らない）
        case unavailable
        /// ログインしていない
        case signedOut
    }

    private struct UsageBody: Decodable {
        let usage: Usage
        /// 旅行プランの AI の今日と今月の数（status だけが返す・札 #652）。古いサーバーは返さない
        var trip: AskUsage?
    }
    private struct PlanBody: Decodable { let plan: TripAIPlan; let usage: Usage }
    private struct Request: Encodable {
        let action: String
        var request: String?
        var days: Int?
        var candidates: [Candidate]?
        var current: [TripAIPlan.Stop]?
    }

    private let api: APIClient

    init(api: APIClient) { self.api = api }

    func status() async throws -> Usage {
        try await statusWithQuota().usage
    }

    /// 今月の数と、今日の数（`trip.day`）。2026-11-20 判断（札 #667 の確かめ役）: 1日の上限に当たっているかを、
    /// AI を呼ぶ前に知るために読む
    func statusWithQuota() async throws -> (usage: Usage, trip: AskUsage?) {
        if let fixture = TripAIFixture.usage { return (fixture, nil) }
        let body = try await call(Request(action: "status"), as: UsageBody.self)
        return (body.usage, body.trip)
    }

    /// 組む前に1回取る（札 #652・2026-11-20 owner 承認）。**端末の AI の回も、無料も Pro も同じ上限で数える**
    /// （旅行プランの AI: 無料 1日5回かつ月30回、Pro 1日20回かつ月300回）。口は「AI に頼む」と同じ `reserve`（`kind: "trip"`）。
    /// 取れなければ `AskService.Failure.limit`
    func reserve(via: AskService.Via) async throws -> AskUsage {
        if TripAIFixture.isOn {
            if mode == "usedUp" { throw AskService.Failure.limit(.day, nil) }
            return try AskFixture.reserve(kind: .trip, via: via)
        }
        return try await AskService(api: api).reserve(kind: .trip, via: via)
    }

    private var mode: String { TripAIFixture.mode }

    func plan(request: String, days: Int?, candidates: [OfficialSpot], current: [TripAIPlan.Stop] = []) async throws -> (TripAIPlan, Usage) {
        // 2026-11-22 判断（審査 5.1.2(i)）: 同意の無いまま送らない。画面で聞き忘れた道があっても、ここで止める（`AIServerConsent`）
        try AIServerConsent.requireAccepted()
        if TripAIFixture.isOn { return try await TripAIFixture.plan(candidates: candidates, days: days, current: current) }
        let body = Request(action: "plan", request: String(request.prefix(TripAILimits.maxRequest)), days: days,
                           candidates: candidates.prefix(TripAILimits.maxCandidates).map(Candidate.init),
                           current: current.isEmpty ? nil : current)
        let res = try await call(body, as: PlanBody.self)
        return (res.plan, res.usage)
    }

    private func call<T: Decodable>(_ body: Request, as type: T.Type) async throws -> T {
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
                // 札 #652: 本文の `reason`（今日の分、今月の分、1人の止め、全体の止め）があれば帯の文を言い分ける
                if AskService.reasonText(from: sink.data) != nil {
                    throw AskService.Failure.limit(AskService.reason(from: sink.data), AskService.quota(from: sink.data))
                }
                throw Failure.limit
            case .server(let status, _) where status == 422 || status == 403:
                // 無料の人の plan は 422 `pro_only`（札 #652・サーバーの担当のコメント）
                if APIClient.errorCode(from: sink.data) == "pro_only" || AskService.reasonText(from: sink.data) == "proOnly" {
                    throw AskService.Failure.proOnly
                }
                if status == 403 { throw error }
                throw Failure.unreadable
            case .server(let status, _) where status == 502 || status == 503 || status == 504: throw Failure.unavailable
            default: throw error
            }
        }
    }
}

/// UI テストの見本（`-JPTripAIFixture YES`・Debug のときだけ）。サーバーへは送らず、候補の上から日に割った答えを返す
enum TripAIFixture {
    static let key = "JPTripAIFixture"
    /// 見本の状態（`usedUp` 今月の回数を使い切った・`silent` AI が答えない）。無ければふつう
    static let modeKey = "JPTripAIFixtureMode"
    /// AI が答えるまでの見本の待ち（秒・既定 2.5。1日目が出る前の骨組みを撮るため）
    static let delayKey = "JPTripAIFixtureDelay"

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

    /// 見本の回数。2026-11-20（札 #652）: サーバーの AI で組むのは Pro だけになったので、見本はふだん Pro
    /// （端末の AI の無いシミュレーターでも AI で組んだ形を撮る）。`usedUp` と `free` は無料の人
    static var usage: TripAIService.Usage? {
        guard isOn else { return nil }
        let left = mode == "usedUp" ? 0 : 3
        let free = mode == "usedUp" || mode == "free"
        let limit = free ? TripAILimits.free : TripAILimits.pro
        return .init(tier: free ? "free" : "pro", used: limit - left, limit: limit, remaining: left,
                     resetsOn: TripAIText.nextReset(), countsDevice: true)
    }

    static func plan(candidates: [OfficialSpot], days: Int?, current: [TripAIPlan.Stop] = []) async throws -> (TripAIPlan, TripAIService.Usage) {
        let delay = UserDefaults.standard.object(forKey: delayKey) == nil ? 2.5 : UserDefaults.standard.double(forKey: delayKey)
        try await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
        if mode == "usedUp" { throw TripAIService.Failure.limit }
        if mode == "silent" { throw TripAIService.Failure.unavailable }
        if !current.isEmpty {
            // 組み直し（札 #667）の見本: 必ず変わる答え（日を入れ替え、まだ入っていない候補を1つ1日目の頭に足す）。
            // 「今 | 組み直した案」の印と「この案にする」を撮るため
            let d = max(days ?? 1, 1)
            var stops = current.map { TripAIPlan.Stop(n: $0.n, day: d - $0.day + 1) }
            let used = Set(current.map(\.n))
            if let extra = candidates.indices.map({ $0 + 1 }).first(where: { !used.contains($0) }) {
                stops.insert(.init(n: extra, day: 1), at: 0)
            }
            let plan = TripAIPlan(title: "", days: d, stops: stops,
                                  reason: L("雨の日に向く所を先にし、日を入れ替えました。", "Rain-friendly places first; days swapped."))
            return (plan, usage ?? .init(tier: "pro", used: 1, limit: TripAILimits.pro, remaining: 299, resetsOn: TripAIText.nextReset(), countsDevice: true))
        }
        var plan = TripAIFallback.plan(candidates: candidates, days: days ?? 2, title: "")
        plan.reason = L("秋の案内がある所を入れ、朝に向く所を先にしました。", "Picked places with autumn notes, morning spots first.")
        return (plan, usage ?? .init(tier: "free", used: 1, limit: TripAILimits.free, remaining: 29, resetsOn: TripAIText.nextReset(), countsDevice: true))
    }
}
