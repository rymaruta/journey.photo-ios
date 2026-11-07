import Foundation

/// 同時に飛ばす要求の数を絞る順番待ち（2026-11-07 判断・札: 本番 Lambda の同時実行上限）。
///
/// **なぜ要るか**: 本番の Lambda は同時実行の上限が 10 しかなく、アプリは起動直後に
/// 画面ごとの読み込み（ホーム・未読通知・プロフィール・旅行プラン・同期）を一斉に出す。
/// 上限を超えた分はスロットル（API は 503）になり、画面が「通信できません」を出していた。
/// 先頭から `limit` 本だけ通し、残りは届いた順に待たせる（先に着いた要求から出る）。
///
/// 取り消された待ちは列から外して `CancellationError` を投げる（画面を離れた要求が
/// 枠を握ったまま残らない）。
actor RequestLimiter {

    /// 既定の同時数。**4**: 本番の上限 10 のうち、アプリ1台が使ってよい分を半分未満に抑える
    /// （同じ API をほかの端末・Web・バッチも使う）。1画面の読み込みは普通 2〜3 本なので、
    /// 通常の画面は待たされない。起動の山（8〜14 本）だけが 4 本ずつに均される
    static let defaultLimit = 4

    /// **アプリ全体で1つの絞り**(2026-11-07)。本番の配線(`AppEnvironment.api`・`APIClient.app()`)だけがこれを使う。
    /// 絞りが `APIClient` ごとにあると、`APIClient.app()` が画面ごとに作る実体(マイページ・投稿・写真詳細・通知)が
    /// それぞれ4本ずつ出せてしまい、アプリ全体の同時数を守れない。
    /// 試験が直に作る `APIClient` は、互いに詰まらないよう独立の絞りのまま
    static let shared = RequestLimiter()

    private let limit: Int
    private var running = 0
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Void, Error>)] = []
    private var nextID: UInt64 = 0

    init(limit: Int = RequestLimiter.defaultLimit) {
        self.limit = max(1, limit)
    }

    /// いま走っている本数（試験用）
    var inFlight: Int { running }
    /// 待っている本数（試験用）
    var queued: Int { waiters.count }

    /// 枠が空くまで待つ。**呼んだら必ず `release()` を対で呼ぶ**（`run` を使えば自動）
    func acquire() async throws {
        try Task.checkCancellation()
        if running < limit {
            running += 1
            return
        }
        nextID += 1
        let id = nextID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // 取り消しの合図が先に来ていたら、列に入れずに戻す
                // （`onCancel` は `Task.isCancelled` が立ってから呼ばれるので、ここで見れば取りこぼさない）
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            running = max(0, running - 1)
        } else {
            // 枠を待っている先頭へそのまま渡す（`running` は変えない）
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancel(id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// 枠を取って `body` を走らせ、終わったら（失敗・取り消しでも）返す
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await body()
    }
}
