import SwiftUI
import UIKit

/// ホームの上の札から旅行プランを消す・抜ける（2026-11-12）。**聞かずにすぐ札から消し、「元に戻す」を6秒出して、
/// 6秒たってからサーバーへ送る**（今のアプリに削除の取り消しの口は無いので、端末の中で送るのを遅らせる）。
///
/// 2026-11-12 判断（送るまでの間に起きること）:
/// - **押した時点で端末に書き残す**（人ごと）。6秒の間にアプリを閉じられても、次に開いたとき送る
///   （押して「元に戻す」を押さなかった＝消すと決めた、と読む）
/// - アプリが裏に回ったら、6秒を待たずにその場で送る（裏で少しだけ続けさせてもらう・`beginBackgroundTask`）
/// - **圏外・届かなかった**（`APIError.unreachable`・`URLError`）ときは札から消したまま書き残し、
///   前面に戻った・電波が戻った・ホームに戻ったときに送り直す（`resume`）
/// - すでに無い（404）は消し終えたと読む（別の端末で消した）
/// - それ以外で断られたら、札を戻して「削除できませんでした」を出す（`Bar.failed`・4秒）
/// - 人が替わったら、前の人の分は送らない（書き残しは前の人のまま。その人が戻ったら送る）
///
/// 「この旅をホームに出さない」の「元に戻す」も同じ帯に出す（`Bar.hidden`）
@MainActor
final class TripPlanRemovalQueue: ObservableObject {

    static let shared = TripPlanRemovalQueue()

    /// 送る1件（書き残す形）
    struct Job: Codable, Equatable {
        let planId: String
        let title: String
        /// `HomeTripCardMenu.Item` の rawValue（削除・仲間全員から削除・抜ける）
        let item: String
        let userId: String

        var menuItem: HomeTripCardMenu.Item { HomeTripCardMenu.Item(rawValue: item) ?? .delete }
    }

    /// 画面の下の帯
    enum Bar: Equatable {
        /// 消した（送るのを待っている）。「元に戻す」で取り消す
        case removed(Job)
        /// ホームに出さないにした。「元に戻す」で印を外す
        case hidden(planId: String, title: String, userId: String)
        /// 消せなかった（札は戻した）
        case failed(String)

        var text: String {
            switch self {
            case .removed(let job): return HomeTripCardMenu.doneText(job.menuItem, planTitle: job.title)
            case .hidden(_, let title, _): return HomeTripCardMenu.doneText(.hideFromHome, planTitle: title)
            case .failed(let text): return text
            }
        }
    }

    /// 送るのを今は見送った（人が替わった）。書き残しはそのまま
    struct NotNow: Error {}

    /// サーバーへ送る口（`TripPlanService.delete`）。呼び手が今の人を確かめ、違えば `NotNow` を投げる
    typealias Send = (Job) async throws -> Void

    @Published private(set) var bar: Bar?
    /// 札と一覧から落とすプラン（元に戻すを待っている・圏外で送るのを待っている・この起動中に消し終えた）
    @Published private(set) var removedIds: Set<String> = []
    /// 今の人の「ホームに出さない」の印（`HomeHiddenTrips`）。読み直すのはホームに戻ったとき・人が替わったとき・
    /// 出さない／元に戻すを押したときだけ（札の `body` で毎回端末を読まない）
    @Published private(set) var hiddenTrips: [HomeHiddenTrips.Entry] = []

    /// 「元に戻す」を待つ秒数（owner の指示 6 秒。板の知らせは 4 秒だが、押す間を残す）
    nonisolated static let undoSeconds: Double = 6
    /// 消せなかった知らせを出す秒数（板の知らせと同じ 4 秒）
    nonisolated static let failedSeconds: Double = 4

    private let defaults: UserDefaults
    private let hiddenStore: HomeHiddenTrips
    private let seconds: Double
    private let failedSeconds: Double
    private var pending: Job?
    private var timer: Task<Void, Never>?
    private var barTimer: Task<Void, Never>?
    private var send: Send?
    /// 送っている最中の planId（二重に送らない）
    private var sending: Set<String> = []

    init(defaults: UserDefaults = .standard, seconds: Double = TripPlanRemovalQueue.undoSeconds,
         failedSeconds: Double = TripPlanRemovalQueue.failedSeconds) {
        self.defaults = defaults
        self.hiddenStore = HomeHiddenTrips(defaults: defaults)
        self.seconds = seconds
        self.failedSeconds = failedSeconds
    }

    // MARK: - 書き残し（人ごと）

    private nonisolated static let key = "journey-photo-trip-plan-removals"
    private nonisolated static func key(for userId: String) -> String { "\(key):\(userId)" }

    func waiting(for userId: String?) -> [Job] {
        guard let userId, !userId.isEmpty,
              let data = defaults.data(forKey: Self.key(for: userId)),
              let list = try? JSONDecoder().decode([Job].self, from: data) else { return [] }
        return list
    }

    private func write(_ list: [Job], for userId: String) {
        if list.isEmpty {
            defaults.removeObject(forKey: Self.key(for: userId))
        } else if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Self.key(for: userId))
        }
    }

    private func store(_ job: Job) {
        write(waiting(for: job.userId).filter { $0.planId != job.planId } + [job], for: job.userId)
    }

    private func drop(_ job: Job) {
        write(waiting(for: job.userId).filter { $0.planId != job.planId }, for: job.userId)
    }

    /// 退会した人の書き残しを消す（`AccountLocalData`）
    nonisolated static func removeData(for userId: String, defaults: UserDefaults) {
        defaults.removeObject(forKey: key(for: userId))
    }

    // MARK: - 操作

    /// 消す・抜ける。札からすぐ落とし、6秒「元に戻す」を出してから送る。前の1件の「元に戻す」は積まずに送る
    func remove(planId: String, title: String, item: HomeTripCardMenu.Item, userId: String, send: @escaping Send) {
        guard !userId.isEmpty, item != .hideFromHome else { return }
        self.send = send
        commitNow()
        let job = Job(planId: planId, title: title, item: item.rawValue, userId: userId)
        store(job)
        removedIds.insert(planId)
        pending = job
        showBar(.removed(job), for: nil)
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self, self.pending == job else { return }
            self.pending = nil
            self.timer = nil
            if case .removed(let shown)? = self.bar, shown == job { self.clearBar() }
            await self.commit(job)
        }
    }

    /// この旅をホームに出さない（端末に印を付け、6秒「元に戻す」を出す）。旅行プランは消さない
    func hide(_ plan: TripPlan, title: String, userId: String) {
        guard !userId.isEmpty else { return }
        commitNow()
        hiddenStore.hide(plan, for: userId)
        hiddenTrips = hiddenStore.entries(for: userId)
        showBar(.hidden(planId: plan.planId, title: title, userId: userId), for: seconds)
    }

    /// 「ホームに出さない」の印を読み直す（ホームに戻った・人が替わった）。終わった旅の印はここで消す
    func loadHidden(userId: String?, today: String) {
        hiddenStore.prune(today: today, for: userId)
        let next = hiddenStore.entries(for: userId)
        if next != hiddenTrips { hiddenTrips = next }
    }

    /// 「元に戻す」。消したなら送らずに札を戻す。出さないにしたなら印を外す
    func undo() {
        switch bar {
        case .removed(let job)?:
            guard pending == job else { return }
            timer?.cancel()
            timer = nil
            pending = nil
            drop(job)
            removedIds.remove(job.planId)
        case .hidden(let planId, _, let userId)?:
            hiddenStore.unhide(planId: planId, for: userId)
            hiddenTrips = hiddenStore.entries(for: userId)
        default:
            break
        }
        clearBar()
    }

    /// 人が替わった。待っている1件は送らず書き残しのまま（前の人が戻ったら `resume` が送る）。帯と札の印は次の人に残さない
    func userChanged() {
        timer?.cancel()
        timer = nil
        pending = nil
        clearBar()
        removedIds = []
        hiddenTrips = []
    }

    /// 待っている1件をいま送る（次を押した・アプリが裏に回った）
    func commitNow() {
        guard let job = pending else { return }
        timer?.cancel()
        timer = nil
        pending = nil
        if case .removed(let shown)? = bar, shown == job { clearBar() }
        let window = RemovalBackgroundWindow()
        Task { [weak self] in
            await self?.commit(job)
            window.end()
        }
    }

    /// 書き残した分（圏外で送れなかった・6秒の間にアプリを閉じた）を送り直す。前面に戻った・電波が戻った・
    /// ホームに戻ったときに呼ぶ。札から落とす印も書き残しから戻す
    func resume(userId: String?, send: @escaping Send) {
        guard let userId, !userId.isEmpty else { return }
        self.send = send
        for job in waiting(for: userId) where job != pending {
            removedIds.insert(job.planId)
            Task { [weak self] in await self?.commit(job) }
        }
    }

    /// 送る。結果で書き残しと札を整える
    private func commit(_ job: Job) async {
        guard let send, !sending.contains(job.planId) else { return }
        sending.insert(job.planId)
        defer { sending.remove(job.planId) }
        do {
            try await send(job)
            drop(job)
        } catch {
            switch Self.outcome(of: error) {
            case .done:
                drop(job)
            case .later:
                // 札から落としたまま書き残しておく（次の `resume` で送る）
                break
            case .failed:
                drop(job)
                removedIds.remove(job.planId)
                showBar(.failed(HomeTripCardMenu.failedText(job.menuItem, planTitle: job.title)), for: failedSeconds)
            }
        }
    }

    enum Outcome: Equatable { case done, later, failed }

    /// 送れなかった理由の読み分け（試験で確かめる）
    nonisolated static func outcome(of error: Error) -> Outcome {
        if error is NotNow || error is URLError || error is CancellationError { return .later }
        if let api = error as? APIError {
            switch api {
            case .unreachable: return .later
            case .server(let status, _) where status == 404: return .done
            default: return .failed
            }
        }
        return .failed
    }

    // MARK: - 帯

    private func showBar(_ next: Bar, for seconds: Double?) {
        barTimer?.cancel()
        barTimer = nil
        bar = next
        guard let seconds else { return }
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        barTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self, self.bar == next else { return }
            self.bar = nil
        }
    }

    private func clearBar() {
        barTimer?.cancel()
        barTimer = nil
        bar = nil
    }
}

/// 裏に回っても送り終えるまで少しだけ続けさせてもらう窓（`beginBackgroundTask`）。**時間切れでも必ず終える**
/// （終えないとアプリが止められる。日程の画面の `TripBackgroundWindow` と同じ形——あちらは画面の中に閉じているので写した）
@MainActor
private final class RemovalBackgroundWindow {
    private var id = UIBackgroundTaskIdentifier.invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "trip-plan-removal") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// 旅行プランを消した・ホームに出さないにした知らせと「元に戻す」（ホームの下）。見た目は下書きの「元に戻す」と同じ札
/// （`JPUndoBar`）。消せなかったときは危険の色の字で知らせる
struct TripRemovalBar: View {
    @ObservedObject var queue: TripPlanRemovalQueue

    var body: some View {
        if let bar = queue.bar {
            switch bar {
            case .failed(let text):
                JPUndoBar(text: text, failed: true, identifier: "home.tripMenu.failed")
            default:
                JPUndoBar(text: bar.text, undoTitle: HomeTripCardMenu.undo, identifier: "home.tripMenu.undo") {
                    queue.undo()
                }
            }
        }
    }
}
