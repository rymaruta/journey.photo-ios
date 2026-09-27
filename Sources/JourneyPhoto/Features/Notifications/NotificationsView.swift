import SwiftUI

/// お知らせ。
struct NotificationsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    /// **通知を押すたびに読み直すため**に見ている。
    ///
    /// お知らせタブを開いたまま通知を押した回は、`RootView` の
    /// `selection` が既に `.notifications` なので何も変わらない
    /// ——`.task` は一度きりなので、**押した当の通知が出ないまま**
    /// アイコンの数字も残っていた。
    @ObservedObject private var router = NotificationRouter.shared
    @StateObject private var model = NotificationsViewModel()
    @State private var filter: NotificationFilter = .all
    /// 押した先。**行を `NavigationLink` で包まない**——行の中にアイコンの
    /// ボタン（プロフィール）とフォローバックが並ぶので、包むと
    /// リンクの中にボタンが入れ子になり、押した所によって二重に遷移したり、
    /// VoiceOver が行を1つにまとめて中のボタンへ届かなかったりする。
    /// 行の本体・アイコンをそれぞれ横並びの別ボタンにして、押したら
    /// ここに行き先を立て、一覧の外（`navigationDestination`）から開く
    @State private var route: NotificationsViewModel.Route?

    var body: some View {
        Group {
            if auth.isResolving {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.userId == nil {
                SignInView(reason: L("お知らせを見るにはログインしてください", "Sign in to see your activity"))
            } else {
                list
            }
        }
        .webScreen()
        .navigationTitle(L("お知らせ", "Activity"))
        // **通知の設定**（板 15 の右上の歯車）。行き先は設定の画面——
        // プッシュ通知の入／切はそこにある。閉じる口は `RootView` が
        // 左に置いているので、右に置いてぶつからない
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(L("通知の設定", "Notification settings"))
                .accessibilityIdentifier("notifications.settings")
            }
        }
    }

    /// 種類で絞る（提案の絵）。**数の多い順ではなく決まった並び**
    /// ——押すたびに位置が変わると、目で追えない
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases) { option in
                    let selected = filter == option
                    Button {
                        filter = option
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selected ? AnyShapeStyle(WebTheme.foreground)
                                                 : AnyShapeStyle(WebTheme.surface),
                                        in: Capsule())
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var shownRows: [AppNotification] {
        // **種類の分からないお知らせは「すべて」にだけ出す。**
        // 捨てると届いたことが伝わらないし、当て推量で仕分けると嘘になる
        model.rows.filter { row in
            guard let kind = row.kind else { return filter == .all }
            return filter.matches(kind)
        }
    }

    /// 1件ぶん。**押せるようにする**——行き止まりの一覧は「壊れている」に見える。
    /// 行き先が分からないものは押せないまま出す（空振りを作らない）
    private func rowLink(_ entry: NotificationText.Entry) -> some View {
        let target = model.route(for: entry.lead)
        return NotificationRow(entry: entry, following: model.following,
                               onFollowBack: { await model.followBack($0, environment: environment) },
                               onOpen: target.map { target in { route = target } },
                               onOpenProfile: { route = .user($0) })
    }

    /// 行き先の画面。写真は**押した時点の値**で開く（`Route` を参照）
    @ViewBuilder
    private func destinationView(_ route: NotificationsViewModel.Route) -> some View {
        switch route {
        case .photo(let photo, let fromPublicFeed):
            PhotoDetailView(photo: photo, fromPublicFeed: fromPublicFeed)
        case .user(let userId):
            UserProfileView(userId: userId)
        }
    }

    /// 何も無いときの画面（モック10 の「まだ通知はありません」）。
    /// **「1件も無い」と「この種類が無い」を分ける**
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(WebTheme.faint)
            Text(model.rows.isEmpty
                 ? L("まだお知らせはありません", "Nothing yet")
                 : L("この種類のお知らせはありません", "Nothing of this kind"))
                .font(.headline)
                .foregroundStyle(WebTheme.foreground)
            if model.rows.isEmpty {
                Text(L("新しいいいねやコメント、フォローが届くとここに出ます。",
                       "Likes, comments and follows will show up here."))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var list: some View {
        List {
            filterChips
                .listRowBackground(Color.clear)

            if let message = model.errorMessage {
                Text(message).foregroundStyle(WebTheme.danger).font(.callout)
            } else if shownRows.isEmpty && !model.isLoading {
                emptyState
                    .listRowBackground(Color.clear)
            }

            // **時間ごとにまとめる**（モック10）。並べ替えはしない
            // ——サーバーが返した新しい順のまま切るだけ
            ForEach(NotificationGroups.grouped(shownRows)) { group in
                Section {
                    // 同じ写真へのいいねは1行にまとめる（板の「ほか N人」）。
                    // まとめるのは見出しの中だけ——昨日のいいねを今日の行に
                    // 吸い込むと、見出しの「今日」が嘘になる
                    ForEach(NotificationText.collapse(group.rows, unreadIds: model.unreadIds)) { entry in
                        rowLink(entry)
                    }
                } header: {
                    Text(group.bucket.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
                }
            }
        }
        .navigationDestination(item: $route) { route in
            destinationView(route)
        }
        .task(id: router.openActivityRequests) {
            // **読めたときだけ消す。** サーバーは未読数を載せるが、既読に
            // したことは端末のアイコンに伝わらない——誰も消さないと増える
            // 一方。ただし圏外で開いた回に消すと、タブは 3・アイコンは 0 に割れる
            if await model.load(environment: environment, viewerId: auth.userId) { await push.clearBadge() }
        }
        .refreshable {
            if await model.load(environment: environment, viewerId: auth.userId, refreshing: true) {
                await push.clearBadge()
            }
        }
    }
}

private struct NotificationRow: View {

    let entry: NotificationText.Entry
    /// いまフォローしている人。**フォロー通知の「フォローバック」を
    /// 出すかどうかの判断に使う**——既にフォローしている相手に出さない
    var following: Set<String> = []
    var onFollowBack: ((String) async -> Void)?
    /// 行の本体を押したとき。nil なら押せない（行き先が無い）
    var onOpen: (() -> Void)?
    /// 左のアイコンを押したとき（相手のプロフィールを開く）
    var onOpenProfile: ((String) -> Void)?

    @State private var busy = false

    private var notification: AppNotification { entry.lead }

    var body: some View {
        // 知らない種類は描かない（既定の文言で嘘を出さない）
        if let line = NotificationText.line(for: entry) {
            HStack(spacing: 12) {
                avatar
                main(line)
                followBackButton
            }
            .frame(minHeight: 66)
            // **未読の印は行の頭の真鍮の点**（板 15）。真鍮＝合図
            .overlay(alignment: .leading) {
                if entry.unread {
                    Circle()
                        .fill(WebTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: -12)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// 文言と写真の小窓。**押せる行はここ全体が1つのボタン**
    /// （アイコン・フォローバックとは横に並ぶ別のボタン＝入れ子にしない）
    @ViewBuilder
    private func main(_ line: NotificationText.Line) -> some View {
        let label = entry.unread ? L("未読、", "Unread, ") + line.plain : line.plain
        if let onOpen {
            Button(action: onOpen) { mainContent(line) }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            mainContent(line)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
        }
    }

    private func mainContent(_ line: NotificationText.Line) -> some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text(line.who).bold() + Text(line.rest))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text)
                    if let ago = NotificationText.ago(notification.t) {
                        Text(ago)
                            .font(.caption2)
                            .foregroundStyle(WebTheme.faint)
                    }
                }
                Spacer(minLength: 0)
                // 写真の小窓は右（板 15）。フォローは写真を伴わない
                if let src = notification.photoSrc, let url = URL(string: src) {
                    RemoteImage(url: url)
                        .frame(width: 44, height: 44)
                        .background(WebTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// 相手のアイコン（左・丸）。**押すとプロフィール。**
    ///
    /// 退会した人は顔も導線も出さない（サーバーが `deleted` を付けて
    /// 名前を伏せているのと揃える）。id の無い古い通知も押せないまま
    @ViewBuilder
    private var avatar: some View {
        let userId = notification.byId.flatMap { $0.isEmpty ? nil : $0 }
        let face = RemoteImage(url: notification.deleted == true ? nil
                               : userId.flatMap { UserProfile.profileAssetURL(userId: $0, suffix: nil, cacheBust: nil) })
            .frame(width: 42, height: 42)
            .background(WebTheme.surface)
            .clipShape(Circle())
        if let userId, notification.deleted != true, let onOpenProfile {
            Button { onOpenProfile(userId) } label: { face }
                .buttonStyle(.plain)
                .accessibilityLabel(NotificationText.openProfileLabel(notification))
        } else {
            face.accessibilityHidden(true)
        }
    }

    /// フォローバック（モック10）。
    ///
    /// **出すのはフォロー通知で、まだフォローしていない相手のときだけ。**
    /// 既にフォローしている相手に出すと、押しても何も変わらないボタンになる。
    @ViewBuilder
    private var followBackButton: some View {
        // 退会した人には出さない（押してもサーバーが 404 を返し、何も起きない）
        if notification.kind == .follow, notification.deleted != true,
           let userId = notification.byId ?? notification.targetUserId,
           !following.contains(userId), let onFollowBack {
            Button {
                busy = true
                Task {
                    await onFollowBack(userId)
                    busy = false
                }
            } label: {
                Text(L("フォローバック", "Follow back"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(WebTheme.foreground, in: Capsule())
                    .foregroundStyle(WebTheme.accentText)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)
        }
    }
}

@MainActor
final class NotificationsViewModel: ObservableObject {

    /// お知らせを押したときの行き先。
    enum Destination {
        /// - Parameter fromPublicFeed: 公開一覧から引き当てたか。
        ///   自分の一覧から拾った写真は、まだ個別ページが無いことがある
        ///   （投稿直後・下書き）ので、共有の口を出さない
        case photo(Photo, fromPublicFeed: Bool)
        case user(String)
        case none
    }

    /// 押した先（`navigationDestination(item:)` に渡すので Hashable）。
    ///
    /// **写真は押した時点の値で持つ**（同じかどうかは id で見る）。id だけ持って
    /// 開くときに手元の一覧から引き直すと、遷移で一覧の `.task` が取り消されたり
    /// 読み直しが失敗したりして一覧が空になった回に、詳細が白紙になる
    enum Route: Hashable {
        case photo(Photo, fromPublicFeed: Bool)
        case user(String)

        static func == (lhs: Route, rhs: Route) -> Bool {
            switch (lhs, rhs) {
            case let (.photo(a, fa), .photo(b, fb)): return a.id == b.id && fa == fb
            case let (.user(a), .user(b)): return a == b
            default: return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .photo(let photo, let fromPublicFeed):
                hasher.combine(0); hasher.combine(photo.id); hasher.combine(fromPublicFeed)
            case .user(let id):
                hasher.combine(1); hasher.combine(id)
            }
        }
    }

    @Published private(set) var rows: [AppNotification] = []
    /// 写真を引き当てるための手元の一覧（公開のぶん）
    private var feed: [Photo] = []
    /// 自分の写真。**いいね・コメントの相手は必ず自分の写真**なので、
    /// 公開一覧に無い回はこちらから引き当てる。
    ///
    /// 公開一覧はビルド時に固まる静的 JSON で、投稿直後の写真はまだ
    /// 載っていない（CLAUDE.md: 反映は再ビルド待ち）。下書きに至っては
    /// 一生載らない。引き当てられないと**押しても何も起きない行**になる。
    private var mine: [Photo] = []
    @Published private(set) var unread = 0
    /// 未読の行（真鍮の点）。**既読にする前の数から決める**——開いたときに
    /// 既読化するので、`unread` はすぐ 0 になる。読み直すまでは点を残す
    @Published private(set) var unreadIds: Set<String> = []
    /// いまフォローしている人。**フォローバックを出すかの判断だけに使う**
    @Published private(set) var following: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// 読み込みの世代。**あとから始まった読み込みがあれば、古い方の結果は捨てる。**
    ///
    /// `.task` と引っぱって読み直しは同時に走りうる。遅れて返った `.task`
    /// （既読化の前に読んだ `unread` を持つ）が、読み直しで消した未読の点を
    /// 和で戻したり、取り消しのエラーを出したりしないため
    private var generation = 0
    /// **画面に移した中でいちばん新しい回。** 古い回を捨てる基準は「もっと新しい回が
    /// 始まった」ではなく「もっと新しい回が**移し終えた**」——新しい回が圏外で
    /// 失敗したとき、先に成功していた古い回まで捨てると、行も既読化も飛ぶ
    private var appliedGeneration = 0
    /// 手元の一覧（`feed` / `mine`）を書いた中でいちばん新しい回（同じ理由）
    private var poolsGeneration = 0

    /// テストから手元の一覧を差し替える口。
    func setFeedForTesting(_ photos: [Photo]) { feed = photos }
    func setMineForTesting(_ photos: [Photo]) { mine = photos }

    /// 行き先を決める。
    ///
    /// - フォローは相手のプロフィール
    /// - いいね・コメントはその写真。公開一覧に無ければ**自分の一覧**から
    ///   引き当てる（投稿直後・下書きは公開一覧に載っていない）。
    ///   どちらにも無ければ押せないまま
    ///   にする（非公開にされた／消された写真を押して空振りさせない）
    /// - ストーリーへの返信は行き先が無い（24時間で消えるため）
    func destination(for notification: AppNotification) -> Destination {
        switch notification.kind {
        case .follow:
            if let id = notification.targetUserId ?? notification.byId, notification.deleted != true {
                return .user(id)
            }
            return .none
        case .like, .comment:
            guard let id = notification.photoId else { return .none }
            if let photo = feed.first(where: { $0.id == id }) {
                return .photo(photo, fromPublicFeed: true)
            }
            if let photo = mine.first(where: { $0.id == id }) {
                return .photo(photo, fromPublicFeed: false)
            }
            return .none
        case .storyreply, .none:
            return .none
        }
    }

    func route(for notification: AppNotification) -> Route? {
        switch destination(for: notification) {
        case .photo(let photo, let fromPublicFeed): return .photo(photo, fromPublicFeed: fromPublicFeed)
        case .user(let id): return .user(id)
        case .none: return nil
        }
    }

    /// - Returns: 読めたか。**バッジを消してよいかの拠り所**——
    ///   取得に失敗した回にアイコンだけ 0 にすると、タブのバッジは 3 のまま
    ///   アイコンは 0、という食い違いが残る。
    @discardableResult
    /// いまフォローしている人を読む。**自分の userId が要る**
    private func loadFollowing(environment: AppEnvironment, viewerId: String?) async {
        guard let me = viewerId, !me.isEmpty else { return }
        guard let list = try? await environment.social.following(userId: me) else { return }
        following = Set(list.users.map(\.id))
    }

    /// フォローバック。**成功したときだけ**印を更新する
    /// （失敗したのにボタンが消えると、フォローできたように見える）
    func followBack(_ userId: String, environment: AppEnvironment) async {
        guard (try? await environment.social.follow(userId: userId)) != nil else { return }
        following.insert(userId)
    }

    /// 読めた1ページを画面の状態に移す。
    ///
    /// - Parameter refreshing: 引っぱって読み直した回か。
    ///
    /// **未読の点は、同じ画面にいる間は前のぶんを保つ（和をとる）。**
    /// 開いた回の最後に既読にするので、行・歯車・アイコンを押して戻った
    /// だけで `.task` が走り直すと、サーバーは `unread=0` を返す。
    /// 入れ替えると、読んでもいないのに点が消える。
    /// 入れ替えるのは**引っぱって読み直したときだけ**（「読んだ」の合図）。
    /// 一覧から消えた行の id は落とす
    /// - Parameter generation: `beginLoad()` の返り値。より新しい読み込みが
    ///   **既に画面に移していたら**何もしない（nil なら世代を見ない）
    /// - Returns: 画面に移したか
    @discardableResult
    func apply(_ page: NotificationService.Page, refreshing: Bool, generation: Int? = nil) -> Bool {
        if let generation {
            guard generation >= appliedGeneration else { return false }
            appliedGeneration = generation
        }
        rows = page.items
        let fresh = NotificationText.unreadIds(page.items, unread: page.unread)
        if refreshing {
            unreadIds = fresh
        } else {
            let present = Set(page.items.map(\.id))
            unreadIds = fresh.union(unreadIds.intersection(present))
        }
        unread = page.unread
        return true
    }

    /// 手元の一覧を書いてよい回か（より新しい回が書いていたら false）
    func claimPools(_ generation: Int) -> Bool {
        guard generation >= poolsGeneration else { return false }
        poolsGeneration = generation
        return true
    }

    /// 読み込みを1本始める（世代を進める）
    func beginLoad() -> Int {
        generation += 1
        return generation
    }

    /// 手元の一覧を取り直した結果。**取り消された回は前の値を保つ**
    /// ——遷移で `.task` が取り消されると `try?` が nil になり、空で上書きすると
    /// 戻ったときに行が押せなくなる。取り消し以外の失敗は従来どおり空にする
    static func kept(_ fetched: [Photo]?, previous: [Photo], cancelled: Bool) -> [Photo] {
        if let fetched { return fetched }
        return cancelled ? previous : []
    }

    /// - Parameter refreshing: 引っぱって読み直した回。**このときだけ**未読の点を
    ///   サーバーの数で入れ替える（`apply` を参照）
    func load(environment: AppEnvironment, viewerId: String?, refreshing: Bool = false) async -> Bool {
        let generation = beginLoad()
        isLoading = true
        errorMessage = nil
        defer { if generation == self.generation { isLoading = false } }
        do {
            // 一覧は控えから即返るので、押し先の引き当てのために先に読む
            // **より新しい回が書いたあとの一覧を、古い回で上書きしない**
            // （遅れて返った古い回の失敗が `[]` を書くと、行が押せなくなる）
            let fetchedFeed = try? await environment.gallery.fetchPhotos()
            if claimPools(generation) {
                feed = Self.kept(fetchedFeed, previous: feed, cancelled: Task.isCancelled)
            }
            let fetchedMine = try? await environment.photos.myPhotos()
            if claimPools(generation) {
                mine = Self.kept(fetchedMine, previous: mine, cancelled: Task.isCancelled)
            }
            let page = try await environment.notifications.fetch()
            // 古い読み込みは画面に移さない（既読化も新しい方に任せる）
            guard apply(page, refreshing: refreshing, generation: generation) else { return false }
            // **フォローバックを出すかの判断に要る。** 取れなくても
            // お知らせ自体は出す（ボタンが出ないだけ）
            await loadFollowing(environment: environment, viewerId: viewerId)
            // ⚠️ **取得と既読化のすきまに届いた通知は、一度も未読に見えない。**
            // サーバーの既読化（`api-user/src/notifications.ts` の
            // `readNotifications`）は無条件の `SET unread = :z` なので、
            // fetch のあとに積まれたぶんも既読に数えてしまう。直すにはサーバーが
            // 「読んだ件数」か「最後に見た時刻」を受け取り、その差だけ減らす
            // 必要がある（端末側だけでは直せない）。
            // **開いたときに1回だけ既読にする。** 読めたあとに呼ぶので、
            // 取得に失敗した回でバッジだけ消える事故が起きない
            if page.unread > 0 {
                try? await environment.notifications.markRead()
                unread = 0
            }
            return true
        } catch {
            // 取り消し・古い読み込みの失敗は出さない（戻ったときに読み直す／新しい方が出す）
            guard generation == self.generation, !Task.isCancelled else { return false }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
            return false
        }
    }
}
