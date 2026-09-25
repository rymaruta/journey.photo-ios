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
    @ViewBuilder
    private func rowLink(_ row: AppNotification) -> some View {
        switch model.destination(for: row) {
        case .photo(let photo, let fromPublicFeed):
            NavigationLink {
                PhotoDetailView(photo: photo, fromPublicFeed: fromPublicFeed)
            } label: {
                NotificationRow(notification: row, following: model.following,
                                onFollowBack: { await model.followBack($0, environment: environment) })
            }
        case .user(let userId):
            NavigationLink { UserProfileView(userId: userId) } label: {
                NotificationRow(notification: row, following: model.following,
                                onFollowBack: { await model.followBack($0, environment: environment) })
            }
        case .none:
            NotificationRow(notification: row, following: model.following,
                            onFollowBack: { await model.followBack($0, environment: environment) })
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
                    ForEach(group.rows) { row in
                        rowLink(row)
                    }
                } header: {
                    Text(group.bucket.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
                }
            }
        }
        .task(id: router.openActivityRequests) {
            // **読めたときだけ消す。** サーバーは未読数を載せるが、既読に
            // したことは端末のアイコンに伝わらない——誰も消さないと増える
            // 一方。ただし圏外で開いた回に消すと、タブは 3・アイコンは 0 に割れる
            if await model.load(environment: environment, viewerId: auth.userId) { await push.clearBadge() }
        }
        .refreshable {
            if await model.load(environment: environment, viewerId: auth.userId) { await push.clearBadge() }
        }
    }
}

private struct NotificationRow: View {

    let notification: AppNotification
    /// いまフォローしている人。**フォロー通知の「フォローバック」を
    /// 出すかどうかの判断に使う**——既にフォローしている相手に出さない
    var following: Set<String> = []
    var onFollowBack: ((String) async -> Void)?

    @State private var busy = false

    var body: some View {
        // 知らない種類は描かない（既定の文言で嘘を出さない）
        if let summary = notification.summary {
            HStack(spacing: 12) {
                if let src = notification.photoSrc, let url = URL(string: src) {
                    RemoteImage(url: url)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary).font(.callout)
                    if let at = notification.atLocation, !at.isEmpty {
                        Text(at).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                followBackButton
            }
            .padding(.vertical, 2)
        }
    }

    /// フォローバック（モック10）。
    ///
    /// **出すのはフォロー通知で、まだフォローしていない相手のときだけ。**
    /// 既にフォローしている相手に出すと、押しても何も変わらないボタンになる。
    @ViewBuilder
    private var followBackButton: some View {
        if notification.kind == .follow, let userId = notification.byId ?? notification.targetUserId,
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
    /// いまフォローしている人。**フォローバックを出すかの判断だけに使う**
    @Published private(set) var following: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

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

    func load(environment: AppEnvironment, viewerId: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 一覧は控えから即返るので、押し先の引き当てのために先に読む
            feed = (try? await environment.gallery.fetchPhotos()) ?? []
            mine = (try? await environment.photos.myPhotos()) ?? []
            let page = try await environment.notifications.fetch()
            rows = page.items
            // **フォローバックを出すかの判断に要る。** 取れなくても
            // お知らせ自体は出す（ボタンが出ないだけ）
            await loadFollowing(environment: environment, viewerId: viewerId)
            unread = page.unread
            // **開いたときに1回だけ既読にする。** 読めたあとに呼ぶので、
            // 取得に失敗した回でバッジだけ消える事故が起きない
            if page.unread > 0 {
                try? await environment.notifications.markRead()
                unread = 0
            }
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
            return false
        }
    }
}
