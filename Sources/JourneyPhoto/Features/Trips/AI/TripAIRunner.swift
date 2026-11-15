import SwiftUI

/// AI で組んだ結果
struct TripAIResult {
    /// どう組んだか（AI か、AI なしで組んだ理由か）
    enum Mode: Equatable {
        case ai
        /// 今月の回数を使い切った（AI なしで組んだ）
        case usedUp
        /// 圏外で端末の AI も使えない、または回数を数えられない（AI なしで組んだ）
        case offline
        /// AI が答えなかった・答えを読めなかった（AI なしで組んだ）
        case silent
    }
    let title: String
    let days: [[OfficialSpot]]
    /// 並べた理由の1文（AI なしでは決まった1文）
    let reason: String
    /// 移動が無理で外した場所（日の下の「外しました　戻す」）
    let removed: [TripAIRouteCheck.Removed]
    let mode: Mode
    /// 候補（「替える」の残りの場所）
    let candidates: [OfficialSpot]
}

/// 組む手順（札 #621）。画面は持たない（待つ間の画面は `TripAIBuildView`）。
///
/// どの AI で組むか（設定の行は作らない・2026-11-15 判断・案の推奨）:
/// - 端末の AI が使える iPhone → 端末で組む（0円・圏外でも動く）。**無料の人はサーバーで回数を数える**
///   （組めたあとに `count`。上限なら組んだものを使わず AI なしの組み方へ。圏外で数えられなければ AI なし）
/// - 使えない iPhone → サーバーの AI（`POST /user/trip-ai`・Amazon Nova Lite・東京）。回数はサーバーが数える
/// - 圏外・上限・AI が答えない → AI なしの組み方（`TripAIFallback`）。行き止まりにしない
@MainActor
final class TripAIRunner: ObservableObject {

    /// 待つ間に見せる段（実際の手順の順）
    enum Step: Int, Comparable, CaseIterable {
        case collecting, ordering, measuring, done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    @Published private(set) var step: Step = .collecting
    /// 集めた候補（写真を順に並べる）
    @Published private(set) var candidates: [OfficialSpot] = []
    @Published private(set) var usage: TripAIService.Usage?
    /// できた日（1日目から順に埋まる。移動の目安を測り終えた日から出す）
    @Published private(set) var readyDays: [[OfficialSpot]] = []
    /// 組む日数の見込み（まだの日は骨組みで出す）
    @Published private(set) var expectedDays = 1
    /// 押してから1日目が出るまで・全部そろうまで（秒）。`measured [trip-ai-time]` の行にも出す
    private(set) var firstDaySeconds: Double?
    private(set) var allDaysSeconds: Double?
    private var startedAt = Date()
    let onDevice: Bool

    init(onDevice: Bool = TripAIDevice.isAvailable) {
        self.onDevice = onDevice
    }

    func setUsage(_ u: TripAIService.Usage?) { usage = u }

    /// 回数を使い切っているか（無料の人は端末の AI も数える）
    var isUsedUp: Bool {
        guard let usage else { return false }
        if onDevice && !usage.countsDevice { return false }
        return usage.remaining <= 0
    }

    func loadUsage(service: TripAIService) async {
        let u = try? await service.status()
        if let u { usage = u }
    }

    /// 頼みから候補を集める（AI は使わない）。行き先が無い・候補が0なら空
    static func candidates(for ask: TripAIAsk, index: [OfficialSpot], wishlist: Set<String>) -> [OfficialSpot] {
        guard ask.hasPlace else { return [] }
        let match = TripAIDestination.Match(prefectures: ask.prefectures, cities: ask.cities)
        var picked = TripAICandidates.pick(text: ask.requestText, match: match, spots: index, wishlist: wishlist.union(ask.mustSpotIds))
        // 札の元になった行きたい場所は必ず候補に入れる（20件の中に）
        let must = index.filter { ask.mustSpotIds.contains($0.spotId) }
        for s in must where !picked.contains(where: { $0.spotId == s.spotId }) {
            if picked.count >= TripAILimits.maxCandidates { picked.removeLast() }
            picked.insert(s, at: 0)
        }
        return picked
    }

    /// 組む。候補が無ければ nil（行き先を選び直す）
    func build(_ ask: TripAIAsk, index: [OfficialSpot], wishlist: Set<String>, offline: Bool, service: TripAIService,
               eta: @escaping TripAIRouteCheck.ETA = TripAIRouteCheck.mapsETA) async -> TripAIResult? {
        step = .collecting
        startedAt = Date()
        readyDays = []
        expectedDays = ask.days ?? 1
        firstDaySeconds = nil
        allDaysSeconds = nil
        let cands = Self.candidates(for: ask, index: index, wishlist: wishlist)
        guard !cands.isEmpty else { return nil }
        candidates = cands
        let title0 = TripAIText.defaultTitle(place: ask.place, days: ask.days ?? 1)
        return await run(request: ask.requestText, candidates: cands, fixedDays: ask.days, current: [],
                         title0: title0, offline: offline, service: service, eta: eta)
    }

    /// 今の日程を頼みに合わせて直す（「ゆっくり」「雨でも」「書いて直す」）。候補は作ったときの候補（無ければ今の場所）
    func revise(request: String, current: [[OfficialSpot]], candidates known: [OfficialSpot], index: [OfficialSpot],
                offline: Bool, service: TripAIService, title: String,
                eta: @escaping TripAIRouteCheck.ETA = TripAIRouteCheck.mapsETA) async -> TripAIResult? {
        let now = current.flatMap { $0 }
        guard !now.isEmpty else { return nil }
        var cands = Array(now.prefix(TripAILimits.maxCandidates))
        for s in known where cands.count < TripAILimits.maxCandidates && !cands.contains(where: { $0.spotId == s.spotId }) {
            cands.append(s)
        }
        if cands.count < TripAILimits.maxCandidates {
            let prefs = Array(Set(now.compactMap { $0.region?.prefecture })).sorted()
            let match = TripAIDestination.Match(prefectures: prefs, cities: Set(now.compactMap { $0.region?.city }))
            for s in TripAICandidates.pick(text: request, match: match, spots: index, wishlist: [])
            where cands.count < TripAILimits.maxCandidates && !cands.contains(where: { $0.spotId == s.spotId }) {
                cands.append(s)
            }
        }
        candidates = cands
        var stops: [TripAIPlan.Stop] = []
        for (d, day) in current.enumerated() {
            for s in day { if let i = cands.firstIndex(where: { $0.spotId == s.spotId }) { stops.append(.init(n: i + 1, day: d + 1)) } }
        }
        return await run(request: request, candidates: cands, fixedDays: max(current.count, 1), current: stops,
                         title0: title, offline: offline, service: service, eta: eta)
    }

    private func run(request: String, candidates: [OfficialSpot], fixedDays: Int?, current: [TripAIPlan.Stop],
                     title0: String, offline: Bool, service: TripAIService,
                     eta: @escaping TripAIRouteCheck.ETA) async -> TripAIResult? {
        step = .ordering
        var plan: TripAIPlan?
        var mode: TripAIResult.Mode = .ai
        if isUsedUp {
            mode = .usedUp
        } else if offline && !onDevice {
            mode = .offline
        } else if onDevice {
            let message = TripAIDevice.message(request: request, days: fixedDays, candidates: candidates, current: current)
            let made = try? await TripAIDevice.plan(message: message, days: fixedDays)
            if let made {
                if usage?.countsDevice == false {
                    plan = made
                } else {
                    do {
                        usage = try await service.countDeviceUse()
                        plan = made
                    } catch TripAIService.Failure.limit {
                        markUsedUp()
                        mode = .usedUp
                    } catch {
                        // 数えられない（圏外）なら、組んだものを使わない（上限はサーバーで守る）
                        mode = .offline
                    }
                }
            } else {
                mode = .silent
            }
        } else {
            do {
                let (made, used) = try await service.plan(request: request, days: fixedDays, candidates: candidates, current: current)
                plan = made
                usage = used
            } catch TripAIService.Failure.limit {
                markUsedUp()
                mode = .usedUp
            } catch TripAIService.Failure.unavailable where offline {
                mode = .offline
            } catch {
                mode = .silent
            }
        }
        // やめた（画面を閉じた）なら、ここで終わる。サーバーで作り終えていた回は数えられている（確かめていない所）
        if Task.isCancelled { return nil }

        let checked = plan?.sanitized(candidateCount: candidates.count, fixedDays: fixedDays)
        if plan != nil && checked == nil { mode = .silent }
        let days = fixedDays ?? 1
        let chosen: TripAIPlan
        if let checked {
            chosen = checked
        } else if !current.isEmpty {
            // 直すときに AI が使えなければ、今の日程のまま（壊さない）
            chosen = TripAIPlan(title: title0, days: days, stops: current, reason: "")
        } else {
            chosen = TripAIFallback.plan(candidates: candidates, days: days, title: title0)
        }
        step = .measuring
        // 1日目から順に、移動の目安を測り終えた日を出す（全部そろうまで白紙にしない・owner 2026-11-15）
        let lists = chosen.dayLists(candidates)
        expectedDays = lists.count
        var keptDays: [[OfficialSpot]] = []
        var removedAll: [TripAIRouteCheck.Removed] = []
        for (d, day) in lists.enumerated() {
            let one = await TripAIRouteCheck.trim([day], eta: eta)
            if Task.isCancelled { return nil }
            keptDays.append(one.days.first ?? [])
            removedAll += one.removed.map { TripAIRouteCheck.Removed(spot: $0.spot, day: d, minutes: $0.minutes) }
            readyDays = keptDays
            if firstDaySeconds == nil { firstDaySeconds = Date().timeIntervalSince(startedAt) }
        }
        allDaysSeconds = Date().timeIntervalSince(startedAt)
        let engine = mode != .ai ? "none" : (onDevice ? "device" : "server")
        let first = String(format: "%.2f", firstDaySeconds ?? -1)
        let all = String(format: "%.2f", allDaysSeconds ?? -1)
        print("measured [trip-ai-time] engine=\(engine) firstDay=\(first)s all=\(all)s days=\(lists.count)")
        let trimmed = (days: keptDays.filter { !$0.isEmpty }, removed: removedAll)
        let reason = checked?.reasonChecked(against: candidates)
            ?? L("AI を使わずに、地域でまとめて近い順に並べました。", "Planned without AI: grouped by area, nearest first.")
        step = .done
        return TripAIResult(title: chosen.title.isEmpty ? title0 : chosen.title, days: trimmed.days,
                            reason: reason, removed: trimmed.removed, mode: mode, candidates: candidates)
    }

    private func markUsedUp() {
        if let u = usage {
            usage = .init(tier: u.tier, used: u.limit, limit: u.limit, remaining: 0, resetsOn: u.resetsOn, countsDevice: u.countsDevice)
        } else {
            usage = .init(tier: "free", used: TripAILimits.free, limit: TripAILimits.free, remaining: 0,
                          resetsOn: TripAIText.nextReset(), countsDevice: true)
        }
    }
}
