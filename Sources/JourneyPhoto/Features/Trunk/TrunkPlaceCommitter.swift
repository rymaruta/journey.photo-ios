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
///   後から同じ1枚を回して予定が替わっても、知らせは引き継ぐ。「完了」が送ったときも呼ぶ
@MainActor
final class TrunkPlaceCommitter: ObservableObject {

    @Published private(set) var pending = TrunkPendingPlaces()

    private weak var model: TrunkViewModel?
    private var tasks: [String: Task<Void, Never>] = [:]
    /// 送り終えたときの知らせ（ラベルごと・1回だけ呼ぶ）
    private var completions: [String: (TrunkViewModel.PlaceOutcome?) -> Void] = [:]
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
                  then done: ((TrunkViewModel.PlaceOutcome?) -> Void)? = nil) {
        if let done { completions[id] = done }
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            // 始めた送信は予定の取り消しで切らない（途中で切ると圏外と同じ失敗になる）。
            // 待っている頼みを止めるのは `discardAll` の取り下げ（`withdrawPlace`）
            let outcome = await Task { await self.commit(id) }.value
            guard !Task.isCancelled else { return }
            if outcome == .busy, attempt < 5 {
                self.schedule(id, delay: 0.3, attempt: attempt + 1)
                return
            }
            self.complete(id, outcome)
        }
    }

    private func complete(_ id: String, _ outcome: TrunkViewModel.PlaceOutcome?) {
        completions.removeValue(forKey: id)?(outcome)
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
        case .refused:
            pending.done(id, sent: item.to)
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
        // 送れた1枚（もう溜まっていない）の知らせを呼ぶ。送れなかった分は、やり直しのために残す
        for id in completions.keys.sorted() where pending[id] == nil { complete(id, .saved) }
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
                // 運んで離した1枚のよれは、閉じたあとに送れても覚える
                if outcome == .saved { done[id]?(outcome) }
            }
        }
    }
}
