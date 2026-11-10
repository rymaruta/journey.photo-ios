import XCTest
@testable import JourneyPhoto

/// メッセージを「ふつうに」始める入口（2026-11-10 owner「普通にDMできる機能がいい」）。
/// プロフィールの「メッセージ」・受信箱の「新しいメッセージ」・まだ会話が無い相手への1通目。
/// 画面は Linux で描けないので、決まり（`DMStart`）は値で、配線は元のファイルを読んで見張る
/// （`DirectMessageWiringTests` と同じ作り・試験は全部 `async`）
@MainActor
final class DirectMessageStartTests: XCTestCase {

    private static let me = "0b6f1c1e-1111-4aaa-8aaa-000000000009"
    private static let peer = "a1b2c3d4-0000-4000-8000-00000000000f"

    // MARK: - 決まり

    /// 会話 id はサーバーの `convIdOf`（`api-user/src/dm.ts`）と同じ。期待値は 2026-11-10 にサーバーの関数を
    /// node で動かして出したもの（大文字の uid・先頭の字で順が入れ替わる組・最後の1字だけ違う組）
    func testConversationIdMatchesTheServerFunction() async {
        let cases: [(String, String, String)] = [
            (Self.me, Self.peer, "0b6f1c1e-1111-4aaa-8aaa-000000000009_a1b2c3d4-0000-4000-8000-00000000000f"),
            ("F0000000-0000-4000-8000-000000000001", "0fffffff-ffff-4fff-bfff-ffffffffffff",
             "0fffffff-ffff-4fff-bfff-ffffffffffff_f0000000-0000-4000-8000-000000000001"),
            ("9a3c0e52-7d1b-4c6e-9f4a-2b8d7e6f5a41", "9A3C0E52-7D1B-4C6E-9F4A-2B8D7E6F5A40",
             "9a3c0e52-7d1b-4c6e-9f4a-2b8d7e6f5a40_9a3c0e52-7d1b-4c6e-9f4a-2b8d7e6f5a41"),
        ]
        for (a, b, expected) in cases {
            XCTAssertEqual(DMStart.conversationId(me: a, peer: b), expected)
            XCTAssertEqual(DMStart.conversationId(me: b, peer: a), expected, "向きで id が変わる")
        }
        // 自分自身・ログインしていない・空には会話を作らない
        XCTAssertNil(DMStart.conversationId(me: Self.me, peer: Self.me.uppercased()))
        XCTAssertNil(DMStart.conversationId(me: nil, peer: Self.peer))
        XCTAssertNil(DMStart.conversationId(me: Self.me, peer: ""))
        // パスに入れられない id は作らない（`PathID`）
        XCTAssertNil(DMStart.conversationId(me: Self.me, peer: "../user"))
    }

    /// 「メッセージ」は**フォローしていると分かっている他人**にだけ（サーバーはフォローしていない人からの
    /// 新しい会話を 404 で断る）。ログインしていない・自分・ブロックの関係では出さない
    func testMessageButtonOnlyForPeopleYouFollow() async {
        XCTAssertTrue(DMStart.showsMessageButton(viewerId: Self.me, userId: Self.peer, isFollowing: true, blocked: []))
        XCTAssertFalse(DMStart.showsMessageButton(viewerId: Self.me, userId: Self.peer, isFollowing: false, blocked: []),
                       "フォローしていない人に出すと、押してから断られる")
        XCTAssertFalse(DMStart.showsMessageButton(viewerId: nil, userId: Self.peer, isFollowing: true, blocked: []))
        XCTAssertFalse(DMStart.showsMessageButton(viewerId: Self.me, userId: Self.me, isFollowing: true, blocked: []))
        XCTAssertFalse(DMStart.showsMessageButton(viewerId: Self.me, userId: Self.peer, isFollowing: true,
                                                  blocked: [Self.peer]))
    }

    /// 会話を読んだ 404 を空の会話として開くのは、入口から開いた `notFound` だけ
    func testOnlyNotFoundFromAStartOpensAnEmptyConversation() async {
        let missing = DMService.Refused(status: 404, message: "会話が見つかりません", code: "notFound")
        let noRoute = DMService.Refused(status: 404, message: "Not Found", code: nil)
        let blocked = DMService.Refused(status: 403, message: "ブロック中の相手には送れません", code: "blockedByMe")
        XCTAssertTrue(DMStart.opensEmpty(missing, starting: true))
        XCTAssertFalse(DMStart.opensEmpty(missing, starting: false), "受信箱から開いた消えた会話を空の会話にした")
        XCTAssertFalse(DMStart.opensEmpty(noRoute, starting: true), "道の無い 404 を「これから始まる」と読んだ")
        XCTAssertFalse(DMStart.opensEmpty(blocked, starting: true))
    }

    /// 新しいメッセージの一覧: 自分・退会した人・ブロックした人・重なりを落とし、並びはサーバーのまま
    func testPickerCandidates() async {
        let users = [
            FollowUser(id: "u-1", name: "夕焼けの人", deleted: nil, username: "yuyake"),
            FollowUser(id: Self.me, name: "自分", deleted: nil),
            FollowUser(id: "u-2", name: nil, deleted: true),
            FollowUser(id: "u-3", name: "港の写真家", deleted: false, username: "Minato"),
            FollowUser(id: "u-4", name: "ブロックした人", deleted: nil),
            FollowUser(id: "u-1", name: "夕焼けの人", deleted: nil, username: "yuyake"),
        ]
        let shown = DMStart.candidates(users, me: Self.me, blocked: ["u-4"])
        XCTAssertEqual(shown.map(\.id), ["u-1", "u-3"])
        // 名前で探す（親しい友達と同じ絞り方: @ を外す・大文字小文字・全角半角を区別しない）
        XCTAssertEqual(DMStart.filter(shown, query: "＠ＭＩＮＡ").map(\.id), ["u-3"])
        XCTAssertEqual(DMStart.filter(shown, query: "夕焼け").map(\.id), ["u-1"])
        XCTAssertEqual(DMStart.filter(shown, query: "  ").map(\.id), ["u-1", "u-3"], "空の語で絞った")
        // 選んだ人から会話に渡す相手（名前が無ければ「ユーザー」）
        let seed = DMStart.seed(FollowUser(id: "u-9", name: " ", deleted: nil, username: "nine"))
        XCTAssertEqual(seed, DMPeerSeed(id: "u-9", name: nil, username: "nine"))
        XCTAssertEqual(seed.name, DMText.name(nil, deleted: false))
    }

    /// 50人の外は人の検索で探す。**フォロー中の全員の ID に入っている人だけ**（フォローしていない人を並べない）
    func testSearchBeyondThePageKeepsOnlyPeopleYouFollow() async throws {
        let json = #"""
        [{"userId": "u-51", "displayName": "雪の駅", "username": "yukieki"},
         {"userId": "u-x", "displayName": "知らない人"},
         {"userId": "u-1", "displayName": "夕焼けの人"},
         {"userId": "u-52", "displayName": "ブロックした人"}]
        """#
        let profiles = try JSONDecoder.api.decode([UserProfile].self, from: Data(json.utf8))
        let hits = DMStart.searchHits(profiles, following: ["u-1", "u-51", "u-52"], me: Self.me,
                                      blocked: ["u-52"], excluding: ["u-1"])
        XCTAssertEqual(hits.map(\.id), ["u-51"])
        XCTAssertEqual(hits.first?.username, "yukieki")
    }

    /// 1通目の前の一言（送る前に決まりを言う）。サーバーの断り（3通・リンク）と同じ数・同じ言い方
    func testFirstMessageNoteSaysTheRulesBeforeSending() async {
        XCTAssertEqual(DMText.firstMessageNote(name: "B", language: "ja"),
                       "B さんが承認するまで、送れるのは文字3通までで、リンクは送れません")
        XCTAssertEqual(DMText.firstMessageNote(name: "B", language: "en"),
                       "Until B accepts, you can send up to 3 text messages, without links.")
        XCTAssertEqual(DMRules.requestLimit, 3)
        XCTAssertTrue(DMText.refusal(status: 429, code: "requestLimit", fallback: "", language: "ja").contains("3通"))
    }

    // MARK: - 見本のサーバー（UI テストの絵）

    /// `-JPPreviewDM` のときだけフォロー中を答える（公開の新着の作者が先・見本の会話の相手が後ろ）。
    /// まだ会話の無い相手への1通目は承認待ちで返る
    func testPreviewBackendAnswersFollowingOnlyWithTheDMFlag() async throws {
        let feed: [[String: Any]] = [
            ["id": "p1", "src": "https://img.test/p1.jpg", "userId": "author-a", "displayName": "作者A"],
            ["id": "p2", "src": "https://img.test/p2.jpg", "userId": "author-a"],
            ["id": "p3", "src": "https://img.test/p3.jpg", "uploadedBy": "author-b"],
            ["id": "p4", "src": "https://img.test/p4.jpg", "userId": "me"],
        ]
        func get(_ route: [String], dm: Bool) async -> PreviewBackend.Reply {
            await PreviewBackend.reply(method: "GET", route: route, body: nil, userId: "me",
                                       store: PreviewBackend.Store(), dm: dm, publicFeed: { feed },
                                       publicLikes: { _ in nil })
        }
        let off = await get(["users", "me", "following"], dm: false)
        XCTAssertNotEqual(off.status, 200, "鍵が無いのにフォロー中を答えた（ほかの UI テストのフォローが変わる）")

        let list = await get(["users", "me", "following"], dm: true)
        XCTAssertEqual(list.status, 200)
        let decoded = try JSONDecoder.api.decode(SocialService.FollowList.self, from: list.body)
        XCTAssertEqual(decoded.users.prefix(2).map(\.id), ["author-a", "author-b"])
        XCTAssertEqual(decoded.users.first?.name, "作者A")
        XCTAssertTrue(decoded.users.contains { $0.id == PreviewBackend.dmPeers[0].id }, "既にある会話の相手がいない")
        XCTAssertFalse(decoded.users.contains { $0.id == "me" })
        XCTAssertEqual(decoded.total, decoded.users.count)

        let ids = await get(["user", "following"], dm: true)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: ids.body) as? [String: Any])
        XCTAssertEqual(object["userIds"] as? [String], decoded.users.map(\.id))

        let conv = DMRules.conversationId("me", "author-a")
        let read = await get(["dm", conv], dm: true)
        XCTAssertEqual(read.status, 404, "まだ会話の無い相手の会話を答えた")
        let body = try JSONSerialization.data(withJSONObject: ["text": "はじめまして", "id": "client-0001"])
        let sent = await PreviewBackend.reply(method: "POST", route: ["dm", conv, "messages"], body: body, userId: "me",
                                              store: PreviewBackend.Store(), dm: true, publicLikes: { _ in nil })
        let result = try JSONDecoder.api.decode(DMSendResult.self, from: sent.body)
        XCTAssertEqual(result.state, .pending)
    }

    // MARK: - 配線

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

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

    /// プロフィール: 「メッセージ」は `canAct`（ログイン・他人・ブロックなし）の中で、さらにフォロー中だけ。
    /// 押すと同じ積み重ねに、その人との会話（まだ無ければ空の会話）を積む
    func testProfileMessageButtonWiring() async throws {
        let view = try source("Features/Profile/UserProfileView.swift")
        let header = slice(view, from: "private var header: some View {", to: "VStack(alignment: .leading, spacing: JPSpace.xxs)")
        XCTAssertTrue(header.contains("if canAct {"))
        XCTAssertTrue(header.contains("if showsMessageButton { messageButton }"), "フォローしていない人にも出している")
        let gate = slice(view, from: "private var showsMessageButton: Bool {", to: "\n    }\n")
        XCTAssertTrue(gate.contains("isFollowing: model.isFollowing"))
        XCTAssertTrue(gate.contains("blocked: hidden.blockedUserIds"))
        XCTAssertTrue(view.contains(".navigationDestination(isPresented: $showConversation)"))
        XCTAssertTrue(view.contains("DMStart.conversationId(me: auth.userId, peer: userId)"))
        XCTAssertTrue(view.contains("DMConversationView(conversationId: id,"))
        XCTAssertTrue(view.contains("startingWith: DMPeerSeed(id: userId, name: model.shownName,"))
        XCTAssertTrue(view.contains(#".accessibilityIdentifier("profile.message")"#))
        // 形は隣の「フォロー中 ▾」と同じ線（主ボタンは1画面に1つ）
        let parts = try source("Features/Profile/ProfileV2Parts.swift")
        let label = slice(parts, from: "struct ProfileMessageButtonLabel", to: "\n}\n")
        XCTAssertTrue(label.contains(".profileHeaderButton(filled: false)"))
        XCTAssertTrue(label.contains("DMText.messageButtonTitle"))
    }

    /// 会話 → 見出し → 相手のプロフィール →「メッセージ」で、同じ会話をもう1枚積まない（戻る）。
    /// 2枚積むと、どちらも10秒ごとに読み直していた（2026-11-10・確かめ役の指摘）
    func testMessageFromAProfileOpenedInTheConversationGoesBack() async throws {
        XCTAssertEqual(DMStart.messageAction(fromConversation: true), .backToConversation)
        XCTAssertEqual(DMStart.messageAction(fromConversation: false), .openConversation)
        XCTAssertEqual(DMStart.messageHint(fromConversation: true), "この人とのメッセージに戻ります")
        XCTAssertEqual(DMStart.messageHint(fromConversation: false), "この人とのメッセージを開きます")
        let conversation = try source("Features/Messages/DMConversationView.swift")
        XCTAssertTrue(conversation.contains("UserProfileView(userId: peerId, fromConversation: true)"),
                      "会話から開くプロフィールに印を渡していない")
        XCTAssertFalse(conversation.contains("UserProfileView(userId: peerId)"))
        let view = try source("Features/Profile/UserProfileView.swift")
        XCTAssertTrue(view.contains("var fromConversation = false"))
        let button = slice(view, from: "private var messageButton: some View {", to: ".accessibilityIdentifier(\"profile.message\")")
        XCTAssertTrue(button.contains("switch DMStart.messageAction(fromConversation: fromConversation) {"))
        XCTAssertTrue(button.contains("case .backToConversation: dismiss()"), "会話から来たのに会話を積み直す")
        XCTAssertTrue(button.contains(".accessibilityHint(DMStart.messageHint(fromConversation: fromConversation))"))
        // ほかの入口（受信箱・写真・検索…）から開くプロフィールは今までどおり積む（既定は false）
        XCTAssertEqual(try source("Features/Messages/DMConversationView.swift").components(separatedBy: "fromConversation: true").count - 1, 1)
    }

    /// 受信箱: 見出しの鉛筆 → 新しいメッセージ（シート）→ 選んだら閉じてから、その人との会話を積む
    func testInboxNewMessageWiring() async throws {
        let inbox = try source("Features/Messages/DMInboxView.swift")
        XCTAssertTrue(inbox.contains("case start(DMPeerSeed)"))
        XCTAssertTrue(inbox.contains(#"Image(systemName: "square.and.pencil")"#))
        XCTAssertTrue(inbox.contains(#".accessibilityIdentifier("dm.new.open")"#))
        XCTAssertTrue(inbox.contains("if auth.userId != nil { newMessageButton }"), "ログインしていない人に鉛筆を出している")
        let sheet = slice(inbox, from: ".sheet(isPresented: $showNewMessage, onDismiss: {", to: "DMNewMessageView")
        XCTAssertTrue(sheet.contains("route = .start(peer)"), "閉じてから会話を積んでいない")
        XCTAssertTrue(inbox.contains("DMConversationView(conversationId: id, startingWith: peer)"))
        XCTAssertTrue(inbox.contains("DMStart.conversationId(me: auth.userId, peer: peer.id)"))
        // 空の状態と一覧の下の文は始め方を言う（ストーリーへの返信だけではなくなった）
        XCTAssertFalse(inbox.contains("メッセージは、ストーリーへの返信から始まります。"))
        XCTAssertFalse(inbox.contains("ホームでストーリーを見る"))
        XCTAssertEqual(inbox.components(separatedBy: "DMText.startHint").count - 1, 2, "空の状態と一覧の下の両方")
        XCTAssertTrue(inbox.contains("actionTitle: DMText.newMessageTitle"))

        let picker = try source("Features/Messages/DMNewMessageView.swift")
        XCTAssertTrue(picker.contains("environment.social.following(userId: me)"), "フォロー中の一覧の口を使っていない")
        XCTAssertTrue(picker.contains("environment.social.myFollowingIds()"))
        XCTAssertTrue(picker.contains("DMStart.candidates(following, me: auth.userId, blocked: hidden.blockedUserIds)"))
        XCTAssertTrue(picker.contains("PeopleSearchField(query: $query"), "名前で探す欄が共通の部品でない")
        XCTAssertTrue(picker.contains("onPick(DMStart.seed(user))"))
        for part in ["JPLoadingState(kind: .people)", "ErrorBanner(", "フォローしている人がいません", "見つかりませんでした",
                     "圏外です。つながると一覧を読めます", "全 \\(total) 人のうち \\(following.count) 人を表示しています"] {
            XCTAssertTrue(picker.contains(part), part)
        }
        // 50人の外の検索は、フォロー中の全員の ID が読めたときだけ
        let beyond = slice(picker, from: "private func searchBeyond(_ text: String) async {", to: "\n    }\n")
        XCTAssertTrue(beyond.contains("hasMoreThanShown, let followingIds"))
        XCTAssertTrue(beyond.contains("DMStart.searchHits(profiles, following: followingIds"))
    }

    /// 会話: 会話を始める入口から開いたときだけ 404 `notFound` を空の会話として開く（受信箱の 404 は今までどおり）。
    /// 1通目の前に決まりを出し、送れたら会話を読み直して受信箱にも出す
    func testConversationOpensEmptyForANewPeer() async throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        XCTAssertTrue(view.contains("var startingWith: DMPeerSeed? = nil"))
        let load = slice(view, from: "private func load() async {", to: "private func poll() async {")
        let missing = load.range(of: "DMStart.opensEmpty(refused, starting: startingWith != nil)")?.lowerBound
        let gone = load.range(of: "refused.status == 404")?.lowerBound
        XCTAssertNotNil(missing, "まだ会話が無い相手を「表示できません」にしている")
        if let missing, let gone { XCTAssertLessThan(missing, gone, "404 の受け方が先に「表示できません」に落ちる") }
        XCTAssertTrue(load.contains("isNew = true"))
        // 承認前の残りは、会話を読めるまで手元で数える
        XCTAssertTrue(view.contains("isNew ? max(0, DMRules.requestLimit - newSent) : meta?.requestRemaining"))
        let composer = slice(view, from: "private var composer: some View {", to: "HStack(alignment: .bottom, spacing: 6)")
        XCTAssertTrue(composer.contains("DMText.firstMessageNote(name: peerName)"))
        if let first = composer.range(of: "isNew && newSent == 0")?.lowerBound,
           let note = composer.range(of: "DMText.requestNote(name: peerName, remaining: remaining)")?.lowerBound {
            XCTAssertLessThan(first, note)
        } else {
            XCTFail("1通目の前の一言が無い")
        }
        let deliver = slice(view, from: "private func deliver(text: String, clientId: String) async {", to: "private func accept() async")
        XCTAssertTrue(deliver.contains("await adoptCreatedConversation()"))
        let adopt = slice(view, from: "private func adoptCreatedConversation() async {", to: "\n    }\n")
        XCTAssertTrue(adopt.contains("isNew = false"))
        XCTAssertTrue(adopt.contains("store.refresh(service: environment.dm, owner: auth.userId)"), "受信箱に出ない")
        // まだ会話が無い間は「…」（通報・削除）を出さない
        XCTAssertTrue(view.contains("if phase == .loaded && !isNew { moreMenu }"))
        XCTAssertTrue(view.contains("メッセージを送れません"))
        XCTAssertTrue(view.contains(#".accessibilityIdentifier("dm.firstNote")"#))
    }

    /// 文言の決まり（新しい画面も）: 日英（`L`）・「捨てる」「撮りどき」を出さない・本文は 12pt 以上
    func testWordingOfTheNewScreens() async throws {
        for file in ["Features/Messages/DMNewMessageView.swift", "Features/Common/PeopleSearchField.swift",
                     "Features/Messages/DMInboxView.swift", "Features/Messages/DMConversationView.swift",
                     "Features/Profile/ProfileV2Parts.swift", "Core/Text/DirectMessages.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains("捨て"), file)
            XCTAssertFalse(text.contains("撮りどき"), file)
            let direct = text.range(of: #"Text\("[^"]*[ぁ-んァ-ン一-龥]"#, options: .regularExpression)
            XCTAssertNil(direct, "\(file): 英語の画面に日本語が出る")
            for size in [8, 9, 10, 11] {
                XCTAssertFalse(text.contains(".system(size: \(size))"), "\(file): \(size)pt の字")
            }
        }
        for text in [DMText.newMessageTitle, DMText.messageButtonTitle, DMText.startHint,
                     DMText.firstMessageNote(name: "A")] {
            XCTAssertFalse(text.contains("撮りどき") || text.contains("捨て"), text)
        }
    }
}
