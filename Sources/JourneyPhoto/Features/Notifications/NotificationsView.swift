import SwiftUI

/// お知らせ。
struct NotificationsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = NotificationsViewModel()

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
        .navigationTitle(L("お知らせ", "Activity"))
    }

    private var list: some View {
        List {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            } else if model.rows.isEmpty && !model.isLoading {
                Text(L("まだ届いていません", "Nothing yet")).foregroundStyle(.secondary)
            }

            ForEach(model.rows) { row in
                // **押せるようにする。** 行き止まりの一覧は「壊れている」に見える。
                // 行き先が分からないものは押せないまま出す（空振りを作らない）
                switch model.destination(for: row) {
                case .photo(let photo):
                    NavigationLink { PhotoDetailView(photo: photo) } label: {
                        NotificationRow(notification: row)
                    }
                case .user(let userId):
                    NavigationLink { UserProfileView(userId: userId) } label: {
                        NotificationRow(notification: row)
                    }
                case .none:
                    NotificationRow(notification: row)
                }
            }
        }
        .task { await model.load(environment: environment) }
        .refreshable { await model.load(environment: environment) }
    }
}

private struct NotificationRow: View {

    let notification: AppNotification

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
            }
            .padding(.vertical, 2)
        }
    }
}

@MainActor
final class NotificationsViewModel: ObservableObject {

    /// お知らせを押したときの行き先。
    enum Destination {
        case photo(Photo)
        case user(String)
        case none
    }

    @Published private(set) var rows: [AppNotification] = []
    /// 写真を引き当てるための手元の一覧（公開のぶん）
    private var feed: [Photo] = []
    @Published private(set) var unread = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// テストから手元の一覧を差し替える口。
    func setFeedForTesting(_ photos: [Photo]) { feed = photos }

    /// 行き先を決める。
    ///
    /// - フォローは相手のプロフィール
    /// - いいね・コメントはその写真。**手元の一覧に無ければ押せないまま**
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
            if let id = notification.photoId, let photo = feed.first(where: { $0.id == id }) {
                return .photo(photo)
            }
            return .none
        case .storyreply, .none:
            return .none
        }
    }

    func load(environment: AppEnvironment) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 一覧は控えから即返るので、押し先の引き当てのために先に読む
            feed = (try? await environment.gallery.fetchPhotos()) ?? []
            let page = try await environment.notifications.fetch()
            rows = page.items
            unread = page.unread
            // **開いたときに1回だけ既読にする。** 読めたあとに呼ぶので、
            // 取得に失敗した回でバッジだけ消える事故が起きない
            if page.unread > 0 {
                try? await environment.notifications.markRead()
                unread = 0
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }
}
