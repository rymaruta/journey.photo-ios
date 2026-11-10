import XCTest
@testable import JourneyPhoto

/// メッセージ（DM・第1段・札 #505・2026-11-10）の配線。画面は Linux で描けないので、**元のファイルを読んで**見張る
/// （`StoryV2RingsFixTests` と同じ作り）。入口・通知・二重送信の鍵・文言の決まり
@MainActor
final class DirectMessageWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
    }

    /// `start` から `end` の手前まで
    private func slice(_ text: String, from start: String, to end: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let s = text.range(of: start) else {
            XCTFail("「\(start)」が無い", file: file, line: line)
            return ""
        }
        guard let e = text.range(of: end, range: s.upperBound..<text.endIndex) else {
            XCTFail("「\(start)」の後に「\(end)」が無い", file: file, line: line)
            return ""
        }
        return String(text[s.lowerBound..<e.lowerBound])
    }

    private func index(of part: String, in text: String, file: StaticString = #filePath, line: UInt = #line) -> String.Index? {
        let found = text.range(of: part)?.lowerBound
        if found == nil { XCTFail("「\(part)」が無い", file: file, line: line) }
        return found
    }

    /// 入口: 見出しのベルの左に吹き出し（`bubble.left`・紙飛行機ではない・owner 指示）。点は受信箱の未読だけ
    func testHeaderHasMessagesLeftOfTheBell() throws {
        let header = try source("Features/Common/AppHeader.swift")
        XCTAssertTrue(header.contains(#"Image(systemName: "bubble.left")"#))
        XCTAssertFalse(header.contains("paperplane"), "入口の絵が紙飛行機")
        XCTAssertTrue(header.contains("TabRouter.shared.openMessages()"))
        XCTAssertTrue(header.contains("if messagesUnread { headerDot }"))
        if let bubble = index(of: #""header.messages""#, in: header),
           let bell = index(of: #"Image(systemName: "bell")"#, in: header),
           let search = index(of: #""header.search""#, in: header) {
            XCTAssertLessThan(search, bubble)
            XCTAssertLessThan(bubble, bell, "吹き出しがベルの左に無い")
        }
        // 点は真鍮の共通の部品（黒地の上の合図）
        let dot = slice(header, from: "private var headerDot", to: "\n    }\n")
        XCTAssertTrue(dot.contains("BrassDot()"))
    }

    /// 点の数え方は受信箱の未読だけ（リクエスト・ブロックした相手は数えない）で、3つのタブに同じ値を配る
    func testRootWiresInboxAndPush() throws {
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("messages.hasUnread(hiding: hidden.blockedUserIds)"))
        XCTAssertEqual(root.components(separatedBy: "messagesUnread: messagesUnread").count - 1, 3, "タブごとに点の値が違う")
        XCTAssertTrue(root.contains(".onChange(of: tabRouter.messagesRequests)"))
        XCTAssertTrue(root.contains(".onChange(of: router.conversationRequests)"))
        XCTAssertTrue(root.contains("DMInboxView(openConversation: $messagesTarget)"))
        let take = slice(root, from: "private func takeConversationRequest()", to: "\n    }\n\n")
        XCTAssertTrue(take.contains("router.takePendingConversation()"))
        XCTAssertTrue(take.contains("ModalProbe.isPresenting()"), "ほかの画面が出ている間に重ねて出そうとしている")
        XCTAssertTrue(take.contains("auth.userId == owner"), "待っている間に人が替わっても開く")

        let app = try source("App/JourneyPhotoApp.swift")
        XCTAssertTrue(app.contains(".environmentObject(messages)"))
        let env = try source("App/AppEnvironment.swift")
        XCTAssertTrue(env.contains("self.dm = DMService(api: api)"))
    }

    /// `NOTIF_DM` を押したら、お知らせではなくその会話へ（お知らせの行き先より先に分ける）
    func testDMPushOpensTheConversation() throws {
        let delegate = try source("App/AppDelegate.swift")
        let received = slice(delegate, from: "didReceive response: UNNotificationResponse", to: "\n    }\n}")
        if let dm = index(of: "NotificationRouter.dmConversationId(", in: received),
           let activity = index(of: "AppNotification.fromPush(", in: received) {
            XCTAssertLessThan(dm, activity)
        }
        XCTAssertTrue(received.contains("NotificationRouter.shared.openConversation(conversationId)"))
    }

    /// 送る1通は**1回だけ**鍵を作る。押し直しは同じ鍵で送る（二重に入らない）
    func testSendCreatesTheKeyOnceAndRetryReusesIt() throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        let send = slice(view, from: "private func send() async {", to: "\n    }\n")
        XCTAssertEqual(send.components(separatedBy: "DMRules.newClientId()").count - 1, 1)
        XCTAssertTrue(send.contains("log.begin(text: text, clientId: clientId)"))
        let retry = slice(view, from: "private func retry(_ clientId: String) async {", to: "\n    }\n")
        XCTAssertFalse(retry.contains("newClientId"), "押し直しで新しい鍵を作っている（二重に入る）")
        XCTAssertTrue(retry.contains("log.retry(clientId)"))
        XCTAssertTrue(retry.contains("deliver(text: text, clientId: clientId)"))
        let deliver = slice(view, from: "private func deliver(text: String, clientId: String) async {", to: "private func accept() async")
        XCTAssertTrue(deliver.contains("environment.dm.send(conversationId, text: text, clientId: clientId)"))
        // 送っている間は送信を押せない（同じ時に2通を走らせない）
        XCTAssertTrue(view.contains("!log.isSending"))
    }

    /// 送信の丸は送っている最中は押せない（`sendEnabled` を名指しで見る・押し直しの guard とは別・レビュー指摘2）
    func testSendButtonIsDisabledWhileSending() throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        let enabled = slice(view, from: "private var sendEnabled: Bool {", to: "\n    }\n")
        XCTAssertTrue(enabled.contains("!log.isSending"), "送っている最中に送信を押せる（2通が同時に走る）")
        XCTAssertTrue(enabled.contains("!connectivity.isOffline"), "圏外で送信を押せる")
        XCTAssertTrue(view.contains(".disabled(!sendEnabled)"))
    }

    /// 10秒の読み直しは前面にいる間だけ（`.task(id:)` が前面の出入りで止まり、`poll` も前面でなければ回さない）
    func testPollingStopsInBackground() throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        XCTAssertTrue(view.contains(#".task(id: "\(conversationId)#\(scenePhase == .active)") { await poll() }"#),
                      "裏へ回っても読み直しが止まらない")
        let poll = slice(view, from: "private func poll() async {", to: "\n    }\n")
        XCTAssertTrue(poll.contains("guard scenePhase == .active else { return }"))
        XCTAssertTrue(poll.contains("try? await Task.sleep(for: DMRules.pollInterval)"))
        XCTAssertTrue(poll.contains("!connectivity.isOffline"))
    }

    /// アイコンの数字（レビュー指摘1）: 会話を読んだら通知センターの通知を消し、受信箱の控えが変わったら数字を合わせ、
    /// お知らせを読んでもメッセージの未読分は残す
    func testBadgeFollowsMessages() throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        let read = slice(view, from: "private func markRead() async {", to: "\n    }\n")
        XCTAssertTrue(read.contains("await push.removeDelivered(conversationId: conversationId)"))
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains(".onChange(of: messages.inbox) { _, _ in syncBadgeWithMessages() }"))
        let sync = slice(root, from: "private func syncBadgeWithMessages() {", to: "\n    }\n")
        XCTAssertTrue(sync.contains("AppBadge.syncValue("))
        XCTAssertTrue(sync.contains("bellOwner: unreadOwner"), "お知らせの数を今の人で読めたかを見ていない")
        XCTAssertTrue(root.contains(".onChange(of: unread) { _, _ in syncBadgeWithMessages() }"),
                      "お知らせの未読が後から読めた回に数字を合わせ直さない")
        let bell = try source("Features/Notifications/NotificationsView.swift")
        XCTAssertFalse(bell.contains("push.clearBadge()"), "お知らせを読んだらメッセージの未読まで 0 にしている")
        XCTAssertEqual(bell.components(separatedBy: "push.clearBadge(keepingMessages: messagesUnread)").count - 1, 3)
        let delegate = try source("App/AppDelegate.swift")
        let present = slice(delegate, from: "willPresent notification: UNNotification", to: "\n    }\n")
        XCTAssertTrue(present.contains("NotificationRouter.presentation(forDMWhileShowing: showing)"))
        XCTAssertTrue(view.contains(".onChange(of: router.dmArrival)"))
        XCTAssertTrue(view.contains(".onAppear { router.conversationOpened(conversationId) }"))
    }

    /// 通知の会話に今の人が入っていなければ開かない（レビュー指摘5）
    func testPushConversationMustBelongToTheCurrentUser() throws {
        let root = try source("App/RootView.swift")
        let take = slice(root, from: "private func takeConversationRequest()", to: "\n    }\n\n")
        XCTAssertTrue(take.contains("guard let me = auth.userId, DMRules.peer(of: id, me: me) != nil else { return }"),
                      "受信箱が出ている回に、前の人の会話を積む")
        XCTAssertTrue(take.contains("DMRules.peer(of: id, me: owner) != nil"), "待った後に、前の人の会話を開く")
    }

    /// リクエストの札は画面に出た分だけ会話を読む（`LazyVStack`・最大50件を一度に読まない・レビュー指摘4）
    func testRequestFactsLoadLazily() throws {
        let view = try source("Features/Messages/DMRequestsView.swift")
        if let lazy = index(of: "LazyVStack(alignment: .leading, spacing: 0) {", in: view),
           let cards = index(of: "ForEach(requests) { request in", in: view),
           let facts = index(of: ".task(id: request.id) { await loadFacts(request) }", in: view) {
            XCTAssertLessThan(lazy, cards)
            XCTAssertLessThan(cards, facts)
        }
        XCTAssertFalse(view.contains("ScrollView {\n                VStack(alignment: .leading, spacing: 0) {"),
                       "札を全部いちどに作って、全部の会話を一度に読む")
    }

    /// 断られて欄に本文を戻したとき、戻した変化で断りの文を消さない（run 937: 送った 1・断られた 1・消えた 1）
    func testRestoredDraftKeepsTheRefusal() throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        let change = slice(view, from: ".onChange(of: draft) { old, new in", to: ".alert(")
        if let skip = index(of: "if new == restoredDraft { return }", in: change),
           let clear = index(of: "fieldError = nil", in: change) {
            XCTAssertLessThan(skip, clear, "戻した本文で断りの文を消している")
        }
        let deliver = slice(view, from: "private func deliver(text: String, clientId: String) async {", to: "private func accept() async")
        if let mark = index(of: "restoredDraft = back", in: deliver), let set = index(of: "draft = back", in: deliver) {
            XCTAssertLessThan(mark, set, "戻す印を付ける前に欄へ戻している")
        }
    }

    /// 会話の状態（読み込み中・失敗・見られない・ブロック中・退会・圏外）がそろっている
    func testConversationStates() throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        for part in ["JPLoadingState(kind: .bubbles)", "会話を読み込めませんでした", "ブロック中です", "ブロックを解除",
                     "この会話は表示できません", "受信箱にもどる", "このユーザーは退会したため、メッセージを送れません。",
                     "圏外です。つながると送れます", "もう一度送る", "返信すると承認されます",
                     "DMText.requestNote(name: peerName, remaining: remaining)"] {
            XCTAssertTrue(view.contains(part), part)
        }
        let inbox = try source("Features/Messages/DMInboxView.swift")
        for part in ["JPLoadingState(kind: .people)", "まだメッセージはありません", "ホームでストーリーを見る",
                     "圏外です。つながると新しいメッセージが届きます", "ErrorBanner(", "if requestCount > 0"] {
            XCTAssertTrue(inbox.contains(part), part)
        }
        let requests = try source("Features/Messages/DMRequestsView.swift")
        for part in ["リクエストはありません", "承認しました。受信箱に移りました", "リクエストを削除しました",
                     "environment.dm.declineAll()", "environment.dm.accept(", "environment.dm.decline("] {
            XCTAssertTrue(requests.contains(part), part)
        }
    }

    /// ストーリーの返信欄（画面案 A〜E）
    func testStoryReplyField() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("返信はメッセージとして残ります"))
        XCTAssertFalse(viewer.contains("さんにだけ届きます"), "返信はメッセージに残るのに「だけ届きます」のまま")
        let send = slice(viewer, from: "private func sendReply(_ text: String, to story: Story, clearsDraft: Bool = false) async {",
                         to: "\n    }\n")
        if let gate = index(of: "gate.refusesURL(in: text)", in: send),
           let call = index(of: "environment.stories.reply(", in: send) {
            XCTAssertLessThan(gate, call, "URL を止める前に送っている")
        }
        XCTAssertTrue(send.contains("gate.limitReached"))
        // 「メッセージを見る」は応答の `dm` 欄で決める（写らなかった返信で会話へ誘わない・欄が無ければ2人から組む）
        XCTAssertTrue(send.contains("outcome.conversationToOpen(me: viewerId, owner: story.userId)"))
        XCTAssertTrue(viewer.contains("DMConversationView(conversationId: target.id)"))
        let replies = try source("Features/Stories/StoryRepliesSheet.swift")
        XCTAssertTrue(replies.contains("返信はメッセージにも残ります。ストーリーが消えても、メッセージは残ります。"))
        XCTAssertTrue(replies.contains("DMConversationView(conversationId: conversationId)"))
        // 矢印は受信箱に在る会話だけ（写らなかった返信へ誘わない・2026-11-10）
        XCTAssertTrue(replies.contains("StoryReplyConversation.id(me: me, replier: uid, hasText: !item.body.isEmpty, inbox: messages.inbox)"))
        // ベルの未読は受信箱に入った返信を数えない（アイコンの数字と同じ数え方）
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("environment.notifications.fetch().bellUnread"))
        let bell = try source("Features/Notifications/NotificationsView.swift")
        XCTAssertTrue(bell.contains("guard !row.isInMessages else { return false }"))
    }

    /// 文言の決まり: 画面の字は日英（`L`）・「捨てる」「撮りどき」を出さない・本文は 12pt 以上
    func testWording() throws {
        for file in ["Features/Messages/DMInboxView.swift", "Features/Messages/DMRequestsView.swift",
                     "Features/Messages/DMConversationView.swift", "Features/Messages/DMParts.swift",
                     "Core/Text/DirectMessages.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains("捨て"), file)
            XCTAssertFalse(text.contains("撮りどき"), file)
            // 日本語の字を `L(` を通さずに `Text("…")` へ直に置かない
            let direct = text.range(of: #"Text\("[^"]*[ぁ-んァ-ン一-龥]"#, options: .regularExpression)
            XCTAssertNil(direct, "\(file): 英語の画面に日本語が出る")
            for size in [8, 9, 10, 11] {
                XCTAssertFalse(text.contains(".system(size: \(size))"), "\(file): \(size)pt の字")
            }
        }
    }
}
