import Foundation
import Combine

/// 写真から行き先を選ぶ画面の状態（`TripPickerView`・`TripPickerDraftView`）。
///
/// 札の山（`TripPicker.deck`）を1枚ずつめくり、**行きたい／見送る**を積む。
/// 積んだ順に「ひとつ戻す」で戻せる。下書きは選んだ場所から**毎回作り直す**
/// （地域で束ねる・日へ割り振るのは `TripPicker`）。
///
/// 「行きたい」への出し入れ（`WishlistSync`）は画面が呼ぶ。ここは**1本ずつ流す列**
/// （`enqueueWish`）だけを持つ——入れる途中で「ひとつ戻す」を押すと、外す要求が
/// 送信中の印（`isSending`）で捨てられ、戻したのに「行きたい」に残っていた、を防ぐ。
@MainActor
final class TripPickerModel: ObservableObject {

    enum Status: Equatable { case loading, loaded, failed }
    enum Choice: Equatable { case want, skip }

    struct Decision: Equatable {
        let spot: OfficialSpot
        let choice: Choice
        /// 決めた時点で**もう「行きたい」に入っていた**か。入っていたら、足しも外しもしない
        /// （山は開いた時点の写しで除くので、起動時の同期が済む前は入っている場所も出る。
        ///  「ひとつ戻す」で本人が前から入れていた場所を外さない）
        var wasWanted = false
    }

    @Published private(set) var status: Status = .loading
    @Published private(set) var deck: [OfficialSpot] = []
    /// めくった札。**並びは押した順**（「ひとつ戻す」は後ろから戻す）
    @Published private(set) var decisions: [Decision] = []
    /// 下書きで「このプランから外す」を押した場所（`spotId`）。**「行きたい」からは外さない**
    @Published private(set) var removed: Set<String> = []

    /// 下書きの保存の1段目（作る）が通ったプラン。**下書きの画面ではなくここに持つ**
    /// ——下書きの画面は戻って開き直すと作り直されるので、そこに置くと2段目が断られた
    /// あとの保存が1段目からやり直しになり、同じプランが2つできた
    @Published var createdPlanId: String?
    @Published var createdTitle: String?
    /// 下書きの題・日付・失敗の文も同じ理由でここに持つ（開き直しで消さない・
    /// 本人が付けた題を案の題で上書きしない）
    @Published var draftTitle = ""
    @Published var draftStart: String?
    @Published var draftEnd: String?
    @Published var draftError: String?

    /// この板の中で「行きたい」に足した場所（`spotId`）。**戻しても消さない**。
    /// 「前から入っていたか」を控えの `contains` だけで決めると、足す→戻す（外す要求が列で待つ）
    /// →また行きたい、で控えにまだ残っているため「前から」と読み、足さずに外していた
    private var addedHere: Set<String> = []

    /// 決める前に呼ぶ。控えに入っていても、**この板で足したものは「前から」ではない**
    func wasWantedBefore(_ spotId: String, inWishlist: Bool) -> Bool {
        inWishlist && !addedHere.contains(spotId)
    }

    /// 足す要求を列に積んだ
    func markAdded(_ spotId: String) {
        addedHere.insert(spotId)
    }

    /// いまの札の位置（めくった数と同じ）
    var position: Int { decisions.count }

    var current: OfficialSpot? { deck.indices.contains(position) ? deck[position] : nil }
    /// 次の札（下に重ねて見せる・先に読み込ませる）
    var upcoming: OfficialSpot? { deck.indices.contains(position + 1) ? deck[position + 1] : nil }

    /// 選んだ場所（押した順）。下書きで外したものは入れない
    var picked: [OfficialSpot] {
        decisions.filter { $0.choice == .want && !removed.contains($0.spot.spotId) }.map(\.spot)
    }

    /// 選べる上限に届いたか（`TripPicker.pickMax`）
    var isFull: Bool { picked.count >= TripPicker.pickMax }

    /// 札の山を作る。**取れた後は作り直さない**（戻ってくるたびに混ぜ直すと、見た札がまた出る）
    ///
    /// - Parameters:
    ///   - fetch: 索引を取る口（`environment.spots.fetchIndex`）
    ///   - excluding: もう「行きたい」に入っている鍵。**開いた時点の写し**を渡す
    ///     （選んでいる間に入れた鍵で山を作り直さない）
    ///   - seed: 混ぜ方の種（画面は開くたびに新しく作る）
    func load(fetch: () async throws -> [OfficialSpot], excluding: Set<String>, seed: UInt64) async {
        guard status != .loaded else { return }
        status = .loading
        do {
            let index = try await fetch()
            // 待っている間に別の読み込みが済んでいたら、そちらを残す
            guard status != .loaded else { return }
            deck = TripPicker.deck(from: index, excluding: excluding, seed: seed)
            status = .loaded
        } catch {
            if Task.isCancelled { return }
            guard status != .loaded else { return }
            status = .failed
        }
    }

    /// いまの札を決める。**決めた場所**を返す（札が無い・上限で「行きたい」を足せないときは nil）
    @discardableResult
    func decide(_ choice: Choice, alreadyWanted: Bool = false) -> OfficialSpot? {
        guard let spot = current else { return nil }
        if choice == .want && isFull { return nil }
        decisions.append(Decision(spot: spot, choice: choice, wasWanted: choice == .want && alreadyWanted))
        return spot
    }

    /// ひとつ戻す。**戻した決めごと**を返す（行きたいだった場合、画面が「行きたい」から外す）
    @discardableResult
    func undo() -> Decision? {
        guard let last = decisions.popLast() else { return nil }
        removed.remove(last.spot.spotId)
        return last
    }

    /// 下書きから外す（札は戻さない・「行きたい」はそのまま）
    func remove(_ spotId: String) {
        removed.insert(spotId)
    }

    // MARK: - 「行きたい」への出し入れを1本ずつ流す

    private var wishQueue: Task<Void, Never>?

    /// 前の出し入れが終わってから `operation` を走らせる（押した順に届く）
    func enqueueWish(_ operation: @escaping @MainActor () async -> Void) {
        let previous = wishQueue
        wishQueue = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// 流している出し入れが全部終わるまで待つ（試験用・保存の前に待つ）
    func waitForWishes() async {
        await wishQueue?.value
    }
}
