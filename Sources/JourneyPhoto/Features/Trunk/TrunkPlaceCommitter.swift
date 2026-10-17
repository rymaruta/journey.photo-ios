import Foundation
import Combine

/// 自分の手で貼る画面の「置き直しの保存」（回した・動かした置き場を、ラベルごとに送る・2026-10-17 の見直し）。
///
/// 画面から分けたのは、送る順序・失敗の数え方を振る舞いでテストするため。
/// - 予定はラベルごと（別のラベルを回しても前の保存は消えない）
/// - 書き込みの最中は待つ・同じラベルへは新しい頼みだけが送る（`TrunkViewModel.placeWhenFree`）
/// - 「完了」（`flush`）: もう溜まっていないラベルは成功と数える。新しい頼みに負けた（`.superseded`）ら、
///   その頼みの結果を待ってから判定する
/// - 「保存せずに閉じる」（`discardAll`）: 溜まった置き場を送らない（トランクは元の置き場で描く）。
///   運んで離した送信も予定（`schedule`）に入れるので、待っている分はここで取り消せる
/// - 送り終えたら、その予定に付けた知らせ（`then`）を1回だけ呼ぶ（運んだ1枚のよれ・音・触覚）。
///   後から同じ1枚を回して予定が替わっても、知らせは引き継ぐ。「完了」が送ったときも呼ぶ。
///   送れなかった（圏外・混んだまま）ときは知らせを残し、あとで「完了」「もう一度」で送れたら呼ぶ。
///   画面が閉じたあとに送れたときは `closed` を立てて呼ぶ（音・触覚は出さず、よれだけ覚える）
@MainActor
final class TrunkPlaceCommitter: ObservableObject {

    @Published private(set) var pending = TrunkPendingPlaces()

    private weak var model: TrunkViewModel?
    private var tasks: [String: Task<Void, Never>] = [:]
    /// 送り終えたときの知らせ（ラベルごと・1回だけ呼ぶ）
    private var completions: [String: Notice] = [:]
    /// ラベルごとの、最後に溜まりから消えた結果（送れた・断られた）。知らせに渡す
    private var lastSent: [String: TrunkViewModel.PlaceOutcome] = [:]
    /// 送り終えた知らせ。`outcome` は送れた（`.saved`）か断られた（`.refused`）。
    /// `closed` は画面が閉じたあと（音・触覚は出さない）
    typealias Notice = (_ outcome: TrunkViewModel.PlaceOutcome, _ closed: Bool) -> Void

    /// 送れた1手（id と、動かす前の置き場）。画面の「ひとつ戻す」に積む
    var onSaved: ((String, TrunkPos) -> Void)?

    init() {}

    func bind(_ model: TrunkViewModel) {
        if self.model == nil { self.model = model }
    }

    var overrides: [String: TrunkPos] { pending.overrides }

    func note(_ id: String, from: TrunkPos, to: TrunkPos) {
        pending.note(id, from: pending[id]?.from ?? from, to: to)
    }

    /// 少し待ってから送る。混んでいたら置き場を残してやり直す（取り消されたら作り直さない）。
    /// `then` は送り終えたときに1回だけ呼ぶ（nil なら前の予定の知らせを引き継ぐ）
    func schedule(_ id: String, delay: Double, attempt: Int = 0,
                  then done: Notice? = nil) {
        if let done { completions[id] = done }
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            // 始めた送信は予定の取り消しで切らない（途中で切ると圏外と同じ失敗になる）。
            // 待っている頼みを止めるのは `discardAll` の取り下げ（`withdrawPlace`）
            let outcome = await Task { await self.commit(id) }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .busy? where attempt < 5:
                self.schedule(id, delay: 0.3, attempt: attempt + 1)
            case .saved?, .refused?, nil:
                // nil はもう溜まっていない（ほかの頼みが送った）: その結果で知らせる
                self.complete(id, outcome ?? self.lastSent[id] ?? .saved)
            default:
                // 圏外・混んだまま・新しい頼みに負けた: 知らせは残す（あとで送れたら付ける）
                break
            }
        }
    }

    private func complete(_ id: String, _ outcome: TrunkViewModel.PlaceOutcome, closed: Bool = false) {
        completions.removeValue(forKey: id)?(outcome, closed)
    }

    /// 1枚の置き場を送る。**溜まっていなければ nil**（送ることが無い）
    @discardableResult
    func commit(_ id: String) async -> TrunkViewModel.PlaceOutcome? {
        guard let model, let item = pending[id] else { return nil }
        let outcome = await model.placeWhenFree(id, at: item.to)
        switch outcome {
        case .saved:
            if TrunkPlacement.clamp(item.from) != TrunkPlacement.clamp(item.to) { onSaved?(id, item.from) }
            pending.done(id, sent: item.to)
            lastSent[id] = .saved
        case .refused:
            pending.done(id, sent: item.to)
            lastSent[id] = .refused
        case .busy, .failed, .superseded:
            // 混んでいた・圏外: 置き場は残す。新しい頼みに負けた: その頼みが送る
            break
        }
        return outcome
    }

    /// 溜まった置き場を全部送る（「完了」）。全部送れたら true
    func flush() async -> Bool {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        var ok = true
        for id in pending.ids {
            var outcome = await commit(id)
            var tries = 0
            // 新しい頼みに負けた: その頼みが終わるのを待ち、まだ溜まっていれば自分で送り直す
            while outcome == .superseded && tries < 3 {
                tries += 1
                _ = await model?.waitUntilIdle()
                outcome = await commit(id)
            }
            switch outcome {
            case nil, .saved?:
                // nil はもう溜まっていない（ほかの頼みが送った）＝成功
                continue
            default:
                ok = false
            }
        }
        // もう溜まっていない1枚の知らせを、その結果で呼ぶ（断られた1枚を「送れた」と知らせない）。
        // 送れなかった分は、やり直しのために残す
        for id in completions.keys.sorted() where pending[id] == nil { complete(id, lastSent[id] ?? .saved) }
        return ok
    }

    /// 保存せずに閉じる: 溜まった置き場を送らない（予定も取り消し、待っている頼みも取り下げる）
    func discardAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        completions = [:]
        for id in pending.ids { model?.withdrawPlace(id) }
        pending = TrunkPendingPlaces()
    }

    /// 画面が閉じた（「完了」を通らずに）。残っている置き場を送る
    func sendLeftovers() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        let done = completions
        completions = [:]
        let leftovers = pending.ids.compactMap { id in pending[id].map { (id, $0.to) } }
        guard !leftovers.isEmpty, let model else { return }
        Task { @MainActor in
            for (id, pos) in leftovers {
                let outcome = await model.placeWhenFree(id, at: pos)
                // 運んで離した1枚のよれは、閉じたあとに送れても覚える（閉じた先の画面で音は出さない）
                if outcome == .saved || outcome == .refused { done[id]?(outcome, true) }
            }
        }
    }
}
