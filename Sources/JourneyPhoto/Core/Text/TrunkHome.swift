import Foundation

// 旅のトランクの最初の画面と部品箱の並び・言葉（札 #711・案「トランクを見やすく」版3・2026-11-23 owner 承認）。
// 画面を持たない層（Linux でテストできる）。画面は `TrunkView`・`TrunkPartsBoxView`。

/// 最初の画面の大きいボタンがすること（状態で1つに替わる）
enum TrunkHomeAction: Equatable {
    /// 貼っていないラベルがある →「ラベルを貼る」
    case stick
    /// ラベルは無いが硬貨がある →「カプセルを回す」
    case gacha
    /// どちらも無い・まだ何も届いていない →「写真を投稿」
    case post
}

/// 大きいボタンの下の4つのカード
enum TrunkHomeTile: String, Equatable, CaseIterable {
    case gacha, parts, tags, open, stick
}

/// 最初の画面の見え方（案の6つの状態。テストと画面写真の見本で同じ名前を使う）
enum TrunkHomeScreen: Equatable {
    /// 読み込み中（形は同じで灰の骨格）
    case loading
    /// 圏外。前に読んだトランクが手元にあれば `saved`（薄く出して上にお知らせ）、無ければ今までどおりの「電波がありません」
    case offline(saved: Bool)
    /// まだ何も届いていない（初めて開いた人）
    case first
    /// 貼っていないラベルがある
    case labels
    /// ラベルは0、硬貨がある
    case coins
    /// ラベルも硬貨も0
    case none
}

enum TrunkHome {

    // MARK: 大きいボタン

    /// 大きいボタンを選ぶ（2026-11-23 判断・案の模型どおり）: 貼っていないラベル → 硬貨 → 投稿の順。
    /// **まだ何も届いていない人は硬貨があっても「写真を投稿」**（初めの一歩は投稿。硬貨は投稿のお礼で届く）
    static func primary(pocket: Int, coins: Int, isEmpty: Bool) -> TrunkHomeAction {
        if pocket > 0 { return .stick }
        if coins > 0 && !isEmpty { return .gacha }
        return .post
    }

    static func primary(_ state: TrunkState) -> TrunkHomeAction {
        primary(pocket: state.pocket.count, coins: state.coins, isEmpty: state.pocket.isEmpty && state.stuck.isEmpty)
    }

    /// 4つのカードの並び。大きいボタンと同じことはカードに出さない（同じ入口を2つ並べない）。
    /// 手荷物タグはサーバーが選びに対応している間だけ（`supportsTagPicks`・今までの行と同じ条件）
    static func tiles(for action: TrunkHomeAction, showsTags: Bool) -> [TrunkHomeTile] {
        let order: [TrunkHomeTile]
        switch action {
        case .stick, .post: order = [.gacha, .parts, .tags, .open]
        case .gacha: order = [.parts, .tags, .open, .stick]
        }
        return order.filter { showsTags || $0 != .tags }
    }

    static func title(_ action: TrunkHomeAction) -> String {
        switch action {
        case .stick: return L("ラベルを貼る", "Stick labels")
        case .gacha: return L("カプセルを回す", "Turn the capsule machine")
        case .post: return L("写真を投稿", "Post a photo")
        }
    }

    /// 大きいボタンの2行目（何があるから押すのか）
    static func subtitle(_ action: TrunkHomeAction, pocket: Int, coins: Int) -> String {
        switch action {
        case .stick: return L("貼っていないラベルが \(pocket) 枚", "\(Plural.count(pocket, "label")) to stick")
        case .gacha: return L("硬貨が \(coins) 枚あります", "You have \(Plural.count(coins, "coin"))")
        case .post: return L("投稿するとラベルと硬貨が届きます", "Posting brings a label and a coin")
        }
    }

    /// UI テストが探す目印。今までの行の目印をそのまま使う（大きいボタンとカードは同じことを出さないので重ならない）
    static func identifier(_ action: TrunkHomeAction) -> String {
        switch action {
        case .stick: return "trunk.stick.open"
        case .gacha: return "trunk.gacha.open"
        case .post: return "trunk.emptyPost"
        }
    }

    static func identifier(_ tile: TrunkHomeTile) -> String {
        switch tile {
        case .gacha: return "trunk.gacha.open"
        case .parts: return "trunk.partsBox"
        case .tags: return "trunk.tags.open"
        case .open: return "trunk.open"
        case .stick: return "trunk.stick.open"
        }
    }

    static func tileTitle(_ tile: TrunkHomeTile) -> String {
        switch tile {
        case .gacha: return L("カプセルを回す", "Capsule machine")
        case .parts: return L("部品箱", "Parts box")
        case .tags: return TrunkTagText.title
        case .open: return L("ふたを開ける", "Open the lid")
        case .stick: return L("ラベルを貼る", "Stick labels")
        }
    }

    /// カードの2行目（数は等幅の数字で出す）
    static func tileValue(_ tile: TrunkHomeTile, state: TrunkState) -> String {
        switch tile {
        case .gacha: return L("硬貨 \(state.coins) 枚", Plural.count(state.coins, "coin"))
        case .parts:
            let c = TrunkPartsBoxText.collected(state.ownedParts)
            return L("\(c.owned) / \(c.total) 集めた", "\(c.owned) / \(c.total) collected")
        case .tags:
            let posts = state.posts ?? 0
            let shown = TrunkLooks.tags(stuck: state.stuck, posts: posts, picks: state.tagPicks).count
            return TrunkTagText.rowValue(shown: shown, open: TrunkAging.tagCount(posts: posts))
        case .open: return L("メダルと乗車券", "Medals and tickets")
        case .stick: return L("手持ち \(state.pocket.count) 枚", "\(state.pocket.count) in pocket")
        }
    }

    // MARK: 状態

    /// 最初の画面の見え方を決める
    /// - Parameters:
    ///   - loading: まだ読めていない（`TrunkViewModel.phase == .loading`）
    ///   - offline: 読めずに圏外（`phase == .offline`）
    ///   - showingSaved: 圏外で、前に読んだトランクを出している
    static func screen(loading: Bool, offline: Bool, showingSaved: Bool, state: TrunkState?) -> TrunkHomeScreen {
        if showingSaved { return .offline(saved: true) }
        if offline { return .offline(saved: false) }
        guard !loading, let state else { return .loading }
        if state.pocket.isEmpty && state.stuck.isEmpty { return .first }
        switch primary(state) {
        case .stick: return .labels
        case .gacha: return .coins
        case .post: return .none
        }
    }

    // MARK: 回して見る

    static var spinTitle: String { L("回して見る", "Turn it") }
    static var spinLabel: String { L("トランクを回して見る", "Pick up and turn your trunk") }

    /// 初めて開いたときだけ揺らして光らせた印（**端末に1回だけ**・人ごとではない。退会で消す物を増やさない）
    static let introKey = "trunk.homeIntroShown"

    /// 揺らすか。揺らす時は印を付けて true（2回目からは false）
    static func takeIntro(_ defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: introKey) else { return false }
        defaults.set(true, forKey: introKey)
        return true
    }

    // MARK: 数え札・空

    /// 数え札の「貼ったラベル ›」（押すと一覧。前の「最近貼ったラベル」の「すべて見る」の代わり）
    static var stuckCaption: String { L("貼ったラベル", "Labels stuck") }

    static var firstNote: String {
        L("写真を投稿すると、お礼に旅のラベルが1枚届きます。届いたラベルをトランクに貼っていきましょう。",
          "Each photo you post brings a travel label as thanks. Stick them on your trunk.")
    }

    // MARK: 圏外

    static var offlineSavedNote: String {
        L("電波がありません。前に見たときのトランクです。", "No signal. This is your trunk as you last saw it.")
    }

    static var offlineRetry: String { L("もう一度", "Retry") }

    /// 「もう一度」を押しても読めなかった
    static var stillOffline: String { L("まだ電波がありません", "Still no signal") }

    /// カードの印（SF Symbols。カプセルは硬貨の絵 `TrunkCoinMark` を描くので使わない）
    static func symbol(_ tile: TrunkHomeTile) -> String {
        switch tile {
        case .gacha: return "circle"
        case .parts: return "shippingbox"
        case .tags: return "tag"
        case .open: return "archivebox"
        case .stick: return "rectangle.on.rectangle.angled"
        }
    }
}
