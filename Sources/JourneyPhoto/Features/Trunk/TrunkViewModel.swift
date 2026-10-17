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
            state = TrunkSample.state(isPro: previewPro, empty: preview == .empty)
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
                       _ remote: (TrunkService) async throws -> TrunkState) async -> Bool {
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
        } catch {
            actionError = Self.message(error)
            return false
        }
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
}
