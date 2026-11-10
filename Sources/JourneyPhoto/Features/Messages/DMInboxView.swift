import SwiftUI

/// 行き先（受信箱から積む画面）
enum DMRoute: Hashable {
    case conversation(String)
    case requests
}

/// メッセージの受信箱（画面案「受信箱」・札 #505・2026-11-10）。ホームの見出しの吹き出しから、シートで開く。
///
/// - 先頭に「リクエスト」の行（件数の真鍮のバッジ。0 件の日は行ごと出さない）
/// - 未読は「点＋太字＋明るい本文」。既読の表示は出さない
/// - 状態: 読み込み中（顔の行の骨格）・空（ホームでストーリーを見る）・失敗（もう一度）・圏外（最後の一覧の上に帯）
struct DMInboxView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var store: DMInboxStore
    @Environment(\.dismiss) private var dismiss

    /// 通知から開く会話（`RootView` が置く。受け取ったら空にする）
    @Binding var openConversation: String?

    @State private var route: DMRoute?

    var body: some View {
        Group {
            if auth.isResolving {
                ScrollView { JPLoadingState(kind: .people).padding(.horizontal, JPSpace.gutter) }
            } else if auth.userId == nil {
                SignInView(reason: L("メッセージを見るにはログインしてください", "Sign in to see your messages"))
            } else {
                content
            }
        }
        .webScreen()
        .navigationTitle(DMText.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { route in
            switch route {
            case .conversation(let id):
                DMConversationView(conversationId: id)
            case .requests:
                DMRequestsView()
            }
        }
        .task(id: auth.userId) { await reload() }
        // つながったら読み直す（画面案「圏外: つながったら自動で更新する」）
        .onChange(of: connectivity.isOffline) { _, offline in
            if !offline { Task { await reload() } }
        }
        .onChange(of: auth.userId) { _, _ in route = nil }
        .onAppear { takeOpenRequest() }
        .onChange(of: openConversation) { _, _ in takeOpenRequest() }
    }

    /// 通知から開く会話を積む（1回だけ）
    private func takeOpenRequest() {
        guard let id = openConversation else { return }
        openConversation = nil
        route = .conversation(id)
    }

    private func reload() async {
        await store.refresh(service: environment.dm, owner: auth.userId)
    }

    private var threads: [DMThread] {
        store.inbox.conversations.filter { !hidden.blockedUserIds.contains($0.peerId) }
    }

    private var requestCount: Int {
        store.inbox.requestTotal(hiding: hidden.blockedUserIds)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if connectivity.isOffline {
                DMOfflineStrip(text: L("圏外です。つながると新しいメッセージが届きます",
                                       "You're offline. New messages will arrive when you reconnect."))
            }
            switch store.phase {
            case .loading:
                ScrollView { JPLoadingState(kind: .people).padding(.horizontal, JPSpace.gutter) }
            case .failed:
                ScrollView {
                    ErrorBanner(title: Labels.Common.loadFailed, message: DMText.loadFailedMessage,
                                isBusy: store.isRefreshing) {
                        Task { await reload() }
                    }
                    .padding(.top, JPSpace.emptyTop)
                }
            case .loaded:
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if requestCount > 0 {
                    requestEntry
                }
                if threads.isEmpty && requestCount == 0 {
                    EmptyState(title: L("まだメッセージはありません", "No messages yet"),
                               message: L("ストーリーに返信すると、ここに会話が残ります。",
                                          "Reply to a story and the conversation will stay here."),
                               actionTitle: L("ホームでストーリーを見る", "See stories on Home"),
                               actionIdentifier: "dm.empty.home") {
                        dismiss()
                        TabRouter.shared.openHome()
                    }
                    .padding(.top, JPSpace.emptyTop)
                } else {
                    ForEach(threads) { thread in
                        Button {
                            route = .conversation(thread.id)
                        } label: {
                            DMThreadRow(thread: thread)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dm.thread")
                    }
                    Text(L("メッセージは、ストーリーへの返信から始まります。",
                           "Messages start from a reply to a story."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, JPSpace.xl)
                        .padding(.horizontal, JPSpace.xxs)
                }
            }
            .padding(.horizontal, JPSpace.gutter)
        }
        .refreshable { await reload() }
        .accessibilityIdentifier("dm.inbox")
    }

    /// 「リクエスト」の行（画面案: 人の印の丸 48・件数の真鍮のバッジ・矢印）
    private var requestEntry: some View {
        Button {
            route = .requests
        } label: {
            HStack(spacing: JPSpace.s) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: DMLook.rowAvatar, height: DMLook.rowAvatar)
                    .background(WebTheme.surface3, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DMText.requestsTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WebTheme.text)
                    Text(L("承認すると受信箱に移ります", "Accept to move them to your inbox"))
                        .font(.system(size: 14))
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CountBadge(count: requestCount, maximum: 99)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DMLook.requestEntryHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("リクエスト \(requestCount)件", "Requests, \(requestCount)"))
        .accessibilityIdentifier("dm.requests.entry")
    }
}
