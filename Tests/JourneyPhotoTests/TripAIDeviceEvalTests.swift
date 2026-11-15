import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 札 #621「AI で旅行プランを作る」を作り込む前の試験（2026-11-15 判断）。
///
/// - 端末の AI（Foundation Models）が Mac の CI のシミュレーターで使えるかを `measured [trip-ai]` の行で出す。
/// - 使えるときだけ、日本語の頼み方 30件（`TripAIEvalFixture`）を流し、日数・番号が候補の中か・好みに合うかを数える。
///   使えないときは数えずに抜ける（失敗にしない。使えないこと自体が取りたい事実）。
/// - 数は成果物 `build-logs` の `xcodebuild-full.log` の `measured [trip-ai]` の行。
final class TripAIDeviceEvalTests: XCTestCase {
    struct Case: Decodable {
        let id: Int
        let text: String
        let days: Int
        let want: [String]
        let n: Int
        let lines: String
        let seasons: [[String]]
        let times: [[String]]
        let cats: [String]
    }

    func testDeviceModelOnJapaneseRequests() async throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            print("measured [trip-ai] availability=os-too-old")
            return
        }
        let model = SystemLanguageModel.default
        let ja = model.supportsLocale(Locale(identifier: "ja_JP"))
        print("measured [trip-ai] availability=\(model.availability) supportsJa=\(ja)")
        guard case .available = model.availability else { return }

        let cases = try JSONDecoder().decode([Case].self, from: Data(TripAIEvalFixture.json.utf8))
        var daysOK = 0, validOK = 0, perDayOK = 0, prefOK = 0, prefN = 0, failed = 0
        var seconds: [Double] = []
        for c in cases {
            let session = LanguageModelSession(instructions: TripAIEvalFixture.system)
            let prompt = "頼み: \(c.text)\n候補:\n\(c.lines)"
            let start = Date()
            do {
                let plan = try await session.respond(to: prompt, generating: TripAIProbePlan.self).content
                let dt = Date().timeIntervalSince(start)
                seconds.append(dt)
                let ns = plan.stops.map(\.n)
                let valid = !ns.isEmpty && ns.allSatisfy { (1...c.n).contains($0) } && Set(ns).count == ns.count
                if plan.days == c.days { daysOK += 1 }
                if valid { validOK += 1 }
                var perDay: [Int: Int] = [:]
                for s in plan.stops { perDay[s.day, default: 0] += 1 }
                let cap = (c.want.contains("slow") || c.want.contains("short")) ? 3 : 5
                if valid, perDay.values.allSatisfy({ (1...cap).contains($0) }), (perDay.keys.max() ?? 0) <= c.days { perDayOK += 1 }
                if valid, let ok = Self.preferenceOK(c, picked: ns.map { $0 - 1 }) {
                    prefN += 1
                    if ok { prefOK += 1 }
                }
                let stopsText = plan.stops.map { "\($0.day):\($0.n)" }.joined(separator: " ")
                print("measured [trip-ai] case=\(c.id) days=\(plan.days)/\(c.days) valid=\(valid) sec=\(String(format: "%.1f", dt)) stops=\(stopsText) title=\(plan.title) reason=\(plan.reason)")
            } catch {
                failed += 1
                print("measured [trip-ai] case=\(c.id) error=\(error)")
            }
        }
        let avg = seconds.isEmpty ? 0 : seconds.reduce(0, +) / Double(seconds.count)
        print("measured [trip-ai] summary days=\(daysOK)/\(cases.count) valid=\(validOK)/\(cases.count) perDay=\(perDayOK)/\(cases.count) pref=\(prefOK)/\(prefN) failed=\(failed) avgSec=\(String(format: "%.1f", avg))")
        #else
        print("measured [trip-ai] availability=no-framework")
        #endif
    }

    /// 好み（季節・時間帯・雨の日・温泉）が、候補にあるのに選ばれていないかを見る。候補に無い好みは数えない。
    static func preferenceOK(_ c: Case, picked: [Int]) -> Bool? {
        let indoor: Set<String> = ["博物館", "美術館", "水族館", "建築", "市場", "鍾乳洞", "洞窟", "植物園"]
        var checks: [Bool] = []
        for w in c.want {
            switch w {
            case "autumn", "spring", "summer", "winter":
                if c.seasons.contains(where: { $0.contains(w) }) { checks.append(picked.contains { c.seasons[$0].contains(w) }) }
            case "night", "morning", "evening":
                let keys: Set<String> = w == "night" ? ["night", "bluehour"] : w == "morning" ? ["dawn", "morning"] : ["sunset", "evening", "golden", "bluehour"]
                if c.times.contains(where: { !keys.isDisjoint(with: $0) }) { checks.append(picked.contains { !keys.isDisjoint(with: c.times[$0]) }) }
            case "indoor":
                checks.append(picked.filter { indoor.contains(c.cats[$0]) }.count * 2 >= picked.count)
            case "onsen":
                if c.cats.contains("温泉") { checks.append(picked.contains { c.cats[$0] == "温泉" }) }
            default:
                break
            }
        }
        return checks.isEmpty ? nil : !checks.contains(false)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct TripAIProbePlan {
    @Guide(description: "日数。日帰りは1、1泊2日は2、2泊3日は3")
    var days: Int
    @Guide(description: "短い題。12字まで")
    var title: String
    @Guide(description: "選んだ候補。番号と何日目", .count(1...15))
    var stops: [TripAIProbeStop]
    @Guide(description: "並べた理由。日本語で1文、40字まで")
    var reason: String
}

@available(iOS 26.0, *)
@Generable
struct TripAIProbeStop {
    @Guide(description: "候補の番号", .range(1...20))
    var n: Int
    @Guide(description: "何日目", .range(1...7))
    var day: Int
}
#endif
