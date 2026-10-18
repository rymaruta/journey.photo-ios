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
/// トランクの画面から戻った／投稿を閉じた（`markStale`）・アプリが前面に戻った（`force`）ときだけ。
/// 読めなかった回は 10 分あけてから読み直す（前面に戻ったときは待たない）。
/// 端末には書かない（人が替わったら捨てる・退会で消す物を増やさない）
@MainActor
final class TrunkEntryStore: ObservableObject {

    static let shared = TrunkEntryStore()

    @Published private(set) var summary: TrunkEntrySummary?

    private var userId: String?
    private var readAt: Date?
    private var failedAt: Date?
    private var stale = false
    private var reading = false

    init() {}

    /// トランクの中身が変わったかもしれない（トランクの画面から戻った・投稿した）。次の `refresh` で読み直す
    func markStale() { stale = true }

    /// 入口の数を（要るときだけ）読む。`available` は `TrunkAvailability.isAvailable`（口が無い間は読まない）
    /// - Parameter force: アプリが前面に戻ったとき（`TrunkAvailability` と同じ・ほかの端末や Web の投稿で硬貨が増える）
    func refresh(userId: String?, available: Bool, service: TrunkService, force: Bool = false, now: Date = Date(),
                 preview: PreviewSession.TrunkPreview? = PreviewSession.trunkSample,
                 previewPro: Bool = PreviewSession.isPro) async {
        if userId != self.userId {
            // 人が替わったら前の人の数を持ち越さない
            self.userId = userId
            summary = nil
            readAt = nil
            failedAt = nil
            stale = false
        }
        guard let userId, available else { return }
        if let preview {
            summary = TrunkEntrySummary(TrunkSample.state(isPro: previewPro, empty: preview == .empty,
                                                          coins: PreviewSession.trunkCoins))
            return
        }
        if force { stale = true }
        guard !reading,
              TrunkEntryRule.needsRead(readAt: readAt, failedAt: failedAt, stale: stale, now: now) else { return }
        reading = true
        defer { reading = false }
        stale = false
        do {
            let state = try await service.state()
            guard self.userId == userId else { return }
            summary = TrunkEntrySummary(state)
            readAt = now
            failedAt = nil
        } catch is CancellationError {
            stale = true
        } catch {
            // 読めなかった: 前の数は消さない（一時の圏外で札の数が消えない）
            guard self.userId == userId else { return }
            failedAt = now
        }
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

    /// 読み上げの値: 硬貨の枚数と、貼っていないラベルの有無（色の点だけで伝えない）
    static func accessibilityValue(_ summary: TrunkEntrySummary?) -> String {
        guard let summary else { return "" }
        let coins = L("硬貨 \(summary.coins)枚", summary.coins == 1 ? "1 coin" : "\(summary.coins) coins")
        let labels = summary.hasUnstuck
            ? L("まだ貼っていないラベルが \(summary.unstuck)枚あります",
                summary.unstuck == 1 ? "1 label not stuck yet" : "\(summary.unstuck) labels not stuck yet")
            : L("貼っていないラベルはありません", "No labels waiting")
        return L("\(coins)、\(labels)", "\(coins), \(labels)")
    }
}
