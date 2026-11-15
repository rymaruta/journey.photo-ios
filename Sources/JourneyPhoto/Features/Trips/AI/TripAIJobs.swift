import SwiftUI

/// AI で作っている旅行プラン（札 #621・owner 2026-11-15「作ってる間に待たせるの良くないな」）。
///
/// - 押したらすぐ日程の画面（`TripAIBuildingView`）を開き、1日目から順にできた日を埋める
/// - **画面を離れても作り続ける**（この入れ物はアプリが動いている間ずっとある）。できたら「旅行プラン」に保存し、
///   まだ見ていない印（真鍮の点）を付け、アプリの上の帯で「金沢の旅ができました」と知らせる。通知の許可は求めない
/// - 失敗・圏外・上限は、日程の画面の中と帯の両方で分かるようにする。やり直しは1回押すだけ（`retry`）
/// - **作り始めた人の作業だけを、その人のまま保存する**（保存の前に `isCurrent` で今の人か確かめる・`WishlistSync` と同じ）。
///   ログアウトと退会では `signOut` で全部止め、帯・開く先・控え（`TripAINotes`）を空にする
/// - 同じ頼みが動いていれば、新しく作らずその作業を開く（連打・戻ってもう一度押した回に二重に作らない）
/// - 「やめる」は保存に入る前まで。保存に入ってから止められた回は、作ったプランを消し、帯も点も出さない
@MainActor
final class TripAIJobs: ObservableObject {
    static let shared = TripAIJobs()

    enum Failure: Error, Equatable {
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

    /// 作る・保存する・消すの口（画面の外の仕組み。試験では差し替える）
    struct Backend {
        var build: @MainActor (TripAIRunner, TripAIAsk, _ offline: Bool) async -> TripAIResult?
        /// 保存する。作ったプランの ID か、失敗
        var save: @MainActor (_ title: String, _ days: [TripDay]) async -> Result<String, Failure>
        /// 作ったプランを消す（保存の途中で「やめる」が押された回）
        var remove: @MainActor (_ planId: String) async -> Void
        var offline: @MainActor () -> Bool
        /// 作り始めた人が、今もログインしている人か
        var isCurrent: @MainActor () -> Bool
    }

    @MainActor
    final class Job: ObservableObject, Identifiable {
        let id = UUID()
        let ask: TripAIAsk
        let owner: String
        @Published var state: State = .building
        /// 保存に入った（「やめる」を隠す）
        @Published var saving = false
        /// 「やめる」が押された
        fileprivate(set) var cancelled = false
        let runner: TripAIRunner
        var result: TripAIResult?
        fileprivate let backend: Backend
        init(ask: TripAIAsk, owner: String, runner: TripAIRunner, backend: Backend) {
            self.ask = ask
            self.owner = owner
            self.runner = runner
            self.backend = backend
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
    /// 帯を押した（アプリのいちばん上で日程の画面を開く）
    @Published var openPlanId: String?
    /// 今その job の画面を見ているか（見ている間は帯を出さない）
    @Published var watching: UUID?
    /// 今の人の、まだ見ていない AI のプラン（真鍮の点）。端末に人ごとに覚える
    @Published private(set) var unseen: Set<String> = []
    private(set) var currentUser: String?

    private let defaults: UserDefaults
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }


    /// 今の人（一覧を開いたとき・人が替わったとき）。点はその人の分だけ読む
    func use(userId: String?) {
        guard currentUser != userId else { return }
        currentUser = userId
        unseen = userId.map { Set(defaults.stringArray(forKey: TripAIUnseen.key($0)) ?? []) } ?? []
    }

    /// ログアウト・退会（`AuthStore.settleSignedOut`）。作業を全部止め、帯・開く先・控えを空にする
    func signOut() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        for job in jobs { job.cancelled = true }
        jobs = []
        banner = nil
        openPlanId = nil
        watching = nil
        currentUser = nil
        unseen = []
        TripAINotes.shared.removeAll()
    }

    func job(_ id: UUID) -> Job? { jobs.first { $0.id == id } }

    /// 作り始める。すぐ返す（呼び手は日程の画面を開く）。同じ人の同じ頼みが動いていれば、その作業を返す
    @discardableResult
    func start(_ ask: TripAIAsk, owner: String, usage: TripAIService.Usage?, backend: Backend,
               runner given: TripAIRunner? = nil) -> Job {
        if let same = jobs.first(where: { $0.owner == owner && $0.ask == ask && !$0.cancelled }) {
            if case .failed = same.state { retry(same) }
            return same
        }
        let runner = given ?? TripAIRunner()
        runner.setUsage(usage)
        let job = Job(ask: ask, owner: owner, runner: runner, backend: backend)
        jobs.append(job)
        launch(job)
        return job
    }

    /// やり直し（1回押すだけ）
    func retry(_ job: Job) {
        if banner?.jobId == job.id { banner = nil }
        job.state = .building
        job.cancelled = false
        if !jobs.contains(where: { $0.id == job.id }) { jobs.append(job) }
        launch(job)
    }

    /// やめる（日程は作らない）。保存に入っていたら、保存できたあとに消す
    func cancel(_ job: Job) {
        job.cancelled = true
        if !job.saving {
            tasks[job.id]?.cancel()
            tasks[job.id] = nil
        }
        jobs.removeAll { $0.id == job.id }
        if banner?.jobId == job.id { banner = nil }
    }

    func markSeen(_ planId: String) {
        guard unseen.contains(planId), let user = currentUser else { return }
        unseen.remove(planId)
        defaults.set(Array(unseen), forKey: TripAIUnseen.key(user))
    }

    private func markUnseen(_ planId: String, owner: String) {
        var set = Set(defaults.stringArray(forKey: TripAIUnseen.key(owner)) ?? [])
        set.insert(planId)
        defaults.set(Array(set), forKey: TripAIUnseen.key(owner))
        if owner == currentUser { unseen = set }
    }

    /// 走っている作業が終わるまで待つ（試験から）
    func settled(_ job: Job) async {
        await tasks[job.id]?.value
    }

    private func launch(_ job: Job) {
        tasks[job.id]?.cancel()
        tasks[job.id] = Task { @MainActor [weak self] in
            await self?.run(job)
        }
    }

    /// 作る → 保存する → 知らせる（試験から待てるよう、呼び手に返す）
    func run(_ job: Job) async {
        let backend = job.backend
        // 見本（UI テスト・Debug のみ）の `offline` は圏外として扱う（圏外の画面を撮るため）
        let offline = backend.offline() || TripAIFixture.mode == "offline"
        // 電波が無く端末の AI も使えないときは、日程を保存できないので作らない（行き止まりにせず、やり直しを1回で）
        if offline && !job.runner.onDevice { return fail(job, .offline) }
        guard let result = await backend.build(job.runner, job.ask, offline) else {
            if Task.isCancelled || job.cancelled { return }
            return fail(job, .noCandidates)
        }
        guard !Task.isCancelled, !job.cancelled, backend.isCurrent() else { return }
        job.result = result
        job.saving = true
        let title = TripPlanService.titleToSend(result.title)
        let days = TripDraft.tripDays(result.days.map { $0.map(TripDraft.place(spot:)) })
        let saved = await backend.save(title, days)
        job.saving = false
        switch saved {
        case .failure(let failure):
            guard !job.cancelled, backend.isCurrent() else { return }
            return fail(job, failure)
        case .success(let planId):
            // 🔴 保存の間に「やめる」が押された・人が替わった: 作ったプランを消し、帯も点も出さない
            guard !job.cancelled, backend.isCurrent() else {
                await backend.remove(planId)
                return
            }
            TripAINotes.shared.set(planId, TripAINote(reason: result.reason, mode: result.mode,
                                                      removed: result.removed, candidates: result.candidates))
            job.state = .saved(planId: planId)
            TripPlanChanges.shared.changed(planId)
            // 終わった作業は片づける（日程の画面は job を持っているので消えない）
            jobs.removeAll { $0.id == job.id }
            tasks[job.id] = nil
            if watching != job.id {
                markUnseen(planId, owner: job.owner)
                let text = result.mode == .ai
                    ? L("「\(result.title)」ができました", "“\(result.title)” is ready")
                    : L("「\(result.title)」ができました（AI なし）", "“\(result.title)” is ready (without AI)")
                banner = Banner(text: text, action: L("開く", "Open"), jobId: job.id, planId: planId, failed: false)
            }
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

extension TripAIJobs.Backend {
    /// アプリの口（サーバーの AI・旅行プランの口）。`owner` は作り始めた人
    @MainActor
    static func live(environment: AppEnvironment, auth: AuthStore, owner: String, index: [OfficialSpot],
                     wishlist: Set<String>, connectivity: Connectivity) -> TripAIJobs.Backend {
        TripAIJobs.Backend(
            build: { runner, ask, offline in
                await runner.build(ask, index: index, wishlist: wishlist, offline: offline, service: environment.tripAI)
            },
            save: { title, days in
                // 作る前の一覧を取り、増えた中から選ぶ（同じ題の別のプランと取り違えない）
                let before: Set<String>
                do {
                    before = Set(try await environment.trips.list().map(\.planId))
                } catch {
                    return .failure(connectivity.isOffline ? .offline
                                    : .save((error as? LocalizedError)?.errorDescription ?? L("旅行プランを保存できませんでした", "Couldn't save the trip")))
                }
                do {
                    let list = try await environment.trips.create(title: title, days: days, startDate: nil, endDate: nil)
                    guard let made = TripPlansModel.created(in: list.plans, before: before, title: title) else {
                        return .failure(.save(L("旅行プランを保存できませんでした", "Couldn't save the trip")))
                    }
                    return .success(made.planId)
                } catch {
                    return .failure(connectivity.isOffline ? .offline
                                    : .save((error as? LocalizedError)?.errorDescription ?? L("旅行プランを保存できませんでした", "Couldn't save the trip")))
                }
            },
            remove: { planId in _ = try? await environment.trips.delete(planId: planId) },
            offline: { connectivity.isOffline },
            isCurrent: { auth.userId == owner }
        )
    }
}

/// まだ見ていない印の端末の控え（人ごと）。退会で消す（`AccountLocalData`）
enum TripAIUnseen {
    static func key(_ userId: String) -> String { "tripAI.unseen.\(userId)" }

    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userId))
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
