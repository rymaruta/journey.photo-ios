import Foundation

/// グループの DM（みんなで話す DM・2026-11-20・札 #582。owner 承認 2026-11-12 と 2026-11-20）の口。
/// サーバーは `api-user/src/groups.ts`（journey.photo-web 枝 `claude/group-dm-server-main` 7cc29632c・別スタック
/// `serverless.groups.yml`）。**本番にはまだ口が無い**——一覧（`GET /groups`）が読めたときだけ、アプリはグループの入口を出す
/// （`DMInboxStore.groupsAvailable`。読めなければ今の1対1のまま）。
///
///     GET    /groups                          一覧 → `GroupInbox`（入っているグループ・外されたグループ・招待）
///     POST   /groups                          作る `{memberIds: 2〜29人, name?}` → 201 `GroupChange`
///     GET    /groups/{groupId}                詳しい → `GroupDetail`（メンバー・招待中・外された。それ以外は 404）
///     PUT    /groups/{groupId}                名前（誰でも）と自分の知らせ `{name?: string|null, muted?}` → `GroupDetail`
///     GET    /groups/{groupId}/messages       読む（読んだ位置もサーバーが進める）→ `GroupMessagesPage`
///     POST   /groups/{groupId}/messages       送る `{text?, photoId?, id?}` → `{message}`（`id` で送り直しを二重にしない）
///     POST   /groups/{groupId}/members        人を足す `{userIds}` → `GroupChange`（`added`・`invitedNow`・`notAdded`）
///     DELETE /groups/{groupId}/members/{uid}  自分なら抜ける（招待中なら断る・外されたなら受信箱から消す）。他人は作った人だけ
///     POST   /groups/{groupId}/join           招待に参加する
///     POST   /groups/{groupId}/decline        招待を断る
///     POST   /groups/{groupId}/report         通報 `{reason, messageId?, note?}`
///
/// 断り（`{error, code}`）は DM と同じ `DMService.Refused` に包む。`code` は `notFound`・`full`・`joinedFull`・
/// `dailyLimit`・`photoNotFound`・`notOwner`・`badRequest`・`empty`・`messageNotFound`（言葉は `GroupText.refusal`）
struct GroupService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private func encoded(_ id: String) throws -> String { try PathID.segment(id) }

    private func refusing<T>(_ call: () async throws -> T) async throws -> T {
        try await DMService.refusing(call)
    }

    func inbox() async throws -> GroupInbox {
        // 控えには載らない（サーバーが `Cache-Control: private, no-store`）
        try await refusing { try await api.authorized(.get, "/groups", as: GroupInbox.self) }
    }

    /// 作る。`memberIds` は自分を除いた 2〜29 人（1人なら1対1の会話を使う・`GroupPick`）
    func create(memberIds: [String], name: String? = nil) async throws -> GroupChange {
        struct Body: Encodable { let memberIds: [String]; let name: String? }
        let sent = try await refusing {
            try await api.authorized(.post, "/groups", body: Body(memberIds: memberIds, name: name), as: GroupChange.self)
        }
        PushPrimerStore.reachedOut()
        return sent
    }

    func detail(_ groupId: String) async throws -> GroupDetail {
        try await refusing { try await api.authorized(.get, "/groups/\(encoded(groupId))", as: GroupDetail.self) }
    }

    /// 名前を変える（`nil` で名前を外す・名前の無いグループはサーバーの `displayName`）
    func rename(_ groupId: String, to name: String?) async throws -> GroupDetail {
        try await refusing {
            try await api.authorized(.put, "/groups/\(encoded(groupId))", body: GroupNameBody(name: name), as: GroupDetail.self)
        }
    }

    /// このグループの知らせを止める・戻す（自分の分だけ）
    func setMuted(_ groupId: String, _ muted: Bool) async throws -> GroupDetail {
        struct Body: Encodable { let muted: Bool }
        return try await refusing {
            try await api.authorized(.put, "/groups/\(encoded(groupId))", body: Body(muted: muted), as: GroupDetail.self)
        }
    }

    func messages(_ groupId: String) async throws -> GroupMessagesPage {
        try await refusing {
            try await api.authorized(.get, "/groups/\(encoded(groupId))/messages", as: GroupMessagesPage.self)
        }
    }

    /// 送る。`clientId` は再送で二重に入れない鍵（DM と同じ・`DMRules.newClientId`）。`photoId` は写真の札（DM と同じ門）
    func send(_ groupId: String, text: String, clientId: String, photoId: String? = nil) async throws -> GroupMessage {
        struct Body: Encodable { let text: String?; let id: String; let photoId: String? }
        struct Sent: Decodable { let message: GroupMessage }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sent = try await refusing {
            try await api.authorized(.post, "/groups/\(encoded(groupId))/messages",
                                     body: Body(text: trimmed.isEmpty ? nil : trimmed, id: clientId, photoId: photoId),
                                     as: Sent.self).message
        }
        PushPrimerStore.reachedOut()
        return sent
    }

    func addMembers(_ groupId: String, userIds: [String]) async throws -> GroupChange {
        struct Body: Encodable { let userIds: [String] }
        return try await refusing {
            try await api.authorized(.post, "/groups/\(encoded(groupId))/members", body: Body(userIds: userIds),
                                     as: GroupChange.self)
        }
    }

    /// 自分なら抜ける（招待中なら断る・外されたグループなら受信箱から消す）。他人を外せるのは作った人だけ（403 `notOwner`）
    func removeMember(_ groupId: String, userId: String) async throws {
        try await refusing {
            _ = try await api.authorizedVoid(.delete, "/groups/\(encoded(groupId))/members/\(encoded(userId))")
        }
    }

    func join(_ groupId: String) async throws {
        try await refusing { _ = try await api.authorizedVoid(.post, "/groups/\(encoded(groupId))/join", body: GroupEmptyBody()) }
    }

    func decline(_ groupId: String) async throws {
        try await refusing { _ = try await api.authorizedVoid(.post, "/groups/\(encoded(groupId))/decline", body: GroupEmptyBody()) }
    }

    /// 通報（理由は DM・写真と同じ許可リスト）。`messageId` は1通を名指しするとき。サーバーは直近20通を写す
    func report(_ groupId: String, reason: ModerationService.ReportReason, messageId: String? = nil,
                note: String?) async throws {
        struct Body: Encodable { let reason: String; let messageId: String?; let note: String? }
        try await refusing {
            _ = try await api.authorizedVoid(.post, "/groups/\(encoded(groupId))/report",
                                             body: Body(reason: reason.rawValue, messageId: try messageId.map(encoded),
                                                        note: ModerationService.reportNote(note)))
        }
    }
}

/// 書く口の本文が空のとき（サーバーは本文を JSON として読む・空の文字は 400）
private struct GroupEmptyBody: Encodable {}

/// 名前の本文。**`nil` は欄を `null` で送る**（欄が無いと「名前を変えない」になる・サーバーの `"name" in body`）
struct GroupNameBody: Encodable {
    let name: String?
    private enum CodingKeys: String, CodingKey { case name }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let name { try c.encode(name, forKey: .name) } else { try c.encodeNil(forKey: .name) }
    }
}

// MARK: - 応答の形

/// 顔と名前（重ねた顔・招待した人）
struct GroupFace: Decodable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

/// 一覧に出す最後の1通（`groups.ts` の `last`）
struct GroupLast: Decodable, Equatable {
    let from: String
    let t: String
    let excerpt: String
    /// 会話の真ん中の1行（作った・足した…）なら種類
    let event: String?
    let fromName: String
    let mine: Bool

    init(from: String, t: String, excerpt: String, event: String? = nil, fromName: String, mine: Bool) {
        self.from = from
        self.t = t
        self.excerpt = excerpt
        self.event = event
        self.fromName = fromName
        self.mine = mine
    }

    private enum CodingKeys: String, CodingKey { case from, t, excerpt, event, fromName, mine }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        excerpt = (try? c.decodeIfPresent(String.self, forKey: .excerpt)) ?? ""
        event = try? c.decodeIfPresent(String.self, forKey: .event)
        fromName = (try? c.decodeIfPresent(String.self, forKey: .fromName)) ?? ""
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
    }
}

/// グループの見出しの中身（`groupView`）
struct GroupInfo: Decodable, Hashable {
    let groupId: String
    /// 付けた名前（無ければ nil・画面は `displayName`）
    let name: String?
    /// 見る人から見た名前（名前が無ければ「けん、みお」「けん、みお、ほか3人」）
    let displayName: String
    /// 見る人を除いた2人まで
    let faces: [GroupFace]
    let memberCount: Int
    let createdAt: String?
    let planId: String?

    init(groupId: String, name: String?, displayName: String, faces: [GroupFace], memberCount: Int,
         createdAt: String? = nil, planId: String? = nil) {
        self.groupId = groupId
        self.name = name
        self.displayName = displayName
        self.faces = faces
        self.memberCount = memberCount
        self.createdAt = createdAt
        self.planId = planId
    }

    private enum CodingKeys: String, CodingKey { case groupId, name, displayName, faces, memberCount, createdAt, planId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try c.decode(String.self, forKey: .groupId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)).flatMap { $0.isEmpty ? nil : $0 }
        displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? ""
        faces = (try? c.decodeIfPresent([Lenient<GroupFace>].self, forKey: .faces))?.compactMap(\.value) ?? []
        memberCount = max(0, (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        planId = try? c.decodeIfPresent(String.self, forKey: .planId)
    }
}

/// 一覧の1行のグループ（`GET /groups` の `groups[]`）
struct GroupThread: Decodable, Identifiable, Equatable {
    enum State: String, Decodable { case member, removed }

    let info: GroupInfo
    let state: State
    let unread: Int
    let last: GroupLast?
    /// 並べる時刻（最後の1通か、作った時刻）
    let updatedAt: String

    var id: String { info.groupId }
    var isRemoved: Bool { state == .removed }
    var showsUnread: Bool { unread > 0 && !isRemoved }

    init(info: GroupInfo, state: State = .member, unread: Int = 0, last: GroupLast? = nil, updatedAt: String) {
        self.info = info
        self.state = state
        self.unread = unread
        self.last = last
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case state, unread, last, updatedAt }

    init(from decoder: Decoder) throws {
        info = try GroupInfo(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 知らない状態は「メンバー」に倒さない（送れる顔をして送れない会話を出さない）。外された扱い
        let raw = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "member"
        state = State(rawValue: raw) ?? .removed
        unread = max(0, (try? c.decodeIfPresent(Int.self, forKey: .unread)) ?? 0)
        last = try? c.decodeIfPresent(GroupLast.self, forKey: .last)
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? info.createdAt ?? ""
    }

    /// 読んだ姿（開いた直後に点を消す）
    func markingRead() -> GroupThread {
        GroupThread(info: info, state: state, unread: 0, last: last, updatedAt: updatedAt)
    }
}

/// 招待（`GET /groups` の `invites[]`）。**見えるのは名前・入れた人・人数だけ**（参加するまで話は見えない）
struct GroupInvite: Decodable, Identifiable, Hashable {
    let info: GroupInfo
    let invitedBy: GroupFace
    let invitedAt: String

    var id: String { info.groupId }

    init(info: GroupInfo, invitedBy: GroupFace, invitedAt: String) {
        self.info = info
        self.invitedBy = invitedBy
        self.invitedAt = invitedAt
    }

    private enum CodingKeys: String, CodingKey { case invitedBy, invitedAt }

    init(from decoder: Decoder) throws {
        info = try GroupInfo(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        invitedBy = try c.decode(GroupFace.self, forKey: .invitedBy)
        invitedAt = (try? c.decodeIfPresent(String.self, forKey: .invitedAt)) ?? ""
    }
}

/// `GET /groups`
struct GroupInbox: Decodable, Equatable {
    let groups: [GroupThread]
    let invites: [GroupInvite]

    static let empty = GroupInbox(groups: [], invites: [])

    init(groups: [GroupThread], invites: [GroupInvite]) {
        self.groups = groups
        self.invites = invites
    }

    private enum CodingKeys: String, CodingKey { case groups, invites }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 読めない1行のせいで一覧ごと落とさない
        groups = (try c.decodeIfPresent([Lenient<GroupThread>].self, forKey: .groups) ?? []).compactMap(\.value)
        invites = (try c.decodeIfPresent([Lenient<GroupInvite>].self, forKey: .invites) ?? []).compactMap(\.value)
    }

    /// 未読のあるグループの数（外されたグループ・ブロックした人が最後に話したグループは数えない）
    func unreadGroups() -> Int { groups.filter(\.showsUnread).count }

    func markingRead(_ groupId: String) -> GroupInbox {
        GroupInbox(groups: groups.map { $0.id == groupId ? $0.markingRead() : $0 }, invites: invites)
    }

    func removing(_ groupId: String) -> GroupInbox {
        GroupInbox(groups: groups.filter { $0.id != groupId }, invites: invites.filter { $0.id != groupId })
    }
}

/// メンバーの1人（`GET /groups/{id}` の `members[]`）
struct GroupMember: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let username: String?
    let owner: Bool
    /// 自分がブロックした人（自分の画面にだけ「ブロック中」）
    let blocked: Bool

    init(id: String, name: String, username: String? = nil, owner: Bool = false, blocked: Bool = false) {
        self.id = id
        self.name = name
        self.username = username
        self.owner = owner
        self.blocked = blocked
    }

    private enum CodingKeys: String, CodingKey { case id, name, username, owner, blocked }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        username = try? c.decodeIfPresent(String.self, forKey: .username)
        owner = (try? c.decodeIfPresent(Bool.self, forKey: .owner)) == true
        blocked = (try? c.decodeIfPresent(Bool.self, forKey: .blocked)) == true
    }
}

/// 招待中の人（`invited[]`）
struct GroupInvitee: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let invitedBy: String
}

/// メンバーから見た詳しい中身
struct GroupMembership: Equatable {
    let group: GroupInfo
    let isOwner: Bool
    let muted: Bool
    let membersMax: Int
    let members: [GroupMember]
    let invited: [GroupInvitee]

    /// 招待中の人も数えた、使っている席
    var seatsUsed: Int { members.count + invited.count }
    var seatsLeft: Int { max(0, membersMax - seatsUsed) }
    /// 人を足す画面で選べない人（もう居る・招待中）
    var present: Set<String> { Set(members.map(\.id) + invited.map(\.id)) }
}

/// `GET /groups/{id}`
enum GroupDetail: Decodable, Equatable {
    case member(GroupMembership)
    /// 招待中（名前・入れた人・人数だけ）
    case invited(group: GroupInfo, invitedBy: GroupFace)
    /// 外された（外されるまでの話は読めるが送れない）
    case removed(group: GroupInfo)

    var group: GroupInfo {
        switch self {
        case .member(let m): return m.group
        case .invited(let g, _): return g
        case .removed(let g): return g
        }
    }

    var membership: GroupMembership? {
        if case .member(let m) = self { return m }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case state, group, isOwner, muted, membersMax, members, invited, invitedBy }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let group = try c.decode(GroupInfo.self, forKey: .group)
        switch try c.decodeIfPresent(String.self, forKey: .state) ?? "member" {
        case "invited":
            self = .invited(group: group, invitedBy: try c.decode(GroupFace.self, forKey: .invitedBy))
        case "removed":
            self = .removed(group: group)
        default:
            self = .member(GroupMembership(
                group: group,
                isOwner: (try? c.decodeIfPresent(Bool.self, forKey: .isOwner)) == true,
                muted: (try? c.decodeIfPresent(Bool.self, forKey: .muted)) == true,
                membersMax: (try? c.decodeIfPresent(Int.self, forKey: .membersMax)) ?? GroupRules.membersMax,
                members: (try c.decodeIfPresent([Lenient<GroupMember>].self, forKey: .members) ?? []).compactMap(\.value),
                invited: (try c.decodeIfPresent([Lenient<GroupInvitee>].self, forKey: .invited) ?? []).compactMap(\.value)))
        }
    }
}

/// 作る・人を足すの応答（詳しいと同じ形に、入った人・招待した人・入れなかった人の数を足したもの）
struct GroupChange: Decodable, Equatable {
    let detail: GroupDetail
    /// そのまま入った人（人を足すときだけ）
    let added: [String]
    /// 招待になった人（相手が足した人をフォローしていない・人を足すときだけ）
    let invitedNow: [String]
    /// 入れられなかった人の数（理由は言わない・ブロックの関係かは分からない）
    let notAdded: Int

    init(detail: GroupDetail, added: [String] = [], invitedNow: [String] = [], notAdded: Int = 0) {
        self.detail = detail
        self.added = added
        self.invitedNow = invitedNow
        self.notAdded = notAdded
    }

    private enum CodingKeys: String, CodingKey { case added, invitedNow, notAdded }

    init(from decoder: Decoder) throws {
        detail = try GroupDetail(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = (try? c.decodeIfPresent([String].self, forKey: .added)) ?? []
        invitedNow = (try? c.decodeIfPresent([String].self, forKey: .invitedNow)) ?? []
        notAdded = max(0, (try? c.decodeIfPresent(Int.self, forKey: .notAdded)) ?? 0)
    }
}

/// 会話の真ん中の1行の中身（`groupChat.ts` の `GroupEvent`）
struct GroupEvent: Decodable, Equatable, Hashable {
    let type: String
    let targets: [String]
    let name: String?

    init(type: String, targets: [String] = [], name: String? = nil) {
        self.type = type
        self.targets = targets
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case type, targets, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        targets = (try? c.decodeIfPresent([String].self, forKey: .targets)) ?? []
        name = try? c.decodeIfPresent(String.self, forKey: .name)
    }
}

/// 会話の1通（`GET /groups/{id}/messages` の `messages[]`）
struct GroupMessage: Decodable, Identifiable, Equatable {
    let id: String
    /// 通し番号（1から）
    let n: Int
    let from: String
    let mine: Bool
    let t: String
    let text: String?
    /// 読む人から見た写真の札（DM と同じ形・`DMPhotoQuote`）
    let photo: DMPhotoQuote?
    let event: GroupEvent?

    init(id: String, n: Int, from: String, mine: Bool, t: String, text: String? = nil, photo: DMPhotoQuote? = nil,
         event: GroupEvent? = nil) {
        self.id = id
        self.n = n
        self.from = from
        self.mine = mine
        self.t = t
        self.text = text
        self.photo = photo
        self.event = event
    }

    private enum CodingKeys: String, CodingKey { case id, n, from, mine, t, text, photo, event }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        n = (try? c.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        from = (try? c.decodeIfPresent(String.self, forKey: .from)) ?? ""
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) == true
        t = (try? c.decodeIfPresent(String.self, forKey: .t)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)).flatMap { $0.isEmpty ? nil : $0 }
        photo = try? c.decodeIfPresent(DMPhotoQuote.self, forKey: .photo)
        event = try? c.decodeIfPresent(GroupEvent.self, forKey: .event)
    }

    /// DM の会話の部品（吹き出し・写真の札・送る1通の控え `DMThreadLog`）で描くための形。写しを作らないため
    var asDM: DMMessage {
        DMMessage(id: id, from: from, mine: mine, text: text ?? "", t: t,
                  photoId: photo?.id, photoOnly: photo != nil && text == nil, photo: photo, groupEvent: event)
    }
}

/// `GET /groups/{id}/messages`
struct GroupMessagesPage: Decodable, Equatable {
    enum State: String { case member, removed }

    let state: State
    let canSend: Bool
    let seq: Int
    let messages: [GroupMessage]
    /// 名前を引く相手（メンバーと、見えている通を書いた人）
    let members: [GroupFace]

    init(state: State = .member, canSend: Bool = true, seq: Int = 0, messages: [GroupMessage], members: [GroupFace]) {
        self.state = state
        self.canSend = canSend
        self.seq = seq
        self.messages = messages
        self.members = members
    }

    private enum CodingKeys: String, CodingKey { case state, canSend, seq, messages, members }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = State(rawValue: (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "member") ?? .removed
        canSend = (try? c.decodeIfPresent(Bool.self, forKey: .canSend)) == true && state == .member
        seq = (try? c.decodeIfPresent(Int.self, forKey: .seq)) ?? 0
        messages = (try c.decodeIfPresent([Lenient<GroupMessage>].self, forKey: .messages) ?? []).compactMap(\.value)
        members = (try? c.decodeIfPresent([Lenient<GroupFace>].self, forKey: .members))?.compactMap(\.value) ?? []
    }
}
