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

    init(id: String, photoId: String, kind: Kind, place: Place, season: Season? = nil,
         timeslot: Timeslot? = nil, milestone: Milestone? = nil, seed: Int, at: String, foil: Bool = false) {
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
    }

    /// 同じラベルで種だけ替えたもの（作り直しの候補を描く）
    func withSeed(_ seed: Int) -> TrunkLabel {
        TrunkLabel(id: id, photoId: photoId, kind: kind, place: place, season: season, timeslot: timeslot,
                   milestone: milestone, seed: seed, at: at, foil: foil)
    }

    private enum CodingKeys: String, CodingKey {
        case id, photoId, kind, place, season, timeslot, milestone, seed, at, foil
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
    }

    /// 配った日（日本時間の暦ではなく、`at` の頭の年月日をそのまま読む）。読めなければ nil
    var day: (year: Int, month: Int, day: Int)? {
        let parts = at.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 1900, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return (parts[0], parts[1], parts[2])
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

    init(model: TrunkModel, effectiveModel: TrunkModel? = nil, pocket: [TrunkLabel], stuck: [TrunkLabel],
         limit: Int, isPro: Bool, rerollsLeft: Int, pendingReroll: TrunkPendingReroll? = nil,
         posts: Int?, receiveLabels: Bool) {
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
    }

    /// サーバーの既定（無料 30）。`limit` が読めない応答に使う
    static let freeLimit = 30
    static let proLimit = 150

    private enum CodingKeys: String, CodingKey {
        case model, effectiveModel, pocket, stuck, limit, isPro, rerolls, pendingReroll, posts, receiveLabels
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
    }

    /// 書き込みの応答（`posts` が無い）に、前に読んだ投稿の数を引き継ぐ
    func keepingPosts(from previous: TrunkState?) -> TrunkState {
        guard posts == nil, let previousPosts = previous?.posts else { return self }
        return TrunkState(model: model, effectiveModel: effectiveModel, pocket: pocket, stuck: stuck, limit: limit,
                          isPro: isPro, rerollsLeft: rerollsLeft, pendingReroll: pendingReroll,
                          posts: previousPosts, receiveLabels: receiveLabels)
    }
}

/// 配った結果（`POST /upload/save` と、下書きを公開した `PUT /photos/{id}` の応答の `label`・`labelSkipped`）。
/// **どちらも包みで読み、古いサーバーが返さなくても、形が違っても投げない**
struct TrunkDealt: Decodable, Equatable {
    let label: TrunkLabel?
    let labelSkipped: TrunkLabelSkip?

    init(label: TrunkLabel? = nil, labelSkipped: TrunkLabelSkip? = nil) {
        self.label = label
        self.labelSkipped = labelSkipped
    }

    private enum CodingKeys: String, CodingKey { case label, labelSkipped }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(label: (try? c.decodeIfPresent(Lenient<TrunkLabel>.self, forKey: .label))??.value,
                  labelSkipped: ((try? c.decodeIfPresent(String.self, forKey: .labelSkipped)) ?? nil).map(TrunkLabelSkip.init))
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
