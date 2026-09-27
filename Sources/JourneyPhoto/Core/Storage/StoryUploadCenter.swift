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
    private var onFailed: ((String) -> Void)?
    /// 🔴 **誰の投稿か。** 係はアプリに1つなので、ログインし直した別の人の
    /// トークンで前の人の写真を出してしまわないよう、送る前に毎回照らす
    private var ownerId: String?
    private var currentUserId: (() -> String?)?
    /// 🔴 **捨てた並びの送信を続けさせない番号。** 送信の返事を待つ間に捨てる
    /// （ログアウト・やめる）と、戻ってきた `run` が空の並びから取り出して落ちる
    private var generation = 0

    /// 送っている最中か、失敗した残りを持っているか（新しい投稿を受けない）
    var isBusy: Bool { phase != .idle }

    /// 送り始める。**前の投稿が片付いていなければ受けない**（false）——
    /// 2つの並びが混ざると、どれが出たのか分からなくなる
    @discardableResult
    func start(_ jobs: [Job],
               ownerId: String,
               currentUserId: @escaping () -> String?,
               send: @escaping (Job) async throws -> Void,
               onAllSent: @escaping () -> Void = {},
               onFailed: @escaping (String) -> Void = { _ in }) -> Bool {
        guard !isBusy, !jobs.isEmpty, !ownerId.isEmpty else { return false }
        pending = jobs
        total = jobs.count
        self.ownerId = ownerId
        self.currentUserId = currentUserId
        self.send = send
        self.onAllSent = onAllSent
        self.onFailed = onFailed
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

    /// ログインしている人が変わった（ログアウト・別の人でログイン・退会）。
    /// **投稿した本人でなくなったら、送っている最中でも残りを捨てる**
    func userChanged(to userId: String?) {
        guard isBusy, userId != ownerId else { return }
        reset()
    }

    private func run() async {
        guard let send else { return }
        let myGeneration = generation
        phase = .sending(done: total - pending.count, total: total)
        while let job = pending.first {
            // **本人のままか、送る前に毎回照らす**（別の人のトークンで出さない）
            guard currentUserId?() == ownerId else {
                reset()
                return
            }
            do {
                try await send(job)
                // 待っている間に捨てられた並びなら、ここで手を引く
                guard myGeneration == generation else { return }
                pending.removeFirst()
                phase = .sending(done: total - pending.count, total: total)
            } catch {
                guard myGeneration == generation else { return }
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? L("投稿できませんでした", "Couldn't post")
                let message = StoryQueue.partialFailure(posted: total - pending.count,
                                                        total: total, reason: reason)
                phase = .failed(message: message, remaining: pending.count)
                // **失敗は知らせる。** ホームの輪が見えない画面にいる人にも届くように
                onFailed?(message)
                return
            }
        }
        onAllSent?()
        reset()
        finished += 1
    }

    private func reset() {
        generation += 1
        pending = []
        total = 0
        send = nil
        onAllSent = nil
        onFailed = nil
        ownerId = nil
        currentUserId = nil
        phase = .idle
    }
}
