import Foundation

// 旅のトランク（2026-10-17 owner 承認・モック「旅のトランク」）。
//
// サーバーは `api-user/src/trunk.ts`（photo-gallery の `claude/journey-photo-ios-features-herhk1`）。
// 応答の形は `view()`＋`posts`:
//
//     { model, effectiveModel, pocket[], stuck[], limit, isPro,
//       rerolls{left, month}, pendingReroll?{labelId, seeds[], at}, posts, receiveLabels,
//       custom?{n, t, every, rerolls} }
//
// 2026-11-23（札 #706・owner 承認）: 作り直しは全員・ラベルごとに3回（ラベルの `rr`・候補 `cs`）。
// Pro の月3回（`rerolls`・`pendingReroll`）はやめた——古いサーバーと古いアプリのための欄で、画面では使わない。
// 好きなデザインで作る（ラベルの `cu`・状態の `custom`）。**`custom` の欄が無いサーバーでは、どちらの口も出さない**
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
    /// おまかせの置き場の番号（`TrunkSlots.slots` の番号・置き場 `pos` の無い貼ったラベルだけ・2026-10-19）。
    /// はがすときに、ずれるラベルへサーバーが同じ1回で書く（`TrunkPlacement.slotsBeforeUnstick`）。無ければ並びの何番目かで置く
    let slot: Int?
    /// 作り直した回数（0〜`TrunkLabel.rerollMax`・サーバーの `rr`・#706）。はがしても残る
    let rerolls: Int
    /// 作り直しの候補の種（先頭は最初の1枚・サーバーの `cs`・#706）。貼ったら消える
    let candidates: [Int]
    /// 好きなデザインで作った形・色・絵（サーバーの `cu`・#706）。無ければ種から決める
    let custom: TrunkLabelCustom?

    /// ラベル1枚の作り直しの上限（サーバーの `REROLLS_PER_LABEL`）
    static let rerollMax = 3

    init(id: String, photoId: String, kind: Kind, place: Place, season: Season? = nil,
         timeslot: Timeslot? = nil, milestone: Milestone? = nil, seed: Int, at: String, foil: Bool = false,
         pos: TrunkPos? = nil, slot: Int? = nil, rerolls: Int = 0, candidates: [Int] = [],
         custom: TrunkLabelCustom? = nil) {
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
        self.slot = pos == nil ? slot : nil
        self.rerolls = min(Self.rerollMax, max(0, rerolls))
        self.candidates = candidates
        self.custom = custom
    }

    /// 一部だけ替えたもの（ほかの欄はそのまま引き継ぐ）
    private func with(seed: Int? = nil, pos: TrunkPos?? = nil, slot: Int?? = nil, rerolls: Int? = nil,
                      candidates: [Int]? = nil, custom: TrunkLabelCustom?? = nil) -> TrunkLabel {
        TrunkLabel(id: id, photoId: photoId, kind: kind, place: place, season: season, timeslot: timeslot,
                   milestone: milestone, seed: seed ?? self.seed, at: at, foil: foil,
                   pos: pos == nil ? self.pos : pos!, slot: slot == nil ? self.slot : slot!,
                   rerolls: rerolls ?? self.rerolls, candidates: candidates ?? self.candidates,
                   custom: custom == nil ? self.custom : custom!)
    }

    /// 同じラベルで種だけ替えたもの（作り直しの候補を描く）
    func withSeed(_ seed: Int) -> TrunkLabel { with(seed: seed) }

    /// 同じラベルで置き場だけ替えたもの（nil ならおまかせの置き場）。**おまかせの置き場の番号は消す**（サーバーと同じ）
    func withPos(_ pos: TrunkPos?) -> TrunkLabel { with(pos: .some(pos), slot: .some(nil)) }

    /// 置き場なしで、おまかせの置き場の番号だけ替えたもの（nil なら並びの何番目かで置く）
    func withSlot(_ slot: Int?) -> TrunkLabel { with(pos: .some(nil), slot: .some(slot)) }

    /// 作り直しを1回足したもの（サーバーの `rerollMutation` と同じ: 候補の先頭に最初の1枚を置き、新しい種を選んだ状態）
    func withReroll(seed newSeed: Int) -> TrunkLabel {
        let list = candidates.isEmpty ? [seed] : candidates
        return with(seed: newSeed, rerolls: rerolls + 1, candidates: Array((list + [newSeed]).prefix(Self.rerollMax + 1)))
    }

    /// 貼るとき（候補は消す・回数は残す）
    func droppingCandidates() -> TrunkLabel { with(candidates: []) }

    /// 好きなデザインを付けたもの
    func withCustom(_ custom: TrunkLabelCustom?) -> TrunkLabel { with(custom: .some(custom)) }

    /// 選べる候補（作り直していなければ今の種だけ）
    var choices: [Int] { candidates.isEmpty ? [seed] : candidates }

    /// あと何回作り直せるか
    var rerollsLeft: Int { max(0, Self.rerollMax - rerolls) }

    private enum CodingKeys: String, CodingKey {
        case id, photoId, kind, place, season, timeslot, milestone, seed, at, foil, pos, slot
        case rr, cs, cu
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
        // 番号は置き場の無いラベルだけ・範囲の内だけ読む（違えば並びの何番目かで置く）
        let slotValue = LenientInt.read(c, .slot)
        slot = pos == nil ? slotValue.flatMap { (0..<TrunkSlots.capacity).contains($0) ? $0 : nil } : nil
        // 作り直し・好きなデザイン（#706）。**包みで読み、範囲の外は無いものとする**（古いサーバーは返さない）
        rerolls = min(Self.rerollMax, max(0, LenientInt.read(c, .rr) ?? 0))
        let rawCandidates = ((try? c.decodeIfPresent([Lenient<Int>].self, forKey: .cs)) ?? nil)?.compactMap(\.value) ?? []
        candidates = rawCandidates.count <= Self.rerollMax + 1 && rawCandidates.allSatisfy({ $0 >= 0 }) ? rawCandidates : []
        custom = (try? c.decodeIfPresent(Lenient<TrunkLabelCustom>.self, forKey: .cu))??.value
    }

    /// 配った日（日本時間の暦ではなく、`at` の頭の年月日をそのまま読む）。読めなければ nil
    var day: (year: Int, month: Int, day: Int)? {
        let parts = at.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 1900, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return (parts[0], parts[1], parts[2])
    }
}

/// 好きなデザインの番号（サーバーの `cu`・#706）。形・色・絵は `TrunkLabelDesign.customShapes`・`customPalettes`・
/// `customArts` の並びの番号。**範囲の外は読まない**（ふつうの図柄で描く）
struct TrunkLabelCustom: Codable, Equatable, Hashable {
    let shape: Int
    let palette: Int
    let art: Int

    init(shape: Int, palette: Int, art: Int) {
        self.shape = shape
        self.palette = palette
        self.art = art
    }

    /// 番号がどれも並びの中か
    var isValid: Bool {
        (0..<TrunkLabelDesign.customShapes.count).contains(shape)
            && (0..<TrunkLabelDesign.customPalettes.count).contains(palette)
            && (0..<TrunkLabelDesign.customArts.count).contains(art)
    }

    private enum CodingKeys: String, CodingKey { case shape, palette, art }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let shape = LenientInt.read(c, .shape), let palette = LenientInt.read(c, .palette),
              let art = LenientInt.read(c, .art) else {
            throw DecodingError.dataCorruptedError(forKey: .shape, in: c, debugDescription: "好きなデザインの番号が読めない")
        }
        self.init(shape: shape, palette: palette, art: art)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .shape, in: c, debugDescription: "好きなデザインの番号が範囲の外")
        }
    }
}

/// 好きなデザインで作るまでの進み（サーバーの `custom`・#706）
struct TrunkCustomProgress: Equatable {
    /// 進み（0〜`every`−1）
    let posts: Int
    /// 使える回数（0〜3）
    let tickets: Int
    /// 何投稿ごとか（無料 3・Pro 2）
    let every: Int
    /// ラベル1枚の作り直しの上限
    let rerollsPerLabel: Int

    init(posts: Int, tickets: Int, every: Int, rerollsPerLabel: Int = TrunkLabel.rerollMax) {
        self.every = max(1, every)
        self.posts = min(max(0, posts), self.every - 1)
        self.tickets = min(max(0, tickets), Self.ticketsMax)
        self.rerollsPerLabel = max(0, rerollsPerLabel)
    }

    /// 持っておける回数の上限（サーバーの `CUSTOM_TICKETS_MAX`）
    static let ticketsMax = 3

    /// あと何回の投稿で作れるか（1 以上）
    var postsLeft: Int { max(1, every - posts) }

    /// 好きなデザインで作れる（使える回数がある）。**進みでは決めない**——使わずに次を投稿すると進みが 1 以上でも
    /// 回数は残っている（2026-11-23 確かめ役の指摘: 前は進みが 0 のときだけ出していて、回数があるのに主ボタンが消えた）
    var canMake: Bool { tickets > 0 }
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

/// 手荷物タグの枠ごとの選び（2026-11-08 owner 承認・札 #501）。サーバーの `tagPicks` の1要素:
/// `""` = おまかせ（新しいラベルから自動）・`"_"` = その枠にタグを吊るさない・それ以外 = 貼ったラベルの id
/// （人のトランクでは、その返答の中の番号 `s<n>`）
enum TrunkTagPick: Equatable, Hashable {
    case auto
    /// 「タグを外す」: その枠には何も吊るさない
    case removed
    case label(String)

    /// サーバーの「その枠にタグを吊るさない」の印（`TAG_PICK_NONE`）
    static let removedToken = "_"
    /// 枠の数の上限（サーバーの `TAG_PICKS_MAX`・`TrunkLooks.tagSlots` の数）
    static let maxSlots = 3

    init(wire: String) {
        switch wire {
        case "": self = .auto
        case Self.removedToken: self = .removed
        default: self = .label(wire)
        }
    }

    var wire: String {
        switch self {
        case .auto: return ""
        case .removed: return Self.removedToken
        case .label(let id): return id
        }
    }

    /// 枠の順の選び。末尾のおまかせは持たず、枠の数までに収める（サーバーの保存の形と同じ）
    static func normalized(_ picks: [TrunkTagPick]) -> [TrunkTagPick] {
        var out = Array(picks.prefix(maxSlots))
        while out.last == .auto { out.removeLast() }
        return out
    }

    /// 線の上の文字の並びから（形の違うものは作らない＝おまかせ）
    static func list(wire: [String]) -> [TrunkTagPick] {
        normalized(wire.map { TrunkTagPick(wire: $0) })
    }
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
    /// ほかの人にトランクを見せるか（2026-10-18・人のトランク）。**欄の無い応答（人のトランクの口がまだ無いサーバー）は false**
    /// ——見せる口が無いのに「見せています」と言わない
    let showTrunk: Bool
    /// サーバーが人のトランク（見せる設定・わたしの乗車券）に対応しているか。**応答に `showTrunk` の欄があるか**で決める
    /// （対応したサーバーはいつも返す。いまの本番は返さない）。対応していない間は、設定の節を出さず、PUT も送らない
    let supportsSharing: Bool
    /// わたしの乗車券（人のトランクの中に出す1枚・サーバーに置いたもの）。置いていなければ nil
    let ticket: TrunkTicket?
    /// 手荷物タグの枠ごとの選び（2026-11-08・サーバーが、はがした枠を直して返す）。無ければ全部おまかせ
    let tagPicks: [TrunkTagPick]
    /// 好きなデザインで作るまでの進み（#706）。**欄の無い応答（古いサーバー）は nil**——そのときは作り直しも
    /// 好きなデザインも出さない（古いサーバーは本文の回数を読まず、Pro の月の数え方のまま）
    let custom: TrunkCustomProgress?
    /// サーバーがタグの選びに対応しているか。**応答に `tagPicks` の欄があるか**で決める（対応したサーバーはいつも返す）。
    /// 対応していない間は、選ぶ口を出さず、PUT も送らない（旧サーバーが黙って捨てる設定を「保存した」と言わない）
    let supportsTagPicks: Bool

    init(model: TrunkModel, effectiveModel: TrunkModel? = nil, pocket: [TrunkLabel], stuck: [TrunkLabel],
         limit: Int, isPro: Bool, rerollsLeft: Int, pendingReroll: TrunkPendingReroll? = nil,
         posts: Int?, receiveLabels: Bool, coins: Int = 0, parts: [String] = [], fragments: Int = 0,
         equipped: TrunkEquipped = .none, showTrunk: Bool = true, ticket: TrunkTicket? = nil,
         supportsSharing: Bool = true, tagPicks: [TrunkTagPick] = [], supportsTagPicks: Bool = true,
         custom: TrunkCustomProgress? = nil) {
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
        self.supportsSharing = supportsSharing
        self.tagPicks = TrunkTagPick.normalized(tagPicks)
        self.supportsTagPicks = supportsTagPicks
        self.custom = custom
    }

    /// 同じ状態で一部だけ替えたもの（端末の中の移り変わり・ガチャの結果を足す）
    func copy(pocket: [TrunkLabel]? = nil, stuck: [TrunkLabel]? = nil, model: TrunkModel? = nil,
              effectiveModel: TrunkModel? = nil, rerollsLeft: Int? = nil,
              pendingReroll: TrunkPendingReroll?? = nil, posts: Int?? = nil, receiveLabels: Bool? = nil,
              coins: Int? = nil, parts: [String]? = nil, fragments: Int? = nil,
              equipped: TrunkEquipped? = nil, showTrunk: Bool? = nil, ticket: TrunkTicket?? = nil,
              tagPicks: [TrunkTagPick]? = nil, custom: TrunkCustomProgress?? = nil) -> TrunkState {
        TrunkState(model: model ?? self.model, effectiveModel: effectiveModel ?? self.effectiveModel,
                   pocket: pocket ?? self.pocket, stuck: stuck ?? self.stuck, limit: limit, isPro: isPro,
                   rerollsLeft: rerollsLeft ?? self.rerollsLeft,
                   pendingReroll: pendingReroll == nil ? self.pendingReroll : pendingReroll!,
                   posts: posts == nil ? self.posts : posts!, receiveLabels: receiveLabels ?? self.receiveLabels,
                   coins: coins ?? self.coins, parts: parts ?? self.parts, fragments: fragments ?? self.fragments,
                   equipped: equipped ?? self.equipped, showTrunk: showTrunk ?? self.showTrunk,
                   ticket: ticket == nil ? self.ticket : ticket!, supportsSharing: supportsSharing,
                   tagPicks: tagPicks ?? self.tagPicks, supportsTagPicks: supportsTagPicks,
                   custom: custom == nil ? self.custom : custom!)
    }

    /// サーバーがラベルごとの作り直しと好きなデザインに対応しているか（`custom` の欄があるか）
    var supportsLabelReroll: Bool { custom != nil }

    /// 1枚のラベルを替えたもの（手持ち・貼った方のどちらでも）
    func replacing(_ id: String, _ change: (TrunkLabel) -> TrunkLabel) -> TrunkState {
        copy(pocket: pocket.map { $0.id == id ? change($0) : $0 }, stuck: stuck.map { $0.id == id ? change($0) : $0 })
    }

    /// 持っている部品（台帳の順ではなく、届いた新しい順）
    var ownedParts: Set<String> { Set(parts) }

    /// サーバーの既定（無料 30）。`limit` が読めない応答に使う
    static let freeLimit = 30
    static let proLimit = 150

    private enum CodingKeys: String, CodingKey {
        case model, effectiveModel, pocket, stuck, limit, isPro, rerolls, pendingReroll, posts, receiveLabels
        case coins, parts, fragments, equipped, showTrunk, ticket, tagPicks, custom
    }
    private enum RerollKeys: String, CodingKey { case left, month }
    private enum CustomKeys: String, CodingKey { case n, t, every, rerolls }
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
        // 見せる設定とわたしの乗車券（2026-10-18）。**包みで読む**。欄が無ければ、サーバーが対応していない（見せない・乗車券なし）
        let shows = (try? c.decodeIfPresent(Bool.self, forKey: .showTrunk)) ?? nil
        supportsSharing = shows != nil
        showTrunk = shows ?? false
        ticket = (try? c.decodeIfPresent(Lenient<TrunkTicket>.self, forKey: .ticket))??.value
        // 手荷物タグの選び（2026-11-08）。**包みで読む**。欄が無ければ、サーバーが対応していない（全部おまかせ・選ぶ口を出さない）
        let picks = (try? c.decodeIfPresent([Lenient<String>].self, forKey: .tagPicks)) ?? nil
        supportsTagPicks = picks != nil
        tagPicks = TrunkTagPick.list(wire: picks?.map { $0.value ?? "" } ?? [])
        // 好きなデザインで作るまでの進み（#706）。**欄が無い・形が違えば nil**（作り直しの口を出さない）
        if let k = try? c.nestedContainer(keyedBy: CustomKeys.self, forKey: .custom) {
            custom = TrunkCustomProgress(posts: LenientInt.read(k, .n) ?? 0, tickets: LenientInt.read(k, .t) ?? 0,
                                         every: LenientInt.read(k, .every) ?? (pro ? 2 : 3),
                                         rerollsPerLabel: LenientInt.read(k, .rerolls) ?? TrunkLabel.rerollMax)
        } else {
            custom = nil
        }
    }

    /// ほかの人に見えているか（サーバーが対応していて、見せる設定がオン）
    var sharedWithOthers: Bool { supportsSharing && showTrunk }

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
    /// 配ったかけら（0 か 1・札 #713）。投稿のお礼にかけらを配るのはサーバーの変更（`api-user/src/trunk.ts` の投稿のお礼）で、
    /// 今のサーバーは返さない（無ければ 0）。返すようになったら、届いた画面の札と知らせにそのまま出る
    let fragment: Int
    // 2026-11-23（札 #709）: とおまわり号を消したので、応答の `camper.added` は読まない（サーバーは返し続けても害は無い）

    init(label: TrunkLabel? = nil, labelSkipped: TrunkLabelSkip? = nil, coin: Int = 0, fragment: Int = 0) {
        self.label = label
        self.labelSkipped = labelSkipped
        self.coin = coin
        self.fragment = fragment
    }

    private enum CodingKeys: String, CodingKey { case label, labelSkipped, coin, fragment }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        // 硬貨は 0 か 1 だけ読む（知らない値・負の数・大きい数は 0）
        let coin = LenientInt.read(c, .coin) ?? 0
        // かけらも 0 か 1 だけ読む（無い・知らない値は 0）
        let fragment = LenientInt.read(c, .fragment) ?? 0
        self.init(label: (try? c.decodeIfPresent(Lenient<TrunkLabel>.self, forKey: .label))??.value,
                  labelSkipped: ((try? c.decodeIfPresent(String.self, forKey: .labelSkipped)) ?? nil).map(TrunkLabelSkip.init),
                  coin: coin == 1 ? 1 : 0, fragment: fragment == 1 ? 1 : 0)
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
