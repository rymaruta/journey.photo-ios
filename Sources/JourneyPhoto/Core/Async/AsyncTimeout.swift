import Foundation

/// 上限時間つきで待つ（共通・2026-10-03 に `OfficialSpotIndex` から移した）。
///
/// 使っているところ: 経路の検索（`SpotDirections`）・投稿画面のライブラリの写真の読み込み
/// （`UploadViewModel.pickedLoadTimeout`）・ストーリーの写真の読み込み（`StorySimpleRules.readPicks`）・
/// 送る前の撮影スポットの索引の待ち（`PlaceCoordsRule.index`）
enum AsyncTimeout {

    /// `operation` の答えを `seconds` 秒だけ待つ。過ぎたら nil を返し、`operation` は止める。
    ///
    /// **`operation` が止まるのを待たない。** 子タスクの組（`withTaskGroup`）で競わせると、
    /// 抜けるときに全部の子の終わりを待つので、取り消しに応じない処理（地図の検索・iCloud の写真）
    /// では時間切れが効かない。呼んだ側が取り消されたときも、すぐ nil を返す。
    ///
    /// **先に答えが来たら、時間を計る側も止める**（止めないと、答えのあとも上限時間ぶん眠り続ける）
    static func firstWithin<T>(seconds: Double, _ operation: @escaping () async -> T?) async -> T? {
        await firstWithin(seconds: seconds, sleep: { try await Task.sleep(nanoseconds: $0) }, operation)
    }

    /// 眠り方を差し替えられる形（試験で、時間を計る側が止められたかを見る）。
    /// `betweenTimeoutSteps` は時間切れの「門を閉める」と「処理を止める」の間に呼ぶ（試験で順番を見るためだけ）
    static func firstWithin<T>(seconds: Double, sleep: @escaping @Sendable (UInt64) async throws -> Void,
                               betweenTimeoutSteps: (@Sendable () -> Void)? = nil,
                               _ operation: @escaping () async -> T?) async -> T? {
        let gate = FirstResultGate<T>()
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
                gate.start(continuation)
                let work = Task {
                    gate.finish(await operation())
                }
                gate.timer = Task {
                    // 止められた（答えが先に来た）なら何もしない
                    guard (try? await sleep(nanos)) != nil, !Task.isCancelled else { return }
                    // 🔴 **先に「時間切れ」で門を閉めてから止める**（2026-10-09）。逆の順だと、取り消しに
                    // すぐ応えて答えを返す処理（`try? await Task.sleep` のあとで値を返すもの）が、止めた
                    // 直後に別の糸で `finish(答え)` を先に通し、時間切れなのに答えが返ることがあった
                    // （手元の `swift test` を並べて流したときに `PlaceCoordsRuleTests` が時々落ちた）
                    gate.finish(nil)
                    betweenTimeoutSteps?()
                    work.cancel()
                }
                gate.onCancel = { work.cancel() }
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

/// `firstWithin` の「先に来た1回だけ返す」門
private final class FirstResultGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var done = false
    private var cancelled = false
    var onCancel: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onCancel }
        set {
            lock.lock()
            let fire = cancelled
            _onCancel = newValue
            lock.unlock()
            if fire { newValue?() }
        }
    }
    private var _onCancel: (() -> Void)?

    /// 時間を計る仕事。終わった後に渡されたら、すぐ止める
    var timer: Task<Void, Never>? {
        get { lock.lock(); defer { lock.unlock() }; return _timer }
        set {
            lock.lock()
            let stop = done
            _timer = newValue
            lock.unlock()
            if stop { newValue?.cancel() }
        }
    }
    private var _timer: Task<Void, Never>?

    func start(_ c: CheckedContinuation<T?, Never>) {
        lock.lock()
        if cancelled || done { done = true; lock.unlock(); c.resume(returning: nil); return }
        continuation = c
        lock.unlock()
    }

    func finish(_ value: T?) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let c = continuation
        continuation = nil
        let timer = _timer
        lock.unlock()
        timer?.cancel()
        c?.resume(returning: value)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let hook = _onCancel
        lock.unlock()
        // 先に nil で閉めてから止める（上の時間切れと同じ理由）
        finish(nil)
        hook?()
    }
}
