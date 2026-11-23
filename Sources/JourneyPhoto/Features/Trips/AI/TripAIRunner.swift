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
        /// 端末の AI が無い iPhone の無料の人（サーバーの AI は Pro だけ・札 #652。AI なしで組んだ）
        case proOnly
        /// サーバーで回数を取れなかった（429 の `reason`: 今日の分、今月の分、1人の止め、全体の止め・札 #652）
        case limited(AskLimitReason)
        /// サーバーの AI への送信を「やめる」と答えた（送らずに AI なしで組んだ・2026-11-22 判断・`AIServerConsent`）
        case declined
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
    /// 答えの見張りで断った（題か理由に、鍵の形・内部の名前・URL などが混じった・`AskGuard.leaks`）。
    /// 組み直し（札 #667）だけが立てる。立ったら案を出さず、断りの1行を出す
    var refused = false
}

/// 組む手順（札 #621）。画面は持たない（待つ間の画面は `TripAIBuildView`）。
///
/// どの AI で組むか（設定の行は作らない・2026-11-15 判断・案の推奨）:
/// - 端末の AI が使える iPhone → 端末で組む（0円）。**組む前にサーバーで1回取る**（`reserve`・札 #652。無料も Pro も、
///   1日と月の上限で数える。上限なら AI なしの組み方へ。圏外で数えられなければ AI なし）
/// - 使えない iPhone → Pro と管理者だけサーバーの AI（`POST /user/trip-ai`・Amazon Nova Lite・東京）。回数はサーバーが数える。
///   無料の人はサーバーで組まず、AI なしで組む（`.proOnly`・2026-11-20 owner 承認）
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
    /// 打った文をサーバーへ送ったか（組めなかった回も含む）。同意の試験が「送っていない」を確かめるのに使う（`AIServerConsentTests`）
    private(set) var askedServer = false

    /// 試験だけが差し替える AI の答え（頼み・候補・日数・今の日程 → 答え）。nil ならサーバーか端末の AI
    typealias Planner = (String, [OfficialSpot], Int?, [TripAIPlan.Stop]) async throws -> TripAIPlan
    private let planner: Planner?
    /// 端末の AI（文・日数 → 答え）。nil なら `TripAIDevice.plan`。試験は数え方を確かめるために差し替える
    typealias DevicePlanner = (String, Int?) async throws -> TripAIPlan
    private let devicePlanner: DevicePlanner?
    /// 回数を1回取る口。nil なら `TripAIService.reserve`。試験は「数えた回」を数えるために差し替える
    typealias Reserver = (AskService.Via) async throws -> AskUsage
    private let reserver: Reserver?
    /// サーバーの AI に送ってよいか（同意のシート）。nil なら `AIServerConsent.shared.request`。試験は差し替える
    typealias Consent = () async -> Bool
    private let consent: Consent?

    /// 見本の AI（`-JPTripAIFixture`・Debug の UI テストだけ）のときは端末の AI を使わず、見本の答え（サーバーの道）で組む。
    /// 2026-11-20 判断（札 #667・Mac run 1621）: CI の模擬機は `availability=available supportsJa=true` を返すのに、
    /// 答えは毎回 `ModelManagerError 1019` で落ちた（`measured [trip-ai]` の9件すべて）。端末の道に入って「AI が答えなかった」に
    /// なり、見本の答えが使われなかった
    nonisolated static var usesDeviceAI: Bool { TripAIDevice.isAvailable && !TripAIFixture.isOn }

    init(onDevice: Bool = TripAIRunner.usesDeviceAI, planner: Planner? = nil,
         devicePlanner: DevicePlanner? = nil, reserver: Reserver? = nil, consent: Consent? = nil) {
        self.onDevice = onDevice
        self.consent = consent
        self.planner = planner
        self.devicePlanner = devicePlanner
        self.reserver = reserver
    }

    func setUsage(_ u: TripAIService.Usage?) { usage = u }

    /// 今日の分を使い切ったか（429 の `day`、または status・reserve の `trip.day.remaining` が0）。
    /// 2026-11-20 判断（札 #667 の確かめ役）: **月の数（`usage`）とは別に覚える。** 前は1日の上限でも `markUsedUp` が
    /// 月の残りを0にし、次から「今月の回数を使い切りました」と間違って出していた
    @Published private(set) var dayUsedUp = false

    /// 回数を使い切っているか（今月の分。2026-11-20 から端末の AI の回も、無料も Pro も数える・札 #652）
    var isUsedUp: Bool {
        guard let usage else { return false }
        return usage.remaining <= 0
    }

    func loadUsage(service: TripAIService) async {
        guard let got = try? await service.statusWithQuota() else { return }
        usage = got.usage
        if let day = got.trip?.day { dayUsedUp = day.remaining <= 0 }
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
    ///
    /// - Parameter countAfter: 組み直しの案（札 #667）。端末の AI の回は**答えを画面に出す直前に1回取る**（答えなかった回・
    ///   見張りで断った回・取り消した回は数えない）。答えの題と理由は見張りを通す。AI が使えなければ今の日程を案にしない
    func revise(request: String, current: [[OfficialSpot]], candidates known: [OfficialSpot], index: [OfficialSpot],
                offline: Bool, service: TripAIService, title: String, countAfter: Bool = false,
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
                         title0: title, offline: offline, service: service, countAfter: countAfter, eta: eta)
    }

    private func run(request: String, candidates: [OfficialSpot], fixedDays: Int?, current: [TripAIPlan.Stop],
                     title0: String, offline: Bool, service: TripAIService, countAfter: Bool = false,
                     eta: @escaping TripAIRouteCheck.ETA) async -> TripAIResult? {
        step = .ordering
        var plan: TripAIPlan?
        var mode: TripAIResult.Mode = .ai
        var refused = false
        // サーバーで組んでよいか（端末の AI が無い iPhone の Pro と管理者だけ・札 #652）
        var server = ServerUse.allowed
        if planner == nil, !isUsedUp, !dayUsedUp, !offline, !onDevice {
            server = await mayUseServer(service: service)
        }
        // 端末の AI の回を、移動の見込みを測った後（案を出す直前）に取るか（組み直し・札 #667）
        var reserveAtEnd = false
        if isUsedUp {
            mode = .usedUp
        } else if dayUsedUp {
            // 今日の分を使い切っている: 呼ぶ前に止める（月の分の文にしない）
            mode = .limited(.day)
        } else if let planner {
            plan = try? await planner(request, candidates, fixedDays, current)
            if plan == nil { mode = .silent }
        } else if offline && !onDevice {
            mode = .offline
        } else if onDevice && countAfter {
            // 2026-11-20 判断（札 #667・組み直し）: 「AI に頼む」（`AskEngine` の 5a）と同じく、**答えを画面に出す直前に1回取る**。
            // AI が答えなかった、形が崩れた、見張りで断った、画面を閉じて取り消した回は数えない。圏外は数えられないので AI を呼ばない
            if offline {
                mode = .offline
            } else {
                let message = TripAIDevice.message(request: request, days: fixedDays, candidates: candidates, current: current)
                let made: TripAIPlan?
                if let devicePlanner {
                    made = try? await devicePlanner(message, fixedDays)
                } else {
                    made = try? await TripAIDevice.plan(message: message, days: fixedDays)
                }
                if Task.isCancelled { return nil }
                if let made, made.sanitized(candidateCount: candidates.count, fixedDays: fixedDays) != nil {
                    if TripReplan.leaks(made) {
                        refused = true
                        mode = .silent
                    } else {
                        // 回は、移動の見込みを測り終えて案を出す直前に取る（下の `reserveAtEnd`）。
                        // 測っている間に画面を閉じた（取り消した）回は数えない
                        plan = made
                        reserveAtEnd = true
                    }
                } else {
                    mode = .silent
                }
            }
        } else if onDevice {
            // 2026-11-20（札 #652・owner 承認）: **組む前にサーバーで1回取る**。端末の AI の回も、無料も Pro も同じ上限
            // （1日と月）で数える。前は組んだあとに無料の人だけ数えていた（Pro は数えず、1日の上限も無かった）。
            // 数えられない（圏外）なら AI を使わない（上限はサーバーで守る）
            var reserved = false
            do {
                let left = try await service.reserve(via: .device)
                reserved = true
                setRemaining(left)
            } catch AskService.Failure.limit(let reason, _) {
                noteLimit(reason)
                mode = .limited(reason)
            } catch {
                mode = .offline
            }
            if reserved {
                let message = TripAIDevice.message(request: request, days: fixedDays, candidates: candidates, current: current)
                let made = try? await TripAIDevice.plan(message: message, days: fixedDays)
                if let made {
                    plan = made
                } else {
                    mode = .silent
                }
            }
        } else if server == .unknown {
            // 2026-11-20 判断: Pro かどうかが読めなかった（status の失敗）。「Pro だけ」とは言わず、AI なしで組んだ理由を言う
            mode = .silent
        } else if server == .proOnly {
            // 2026-11-20（札 #652・owner 承認）: 端末の AI が無い iPhone の**無料の人はサーバーで組まない**
            // （サーバーの AI は Pro だけ。アプリ全体の AI の請求を月500円までに収める）。AI なしで組み、帯で Pro を案内する
            mode = .proOnly
        } else if !(await serverConsented()) {
            // 2026-11-22 判断（審査 5.1.2(i)）: サーバーの AI に初めて送る直前に1回だけ同意を聞く。「やめる」なら送らずに AI なしで組む
            // （組み直しは今の日程のまま）。旅行プランは押した回ごとに聞く（「AI で作る」「整えて」ははっきり頼む操作）
            mode = .declined
        } else {
            // 同意を待つ間に画面を閉じた（取り消した）なら送らない（2026-11-22 確かめ役の指摘）
            if Task.isCancelled { return nil }
            // 打った文をサーバーへ送る（送ったことを覚える・`askedServer`）
            askedServer = true
            do {
                let (made, used) = try await service.plan(request: request, days: fixedDays, candidates: candidates, current: current)
                plan = made
                usage = used
            } catch TripAIService.Failure.limit {
                markUsedUp()
                mode = .usedUp
            } catch AskService.Failure.limit(let reason, _) {
                noteLimit(reason)
                mode = .limited(reason)
            } catch AskService.Failure.proOnly {
                mode = .proOnly
            } catch TripAIService.Failure.unavailable where offline {
                mode = .offline
            } catch {
                mode = .silent
            }
        }
        // やめた（画面を閉じた）なら、ここで終わる。サーバーで作り終えていた回は数えられている（確かめていない所）
        if Task.isCancelled { return nil }
        // 組み直し（札 #667）: サーバーの答えも見張りを通す（題と理由に漏れの形が混じったら案を出さない）
        if countAfter, let made = plan, TripReplan.leaks(made) {
            plan = nil
            refused = true
            mode = .silent
        } else if let made = plan {
            // 2026-11-23 判断: 最初に作る回も、端末の AI とサーバーの両方で題と理由を見張りに通す（前は組み直しだけ）。
            // 混じった方を空にする（日程は使う）。理由に候補の番号（「3と7は近いので」）があれば理由を空にする
            plan = made.screenedTitleAndReason()
        }

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
        // 直すとき（今の日程がある）は空の日を詰めない。日の番号をそのまま返し、元の日付と場所の組を崩さない
        let revising = !current.isEmpty
        // 2026-11-23 判断（東山→嵐山→東山と行ったり来たりした）: 最初に作るときは、日の中の並びをアプリが決める
        // （近い順と時間帯の順・`TripDraft.plan`）。組み直しは利用者の並びを壊さないので AI の並びのまま
        let lists = revising ? chosen.dayLists(candidates, keepEmpty: true) : TripAIDayOrder.ordered(chosen.dayLists(candidates))
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
        let trimmed = (days: revising ? keptDays : keptDays.filter { !$0.isEmpty }, removed: removedAll)
        let reason = checked?.reasonChecked(against: candidates)
            ?? L("AI を使わずに、地域でまとめて近い順に並べました。", "Planned without AI: grouped by area, nearest first.")
        if reserveAtEnd {
            // 2026-11-20 判断（札 #667 の確かめ役）: 端末の AI の回は**ここで取る**（案を出す直前）。取り消した回は数えない
            if Task.isCancelled { return nil }
            do {
                let left: AskUsage
                if let reserver {
                    left = try await reserver(.device)
                } else {
                    left = try await service.reserve(via: .device)
                }
                setRemaining(left)
            } catch AskService.Failure.limit(let reason, _) {
                noteLimit(reason)
                mode = .limited(reason)
            } catch {
                mode = .offline
            }
            if Task.isCancelled { return nil }
        }
        step = .done
        return TripAIResult(title: chosen.title.isEmpty ? title0 : chosen.title, days: trimmed.days,
                            reason: reason, removed: trimmed.removed, mode: mode, candidates: candidates, refused: refused)
    }

    enum ServerUse: Equatable { case allowed, proOnly, unknown }

    private func serverConsented() async -> Bool {
        if let consent { return await consent() }
        return await AIServerConsent.shared.request()
    }

    /// サーバーで組んでよいか（Pro と管理者だけ）。回数がまだ分からなければ一度だけ読む。読めなければ組まない（費用を守る側）
    private func mayUseServer(service: TripAIService) async -> ServerUse {
        if usage == nil { usage = try? await service.status() }
        guard let tier = usage?.tier else { return .unknown }
        return tier == "pro" || tier == "admin" ? .allowed : .proOnly
    }

    /// 取れた回の残り（月の数）を、今の回数の表示に写す。今日の残りも覚える
    private func setRemaining(_ left: AskUsage) {
        usage = .init(tier: left.tier, used: left.month.used, limit: left.month.limit, remaining: left.month.remaining,
                      resetsOn: left.month.resetsOn ?? usage?.resetsOn ?? TripAIText.nextReset(), countsDevice: true)
        dayUsedUp = left.day.remaining <= 0
    }

    /// 429 の理由を覚える。今日の分は `dayUsedUp`、今月の分だけ月の残りを0にする（1日の上限で月の文を出さない）
    private func noteLimit(_ reason: AskLimitReason) {
        switch reason {
        case .day: dayUsedUp = true
        case .month: markUsedUp()
        default: break
        }
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
