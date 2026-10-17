import Foundation
import Combine

/// 旅のトランクの画面の状態（トランク・手持ち・作り直し・型の画面が同じものを見る・2026-10-17）。
///
/// **書き込みの応答をそのまま映す**（`TrunkService` の注記）。失敗した書き込みは状態を変えず、
/// 画面の上の一行（`actionError`）で知らせる。画面写真の見本（`PreviewSession.trunkSample`）では
/// サーバーに何も送らず、同じ決まりで端末の中だけ動かす（`TrunkLocal`）。
@MainActor
final class TrunkViewModel: ObservableObject {

    /// 読み込みの具合（板 v2 の4つの状態: 読み込み中・中身・失敗・圏外）
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        case offline
    }

    @Published private(set) var state: TrunkState?
    @Published private(set) var phase: Phase = .loading
    /// 書き込みの失敗（画面の上に一行）
    @Published var actionError: String?
    /// 書き込みの最中（同じボタンを続けて押させない）
    @Published private(set) var busy = false

    /// 口（画面が `.task` で `bind` する。`@StateObject` の作り始めには環境が無いため）
    private var service: TrunkService?
    private let preview: PreviewSession.TrunkPreview?
    private let previewPro: Bool

    init(preview: PreviewSession.TrunkPreview? = PreviewSession.trunkSample,
         previewPro: Bool = PreviewSession.isPro) {
        self.preview = preview
        self.previewPro = previewPro
    }

    func bind(_ service: TrunkService) {
        if self.service == nil { self.service = service }
    }

    /// 見本で動いているか（画面写真の起動の鍵）
    var isPreview: Bool { preview != nil }

    /// 届いたラベルが1枚も無い（手持ちも貼ったものも空）
    var isEmpty: Bool { (state?.pocket.isEmpty ?? true) && (state?.stuck.isEmpty ?? true) }

    /// - Parameter offline: いま電波が無いか（`Connectivity`）。読めなかったときに「圏外」で出すかを決める
    func load(offline: Bool) async {
        if let preview {
            // 一度動かした見本（貼った・回した・付け替えた）は、画面を開き直しても消さない
            if state == nil {
                state = TrunkSample.state(isPro: previewPro, empty: preview == .empty, coins: PreviewSession.trunkCoins)
            }
            phase = .loaded
            return
        }
        guard let service else { return }
        if state == nil { phase = .loading }
        do {
            let fresh = try await service.state()
            // **読むたびにサーバーの中身で丸ごと置き換える**（2026-10-17: 投稿から24時間以内に削除・非公開にした
            // 写真のラベルは、手持ちからも貼ったラベルからも消える）。端末には控えを持たず、引き継ぐのは投稿の数だけ
            state = fresh.keepingPosts(from: state)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            // **一度読めた中身は、読み直しの失敗で消さない**（マイページと同じ判断）
            guard state == nil else {
                actionError = Self.message(error)
                return
            }
            phase = Self.isUnreachable(error) && offline ? .offline : .failed(Self.message(error))
        }
    }

    static func isUnreachable(_ error: Error) -> Bool {
        (error as? APIError) == .unreachable
    }

    static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
    }

    // MARK: 書き込み

    /// 書き込みを1つ流す。成功したら true（状態は応答に置き換わる）
    @discardableResult
    private func write(_ local: (TrunkState) -> TrunkState,
                       _ remote: (TrunkService) async throws -> TrunkState,
                       refusal: ((TrunkService.Refused) -> String?)? = nil) async -> Bool {
        guard !busy, let current = state else { return false }
        busy = true
        defer { busy = false }
        actionError = nil
        if preview != nil {
            state = local(current)
            return true
        }
        guard let service else { return false }
        do {
            state = try await remote(service).keepingPosts(from: current)
            return true
        } catch is CancellationError {
            return false
        } catch let refused as TrunkService.Refused {
            lastWriteRefused = true
            actionError = refusal?(refused) ?? Self.message(refused)
            return false
        } catch {
            lastWriteRefused = false
            actionError = Self.message(error)
            return false
        }
    }

    /// 最後に失敗した書き込みが、サーバーの断り（`Refused`）だったか。false なら圏外・時間切れなど（やり直せる）
    private(set) var lastWriteRefused = false

    /// 届いた画面の「トランクに貼る」。**読めていなければ読み直してから貼る。それでも読めなければ一言を出す**
    /// （黙って何もしない、をなくす・2026-10-17 の読み直し）
    @discardableResult
    func stickEnsuringLoaded(_ id: String, offline: Bool = false) async -> Bool {
        if state == nil { await load(offline: offline) }
        guard state != nil else {
            switch phase {
            case .failed(let message): actionError = message
            case .offline: actionError = Labels.Common.unreachable
            default: actionError = Labels.Common.loadFailed
            }
            return false
        }
        return await stick(id)
    }

    /// Pro の案内を閉じたあと（買えたかもしれない）。Pro かどうか・上限・回数を読み直す
    func refreshAfterPaywall(offline: Bool = false) async {
        await load(offline: offline)
    }

    @discardableResult
    func stick(_ id: String) async -> Bool {
        await write({ TrunkLocal.stick($0, id: id) }, { try await $0.stick(id) })
    }

    @discardableResult
    func remove(_ id: String) async -> Bool {
        await write({ TrunkLocal.remove($0, id: id) }, { try await $0.remove(id) })
    }

    /// 作り直す（候補が `state.pendingReroll` に入る）。**同じラベルの選びかけがあれば呼ばない**（回数を使わない）
    @discardableResult
    func reroll(_ id: String) async -> Bool {
        if state?.pendingReroll?.labelId == id { return true }
        return await write({ TrunkLocal.reroll($0, id: id, seeds: TrunkSample.rerollSeeds) },
                           { try await $0.reroll(id) })
    }

    @discardableResult
    func choose(_ id: String, seed: Int) async -> Bool {
        await write({ TrunkLocal.choose($0, id: id, seed: seed) }, { try await $0.choose(id, seed: seed) })
    }

    @discardableResult
    func setModel(_ model: TrunkModel) async -> Bool {
        guard state?.model != model || state?.effectiveModel != model else { return true }
        return await write({ TrunkLocal.setModel($0, model) }, { try await $0.setModel(model) })
    }

    @discardableResult
    func setReceiveLabels(_ on: Bool) async -> Bool {
        guard state?.receiveLabels != on else { return true }
        return await write({ TrunkLocal.setReceive($0, on) }, { try await $0.setReceiveLabels(on) })
    }

    // MARK: 自分の手で貼る（2026-10-17 次の版）

    /// 置き場つきで貼る
    @discardableResult
    func stick(_ id: String, at pos: TrunkPos) async -> Bool {
        await write({ TrunkLocal.stick($0, id: id, pos: pos) }, { try await $0.stick(id, at: pos) })
    }

    /// 貼ったラベルを置き直す
    @discardableResult
    func place(_ id: String, at pos: TrunkPos) async -> Bool {
        guard state?.stuck.first(where: { $0.id == id })?.pos != TrunkPlacement.clamp(pos) else { return true }
        return await write({ TrunkLocal.place($0, id: id, pos: pos) }, { try await $0.place(id, at: pos) })
    }

    /// 書き込みの最中なら終わるまで待つ（5 秒まで）。空いたら true
    func waitUntilIdle(timeout: Double = 5) async -> Bool {
        var waited = 0.0
        while busy && waited < timeout {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 0.05
        }
        return !busy
    }

    /// 置き直しの結果
    enum PlaceOutcome: Equatable {
        case saved
        /// 断られた・読めなかった（一言は `actionError`）
        case refused
        /// 別の書き込みが終わらず送れなかった（あとでやり直す）
        case busy
        /// 圏外・時間切れなどで送れなかった（置き場は残してやり直せる）
        case failed
        /// 同じラベルに、あとから新しい置き場が頼まれた（古い値は送らない）
        case superseded
    }

    /// ラベルごとの置き直しの番号（新しい頼みが来たら、待っている古い頼みは送らない）
    private var placeTickets = TrunkPlaceTickets()

    /// 置き直す。**書き込みの最中なら待ってから送る**（2026-10-17 の見直し: 黙って false で、回した向きが
    /// 保存されないことがあった）
    ///
    /// **同じラベルへの頼みは新しい方が勝つ**（閉じたあとの送り残しと、開き直した画面の新しい置き場がぶつかっても、
    /// 古い値で上書きしない・2026-10-17 の見直し）
    func placeWhenFree(_ id: String, at pos: TrunkPos) async -> PlaceOutcome {
        let ticket = placeTickets.issue(id)
        guard await waitUntilIdle() else { return .busy }
        guard placeTickets.isLatest(id, ticket) else { return .superseded }
        if await place(id, at: pos) { return .saved }
        if actionError == nil { return .busy }
        return lastWriteRefused ? .refused : .failed
    }

    /// 待っている置き直しの頼みを取り下げる（「保存せずに閉じる」）。待っている古い頼みは `.superseded` で送らずに終わる
    func withdrawPlace(_ id: String) {
        _ = placeTickets.issue(id)
    }

    /// 置き場つきで貼る（書き込みの最中なら待ってから）
    func stickWhenFree(_ id: String, at pos: TrunkPos) async -> Bool {
        guard await waitUntilIdle() else { return false }
        return await stick(id, at: pos)
    }

    /// はがして手持ちに戻す（手持ちが上限なら一言）
    @discardableResult
    func unstick(_ id: String) async -> Bool {
        if let state, state.pocket.count >= state.limit, preview != nil {
            actionError = TrunkText.unstickFull
            return false
        }
        return await write({ TrunkLocal.unstick($0, id: id) }, { try await $0.unstick(id) },
                           refusal: { $0.code == "full" ? TrunkText.unstickFull : nil })
    }

    /// おまかせで並べる（空いている置き場に、手持ちの新しいものから順に貼る）。貼れた id を返す。
    /// 空きが無ければ一言を出して空を返す
    func autoArrange() async -> [String] {
        guard let state else { return [] }
        let plan = TrunkPlacement.autoArrange(pocket: state.pocket, stuck: state.stuck)
        guard !plan.isEmpty else {
            actionError = state.pocket.isEmpty ? TrunkText.noPocketLabels : TrunkText.noFreeSlot
            return []
        }
        var done: [String] = []
        for item in plan {
            guard await stick(item.id, at: item.pos) else { break }
            done.append(item.id)
        }
        return done
    }

    // MARK: カプセルの機械・部品（2026-10-17 次の版）

    /// 見本で回した回数（出る部品の並びを進める）
    private var previewDraws = 0

    /// 回す（硬貨1枚）。出た部品を返す（断られた・読めなければ nil で、一言は `actionError`）。
    /// 応答は状態を丸ごと返さないので、硬貨・かけら・部品だけを手元の状態に足す
    func gacha() async -> TrunkGachaResult? {
        guard !busy, let current = state else { return nil }
        busy = true
        defer { busy = false }
        actionError = nil
        if preview != nil {
            guard let result = TrunkLocal.gacha(current, draw: previewDraws) else {
                actionError = TrunkText.refusal(code: "noCoins", fallback: Labels.Common.loadFailed)
                return nil
            }
            previewDraws += 1
            state = result.applied(to: current)
            return result
        }
        guard let service else { return nil }
        do {
            let result = try await service.gacha()
            state = result.applied(to: current)
            return result
        } catch is CancellationError {
            return nil
        } catch {
            actionError = Self.message(error)
            // 回ったかどうか分からない（知らない部品・時間切れ）。硬貨と部品を読み直す
            if !(error is TrunkService.Refused) { await load(offline: false) }
            return nil
        }
    }

    /// かけら5つで交換
    @discardableResult
    func exchange(_ partId: String) async -> Bool {
        await write({ TrunkLocal.exchange($0, partId: partId) }, { try await $0.exchange(partId) })
    }

    /// 付け替えを保存する
    @discardableResult
    func equip(_ equipped: TrunkEquipped) async -> Bool {
        guard state?.equipped != equipped else { return true }
        return await write({ TrunkLocal.equip($0, equipped) }, { try await $0.equip(equipped) })
    }
}
