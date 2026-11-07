import Foundation

/// 時間切れつきで答えを待つ(2026-11-07)。`work` が先に終われば、その答え。`timeout` 秒が先に来たら
/// `fallback` を返す(`work` は止めずに放っておく——取り消せない外部の問い合わせ(地名引き)があるため、
/// 構造化された並行(`withTaskGroup`)ではなく、先に来た方だけを通す一回きりの合図で返す)。
///
/// 使い所: すれちがいの受け取りの地名引き(`PassCoordinator.receive`)。背面で止められると、引き終わるのを待つ間に
/// 記録が落ちるので、数秒で諦めて地名なしで綴じる。
enum FirstResult {

    /// 一回だけ通す合図
    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
        func fire(_ value: T) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }

    @Sendable static func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    /// - Parameters:
    ///   - work: 答えを出す仕事(主スレッドの持ち物に触れるので `@MainActor`)
    ///   - pause: 待ち(試験が差し替える)
    static func run<T: Sendable>(timeout: TimeInterval, fallback: T,
                                 pause: @escaping @Sendable (TimeInterval) async -> Void = FirstResult.sleep,
                                 work: @escaping @MainActor () async -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let once = Once(continuation)
            Task { @MainActor in once.fire(await work()) }
            Task { await pause(timeout); once.fire(fallback) }
        }
    }
}
