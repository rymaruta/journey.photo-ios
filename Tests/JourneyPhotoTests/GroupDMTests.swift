import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// グループの DM（2026-11-20・札 #582・案「グループチャットを簡単に」の推奨 C）の決まり。
/// サーバーの形は journey.photo-web 7cc29632c の `api-user/src/groups.ts` から写した
final class GroupDMTests: XCTestCase {

    private static let me = "me-0000"

    private func user(_ id: String, _ name: String = "") -> FollowUser {
        FollowUser(id: id, name: name.isEmpty ? id : name, deleted: false)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - 2人以上でグループ・1人なら1対1

    func testTwoOrMorePeopleMakeAGroupAndOneIsOneToOne() {
        let ken = user("ken", "けん"), mio = user("mio", "みお")
        XCTAssertEqual(GroupPick.outcome(selected: [ken], mode: .start), .oneToOne(DMStart.seed(ken)))
        XCTAssertEqual(GroupPick.outcome(selected: [ken, mio], mode: .start), .create(["ken", "mio"]))
        XCTAssertEqual(GroupPick.outcome(selected: [], mode: .start), .none)
        // 主ボタンは押すと何が起きるかを言う（自分を入れた人数）
        XCTAssertEqual(GroupPick.mainTitle(selected: 1, mode: .start, language: "ja"), "メッセージを送る")
        XCTAssertEqual(GroupPick.mainTitle(selected: 2, mode: .start, language: "ja"), "3人で話す")
        XCTAssertNil(GroupPick.mainTitle(selected: 0, mode: .start, language: "ja"))
        // 1対1に足す: 相手と選んだ人でグループ（相手は外せない・自分と相手で2人）
        let peer = DMPeerSeed(id: "yu", name: "ゆう")
        XCTAssertEqual(GroupPick.outcome(selected: [mio], mode: .extend(peer: peer)), .create(["yu", "mio"]))
        XCTAssertEqual(GroupPick.mainTitle(selected: 1, mode: .extend(peer: peer), language: "ja"), "3人で話す")
        // グループに足す: もう居る人は足さない
        XCTAssertEqual(GroupPick.outcome(selected: [ken, mio], mode: .add(present: ["ken"], seatsLeft: 5)), .add(["mio"]))
        XCTAssertEqual(GroupPick.mainTitle(selected: 2, mode: .add(present: [], seatsLeft: 5), language: "ja"), "2人を足す")
    }

    /// グループの口が無いサーバーでは今の1対1のまま（押すとすぐ会話・主ボタンなし）
    func testSingleModeWithoutGroupsKeepsOneToOne() {
        XCTAssertEqual(GroupPick.startMode(groupsAvailable: false), .single)
        XCTAssertEqual(GroupPick.startMode(groupsAvailable: true), .start)
        XCTAssertFalse(GroupPick.isMulti(.single))
        XCTAssertNil(GroupPick.mainTitle(selected: 1, mode: .single, language: "ja"))
        XCTAssertEqual(GroupPick.outcome(selected: [user("a"), user("b")], mode: .single), .none, "1対1の形でグループを作らない")
    }

    // MARK: - 30人の上限

    func testThirtyPeopleLimit() {
        XCTAssertEqual(GroupRules.membersMax, 30)
        XCTAssertEqual(GroupPick.limit(.start), 29, "自分を入れて30人")
        XCTAssertEqual(GroupPick.limit(.extend(peer: DMPeerSeed(id: "p", name: "p"))), 28, "自分と相手を入れて30人")
        XCTAssertEqual(GroupPick.limit(.add(present: [], seatsLeft: 3)), 3)
        var picked: [FollowUser] = []
        for i in 0..<40 { picked = GroupPick.toggled(picked, user("u\(i)"), mode: .start) }
        XCTAssertEqual(picked.count, 29, "30人目から先は選べない")
        XCTAssertFalse(GroupPick.canSelectMore(count: 29, mode: .start))
        XCTAssertTrue(GroupPick.canSelectMore(count: 28, mode: .start))
        XCTAssertEqual(GroupPick.mainTitle(selected: 29, mode: .start, language: "ja"), "30人で話す")
        // 外すのはいつでもできる
        XCTAssertEqual(GroupPick.toggled(picked, user("u0"), mode: .start).count, 28)
        // 上限を越えた選び方からは作らない
        let over = (0..<30).map { user("x\($0)") }
        XCTAssertEqual(GroupPick.outcome(selected: over, mode: .start), .none)
        XCTAssertEqual(GroupText.fullNotice, L("グループは30人までです", "Groups can have up to 30 people."))
        XCTAssertEqual(GroupText.refusal(status: 403, code: "full", fallback: "", language: "ja"), "グループは30人までです")
    }

    // MARK: - 抜けた・外されたら送れない

    func testRemovedGroupCannotSend() throws {
        // サーバーが canSend: true を返しても、外された状態では送れない
        let page = try decode(GroupMessagesPage.self, """
        {"state":"removed","canSend":true,"seq":3,"messages":[{"id":"a","n":1,"from":"x","mine":false,"t":"2026-11-20T00:00:00.000Z","text":"やあ"}],"members":[]}
        """)
        XCTAssertEqual(page.state, .removed)
        XCTAssertFalse(page.canSend)
        let member = try decode(GroupMessagesPage.self, """
        {"state":"member","canSend":true,"seq":0,"messages":[],"members":[]}
        """)
        XCTAssertTrue(member.canSend)
        let removed = try decode(GroupThread.self, """
        {"groupId":"g1","name":null,"displayName":"けん、みお","faces":[],"memberCount":3,"createdAt":"2026-11-20T00:00:00.000Z","state":"removed","unread":4,"updatedAt":"2026-11-20T00:00:00.000Z"}
        """)
        XCTAssertTrue(removed.isRemoved)
        XCTAssertFalse(removed.showsUnread, "外されたグループで点を出さない")
        XCTAssertEqual(GroupText.excerpt(removed, language: "ja"), "グループから外されました")
        // サーバー ed0e0dc70 の外された人の行（人数・最後の通・顔は来ない。名前が無ければ「外されたグループ」）
        let bare = try decode(GroupThread.self, """
        {"groupId":"g9","name":null,"displayName":"外されたグループ","faces":[],"state":"removed","unread":0,"updatedAt":"2026-11-20T00:00:00.000Z"}
        """)
        XCTAssertTrue(bare.isRemoved)
        XCTAssertEqual(bare.info.memberCount, 0)
        XCTAssertNil(bare.last)
        XCTAssertEqual(GroupText.title(bare.info), "外されたグループ")
        let bareDetail = try decode(GroupDetail.self, """
        {"state":"removed","group":{"groupId":"g9","name":null,"displayName":"外されたグループ","faces":[]}}
        """)
        XCTAssertEqual(bareDetail, .removed(group: GroupInfo(groupId: "g9", name: nil, displayName: "外されたグループ", faces: [], memberCount: 0)))
        // 知らない状態はメンバーに倒さない
        let odd = try decode(GroupThread.self, """
        {"groupId":"g1","displayName":"x","faces":[],"memberCount":3,"state":"something","unread":1,"updatedAt":""}
        """)
        XCTAssertTrue(odd.isRemoved)
        // 抜けたグループは一覧から外す
        let inbox = GroupInbox(groups: [removed], invites: [])
        XCTAssertTrue(inbox.removing("g1").groups.isEmpty)
    }

    // MARK: - 招待中は中身を出さない

    func testInvitedDetailHasNoContent() throws {
        let detail = try decode(GroupDetail.self, """
        {"state":"invited","group":{"groupId":"g2","name":"週末の写真散歩","displayName":"週末の写真散歩","faces":[{"id":"c","name":"山の朝"}],"memberCount":3},"invitedBy":{"id":"c","name":"山の朝"}}
        """)
        XCTAssertNil(detail.membership, "招待中にメンバーの一覧を持たない")
        guard case .invited(let group, let by) = detail else { return XCTFail("招待の形で読めない") }
        XCTAssertEqual(group.displayName, "週末の写真散歩")
        XCTAssertEqual(by.name, "山の朝")
        XCTAssertEqual(GroupText.invitedLine(by: "ゆう", language: "ja"), "ゆう さんがあなたを入れようとしています")
        XCTAssertEqual(GroupText.groupSize(3, language: "ja"), "3人のグループ")
        // 招待の画面は会話を読まない（参加するまで話は1通も見えない）
        let view = try source("Features/Messages/GroupInviteView.swift")
        let inviteBody = slice(view, from: "private var inviteBody: some View {", to: "private func join() async {")
        XCTAssertFalse(inviteBody.contains("groups.messages"), "招待の画面で会話を読んでいる")
        XCTAssertFalse(inviteBody.contains("DMPhotoCard"), "招待の画面で写真を出している")
    }

    // MARK: - 口が無いサーバーで入口を出さない

    @MainActor
    func testNoGroupEntranceWhenTheServerHasNoGroupsRoute() async throws {
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: StubTokenProvider(token: "t"),
                            session: URLSession(configuration: config))
        let service = GroupService(api: api)
        let store = DMInboxStore()
        // API Gateway の「道が無い」（本番にまだ口が無い）
        StubProtocol.respond(status: 404, body: #"{"message":"Not Found"}"#)
        await store.refreshGroups(service: service, owner: Self.me)
        XCTAssertFalse(store.groupsAvailable, "口の無いサーバーでグループの入口を出している")
        XCTAssertEqual(GroupPick.startMode(groupsAvailable: store.groupsAvailable), .single)
        // 古いサーバーの 403 も同じ
        StubProtocol.respond(status: 403, body: #"{"message":"Forbidden"}"#)
        await store.refreshGroups(service: service, owner: Self.me)
        XCTAssertFalse(store.groupsAvailable)
        // 読めたら入口を出す
        StubProtocol.respond(status: 200, body: #"{"groups":[],"invites":[]}"#)
        await store.refreshGroups(service: service, owner: Self.me)
        XCTAssertTrue(store.groupsAvailable)
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/groups")
        // 一度読めたあとは、圏外・混み合いで入口を消さない
        StubProtocol.respond(status: 503, body: #"{"error":"busy"}"#)
        await store.refreshGroups(service: service, owner: Self.me)
        XCTAssertTrue(store.groupsAvailable)
        // 人が替わったら、また読めるまで出さない
        store.use(owner: "someone-else")
        XCTAssertFalse(store.groupsAvailable)
    }

    /// 入口の付け方: 新しいメッセージは `groupsAvailable` で形を選び、1対1の「人を足す」も同じ旗を見る
    func testEntrancesFollowGroupsAvailable() throws {
        let inbox = try source("Features/Messages/DMInboxView.swift")
        XCTAssertTrue(inbox.contains("GroupPick.startMode(groupsAvailable: store.groupsAvailable)"))
        XCTAssertTrue(inbox.contains("store.groupsAvailable ? store.groups.groups : []"), "口が無いのに一覧にグループを混ぜている")
        let conversation = try source("Features/Messages/DMConversationView.swift")
        XCTAssertTrue(conversation.contains("store.groupsAvailable && peerId != nil && !isNew"))
        XCTAssertTrue(conversation.contains("if canAddPeople {"))
        let requests = try source("Features/Messages/DMRequestsView.swift")
        XCTAssertTrue(requests.contains("guard store.groupsAvailable else { return [] }"))
    }

    // MARK: - 空の言葉は入力欄に入るだけ

    func testStartersOnlyFillTheField() throws {
        XCTAssertEqual(GroupRules.starters, [L("どこ行く？", "Where to?"), L("いつ空いてる？", "When are you free?")])
        XCTAssertEqual(GroupRules.starterDraft(current: "", adding: "どこ行く？"), "どこ行く？")
        XCTAssertEqual(GroupRules.starterDraft(current: "来月", adding: "いつ空いてる？"), "来月 いつ空いてる？", "書きかけを消さない")
        XCTAssertEqual(GroupRules.starterDraft(current: "  ", adding: "どこ行く？"), "どこ行く？")
        XCTAssertEqual(GroupRules.starterDraft(current: String(repeating: "あ", count: 499), adding: "どこ行く？").count, 500)
        // 押したときは欄に入れて焦点を当てるだけ（送らない・AI を呼ばない）
        let view = try source("Features/Messages/GroupConversationView.swift")
        let chip = slice(view, from: "PillChip(title: phrase, selected: false) {", to: ".accessibilityIdentifier(\"group.starter\")")
        XCTAssertTrue(chip.contains("draft = GroupRules.starterDraft(current: draft, adding: phrase)"))
        XCTAssertFalse(chip.contains("send("), "候補を押しただけで送っている")
        XCTAssertFalse(chip.contains("deliver("))
        XCTAssertFalse(view.contains("tripAI") || view.contains("environment.ask"), "空の言葉に AI を使っている")
    }

    // MARK: - 会話の並び

    private func msg(_ id: String, from: String, mine: Bool = false, _ t: String, event: GroupEvent? = nil) -> DMMessage {
        DMMessage(id: id, from: from, mine: mine, text: event == nil ? id : "", t: t, groupEvent: event)
    }

    func testRowsShowSenderOnceAndTimeAtTheEnd() {
        let rows = GroupRows.build([
            msg("e", from: "yu", "2026-11-20T00:00:00.000Z", event: GroupEvent(type: "created")),
            msg("m1", from: "me", mine: true, "2026-11-20T00:01:00.000Z"),
            msg("k1", from: "ken", "2026-11-20T00:02:00.000Z"),
            msg("m2", from: "mio", "2026-11-20T00:03:00.000Z"),
            msg("m3", from: "mio", "2026-11-20T00:03:30.000Z"),
        ], calendar: Self.utc)
        XCTAssertEqual(rows.map(\.showsSender), [false, false, true, true, false], "同じ人の続きは2通目から名前を省く")
        XCTAssertTrue(rows[0].isEvent)
        XCTAssertNotNil(rows[2].time, "次が別の人なら時刻を出す（相手どうしでも分ける）")
        XCTAssertNil(rows[3].time, "同じ人の続きで5分以内は最後の1通だけ")
        XCTAssertNotNil(rows[4].time)
        XCTAssertTrue(rows[4].joinsPrevious)
        XCTAssertFalse(rows[3].joinsPrevious, "別の人の吹き出しとつなげている")
        XCTAssertTrue(GroupRows.hasConversation([msg("m", from: "a", "2026-11-20T00:00:00.000Z")]))
        XCTAssertFalse(GroupRows.hasConversation([msg("e", from: "a", "2026-11-20T00:00:00.000Z", event: GroupEvent(type: "created"))]),
                       "作った1行だけなら空の会話（はじめの一言の候補を出す）")
    }

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testEventLines() {
        let names = ["yu": "ゆう", "ken": "けん", "mio": "みお"]
        XCTAssertEqual(GroupText.event(GroupEvent(type: "created"), actor: "yu", names: names, me: Self.me, language: "ja"),
                       "ゆうがグループを作りました")
        XCTAssertEqual(GroupText.event(GroupEvent(type: "added", targets: ["ken", "mio"]), actor: Self.me, names: names,
                                       me: Self.me, language: "ja"), "あなたがけん、みおを足しました")
        XCTAssertEqual(GroupText.event(GroupEvent(type: "renamed", name: "金沢 秋の旅"), actor: "ken", names: names,
                                       me: Self.me, language: "ja"), "けんが名前を「金沢 秋の旅」にしました")
        XCTAssertEqual(GroupText.event(GroupEvent(type: "left"), actor: "zzz", names: names, me: Self.me, language: "ja"),
                       "メンバーが抜けました", "引けない名前を「名前未設定さん」と言っている")
        for type in ["created", "added", "joined", "left", "removed", "renamed"] {
            let text = GroupText.event(GroupEvent(type: type, targets: ["ken"]), actor: "yu", names: names, me: nil, language: "ja")
            XCTAssertFalse(text.contains("・") || text.contains("·"), "中黒で区切っている: \(text)")
        }
    }

    // MARK: - 受信箱（時刻の順に混ぜる・重ねた顔）

    func testInboxMixesByTimeAndExcerpts() throws {
        let inbox = try decode(GroupInbox.self, """
        {"groups":[{"groupId":"6f1c2a10-0000-4000-8000-000000000001","name":null,"displayName":"けん、みお","faces":[{"id":"ken","name":"けん"},{"id":"mio","name":"みお"}],"memberCount":3,"createdAt":"2026-11-20T00:00:00.000Z","state":"member","unread":2,"last":{"from":"mio","t":"2026-11-20T09:20:00.000Z","excerpt":"紅葉の時期がいいな","fromName":"みお","mine":false},"updatedAt":"2026-11-20T09:20:00.000Z"},
                   {"broken":true}],
         "invites":[{"groupId":"g2","name":"週末","displayName":"週末","faces":[],"memberCount":3,"invitedBy":{"id":"c","name":"山の朝"},"invitedAt":"2026-11-20T00:00:00.000Z"}]}
        """)
        XCTAssertEqual(inbox.groups.count, 1, "読めない1行で一覧ごと落とさない")
        XCTAssertEqual(inbox.invites.count, 1)
        let group = inbox.groups[0]
        XCTAssertEqual(group.info.faces.map(\.id), ["ken", "mio"])
        XCTAssertEqual(GroupText.title(group.info), "けん、みお", "名前の無いグループはサーバーの displayName")
        XCTAssertEqual(GroupText.excerpt(group, language: "ja"), "みお: 紅葉の時期がいいな")
        XCTAssertTrue(group.showsUnread)
        XCTAssertEqual(inbox.unreadGroups(), 1)
        XCTAssertEqual(inbox.markingRead(group.id).unreadGroups(), 0)

        let dm = DMThread(id: "a_b", peerId: "b", name: "けん", t: "2026-11-20T08:00:00.000Z", excerpt: "x", unread: 0, state: .inbox)
        let newer = DMThread(id: "a_c", peerId: "c", name: "はな", t: "2026-11-20T10:00:00.000Z", excerpt: "y", unread: 0, state: .inbox)
        let trip = TripInboxItem(planId: "p", title: "金沢", members: [], unread: 0,
                                 last: .init(from: "x", fromName: "そら", mine: false, t: "2026-11-20T09:00:00Z", excerpt: "宿", event: nil),
                                 updatedAt: nil)
        let merged = MessagesInboxItem.merged(dms: [newer, dm], trips: [trip], groups: [group])
        XCTAssertEqual(merged.map(\.id), ["dm:a_c", "group:\(group.id)", "trip:p", "dm:a_b"], "時刻の順に混ざっていない")

        // 自分が最後・写真だけ・真ん中の1行
        let mine = GroupThread(info: group.info, last: GroupLast(from: Self.me, t: "x", excerpt: "ありがとう", fromName: "わたし", mine: true),
                               updatedAt: "x")
        XCTAssertEqual(GroupText.excerpt(mine, language: "ja"), "あなた: ありがとう")
        let photo = GroupThread(info: group.info, last: GroupLast(from: "ken", t: "x", excerpt: "写真を送りました", fromName: "けん", mine: false),
                                updatedAt: "x")
        XCTAssertEqual(GroupText.excerpt(photo, language: "ja"), "けん: 写真が届きました")
        let created = GroupThread(info: group.info, last: GroupLast(from: "ken", t: "x", excerpt: "", event: "created", fromName: "けん", mine: false),
                                  updatedAt: "x")
        XCTAssertEqual(GroupText.excerpt(created, language: "ja"), "けんがグループを作りました")
    }

    @MainActor
    func testStoreCountsGroupUnreadAndInvites() async throws {
        let store = DMInboxStore()
        let info = GroupInfo(groupId: "g1", name: nil, displayName: "けん、みお", faces: [], memberCount: 3)
        let groups = GroupInbox(groups: [GroupThread(info: info, unread: 1,
                                                     last: GroupLast(from: "ken", t: "x", excerpt: "やあ", fromName: "けん", mine: false),
                                                     updatedAt: "x")],
                                invites: [GroupInvite(info: GroupInfo(groupId: "g2", name: "週末", displayName: "週末", faces: [], memberCount: 3),
                                                      invitedBy: GroupFace(id: "blocked", name: "x"), invitedAt: "x"),
                                          GroupInvite(info: GroupInfo(groupId: "g3", name: "朝", displayName: "朝", faces: [], memberCount: 2),
                                                      invitedBy: GroupFace(id: "c", name: "y"), invitedAt: "x")])
        store.setForTesting(.empty, owner: Self.me, groups: groups)
        XCTAssertTrue(store.hasUnread(hiding: []), "未読のグループで吹き出しの点が出ない")
        XCTAssertEqual(store.requestTotal(hiding: ["blocked"]), 1, "ブロックした人からの招待を数えている")
        store.applyGroups { $0.markingRead("g1") }
        XCTAssertFalse(store.hasUnread(hiding: []))
        // 口が無いサーバー（読めていない）では数えない
        let empty = DMInboxStore()
        empty.setForTesting(.empty, owner: Self.me)
        XCTAssertFalse(empty.groupsAvailable)
        XCTAssertEqual(empty.requestTotal(hiding: []), 0)
    }

    // MARK: - 応答の形（groups.ts）

    func testDecodesServerShapes() throws {
        let created = try decode(GroupChange.self, """
        {"state":"member","group":{"groupId":"g1","name":null,"displayName":"けん、みお","faces":[{"id":"ken","name":"けん"},{"id":"mio","name":"みお"}],"memberCount":3,"createdAt":"2026-11-20T00:00:00.000Z"},
         "isOwner":true,"muted":false,"membersMax":30,
         "members":[{"id":"me","name":"わたし","owner":true},{"id":"ken","name":"けん","username":"ken_trip"},{"id":"mio","name":"みお","blocked":true}],
         "invited":[{"id":"sora","name":"そら","invitedBy":"me"}],"notAdded":1}
        """)
        guard let m = created.detail.membership else { return XCTFail("メンバーの形で読めない") }
        XCTAssertTrue(m.isOwner)
        XCTAssertEqual(m.members.first?.owner, true)
        XCTAssertEqual(m.members.last?.blocked, true)
        XCTAssertEqual(m.seatsUsed, 4)
        XCTAssertEqual(m.seatsLeft, 26)
        XCTAssertEqual(m.present, ["me", "ken", "mio", "sora"])
        XCTAssertEqual(created.notAdded, 1)
        // 作る口は invitedNow を返さない: 招待中の人を数えて知らせる（2026-11-20 確かめ役の指摘）
        XCTAssertEqual(GroupReady(change: created).invitedCount, 1)
        XCTAssertEqual(GroupReady(change: created).notice, "1人に招待を送りました。参加するとここで話せます\n1人は入れられませんでした")
        XCTAssertNil(created.detail.group.name)

        let added = try decode(GroupChange.self, """
        {"state":"member","group":{"groupId":"g1","name":"金沢","displayName":"金沢","faces":[],"memberCount":4},"isOwner":false,"muted":true,"membersMax":30,
         "members":[],"invited":[],"added":["sora"],"invitedNow":["hana"],"notAdded":0}
        """)
        XCTAssertEqual(added.added, ["sora"])
        XCTAssertEqual(added.invitedNow, ["hana"])
        XCTAssertEqual(added.detail.membership?.muted, true)
        XCTAssertEqual(GroupReady(change: added).notice, "1人に招待を送りました。参加するとここで話せます")

        let page = try decode(GroupMessagesPage.self, """
        {"state":"member","canSend":true,"seq":4,"messages":[
          {"id":"1","n":1,"from":"yu","mine":false,"t":"2026-11-20T00:00:00.000Z","event":{"type":"created"}},
          {"id":"2","n":2,"from":"me","mine":true,"t":"2026-11-20T00:01:00.000Z","text":"来月の金沢"},
          {"id":"3","n":3,"from":"ken","mine":false,"t":"2026-11-20T00:02:00.000Z","photo":{"id":"p1","state":"live","src":"https://x/p.jpg","ownerId":"ken"}},
          {"id":"4","n":4,"from":"ken","mine":false,"t":"2026-11-20T00:03:00.000Z","photo":{"id":"p2","state":"gone"}},
          {"broken":1}],
         "members":[{"id":"yu","name":"ゆう"},{"id":"ken","name":"けん"}]}
        """)
        XCTAssertEqual(page.messages.count, 4, "読めない1通で会話ごと落とさない")
        let dm = page.messages.map(\.asDM)
        XCTAssertEqual(dm[0].groupEvent?.type, "created")
        XCTAssertEqual(dm[1].bubbleText, "来月の金沢")
        XCTAssertTrue(dm[2].hasPhoto)
        XCTAssertTrue(dm[2].photoOnly, "写真だけの通に吹き出しを出している")
        XCTAssertEqual(DMPhotoCardState.of(dm[2], blocked: []), .live(DMPhotoQuote(id: "p1", state: "live", src: "https://x/p.jpg", ownerId: "ken")))
        XCTAssertEqual(DMPhotoCardState.of(dm[3], blocked: []), .gone)
        XCTAssertEqual(DMPhotoCardState.of(dm[2], blocked: ["ken"]), .gone, "ブロックした人の写真を出している")
    }

    // MARK: - 確かめ役の指摘（2026-11-20）

    /// 全員が招待になった作り方でも、招待を送ったと分かる（会話の人数は自分だけ）
    func testAllInvitedOnCreateIsAnnounced() throws {
        let created = try decode(GroupChange.self, """
        {"state":"member","group":{"groupId":"g1","name":null,"displayName":"グループ","faces":[],"memberCount":1},
         "isOwner":true,"muted":false,"membersMax":30,"members":[{"id":"me","name":"わたし","owner":true}],
         "invited":[{"id":"a","name":"a","invitedBy":"me"},{"id":"b","name":"b","invitedBy":"me"}],"notAdded":0}
        """)
        XCTAssertEqual(GroupReady(change: created).notice, "2人に招待を送りました。参加するとここで話せます")
        let plain = try decode(GroupChange.self, """
        {"state":"member","group":{"groupId":"g1","displayName":"x","faces":[],"memberCount":3},"members":[],"invited":[],"notAdded":0}
        """)
        XCTAssertNil(GroupReady(change: plain).notice)
    }

    /// ブロックした人の通だけが増えた（サーバーが最後の1通を隠した）グループに未読の点を出さない
    func testHiddenLastIsNotUnread() throws {
        let hidden = try decode(GroupThread.self, """
        {"groupId":"g1","displayName":"x","faces":[],"memberCount":3,"state":"member","unread":2,"updatedAt":"2026-11-20T00:00:00.000Z"}
        """)
        XCTAssertFalse(hidden.showsUnread, "隠された通だけで未読の点が出る")
        XCTAssertEqual(GroupInbox(groups: [hidden], invites: []).unreadGroups(), 0)
        let shown = GroupThread(info: hidden.info, unread: 2,
                                last: GroupLast(from: "a", t: "x", excerpt: "やあ", fromName: "a", mine: false), updatedAt: "x")
        XCTAssertTrue(shown.showsUnread)
    }

    /// どちらの欄も無い 2xx は「口が無い」と同じ（入口を出さない）
    @MainActor
    func testEmptyBodyIsNotAGroupsRoute() async throws {
        XCTAssertThrowsError(try decode(GroupInbox.self, "{}"))
        XCTAssertThrowsError(try decode(GroupInbox.self, #"{"message":"ok"}"#))
        XCTAssertNoThrow(try decode(GroupInbox.self, #"{"groups":[]}"#))
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: StubTokenProvider(token: "t"),
                            session: URLSession(configuration: config))
        let store = DMInboxStore()
        StubProtocol.respond(status: 200, body: "{}")
        await store.refreshGroups(service: GroupService(api: api), owner: Self.me)
        XCTAssertFalse(store.groupsAvailable, "中身の無い 200 で入口を出している")
    }

    /// 15 秒ごとの読み直しは会話だけ。メンバーが変わる1行が新しく来たときだけ詳しい中身を読む
    func testDetailIsReloadedOnlyOnMemberEvents() throws {
        let old = [msg("e1", from: "a", "2026-11-20T00:00:00.000Z", event: GroupEvent(type: "created")),
                   msg("t1", from: "a", "2026-11-20T00:01:00.000Z")]
        XCTAssertFalse(GroupRows.changesMembers(old: old, new: old + [msg("t2", from: "b", "2026-11-20T00:02:00.000Z")]))
        XCTAssertFalse(GroupRows.changesMembers(old: old, new: old), "同じ1行で読み直している")
        for type in ["added", "joined", "left", "removed", "renamed"] {
            XCTAssertTrue(GroupRows.changesMembers(old: old, new: old + [msg("x", from: "a", "2026-11-20T00:03:00.000Z",
                                                                         event: GroupEvent(type: type))]), type)
        }
        let view = try source("Features/Messages/GroupConversationView.swift")
        let poll = slice(view, from: "private func poll() async {", to: "// MARK: - 送る")
        XCTAssertTrue(poll.contains("await load(quiet: true, withDetail: false)"), "15 秒ごとに詳しい中身も読んでいる")
        let load = slice(view, from: "private func load(quiet: Bool = false, withDetail: Bool = true) async {", to: "private func poll()")
        XCTAssertTrue(load.contains("withDetail || GroupRows.changesMembers(old: log.messages, new: fresh)"))
    }

    /// 相手の顔の当たりは 44（見た目は 28）。相手の写真だけの通にも通報・ブロック。ブロックした相手の1対1に「人を足す」を出さない。
    /// 開いている間に外されたら、詳しい画面を外された形にする
    func testReviewWiring() throws {
        XCTAssertEqual(GroupLook.senderAvatar + GroupLook.senderHitSlack * 2, WebTheme.minTapTarget)
        let view = try source("Features/Messages/GroupConversationView.swift")
        let face = slice(view, from: "Button { profileTarget = message.from } label: {", to: ".accessibilityLabel(")
        XCTAssertTrue(face.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"), "顔の当たりが 28 のまま")
        XCTAssertTrue(face.contains(".padding(-GroupLook.senderHitSlack)"), "当たりを広げた分で並びがずれる")
        XCTAssertTrue(view.contains("menu: { theirMenu(message, name: name, text: nil) }"), "相手の写真の札から通報できない")
        let conversation = try source("Features/Messages/DMConversationView.swift")
        XCTAssertTrue(conversation.contains("!isDeletedPeer && !iBlockedPeer"), "ブロックした相手との1対1に「人を足す」を出している")
        let detail = try source("Features/Messages/GroupDetailView.swift")
        XCTAssertTrue(detail.contains("private var current: GroupMembership? { gone ? nil : (membership ?? seed) }"),
                      "外されても操作を出している")
        let load = slice(detail, from: "private func load() async {", to: "private func apply(")
        XCTAssertTrue(load.contains("gone = true"))
        XCTAssertEqual(GroupText.name("zzz", in: [:], me: nil, language: "ja"), "メンバー")
    }

    /// 名前を外すときは欄を null で送る（欄が無いと「変えない」になる・サーバーの `"name" in body`）
    func testRenameToNilSendsNull() throws {
        let cleared = String(data: try JSONEncoder().encode(GroupNameBody(name: nil)), encoding: .utf8)
        XCTAssertEqual(cleared, #"{"name":null}"#)
        let named = String(data: try JSONEncoder().encode(GroupNameBody(name: "金沢")), encoding: .utf8)
        XCTAssertEqual(named, #"{"name":"金沢"}"#)
    }

    // MARK: - 見本の通信（UI テストの作り物の口）が本物の形と合う

    func testPreviewBackendMatchesTheShapes() async throws {
        let store = PreviewBackend.GroupStore()
        let me = "preview-me"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func call(_ method: String, _ parts: [String], _ json: [String: Any] = [:]) throws -> (Int, Data) {
            let reply = try XCTUnwrap(PreviewBackend.groupReply(method: method, parts: parts, json: json, me: me, now: now,
                                                                names: [:], store: store))
            return (reply.status, reply.body)
        }
        let (s1, b1) = try call("GET", ["groups"])
        XCTAssertEqual(s1, 200)
        let inbox = try JSONDecoder().decode(GroupInbox.self, from: b1)
        XCTAssertEqual(inbox.groups.count, 1)
        XCTAssertEqual(inbox.invites.count, 1)
        // 作る → 送る → 人を足す → 抜ける
        let peers = PreviewBackend.dmPeers
        let (s2, b2) = try call("POST", ["groups"], ["memberIds": [peers[0].id, peers[1].id]])
        XCTAssertEqual(s2, 201)
        let created = try JSONDecoder().decode(GroupChange.self, from: b2)
        let gid = created.detail.group.groupId
        XCTAssertTrue(PathID.isSafe(gid))
        XCTAssertEqual(created.detail.group.memberCount, 3)
        let (_, b3) = try call("POST", ["groups", gid, "messages"], ["text": "どこ行く？", "id": "client-0001"])
        XCTAssertNoThrow(try JSONDecoder().decode([String: GroupMessage].self, from: b3))
        let (_, b4) = try call("POST", ["groups", gid, "members"], ["userIds": [peers[2].id]])
        let addedChange = try JSONDecoder().decode(GroupChange.self, from: b4)
        XCTAssertEqual(addedChange.added, [peers[2].id])
        XCTAssertEqual(addedChange.detail.group.memberCount, 4)
        let (_, b5) = try call("GET", ["groups", gid, "messages"])
        let page = try JSONDecoder().decode(GroupMessagesPage.self, from: b5)
        XCTAssertEqual(page.messages.map { $0.event?.type ?? "text" }, ["created", "text", "added"])
        let (s6, _) = try call("DELETE", ["groups", gid, "members", me])
        XCTAssertEqual(s6, 200)
        let (s7, _) = try call("GET", ["groups", gid])
        XCTAssertEqual(s7, 404, "抜けたグループが読める")
        // 30人を越えて作れない
        let many = (0..<30).map { "u\($0)" }
        let (s8, b8) = try call("POST", ["groups"], ["memberIds": many])
        XCTAssertEqual(s8, 403)
        XCTAssertTrue(String(data: b8, encoding: .utf8)?.contains("\"full\"") == true)
        // 招待: 中身は名前・入れた人・人数だけ。参加すると入った後の話だけ
        let (_, b9) = try call("GET", ["groups", PreviewBackend.groupInviteId])
        XCTAssertNil(try JSONDecoder().decode(GroupDetail.self, from: b9).membership)
        let (s10, _) = try call("GET", ["groups", PreviewBackend.groupInviteId, "messages"])
        XCTAssertEqual(s10, 404, "招待中に会話が読める")
        _ = try call("POST", ["groups", PreviewBackend.groupInviteId, "join"])
        let (_, b11) = try call("GET", ["groups", PreviewBackend.groupInviteId, "messages"])
        let joined = try JSONDecoder().decode(GroupMessagesPage.self, from: b11)
        XCTAssertEqual(joined.messages.map { $0.event?.type ?? "text" }, ["joined"], "入る前の話が見えている")
    }

    // MARK: - 言葉の決まり

    func testWording() throws {
        for file in ["Features/Messages/GroupConversationView.swift", "Features/Messages/GroupDetailView.swift",
                     "Features/Messages/GroupInviteView.swift", "Features/Messages/GroupParts.swift",
                     "Core/Text/GroupMessages.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains("捨て"), file)
            XCTAssertFalse(text.contains("撮りどき"), file)
            let direct = text.range(of: #"Text\("[^"]*[ぁ-んァ-ン一-龥]"#, options: .regularExpression)
            XCTAssertNil(direct, "\(file): 英語の画面に日本語が出る")
            // 画面の文で「・」「·」で区切らない（L("…") の中）
            for line in text.split(separator: "\n") where line.contains("L(\"") {
                XCTAssertFalse(line.contains("・") || line.contains("·"), "\(file): \(line)")
            }
        }
        // 判断は「2026-11-20 判断」と注記してある
        XCTAssertTrue(try source("Core/Text/GroupMessages.swift").contains("2026-11-20 判断"))
        // 危険の行は板の danger（系統の赤を画面の行に出さない）
        let detail = try source("Features/Messages/GroupDetailView.swift")
        XCTAssertTrue(detail.contains(".foregroundStyle(WebTheme.danger)"))
        XCTAssertFalse(detail.contains("Color.red"))
    }

    // MARK: - 他人の写真は、その人のもの

    /// グループでも写真の札は DM と同じ部品（縮小版を見せて持ち主の頁へ連れて行くだけ）。保存・共有・ストーリーの道を作らない
    func testNoNewWayToTakeOthersPhotos() throws {
        for file in ["Features/Messages/GroupConversationView.swift", "Features/Messages/GroupDetailView.swift",
                     "Features/Messages/GroupInviteView.swift", "Features/Messages/GroupParts.swift"] {
            let text = try source(file)
            for banned in ["ShareLink", "UIImageWriteToSavedPhotosAlbum", "UIActivityViewController", "PHPhotoLibrary",
                           "StoryComposer", "UIPasteboard.general.image"] {
                XCTAssertFalse(text.contains(banned), "\(file): \(banned)")
            }
        }
        let conversation = try source("Features/Messages/GroupConversationView.swift")
        XCTAssertTrue(conversation.contains("DMPhotoCard(message: message"), "写真の札を DM と別に作っている")
        XCTAssertTrue(conversation.contains("DMComposer("), "入力欄を DM と別に作っている")
        XCTAssertTrue(conversation.contains("DMBubble("))
        XCTAssertTrue(conversation.contains("DMThreadLog()"))
        // グループのアイコンは写真にしない（重ねた顔だけ）
        XCTAssertFalse(try source("Features/Messages/GroupParts.swift").contains("RemoteImage"))
    }

    // MARK: - 下ごしらえ

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/\(path)"), encoding: .utf8)
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let a = text.range(of: start) else { return "" }
        let rest = text[a.upperBound...]
        guard let b = rest.range(of: end) else { return String(rest) }
        return String(rest[..<b.lowerBound])
    }
}
