import Foundation
import Combine

/// 投稿のお礼に届いたラベル（旅のトランク・モック LabelArrived・2026-10-17）。
///
/// 投稿は全部上がると画面を閉じ、Threads への共有の画面が続くこともある。届いた画面は
/// **それらが閉じてから** `RootView` が出す（通知の説明 `PushPrimerStore` と同じ待ち方）。
/// ここは「出すものがある」を持つだけで、端末には何も書かない（届いたラベルはサーバーの手持ちにある）。
@MainActor
final class TrunkArrivals: ObservableObject {

    static let shared = TrunkArrivals()

    struct Arrival: Equatable {
        let label: TrunkLabel
        /// 投稿した写真の題（空なら「写真」と言う）
        let photoTitle: String
    }

    /// 届いた画面に出す束（先頭が大きく出る1枚・残りは「ほかに N 枚」）
    struct Batch: Identifiable, Equatable {
        let arrivals: [Arrival]
        var id: String { arrivals.map(\.label.id).joined(separator: ",") }
        var first: Arrival { arrivals[0] }
        var othersCount: Int { arrivals.count - 1 }
    }

    /// 増えるたびに `RootView` が出す頃合いを見る
    @Published private(set) var requests = 0
    private(set) var pending: Batch?
    /// 手持ちがいっぱいで届かなかった（一言を出す）
    private(set) var pendingFullNotice = false

    init() {}

    /// 投稿が全部上がった。届いたラベル（無ければ空）と、いっぱいで届かなかったか
    func deliver(_ arrivals: [Arrival], pocketWasFull: Bool) {
        guard !arrivals.isEmpty || pocketWasFull else { return }
        if !arrivals.isEmpty {
            pending = Batch(arrivals: (pending?.arrivals ?? []) + arrivals)
        } else {
            pendingFullNotice = true
        }
        requests += 1
    }

    /// 出す束を受け取る（受け取ったら空にする）
    func consume() -> Batch? {
        defer { pending = nil }
        return pending
    }

    /// いっぱいの一言を出すか（受け取ったら下ろす）。ラベルが届いた回は出さない
    func consumeFullNotice() -> Bool {
        defer { pendingFullNotice = false }
        return pendingFullNotice && pending == nil
    }
}
