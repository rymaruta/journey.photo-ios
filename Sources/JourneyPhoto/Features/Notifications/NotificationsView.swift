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
                NotificationRow(notification: row)
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

    @Published private(set) var rows: [AppNotification] = []
    @Published private(set) var unread = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func load(environment: AppEnvironment) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
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
