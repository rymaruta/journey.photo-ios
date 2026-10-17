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
    /// ラベルが届かなかった理由のうち、一言で知らせるもの（手持ちがいっぱい・トランクの容量）。
    /// ほかの理由（同じ写真・1日の上限・受け取らない設定・時間切れ・知らない値）は黙って何も出さない
    enum Notice: Equatable {
        case full, storage

        init?(_ skip: TrunkLabelSkip?) {
            switch skip {
            case .full: self = .full
            case .storage: self = .storage
            default: return nil
            }
        }

        var text: String {
            switch self {
            case .full: return TrunkText.fullNotice
            case .storage: return TrunkText.storageNotice
            }
        }
    }

    private(set) var pendingNotice: Notice?

    /// 束を出す相手（ログアウト・人の切り替えで前の人の束を捨てる）
    private var owner: String?

    init() {}

    /// 出すものがあるか（画面が閉じたら出し直す）
    var hasPending: Bool { pending != nil || pendingNotice != nil }

    /// 束が入った時刻（評価のお願いを止めるのは入ってから少しの間だけ）
    private(set) var deliveredAt: Date?

    /// 評価のお願いを止めてよい長さ。2026-10-17 判断: 2分。待ちきれずに残った束（投稿の画面を開いたまま・
    /// 通知の説明が長く出ていた）が、評価のお願いをずっと止めないように
    static let reviewHoldSeconds: TimeInterval = 120

    /// 評価のお願いを止めるか（入ってから `reviewHoldSeconds` の間だけ）
    func blocksReview(now: Date = Date()) -> Bool {
        guard hasPending, let deliveredAt else { return false }
        return now.timeIntervalSince(deliveredAt) < Self.reviewHoldSeconds
    }

    /// 届いた画面で「トランクに貼る」が済んだ（閉じ切ってから全体の知らせを1つだけ出す・`RootView`）
    private var stuckFromArrival = false

    func noteStuckFromArrival() { stuckFromArrival = true }

    /// 閉じたあとに「トランクに貼りました」を出すか（受け取ったら下ろす）
    func consumeStuckFromArrival() -> Bool {
        defer { stuckFromArrival = false }
        return stuckFromArrival
    }

    /// 下書きを公開した・投稿した応答の配った結果を渡す（`TrunkDealt`）
    func deliver(_ dealt: TrunkDealt, photoTitle: String, now: Date = Date()) {
        deliver(dealt.label.map { [Arrival(label: $0, photoTitle: photoTitle)] } ?? [],
                notice: Notice(dealt.labelSkipped), now: now)
    }

    /// 入っている人が替わった（ログアウトを含む）。**前の人に届いた束と一言を捨てる**（2026-10-17 の読み直し）
    func noteUser(_ userId: String?) {
        guard userId != owner else { return }
        owner = userId
        reset()
    }

    func reset() {
        pending = nil
        pendingNotice = nil
        deliveredAt = nil
        stuckFromArrival = false
    }

    /// 投稿が全部上がった。届いたラベル（無ければ空）と、届かなかった理由の一言（無ければ nil）
    func deliver(_ arrivals: [Arrival], notice: Notice?, now: Date = Date()) {
        guard !arrivals.isEmpty || notice != nil else { return }
        deliveredAt = now
        if !arrivals.isEmpty {
            pending = Batch(arrivals: (pending?.arrivals ?? []) + arrivals)
        } else {
            pendingNotice = notice
        }
        requests += 1
    }

    /// 出す束を受け取る（受け取ったら空にする）
    func consume() -> Batch? {
        defer { pending = nil }
        return pending
    }

    /// 出す一言（受け取ったら下ろす）。ラベルが届いた回は出さない
    func consumeNotice() -> Notice? {
        defer { pendingNotice = nil }
        return pending == nil ? pendingNotice : nil
    }
}
