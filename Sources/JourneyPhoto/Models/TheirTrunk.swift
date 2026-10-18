import Foundation

// 人のトランク（2026-10-18 owner「トランクはマイページに載せたい。他の人のトランクの中身とか見れたら楽しい」・
// 板 TheirTrunk・TheirInside・ProfileTrunk・TrunkPrivacy）。
//
// サーバーは `api-user/src/trunk.ts` の `readTheirTrunk`（`GET /users/{uid}/trunk`・ログインした人だけ）:
//
//     { userId, model, stuck: [ラベル], equipped, posts?,
//       inside: { badges, card: { pro } | null, ticket: { photoId, note, origin, destination, face, showsFrom } | null } }
//
// - ラベルの `id` は「s＋番号」で**1回の返答の中だけ**の見分け（写真の id は来ない）。返答をまたいで同じラベルを指さない
// - 地名を見せてよいと確かめていないラベルと、地名がもともと無いラベルは同じ形
//   `{ id, kind, seed, foil?, pos?, place: { name: "" }, where: null }`。**2つを見分けない**
//   （画面は「地名が空なら地名なしの形で描く」・`TrunkLabelDesign.isSealed`）
// - 見せない・ブロック・退会・行が無いは、どれも区別しない 404（`TrunkService.theirs` が nil で返す）
//
// **どの項目も包みで読み、欠けても型が違っても投げない**（`TrunkState` と同じ）。ただし `stuck` の無い応答は
// 形が違うものとして投げる（空のトランクと混ぜない）

/// わたしの乗車券（`PUT /user/trunk/settings` の `ticket`・人のトランクの中に出す1枚）。
/// 字の上限はサーバーの `parseTicket` と同じ（**越えたら 400** なので、送る前に収める・`TrunkTicket.mine`）
struct TrunkTicket: Codable, Equatable, Hashable {
    /// 本人の公開写真の id
    let photoId: String
    /// 裏に書くひとこと（20字・80バイトまで）
    let note: String
    /// 区間の「発」に自分で書いた字（6字・24バイトまで・空なら居住地か「どこか」）
    let origin: String
    /// 区間の「着」に自分で書いた字（空なら「旅先」）
    let destination: String
    /// 券面の電波の番号（0 はマルス券・人の口は Pro でない人のぶんを 0 にして返す）
    let face: Int
    /// 「発」に居住地を出すか
    let showsFrom: Bool

    init(photoId: String, note: String = "", origin: String = "", destination: String = "", face: Int = 0,
         showsFrom: Bool = true) {
        self.photoId = photoId
        self.note = note
        self.origin = origin
        self.destination = destination
        self.face = min(255, max(0, face))
        self.showsFrom = showsFrom
    }

    /// サーバーの字の上限（`TICKET_NOTE_MAX` など。字は**コードポイント**で数える）
    static let noteChars = 20
    static let noteBytes = 80
    static let labelChars = 6
    static let labelBytes = 24

    private enum CodingKeys: String, CodingKey { case photoId, note, origin, destination, face, showsFrom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let photoId = (try? c.decodeIfPresent(String.self, forKey: .photoId)) ?? nil,
              PassExchange.isValidPhotoId(photoId) else {
            throw DecodingError.dataCorruptedError(forKey: .photoId, in: c, debugDescription: "乗車券の写真の id が読めない")
        }
        func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        self.init(photoId: photoId, note: text(.note), origin: text(.origin), destination: text(.destination),
                  face: LenientInt.read(c, .face) ?? 0,
                  showsFrom: ((try? c.decodeIfPresent(Bool.self, forKey: .showsFrom)) ?? nil) ?? true)
    }

    /// 端末の中の「わたしの乗車券」（すれちがいの設定）から、サーバーに置く1枚を作る。写真を選んでいなければ nil。
    /// 字は端末の決まりで整え（`PassExchange.cleanNote`・`cleanLabel`・連絡先の形は載せない）、
    /// サーバーの上限（コードポイントの数とバイト数）に**字の途中で切らずに**収める
    static func mine(_ settings: PassSettings) -> TrunkTicket? {
        guard let id = settings.cardPhotoId, PassExchange.isValidPhotoId(id) else { return nil }
        let rawNote = PassExchange.cleanNote(settings.note)
        let note = PassExchange.containsContact(rawNote) ? "" : rawNote
        return TrunkTicket(photoId: id,
                           note: fit(note, chars: noteChars, bytes: noteBytes),
                           origin: fit(PassExchange.cleanLabel(settings.originLabel ?? ""), chars: labelChars, bytes: labelBytes),
                           destination: fit(PassExchange.cleanLabel(settings.destinationLabel ?? ""),
                                            chars: labelChars, bytes: labelBytes),
                           face: Int(settings.faceStyle ?? 0),
                           showsFrom: settings.showsFrom)
    }

    /// 字（書記素）の切れ目で、コードポイントの数とバイト数の両方に収める
    static func fit(_ text: String, chars: Int, bytes: Int) -> String {
        var out = ""
        var scalars = 0
        var size = 0
        for ch in text {
            let s = ch.unicodeScalars.count, b = String(ch).utf8.count
            guard scalars + s <= chars, size + b <= bytes else { break }
            out.append(ch)
            scalars += s
            size += b
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// 区間の「発」の選び方（自分で書いた字 → 居住地 → 出さない）
    var originChoice: PassSettings.Origin {
        if !origin.isEmpty { return .custom }
        return showsFrom ? .home : .hidden
    }
}

/// 人のトランク（`GET /users/{uid}/trunk`）
struct TheirTrunk: Decodable, Equatable {
    let userId: String
    /// 見せている型（Pro をやめた人の Pro の型は来ない）
    let model: TrunkModel
    /// 貼ったラベル（新しい順）。id は返答の中だけの番号
    let stuck: [TrunkLabel]
    /// 付けた部品（台帳に無い・場所の合わない id は落とす）
    let equipped: TrunkEquipped
    /// 古び方に使う公開の投稿の数（控えが無ければ nil → 新しいトランク）
    let posts: Int?
    /// ラベル → その土地で撮った写真を引く手がかり（`where.location`）。地名の無いラベルは入らない
    let places: [String: String]
    /// メダル（公開プロフィールと同じ整え方）
    let badges: BadgeSet
    /// 会員証（サポーター番号を持つ人だけ。番号・始めた年月は来ない）
    let card: Card?
    /// わたしの乗車券（置いた写真が今も公開のときだけ）
    let ticket: TrunkTicket?

    struct Card: Equatable {
        /// 今 Pro か
        let pro: Bool
    }

    init(userId: String, model: TrunkModel, stuck: [TrunkLabel], equipped: TrunkEquipped = .none, posts: Int? = nil,
         places: [String: String] = [:], badges: BadgeSet = BadgeSet(), card: Card? = nil, ticket: TrunkTicket? = nil) {
        self.userId = userId
        self.model = model
        self.stuck = stuck
        self.equipped = equipped
        self.posts = posts
        self.places = places
        self.badges = badges
        self.card = card
        self.ticket = ticket
    }

    /// 古び方に渡す投稿の数
    var agingPosts: Int { posts ?? 0 }

    /// 内ポケットに会員証を入れるか。**自分のトランクと同じ決まり**（Pro で、サポーター証があるとき・
    /// `TrunkInsideContents.showsCard`）——画面ごとに出し分けを割らない
    var showsCard: Bool { card?.pro == true }

    /// ラベルの写真を引く土地の名前（地名の無いラベルは nil）
    func place(of label: TrunkLabel) -> String? { places[label.id] }

    private enum CodingKeys: String, CodingKey { case userId, model, stuck, equipped, posts, inside }
    private enum InsideKeys: String, CodingKey { case badges, card, ticket }
    private enum CardKeys: String, CodingKey { case pro }

    /// ラベル1枚（`TrunkLabel` の読み方そのままに、`where` を添える）
    private struct Row: Decodable {
        let label: TrunkLabel
        let location: String?

        private enum Keys: String, CodingKey { case `where` }
        private enum WhereKeys: String, CodingKey { case location }

        init(from decoder: Decoder) throws {
            label = try TrunkLabel(from: decoder)
            let c = try decoder.container(keyedBy: Keys.self)
            let w = try? c.nestedContainer(keyedBy: WhereKeys.self, forKey: .where)
            let raw = w.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .location)) ?? nil }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // 地名の空のラベルに手がかりだけ来ても使わない（地名なしの形に揃える）
            location = (raw?.isEmpty == false && !label.place.name.isEmpty) ? raw : nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.stuck) else {
            throw DecodingError.keyNotFound(CodingKeys.stuck, .init(codingPath: c.codingPath,
                                                                    debugDescription: "人のトランクの形ではない"))
        }
        let rows = ((try? c.decodeIfPresent([Lenient<Row>].self, forKey: .stuck)) ?? nil)?.compactMap(\.value) ?? []
        // 同じ id が2枚来たら後ろを落とす（選ぶ・並べる見分けが割れないように）
        var seen = Set<String>()
        let unique = rows.filter { seen.insert($0.label.id).inserted }
        var places: [String: String] = [:]
        for row in unique { if let location = row.location { places[row.label.id] = location } }
        let modelText = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil
        let inside = try? c.nestedContainer(keyedBy: InsideKeys.self, forKey: .inside)
        let badges = inside.flatMap { (try? $0.decodeIfPresent(BadgeSet.self, forKey: .badges)) ?? nil } ?? BadgeSet()
        var card: Card?
        if let inside, let k = try? inside.nestedContainer(keyedBy: CardKeys.self, forKey: .card) {
            card = Card(pro: ((try? k.decodeIfPresent(Bool.self, forKey: .pro)) ?? nil) ?? false)
        }
        let ticket = inside.flatMap { (try? $0.decodeIfPresent(Lenient<TrunkTicket>.self, forKey: .ticket))??.value }
        let rawEquipped = (try? c.decodeIfPresent(Lenient<TrunkEquipped>.self, forKey: .equipped))??.value ?? .none
        self.init(userId: ((try? c.decodeIfPresent(String.self, forKey: .userId)) ?? nil) ?? "",
                  model: modelText.flatMap(TrunkModel.init(rawValue:)) ?? .leather,
                  stuck: unique.map(\.label),
                  // 人の部品箱は来ないので、台帳と場所だけで確かめる
                  equipped: rawEquipped.sanitized(owned: nil),
                  posts: LenientInt.read(c, .posts).map { max(0, $0) },
                  places: places, badges: badges, card: card, ticket: ticket)
    }
}
