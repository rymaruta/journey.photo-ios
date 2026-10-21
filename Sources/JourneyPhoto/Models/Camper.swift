import Foundation

// とおまわり号（キャンピングカー）の要サーバーの部品の口の形（photo-gallery `api-user/src/trunk.ts` の
// `readMyCamper`・`visitCamper`・`giftCamper`・`firewoodCamper`・2026-10-18 段2。配り始めは 2026-10-19T04:00Z）。
//
// **どれも包みで読む。** 知らない部品の id・形の違う要素は落とし、欄が無くても投げない（古いサーバー・
// 先に増えた欄で画面を壊さない）。`launched` が読めない応答は「始まっていない」と同じ扱い（端末の数え方に戻す）。

/// `GET /user/camper` → `{ launched, parts: [{ id, at, from? }], trips, progress{…}, recounted, added }`
struct CamperServerState: Decodable, Equatable, Sendable {

    struct Part: Decodable, Equatable, Sendable {
        let id: String
        let at: String
        /// 贈り物で届いた部品の贈った人（名前は読む時に引く。退会した人は欄ごと無い・`docs/tombstone-ttl.md`）
        let from: Giver?

        init(id: String, at: String, from: Giver? = nil) {
            self.id = id
            self.at = at
            self.from = from
        }

        private enum CodingKeys: String, CodingKey { case id, at, from }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
            let giver: Lenient<Giver>? = (try? c.decodeIfPresent(Lenient<Giver>.self, forKey: .from)) ?? nil
            from = giver?.value
        }
    }

    struct Giver: Decodable, Equatable, Sendable {
        let userId: String
        /// 表示名（入れていない人は nil）
        let name: String?
    }

    /// 記録の数（サーバーの `camperProgress`）。部品の進み具合の棒に使う
    struct Progress: Decodable, Equatable, Sendable {
        var trips = 0
        var giftsFrom = 0
        var visits = 0
        var wood = 0
        var tripFriends = 0

        init(trips: Int = 0, giftsFrom: Int = 0, visits: Int = 0, wood: Int = 0, tripFriends: Int = 0) {
            self.trips = trips
            self.giftsFrom = giftsFrom
            self.visits = visits
            self.wood = wood
            self.tripFriends = tripFriends
        }

        private enum CodingKeys: String, CodingKey { case trips, giftsFrom, visits, wood, tripFriends }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let n = { (k: CodingKeys) in max(0, LenientInt.read(c, k) ?? 0) }
            self.init(trips: n(.trips), giftsFrom: n(.giftsFrom), visits: n(.visits), wood: n(.wood), tripFriends: n(.tripFriends))
        }
    }

    /// 配り始めたか（`CAMPER_LAUNCH.at`）。false なら部品は来ず、画面は端末の数え方のまま
    let launched: Bool
    /// 持っている要サーバーの部品（新しい順。図鑑に無い id は落とす）
    let parts: [Part]
    /// 配りを通った旅の投稿の数
    let trips: Int
    let progress: Progress
    /// 今日の数え直しをこの回にしたか
    let recounted: Bool
    /// この回（開いた時の数え直し）で新しく届いた部品の id
    let added: [String]

    init(launched: Bool, parts: [Part], trips: Int = 0, progress: Progress = .init(), recounted: Bool = false, added: [String] = []) {
        self.launched = launched
        self.parts = parts
        self.trips = trips
        self.progress = progress
        self.recounted = recounted
        self.added = added
    }

    private enum CodingKeys: String, CodingKey { case launched, parts, trips, progress, recounted, added }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launched = (try? c.decodeIfPresent(Bool.self, forKey: .launched)) ?? false
        let raw: [Lenient<Part>] = ((try? c.decodeIfPresent([Lenient<Part>].self, forKey: .parts)) ?? nil) ?? []
        var seen = Set<String>()
        parts = raw.compactMap(\.value).filter { CamperCatalog.part($0.id) != nil && seen.insert($0.id).inserted }
        trips = max(0, LenientInt.read(c, .trips) ?? 0)
        progress = ((try? c.decodeIfPresent(Progress.self, forKey: .progress)) ?? nil) ?? Progress(trips: max(0, LenientInt.read(c, .trips) ?? 0))
        recounted = (try? c.decodeIfPresent(Bool.self, forKey: .recounted)) ?? false
        added = camperIds(c, .added)
    }

    /// 図鑑に在る id だけ（重なりは落とす・並びは保つ）
    static func knownIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { CamperCatalog.part($0) != nil && seen.insert($0).inserted }
    }

    var partIds: Set<String> { Set(parts.map(\.id)) }

    /// 部品を贈ってくれた人（贈り物で届いた部品だけ）
    func giver(of id: String) -> Giver? { parts.first { $0.id == id }?.from }
}

/// 部品の id の並びを包みで読む（図鑑に在る id だけ・重なりは落とす）
private func camperIds<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String] {
    let raw: [Lenient<String>]? = (try? c.decodeIfPresent([Lenient<String>].self, forKey: key)) ?? nil
    return CamperServerState.knownIds((raw ?? []).compactMap(\.value))
}

/// `GET /users/{uid}/camper` → `{ userId, launched, parts: [id], visit: { counted, added } }`
struct CamperVisitState: Decodable, Equatable, Sendable {
    struct Visit: Decodable, Equatable, Sendable {
        /// 今日はじめて訪ねた（訪ねた記録に1回足した）
        var counted = false
        /// 訪ねたことで**自分に**新しく届いた部品（はしご・同じ日の旅）
        var added: [String] = []

        init(counted: Bool = false, added: [String] = []) {
            self.counted = counted
            self.added = added
        }

        private enum CodingKeys: String, CodingKey { case counted, added }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            counted = (try? c.decodeIfPresent(Bool.self, forKey: .counted)) ?? false
            added = camperIds(c, .added)
        }
    }

    let userId: String
    let launched: Bool
    /// 相手が持っている要サーバーの部品（相手がトランクを見せない設定なら空）
    let parts: [String]
    let visit: Visit

    init(userId: String, launched: Bool, parts: [String], visit: Visit = .init()) {
        self.userId = userId
        self.launched = launched
        self.parts = parts
        self.visit = visit
    }

    private enum CodingKeys: String, CodingKey { case userId, launched, parts, visit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = ((try? c.decodeIfPresent(String.self, forKey: .userId)) ?? nil) ?? ""
        launched = (try? c.decodeIfPresent(Bool.self, forKey: .launched)) ?? false
        parts = camperIds(c, .parts)
        visit = ((try? c.decodeIfPresent(Visit.self, forKey: .visit)) ?? nil) ?? Visit()
    }
}

/// `POST /users/{uid}/camper/gift` → `{ given, part? }`。`part` は**相手に**届いた部品（届かなかった回は無い）
struct CamperGiftResult: Decodable, Equatable, Sendable {
    let given: Bool
    let part: String?

    init(given: Bool, part: String? = nil) {
        self.given = given
        self.part = part
    }

    private enum CodingKeys: String, CodingKey { case given, part }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        given = (try? c.decodeIfPresent(Bool.self, forKey: .given)) ?? false
        part = ((try? c.decodeIfPresent(String.self, forKey: .part)) ?? nil).flatMap { CamperCatalog.part($0) != nil ? $0 : nil }
    }
}

/// `POST /users/{uid}/camper/firewood` → `{ added, count, part? }`。`part` は**自分に**届いた部品（三脚とやかん）
struct CamperFirewoodResult: Decodable, Equatable, Sendable {
    /// 今日はじめてくべた（同じ友達に1日1回）
    let added: Bool
    /// くべた数（友達×日）
    let count: Int
    let part: String?

    init(added: Bool, count: Int, part: String? = nil) {
        self.added = added
        self.count = count
        self.part = part
    }

    private enum CodingKeys: String, CodingKey { case added, count, part }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = (try? c.decodeIfPresent(Bool.self, forKey: .added)) ?? false
        count = max(0, LenientInt.read(c, .count) ?? 0)
        part = ((try? c.decodeIfPresent(String.self, forKey: .part)) ?? nil).flatMap { CamperCatalog.part($0) != nil ? $0 : nil }
    }
}
