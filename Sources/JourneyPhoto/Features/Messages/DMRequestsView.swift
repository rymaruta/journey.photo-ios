import SwiftUI

/// リクエストの一覧（画面案「リクエスト」・札 #505・2026-11-10）。受信箱の先頭の「リクエスト」から積む。
///
/// - 札ごとに 承認（主・白）／削除（副・線）。「…」から通報・ブロック
/// - 送り主の通数（最大 3）と「ストーリーへの返信」を札に出す（会話を読んで数える・`RequestFacts`）
/// - 承認したら、**そのまま会話を開いて書く欄にキーボード**（2026-11-16 判断・使い勝手の見直し A8。前は札が消えて
///   下に「承認しました。受信箱に移りました ›メッセージを見る」が出て、もう1回押してから欄を押していた）。
///   知らせ（`DMText.acceptedNotice`）は会話の画面が出す。削除は「リクエストを削除しました」だけ
/// - まとめて削除は右上の「…」から（確認つき）
struct DMRequestsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var store: DMInboxStore

    /// 積む会話。`accepted` は「承認」を押して開いた回（会話の画面で欄にキーボードを出し、知らせを出す）
    @State private var route: Route?
    /// 札ごとに読んだ事実（通数・ストーリーへの返信か）
    @State private var facts: [String: RequestFacts] = [:]
    /// 操作中の札（二度押しで重ねない）
    @State private var working: Set<String> = []
    @State private var toast: ToastState?
    @State private var menuTarget: DMThread?
    @State private var showMenu = false
    @State private var blockTarget: DMThread?
    @State private var reportTarget: DMThread?
    @State private var confirmDeleteAll = false
    @State private var errorMessage: String?
    /// 開いたグループの招待（2026-11-20 札 #582）
    @State private var inviteTarget: GroupInvite?

    struct RequestFacts: Equatable {
        /// 送り主からの通数
        let count: Int
        let viaStory: Bool
    }

    struct ToastState: Equatable {
        let id = UUID()
        let text: String
    }

    struct Route: Hashable {
        let id: String
        var accepted = false
    }

    private var requests: [DMThread] {
        store.inbox.requests.filter { !hidden.blockedUserIds.contains($0.peerId) }
    }

    /// グループの招待（2026-11-20 札 #582）。口が無いサーバーでは空。ブロックした人からの招待は出さない
    private var invites: [GroupInvite] {
        guard store.groupsAvailable else { return [] }
        return store.groups.invites.filter { !hidden.blockedUserIds.contains($0.invitedBy.id) }
    }

    var body: some View {
        content
            .webScreen()
            .navigationTitle(DMText.requestsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !requests.isEmpty {
                        Menu {
                            Button(L("リクエストをすべて削除", "Delete all requests"), role: .destructive) {
                                confirmDeleteAll = true
                            }
                        } label: {
                            Image(systemName: "ellipsis").webToolbarIcon()
                        }
                        .accessibilityLabel(L("その他の操作", "More"))
                        .accessibilityIdentifier("dm.requests.more")
                    }
                }
            }
            .navigationDestination(item: $route) { route in
                DMConversationView(conversationId: route.id, openedAfterAccept: route.accepted)
            }
            .navigationDestination(item: $inviteTarget) { invite in
                GroupInviteView(invite: invite)
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    DMActionToast(text: toast.text)
                        .task(id: toast.id) {
                            try? await Task.sleep(for: DMActionToast.duration)
                            if !Task.isCancelled, self.toast?.id == toast.id { self.toast = nil }
                        }
                }
            }
            // 押した札は `menuTarget` に残す（閉じるときの `isPresented = false` で消えない・ボタンの中で読む）
            .confirmationDialog(menuTarget.map { L("\(DMText.name($0.name, deleted: $0.isDeleted)) さん", $0.name) } ?? "",
                                isPresented: $showMenu, titleVisibility: .visible) {
                Button(L("通報", "Report"), role: .destructive) { reportTarget = menuTarget }
                Button(L("ブロック", "Block"), role: .destructive) { blockTarget = menuTarget }
                Button(Labels.Common.cancel, role: .cancel) {}
            }
            .alert(blockTarget.map { DMBlockText.title(DMText.name($0.name, deleted: $0.isDeleted)) } ?? "",
                   isPresented: Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }),
                   presenting: blockTarget) { target in
                Button(L("ブロック", "Block"), role: .destructive) { Task { await block(target) } }
                Button(Labels.Common.cancel, role: .cancel) {}
            } message: { _ in
                Text(DMBlockText.message)
            }
            .alert(L("リクエストをすべて削除しますか？", "Delete all requests?"), isPresented: $confirmDeleteAll) {
                Button(L("すべて削除", "Delete all"), role: .destructive) { Task { await declineAll() } }
                Button(Labels.Common.cancel, role: .cancel) {}
            } message: {
                Text(L("相手には知らされません。", "They won't be told."))
            }
            // 通報と一緒にブロックしたら、閉じたときに札を外す（ブロックした相手の会話は両者の画面から隠れる）
            .sheet(item: $reportTarget, onDismiss: dropBlockedRequests) { target in
                ReportSheet(photoId: "", ownerId: target.peerId,
                            conversation: ReportSheet.Conversation(id: target.id,
                                                                   name: DMText.name(target.name, deleted: target.isDeleted)))
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.phase == .loading {
            ScrollView { JPLoadingState(kind: .people).padding(.horizontal, JPSpace.gutter) }
        } else {
            ScrollView {
                // **画面に出た札だけ作る**（札ごとに会話を読む `loadFacts` が、最大50件を一度に走らせない・2026-11-10 レビュー指摘4）
                LazyVStack(alignment: .leading, spacing: 0) {
                    if connectivity.isOffline {
                        DMOfflineStrip(text: L("圏外です。つながると新しいメッセージが届きます",
                                               "You're offline. New messages will arrive when you reconnect."))
                            .padding(.horizontal, -JPSpace.gutter)
                    }
                    if !invites.isEmpty {
                        // グループの招待（参加するまで話は見えない・押すと招待の札）
                        JPEyebrowLine(L("グループの招待", "Group invites"))
                            .padding(.top, JPSpace.xs)
                        ForEach(invites) { invite in
                            inviteRow(invite)
                        }
                        if !requests.isEmpty {
                            JPEyebrowLine(L("メッセージ", "Messages"))
                                .padding(.top, JPSpace.m)
                        }
                    }
                    if requests.isEmpty && invites.isEmpty {
                        EmptyState(icon: "person.2", title: L("リクエストはありません", "No requests"),
                                   message: L("承認前のメッセージは、ここに並びます。",
                                              "Messages from people you haven't accepted will show up here."))
                            .padding(.top, JPSpace.emptyTop)
                    } else if !requests.isEmpty {
                        Text(L("まだ承認していない人からのメッセージです。相手が送れるのは文字\(DMRules.requestLimit)通までで、リンクは送れません。承認するか返信すると、受信箱に移ります。",
                               "Messages from people you haven't accepted yet. They can send up to \(DMRules.requestLimit) text messages and no links. Accept or reply to move them to your inbox."))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, JPSpace.xxs)
                            .padding(.top, JPSpace.xs)
                            .padding(.bottom, JPSpace.s)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.danger)
                                .padding(.bottom, JPSpace.xs)
                        }
                        ForEach(requests) { request in
                            card(request)
                                .task(id: request.id) { await loadFacts(request) }
                        }
                    }
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.bottom, 96)
            }
            .refreshable {
                await store.refresh(service: environment.dm, owner: auth.userId)
                await store.refreshGroups(service: environment.groups, owner: auth.userId)
            }
            .accessibilityIdentifier("dm.requests")
        }
    }

    /// 1件の札（画面案: surface-1 の地・白 8% の縁・角 16）
    private func card(_ request: DMThread) -> some View {
        let name = DMText.name(request.name, deleted: request.isDeleted)
        let busy = working.contains(request.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: JPSpace.s) {
                Button { route = Route(id: request.id) } label: {
                    HStack(spacing: JPSpace.s) {
                        DMAvatar(userId: request.peerId, deleted: request.isDeleted, size: DMLook.requestAvatar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(JPFont.body.weight(.medium))
                                .foregroundStyle(WebTheme.text)
                                .lineLimit(1)
                            Text([request.username.map { "@\($0)" }, DMText.listTime(request.t)]
                                    .compactMap { $0 }.joined(separator: "\u{2002}"))
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    menuTarget = request
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("その他の操作（ブロック、通報）", "More (block, report)"))
                .accessibilityIdentifier("dm.request.more")
            }
            Button { route = Route(id: request.id) } label: {
                Text(request.excerpt)
                    .jpSystemFont(14)
                    .foregroundStyle(WebTheme.text)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
            .buttonStyle(.plain)
            if let fact = facts[request.id] {
                HStack(spacing: JPSpace.xs) {
                    if fact.viaStory { DMChip(text: L("ストーリーへの返信", "Story reply")) }
                    DMChip(text: L("\(fact.count)通", fact.count == 1 ? "1 message" : "\(fact.count) messages"))
                }
                .padding(.top, JPSpace.xxs)
            }
            HStack(spacing: JPSpace.xs) {
                Button { Task { await accept(request) } } label: {
                    // 写真の無い画面の主ボタン＝真鍮の塗りに墨（7.11:1・2026-11-11 案C。今までは白）
                    Text(L("承認", "Accept"))
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 18)
                        .frame(height: JPHeight.inlineButton)
                        .background(WebTheme.accentFill, in: Capsule())
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dm.request.accept")
                Button { Task { await decline(request) } } label: {
                    // 縁は outline（部品の縁 3:1 以上。白 28% は届かなかった・2026-11-11）
                    Text(Labels.Common.delete)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.horizontal, 18)
                        .frame(height: JPHeight.inlineButton)
                        .overlay(Capsule().strokeBorder(WebTheme.outline, lineWidth: JPStroke.hairline))
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dm.request.decline")
            }
            .padding(.top, JPSpace.xxs)
            .disabled(busy || connectivity.isOffline)
            .opacity(busy ? 0.5 : 1)
        }
        .padding(.leading, 14)
        .padding(.trailing, JPSpace.s)
        .padding(.top, JPSpace.s)
        .padding(.bottom, JPSpace.xs)
        .jpCardFace()
        .padding(.bottom, JPSpace.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dm.request")
    }

    /// グループの招待の行（重ねた顔 52・名前・「〜さんがあなたを入れようとしています」・矢印）。押すと招待の札
    private func inviteRow(_ invite: GroupInvite) -> some View {
        Button { inviteTarget = invite } label: {
            HStack(spacing: JPSpace.s) {
                GroupFaces(faces: invite.info.faces, size: GroupLook.rowFaces)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GroupText.title(invite.info))
                        .font(JPFont.body.weight(.medium))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    Text(GroupText.invitedLine(by: invite.invitedBy.name))
                        .jpSystemFont(14)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DMLook.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dm.groupInvite")
    }

    // MARK: - 操作

    /// 札の通数と「ストーリーへの返信」を、会話を読んで数える（既読にはしない——既読は `PUT …/read` だけ）
    private func loadFacts(_ request: DMThread) async {
        guard facts[request.id] == nil,
              let conversation = try? await environment.dm.conversation(request.id) else { return }
        let fromPeer = conversation.items.filter { !$0.mine }
        facts[request.id] = RequestFacts(count: fromPeer.count, viaStory: fromPeer.contains(where: \.isStoryReply))
    }

    private func accept(_ request: DMThread) async {
        guard working.insert(request.id).inserted else { return }
        defer { working.remove(request.id) }
        errorMessage = nil
        do {
            try await environment.dm.accept(request.id)
            store.apply { $0.accepting(request.id) }
            // 2026-11-16 判断（A8）: そのまま会話へ。欄にキーボードと「承認しました」は会話の画面が出す
            toast = nil
            route = Route(id: request.id, accepted: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("承認できませんでした", "Couldn't accept")
        }
    }

    private func decline(_ request: DMThread) async {
        guard working.insert(request.id).inserted else { return }
        defer { working.remove(request.id) }
        errorMessage = nil
        do {
            try await environment.dm.decline(request.id)
            store.apply { $0.removing(request.id) }
            toast = ToastState(text: L("リクエストを削除しました", "Request deleted"))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }

    private func declineAll() async {
        errorMessage = nil
        let ids = Set(requests.map(\.id))
        do {
            _ = try await environment.dm.declineAll()
            store.apply { inbox in DMInbox(rebuilding: inbox.items.filter { !ids.contains($0.id) }) }
            toast = ToastState(text: L("リクエストをすべて削除しました", "All requests deleted"))
            // サーバーの側で残った分（読んだあとに届いた分）を映す
            await store.refresh(service: environment.dm, owner: auth.userId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }

    private func dropBlockedRequests() {
        let blocked = hidden.blockedUserIds
        store.apply { inbox in DMInbox(rebuilding: inbox.items.filter { !blocked.contains($0.peerId) }) }
    }

    private func block(_ target: DMThread) async {
        do {
            try await hidden.blockAndHide(target.peerId, environment: environment)
            // ブロックした相手の会話は両者の画面から隠れる（サーバーは消さずに隠す・解除で戻る）
            store.apply { $0.removing(target.id) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }
}
