import Foundation
import Combine

/// **ストーリーを裏で送る係**（板 27「投稿した直後——上がるまで自分の輪が進み具合を示す」）。
///
/// 以前は投稿画面の中で送り終えるまで待ち、その間は画面を閉じられなかった
/// （`interactiveDismissDisabled`）。いまは「ストーリーに投稿」で画面を閉じ、
/// ここが順に送る。ホームの自分の輪は `phase` を見て進み具合と「送信中…」を出す。
///
/// 🔴 **途中で失敗したら、そこで止める**（投稿画面にあった決まりをそのまま移した）。
/// 残りを出し続けると「何本出たのか」が誰にも分からなくなる。出たぶんは残し、
/// **送れなかった残りは捨てずに持つ**——輪から「もう一度送る」か「やめる」を選ぶ。
@MainActor
final class StoryUploadCenter: ObservableObject {

    static let shared = StoryUploadCenter()

    /// 1本ぶん。**焼き込み済みの画像**を持つ（文字の配置は投稿画面の中の話）
    struct Job: Identifiable {
        let id = UUID()
        let imageData: Data
        let caption: String
        let location: String
        let coords: Photo.Coords?
        let song: Photo.Song?
        let durationSec: Int
        let archive: Bool
    }

    enum Phase: Equatable {
        case idle
        /// `done` 本出して、全部で `total` 本
        case sending(done: Int, total: Int)
        /// 止まった。`remaining` 本が手元に残っている
        case failed(message: String, remaining: Int)
    }

    @Published private(set) var phase: Phase = .idle
    /// **全部送り終えた回数。** 輪はこれを見て一覧を読み直す
    /// （回数で伝えるのは `TabRouter` と同じ理由——真偽値だと2回目が効かない）
    @Published private(set) var finished = 0

    private var pending: [Job] = []
    private var total = 0
    private var send: ((Job) async throws -> Void)?
    private var onAllSent: (() -> Void)?

    /// 送っている最中か、失敗した残りを持っているか（新しい投稿を受けない）
    var isBusy: Bool { phase != .idle }

    /// 送り始める。**前の投稿が片付いていなければ受けない**（false）——
    /// 2つの並びが混ざると、どれが出たのか分からなくなる
    @discardableResult
    func start(_ jobs: [Job],
               send: @escaping (Job) async throws -> Void,
               onAllSent: @escaping () -> Void = {}) -> Bool {
        guard !isBusy, !jobs.isEmpty else { return false }
        pending = jobs
        total = jobs.count
        self.send = send
        self.onAllSent = onAllSent
        // 🔴 **その場で「送信中」にする。** 裏の `Task` が動き出すまで `.idle` のままだと、
        // その隙の二度押しをもう1本として受けてしまう（テストで捕まえた）。
        // 輪もこの瞬間から「送信中…」を出せる
        phase = .sending(done: 0, total: total)
        Task { await run() }
        return true
    }

    /// 失敗した残りをもう一度送る
    func retry() {
        guard case .failed = phase, !pending.isEmpty else { return }
        phase = .sending(done: total - pending.count, total: total)
        Task { await run() }
    }

    /// 失敗した残りを捨てる（出せたぶんはそのまま）
    func discard() {
        guard case .failed = phase else { return }
        reset()
    }

    private func run() async {
        guard let send else { return }
        phase = .sending(done: total - pending.count, total: total)
        while let job = pending.first {
            do {
                try await send(job)
                pending.removeFirst()
                phase = .sending(done: total - pending.count, total: total)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? L("投稿できませんでした", "Couldn't post")
                phase = .failed(message: StoryQueue.partialFailure(posted: total - pending.count,
                                                                   total: total, reason: reason),
                                remaining: pending.count)
                return
            }
        }
        onAllSent?()
        reset()
        finished += 1
    }

    private func reset() {
        pending = []
        total = 0
        send = nil
        onAllSent = nil
        phase = .idle
    }
}
