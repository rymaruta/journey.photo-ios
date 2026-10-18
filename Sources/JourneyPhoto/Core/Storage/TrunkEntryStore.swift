import Foundation
import Combine

/// 旅のトランクの入口の札（マイページの上・設定の行）に出す数（2026-10-18 owner「入口がわかりずらい」）。
///
/// - 出すのは **硬貨の枚数**（`TrunkState.coins`）と、**手持ちに貼っていないラベルがあるか**（`pocket`）だけ
/// - 中身は `TrunkService.state()`（`GET /user/trunk`）の応答から作る。トランクの画面の状態（`TrunkViewModel`）は
///   画面ごとに持つので、入口はその写しを持たず、2つの数だけを覚える
/// - 見本（画面写真・`PreviewSession.trunkSample`）では読まずに、トランクの画面と同じ見本（`TrunkSample.state`）から作る
///
/// 2026-10-18 判断: **マイページを開くたびに読まない。** 読むのは、
/// まだ読んでいない・前に読んでから 6 時間（`TrunkAvailabilityRule.recheckInterval` と同じ）・
/// トランクの画面から戻った／公開の写真を投稿した（`markStale`）ときだけ。読めなかった回は 10 分あけてから読み直す。
///
/// **`GET /user/trunk` は1本にまとめる**（2026-10-18 見直し）: 口の有無（`TrunkAvailability`）も `read` を通して読み、
/// 読めた中身をこちらにも入れる。同じ人の読み込みが走っている間に呼ばれたら、新しく読まずにその結果を待つ
/// （起動直後・前面に戻ったときに、口の有無と札の数で2回読んでいた）。
/// アプリが前面に戻ったときは `TrunkAvailability.refresh(force:)` の1回で両方が埋まる。
///
/// 端末には書かない（人が替わったら捨てる・退会で消す物を増やさない）。
/// 残る重なり: トランクの画面は自分で読む（`TrunkViewModel`・触らない所）ので、トランクを1回見ると、
/// 画面の読み込みと戻ったときの札の読み直しで2回になる
@MainActor
final class TrunkEntryStore: ObservableObject {

    static let shared = TrunkEntryStore()

    @Published private(set) var summary: TrunkEntrySummary?
    /// 読めた中身そのもの（札の左の小さなトランクの絵・型の名前に使う・2026-10-18 A′）。`summary` と同じ回に入る
    @Published private(set) var state: TrunkState?

    private var userId: String?
    private var readAt: Date?
    private var failedAt: Date?
    private var stale = false
    /// 走っている読み込み（同じ人なら相乗りする）
    private var inFlight: (token: Int, userId: String, task: Task<TrunkState, Error>)?
    private var nextToken = 0

    init() {}

    /// トランクの中身が変わったかもしれない（トランクの画面から戻った・投稿した）。次の `refresh` で読み直す
    func markStale() { stale = true }

    private func use(_ userId: String?) {
        guard userId != self.userId else { return }
        // 人が替わったら前の人の数を持ち越さない
        self.userId = userId
        summary = nil
        state = nil
        readAt = nil
        failedAt = nil
        stale = false
    }

    /// `GET /user/trunk` を1回読み、札の数にも入れる（`TrunkAvailability` もここを通す）。
    /// 同じ人の読み込みが走っていれば、その結果を待つ（2本目を出さない）
    func read(userId: String, service: TrunkService, now: Date = Date()) async throws -> TrunkState {
        if let running = inFlight, running.userId == userId {
            return try await running.task.value
        }
        use(userId)
        nextToken += 1
        let token = nextToken
        // 呼び手が取り消されても、相乗りしている側のために読み切る
        let task = Task { try await service.state() }
        inFlight = (token, userId, task)
        defer { if inFlight?.token == token { inFlight = nil } }
        do {
            let state = try await task.value
            if self.userId == userId {
                summary = TrunkEntrySummary(state)
                self.state = state
                readAt = now
                failedAt = nil
                stale = false
            }
            return state
        } catch {
            // 取り消し（`CancellationError`・`URLError(.cancelled)`）は失敗に数えない（10 分止めない）
            if self.userId == userId, !TrunkEntryRule.isCancellation(error) { failedAt = now }
            throw error
        }
    }

    /// 入口の数を（要るときだけ）読む。`available` は `TrunkAvailability.isAvailable`（口が無い間は読まない）
    func refresh(userId: String?, available: Bool, service: TrunkService, now: Date = Date(),
                 preview: PreviewSession.TrunkPreview? = PreviewSession.trunkSample,
                 previewPro: Bool = PreviewSession.isPro) async {
        use(userId)
        guard let userId, available else { return }
        if let preview {
            let sample = TrunkSample.state(isPro: previewPro, empty: preview == .empty, coins: PreviewSession.trunkCoins)
            summary = TrunkEntrySummary(sample)
            state = sample
            return
        }
        let running = inFlight?.userId == userId
        guard running || TrunkEntryRule.needsRead(readAt: readAt, failedAt: failedAt, stale: stale, now: now) else { return }
        do {
            _ = try await read(userId: userId, service: service, now: now)
        } catch {
            // 取り消されたら、次の機会に読み直す
            if TrunkEntryRule.isCancellation(error) { stale = true }
        }
    }
}

/// アプリが**裏から**前面に戻ったか（2026-10-18 見直し）。通知センター・Face ID・コントロールセンターから
/// 戻ったとき（`inactive` → `active`）は読まない。裏に回った（`background`）あとの `active` だけ
struct TrunkForegroundGate: Equatable {
    private(set) var wentToBackground = false

    /// 場面の移り変わりを受け、読み直す時なら true
    mutating func shouldRecheck(isBackground: Bool, isActive: Bool) -> Bool {
        if isBackground {
            wentToBackground = true
            return false
        }
        guard isActive, wentToBackground else { return false }
        wentToBackground = false
        return true
    }
}

/// 入口の札の2つの数
struct TrunkEntrySummary: Equatable {
    /// 硬貨の枚数
    let coins: Int
    /// 手持ちの（まだ貼っていない）ラベルの枚数
    let unstuck: Int

    init(coins: Int, unstuck: Int) {
        self.coins = max(0, coins)
        self.unstuck = max(0, unstuck)
    }

    init(_ state: TrunkState) {
        self.init(coins: state.coins, unstuck: state.pocket.count)
    }

    /// 真鍮の点を出すか（手持ちに貼っていないラベルがある）
    var hasUnstuck: Bool { unstuck > 0 }
}

/// 入口を出すか・いつ読むか（画面を持たない・Linux でテストする）
enum TrunkEntryRule {

    /// 読めなかったあと、読み直すまでの間
    static let retryInterval: TimeInterval = 10 * 60

    /// 入口（マイページの上の札・設定の行）を出すか。**口が読めたことのある人だけ**（今までの行と同じ条件）
    static func shows(signedIn: Bool, available: Bool) -> Bool {
        signedIn && available
    }

    /// 取り消し（失敗に数えない）
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    /// 公開の写真を投稿したか（硬貨とラベルが届く・`PhotoTrip.isPublic`）。取り消し・ストーリー・
    /// 下書き・公開範囲を絞った写真では読み直さない
    static func postedPublic(_ photos: [Photo]) -> Bool {
        photos.contains(where: PhotoTrip.isPublic)
    }

    /// 読むか
    static func needsRead(readAt: Date?, failedAt: Date?, stale: Bool, now: Date) -> Bool {
        if stale { return true }
        if let failedAt, now.timeIntervalSince(failedAt) < retryInterval { return false }
        guard let readAt else { return true }
        return now.timeIntervalSince(readAt) >= TrunkAvailabilityRule.recheckInterval
    }
}

/// 入口の言葉（2026-10-18）。**`TrunkText` は旅のトランクの担当が書いている所なので、入口の言葉はここに置く**。
/// 「旅のトランク」「投稿のお礼に届いた…」は今までの旅の記録の行、「硬貨 N」はトランクの画面の札と同じ言葉
enum TrunkEntryText {

    static var title: String { L("旅のトランク", "Travel trunk") }

    static var detail: String {
        L("投稿のお礼に届いた旅のラベルを貼っていく", "Stick the travel labels you get for posting")
    }

    /// 「硬貨 3」（トランクの画面の「カプセルの機械」の行と同じ形）
    static func coins(_ n: Int) -> String {
        L("硬貨 \(max(0, n))", max(0, n) == 1 ? "1 coin" : "\(max(0, n)) coins")
    }

    /// 札の題の下の行（型の名前・例「革の旅行鞄」）。いま描く型（Pro をやめたら最後の無料の型）
    static func modelName(_ state: TrunkState?) -> String? {
        state.map { TrunkText.info($0.effectiveModel).name }
    }

    /// 読み上げの値: 型の名前・硬貨の枚数・貼っていないラベルの有無（色の点だけで伝えない）
    static func accessibilityValue(_ summary: TrunkEntrySummary?, model: String? = nil) -> String {
        guard let summary else { return model ?? "" }
        let coins = L("硬貨 \(summary.coins)枚", summary.coins == 1 ? "1 coin" : "\(summary.coins) coins")
        let labels = summary.hasUnstuck
            ? L("まだ貼っていないラベルが \(summary.unstuck)枚あります",
                summary.unstuck == 1 ? "1 label not stuck yet" : "\(summary.unstuck) labels not stuck yet")
            : L("貼っていないラベルはありません", "No labels waiting")
        let counts = L("\(coins)、\(labels)", "\(coins), \(labels)")
        guard let model, !model.isEmpty else { return counts }
        return L("\(model)、\(counts)", "\(model), \(counts)")
    }
}
