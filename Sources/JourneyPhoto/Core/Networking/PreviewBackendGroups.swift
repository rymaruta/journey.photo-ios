import Foundation

#if DEBUG
/// グループの DM の見本の答え（`-JPPreviewGroups`・UI テストだけ・Debug のみ・2026-11-20 札 #582）。
/// 形はサーバーの `api-user/src/groups.ts`（journey.photo-web 7cc29632c）に合わせる。**サーバーには何も書かない**。
///
/// はじめから在るもの:
/// - 入っているグループ1つ（名前なし・夕焼けの人と港の写真家と自分・夕焼けの人が作った・未読1）
/// - 招待1つ（「週末の写真散歩」・山の朝が入れた・3人）
/// 作る・送る・人を足す・抜ける・参加する・断る・名前・知らせ・通報は、この端末の中で覚える（アプリを閉じれば消える）
extension PreviewBackend {

    static let groupSeedId = "6f1c2a10-0000-4000-8000-000000000001"
    static let groupInviteId = "6f1c2a10-0000-4000-8000-000000000002"

    final class GroupStore: @unchecked Sendable {
        struct Group {
            let id: String
            var name: String?
            var ownerId: String
            var members: [String]
            var messages: [[String: Any]]
            var muted = false
            let createdAt: String
            var read = 0
        }

        private let lock = NSLock()
        private(set) var groups: [String: Group] = [:]
        private(set) var order: [String] = []
        private(set) var invites: [String: (group: Group, by: String, at: String)] = [:]
        private var serial = 0
        private var seeded = false

        func with<T>(_ body: (GroupStore) -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body(self)
        }

        fileprivate func seedIfNeeded(me: String, now: Date) {
            guard !seeded else { return }
            seeded = true
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            func ago(_ minutes: Double) -> String { iso.string(from: now.addingTimeInterval(-minutes * 60)) }
            let a = PreviewBackend.dmPeers[0].id, b = PreviewBackend.dmPeers[1].id
            var g = Group(id: PreviewBackend.groupSeedId, name: nil, ownerId: a, members: [a, me, b], messages: [],
                          createdAt: ago(60 * 3))
            g.messages = [
                ["id": "pg-1", "n": 1, "from": a, "t": ago(60 * 3), "event": ["type": "created"]],
                ["id": "pg-2", "n": 2, "from": a, "t": ago(60 * 2), "text": "来月の金沢、3人で行かない？"],
                ["id": "pg-3", "n": 3, "from": me, "t": ago(60 * 1.9), "text": "行ける！"],
                ["id": "pg-4", "n": 4, "from": b, "t": ago(9), "text": "紅葉の時期がいいな"],
                ["id": "pg-5", "n": 5, "from": b, "t": ago(8.5), "text": "兼六園は外せない"],
            ]
            g.read = 4
            groups[g.id] = g
            order = [g.id]
            let c = PreviewBackend.dmPeers[2].id, d = PreviewBackend.dmPeers[3].id
            let invite = Group(id: PreviewBackend.groupInviteId, name: "週末の写真散歩", ownerId: c, members: [c, d],
                               messages: [["id": "pi-1", "n": 1, "from": c, "t": ago(120), "event": ["type": "created"]],
                                          ["id": "pi-2", "n": 2, "from": c, "t": ago(100), "text": "土曜の朝に集まろう"]],
                               createdAt: ago(120))
            invites[invite.id] = (invite, c, ago(90))
        }

        fileprivate func nextId() -> String {
            serial += 1
            return String(format: "6f1c2a10-0000-4000-8000-%012d", 100 + serial)
        }

        fileprivate func nextMessageId() -> String {
            serial += 1
            return "pg-new-\(serial)"
        }

        fileprivate func put(_ g: Group) {
            if groups[g.id] == nil { order.insert(g.id, at: 0) }
            groups[g.id] = g
        }

        fileprivate func drop(_ id: String) {
            groups[id] = nil
            order.removeAll { $0 == id }
        }

        fileprivate func dropInvite(_ id: String) { invites[id] = nil }
    }

    static let groupStore = GroupStore()

    /// `/groups` の答え。知らない口は nil（ふだんの 503 へ）。`names` は名前の表（見本の相手とフォロー中の人）
    static func groupReply(method: String, parts: [String], json: [String: Any], me: String, now: Date,
                           names: [String: String], store: GroupStore = PreviewBackend.groupStore) -> Reply? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = iso.string(from: now)
        func name(_ id: String) -> String {
            if let p = dmPeers.first(where: { $0.id == id }), !p.name.isEmpty { return p.name }
            if id == me { return "わたし" }
            return names[id] ?? "旅の人"
        }
        func displayName(_ g: GroupStore.Group) -> String {
            if let n = g.name, !n.isEmpty { return n }
            let others = g.members.filter { $0 != me }
            let shown = others.prefix(2).map(name)
            let rest = others.count - shown.count
            return shown.joined(separator: "、") + (rest > 0 ? "、ほか\(rest)人" : "")
        }
        func faces(_ g: GroupStore.Group) -> [[String: Any]] {
            g.members.filter { $0 != me }.prefix(2).map { ["id": $0, "name": name($0)] }
        }
        func view(_ g: GroupStore.Group) -> [String: Any] {
            var v: [String: Any] = ["groupId": g.id, "displayName": displayName(g), "faces": faces(g),
                                    "memberCount": g.members.count, "createdAt": g.createdAt]
            v["name"] = g.name ?? NSNull()
            return v
        }
        func detail(_ g: GroupStore.Group) -> [String: Any] {
            ["state": "member", "group": view(g), "isOwner": g.ownerId == me, "muted": g.muted, "membersMax": GroupRules.membersMax,
             "members": g.members.map { id -> [String: Any] in
                 var m: [String: Any] = ["id": id, "name": name(id)]
                 if id == g.ownerId { m["owner"] = true }
                 return m
             },
             "invited": [Any]()]
        }
        func shaped(_ m: [String: Any]) -> [String: Any] {
            var out = m
            out["mine"] = (m["from"] as? String) == me
            return out
        }
        func appendEvent(_ g: inout GroupStore.Group, _ event: [String: Any]) {
            g.messages.append(["id": store.nextMessageId(), "n": g.messages.count + 1, "from": me, "t": stamp, "event": event])
        }
        let notFound = Reply.json(["error": "グループが見つかりません", "code": "notFound"], status: 404)

        return store.with { store -> Reply? in
            store.seedIfNeeded(me: me, now: now)
            switch (method, parts.count) {
            case ("GET", 1):
                let groups: [[String: Any]] = store.order.compactMap { store.groups[$0] }.map { g in
                    var row = view(g)
                    row["state"] = "member"
                    let last = g.messages.last
                    row["unread"] = max(0, g.messages.count - g.read)
                    if let last, let from = last["from"] as? String, let t = last["t"] as? String {
                        var l: [String: Any] = ["from": from, "t": t, "fromName": name(from), "mine": from == me,
                                                "excerpt": (last["text"] as? String) ?? ""]
                        if let ev = last["event"] as? [String: Any] { l["event"] = ev["type"] ?? "" }
                        row["last"] = l
                        row["updatedAt"] = t
                    } else {
                        row["updatedAt"] = g.createdAt
                    }
                    return row
                }
                let invites: [[String: Any]] = store.invites.values.map { inv in
                    var row = view(inv.group)
                    row["invitedBy"] = ["id": inv.by, "name": name(inv.by)]
                    row["invitedAt"] = inv.at
                    return row
                }
                return .json(["groups": groups, "invites": invites])
            case ("POST", 1):
                let ids = (json["memberIds"] as? [String] ?? []).filter { $0 != me }
                if ids.count < 2 { return .json(["error": "2人以上を選んでください", "code": "badRequest"], status: 400) }
                if ids.count > GroupRules.membersMax - 1 {
                    return .json(["error": "グループは30人までです", "code": "full"], status: 403)
                }
                var g = GroupStore.Group(id: store.nextId(), name: json["name"] as? String, ownerId: me, members: [me] + ids,
                                         messages: [], createdAt: stamp)
                appendEvent(&g, ["type": "created"])
                g.read = g.messages.count
                store.put(g)
                var body = detail(g)
                body["notAdded"] = 0
                return .json(body, status: 201)
            default:
                break
            }
            guard parts.count >= 2 else { return nil }
            let id = parts[1]
            if var g = store.groups[id] {
                switch (method, parts.count, parts.count > 2 ? parts[2] : "") {
                case ("GET", 2, _):
                    return .json(detail(g))
                case ("PUT", 2, _):
                    if let muted = json["muted"] as? Bool { g.muted = muted }
                    if json.keys.contains("name") {
                        let next = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        if next != g.name {
                            g.name = next
                            var ev: [String: Any] = ["type": "renamed"]
                            if let next { ev["name"] = next }
                            appendEvent(&g, ev)
                            g.read = g.messages.count
                        }
                    }
                    store.put(g)
                    return .json(detail(g))
                case ("GET", 3, "messages"):
                    g.read = g.messages.count
                    store.put(g)
                    let ids = Set(g.members + g.messages.compactMap { $0["from"] as? String })
                    return .json(["state": "member", "canSend": true, "seq": g.messages.count,
                                  "messages": g.messages.map(shaped),
                                  "members": ids.sorted().map { ["id": $0, "name": name($0)] }])
                case ("POST", 3, "messages"):
                    let text = (json["text"] as? String) ?? ""
                    if text.isEmpty { return .json(["error": "メッセージを入力してください", "code": "empty"], status: 400) }
                    let mid = (json["id"] as? String) ?? store.nextMessageId()
                    if let prior = g.messages.first(where: { ($0["id"] as? String) == mid }) {
                        return .json(["message": shaped(prior)])
                    }
                    let m: [String: Any] = ["id": mid, "n": g.messages.count + 1, "from": me, "t": stamp, "text": text]
                    g.messages.append(m)
                    g.read = g.messages.count
                    store.put(g)
                    return .json(["message": shaped(m)])
                case ("POST", 3, "members"):
                    let ids = (json["userIds"] as? [String] ?? []).filter { !g.members.contains($0) && $0 != me }
                    if ids.isEmpty { return .json(["error": "足す人を選んでください", "code": "badRequest"], status: 400) }
                    if g.members.count + ids.count > GroupRules.membersMax {
                        return .json(["error": "グループは30人までです", "code": "full"], status: 403)
                    }
                    g.members += ids
                    appendEvent(&g, ["type": "added", "targets": ids])
                    g.read = g.messages.count
                    store.put(g)
                    var body = detail(g)
                    body["added"] = ids
                    body["invitedNow"] = [String]()
                    body["notAdded"] = 0
                    return .json(body)
                case ("DELETE", 4, "members"):
                    let who = parts[3]
                    if who == me {
                        store.drop(id)
                        return .json(["ok": true])
                    }
                    guard g.ownerId == me else {
                        return .json(["error": "人を外せるのはグループを作った人だけです", "code": "notOwner"], status: 403)
                    }
                    g.members.removeAll { $0 == who }
                    appendEvent(&g, ["type": "removed", "targets": [who]])
                    store.put(g)
                    return .json(["ok": true])
                case ("POST", 3, "report"):
                    return .json(["success": true])
                default:
                    return nil
                }
            }
            if let inv = store.invites[id] {
                switch (method, parts.count, parts.count > 2 ? parts[2] : "") {
                case ("GET", 2, _):
                    return .json(["state": "invited", "group": view(inv.group),
                                  "invitedBy": ["id": inv.by, "name": name(inv.by)]])
                case ("POST", 3, "join"):
                    var g = inv.group
                    g.members.append(me)
                    g.messages.append(["id": store.nextMessageId(), "n": g.messages.count + 1, "from": me, "t": stamp,
                                       "event": ["type": "joined"]])
                    // 入る前の話は見せない（参加した1行から）
                    g.messages = Array(g.messages.suffix(1))
                    g.read = g.messages.count
                    store.dropInvite(id)
                    store.put(g)
                    return .json(["groupId": id, "joined": true])
                case ("POST", 3, "decline"), ("DELETE", 4, "members"):
                    store.dropInvite(id)
                    return .json(["ok": true])
                default:
                    return notFound
                }
            }
            return notFound
        }
    }
}
#endif
