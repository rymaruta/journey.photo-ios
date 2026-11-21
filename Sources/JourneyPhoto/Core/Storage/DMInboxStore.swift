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
    /// グループの一覧（2026-11-20 札 #582）。**`groupsAvailable` が偽の間は使わない**
    @Published private(set) var groups: GroupInbox = .empty
    /// グループの口がこのサーバーに在るか。**今の人で一覧が1回でも読めたときだけ真**（本番にまだ口が無い間・
    /// 古いサーバーの 404・403・圏外では入口を出さず、今の1対1のまま・2026-11-20 判断）
    @Published private(set) var groupsAvailable = false
    /// 相互フォローの控え（2026-11-20 owner 判断・1対1の「人を足す」を出すか）。読んでから 5 分は読み直さない
    @Published private(set) var mutual: MutualFollow = .unknownAll
    private var mutualAt: Date?
    @Published private(set) var phase: Phase = .loading
    /// 読み直している最中（「もう一度」を止める）
    @Published private(set) var isRefreshing = false

    /// いまの控えが誰のものか
    private(set) var owner: String?
    private var generation = 0
    private var groupGeneration = 0
    /// まだ一覧を読めていない間に手元で置いた変化（既読・削除・承認）。**読めた答えの上に重ねる**
    private var pendingChanges: [(DMInbox) -> DMInbox] = []

    init() {}

    /// 吹き出しの点を出すか（1対1の未読の会話か、未読のグループ）
    func hasUnread(hiding blocked: Set<String>) -> Bool {
        inbox.unreadConversations(hiding: blocked) > 0 || (groupsAvailable && groups.unreadGroups() > 0)
    }

    /// リクエストの棚の数（1対1のリクエストと、グループの招待）
    func requestTotal(hiding blocked: Set<String>) -> Int {
        inbox.requestTotal(hiding: blocked) + (groupsAvailable ? groups.invites.filter { !blocked.contains($0.invitedBy.id) }.count : 0)
    }

    /// グループの一覧を読み直す。**読めたらグループの入口を出す**。読めなければ前の一覧と入口をそのまま（圏外で消さない）
    func refreshGroups(service: GroupService, owner: String?) async {
        use(owner: owner)
        guard owner != nil else { return }
        let mine = groupGeneration
        do {
            let fetched = try await service.inbox()
            guard mine == groupGeneration, owner == self.owner else { return }
            groups = fetched
            groupsAvailable = true
        } catch {
            // 口が無い（404・403）・圏外・混み合い: 入口は出さないまま（一度読めていれば残す）
        }
    }

    /// 相互フォローを読む（自分のフォロー中の全員の ID とフォロワーの一覧・2本）。新しい控えがあれば読まない
    func refreshMutual(social: SocialService, owner: String?, maxAge: TimeInterval = 300, now: Date = Date()) async {
        use(owner: owner)
        guard let owner else { return }
        if let at = mutualAt, now.timeIntervalSince(at) < maxAge { return }
        async let ids = try? social.myFollowingIds()
        async let followers = try? social.followers(userId: owner)
        let (all, list) = await (ids, followers)
        guard owner == self.owner, let all, let list else { return }
        setMutual(MutualFollow(following: Set(all), followerList: list.users, followerTotal: list.total), owner: owner, now: now)
    }

    func setMutual(_ value: MutualFollow, owner: String?, now: Date = Date()) {
        guard owner == self.owner else { return }
        mutual = value
        mutualAt = now
    }

    /// 手元で変えたグループの一覧（読んだ・抜けた・参加した）。進んでいる読み込みの答えは捨てる
    func applyGroups(_ change: (GroupInbox) -> GroupInbox) {
        groups = change(groups)
        groupGeneration += 1
    }

    /// 人が替わった。前の人の控えを捨てる
    func use(owner: String?) {
        guard owner != self.owner else { return }
        self.owner = owner
        generation += 1
        inbox = .empty
        phase = .loading
        isRefreshing = false
        pendingChanges = []
        groups = .empty
        groupsAvailable = false
        groupGeneration += 1
        mutual = .unknownAll
        mutualAt = nil
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
            // 読み込み中に置いた変化（通知から先に開いた会話の既読など）を、読めた答えに重ねる
            inbox = pendingChanges.reduce(fetched) { $1($0) }
            pendingChanges = []
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
    ///
    /// - 読めている間: **進んでいる読み込みの答えは捨てる**（変える前の一覧で上書きしない）
    /// - **まだ読めていない間は世代を進めない**（2026-11-10 レビュー指摘3・run 939 で再現: 最初の読み込みの途中に
    ///   既読を置くと、読めた一覧を捨てて空の一覧を「読めた」にしていた）。変化は覚えておき、読めた答えに重ねる
    func apply(_ change: @escaping (DMInbox) -> DMInbox) {
        inbox = change(inbox)
        guard phase == .loaded else {
            pendingChanges.append(change)
            return
        }
        generation += 1
        isRefreshing = false
    }

    /// 試験・見本のため（画面を持たない試験で、控えを置いた状態から始める）
    func setForTesting(_ inbox: DMInbox, owner: String?, groups: GroupInbox? = nil) {
        self.owner = owner
        self.inbox = inbox
        phase = .loaded
        if let groups {
            self.groups = groups
            groupsAvailable = true
        }
    }
}
