import Foundation

// とおまわり号の要サーバーの部品（2026-10-19・第2段。サーバーは photo-gallery `api-user/src/camper.ts`・本番で
// 2026-10-19T04:00Z に配り始めた）。
//
// - 持っているか: `GET /user/camper` の `parts`（サーバーが正）を、端末で数えた部品に足す。
// - 分母: **サーバーの口が読めて `launched: true` の間だけ** 98 → 131（要サーバー 33 を足す。キャンプ場の焚き火
//   `fire_pit.stone_ring` は `.later` のまま「近日」）。読めない・始まっていない・通信が落ちた間は今までどおり 98
//   （端末の数え方に戻す）。`TrunkAvailability` と同じ「読めたら出す」。
// - 進み具合の棒: 記録で決まる 20 個だけ（旅の数・贈り物・訪ねた・薪・同じ日の旅。数はサーバーの `progress`）。
//   写真で決まる 13 個（スポット・行事・祭り・天気）は「届いた／まだ」だけ（設計案 3.4: 端末で数えると数がずれる）。

/// 要サーバーの部品の決まり（サーバー `camper.ts` の表の写し。`CamperServerTests` が図鑑の `.server` と突き合わせる）
enum CamperServerRule {

    /// 記録の数（サーバーの `progress` の欄）
    enum Metric: Equatable, Sendable {
        case trips, giftsFrom, visits, wood, tripFriends

        func value(_ p: CamperServerState.Progress) -> Int {
            switch self {
            case .trips: return p.trips
            case .giftsFrom: return p.giftsFrom
            case .visits: return p.visits
            case .wood: return p.wood
            case .tripFriends: return p.tripFriends
            }
        }
    }

    struct Need: Equatable, Sendable {
        let metric: Metric
        let count: Int
    }

    /// 記録で決まる 20 個（`CAMPER_TRIP_TIERS`・`CAMPER_GIFT_TIERS`・`CAMPER_LADDER`・`CAMPER_WOOD`・
    /// `CAMPER_SAME_DAY`・`CAMPER_TRIP_FRIENDS`）
    static let needs: [String: Need] = {
        var out: [String: Need] = [:]
        for (n, id) in [(2, "flag.swallowtail"), (3, "mudflap.checker"), (4, "roof_tent.popup_canvas"), (4, "cushion.tasseled"),
                        (5, "grille.honeycomb"), (5, "solar.folding_suitcase"), (6, "spare_cover.hardshell"),
                        (6, "table.wooden_crate_table"), (7, "bookshelf.crate_stack"), (8, "bike_rack.folding_bike"),
                        (12, "wall_wood.herringbone"), (20, "wheel.brass_spoke")] {
            out[id] = Need(metric: .trips, count: n)
        }
        for (n, id) in [(1, "sticker_edge.signed"), (2, "mirror.brass_oval"), (4, "rug.kilim"), (6, "awning.rust_stripe")] {
            out[id] = Need(metric: .giftsFrom, count: n)
        }
        out["ladder.wood_rungs"] = Need(metric: .visits, count: 3)
        out["fire_pit.tripod_kettle"] = Need(metric: .wood, count: 10)
        out["roof_tent.wing"] = Need(metric: .tripFriends, count: 1)
        out["antenna.ham_long"] = Need(metric: .tripFriends, count: 10)
        return out
    }()

    /// 写真で決まる 13 個（スポット 5・行事 3・祭り 2・天気 3）。進み具合は出さない
    static let photoParts: Set<String> = [
        "bumper.wood_beam", "roof_cargo.canoe", "window_shape.porthole", "bike_rack.rear_two", "mug.ceramic_glazed",
        "window_shape.arched", "curtain.beaded", "sticker_edge.holo", "outdoor_light.paper_lantern", "flag.prayer_line",
        "tire_tread.mud_block", "plant.hanging_ivy", "flag.windsock",
    ]

    /// 要サーバーの 33 個
    static var all: Set<String> { photoParts.union(needs.keys) }

    /// (いまの数, 要る数)。写真で決まる部品・知らない id は nil
    static func progress(_ id: String, _ p: CamperServerState.Progress) -> (have: Int, need: Int)? {
        guard let need = needs[id] else { return nil }
        return (min(need.metric.value(p), need.count), need.count)
    }
}

/// 画面が持つ「サーバーの部品」（読めた答え）。読めない・始まっていない間は `open` が false で、何も足さない
struct CamperServerParts: Equatable, Sendable {
    /// 読めた答え（`launched: false` も入る）
    var state: CamperServerState?
    /// 写真の保存などで「届いた」とサーバーが答えた部品（`CamperStore.inbox`）。口がまだ読めていなくても持っている扱い
    /// （2026-10-19 判断: 部品は消えない決まりなので、サーバーが一度届けたと言った部品は外さない）
    var inbox: [String] = []

    static let closed = CamperServerParts()

    /// サーバーの部品を数に入れるか（読めて、配り始めている）
    var open: Bool { state?.launched == true }

    /// サーバーで持っている部品（届いたばかりのものも入れる）
    var ownedIds: Set<String> {
        var ids = Set(inbox)
        if open, let state { ids.formUnion(state.partIds) }
        return ids
    }

    var progress: CamperServerState.Progress {
        guard open, let state else { return CamperServerState.Progress() }
        return state.progress
    }

    /// 新しく届いた部品（先に見せる順: この回の数え直し・写真の保存で届いたもの）
    var freshFirst: [String] {
        var out: [String] = []
        let added: [String] = open ? (state?.added ?? []) : []
        for id in inbox + added where !out.contains(id) { out.append(id) }
        return out
    }

    /// 贈ってくれた人の名前（贈り物で届いた部品だけ。名前の無い人は空の字）
    func giverName(_ id: String) -> String? {
        guard open, let giver = state?.giver(of: id) else { return nil }
        return giver.name ?? ""
    }
}

extension CamperCatalog {

    /// 図鑑の分母に入る部品。サーバーが読める間は要サーバーの 33 個も入る（131）。キャンプ場の焚き火は入れない
    static func collectable(serverOpen: Bool) -> [CamperPart] {
        dex.filter { $0.unlock.isAvailable || (serverOpen && $0.unlock.isServer) }
    }

    /// 図鑑の「持っている / 全部」（サーバーが読める間は分母 131）
    static func dexCount(_ owned: Set<String>, serverOpen: Bool) -> (have: Int, total: Int) {
        let pool = collectable(serverOpen: serverOpen)
        return (pool.filter { owned.contains($0.id) }.count, pool.count)
    }

    /// 分類の札の「持っている / 全部」。**どちらも分母と同じ集まりで数える**（サーバーが読めない間に控えの
    /// 要サーバーの部品だけを持っていると「3 / 2」になっていた・2026-10-19 見直し）
    static func categoryCount(_ c: CamperCategory, owned: Set<String>, serverOpen: Bool) -> (have: Int, total: Int) {
        let pool = parts(c).filter { $0.unlock.isAvailable || (serverOpen && $0.unlock.isServer) }
        return (pool.filter { owned.contains($0.id) }.count, pool.count)
    }

    /// 持っている部品（端末で数えたもの＋サーバーの部品）
    static func owned(_ stats: CamperStats, server: CamperServerParts) -> Set<String> {
        owned(stats).union(server.ownedIds.filter { part($0)?.unlock.isServer == true })
    }
}

extension CamperUnlock {
    /// 要サーバーの部品か
    var isServer: Bool {
        if case .server = self { return true }
        return false
    }
}

extension CamperStore {

    static func inboxKey(_ userId: String) -> String { "camper.inbox.\(userId)" }

    /// 写真の保存（`savePhoto`・下書きの公開）の応答で届いた部品（`camper.added`）。届いた画面で見せたら消す
    var inbox: [String] {
        guard let userId else { return [] }
        return defaults.stringArray(forKey: Self.inboxKey(userId)) ?? []
    }

    /// 届いた部品を控える（図鑑に無い id は落とす・前の控えに足す・最大 64）
    func receive(_ ids: [String]) {
        guard let userId else { return }
        let known = CamperServerState.knownIds(inbox + ids)
        guard !known.isEmpty else { return }
        defaults.set(Array(known.prefix(64)), forKey: Self.inboxKey(userId))
    }

    func clearInbox() {
        guard let userId else { return }
        defaults.removeObject(forKey: Self.inboxKey(userId))
    }

    /// 写真の保存の応答から届いた部品を控える（人が分からなければ何もしない）
    static func receive(_ ids: [String], userId: String?, defaults: UserDefaults = .standard) {
        guard !ids.isEmpty, let userId, !userId.isEmpty else { return }
        CamperStore(userId: userId, defaults: defaults).receive(ids)
    }
}

/// 画面写真の見本（`-JPPreviewCamper YES`・Debug のみ。サーバーには何も送らない）
enum CamperServerSample {

    /// 自分の車: 旅 5 回・贈り物 1 人・訪ねた 2・薪 4。この回に旅の 4 個と贈り物の署名入りが届いた
    static let mine = CamperServerState(
        launched: true,
        parts: [
            .init(id: "sticker_edge.signed", at: "2026-10-19T09:00:00.000Z", from: .init(userId: "sample-friend", name: "mio")),
            .init(id: "grille.honeycomb", at: "2026-10-19T08:00:00.000Z"),
            .init(id: "solar.folding_suitcase", at: "2026-10-19T08:00:00.000Z"),
            .init(id: "roof_tent.popup_canvas", at: "2026-10-19T08:00:00.000Z"),
            .init(id: "cushion.tasseled", at: "2026-10-19T08:00:00.000Z"),
            .init(id: "mudflap.checker", at: "2026-10-19T07:00:00.000Z"),
            .init(id: "flag.swallowtail", at: "2026-10-19T07:00:00.000Z"),
            .init(id: "roof_cargo.canoe", at: "2026-10-19T06:00:00.000Z"),
        ],
        trips: 5,
        progress: .init(trips: 5, giftsFrom: 1, visits: 2, wood: 4, tripFriends: 0),
        recounted: true,
        added: ["sticker_edge.signed", "grille.honeycomb", "solar.folding_suitcase"])

    /// 見本の友達（`-JPPreviewCamperVisit` の行の行き先）
    static let friendId = "sample-friend"
    static let friendName = "mio"

    /// 友達の車（訪ねた回が今日はじめて数えられた）
    static func visit(userId: String) -> CamperVisitState {
        CamperVisitState(userId: userId, launched: true,
                         parts: ["roof_cargo.canoe", "flag.swallowtail", "mudflap.checker", "awning.rust_stripe", "wheel.brass_spoke"],
                         visit: .init(counted: true, added: []))
    }
}
