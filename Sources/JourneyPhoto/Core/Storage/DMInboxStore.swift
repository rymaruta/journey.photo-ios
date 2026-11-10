import Foundation
import Combine

/// メッセージの受信箱の控え（札 #505・2026-11-10）。**ホームの吹き出しの点と、受信箱・リクエストの画面が同じ1つを見る**。
///
/// - 点は「受信箱に未読の会話がある」ときだけ（リクエストでは出さない・板の決まり）。数え方は `DMInbox.unreadConversations`
/// - **最後に読めた一覧を残す**（圏外の帯の下に出す・板「圏外: 最後に読めた会話を残し、上に帯」）
/// - 人が替わったら捨てる（前の人の会話を次の人に見せない）。読み込みは世代で古い答えを捨てる（`RootView.refreshUnread` と同じ）
@MainActor
final class DMInboxStore: ObservableObject {

    enum Phase: Equatable {
        /// まだ1回も読めていない（読み込み中）
        case loading
        /// 読めた
        case loaded
        /// 1回も読めないまま失敗した（`message` は画面の文）
        case failed(String)
    }

    @Published private(set) var inbox: DMInbox = .empty
    @Published private(set) var phase: Phase = .loading
    /// 読み直している最中（「もう一度」を止める）
    @Published private(set) var isRefreshing = false

    /// いまの控えが誰のものか
    private(set) var owner: String?
    private var generation = 0

    init() {}

    /// 吹き出しの点を出すか
    func hasUnread(hiding blocked: Set<String>) -> Bool {
        inbox.unreadConversations(hiding: blocked) > 0
    }

    /// 人が替わった。前の人の控えを捨てる
    func use(owner: String?) {
        guard owner != self.owner else { return }
        self.owner = owner
        generation += 1
        inbox = .empty
        phase = .loading
        isRefreshing = false
    }

    /// 読み直す。**失敗しても読めていた一覧は残す**（圏外で戻っただけで点・行が消えない）
    func refresh(service: DMService, owner: String?) async {
        use(owner: owner)
        guard owner != nil else { return }
        generation += 1
        let mine = generation
        isRefreshing = true
        do {
            let fetched = try await service.inbox()
            guard mine == generation, owner == self.owner else { return }
            inbox = fetched
            phase = .loaded
            isRefreshing = false
        } catch {
            guard mine == generation, owner == self.owner else { return }
            isRefreshing = false
            if phase != .loaded {
                phase = .failed((error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed)
            }
        }
    }

    /// 手元で変えた姿を置く（既読・削除・承認の直後。サーバーの答えを待たずに点・行を合わせる）。
    /// **進んでいる読み込みの答えは捨てる**（変える前の一覧で上書きしない）
    func apply(_ change: (DMInbox) -> DMInbox) {
        generation += 1
        isRefreshing = false
        inbox = change(inbox)
        if phase != .loaded { phase = .loaded }
    }

    /// 試験・見本のため（画面を持たない試験で、控えを置いた状態から始める）
    func setForTesting(_ inbox: DMInbox, owner: String?) {
        self.owner = owner
        self.inbox = inbox
        phase = .loaded
    }
}
