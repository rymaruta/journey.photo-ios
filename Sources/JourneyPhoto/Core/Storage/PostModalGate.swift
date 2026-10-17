import Foundation

/// 投稿のあとに続けて出るもの（通知の説明・評価のお願い・旅のトランクの届いた画面）の順番（2026-10-17 の読み直し）。
///
/// **通知の説明 → 評価のお願い → 届いた画面** の順に決める:
/// - 評価のお願いは、通知の説明が決め終わり、ほかの画面が出ていないときに頼む。
///   **届いた画面が出ている・出すものが残っている間は頼まない**（全画面の上に評価の窓が重なる）
/// - 届いた画面は、通知の説明が決め終わり（出していれば閉じてから）、評価のお願いが決め終わってから出す
///
/// `RootView` は `wait` で待ち、決め方はここの関数だけを使う（待ち方を画面に書き散らさない）
struct PostModalSnapshot: Equatable {
    var modalPresenting = false
    var pushPrimerDeciding = false
    var pushPrimerShowing = false
    var reviewDeciding = false
    var trunkPending = false
    var trunkShowing = false
}

enum PostModalGate {

    /// 評価のお願いの待ちが終わったか（通知の説明が決め終わり、ほかの画面が出ていない）
    static func reviewWaitIsOver(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.pushPrimerDeciding
    }

    /// 評価のお願いを頼んでよいか
    static func reviewMayAsk(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.pushPrimerShowing && !s.pushPrimerDeciding && !s.trunkPending && !s.trunkShowing
    }

    /// 届いた画面を出してよいか
    static func trunkMayShow(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.pushPrimerDeciding && !s.pushPrimerShowing && !s.reviewDeciding && !s.trunkShowing
    }

    /// `ready` になるまで最大 `tries` 回待つ。なったら true（`sleep` はテストで差し替える）
    static func wait(tries: Int, snapshot: () -> PostModalSnapshot, until ready: (PostModalSnapshot) -> Bool,
                     sleep: () async -> Void) async -> Bool {
        for _ in 0..<max(1, tries) {
            await sleep()
            if Task.isCancelled { return false }
            if ready(snapshot()) { return true }
        }
        return ready(snapshot())
    }
}
