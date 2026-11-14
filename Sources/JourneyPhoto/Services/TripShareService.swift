import Foundation

/// 旅行プランを仲間と使う口（2026-11-12・資料「SNS をもっと SNS に」2b・サーバーの `api-user/src/tripShare.ts`）。
///
/// 日程を直す・消す（抜ける）は今の口（`TripPlanService`）のまま。ここは共有する・仲間・招待リンク・会話・受信箱だけ。
/// - 仲間でない人には、サーバーはプランの有無も教えない（404）
/// - 直接の共有（`share(planId:with:)`）は、DM の会話が承認済みの相手だけ（サーバーが確かめる）
/// - UI テストの見本（Debug・`TripPlanFixture.isOn`）のときはサーバーへ送らない（`TripShareFixtureStore`）
struct TripShareService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private func encoded(_ value: String) throws -> String { try PathID.segment(value) }

    private struct ShareBody: Encodable { var withUserId: String? }
    private struct Empty: Encodable {}
    private struct SendBody: Encodable { let text: String }

    /// 共有する（作った人だけ）。`with` を渡すと、その人をすぐ仲間に入れる（DM の相手）
    func share(planId: String, with userId: String? = nil) async throws -> TripShareDetail {
        if TripPlanFixture.isOn { return await TripShareFixtureStore.shared.share(planId: planId, with: userId) }
        return try await api.authorized(.post, "/trip-share/\(encoded(planId))", body: ShareBody(withUserId: userId),
                                        as: TripShareDetail.self)
    }

    func detail(planId: String) async throws -> TripShareDetail {
        if TripPlanFixture.isOn { return try await TripShareFixtureStore.shared.detail(planId: planId) }
        return try await api.authorized(.get, "/trip-share/\(encoded(planId))", as: TripShareDetail.self)
    }

    /// 招待リンク（プランに1本・生きていればそれが返る）
    func invite(planId: String) async throws -> TripInviteLink {
        if TripPlanFixture.isOn { return TripInviteLink(token: "fixture-invite-token-0000000000000", expiresAt: nil) }
        return try await api.authorized(.post, "/trip-share/\(encoded(planId))/invite", body: Empty(), as: TripInviteLink.self)
    }

    /// 抜ける（自分）。作った人が仲間を外すときも同じ口
    func removeMember(planId: String, userId: String) async throws {
        if TripPlanFixture.isOn { return }
        try await api.authorizedVoid(.delete, "/trip-share/\(encoded(planId))/members/\(encoded(userId))")
    }

    func chat(planId: String) async throws -> TripChatPage {
        if TripPlanFixture.isOn { return await TripShareFixtureStore.shared.chat(planId: planId) }
        return try await api.authorized(.get, "/trip-share/\(encoded(planId))/chat", as: TripChatPage.self)
    }

    func send(planId: String, text: String) async throws -> TripChatMessage {
        if TripPlanFixture.isOn { return await TripShareFixtureStore.shared.send(planId: planId, text: text) }
        return try await api.authorized(.post, "/trip-share/\(encoded(planId))/chat", body: SendBody(text: text),
                                        as: TripChatSent.self).message
    }

    /// 会話の1通を通報する（2026-11-14・札 #597・審査ガイドライン 1.2）。サーバーの `POST /trip-share/{planId}/report`。
    /// DM の通報（`DMService.report`）は会話 ID（2人の uid）で引く口なので使えない。理由は DM・写真と同じ許可リスト。
    /// サーバーは通報時点の直近 20 通と通報した通を写して運営に残す（相手には知らせない）
    func report(planId: String, messageId: String, reason: ModerationService.ReportReason, note: String?) async throws {
        struct Body: Encodable {
            let messageId: String
            let reason: String
            let note: String?
        }
        if TripPlanFixture.isOn { return }
        try await api.authorizedVoid(.post, "/trip-share/\(encoded(planId))/report",
                                     body: Body(messageId: try encoded(messageId), reason: reason.rawValue,
                                                note: ModerationService.reportNote(note)))
    }

    /// 受信箱に並べるプランの会話
    func inbox() async throws -> [TripInboxItem] {
        if TripPlanFixture.isOn { return await TripShareFixtureStore.shared.inbox() }
        return try await api.authorized(.get, "/trip-share/inbox", as: TripInboxPage.self).trips
    }
}

/// 招待リンクの URL（Web の `/t?t=<トークン>`。アプリが無い人も Web で見て参加できる）
struct TripInviteLink: Decodable, Equatable {
    let token: String
    let expiresAt: String?

    var url: URL? {
        var c = URLComponents(string: "https://journey-photo.com/t")
        c?.queryItems = [URLQueryItem(name: "t", value: token)]
        return c?.url
    }
}

struct TripMember: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let username: String?
    let deleted: Bool?
    let owner: Bool?
}

struct TripShareDetail: Decodable, Equatable {
    let plan: TripPlan
    let members: [TripMember]
    let isOwner: Bool
    let membersMax: Int?
    let invite: TripInviteLink?
}

/// 会話の1通。`event` は「日程に足しました」（足した場所・何日目か）
struct TripChatMessage: Decodable, Equatable, Identifiable {
    struct Event: Decodable, Equatable {
        let type: String
        let item: TripItem
        let day: Int
    }
    let id: String
    let from: String
    let mine: Bool
    let t: String
    let text: String?
    let event: Event?
}

struct TripChatPage: Decodable, Equatable {
    let messages: [TripChatMessage]
    let members: [TripMember]

    private enum CodingKeys: String, CodingKey { case messages, members }

    init(messages: [TripChatMessage], members: [TripMember]) {
        self.messages = messages
        self.members = members
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 読めない通は落とす（1通のせいで会話ごと開けなくしない）
        messages = try c.decode([Lenient<TripChatMessage>].self, forKey: .messages).compactMap(\.value)
        members = (try? c.decode([Lenient<TripMember>].self, forKey: .members))?.compactMap(\.value) ?? []
    }
}

private struct TripChatSent: Decodable { let message: TripChatMessage }

/// 受信箱の1行（プランの会話）
struct TripInboxItem: Decodable, Equatable, Identifiable {
    struct Member: Decodable, Equatable { let id: String; let name: String }
    struct Last: Decodable, Equatable {
        let from: String
        let fromName: String
        let mine: Bool
        let t: String
        let excerpt: String
        let event: Bool?
    }
    let planId: String
    let title: String
    let members: [Member]
    let unread: Int
    let last: Last?
    let updatedAt: String?

    var id: String { planId }
}

private struct TripInboxPage: Decodable {
    let trips: [TripInboxItem]

    private enum CodingKeys: String, CodingKey { case trips }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trips = try c.decode([Lenient<TripInboxItem>].self, forKey: .trips).compactMap(\.value)
    }
}

/// UI テストの見本（Debug のときだけ・サーバーへは送らない）。金沢のプランを「あお」と共有している形
actor TripShareFixtureStore {
    static let shared = TripShareFixtureStore()

    static let me = "fixture-me"
    static let friend = "fixture-friend"
    private var shared: Set<String> = []
    private var messages: [String: [TripChatMessage]] = [:]
    private var serial = 0

    private func members(_ planId: String) -> [TripMember] {
        [TripMember(id: Self.me, name: L("わたし", "Me"), username: nil, deleted: nil, owner: true),
         TripMember(id: Self.friend, name: "あお", username: nil, deleted: nil, owner: nil)]
    }

    private func plan(_ planId: String) async -> TripPlan? {
        try? await TripPlanFixtureStore.shared.list().first { $0.planId == planId }
    }

    func share(planId: String, with userId: String?) async -> TripShareDetail {
        shared.insert(planId)
        let p = await plan(planId) ?? TripPlan(planId: planId, title: "")
        return TripShareDetail(plan: p, members: members(planId), isOwner: true, membersMax: 20, invite: nil)
    }

    func detail(planId: String) async throws -> TripShareDetail {
        guard let p = await plan(planId) else { throw APIError.server(status: 404, message: "") }
        return TripShareDetail(plan: p, members: members(planId), isOwner: true, membersMax: 20, invite: nil)
    }

    func chat(planId: String) -> TripChatPage {
        if messages[planId] == nil {
            messages[planId] = [
                TripChatMessage(id: "m1", from: Self.friend, mine: false, t: "2026-11-10T09:00:00Z",
                                text: "朝のひがし茶屋街、人が少なくて良いらしい", event: nil),
                TripChatMessage(id: "m2", from: Self.friend, mine: false, t: "2026-11-10T09:01:00Z", text: nil,
                                event: .init(type: "added", item: .spot(spotId: "sp_64ff5284da9e", note: nil), day: 0)),
                TripChatMessage(id: "m3", from: Self.me, mine: true, t: "2026-11-10T09:05:00Z",
                                text: "いいね、朝いちで行こう", event: nil),
            ]
        }
        return TripChatPage(messages: messages[planId] ?? [], members: members(planId))
    }

    func send(planId: String, text: String) -> TripChatMessage {
        serial += 1
        let m = TripChatMessage(id: "sent-\(serial)", from: Self.me, mine: true, t: "2026-11-10T09:10:00Z", text: text, event: nil)
        messages[planId, default: []].append(m)
        return m
    }

    func inbox() -> [TripInboxItem] {
        [TripInboxItem(planId: "fixture-kanazawa", title: "金沢・福井の旅",
                       members: [.init(id: Self.me, name: L("わたし", "Me")), .init(id: Self.friend, name: "あお")],
                       unread: 1,
                       last: .init(from: Self.friend, fromName: "あお", mine: false, t: "2026-11-10T09:00:00Z",
                                   excerpt: "朝のひがし茶屋街、人が少なくて良いらしい", event: nil),
                       updatedAt: "2026-11-10T09:00:00Z")]
    }
}
