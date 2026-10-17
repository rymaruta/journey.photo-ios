import Foundation

// 旅のトランクの画面の言葉と数（モック Main・Pocket・Reroll・Models・PaidTrunks・2026-10-17）。
// SwiftUI を読まない（Linux でテストする）。

enum TrunkText {

    // MARK: 手持ちの上限

    /// 「28 / 30」
    static func pocketCounter(count: Int, limit: Int) -> String { "\(count) / \(max(1, limit))" }

    /// 棒の伸び（0〜1）。上限を越えていても（Pro をやめた）1 で止める
    static func pocketFraction(count: Int, limit: Int) -> Double {
        min(1, max(0, Double(count) / Double(max(1, limit))))
    }

    static func isFull(count: Int, limit: Int) -> Bool { count >= max(1, limit) }

    /// 「あと2枚」・いっぱいなら「いっぱいです」
    static func remaining(count: Int, limit: Int) -> String {
        let left = max(1, limit) - count
        return left > 0 ? L("あと\(left)枚", "\(left) left") : L("いっぱいです", "Full")
    }

    /// 手持ちの札の説明（モック Pocket）
    static var pocketNote: String {
        L("いっぱいの間は、投稿してもラベルは届きません。貼るか削除すると、また受け取れます。トランクに貼ったラベルは数えません。",
          "While it\u{2019}s full, posting won\u{2019}t bring new labels. Stick or delete one to receive again. Labels on your trunk don\u{2019}t count.")
    }

    static var proPocketLink: String {
        L("Pro なら \(TrunkState.proLimit) 枚まで持てます", "With Pro you can hold \(TrunkState.proLimit)")
    }

    /// 投稿が上がったのに、手持ちがいっぱいでラベルが届かなかった（`labelSkipped: "full"`）ときの一言
    static var fullNotice: String {
        L("手持ちのラベルがいっぱいで、今回は届きませんでした。マイページの「旅のトランク」で貼るか削除すると、また届きます。",
          "Your label pocket is full, so no label this time. Stick or delete one in Travel trunk on My Page to receive again.")
    }

    /// トランクの行の大きさが上限に近く、ラベルを受け取れなかった（`labelSkipped: "storage"`）ときの一言
    static var storageNotice: String {
        L("トランクの容量が上限に近いため、今回のラベルは受け取れませんでした。手持ちのラベルを削除すると、また受け取れます。",
          "Your trunk is nearly at its storage limit, so this label couldn\u{2019}t be received. Delete some labels in your pocket to receive again.")
    }

    // MARK: 作り直し

    /// 「あと 2 回」
    static func rerollsLeft(_ n: Int) -> String { L("あと \(max(0, n)) 回", "\(max(0, n)) left") }

    static var rerollNote: String {
        L("1回の作り直しで候補が3つ出ます。いまの図柄を選べば、そのままにできます。",
          "Each redo offers three designs. Pick the current one to keep it as it is.")
    }

    static var rerollLead: String {
        L("土地と季節はそのまま、図柄だけを作り直します。形・色・絵が変わります。",
          "The place and season stay; only the design is redone. The shape, colors and picture change.")
    }

    /// 作り直しの断り（サーバーの `code`）を画面の言葉に
    static func refusal(code: String?, fallback: String) -> String {
        switch code {
        case "proOnly": return L("Pro の機能です", "This is a Pro feature")
        case "noRerollsLeft": return L("今月の作り直しは使い切りました。来月また3回使えます。",
                                       "You\u{2019}ve used this month\u{2019}s redos. You get three more next month.")
        case "pendingReroll": return L("ほかのラベルの作り直しが選びかけです。先にそちらを選んでください。",
                                       "Another label\u{2019}s redo is waiting. Choose a design there first.")
        case "notFound": return L("ラベルが見つかりませんでした。読み直してください。", "That label wasn\u{2019}t found. Reload and try again.")
        case "full": return L("トランクがいっぱいです", "Your trunk is full")
        case "noPending": return L("作り直しの候補がありません。もう一度作り直してください。",
                                   "There are no designs to choose from. Redo it again.")
        case "busy": return L("混み合っています。もう一度お試しください", "It\u{2019}s busy. Please try again.")
        default: return fallback
        }
    }

    // MARK: 数え札（モック Main の3つ）

    struct Stats: Equatable {
        /// 貼ったラベル
        let stuck: Int
        /// か国・地域（貼ったラベルの国の数。国の分からない国内のラベルは日本に数える）
        let countries: Int
        /// いちばん古いラベルの年（無ければ nil）
        let sinceYear: Int?
    }

    static func stats(_ state: TrunkState) -> Stats {
        var countries = Set<String>()
        for label in state.stuck {
            if let c = label.place.country { countries.insert(c) }
            else if !label.place.name.isEmpty { countries.insert("日本") }
        }
        let years = (state.stuck + state.pocket).compactMap { $0.day?.year }
        return Stats(stuck: state.stuck.count, countries: countries.count, sinceYear: years.min())
    }

    // MARK: 型

    struct ModelInfo: Equatable {
        let name: String
        let material: String
        let aging: String
        /// Pro の型の説明（PaidTrunks）。無料の型は nil
        let concept: String?
        let hardware: String?
        let only: String?
    }

    static func info(_ model: TrunkModel) -> ModelInfo {
        switch model {
        case .leather:
            return ModelInfo(name: L("革の旅行鞄", "Leather case"),
                             material: L("牛革 · 縫い目の縁 · 真鍮の金具", "Cowhide · stitched edges · brass fittings"),
                             aging: L("革に艶が出て飴色へ", "The leather gains a shine and turns amber"),
                             concept: nil, hardware: nil, only: nil)
        case .canvas:
            return ModelInfo(name: L("帆布の鞄", "Canvas bag"),
                             material: L("縞の帆布 · 厚革の縁と角", "Striped canvas · thick leather edges and corners"),
                             aging: L("布が日に焼け、しみが増える", "The cloth sun-fades and gathers stains"),
                             concept: nil, hardware: nil, only: nil)
        case .aluminum:
            return ModelInfo(name: L("アルミのケース", "Aluminum case"),
                             material: L("波板のアルミ · 打ち出しの角", "Ribbed aluminum · pressed corners"),
                             aging: L("細かな擦り傷が光る", "Fine scratches catch the light"),
                             concept: nil, hardware: nil, only: nil)
        case .steamer:
            return ModelInfo(name: L("船旅の衣装箱", "Steamer trunk"),
                             material: L("緑の帆布張り · 木の桟 · 真鍮の鋲", "Green canvas · wooden slats · brass studs"),
                             aging: L("木の桟が明るく褪せる", "The wooden slats fade lighter"),
                             concept: nil, hardware: nil, only: nil)
        case .urushi:
            return ModelInfo(name: L("漆の旅箱", "Lacquer travel box"),
                             material: L("木地 · 黒漆に朱の下塗り", "Wood · black lacquer over a vermilion base"),
                             aging: L("使うほど黒が透けて、下の朱がほんのり出てくる",
                                      "With use the black thins and the vermilion beneath shows through"),
                             concept: L("木地に漆を何度も塗り重ね、金で波を描いた旅の箱。紐は正絹の組紐。",
                                        "A travel box of many lacquer coats with golden waves. Tied with braided silk."),
                             hardware: L("金の角金具（彫り）· 組紐の留め", "Engraved gold corners · braided-cord ties"),
                             only: L("金蒔絵の波と家紋のような丸紋", "Maki-e waves and a crest-like roundel"))
        case .kori:
            return ModelInfo(name: L("柳行李", "Willow kori"),
                             material: L("柳の編み · 籐の縁", "Woven willow · rattan rim"),
                             aging: L("編み目が飴色に焼けて、縄がほつれる", "The weave tans to amber and the rope frays"),
                             concept: L("柳の枝を編んだ、昔の旅の行李。軽くて、編み目に旅の日が染みていく。",
                                        "An old woven-willow travel basket. Light, and every trip soaks into the weave."),
                             hardware: L("革の角当て · 麻の縄", "Leather corner guards · hemp rope"),
                             only: L("縄の結び目が旅の数だけ増える", "A knot in the rope for every trip"))
        case .sleeper:
            return ModelInfo(name: L("寝台列車の鞄", "Sleeper-train case"),
                             material: L("牛革（ボルドー）· 縫い目の縁", "Bordeaux cowhide · stitched edges"),
                             aging: L("赤が深まり、名札の文字が擦れて光る", "The red deepens and the name plate wears to a shine"),
                             concept: L("長い夜行列車の旅のための、深い赤の革鞄。真鍮の名札に持ち主の名前を刻む。",
                                        "A deep-red leather case for long night trains, with your name on a brass plate."),
                             hardware: L("真鍮の上下の帯 · 名札 · 錠前", "Brass bands · name plate · lock"),
                             only: L("持ち主の名前を刻んだ真鍮の名札", "A brass plate engraved with your name"))
        case .clipper:
            return ModelInfo(name: L("飛行艇のアルミ", "Flying-boat aluminum"),
                             material: L("磨いたアルミ · 鋲留めの継ぎ目", "Polished aluminum · riveted seams"),
                             aging: L("擦り傷が増えて、光り方が柔らかくなる", "Scratches gather and the shine softens"),
                             concept: L("海を渡った飛行艇の時代の、磨いたアルミの鞄。鋲の列と継ぎ目まで機体と同じ作り。",
                                        "A polished aluminum case from the flying-boat era, riveted like the airframe."),
                             hardware: L("クロームの角 · 名札 · 革の持ち手", "Chrome corners · name plate · leather handle"),
                             only: L("飛んだ区間を刻める機体の名札", "An airframe plate for the routes you flew"))
        case .captain:
            return ModelInfo(name: L("船長の箱", "Captain\u{2019}s chest"),
                             material: L("チークの板張り", "Teak planks"),
                             aging: L("板が明るく褪せ、真鍮が青くくすむ", "The planks bleach and the brass turns verdigris"),
                             concept: L("チークの板を真鍮の帯で締めた、船乗りの道具箱。ふたに羅針盤を嵌めてある。",
                                        "A sailor\u{2019}s chest of teak bound in brass, with a compass set in the lid."),
                             hardware: L("真鍮の帯と大きな角 · 鋲", "Brass bands, large corners · studs"),
                             only: L("ふたの羅針盤（行きたい場所の方角を指す）", "A compass in the lid (points to your saved places)"))
        case .starchart:
            return ModelInfo(name: L("星図の鞄", "Star-chart case"),
                             material: L("牛革（紺）· 金の押し線", "Navy cowhide · gold tooling"),
                             aging: L("旅の場所が増えるたびに、星と線が増える", "More stars and lines with every new place"),
                             concept: L("紺の革に金の押し線で星座を描いた鞄。星は、自分が写真を撮った場所の並び。",
                                        "Navy leather tooled in gold with a constellation made of the places you photographed."),
                             hardware: L("真鍮の角 · 金の尾錠", "Brass corners · gold buckles"),
                             only: L("自分の撮影地から描かれる星座", "A constellation drawn from your photo spots"))
        }
    }

    /// 型の古び方の短い説明（モック MaterialAging）
    static func materialAging(_ model: TrunkModel) -> String {
        switch model {
        case .leather: return L("深い茶色から飴色へ。金具がくすむ", "Deep brown to amber. The fittings dull")
        case .canvas: return L("布が日に焼けて明るくなり、しみが増える", "The cloth sun-fades lighter and gathers stains")
        case .aluminum: return L("細かな擦り傷が増え、光り方が柔らかくなる", "Fine scratches gather and the shine softens")
        case .steamer: return L("木の桟が明るく褪せ、帆布が擦れる", "The slats fade lighter and the canvas wears")
        case .urushi: return L("黒が透けて、角から下塗りの朱が出てくる", "The black thins and vermilion shows at the corners")
        case .kori: return L("編み目が飴色に焼け、縁が濃くなる", "The weave tans to amber and the rim darkens")
        case .sleeper: return L("赤が深まり、艶が増していく", "The red deepens and the shine grows")
        case .clipper: return L("擦り傷が重なり、鏡のような光が鈍る", "Scratches layer up and the mirror shine dulls")
        case .captain: return L("板が褪せ、真鍮の角が青緑にくすむ", "The planks fade and the brass corners turn blue-green")
        case .starchart: return L("紺が柔らかくなり、金の線が浮かぶ", "The navy softens and the gold lines stand out")
        }
    }

    /// 眉ラベル（モック Main の「MY TRUNK · 革の旅行鞄」）
    static func eyebrow(_ model: TrunkModel) -> String { "MY TRUNK · \(info(model).name)" }

    /// トランクの読み上げ（モック Trunk の `ariaLabel`）
    static func accessibilityLabel(model: TrunkModel, labels: Int, tags: Int) -> String {
        var text = L("\(info(model).name)。ラベル\(labels)枚", "\(info(model).name). \(labels) labels")
        if tags > 0 { text += L("、手荷物タグ\(tags)枚", ", \(tags) baggage tags") }
        return text
    }
}

// MARK: - 端末の中だけの移り変わり（画面写真の見本・`PreviewSession.trunkSample`）

/// サーバーと同じ決まりで、トランクの状態を手元で動かす（Debug の見本だけが使う。本番はサーバーの応答を映す）
enum TrunkLocal {

    static func stick(_ s: TrunkState, id: String) -> TrunkState {
        guard let label = s.pocket.first(where: { $0.id == id }) else { return s }
        return copy(s, pocket: s.pocket.filter { $0.id != id }, stuck: [label] + s.stuck,
                    pending: s.pendingReroll?.labelId == id ? .some(nil) : nil)
    }

    static func remove(_ s: TrunkState, id: String) -> TrunkState {
        copy(s, pocket: s.pocket.filter { $0.id != id },
             pending: s.pendingReroll?.labelId == id ? .some(nil) : nil)
    }

    /// 作り直し（候補の種3つ）。Pro で、回数が残っているときだけ
    static func reroll(_ s: TrunkState, id: String, seeds: [Int]) -> TrunkState {
        guard s.isPro, s.rerollsLeft > 0, s.pocket.contains(where: { $0.id == id }) else { return s }
        if s.pendingReroll?.labelId == id { return s }
        return copy(s, rerollsLeft: s.rerollsLeft - 1, pending: .some(TrunkPendingReroll(labelId: id, seeds: seeds)))
    }

    static func choose(_ s: TrunkState, id: String, seed: Int) -> TrunkState {
        guard let pending = s.pendingReroll, pending.labelId == id else { return s }
        let pocket = s.pocket.map { $0.id == id && (pending.seeds.contains(seed) || $0.seed == seed) ? $0.withSeed(seed) : $0 }
        return copy(s, pocket: pocket, pending: .some(nil))
    }

    static func setModel(_ s: TrunkState, _ model: TrunkModel) -> TrunkState {
        guard !model.isPro || s.isPro else { return s }
        return TrunkState(model: model, effectiveModel: model, pocket: s.pocket, stuck: s.stuck, limit: s.limit,
                          isPro: s.isPro, rerollsLeft: s.rerollsLeft, pendingReroll: s.pendingReroll,
                          posts: s.posts, receiveLabels: s.receiveLabels)
    }

    static func setReceive(_ s: TrunkState, _ on: Bool) -> TrunkState {
        TrunkState(model: s.model, effectiveModel: s.effectiveModel, pocket: s.pocket, stuck: s.stuck, limit: s.limit,
                   isPro: s.isPro, rerollsLeft: s.rerollsLeft, pendingReroll: s.pendingReroll,
                   posts: s.posts, receiveLabels: on)
    }

    /// `pending` は「触らない（nil）」「外す（.some(nil)）」「置く（.some(値)）」の3つ
    private static func copy(_ s: TrunkState, pocket: [TrunkLabel]? = nil, stuck: [TrunkLabel]? = nil,
                             rerollsLeft: Int? = nil, pending: TrunkPendingReroll?? = nil) -> TrunkState {
        TrunkState(model: s.model, effectiveModel: s.effectiveModel, pocket: pocket ?? s.pocket, stuck: stuck ?? s.stuck,
                   limit: s.limit, isPro: s.isPro, rerollsLeft: rerollsLeft ?? s.rerollsLeft,
                   pendingReroll: pending == nil ? s.pendingReroll : pending!,
                   posts: s.posts, receiveLabels: s.receiveLabels)
    }
}

/// 画面写真の見本（Debug の `-JPPreviewTrunk`）。**サーバーには何も送らない**
enum TrunkSample {

    private static func label(_ id: String, _ kind: TrunkLabel.Kind, _ name: String, latin: String? = nil,
                              country: String? = nil, season: TrunkLabel.Season? = nil,
                              timeslot: TrunkLabel.Timeslot? = nil, milestone: TrunkLabel.Milestone? = nil,
                              seed: Int, at: String, foil: Bool = false) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: kind, place: .init(name: name, latin: latin, country: country),
                   season: season, timeslot: timeslot, milestone: milestone, seed: seed, at: at, foil: foil)
    }

    /// 貼ったラベル（新しい順）
    static let stuck: [TrunkLabel] = [
        label("s-kyoto", .season, "京都", latin: "Kyoto", country: "日本", season: .spring, seed: 41_207, at: "2026-04-03T09:00:00Z"),
        label("s-helsinki", .timeslot, "ヘルシンキ", latin: "Helsinki", country: "フィンランド", season: .summer,
              timeslot: .night, seed: 77_031, at: "2025-06-20T21:00:00Z"),
        label("s-takaya", .season, "高屋神社", latin: "Takaya", country: "日本", season: .autumn, seed: 9_120,
              at: "2024-10-30T06:00:00Z"),
        label("s-paris", .place, "パリ", latin: "Paris", country: "フランス", seed: 120_004, at: "2024-02-11T10:00:00Z"),
        label("s-sapporo", .season, "札幌", latin: "Sapporo", country: "日本", season: .winter, seed: 55_555,
              at: "2023-02-08T10:00:00Z"),
        label("s-fuji", .timeslot, "山中湖", latin: "Mt. Fuji", country: "日本", timeslot: .dawn, seed: 3_141,
              at: "2022-11-03T05:12:00Z"),
        label("s-barcelona", .milestone, "バルセロナ", latin: "Barcelona", country: "スペイン", milestone: .firstCountry,
              seed: 8_808, at: "2021-08-02T12:00:00Z"),
        label("s-santorini", .timeslot, "サントリーニ", latin: "Santorini", country: "ギリシャ", timeslot: .dusk,
              seed: 60_060, at: "2020-07-14T18:40:00Z"),
        label("s-first", .milestone, "函館", latin: "Hakodate", country: "日本", milestone: .first, seed: 1_001,
              at: "2019-02-08T21:30:00Z"),
    ]

    /// 手持ち（新しい順）
    static let pocket: [TrunkLabel] = [
        label("p-sapporo", .season, "札幌", latin: "Sapporo", country: "日本", season: .winter, seed: 31_337,
              at: "2026-01-18T10:00:00Z"),
        label("p-naoshima", .place, "直島", latin: "Naoshima", country: "日本", seed: 4_242, at: "2025-09-01T10:00:00Z"),
        label("p-rovaniemi", .timeslot, "ロヴァニエミ", latin: "Rovaniemi", country: "フィンランド", timeslot: .night,
              seed: 99_001, at: "2025-12-20T22:00:00Z", foil: true),
        label("p-kanazawa", .season, "金沢", latin: "Kanazawa", country: "日本", season: .autumn, seed: 12_012,
              at: "2025-11-11T10:00:00Z"),
        label("p-ten", .milestone, "", milestone: .posts10, seed: 10_010, at: "2025-05-05T10:00:00Z"),
        label("p-naha", .season, "那覇", latin: "Naha", country: "日本", season: .summer, seed: 70_707, at: "2025-07-07T10:00:00Z"),
    ]

    /// 見本の状態。`empty` は届いたラベルが1枚も無い人（空の状態の絵）
    static func state(isPro: Bool, empty: Bool = false) -> TrunkState {
        TrunkState(model: .leather, effectiveModel: .leather,
                   pocket: empty ? [] : pocket, stuck: empty ? [] : stuck,
                   limit: isPro ? TrunkState.proLimit : TrunkState.freeLimit, isPro: isPro,
                   rerollsLeft: isPro ? 2 : 0, pendingReroll: nil,
                   posts: empty ? 0 : 42, receiveLabels: true)
    }

    /// 届いた画面の見本の1枚（モック LabelArrived の「京都 · 桜」）
    static let arrived = label("a-kyoto", .season, "京都", latin: "Kyoto", country: "日本", season: .spring, seed: 41_207,
                               at: "2026-04-03T09:00:00Z")

    /// 作り直しの見本の候補の種
    static let rerollSeeds = [20_001, 20_002, 20_003]
}
