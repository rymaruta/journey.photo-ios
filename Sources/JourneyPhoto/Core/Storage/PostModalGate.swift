import Foundation

/// 投稿のあとに続けて出るもの（通知の説明・評価のお願い・旅のトランクの届いた画面）と、
/// 起動のときの「はじめての硬貨」の案内（2026-10-18）の順番（2026-10-17 の読み直し）。
///
/// **通知の説明 → 評価のお願い → 届いた画面** の順に決める:
/// - 評価のお願いは、通知の説明が決め終わり、ほかの画面が出ていないときに頼む。
///   **届いた画面が出ている・出すものが残っている間は頼まない**（全画面の上に評価の窓が重なる）
/// - 届いた画面は、通知の説明が決め終わり（出していれば閉じてから）、評価のお願いが決め終わってから出す
///
/// はじめての硬貨の案内（`TrunkWelcome`）は**いちばん後ろ**:
/// - アプリが前面に出ていて（裏にいる間に出すと、戻ったときには閉じる手前の画面が見えないまま残る）、
///   起動のときの案内（新しくなったこと → 初期ユーザー章の贈り物）が決め終わり、通知の説明・評価のお願い・
///   届いた画面のどれも出ていない・決めている最中でない・届いた画面に出すものが残っていないときに出す
/// - 案内が出ている間は、評価のお願いを頼まず、届いた画面も出さない（閉じてから出す）
///
/// #304（2026-10-18）の「この1枚をカバーに」とアイコン・カバーのお礼（板の付箋の順）:
/// - **初めての投稿の差し出しは通知の説明より前**。決めている・出している間（`coverOfferBusy`）は、通知の説明・評価・
///   届いた画面・はじめての硬貨を待たせる
/// - **お礼といいねの差し出しは最後**: はじめての硬貨の案内（出ている・残っている）のあと。お礼 → いいねの差し出しの順
///
/// `RootView` は `wait` で待ち、決め方はここの関数だけを使う（待ち方を画面に書き散らさない）
struct PostModalSnapshot: Equatable {
    var modalPresenting = false
    var pushPrimerDeciding = false
    var pushPrimerShowing = false
    var reviewDeciding = false
    var trunkPending = false
    var trunkShowing = false
    /// 起動のときの案内（新しくなったこと・初期ユーザー章）を決めている・出している
    var launchNoticesDeciding = false
    /// はじめての硬貨の案内を出している（出そうとしている間も含む）
    var welcomeShowing = false
    /// アプリが前面に出ている（`scenePhase == .active`）。裏にいる間は案内を出さない
    var sceneActive = true
    /// 初めての投稿の「この1枚をカバーに」を決めている・出している（出す待ちも含む）
    var coverOfferBusy = false
    /// はじめての硬貨の案内が出す待ちに残っている
    var welcomePending = false
    /// お礼かいいねの差し出しを出している
    var extrasShowing = false
}

enum PostModalGate {

    /// 評価のお願いの待ちが終わったか（通知の説明が決め終わり、ほかの画面が出ていない）
    static func reviewWaitIsOver(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.pushPrimerDeciding
    }

    /// 評価のお願いを頼んでよいか
    static func reviewMayAsk(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.pushPrimerShowing && !s.pushPrimerDeciding && !s.trunkPending && !s.trunkShowing
            && !s.welcomeShowing && !s.coverOfferBusy && !s.extrasShowing
    }

    /// 届いた画面を出してよいか
    static func trunkMayShow(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.pushPrimerDeciding && !s.pushPrimerShowing && !s.reviewDeciding && !s.trunkShowing
            && !s.welcomeShowing && !s.coverOfferBusy && !s.extrasShowing
    }

    /// はじめての硬貨の案内を出してよいか（いちばん後ろ。ほかのどれも出ていない・決めていない・残っていない）
    static func welcomeMayShow(_ s: PostModalSnapshot) -> Bool {
        s.sceneActive && !s.modalPresenting && !s.launchNoticesDeciding && !s.pushPrimerDeciding && !s.pushPrimerShowing
            && !s.reviewDeciding && !s.trunkPending && !s.trunkShowing && !s.welcomeShowing
            && !s.coverOfferBusy && !s.extrasShowing
    }

    /// 通知の説明の待ちが終わったか（ほかの画面が出ていない・初めての投稿の差し出しを決め終えて閉じた・#304）
    static func pushPrimerWaitIsOver(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.coverOfferBusy && !s.extrasShowing
    }

    /// アイコン・カバーのお礼を出してよいか（はじめての硬貨の案内のあと・#304）
    static func rewardMayShow(_ s: PostModalSnapshot) -> Bool {
        welcomeMayShow(s) && !s.welcomePending
    }

    /// いいねが集まった1枚の差し出しを出してよいか（いちばん後ろ・#304）。お礼が残っていれば、`RootView` がお礼を先に出す
    static func likedOfferMayShow(_ s: PostModalSnapshot) -> Bool {
        welcomeMayShow(s) && !s.welcomePending
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

/// はじめての硬貨の全画面を出したあと、**本当に出たか**を見る（2026-10-18 の見直し）。
///
/// 決まった秒数で「出なかった」と決めない——全画面が出るのが遅い端末で、待ちへ戻したあとに遅れて出て、
/// 一瞬出て閉じ、もう一度出ていた。決め方:
/// - 出た合図（`TrunkWelcomeView` の onAppear）が来た → 出た
/// - 何かが出ている（`ModalProbe`・自分の全画面が出かけている間も含む）→ 待ち続ける
/// - 何も出ていない状態が `quietSeconds` 続いた → 出なかった（待ちへ戻す）
/// - 前面に出ていない間は数えない（裏へ回った直後の起点が残ると、前面に戻った瞬間に「出なかった」となり一瞬二度出る）
///
/// 問い合わせの間隔（`pollInterval`）は 0.1 秒。何かが出たまま（または裏にいるまま）`slowAfterSeconds` 続いたら 1 秒に延ばし、
/// 閉じたら 0.1 秒に戻す（長く開いている写真の全画面の間、毎秒10回問わない）
struct WelcomePresentationWatch {
    enum Outcome: Equatable { case shown, waiting, giveBack }

    /// 何も出ていない状態がこれだけ続いたら「出なかった」
    static let quietSeconds: TimeInterval = 1
    /// 何かが出たままの状態がこれだけ続いたら、問い合わせを延ばす
    static let slowAfterSeconds: TimeInterval = 3
    static let fastInterval: TimeInterval = 0.1
    static let slowInterval: TimeInterval = 1

    private var quietSince: Date?
    private var busySince: Date?
    /// 次に問うまでの間（秒）
    private(set) var pollInterval: TimeInterval = fastInterval

    mutating func check(appeared: Bool, modalPresenting: Bool, sceneActive: Bool = true, now: Date) -> Outcome {
        if appeared { return .shown }
        if modalPresenting || !sceneActive {
            quietSince = nil
            let since = busySince ?? now
            busySince = since
            pollInterval = now.timeIntervalSince(since) >= Self.slowAfterSeconds ? Self.slowInterval : Self.fastInterval
            return .waiting
        }
        busySince = nil
        pollInterval = Self.fastInterval
        guard let since = quietSince else {
            quietSince = now
            return .waiting
        }
        return now.timeIntervalSince(since) >= Self.quietSeconds ? .giveBack : .waiting
    }
}
