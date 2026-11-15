import SwiftUI

/// AI で作っている旅行プラン（札 #621・owner 2026-11-15「作ってる間に待たせるの良くないな」）。
///
/// - 押したらすぐ日程の画面（`TripAIBuildingView`）を開き、1日目から順にできた日を埋める
/// - **画面を離れても作り続ける**（この入れ物はアプリが動いている間ずっとある）。できたら「旅行プラン」に保存し、
///   まだ見ていない印（真鍮の点）を付け、アプリの上の帯で「金沢の旅ができました」と知らせる。通知の許可は求めない
/// - 失敗・圏外・上限は、日程の画面の中と帯の両方で分かるようにする。やり直しは1回押すだけ（`retry`）
@MainActor
final class TripAIJobs: ObservableObject {
    static let shared = TripAIJobs()

    enum Failure: Equatable {
        /// 電波が届かず、端末の AI も使えない（日程の保存もできない）
        case offline
        /// 候補が集まらなかった（行き先に観光スポットが無い）
        case noCandidates
        /// 保存できなかった
        case save(String)
    }

    enum State: Equatable {
        case building
        case saved(planId: String)
        case failed(Failure)
    }

    @MainActor
    final class Job: ObservableObject, Identifiable {
        let id = UUID()
        let ask: TripAIAsk
        @Published var state: State = .building
        let runner: TripAIRunner
        var result: TripAIResult?
        init(ask: TripAIAsk, runner: TripAIRunner) {
            self.ask = ask
            self.runner = runner
        }
        var title: String { result?.title ?? TripAIText.defaultTitle(place: ask.place, days: ask.days ?? 1) }
    }

    /// 上の帯（できた・作れなかった）
    struct Banner: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let action: String
        let jobId: UUID
        let planId: String?
        let failed: Bool
        static func == (a: Banner, b: Banner) -> Bool { a.id == b.id }
    }

    @Published private(set) var jobs: [Job] = []
    @Published var banner: Banner?
    /// 帯を押した・一覧から開く（アプリのいちばん上で日程の画面を開く）
    @Published var openPlanId: String?
    /// 今その job の画面を見ているか（見ている間は帯を出さない）
    @Published var watching: UUID?
    /// まだ見ていない AI のプラン（真鍮の点）。端末に覚える
    @Published private(set) var unseen: Set<String>

    private static let unseenKey = "tripAI.unseen"
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var contexts: [UUID: (environment: AppEnvironment, index: [OfficialSpot], wishlist: Set<String>, offline: () -> Bool)] = [:]

    init() {
        unseen = Set(UserDefaults.standard.stringArray(forKey: Self.unseenKey) ?? [])
    }

    func job(_ id: UUID) -> Job? { jobs.first { $0.id == id } }

    /// 作り始める。すぐ返す（呼び手は日程の画面を開く）
    @discardableResult
    func start(_ ask: TripAIAsk, environment: AppEnvironment, index: [OfficialSpot], wishlist: Set<String>,
               usage: TripAIService.Usage?, offline: @escaping () -> Bool) -> Job {
        let runner = TripAIRunner()
        runner.setUsage(usage)
        let job = Job(ask: ask, runner: runner)
        jobs.append(job)
        contexts[job.id] = (environment, index, wishlist, offline)
        launch(job)
        return job
    }

    /// やり直し（1回押すだけ）
    func retry(_ job: Job) {
        banner = nil
        job.state = .building
        launch(job)
    }

    /// やめる（日程は作らない）
    func cancel(_ job: Job) {
        tasks[job.id]?.cancel()
        tasks[job.id] = nil
        jobs.removeAll { $0.id == job.id }
        contexts[job.id] = nil
    }

    func markSeen(_ planId: String) {
        guard unseen.contains(planId) else { return }
        unseen.remove(planId)
        UserDefaults.standard.set(Array(unseen), forKey: Self.unseenKey)
    }

    private func markUnseen(_ planId: String) {
        unseen.insert(planId)
        UserDefaults.standard.set(Array(unseen), forKey: Self.unseenKey)
    }

    private func launch(_ job: Job) {
        guard let ctx = contexts[job.id] else { return }
        tasks[job.id]?.cancel()
        tasks[job.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            // 見本（UI テスト・Debug のみ）の `offline` は圏外として扱う（圏外の画面を撮るため）
            let offline = ctx.offline() || TripAIFixture.mode == "offline"
            // 電波が無く端末の AI も使えないときは、日程を保存できないので作らない（行き止まりにせず、やり直しを1回で）
            if offline && !job.runner.onDevice {
                return self.fail(job, .offline)
            }
            guard let result = await job.runner.build(job.ask, index: ctx.index, wishlist: ctx.wishlist,
                                                      offline: offline, service: ctx.environment.tripAI) else {
                if Task.isCancelled { return }
                return self.fail(job, .noCandidates)
            }
            if Task.isCancelled { return }
            job.result = result
            let plans = TripPlansModel()
            let title = TripPlanService.titleToSend(result.title)
            let days = TripDraft.tripDays(result.days.map { $0.map(TripDraft.place(spot:)) })
            guard let made = await plans.create(title: title, days: days, environment: ctx.environment) else {
                if Task.isCancelled { return }
                let message = plans.errorMessage ?? L("旅行プランを保存できませんでした", "Couldn't save the trip")
                return self.fail(job, ctx.offline() ? .offline : .save(message))
            }
            TripAINotes.shared.set(made.planId, TripAINote(reason: result.reason, mode: result.mode,
                                                           removed: result.removed, candidates: result.candidates))
            job.state = .saved(planId: made.planId)
            TripPlanChanges.shared.changed(made.planId)
            if self.watching != job.id {
                self.markUnseen(made.planId)
                let text = result.mode == .ai
                    ? L("「\(result.title)」ができました", "“\(result.title)” is ready")
                    : L("「\(result.title)」ができました（AI なし）", "“\(result.title)” is ready (without AI)")
                self.banner = Banner(text: text, action: L("開く", "Open"), jobId: job.id, planId: made.planId, failed: false)
            }
            self.tasks[job.id] = nil
        }
    }

    private func fail(_ job: Job, _ failure: Failure) {
        job.state = .failed(failure)
        tasks[job.id] = nil
        guard watching != job.id else { return }
        banner = Banner(text: TripAIJobText.failureLine(failure, title: job.title), action: L("もう一度", "Retry"),
                        jobId: job.id, planId: nil, failed: true)
    }

    /// 帯を押した
    func tapBanner() {
        guard let b = banner else { return }
        banner = nil
        if let planId = b.planId {
            markSeen(planId)
            openPlanId = planId
        } else if let job = job(b.jobId) {
            retry(job)
        }
    }
}

/// 帯の言葉（画面を持たない・試験は Linux で）
enum TripAIJobText {
    static func failureLine(_ failure: TripAIJobs.Failure, title: String) -> String {
        switch failure {
        case .offline:
            return L("「\(title)」を作れませんでした。電波が届いていません", "Couldn't make “\(title)”. No signal")
        case .noCandidates:
            return L("「\(title)」を作れませんでした。行き先の観光スポットが見つかりません", "Couldn't make “\(title)”. No spots found there")
        case .save:
            return L("「\(title)」を保存できませんでした", "Couldn't save “\(title)”")
        }
    }
}
