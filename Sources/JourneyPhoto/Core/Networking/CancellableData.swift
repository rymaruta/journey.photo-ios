import Foundation

// Linux では URLSession が別モジュールに居る（`PublicGalleryService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession {
    /// `data(for:)` と同じ。**取り消されても固まらない**（Linux の試験のため）。
    ///
    /// 🔴 **Linux の swift-corelibs-foundation の `data(for:)` は、取り消しと応答が重なると
    /// 固まる**（2026-10-03・全試験を流すと3回に1回ほど止まった。gdb で両方のスレッドを見た）:
    ///
    /// - 取り消す側: `async let` を抜ける（`swift_asyncLet_finish`）→ `swift_task_cancel` が
    ///   **その仕事の状態の鍵を握ったまま**取り消しの手当て（`onCancel`）を呼ぶ →
    ///   `URLSessionTask.cancel()` が URLSession の作業列に `sync` で入るのを待つ
    /// - 応答する側: その作業列の上で応答を届け終え（`_callCompletionHandlerInline` で
    ///   作業列の上で直に呼ぶ）、待っている仕事を起こす（`continuation.resume`）→
    ///   起こすには同じ仕事の状態の鍵が要る
    ///
    /// 互いに相手を待つので、どちらも進まない。`URLSessionTask.cancel()` を呼ぶと、
    /// 応答と取り消しが両方とも仕事を台帳から外そうとして `TaskRegistry.swift:118` の
    /// Fatal error で落ちる回もある（`RequestCancellation` の注記の落ち方と同じ根）。
    ///
    /// だから Linux では URLSession の async の口を使わず、`dataTask` の完了の手当てで
    /// 受ける。**取り消されたら、URLSession の task には触らず、待っている側だけを
    /// `URLError(.cancelled)` で先に起こす**（`cancel()` を呼ばない＝作業列を待たない・
    /// 台帳を二重に外さない）。task は自分で終わり、その答えは捨てる。呼び手から見た
    /// 振る舞い（取り消しは `URLError(.cancelled)`）は `data(for:)` と同じ。
    ///
    /// **iOS（Darwin）はそのまま `data(for:)`。** 固まる2つの部品——`cancel()` が作業列に
    /// `sync` で入ること・完了を作業列の上で直に呼ぶこと・`TaskRegistry`——は
    /// swift-corelibs-foundation の実装で、Darwin の URLSession（CFNetwork）には無い
    /// （Apple の文書では `cancel()` は「すぐ戻る」）。実機で固まらないことを実機では
    /// 確かめていない。Linux で動くのは試験だけ（アプリは iOS だけ）
    func cancellableData(for request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        let waiter = CancellableWaiter<(Data, URLResponse)>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard waiter.install(continuation) else { return }
                let task = dataTask(with: request) { data, response, error in
                    if let error {
                        waiter.finish(.failure(error))
                    } else if let data, let response {
                        waiter.finish(.success((data, response)))
                    } else {
                        waiter.finish(.failure(URLError(.badServerResponse)))
                    }
                }
                task.resume()
            }
        } onCancel: {
            // 手当ては仕事の状態の鍵を握ったまま呼ばれる。その場で待ち手を起こさず、
            // 鍵の外で起こす（鍵を握ったまま何かを待つ形を作らない）
            DispatchQueue.global().async { waiter.finish(.failure(URLError(.cancelled))) }
        }
        #else
        return try await data(for: request)
        #endif
    }
}

extension Task where Failure == Error {
    /// 共有している仕事の答えを待つ。**待っている側が取り消されたら、待ちだけを外す**
    /// （`CancellationError` で起こす）。仕事そのものは取り消さない——同じ仕事を
    /// 待っているほかの呼び手の答えまで止めないため（`PublicGalleryService.fetchStaticList`）。
    ///
    /// ふつうの `await task.value` は、待っている側が取り消されても仕事が終わるまで
    /// 戻らない（取り消しは仕事へ伝わらない）。起こし方は `cancellableData` と同じ
    /// ——手当ての中では起こさず、鍵の外で起こす
    func valueReleasingOnCancel() async throws -> Success {
        let waiter = CancellableWaiter<Success>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard waiter.install(continuation) else { return }
                Task<Void, Never> {
                    do {
                        waiter.finish(.success(try await self.value))
                    } catch {
                        waiter.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            DispatchQueue.global().async { waiter.finish(.failure(waitCancelled())) }
        }
    }
}

/// `Task` の中では `CancellationError()` が古い `Task.CancellationError()` の方に
/// 解決されて書けないので、外で作る
private func waitCancelled() -> Error { CancellationError() }

/// 待っている側を**1回だけ**起こす（答えと取り消しの先に来た方）。
/// 取り消しが `install` より先に来たら、入れた途端に取り消しで起こす
final class CancellableWaiter<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var early: Result<Value, Error>?
    private var done = false

    /// 入れたら true。もう終わっていた（先に取り消された）ら、その場で起こして false
    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let early {
            self.early = nil
            lock.unlock()
            continuation.resume(with: early)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        guard let continuation else {
            early = result
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
