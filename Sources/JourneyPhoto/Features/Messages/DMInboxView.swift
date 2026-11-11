import SwiftUI

/// 行き先（受信箱から積む画面）
enum DMRoute: Hashable {
    case conversation(String)
    case requests
    /// 会話を始める（「新しいメッセージ」で選んだ人・2026-11-10）。まだ会話が無くても開く
    case start(DMPeerSeed)
}

/// メッセージの受信箱（画面案「受信箱」・札 #505・2026-11-10）。ホームの見出しの吹き出しから、シートで開く。
///
/// - 先頭に「リクエスト」の行（件数の真鍮のバッジ。0 件の日は行ごと出さない）
/// - 未読は「点＋太字＋明るい本文」。既読の表示は出さない
/// - 状態: 読み込み中（顔の行の骨格）・空（新しいメッセージ）・失敗（もう一度）・圏外（最後の一覧の上に帯）
/// - 見出しの右に鉛筆（「新しいメッセージ」・2026-11-10 owner「普通にDMできる機能がいい」）。フォロー中の人から選ぶ
///
/// **2026-11-11 作り直し（札 #541・案C）**: 顔は 52 で、未見のストーリーがある人は真鍮の輪（押すとストーリー・
/// `DMStoryFace`）。時刻は名前の横・未読の点は行の右の真ん中・行の間の線をやめて 72 の余白で区切る（リクエストの下だけ線）。
/// 一覧の下の説明文はやめた（右上の鉛筆で分かる・説明は空の受信箱だけ・「見れば分かる」）。
/// 空の受信箱には「フォロー中」の顔の列（押すとその人との会話・最初の1通が 4 → 3 押し）
struct DMInboxView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var store: DMInboxStore

    /// 通知から開く会話（`RootView` が置く。受け取ったら空にする）
    @Binding var openConversation: String?

    @State private var route: DMRoute?
    /// 「新しいメッセージ」のシート。選んだ人は閉じてから積む（シートが閉じる途中で積むと、積んだ画面が出ないことがある）
    @State private var showNewMessage = false
    @State private var picked: DMPeerSeed?
    /// 空の受信箱の顔の列（フォロー中の人・読めなければ列を出さない）
    @State private var faces: [FollowUser] = []

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
            case .start(let peer):
                if let id = DMStart.conversationId(me: auth.userId, peer: peer.id) {
                    DMConversationView(conversationId: id, startingWith: peer)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if auth.userId != nil { newMessageButton }
            }
        }
        .sheet(isPresented: $showNewMessage, onDismiss: {
            guard let peer = picked else { return }
            picked = nil
            route = .start(peer)
        }) {
            NavigationStack {
                DMNewMessageView { peer in
                    picked = peer
                    showNewMessage = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                }
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

    /// 空の受信箱の顔の列（フォロー中の名前つき一覧・`DMNewMessageView` と同じ口と同じふるい）。
    /// 受信箱に会話がある間は読まない。読めなければ列を出さない（空の状態の一手は残る）
    private func loadFaces() async {
        guard let me = auth.userId, threads.isEmpty, requestCount == 0, store.phase == .loaded else { return }
        guard let fetched = try? await environment.social.following(userId: me), !Task.isCancelled,
              auth.userId == me else { return }
        faces = Array(DMStart.candidates(fetched.users, me: me, blocked: hidden.blockedUserIds).prefix(12))
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
                    // 2026-11-10 判断: 一手は「新しいメッセージ」（フォロー中の人から選ぶ）。ストーリーへの返信も残るが、
                    // 始め方の主はこちら
                    EmptyState(title: L("まだメッセージはありません", "No messages yet"),
                               message: DMText.startHint,
                               actionTitle: DMText.newMessageTitle,
                               actionIdentifier: "dm.empty.new") {
                        showNewMessage = true
                    }
                    .padding(.top, JPSpace.emptyTop)
                    if !faces.isEmpty {
                        VStack(alignment: .leading, spacing: JPSpace.xs) {
                            JPEyebrowLine(L("フォロー中", "Following"))
                                .padding(.horizontal, JPSpace.gutter)
                            DMPeopleFacesRow(people: faces) { user in
                                route = .start(DMStart.seed(user))
                            }
                        }
                        // 顔の列は端まで流す（左右の余白は列の中で取る）
                        .padding(.horizontal, -JPSpace.gutter)
                        .padding(.top, JPSpace.xl)
                    }
                } else {
                    ForEach(threads) { thread in
                        HStack(spacing: JPSpace.s) {
                            DMStoryFace(userId: thread.peerId, deleted: thread.isDeleted,
                                        name: DMText.name(thread.name, deleted: thread.isDeleted),
                                        size: DMLook.rowAvatar) {
                                route = .conversation(thread.id)
                            }
                            Button {
                                route = .conversation(thread.id)
                            } label: {
                                DMThreadRow(thread: thread)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dm.thread")
                        }
                    }
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.bottom, JPSpace.screenEnd)
        }
        .task(id: "\(auth.userId ?? "-")#\(store.phase == .loaded && threads.isEmpty && requestCount == 0)") {
            await loadFaces()
        }
        .refreshable { await reload() }
        .accessibilityIdentifier("dm.inbox")
    }

    /// 見出しの右の鉛筆（「新しいメッセージ」）。印は上のバーの印と同じ大きさ・当たり 44（`appHeaderHitArea`）
    private var newMessageButton: some View {
        Button { showNewMessage = true } label: {
            Image(systemName: "square.and.pencil").webToolbarIcon().appHeaderHitArea()
        }
        .accessibilityLabel(DMText.newMessageTitle)
        .accessibilityIdentifier("dm.new.open")
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
                        .font(JPFont.body.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                    Text(L("承認すると受信箱に移ります", "Accept to move them to your inbox"))
                        .jpSystemFont(14)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CountBadge(count: requestCount, maximum: 99)
                Image(systemName: "chevron.right")
                    .font(JPFont.footnote.weight(.semibold))
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
