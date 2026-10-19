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

    /// 作り直しの画面の段（2026-10-17 判断: **開いただけでは回数を使わない**。「作り直す」を押して初めて使う）
    enum RerollStep: Equatable {
        /// まだ作り直していない。押すと1回使って候補3つ（`left` は今月の残り）
        case start(left: Int)
        /// 候補が出ている（選ぶまで残る・回数はもう使った）
        case choosing([Int])
        /// 今月の回数を使い切った
        case noneLeft
        /// Pro でない
        case notPro
    }

    static func rerollStep(_ state: TrunkState?, labelId: String) -> RerollStep {
        guard let state else { return .start(left: 0) }
        if let pending = state.pendingReroll, pending.labelId == labelId { return .choosing(Array(pending.seeds.prefix(3))) }
        guard state.isPro else { return .notPro }
        return state.rerollsLeft > 0 ? .start(left: state.rerollsLeft) : .noneLeft
    }

    /// 押す前の注記（モック RerollStart）
    static var rerollStartNote: String {
        L("押すと1回使い、候補が3つ出ます。開いただけでは回数は減りません。毎月3回・繰り越しなし。",
          "Tapping uses one redo and shows three designs. Just opening this doesn\u{2019}t use one. 3 a month, no carry-over.")
    }

    /// 「作り直す · 今月あと 2 回」
    static func rerollStartTitle(left: Int) -> String {
        L("作り直す · 今月あと \(max(0, left)) 回", "Redo · \(max(0, left)) left this month")
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
        case "storage": return L("トランクの容量が上限に近いため、受け取れませんでした。手持ちのラベルを削除すると、また受け取れます。",
                                 "Your trunk is nearly at its storage limit, so it couldn\u{2019}t be received. Delete some labels in your pocket to receive again.")
        case "noPending": return L("作り直しの候補がありません。もう一度作り直してください。",
                                   "There are no designs to choose from. Redo it again.")
        case "busy": return L("混み合っています。もう一度お試しください", "It\u{2019}s busy. Please try again.")
        // 次の版（2026-10-17）: 置き場・はがす・カプセルの機械・部品
        case "badPlace": return L("その場所には貼れませんでした。トランクの上で離してください。",
                                  "Couldn\u{2019}t stick it there. Let go over the trunk.")
        case "notStuck": return L("まだ貼っていないラベルです。読み直してください。", "That label isn\u{2019}t stuck yet. Reload and try again.")
        case "noCoins": return L("硬貨がありません。公開の投稿1件で1枚もらえます。", "No coins. You get one for each public post.")
        case "notEnoughFragments": return L("かけらが足りません。5つで1つ交換できます。", "Not enough fragments. Five make one exchange.")
        case "owned": return L("もう持っている部品です。", "You already have that part.")
        case "notOwned": return L("持っていない部品は付けられません。読み直してください。", "You can\u{2019}t use a part you don\u{2019}t have. Reload and try again.")
        case "badPart", "badKind": return L("その部品は付けられませんでした。読み直してください。", "That part couldn\u{2019}t be used. Reload and try again.")
        default: return fallback
        }
    }

    // MARK: 数え札（モック Main の3つ）

    struct Stats: Equatable {
        /// 貼ったラベル
        let stuck: Int
        /// か国・地域（貼ったラベルの国の数。**国名が分かるものだけ**数える・2026-10-17 の読み直し）
        let countries: Int
        /// いちばん古いラベルの年（無ければ nil）
        let sinceYear: Int?
    }

    static func stats(_ state: TrunkState) -> Stats {
        var countries = Set<String>()
        for label in state.stuck {
            if let c = label.place.country { countries.insert(c) }
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

    /// トランクの読み上げ（モック Trunk の `ariaLabel`）。付けている部品があれば名前を添える
    static func accessibilityLabel(model: TrunkModel, labels: Int, tags: Int, equipped: TrunkEquipped = .none) -> String {
        var text = L("\(info(model).name)。ラベル\(labels)枚", "\(info(model).name). \(labels) labels")
        if tags > 0 { text += L("、手荷物タグ\(tags)枚", ", \(tags) baggage tags") }
        let names = equipped.all.compactMap { TrunkPartCatalog.part($0) }.filter { $0.kind != .lining }.map(\.name)
        if !names.isEmpty { text += L("。付けている部品: \(names.joined(separator: "、"))", ". Parts: \(names.joined(separator: ", "))") }
        return text
    }

    /// 「はがして手持ちに戻す」が手持ちの上限で断られたとき
    /// 「完了」で置き場を送れなかった（混んでいた・圏外）
    static let placeNotSaved = L("置き場を保存できませんでした。電波のあるところで、もう一度「完了」を押してください。",
                                 "Couldn\u{2019}t save where your labels are. Try Done again where you have a signal.")

    /// おまかせで並べる空きが無い
    static let noFreeSlot = L("おまかせの置き場が埋まっています。ラベルを押さえて、好きな所へ運んで貼れます。",
                              "The suggested spots are full. Hold a label and carry it anywhere on the trunk.")
    /// 手持ちが空
    static let noPocketLabels = L("手持ちのラベルがありません。写真を投稿すると届きます。",
                                  "No labels in your pocket. Post a photo to get one.")

    /// 硬貨だけが届いた一言（ラベルは受け取らない設定・2026-10-17 次の版）
    static func coinNotice(_ n: Int) -> String {
        L("硬貨 +\(n) · カプセルの機械で部品と換えられます", "+\(n) coin · Use it at the capsule machine for a trunk part")
    }

    /// ラベルが届かなかった一言に添える硬貨（手持ちがいっぱいでも硬貨は届く）
    static func coinAlsoNotice(_ n: Int) -> String {
        L("硬貨は +\(n) 届いています。", "You still got +\(n) coin.")
    }

    /// 届いた画面の硬貨の札（「硬貨 +1」）
    static func coinChip(_ n: Int) -> String { L("硬貨 +\(n)", "+\(n) coin") }

    static let unstickFull = L("手持ちがいっぱいのため、はがせません。手持ちのラベルを貼るか削除してください。",
                               "Your pocket is full, so it can\u{2019}t be peeled off. Stick or delete a label in your pocket first.")
}

// MARK: - 端末の中だけの移り変わり（画面写真の見本・`PreviewSession.trunkSample`）

/// サーバーと同じ決まりで、トランクの状態を手元で動かす（Debug の見本だけが使う。本番はサーバーの応答を映す）
enum TrunkLocal {

    /// 貼る。置き場があればそれ（番号は付けない）、無ければ添えたおまかせの置き場の番号（サーバーの `stickMutation`）
    static func stick(_ s: TrunkState, id: String, pos: TrunkPos? = nil, slot: Int? = nil) -> TrunkState {
        guard let label = s.pocket.first(where: { $0.id == id }) else { return s }
        let stuck = pos.map { label.withPos(TrunkPlacement.clamp($0)) } ?? label.withSlot(slot)
        return s.copy(pocket: s.pocket.filter { $0.id != id }, stuck: [stuck] + s.stuck,
                      pendingReroll: s.pendingReroll?.labelId == id ? .some(nil) : nil)
    }

    static func place(_ s: TrunkState, id: String, pos: TrunkPos) -> TrunkState {
        guard s.stuck.contains(where: { $0.id == id }) else { return s }
        return s.copy(stuck: s.stuck.map { $0.id == id ? $0.withPos(TrunkPlacement.clamp(pos)) : $0 })
    }

    /// はがす（手持ちのいちばん上へ・置き場と番号は消す）。手持ちが上限なら変えない（サーバーは 409 `full`）。
    /// `slots` はずれるラベルに添える番号（置き場の無いラベルだけに書く・サーバーの `unstickMutation`）
    static func unstick(_ s: TrunkState, id: String, slots: [String: Int] = [:]) -> TrunkState {
        guard let label = s.stuck.first(where: { $0.id == id }), s.pocket.count < s.limit else { return s }
        let rest = s.stuck.filter { $0.id != id }.map { l in
            l.pos == nil ? (slots[l.id].map { l.withSlot($0) } ?? l) : l
        }
        return s.copy(pocket: [label.withPos(nil)] + s.pocket, stuck: rest)
    }

    static func remove(_ s: TrunkState, id: String) -> TrunkState {
        s.copy(pocket: s.pocket.filter { $0.id != id },
               pendingReroll: s.pendingReroll?.labelId == id ? .some(nil) : nil)
    }

    /// 作り直し（候補の種3つ）。Pro で、回数が残っているときだけ
    static func reroll(_ s: TrunkState, id: String, seeds: [Int]) -> TrunkState {
        guard s.isPro, s.rerollsLeft > 0, s.pocket.contains(where: { $0.id == id }) else { return s }
        if s.pendingReroll?.labelId == id { return s }
        return s.copy(rerollsLeft: s.rerollsLeft - 1, pendingReroll: .some(TrunkPendingReroll(labelId: id, seeds: seeds)))
    }

    static func choose(_ s: TrunkState, id: String, seed: Int) -> TrunkState {
        guard let pending = s.pendingReroll, pending.labelId == id else { return s }
        let pocket = s.pocket.map { $0.id == id && (pending.seeds.contains(seed) || $0.seed == seed) ? $0.withSeed(seed) : $0 }
        return s.copy(pocket: pocket, pendingReroll: .some(nil))
    }

    static func setModel(_ s: TrunkState, _ model: TrunkModel) -> TrunkState {
        guard !model.isPro || s.isPro else { return s }
        return s.copy(model: model, effectiveModel: model)
    }

    static func setReceive(_ s: TrunkState, _ on: Bool) -> TrunkState {
        s.copy(receiveLabels: on)
    }

    /// カプセルの機械（見本）。硬貨が無ければ nil。出る部品は見本の並び（`TrunkSample.gachaOrder`）を回す
    static func gacha(_ s: TrunkState, draw: Int) -> TrunkGachaResult? {
        guard s.coins > 0, !TrunkSample.gachaOrder.isEmpty,
              let part = TrunkPartCatalog.part(TrunkSample.gachaOrder[draw % TrunkSample.gachaOrder.count]) else { return nil }
        let duplicate = s.parts.contains(part.id)
        return TrunkGachaResult(part: part, duplicate: duplicate, fragments: s.fragments + (duplicate ? 1 : 0), coins: s.coins - 1)
    }

    static func exchange(_ s: TrunkState, partId: String) -> TrunkState {
        guard TrunkPartCatalog.part(partId) != nil, !s.parts.contains(partId),
              s.fragments >= TrunkPartsBoxText.fragmentsPerExchange else { return s }
        return s.copy(parts: [partId] + s.parts, fragments: s.fragments - TrunkPartsBoxText.fragmentsPerExchange)
    }

    static func equip(_ s: TrunkState, _ equipped: TrunkEquipped) -> TrunkState {
        s.copy(equipped: equipped.sanitized(owned: s.ownedParts))
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

    /// 見本の持っている部品（モック PartsBox の錠前 5/12 ほか・付け替えの見本 Equip の鳥居と汽船のピン）
    static let parts: [String] = [
        "lock.1", "lock.2", "lock.3", "lock.5", "lock.8",
        "handle.1", "handle.2", "handle.7", "handle.6",
        "corner.2", "corner.4", "corner.12",
        "lining.1", "lining.7",
        "tag.1", "tag.4", "tag.9",
        "pin.1", "pin.7", "pin.2", "pin.5", "pin.9",
        "patch.1",
        "charm.1", "charm.4",
        "key.4",
    ]

    /// 見本の付けている部品（モック Equip の「古都」: 赤の組紐・金の唐草・ピン2つ・京都のワッペン・鳥居のチャーム・赤い札の鍵）
    static let equipped = TrunkEquipped(handle: "handle.7", corner: "corner.12", lock: "lock.2", lining: "lining.7",
                                        tag: "tag.4", charm: "charm.1", key: "key.4",
                                        pins: ["pin.1", "pin.7"], patches: ["patch.1"])

    /// 見本のカプセルの機械で出る順（めずらしい錠前「菊」→ まだ持っていない部品 → 持っている部品（かけら））
    static let gachaOrder = ["lock.2", "charm.12", "pin.1", "patch.6"]

    /// 見本の状態。`empty` は届いたラベルが1枚も無い人（空の状態の絵）。`coins` で硬貨の枚数を替える（画面写真の「硬貨がありません」）
    static func state(isPro: Bool, empty: Bool = false, coins: Int? = nil) -> TrunkState {
        TrunkState(model: .leather, effectiveModel: .leather,
                   pocket: empty ? [] : pocket, stuck: empty ? [] : stuck,
                   limit: isPro ? TrunkState.proLimit : TrunkState.freeLimit, isPro: isPro,
                   rerollsLeft: isPro ? 2 : 0, pendingReroll: nil,
                   posts: empty ? 0 : 42, receiveLabels: true,
                   coins: coins ?? (empty ? 0 : 2), parts: empty ? [] : parts, fragments: empty ? 0 : 3,
                   equipped: empty ? .none : equipped)
    }

    /// 届いた画面の見本の1枚（モック LabelArrived の「京都 · 桜」）
    static let arrived = label("a-kyoto", .season, "京都", latin: "Kyoto", country: "日本", season: .spring, seed: 41_207,
                               at: "2026-04-03T09:00:00Z")

    /// 作り直しの見本の候補の種
    static let rerollSeeds = [20_001, 20_002, 20_003]
}

/// 古び方の区切りの知らせを出した印（人ごとに端末へ・退会で消す `AccountLocalData`）
enum TrunkAgingNotice {
    static func key(_ userId: String) -> String { "trunk.agingSeen.\(userId)" }
}
