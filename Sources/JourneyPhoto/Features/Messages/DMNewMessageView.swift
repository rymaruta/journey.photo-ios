import SwiftUI

/// 「新しいメッセージ」（2026-11-10 owner「普通にDMできる機能がいい」）。受信箱の見出しの鉛筆から、シートで開く。
///
/// フォローしている人の一覧（`GET /users/{me}/following`）から相手を選ぶと、その人との会話を開く
/// （まだ会話が無ければ空の会話の画面から1通目を送れる・`DMConversationView(startingWith:)`）。
/// **フォローしている人だけを並べる**——サーバーは新しい会話を、相手をフォローしている人からしか受けない
/// （`dm.ts` の `sendDm`・押して断られる体験を作らない）。
///
/// 2026-11-10 判断:
/// - 並びと行は板 FollowList の人の行（64・顔 44・区切り白 8%）。右はフォローの札の代わりに矢印（押すと会話）
/// - 名前で探す欄は親しい友達と同じ部品（`PeopleSearchField`・`ListIdentity.filter`）
/// - 名前つきの一覧はサーバーが50人で切る（`FOLLOWING_PAGE`）。その外の人は、語を打ったときだけ人の検索
///   （`/users/search`）で探し、**フォロー中の全員の ID**（`/user/following`）に入っている人だけ足す
/// - 状態: 読み込み中（人の行の骨格）・失敗（もう一度）・0人（フォローすると送れる）・見つからない・圏外（帯）
///
/// **2026-11-20 判断（グループの DM・札 #582・案「グループチャットを簡単に」の推奨 C）**: グループの口があるサーバー
/// （`DMInboxStore.groupsAvailable`）では、人を押すと印が付き、下の主ボタンが人数を言う（`GroupPick`）。
/// 1人なら「メッセージを送る」で今の1対1、2人以上なら「3人で話す」でグループを作る。グループに人を足す画面・
/// 1対1に人を足す画面も同じ画面（`mode`）。先頭に「最近話した人」（受信箱の会話の新しい順）。30人目を選ぶとそれ以上は押せない。
/// グループの口が無いサーバーでは今のまま（押すとすぐその人との会話・`.single`）
struct DMNewMessageView: View {

    /// 選び方（今の1対1・何人でも・グループに足す・1対1に足す）
    var mode: GroupPick.Mode = .single
    /// 人を足す先のグループ（`.add` のときだけ）
    var groupId: String?
    /// 選んだ相手（受信箱が、このシートを閉じてから会話を積む）
    let onPick: (DMPeerSeed) -> Void
    /// グループができた・人を足した（呼ぶ側がシートを閉じて会話を積む）
    var onGroup: ((GroupReady) -> Void)?

    init(mode: GroupPick.Mode = .single, groupId: String? = nil, onPick: @escaping (DMPeerSeed) -> Void,
         onGroup: ((GroupReady) -> Void)? = nil) {
        self.mode = mode
        self.groupId = groupId
        self.onPick = onPick
        self.onGroup = onGroup
    }

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var store: DMInboxStore

    enum Phase: Equatable { case loading, loaded, failed }

    @State private var phase: Phase = .loading
    /// 名前つきのフォロー中（50人まで）
    @State private var following: [FollowUser] = []
    /// フォロー中の人数（数え札。一覧の長さとは一致しない）
    @State private var total = 0
    /// フォロー中の全員の ID（50人の外を検索で探すときの門）。読めなければ nil（検索で足さない）
    @State private var followingIds: Set<String>?
    @State private var query = ""
    /// 50人の外で、語に当たったフォロー中の人
    @State private var beyond: [FollowUser] = []
    @State private var searching = false
    /// 選んだ人（選んだ順・何人でも選べる形のときだけ）
    @State private var selected: [FollowUser] = []
    /// グループを作っている・人を足している最中
    @State private var working = false
    @State private var workError: String?

    private var multi: Bool { GroupPick.isMulti(mode) }
    private var excluded: Set<String> { GroupPick.excluded(mode) }

    private var candidates: [FollowUser] {
        DMStart.candidates(following, me: auth.userId, blocked: hidden.blockedUserIds).filter { !excluded.contains($0.id) }
    }

    private var shown: [FollowUser] {
        DMStart.filter(candidates, query: query) + DMStart.candidates(beyond, me: auth.userId, blocked: hidden.blockedUserIds)
            .filter { !excluded.contains($0.id) }
    }

    /// 「最近話した人」（何人でも選べる形で、語が空のときだけ）
    private var recent: [FollowUser] {
        guard multi, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return GroupPick.recent(threads: store.inbox.conversations, following: candidates, excluding: excluded)
    }

    /// 一覧に載らない人がいるか（50人で切った・追いついていない）
    private var hasMoreThanShown: Bool { total > following.count }

    var body: some View {
        VStack(spacing: 0) {
            if connectivity.isOffline {
                DMOfflineStrip(text: L("圏外です。つながると一覧を読めます", "You're offline. The list loads when you reconnect."))
                    .padding(.top, JPSpace.xs)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.bottom, JPSpace.screenEnd)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if multi, phase == .loaded { footer }
        }
        .webScreen()
        .navigationTitle(GroupPick.title(mode))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: auth.userId) { await load() }
        .onChange(of: connectivity.isOffline) { _, offline in
            if !offline, phase == .failed { Task { await load() } }
        }
        // 50人の外を探す（打ち終わるのを 0.3 秒待つ・語が変わったら前の検索は取り消す）
        .task(id: query) { await searchBeyond(query) }
        .accessibilityIdentifier("dm.new")
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            JPLoadingState(kind: .people)
                .padding(.top, JPSpace.xs)
        case .failed:
            ErrorBanner(title: Labels.Common.loadFailed, message: DMText.loadFailedMessage) {
                Task { await load() }
            }
            .padding(.top, JPSpace.emptyTop)
        case .loaded:
            if candidates.isEmpty && !hasMoreThanShown {
                EmptyState(icon: "person.2", title: L("フォローしている人がいません", "You're not following anyone yet"),
                           message: L("メッセージを送れるのは、フォローしている人です。気になる人をフォローすると、ここから選べます。",
                                      "You can message people you follow. Follow someone and they'll show up here."))
                    .padding(.top, JPSpace.emptyTop)
            } else {
                PeopleSearchField(query: $query, placeholder: L("フォロー中の人を探す", "Search people you follow"),
                                  identifier: "dm.new.search")
                    .padding(.top, JPSpace.xs)
                    .padding(.bottom, JPSpace.xxs)
                if multi && (!selected.isEmpty || lockedPeer != nil) {
                    pickedChips
                }
                Text(L("メッセージを送れるのは、フォローしている人です。", "You can message people you follow."))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.horizontal, JPSpace.xxs)
                    .padding(.vertical, JPSpace.xs)
                if !recent.isEmpty {
                    JPEyebrowLine(L("最近話した人", "Recent"))
                        .padding(.top, JPSpace.xs)
                    ForEach(recent) { user in
                        row(user)
                    }
                    JPEyebrowLine(L("フォロー中", "Following"))
                        .padding(.top, JPSpace.m)
                }
                ForEach(shown.filter { user in !recent.contains(where: { $0.id == user.id }) }) { user in
                    row(user)
                }
                if shown.isEmpty {
                    Text(searching ? L("探しています…", "Searching…") : L("見つかりませんでした", "No matches"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, JPSpace.xl)
                }
                if hasMoreThanShown && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 黙って食い違わせない（フォロー一覧と同じ文に、探し方を1つ足す）
                    Text(L("全 \(total) 人のうち \(following.count) 人を表示しています。ほかの人は名前で探せます",
                           "Showing \(following.count) of \(total). Search by name to find others."))
                        .font(JPFont.caption.monospacedDigit())
                        .foregroundStyle(WebTheme.text3)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, JPSpace.s)
                }
            }
        }
    }

    /// 人の行（板 FollowList: 64・顔 44・名前 14 と @ユーザー名 12・区切り白 8%）。行のどこを押しても会話へ。
    /// 何人でも選べる形では、右の矢印が選ぶ印（`GroupCheckMark`）に替わり、押すと印を付け外しする
    @ViewBuilder
    private func row(_ user: FollowUser) -> some View {
        if multi {
            multiRow(user)
        } else {
            singleRow(user)
        }
    }

    private func singleRow(_ user: FollowUser) -> some View {
        Button {
            onPick(DMStart.seed(user))
        } label: {
            HStack(spacing: JPSpace.s) {
                DMAvatar(userId: user.id, size: DMLook.pickerAvatar)
                PersonNameLines(user: user)
                    .foregroundStyle(WebTheme.foreground)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: JPHeight.tallRow)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(user.displayName) さんにメッセージ", "Message \(user.displayName)"))
        .accessibilityIdentifier("dm.new.person")
    }

    private func multiRow(_ user: FollowUser) -> some View {
        let on = selected.contains { $0.id == user.id }
        let full = !on && !GroupPick.canSelectMore(count: selected.count, mode: mode)
        return Button {
            selected = GroupPick.toggled(selected, user, mode: mode)
            workError = nil
        } label: {
            HStack(spacing: JPSpace.s) {
                DMAvatar(userId: user.id, size: DMLook.pickerAvatar)
                PersonNameLines(user: user)
                    .foregroundStyle(WebTheme.foreground)
                Spacer(minLength: 0)
                GroupCheckMark(selected: on)
            }
            .frame(minHeight: JPHeight.tallRow)
            .contentShape(Rectangle())
            .opacity(full ? DMLook.unreachableFaceOpacity : 1)
            .overlay(alignment: .bottom) {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            }
        }
        .buttonStyle(.plain)
        .disabled(full || working)
        .accessibilityLabel(user.displayName)
        .accessibilityValue(on ? L("選択中", "Selected") : "")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("dm.new.person")
    }

    /// 1対1に足すときの相手（外せない札）
    private var lockedPeer: FollowUser? {
        if case .extend(let peer) = mode {
            return FollowUser(id: peer.id, name: peer.name, deleted: false, username: peer.username)
        }
        return nil
    }

    /// 選んだ人の札（× で外す・選んだ順・横に流す）
    private var pickedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let lockedPeer {
                    GroupPickedChip(user: lockedPeer, locked: true) {}
                }
                ForEach(selected) { user in
                    GroupPickedChip(user: user) {
                        selected = selected.filter { $0.id != user.id }
                    }
                }
            }
            .padding(.vertical, JPSpace.xxs)
        }
        .accessibilityIdentifier("group.picked")
    }

    /// 下の主ボタン（人数を言う・真鍮の塗りに墨・高さ 48）。30人に届いたら一言。作れなかったら理由を上に
    private var footer: some View {
        VStack(spacing: 6) {
            if let workError {
                DMNoteRow(text: workError, error: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("group.pick.error")
            } else if !selected.isEmpty && !GroupPick.canSelectMore(count: selected.count, mode: mode) {
                Text(GroupText.fullNotice)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityIdentifier("group.pick.full")
            }
            Button { Task { await commit() } } label: {
                HStack(spacing: JPSpace.xs) {
                    if working { ProgressView().tint(WebTheme.accentText) }
                    Text(GroupPick.mainTitle(selected: selected.count, mode: mode) ?? GroupPick.idleTitle(mode))
                }
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(selected.isEmpty ? WebTheme.text3 : WebTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: GroupLook.mainButtonHeight)
                .background(selected.isEmpty ? WebTheme.surface8 : WebTheme.accentFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty || working || connectivity.isOffline)
            .accessibilityIdentifier("group.pick.go")
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.top, JPSpace.s)
        .padding(.bottom, JPSpace.xs)
        .background(WebTheme.background, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    /// 主ボタン: 1人なら1対1の会話、2人以上ならグループを作る、グループに足すなら足す
    private func commit() async {
        guard !working else { return }
        workError = nil
        switch GroupPick.outcome(selected: selected, mode: mode) {
        case .none:
            return
        case .oneToOne(let seed):
            onPick(seed)
        case .create(let ids):
            working = true
            defer { working = false }
            do {
                let change = try await environment.groups.create(memberIds: ids)
                onGroup?(GroupReady(change: change))
            } catch {
                workError = GroupText.message(for: error, fallback: L("グループを作れませんでした", "Couldn't create the group"))
            }
        case .add(let ids):
            guard let groupId else { return }
            working = true
            defer { working = false }
            do {
                let change = try await environment.groups.addMembers(groupId, userIds: ids)
                onGroup?(GroupReady(change: change))
            } catch {
                workError = GroupText.message(for: error, fallback: L("人を足せませんでした", "Couldn't add people"))
            }
        }
    }

    private func load() async {
        guard let me = auth.userId else { return }
        if following.isEmpty { phase = .loading }
        async let list = environment.social.following(userId: me)
        async let ids = try? environment.social.myFollowingIds()
        do {
            let fetched = try await list
            let all = await ids
            guard !Task.isCancelled, auth.userId == me else { return }
            following = fetched.users
            total = fetched.total
            followingIds = all.map(Set.init)
            phase = .loaded
        } catch is CancellationError {
            // 画面を離れた。失敗と言わない
        } catch {
            guard auth.userId == me else { return }
            // 一度読めていれば一覧を残す
            if following.isEmpty { phase = .failed }
        }
    }

    /// 50人の外を語で探す。一覧に全員が載っている・語が空・全員の ID が読めていないときは探さない
    private func searchBeyond(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, hasMoreThanShown, let followingIds else {
            beyond = []
            searching = false
            return
        }
        searching = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        let profiles = (try? await environment.search.search(query: trimmed)) ?? []
        guard !Task.isCancelled, trimmed == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        beyond = DMStart.searchHits(profiles, following: followingIds, me: auth.userId,
                                    blocked: hidden.blockedUserIds, excluding: Set(following.map(\.id)))
        searching = false
    }
}
