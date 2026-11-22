import Foundation
import Combine

/// **初めての投稿のあとの「投稿しました」1枚**（札 #628・2026-11-22 判断）。
///
/// 前は初めての投稿のあと、共有カード → この1枚をカバーに → 通知の説明 → iPhone の許可 → 届いたラベル（全画面）→
/// お礼（全画面）が順に出て、閉じるまで次に進めなかった（閉じるまで 5〜7回）。いまは1枚にまとめ、
/// 行は押した人だけが進む。閉じれば終わり（1回）。
///
/// - 行: 返事が来たら知らせる（オンにする）、この写真をカバーに（する）、ラベルが届きました（見る）
/// - 2回目からの投稿は今までどおり知らせ「投稿しました　カードにする」だけ（`PostUploadCenter`）
/// - 届いたラベルは、この1枚が開いていれば行に、閉じていれば知らせ「ラベルが届きました　見る」に（全画面を自分からは出さない）
@MainActor
final class PostedSummaryCenter: ObservableObject {

    static let shared = PostedSummaryCenter()

    struct Summary: Identifiable {
        let id = UUID()
        /// 誰の投稿か（人が替わったら閉じる）
        let ownerId: String
        /// 共有カード（公開・全体に公開の投稿だけ。無ければカードの絵とボタンは出さない）
        var card: PostedShareCard?
        /// この写真をカバーに（初めての投稿で、カバーが無い人だけ）
        var cover: CoverOfferStore.Offer?
        /// 返事が来たら知らせる（まだ通知の許可を聞いていない人だけ・`PushPrimer.shouldOffer`）
        var offersPush: Bool
        /// 一緒に届いたラベル（開いている間に届いた分も足す）
        var labels: TrunkArrivals.Batch?
    }

    /// 開いている「投稿しました」
    @Published var presented: Summary?

    /// 閉じたあとに続ける操作（行の「見る」「カードを共有」。閉じきってから `RootView` が開く）
    enum FollowUp {
        /// 「カードを共有」: カードの画面（`PostedShareCardSheet`）
        case shareCard(PostedShareCard)
        /// ラベルの「見る」: 届いた画面（`LabelArrivedView`）
        case labels(TrunkArrivals.Batch)
    }

    /// 閉じる前に押した続き（`close(then:)` が中身ごと預かる）
    enum Choice: Equatable {
        case shareCard
        case labels
    }

    private(set) var followUp: FollowUp?

    /// 出すか（カードも行も無ければ、知らせだけで足りる）
    static func showsSheet(_ summary: Summary) -> Bool {
        summary.card != nil || !rows(summary).isEmpty
    }

    /// 行の並び（板の案の順: 通知、カバー、ラベル）
    enum Row: Equatable {
        case push
        case cover
        case labels(count: Int)
    }

    static func rows(_ summary: Summary) -> [Row] {
        var rows: [Row] = []
        if summary.offersPush { rows.append(.push) }
        if summary.cover != nil { rows.append(.cover) }
        if let labels = summary.labels, !labels.arrivals.isEmpty { rows.append(.labels(count: labels.arrivals.count)) }
        return rows
    }

    /// 届いたラベルの出し方（全画面は自分からは出さない）
    enum LabelArrival: Equatable {
        /// 開いている「投稿しました」の行に足す
        case summaryRow
        /// 知らせ「ラベルが届きました　見る」
        case notice
    }

    static func labelArrival(summaryOpen: Bool) -> LabelArrival {
        summaryOpen ? .summaryRow : .notice
    }

    /// 出してよいか（ほかの画面が出ていない。ほかの差し出し・お礼・この1枚も出ていない）。
    /// 決めている途中（`coverOfferBusy`）は自分のことなので見ない
    static func mayPresent(_ s: PostModalSnapshot) -> Bool {
        !s.modalPresenting && !s.extrasShowing
    }

    /// 出した投稿の評価のお願いを見送る印（投稿のあとで割り込むのは1つまで・札 #628）。
    /// 立てるのは評価の側が待っている間に出したときだけ、下ろすのはその待ちが終わったとき（先に抜けた回に印が残り、
    /// 次のうれしい瞬間を黙って見送らないように・2026-11-22 確かめ役の指摘）
    private(set) var skipsNextReview = false
    /// 待っている評価のお願いの数
    private var reviewWaits = 0

    /// 評価のお願いが待ち始めた
    func beginReviewWait() { reviewWaits += 1 }

    /// 評価のお願いの待ちが終わった（頼んだ・見送った・抜けた、のどれでも）。最後の待ちが終われば印を下ろす
    func endReviewWait() {
        reviewWaits = max(0, reviewWaits - 1)
        if reviewWaits == 0 { skipsNextReview = false }
    }

    /// 評価のお願いの側が1回だけ受け取る（受け取ったら下ろす）
    func takeReviewSkip() -> Bool {
        defer { skipsNextReview = false }
        return skipsNextReview
    }

    /// 出す（出すものが無ければ出さずに false）
    @discardableResult
    func present(_ summary: Summary) -> Bool {
        guard Self.showsSheet(summary) else { return false }
        followUp = nil
        presented = summary
        if reviewWaits > 0 { skipsNextReview = true }
        return true
    }

    /// 開いている1枚にラベルを足す。足せたら true（開いていなければ false＝知らせにする）
    @discardableResult
    func addLabels(_ batch: TrunkArrivals.Batch) -> Bool {
        guard var summary = presented else { return false }
        if let had = summary.labels {
            summary.labels = TrunkArrivals.Batch(arrivals: had.arrivals + batch.arrivals, coins: had.coins + batch.coins)
        } else {
            summary.labels = batch
        }
        presented = summary
        return true
    }

    /// 通知の行を済ませた・カバーにした: 行を外す
    func clearPush() { presented?.offersPush = false }
    func clearCover() { presented?.cover = nil }

    /// 行・ボタンから閉じる（閉じきってから続きを開く）。中身はここで預かる（閉じると `presented` は空になる）
    func close(then choice: Choice?) {
        switch choice {
        case .shareCard: followUp = presented?.card.map { .shareCard($0) }
        case .labels: followUp = presented?.labels.map { .labels($0) }
        case nil: followUp = nil
        }
        presented = nil
    }

    /// 閉じきった: 続きを受け取る（受け取ったら空）
    func takeFollowUp() -> FollowUp? {
        defer { followUp = nil }
        return followUp
    }

    /// 人が替わった（ログアウトを含む）: 前の人の分は閉じる
    func userChanged(to userId: String?) {
        if let presented, presented.ownerId != userId {
            self.presented = nil
            followUp = nil
        }
    }
}
