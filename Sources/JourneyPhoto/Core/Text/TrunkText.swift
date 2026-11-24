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

    // MARK: 作り直し（札 #706・2026-11-23 owner 承認: 全員・ラベルごとに3回・届いた画面のまま）

    /// 届いた画面の作り直しの段
    enum RedoStep: Equatable {
        /// 出さない（サーバーが対応していない・好きなデザインのラベル・手持ちに無い）
        case hidden
        /// まだ作り直せる（`left` は残りの回数）
        case ready(left: Int)
        /// 3回を使い切った（候補から選ぶだけ）
        case usedUp
    }

    static func redoStep(_ state: TrunkState?, label: TrunkLabel) -> RedoStep {
        guard let state, state.supportsLabelReroll, label.custom == nil,
              let current = state.pocket.first(where: { $0.id == label.id }) else { return .hidden }
        return current.rerollsLeft > 0 ? .ready(left: current.rerollsLeft) : .usedUp
    }

    /// 「作り直す　あと 3 回」（区切りは空白・中黒を使わない）
    static func redoTitle(left: Int, again: Bool = false) -> String {
        let n = max(0, left)
        return again ? L("もう一度作り直す\u{2002}あと \(n) 回", "Try again\u{2002}\(n) left")
                     : L("作り直す\u{2002}あと \(n) 回", "Redo\u{2002}\(n) left")
    }

    /// 読み上げ（「作り直す、あと 3 回」）
    static func redoAccessibility(left: Int) -> String {
        L("作り直す、あと \(max(0, left)) 回", "Redo, \(max(0, left)) left")
    }

    static var redoUsedUp: String {
        L("作り直しは3回までです。4つから選んで貼ってください", "You can redo up to 3 times. Pick one of the four to stick.")
    }

    static var redoOffline: String {
        L("電波が無いので作り直せません。貼るのは電波が戻ってから", "You\u{2019}re offline, so you can\u{2019}t redo now. Stick it once you\u{2019}re back online.")
    }

    static var redoFailed: String {
        L("作り直せませんでした。回数は減っていません", "Couldn\u{2019}t redo it. Your redos weren\u{2019}t used.")
    }

    /// 候補の札の下の字（「最初」「1回目」…）
    static func candidateCaption(_ index: Int) -> String {
        index == 0 ? L("最初", "First") : L("\(index)回目", "Redo \(index)")
    }

    /// 候補の札の読み上げ
    static func candidateAccessibility(_ index: Int) -> String {
        index == 0 ? L("最初の図柄", "First design") : L("\(index)回目の図柄", "Redo \(index) design")
    }

    /// 候補の列の下の一行（作る前: 何が起きるか。作ったあと: 押すと戻せること）
    static func candidatesHint(rerolls: Int) -> String {
        rerolls > 0 ? L("押すと、前の図柄に戻せます", "Tap one to go back to an earlier design")
                    : L("作り直すと、ここに候補が並びます", "Redo and your options line up here")
    }

    /// 空いている枠の読み上げ（まだ作っていない回）
    static func candidateEmptyAccessibility(_ index: Int) -> String {
        L("\(index)回目はまだ作っていません", "Redo \(index) not made yet")
    }

    // MARK: 好きなデザインで作る（札 #706。画面では「カスタム」と言わない）

    /// 進み具合の1行目
    static var customProgressTitle: String { L("好きなデザインで作れるまで", "Until you can make your own design") }

    /// 進み具合の2行目の数（「あと 2 回の投稿」）
    static func customPostsLeft(_ n: Int) -> String {
        L("あと \(max(1, n)) 回の投稿", "\(max(1, n)) more post\(max(1, n) == 1 ? "" : "s")")
    }

    /// 作れる回数があるとき（進み具合の代わり）
    static func customReady(tickets: Int) -> String {
        tickets > 1 ? L("好きなデザインで作れます（\(tickets) 回分）", "You can make your own design (\(tickets) left)")
                    : L("好きなデザインで作れます", "You can make your own design")
    }

    /// 進み具合の読み上げ
    static func customProgressAccessibility(_ p: TrunkCustomProgress) -> String {
        p.canMake
            ? customReady(tickets: p.tickets)
            : L("好きなデザインで作れるまで、あと \(p.postsLeft) 回の投稿", "\(p.postsLeft) more posts until you can make your own design")
    }

    static var customTitle: String { L("好きなデザインで作る", "Make your own design") }

    /// 届いた画面のお礼の一行（作れるようになった投稿）
    static var customThanks: String { L("今回は、好きなデザインで作れます", "This time, you can make your own design") }

    static var customKeepTitle: String { L("このまま貼る", "Stick as is") }

    static var customLaterNote: String { L("あとでも手持ちから作れます", "You can also make it later from your pocket") }

    /// 作る画面の眉ラベル（英字の刷り。画面の言語で変えない）
    static let customEyebrow = "YOUR DESIGN"

    static var customFixedNote: String { L("字は投稿の土地と季節のまま", "The words stay as the place and season of your post") }

    static var customFoilNote: String {
        L("箔押しのラベルは、色が箔のままです", "Gold-foil labels keep their foil colors")
    }

    static var customShapeTab: String { L("形", "Shape") }
    static var customPaletteTab: String { L("色", "Color") }
    static var customArtTab: String { L("絵", "Picture") }

    /// 作る画面の主ボタン（届いた画面から: 作って貼る・手持ちから: 作るだけ）
    static func customDoneTitle(sticks: Bool) -> String {
        sticks ? L("このデザインで貼る", "Stick with this design") : L("このデザインにする", "Use this design")
    }

    static var customShuffleTitle: String { L("おまかせで組み直す", "Shuffle") }

    static var customMade: String { L("好きなデザインで作りました", "Made your design") }

    /// 手持ちの帯のボタン
    static var customPocketTitle: String { L("好きなデザインで作る", "Make your design") }

    /// 形・色・絵の札の読み上げ（「形：切符」「絵：もみじ」）。番号では言わない（2026-11-23 確かめ役の指摘）
    static func customOptionAccessibility(tab: String, name: String) -> String { L("\(tab)：\(name)", "\(tab): \(name)") }

    /// 形の名前（`TrunkLabelDesign.customShapes` の並び）
    static func shapeName(_ shape: TrunkLabelShape) -> String {
        switch shape {
        case .oval: return L("楕円", "Oval")
        case .circle: return L("円", "Circle")
        case .rect: return L("四角", "Rectangle")
        case .ticket: return L("切符", "Ticket")
        case .shield: return L("盾", "Shield")
        case .diamond: return L("ひし形", "Diamond")
        case .hexagon: return L("六角形", "Hexagon")
        case .octagon: return L("八角形", "Octagon")
        case .banner: return L("旗", "Banner")
        case .burst: return L("星形", "Starburst")
        }
    }

    /// 色の組の名前（`TrunkLabelDesign.customPalettes` の並び・地の色で言う）
    static func paletteName(_ index: Int) -> String {
        let names: [(String, String)] = [
            ("生成り", "Cream"), ("赤茶", "Rust"), ("藤色", "Wisteria"), ("若葉", "Leaf green"), ("水色", "Pale blue"),
            ("橙", "Orange"), ("紺", "Navy"), ("夜空", "Night sky"), ("深緑", "Deep green"), ("えんじ", "Crimson"),
            ("金茶", "Golden brown"), ("薄藍", "Pale indigo"),
        ]
        guard names.indices.contains(index) else { return L("色 \(index + 1)", "Color \(index + 1)") }
        return L(names[index].0, names[index].1)
    }

    /// 絵の名前（`TrunkLabelDesign.customArts` に入る絵）
    static func artName(_ art: TrunkLabelArt) -> String {
        switch art {
        case .fuji: return L("富士山", "Mt. Fuji")
        case .pagoda: return L("塔", "Pagoda")
        case .torii: return L("鳥居", "Torii gate")
        case .sakura: return L("桜", "Cherry blossom")
        case .maple: return L("もみじ", "Maple leaf")
        case .wave: return L("波", "Wave")
        case .sun: return L("太陽", "Sun")
        case .moon: return L("月", "Moon")
        case .ship: return L("船", "Ship")
        case .train: return L("汽車", "Train")
        case .lighthouse: return L("灯台", "Lighthouse")
        case .cloud: return L("雲", "Cloud")
        default: return art.rawValue
        }
    }

    /// 作り直しの断り（サーバーの `code`）を画面の言葉に
    static func refusal(code: String?, fallback: String) -> String {
        switch code {
        case "proOnly": return L("Pro の機能です", "This is a Pro feature")
        // 作り直し・好きなデザイン（#706）
        case "noRerollsLeft": return L("このラベルの作り直しは使い切りました（1枚につき3回まで）。",
                                       "You\u{2019}ve used all redos for this label (3 per label).")
        case "rerollOrder": return L("作り直しの回数が合いませんでした。読み直してください。",
                                     "The redo count didn\u{2019}t match. Reload and try again.")
        case "custom": return L("好きなデザインで作ったラベルは、作り直せません。",
                                "A label with your own design can\u{2019}t be redone.")
        case "noCustom": return L("好きなデザインで作れる回数がありません。投稿すると貯まります。",
                                  "You can\u{2019}t make your own design right now. Keep posting to earn one.")
        case "badCustom": return L("そのデザインは選べませんでした。選び直してください。",
                                   "That design couldn\u{2019}t be used. Choose again.")
        case "notInPocket": return L("貼ったラベルには使えません。手持ちに戻してから選んでください。",
                                     "This can\u{2019}t be used on a stuck label. Move it back to your pocket first.")
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
        // 手荷物タグを自分で選ぶ（2026-11-08・札 #501）
        case "tagPickNotStuck": return L("そのラベルはもう貼っていません。選び直してください。",
                                         "That label isn\u{2019}t on your trunk anymore. Choose again.")
        case "tagPickNoPlace": return L("地名のないラベルはタグに載せられません。", "A label without a place name can\u{2019}t go on a tag.")
        case "tagPickDuplicate": return L("同じ地名は、タグに1枚だけ載せられます。", "Each place can be on only one tag.")
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
                             material: L("牛革、縫い目の縁、真鍮の金具", "Cowhide, stitched edges, brass fittings"),
                             aging: L("革に艶が出て飴色へ", "The leather gains a shine and turns amber"),
                             concept: nil, hardware: nil, only: nil)
        case .canvas:
            return ModelInfo(name: L("帆布の鞄", "Canvas bag"),
                             material: L("縞の帆布、厚革の縁と角", "Striped canvas, thick leather edges and corners"),
                             aging: L("布が日に焼け、しみが増える", "The cloth sun-fades and gathers stains"),
                             concept: nil, hardware: nil, only: nil)
        case .aluminum:
            return ModelInfo(name: L("アルミのケース", "Aluminum case"),
                             material: L("波板のアルミ、打ち出しの角", "Ribbed aluminum, pressed corners"),
                             aging: L("細かな擦り傷が光る", "Fine scratches catch the light"),
                             concept: nil, hardware: nil, only: nil)
        case .steamer:
            return ModelInfo(name: L("船旅の衣装箱", "Steamer trunk"),
                             material: L("緑の帆布張り、木の桟、真鍮の鋲", "Green canvas, wooden slats, brass studs"),
                             aging: L("木の桟が明るく褪せる", "The wooden slats fade lighter"),
                             concept: nil, hardware: nil, only: nil)
        case .urushi:
            return ModelInfo(name: L("漆の旅箱", "Lacquer travel box"),
                             material: L("木地、黒漆に朱の下塗り", "Wood, black lacquer over a vermilion base"),
                             aging: L("使うほど黒が透けて、下の朱がほんのり出てくる",
                                      "With use the black thins and the vermilion beneath shows through"),
                             concept: L("木地に漆を何度も塗り重ね、金で波を描いた旅の箱。紐は正絹の組紐。",
                                        "A travel box of many lacquer coats with golden waves. Tied with braided silk."),
                             hardware: L("金の角金具（彫り）、組紐の留め", "Engraved gold corners, braided-cord ties"),
                             only: L("金蒔絵の波と家紋のような丸紋", "Maki-e waves and a crest-like roundel"))
        case .kori:
            return ModelInfo(name: L("柳行李", "Willow kori"),
                             material: L("柳の編み、籐の縁", "Woven willow, rattan rim"),
                             aging: L("編み目が飴色に焼けて、縄がほつれる", "The weave tans to amber and the rope frays"),
                             concept: L("柳の枝を編んだ、昔の旅の行李。軽くて、編み目に旅の日が染みていく。",
                                        "An old woven-willow travel basket. Light, and every trip soaks into the weave."),
                             hardware: L("革の角当て、麻の縄", "Leather corner guards, hemp rope"),
                             only: L("縄の結び目が旅の数だけ増える", "A knot in the rope for every trip"))
        case .sleeper:
            return ModelInfo(name: L("寝台列車の鞄", "Sleeper-train case"),
                             material: L("牛革（ボルドー）、縫い目の縁", "Bordeaux cowhide, stitched edges"),
                             aging: L("赤が深まり、名札の文字が擦れて光る", "The red deepens and the name plate wears to a shine"),
                             concept: L("長い夜行列車の旅のための、深い赤の革鞄。真鍮の名札に持ち主の名前を刻む。",
                                        "A deep-red leather case for long night trains, with your name on a brass plate."),
                             hardware: L("真鍮の上下の帯、名札、錠前", "Brass bands, name plate, lock"),
                             only: L("持ち主の名前を刻んだ真鍮の名札", "A brass plate engraved with your name"))
        case .clipper:
            return ModelInfo(name: L("飛行艇のアルミ", "Flying-boat aluminum"),
                             material: L("磨いたアルミ、鋲留めの継ぎ目", "Polished aluminum, riveted seams"),
                             aging: L("擦り傷が増えて、光り方が柔らかくなる", "Scratches gather and the shine softens"),
                             concept: L("海を渡った飛行艇の時代の、磨いたアルミの鞄。鋲の列と継ぎ目まで機体と同じ作り。",
                                        "A polished aluminum case from the flying-boat era, riveted like the airframe."),
                             hardware: L("クロームの角、名札、革の持ち手", "Chrome corners, name plate, leather handle"),
                             only: L("飛んだ区間を刻める機体の名札", "An airframe plate for the routes you flew"))
        case .captain:
            return ModelInfo(name: L("船長の箱", "Captain\u{2019}s chest"),
                             material: L("チークの板張り", "Teak planks"),
                             aging: L("板が明るく褪せ、真鍮が青くくすむ", "The planks bleach and the brass turns verdigris"),
                             concept: L("チークの板を真鍮の帯で締めた、船乗りの道具箱。ふたに羅針盤を嵌めてある。",
                                        "A sailor\u{2019}s chest of teak bound in brass, with a compass set in the lid."),
                             hardware: L("真鍮の帯と大きな角、鋲", "Brass bands, large corners, studs"),
                             only: L("ふたの羅針盤（行きたい場所の方角を指す）", "A compass in the lid (points to your saved places)"))
        case .starchart:
            return ModelInfo(name: L("星図の鞄", "Star-chart case"),
                             material: L("牛革（紺）、金の押し線", "Navy cowhide, gold tooling"),
                             aging: L("旅の場所が増えるたびに、星と線が増える", "More stars and lines with every new place"),
                             concept: L("紺の革に金の押し線で星座を描いた鞄。星は、自分が写真を撮った場所の並び。",
                                        "Navy leather tooled in gold with a constellation made of the places you photographed."),
                             hardware: L("真鍮の角、金の尾錠", "Brass corners, gold buckles"),
                             only: L("自分の撮影地から描かれる星座", "A constellation drawn from your photo spots"))
        }
    }

    /// 眉ラベル（モック Main の「MY TRUNK · 革の旅行鞄」）。
    /// **人のトランクでは「TRUNK · 型」**（2026-10-21・run 609 の 101c: 人のトランクの中なのに「MY TRUNK」と出ていた）
    static func eyebrow(_ model: TrunkModel, theirs: Bool = false) -> String {
        "\(theirs ? "TRUNK" : "MY TRUNK")\u{2002}\(info(model).name)"
    }

    /// トランクの読み上げ（モック Trunk の `ariaLabel`）。付けている部品があれば名前を添える
    static func accessibilityLabel(model: TrunkModel, labels: Int, tags: Int, equipped: TrunkEquipped = .none) -> String {
        var text = L("\(info(model).name)。ラベル\(labels)枚", "\(info(model).name). \(Plural.count(labels, "label"))")
        if tags > 0 { text += L("、手荷物タグ\(tags)枚", ", \(Plural.count(tags, "baggage tag"))") }
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

    /// 硬貨だけが届いた一言（ラベルは受け取らない設定・2026-10-17 次の版）。
    /// 2026-11-23（札 #716・案の頁の「言葉」）: 何をもらって何に使えるかを文で（「硬貨 +1、」の記号の並びをやめた）
    static func coinNotice(_ n: Int) -> String {
        L("硬貨を\(n)枚もらいました。カプセルの機械で使えます", "You got \(Plural.count(n, "coin")). Use it at the capsule machine.")
    }

    /// ラベルが届かなかった一言に添える硬貨（手持ちがいっぱいでも硬貨は届く）
    static func coinAlsoNotice(_ n: Int) -> String {
        L("硬貨は\(n)枚もらいました。", "You still got \(Plural.count(n, "coin")).")
    }

    /// 投稿のお礼でかけらも届いたときに添える一言（札 #713。サーバーが `fragment` を返したときだけ）
    static func fragmentAlsoNotice(_ n: Int) -> String {
        L("かけらも\(n)つもらいました。", "You also got \(Plural.count(n, "fragment")).")
    }

    /// 届いた画面の硬貨の札（「硬貨 +1」）
    static func coinChip(_ n: Int) -> String { L("硬貨 +\(n)", "+\(n) coin") }

    static let unstickFull = L("手持ちがいっぱいのため、はがせません。手持ちのラベルを貼るか削除してください。",
                               "Your pocket is full, so it can\u{2019}t be peeled off. Stick or delete a label in your pocket first.")
}

// MARK: - 端末の中だけの移り変わり（画面写真の見本・`PreviewSession.trunkSample`）

/// サーバーと同じ決まりで、トランクの状態を手元で動かす（Debug の見本だけが使う。本番はサーバーの応答を映す）
enum TrunkLocal {

    /// 貼る（サーバーの `stickMutation` と同じ決まり）。置き場があればそれ（番号は付けない）。無ければ添えた番号で、
    /// その番号をもうほかのラベルが持っていれば書かない——`take` のときだけ、古いラベルの番号を消して移す
    static func stick(_ s: TrunkState, id: String, pos: TrunkPos? = nil, slot: Int? = nil, take: Bool = false) -> TrunkState {
        guard let label = s.pocket.first(where: { $0.id == id }) else { return s }
        let owner = pos == nil ? slot.flatMap { n in s.stuck.first { $0.pos == nil && $0.slot == n } } : nil
        let write = pos == nil && slot != nil && (owner == nil || take)
        let stuck = pos.map { label.withPos(TrunkPlacement.clamp($0)) } ?? label.withSlot(write ? slot : nil)
        let rest = write && owner != nil ? s.stuck.map { $0.id == owner?.id ? $0.withSlot(nil) : $0 } : s.stuck
        // 作り直しの候補は貼ったら消す（回数は残す・サーバーの `stickMutation` と同じ・#706）
        return s.copy(pocket: s.pocket.filter { $0.id != id }, stuck: [stuck.droppingCandidates()] + rest,
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
        // タグに載せていたラベルをはがしたら、その枠はおまかせに戻す（サーバーの `unstickMutation` と同じ）
        let picks = s.tagPicks.map { $0 == .label(id) ? TrunkTagPick.auto : $0 }
        return s.copy(pocket: [label.withPos(nil)] + s.pocket, stuck: rest, tagPicks: picks)
    }

    static func remove(_ s: TrunkState, id: String) -> TrunkState {
        s.copy(pocket: s.pocket.filter { $0.id != id },
               pendingReroll: s.pendingReroll?.labelId == id ? .some(nil) : nil)
    }

    /// 作り直し（#706・サーバーの `rerollMutation` と同じ）: 手持ちのラベルで、好きなデザインでなく、回数が残っているときだけ。
    /// 種を1つ候補に足し、その種を選んだ状態にする
    static func reroll(_ s: TrunkState, id: String, seed: Int) -> TrunkState {
        guard let label = s.pocket.first(where: { $0.id == id }), label.custom == nil, label.rerollsLeft > 0 else { return s }
        return s.copy(pocket: s.pocket.map { $0.id == id ? $0.withReroll(seed: seed) : $0 })
    }

    /// 候補から選ぶ（サーバーの `chooseMutation` と同じ: 候補か今の種だけ）
    static func choose(_ s: TrunkState, id: String, seed: Int) -> TrunkState {
        guard let label = s.pocket.first(where: { $0.id == id }), label.choices.contains(seed) else { return s }
        return s.copy(pocket: s.pocket.map { $0.id == id ? $0.withSeed(seed) : $0 })
    }

    /// 好きなデザインで作る（サーバーの `customMutation` と同じ: 手持ちのラベルに、使える回数を1つ使って付ける）
    static func custom(_ s: TrunkState, id: String, custom: TrunkLabelCustom) -> TrunkState {
        guard custom.isValid, let label = s.pocket.first(where: { $0.id == id }) else { return s }
        if label.custom == custom { return s }
        guard let progress = s.custom, progress.tickets > 0 else { return s }
        let next = TrunkCustomProgress(posts: progress.posts, tickets: progress.tickets - 1, every: progress.every,
                                       rerollsPerLabel: progress.rerollsPerLabel)
        return s.copy(pocket: s.pocket.map { $0.id == id ? $0.withCustom(custom) : $0 }, custom: .some(next))
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

    /// 手荷物タグの選び（見本）。サーバーの `settingsMutation` と同じ決まり: 貼っていない・地名の無いラベルは載せない
    /// （その枠はおまかせ）、前の枠と同じ地名の枠もおまかせ
    static func setTagPicks(_ s: TrunkState, _ picks: [TrunkTagPick]) -> TrunkState {
        var names = Set<String>()
        let cleaned: [TrunkTagPick] = TrunkTagPick.normalized(picks).map { pick in
            guard case .label(let id) = pick else { return pick }
            guard let label = s.stuck.first(where: { $0.id == id }), TrunkLooks.canHangTag(label),
                  names.insert(label.place.name.trimmingCharacters(in: .whitespacesAndNewlines)).inserted else { return .auto }
            return pick
        }
        return s.copy(tagPicks: TrunkTagPick.normalized(cleaned))
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

    /// 見本のカプセルの機械で出る順（めずらしい錠前「船の舵」→ まだ持っていない部品 → 持っている部品（かけら））。
    ///
    /// 2026-11-23 判断（1.2.0 の統合・Mac run 1765 の `testCapturesTrunkGacha`「開けた画面が出ない」）: 1回目は前は「菊」（`lock.2`）だったが、
    /// 見本は菊を持っていて付けてもいる（`parts`・`equipped`）ので、1回目がいつも「持っている部品」になっていた。
    /// 札 #716 から持っている部品の開けた画面は「もう1回まわす」で「トランクに付ける」が出ないため、新しい部品の開けた画面
    /// （画面写真 98a）を撮れなかった。**1回目は見本が持っていない、同じめずらしさ・同じ真鍮の錠前「船の舵」（`lock.6`）にする**。
    /// 菊は付け替えの見本（モック Equip の「古都」）で付けているので、持っている部品からは外さない
    static let gachaOrder = ["lock.6", "charm.12", "pin.1", "patch.6"]

    /// 貼ったあと動かした切符の見本（札 #605・`-JPPreviewTrunkWrinkles`）。owner の実機の「月崎」と同じ組
    /// （春・切符の形・生成りの地 #F3E6CC・桜の絵）になる種
    static let creased = label("s-tsukizaki", .season, "月崎", latin: "Tsukizaki", country: "日本", season: .spring,
                               seed: 852_009, at: "2026-05-02T09:00:00Z")

    /// 見本の状態。`empty` は届いたラベルが1枚も無い人（空の状態の絵）。`coins` で硬貨の枚数を替える（画面写真の「硬貨がありません」）。
    /// `creasedMoves` があれば、貼ったラベルのいちばん新しい所に `creased` を足す（よれの絵・札 #605）
    static func state(isPro: Bool, empty: Bool = false, coins: Int? = nil,
                      creasedMoves: Int? = PreviewSession.trunkWrinkleMoves) -> TrunkState {
        let stuckLabels = empty ? [] : (creasedMoves == nil ? stuck : [creased] + stuck)
        return TrunkState(model: .leather, effectiveModel: .leather,
                   // 届いた画面の見本では、届いた1枚も手持ちに入れる（届いた画面で作り直す・貼るを端末の中で動かすため・#706）
                   pocket: empty ? [] : (PreviewSession.opensTrunkArrived ? [arrived] + pocket : pocket), stuck: stuckLabels,
                   limit: isPro ? TrunkState.proLimit : TrunkState.freeLimit, isPro: isPro,
                   rerollsLeft: isPro ? 2 : 0, pendingReroll: nil,
                   posts: empty ? 0 : 42, receiveLabels: true,
                   coins: coins ?? (empty ? 0 : 2), parts: empty ? [] : parts, fragments: empty ? 0 : 3,
                   equipped: empty ? .none : equipped,
                   custom: TrunkCustomProgress(posts: customPosts ?? 1, tickets: customTickets ?? 0, every: isPro ? 2 : 3))
    }

    /// 見本の好きなデザインの進み（`-JPPreviewTrunkCustomReady` で作れる状態にする・#706）
    static var customPosts: Int? { PreviewSession.trunkCustomReady ? 0 : nil }
    static var customTickets: Int? { PreviewSession.trunkCustomReady ? 1 : nil }

    /// 届いた画面の見本の1枚（モック LabelArrived の「京都 · 桜」）
    static let arrived = label("a-kyoto", .season, "京都", latin: "Kyoto", country: "日本", season: .spring, seed: 41_207,
                               at: "2026-04-03T09:00:00Z")

    /// 作り直しの見本の種（`n` 回目。ラベルごとに違う種にする・#706）
    static func rerollSeed(_ label: TrunkLabel, n: Int) -> Int { 20_000 + n * 7 + abs(label.seed % 1_000) }
}

/// 古び方の区切りの知らせを出した印（人ごとに端末へ・退会で消す `AccountLocalData`）
enum TrunkAgingNotice {
    static func key(_ userId: String) -> String { "trunk.agingSeen.\(userId)" }
}
