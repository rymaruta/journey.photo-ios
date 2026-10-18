import Foundation

// 旅のトランク（2026-10-17 owner 承認・モック「旅のトランク」）。
//
// サーバーは `api-user/src/trunk.ts`（photo-gallery の `claude/journey-photo-ios-features-herhk1`）。
// 応答の形は `view()`＋`posts`:
//
//     { model, effectiveModel, pocket[], stuck[], limit, isPro,
//       rerolls{left, month}, pendingReroll?{labelId, seeds[], at}, posts, receiveLabels }
//
// **どの項目も包みで読み、欠けても型が違っても投げない**（`UserProfile` の決まり）。
// 古いサーバー（口が無い）では画面が「読み込めませんでした」になるだけで、ほかの画面は壊れない。
// ラベルの**絵は持たない**——アプリが `kind`・`place`・`season`・`timeslot`・`milestone`・`seed`
// から決まった描き方で描く（`TrunkLabelDesign`）。

/// 1枚のラベル。**id と seed と土地の名前が読めない行は落とす**（描けない・貼れない）
struct TrunkLabel: Decodable, Equatable, Identifiable, Hashable {

    /// どの系統で届いたか（サーバーの `LABEL_KINDS`）。知らない値は `.place`（土地のラベルとして描く）
    enum Kind: String, CaseIterable { case milestone, timeslot, season, place }
    enum Season: String, CaseIterable { case spring, summer, autumn, winter }
    /// 夜明け 4–6 時・夕方 16–18 時・夜 20–3 時（サーバーの `timeslotOf`）
    enum Timeslot: String, CaseIterable { case dawn, dusk, night }
    /// 節目（サーバーの `MILESTONES`）
    enum Milestone: String, CaseIterable { case first, posts10, posts50, posts100, firstCountry }

    struct Place: Equatable, Hashable {
        /// 撮影地の文字の最初の区切り・県名・国名（無ければ空）
        let name: String
        /// 撮影地の文字にラテン文字の区切りがあるときだけ（サーバーは訳さない・作らない）
        let latin: String?
        /// 国名（日本語。メダルの表で当たったときと、県が分かったときだけ）
        let country: String?
    }

    let id: String
    let photoId: String
    let kind: Kind
    let place: Place
    let season: Season?
    let timeslot: Timeslot?
    let milestone: Milestone?
    /// 絵の種。**同じ種なら同じ絵**（作り直しはこれだけを替える）
    let seed: Int
    /// 配った日時（ISO 8601）
    let at: String
    /// 箔押し（まれに・2%）
    let foil: Bool
    /// 自分の手で貼った置き場（貼ったラベルだけ・2026-10-17 次の版）。無ければおまかせの置き場（`TrunkSlots`）
    let pos: TrunkPos?

    init(id: String, photoId: String, kind: Kind, place: Place, season: Season? = nil,
         timeslot: Timeslot? = nil, milestone: Milestone? = nil, seed: Int, at: String, foil: Bool = false,
         pos: TrunkPos? = nil) {
        self.id = id
        self.photoId = photoId
        self.kind = kind
        self.place = place
        self.season = season
        self.timeslot = timeslot
        self.milestone = milestone
        self.seed = seed
        self.at = at
        self.foil = foil
        self.pos = pos
    }

    /// 同じラベルで種だけ替えたもの（作り直しの候補を描く）
    func withSeed(_ seed: Int) -> TrunkLabel {
        TrunkLabel(id: id, photoId: photoId, kind: kind, place: place, season: season, timeslot: timeslot,
                   milestone: milestone, seed: seed, at: at, foil: foil, pos: pos)
    }

    /// 同じラベルで置き場だけ替えたもの（nil ならおまかせの置き場）
    func withPos(_ pos: TrunkPos?) -> TrunkLabel {
        TrunkLabel(id: id, photoId: photoId, kind: kind, place: place, season: season, timeslot: timeslot,
                   milestone: milestone, seed: seed, at: at, foil: foil, pos: pos)
    }

    private enum CodingKeys: String, CodingKey {
        case id, photoId, kind, place, season, timeslot, milestone, seed, at, foil, pos
    }
    private enum PlaceKeys: String, CodingKey { case name, latin, country }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // **id は道に入れる**（`/user/trunk/labels/{id}`）。サーバーの形（英数字と `-`・64 文字まで）に
        // 合わないものは読まない（`PathID` が要求を出さずに断る値を、押せる札にしない）
        guard let id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil,
              PathID.isSafe(id), id.utf8.count <= 64,
              let seed = LenientInt.read(c, .seed), seed >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "ラベルの id か種が読めない")
        }
        self.id = id
        self.seed = seed
        // 2026-10-17: サーバーは photoId を保存しなくなった（id が写真の id）。無い・空なら id を使う
        let storedPhotoId = ((try? c.decodeIfPresent(String.self, forKey: .photoId)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        photoId = (storedPhotoId?.isEmpty == false ? storedPhotoId : nil) ?? id
        let kindText = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        kind = kindText.flatMap(Kind.init(rawValue:)) ?? .place
        let p = try? c.nestedContainer(keyedBy: PlaceKeys.self, forKey: .place)
        func text(_ key: PlaceKeys) -> String? {
            guard let p, let raw = (try? p.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        place = Place(name: text(.name) ?? "", latin: text(.latin), country: text(.country))
        season = ((try? c.decodeIfPresent(String.self, forKey: .season)) ?? nil).flatMap(Season.init(rawValue:))
        timeslot = ((try? c.decodeIfPresent(String.self, forKey: .timeslot)) ?? nil).flatMap(Timeslot.init(rawValue:))
        milestone = ((try? c.decodeIfPresent(String.self, forKey: .milestone)) ?? nil).flatMap(Milestone.init(rawValue:))
        at = ((try? c.decodeIfPresent(String.self, forKey: .at)) ?? nil) ?? ""
        foil = ((try? c.decodeIfPresent(Bool.self, forKey: .foil)) ?? nil) ?? false
        // 置き場は包みで読む（無い・形が違う・範囲の外ならおまかせ）
        pos = (try? c.decodeIfPresent(Lenient<TrunkPos>.self, forKey: .pos))??.value
    }

    /// 配った日（日本時間の暦ではなく、`at` の頭の年月日をそのまま読む）。読めなければ nil
    var day: (year: Int, month: Int, day: Int)? {
        let parts = at.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 1900, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return (parts[0], parts[1], parts[2])
    }
}

/// 貼ったラベルの置き場（サーバーの `pos`）。x・y はトランクの正面（胴）の 0〜1 で、ラベルの真ん中。
/// rot は傾き（度・-30〜30）。**範囲の外の値は読まない**（おまかせに戻す）
struct TrunkPos: Codable, Equatable, Hashable {
    let x: Double
    let y: Double
    let rot: Double

    init(x: Double, y: Double, rot: Double) {
        self.x = x
        self.y = y
        self.rot = rot
    }

    /// 傾きの上限（サーバーの `ROT_MAX`）
    static let rotMax: Double = 30

    private enum CodingKeys: String, CodingKey { case x, y, rot }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        let rot = try c.decode(Double.self, forKey: .rot)
        guard x.isFinite, y.isFinite, rot.isFinite, (0...1).contains(x), (0...1).contains(y),
              (-Self.rotMax...Self.rotMax).contains(rot) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "置き場が範囲の外")
        }
        self.init(x: x, y: y, rot: rot)
    }
}

/// 付けている部品（サーバーの `equipped`）。**台帳に無い・場所の合わない・持っていない id は落とす**
struct TrunkEquipped: Codable, Equatable, Hashable {
    var handle: String?
    var corner: String?
    var lock: String?
    var lining: String?
    var tag: String?
    var charm: String?
    var key: String?
    /// ピンバッジ（3つまで）
    var pins: [String] = []
    /// ワッペン（2つまで）
    var patches: [String] = []

    static let none = TrunkEquipped()

    init(handle: String? = nil, corner: String? = nil, lock: String? = nil, lining: String? = nil, tag: String? = nil,
         charm: String? = nil, key: String? = nil, pins: [String] = [], patches: [String] = []) {
        self.handle = handle
        self.corner = corner
        self.lock = lock
        self.lining = lining
        self.tag = tag
        self.charm = charm
        self.key = key
        self.pins = pins
        self.patches = patches
    }

    /// 1つの場所に付けている id（ピン・ワッペンは並び）
    func ids(_ kind: TrunkPartKind) -> [String] {
        switch kind {
        case .handle: return handle.map { [$0] } ?? []
        case .corner: return corner.map { [$0] } ?? []
        case .lock: return lock.map { [$0] } ?? []
        case .lining: return lining.map { [$0] } ?? []
        case .tag: return tag.map { [$0] } ?? []
        case .charm: return charm.map { [$0] } ?? []
        case .key: return key.map { [$0] } ?? []
        case .pin: return pins
        case .patch: return patches
        }
    }

    /// 1つの場所を置き換える（数の上限で切る）
    func setting(_ kind: TrunkPartKind, _ ids: [String]) -> TrunkEquipped {
        var e = self
        let list = Array(ids.prefix(kind.capacity))
        switch kind {
        case .handle: e.handle = list.first
        case .corner: e.corner = list.first
        case .lock: e.lock = list.first
        case .lining: e.lining = list.first
        case .tag: e.tag = list.first
        case .charm: e.charm = list.first
        case .key: e.key = list.first
        case .pin: e.pins = list
        case .patch: e.patches = list
        }
        return e
    }

    /// 付けている id 全部
    var all: [String] { TrunkPartKind.allCases.flatMap(ids) }

    /// 持っていない・台帳に無い・場所の合わない id を落とす（サーバーの `parseEquipped` と同じ）
    func sanitized(owned: Set<String>?) -> TrunkEquipped {
        var out = TrunkEquipped()
        for kind in TrunkPartKind.allCases {
            var seen = Set<String>()
            let kept = ids(kind).filter { id in
                guard TrunkPartCatalog.part(id)?.kind == kind, owned?.contains(id) ?? true, !seen.contains(id) else { return false }
                seen.insert(id)
                return true
            }
            out = out.setting(kind, kept)
        }
        return out
    }

    private enum CodingKeys: String, CodingKey { case handle, corner, lock, lining, tag, charm, key, pins, patches }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func one(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        func list(_ key: CodingKeys) -> [String] {
            ((try? c.decodeIfPresent([Lenient<String>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
        }
        self.init(handle: one(.handle), corner: one(.corner), lock: one(.lock), lining: one(.lining), tag: one(.tag),
                  charm: one(.charm), key: one(.key), pins: list(.pins), patches: list(.patches))
    }

    /// `PUT /user/trunk/equip` の本文。**場所を全部送り、外した場所は null**（サーバーは null を「外す」と読む）
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        for (key, value) in [(CodingKeys.handle, handle), (.corner, corner), (.lock, lock), (.lining, lining), (.tag, tag),
                             (.charm, charm), (.key, key)] {
            if let value { try c.encode(value, forKey: key) } else { try c.encodeNil(forKey: key) }
        }
        try c.encode(Array(pins.prefix(TrunkPartKind.pin.capacity)), forKey: .pins)
        try c.encode(Array(patches.prefix(TrunkPartKind.patch.capacity)), forKey: .patches)
    }
}


/// トランクの型（サーバーの `FREE_MODELS`・`PRO_MODELS`）
enum TrunkModel: String, CaseIterable, Identifiable {
    case leather, canvas, aluminum, steamer
    case urushi, kori, sleeper, clipper, captain, starchart

    var id: String { rawValue }

    static let free: [TrunkModel] = [.leather, .canvas, .aluminum, .steamer]
    static let pro: [TrunkModel] = [.urushi, .kori, .sleeper, .clipper, .captain, .starchart]

    var isPro: Bool { Self.pro.contains(self) }
}

/// 作り直しの選びかけ（候補の種3つ・選ぶまで残る）
struct TrunkPendingReroll: Equatable {
    let labelId: String
    let seeds: [Int]
}

/// `GET /user/trunk` の応答（書き込みの口も同じ形で、`posts` だけが無い）
struct TrunkState: Decodable, Equatable {
    /// 選んでいる型（Pro をやめても保存は残る）
    let model: TrunkModel
    /// いま描く型（Pro をやめたら最後の無料の型・サーバーが決める）
    let effectiveModel: TrunkModel
    /// 手持ち（新しい順）
    let pocket: [TrunkLabel]
    /// 貼ったもの（新しい順）
    let stuck: [TrunkLabel]
    /// 手持ちの上限（無料 30・Pro 150）
    let limit: Int
    let isPro: Bool
    /// 今月あと何回作り直せるか（Pro でなければ 0）
    let rerollsLeft: Int
    let pendingReroll: TrunkPendingReroll?
    /// 公開している投稿の数（古び方に使う）。書き込みの応答には無い → nil
    let posts: Int?
    /// ラベルを受け取るか
    let receiveLabels: Bool
    /// 硬貨の枚数（公開の投稿1件で1枚・カプセルの機械で使う・2026-10-17 次の版）。古いサーバーは 0
    let coins: Int
    /// 持っている部品の id（台帳にあるものだけ・新しい順）
    let parts: [String]
    /// かけらの数（同じ部品が出たら +1・5つで交換）
    let fragments: Int
    /// 付けている部品（持っているものだけ）
    let equipped: TrunkEquipped
    /// ほかの人にトランクを見せるか（2026-10-18・人のトランク）。古いサーバーは項目が無い → 既定の true
    let showTrunk: Bool
    /// わたしの乗車券（人のトランクの中に出す1枚・サーバーに置いたもの）。置いていなければ nil
    let ticket: TrunkTicket?

    init(model: TrunkModel, effectiveModel: TrunkModel? = nil, pocket: [TrunkLabel], stuck: [TrunkLabel],
         limit: Int, isPro: Bool, rerollsLeft: Int, pendingReroll: TrunkPendingReroll? = nil,
         posts: Int?, receiveLabels: Bool, coins: Int = 0, parts: [String] = [], fragments: Int = 0,
         equipped: TrunkEquipped = .none, showTrunk: Bool = true, ticket: TrunkTicket? = nil) {
        self.model = model
        self.effectiveModel = effectiveModel ?? model
        self.pocket = pocket
        self.stuck = stuck
        self.limit = limit
        self.isPro = isPro
        self.rerollsLeft = rerollsLeft
        self.pendingReroll = pendingReroll
        self.posts = posts
        self.receiveLabels = receiveLabels
        self.coins = max(0, coins)
        self.parts = parts
        self.fragments = max(0, fragments)
        self.equipped = equipped
        self.showTrunk = showTrunk
        self.ticket = ticket
    }

    /// 同じ状態で一部だけ替えたもの（端末の中の移り変わり・ガチャの結果を足す）
    func copy(pocket: [TrunkLabel]? = nil, stuck: [TrunkLabel]? = nil, model: TrunkModel? = nil,
              effectiveModel: TrunkModel? = nil, rerollsLeft: Int? = nil,
              pendingReroll: TrunkPendingReroll?? = nil, posts: Int?? = nil, receiveLabels: Bool? = nil,
              coins: Int? = nil, parts: [String]? = nil, fragments: Int? = nil,
              equipped: TrunkEquipped? = nil, showTrunk: Bool? = nil, ticket: TrunkTicket?? = nil) -> TrunkState {
        TrunkState(model: model ?? self.model, effectiveModel: effectiveModel ?? self.effectiveModel,
                   pocket: pocket ?? self.pocket, stuck: stuck ?? self.stuck, limit: limit, isPro: isPro,
                   rerollsLeft: rerollsLeft ?? self.rerollsLeft,
                   pendingReroll: pendingReroll == nil ? self.pendingReroll : pendingReroll!,
                   posts: posts == nil ? self.posts : posts!, receiveLabels: receiveLabels ?? self.receiveLabels,
                   coins: coins ?? self.coins, parts: parts ?? self.parts, fragments: fragments ?? self.fragments,
                   equipped: equipped ?? self.equipped, showTrunk: showTrunk ?? self.showTrunk,
                   ticket: ticket == nil ? self.ticket : ticket!)
    }

    /// 持っている部品（台帳の順ではなく、届いた新しい順）
    var ownedParts: Set<String> { Set(parts) }

    /// サーバーの既定（無料 30）。`limit` が読めない応答に使う
    static let freeLimit = 30
    static let proLimit = 150

    private enum CodingKeys: String, CodingKey {
        case model, effectiveModel, pocket, stuck, limit, isPro, rerolls, pendingReroll, posts, receiveLabels
        case coins, parts, fragments, equipped, showTrunk, ticket
    }
    private enum RerollKeys: String, CodingKey { case left, month }
    private enum PendingKeys: String, CodingKey { case labelId, seeds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // **手持ちと貼った一覧のどちらも無い応答は投げる**（形の違う応答を「空のトランク」と混ぜない。
        // `TripPlanList` と同じ判断）。片方だけなら、無い方は空
        guard c.contains(.pocket) || c.contains(.stuck) else {
            throw DecodingError.keyNotFound(CodingKeys.pocket, .init(codingPath: c.codingPath,
                                                                     debugDescription: "トランクの形ではない"))
        }
        func labels(_ key: CodingKeys) -> [TrunkLabel] {
            ((try? c.decodeIfPresent([Lenient<TrunkLabel>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
        }
        pocket = labels(.pocket)
        stuck = labels(.stuck)
        let modelText = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil
        let effectiveText = (try? c.decodeIfPresent(String.self, forKey: .effectiveModel)) ?? nil
        let model = modelText.flatMap(TrunkModel.init(rawValue:)) ?? .leather
        self.model = model
        effectiveModel = effectiveText.flatMap(TrunkModel.init(rawValue:)) ?? (model.isPro ? .leather : model)
        let pro = ((try? c.decodeIfPresent(Bool.self, forKey: .isPro)) ?? nil) ?? false
        isPro = pro
        let limit = LenientInt.read(c, .limit) ?? (pro ? Self.proLimit : Self.freeLimit)
        self.limit = max(1, limit)
        if let r = try? c.nestedContainer(keyedBy: RerollKeys.self, forKey: .rerolls) {
            rerollsLeft = max(0, LenientInt.read(r, .left) ?? 0)
        } else {
            rerollsLeft = 0
        }
        if let p = try? c.nestedContainer(keyedBy: PendingKeys.self, forKey: .pendingReroll),
           let labelId = (try? p.decodeIfPresent(String.self, forKey: .labelId)) ?? nil {
            let seeds = ((try? p.decodeIfPresent([Lenient<Int>].self, forKey: .seeds)) ?? nil)?
                .compactMap(\.value).filter { $0 >= 0 } ?? []
            pendingReroll = seeds.isEmpty ? nil : TrunkPendingReroll(labelId: labelId, seeds: seeds)
        } else {
            pendingReroll = nil
        }
        posts = LenientInt.read(c, .posts).map { max(0, $0) }
        receiveLabels = ((try? c.decodeIfPresent(Bool.self, forKey: .receiveLabels)) ?? nil) ?? true
        // 硬貨・部品・かけら・付けている部品（2026-10-17 次の版）。**どれも包みで読み、無ければ 0・空**
        // （部品の口が無い古いサーバーでも、トランクの画面は今までどおり）
        coins = max(0, LenientInt.read(c, .coins) ?? 0)
        var seen = Set<String>()
        parts = (((try? c.decodeIfPresent([Lenient<String>].self, forKey: .parts)) ?? nil)?.compactMap(\.value) ?? [])
            .filter { TrunkPartCatalog.part($0) != nil && seen.insert($0).inserted }
        fragments = max(0, LenientInt.read(c, .fragments) ?? 0)
        let rawEquipped = (try? c.decodeIfPresent(Lenient<TrunkEquipped>.self, forKey: .equipped))??.value ?? .none
        equipped = rawEquipped.sanitized(owned: Set(parts))
        // 見せる設定とわたしの乗車券（2026-10-18）。**包みで読み、無ければ見せる・乗車券なし**
        showTrunk = ((try? c.decodeIfPresent(Bool.self, forKey: .showTrunk)) ?? nil) ?? true
        ticket = (try? c.decodeIfPresent(Lenient<TrunkTicket>.self, forKey: .ticket))??.value
    }

    /// 書き込みの応答（`posts` が無い）に、前に読んだ投稿の数を引き継ぐ
    func keepingPosts(from previous: TrunkState?) -> TrunkState {
        guard posts == nil, let previousPosts = previous?.posts else { return self }
        return copy(posts: .some(previousPosts))
    }
}

/// 配った結果（`POST /upload/save` と、下書きを公開した `PUT /photos/{id}` の応答の `label`・`labelSkipped`）。
/// **どちらも包みで読み、古いサーバーが返さなくても、形が違っても投げない**
struct TrunkDealt: Decodable, Equatable {
    let label: TrunkLabel?
    let labelSkipped: TrunkLabelSkip?
    /// 配った硬貨（0 か 1・2026-10-17 次の版）。**手持ちがいっぱい・受け取らない設定でも配られる**
    let coin: Int

    init(label: TrunkLabel? = nil, labelSkipped: TrunkLabelSkip? = nil, coin: Int = 0) {
        self.label = label
        self.labelSkipped = labelSkipped
        self.coin = coin
    }

    private enum CodingKeys: String, CodingKey { case label, labelSkipped, coin }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        // 硬貨は 0 か 1 だけ読む（知らない値・負の数・大きい数は 0）
        let coin = LenientInt.read(c, .coin) ?? 0
        self.init(label: (try? c.decodeIfPresent(Lenient<TrunkLabel>.self, forKey: .label))??.value,
                  labelSkipped: ((try? c.decodeIfPresent(String.self, forKey: .labelSkipped)) ?? nil).map(TrunkLabelSkip.init),
                  coin: coin == 1 ? 1 : 0)
    }

    /// 応答の本文から読む（読めなければ空）
    static func read(_ data: Data) -> TrunkDealt {
        (try? JSONDecoder.api.decode(TrunkDealt.self, from: data)) ?? TrunkDealt()
    }
}

/// 投稿の保存（`POST /upload/save`）で、ラベルを配らなかった理由（サーバーの `labelSkipped`）
enum TrunkLabelSkip: Equatable {
    /// 手持ちがいっぱい（貼るか削除すると、また届く）
    case full
    /// トランクの行の大きさが上限に近く、受け取れなかった（サーバーの `storage`・2026-10-17）
    case storage
    /// 受け取らない設定
    case off
    /// 同じ写真（指紋）に配り済み
    case duplicate
    /// その日に3枚配った
    case daily
    /// 同じ束の投稿に配り済み
    case samePost
    /// 下書き・非公開
    case draft
    /// 時間切れ・失敗・知らない理由（届いていれば `GET /user/trunk` に出る）
    case other(String)

    init(_ raw: String) {
        switch raw {
        case "full": self = .full
        case "storage": self = .storage
        case "off": self = .off
        case "duplicate": self = .duplicate
        case "daily": self = .daily
        case "samePost": self = .samePost
        case "draft": self = .draft
        default: self = .other(raw)
        }
    }
}

/// カプセルの機械を回した結果（`POST /user/trunk/gacha` → `{ part, duplicate, fragments, coins }`・2026-10-17 次の版）。
/// **部品の id がこの版の台帳に無ければ投げる**（描けない部品を「出た」と見せない。画面は読み直す）
struct TrunkGachaResult: Decodable, Equatable {
    let part: TrunkPart
    /// 持っている部品だった（かけらが 1 増えた）
    let duplicate: Bool
    /// 回したあとのかけらの数
    let fragments: Int
    /// 回したあとの硬貨の数
    let coins: Int

    init(part: TrunkPart, duplicate: Bool, fragments: Int, coins: Int) {
        self.part = part
        self.duplicate = duplicate
        self.fragments = max(0, fragments)
        self.coins = max(0, coins)
    }

    private enum CodingKeys: String, CodingKey { case part, duplicate, fragments, coins }
    private enum PartKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p = try c.nestedContainer(keyedBy: PartKeys.self, forKey: .part)
        let id = try p.decode(String.self, forKey: .id)
        guard let part = TrunkPartCatalog.part(id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: p, debugDescription: "台帳に無い部品")
        }
        self.init(part: part, duplicate: ((try? c.decodeIfPresent(Bool.self, forKey: .duplicate)) ?? nil) ?? false,
                  fragments: LenientInt.read(c, .fragments) ?? 0, coins: LenientInt.read(c, .coins) ?? 0)
    }

    /// 回す前の状態に結果を足す（応答は状態を丸ごと返さないので、硬貨・かけら・部品だけを置き換える）
    func applied(to state: TrunkState) -> TrunkState {
        let parts = duplicate || state.parts.contains(part.id) ? state.parts : [part.id] + state.parts
        return state.copy(coins: coins, parts: parts, fragments: fragments)
    }
}
