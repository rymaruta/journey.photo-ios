import Foundation

/// 模様替えの札（壁紙・床・カーテン・灯り）
enum CamperRoomStyleTab: String, CaseIterable, Sendable {
    case wall, floor, curtain, light

    var name: String {
        switch self {
        case .wall: return L("壁紙", "Walls")
        case .floor: return L("床", "Floor")
        case .curtain: return L("カーテン", "Curtains")
        case .light: return L("灯り", "Light")
        }
    }

    /// 外まわりの図鑑の分類（壁と床だけ。カーテンと灯りは色で、最初から全部選べる）
    var partCategory: CamperCategory? {
        switch self {
        case .wall: return .wallWood
        case .floor: return .floor
        case .curtain, .light: return nil
        }
    }
}

/// 模様替えの見本 1 つ（2026-10-22 owner の実機: 持っていない柄が空の点線の札「まだ」「近日」で並ぶだけで、選ぶ楽しさが無かった）。
/// 持っていない柄も本当の柄を暗く見せ、鍵と「あと何枚」を添え、押すと部屋で試せる（見本・保存しない）
struct CamperRoomStyleChoice: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// 持っている（押すとすぐ部屋に映り、覚える）
        case owned
        /// 写真で集められる（いまの数 / 要る数）
        case locked(have: Int, need: Int)
        /// まだ集められない（要サーバー・近日）
        case soon
    }

    let key: String
    let name: String
    let state: State
    /// 外まわりの図鑑の部品（壁・床だけ）
    let partId: String?

    var owned: Bool { state == .owned }

    /// 札の下の 2 行目（持っていない物だけ）。数は SF の等幅数字で出す
    var progressText: String? {
        switch state {
        case .owned: return nil
        case .locked(let have, let need): return "\(min(have, need)) / \(need)"
        case .soon: return L("近日", "Soon")
        }
    }

    /// 0〜1 の進み具合（持っていない柄の札の細い棒）
    var fraction: Double {
        switch state {
        case .owned: return 1
        case .soon: return 0
        case .locked(let have, let need): return need > 0 ? min(1, max(0, Double(have) / Double(need))) : 1
        }
    }
}

/// 模様替えの板の決まり（並べる見本・今の柄・下のボタン）。画面から分けて試験する
enum CamperRoomStyleBoard {
    static func choices(_ tab: CamperRoomStyleTab, partsOwned: Set<String>, stats: CamperStats) -> [CamperRoomStyleChoice] {
        if let cat = tab.partCategory {
            return CamperCatalog.parts(cat).map { p in
                let state: CamperRoomStyleChoice.State
                if partsOwned.contains(p.id) {
                    state = .owned
                } else if p.unlock.isAvailable {
                    let pr = p.unlock.progress(stats)
                    state = .locked(have: pr.have, need: pr.need)
                } else {
                    state = .soon
                }
                return CamperRoomStyleChoice(key: p.key, name: p.name, state: state, partId: p.id)
            }
        }
        let colors = tab == .curtain ? CamperRoomMaterials.curtainColors : CamperRoomMaterials.lightColors
        return colors.map { CamperRoomStyleChoice(key: $0.key, name: L($0.ja, $0.en), state: .owned, partId: nil) }
    }

    static func key(_ style: CamperRoomStyle, _ tab: CamperRoomStyleTab) -> String {
        switch tab {
        case .wall: return style.wall
        case .floor: return style.floor
        case .curtain: return style.curtain
        case .light: return style.light
        }
    }

    static func with(_ style: CamperRoomStyle, _ tab: CamperRoomStyleTab, key: String) -> CamperRoomStyle {
        var s = style
        switch tab {
        case .wall: s.wall = key
        case .floor: s.floor = key
        case .curtain: s.curtain = key
        case .light: s.light = key
        }
        return s
    }

    /// 下のボタン（2026-10-22 owner: 今と同じなのに「これにする」が大きく光っていた）。
    /// 選んだ柄はその場で部屋に映って覚えるので、変えていなければ「閉じる」（線だけ）。変えたら「元に戻す」と「これにする」（真鍮の塗り）
    enum Footer: Equatable { case close, revertOrKeep }

    static func footer(entry: CamperRoomStyle?, now: CamperRoomStyle) -> Footer {
        guard let entry, entry != now else { return .close }
        return .revertOrKeep
    }

    /// 札の下の説明（札ごとに 1 行。灯りは夜にして見せる）
    static func note(_ tab: CamperRoomStyleTab, hasLocked: Bool) -> String {
        switch tab {
        case .wall, .floor:
            return hasLocked ? L("押すとすぐ部屋に映る。鍵の柄は押すと見本で試せる。", "Changes show right away. Tap a locked pattern to try it on.")
                : L("押すとすぐ部屋に映る。", "Changes show right away.")
        case .curtain: return L("押すとすぐ部屋に映る。", "Changes show right away.")
        case .light: return L("灯りの色は夜に見えるので、選ぶ間は夜にして見せる。", "Light colours show at night, so the room turns to night while you choose.")
        }
    }
}

/// 模様替えの途中の状態（入った時の柄・試している見本）。画面から分けて試験する（2026-10-22 確かめ役）。
/// 見本は映すだけで覚えない。部屋のタブを替えたら、前の部屋の柄と見本を持ち越さない
/// （持ち越すと、新しい部屋で何も触らないのに「これにする／元に戻す」が光り、「元に戻す」で前の部屋の柄が新しい部屋に書かれた）
struct CamperRoomStyleSession: Equatable {
    /// 模様替えに入った時の柄（模様替えの外では nil）
    private(set) var entry: CamperRoomStyle?
    /// 持っていない柄を部屋で試している見本
    var trial: CamperRoomStyleChoice?

    var active: Bool { entry != nil }

    /// 模様替えに入る
    mutating func begin(_ style: CamperRoomStyle) {
        entry = style
        trial = nil
    }

    /// 模様替えを出る
    mutating func end() {
        entry = nil
        trial = nil
    }

    /// 部屋を替えた。見本は捨て、模様替えの途中なら新しい部屋の柄から数え直す
    mutating func roomChanged(to style: CamperRoomStyle) {
        trial = nil
        if entry != nil { entry = style }
    }

    /// 部屋に映す柄（覚えた柄 `saved` に見本を重ねる。`saved` は変えない）
    func shown(_ saved: CamperRoomStyle, tab: CamperRoomStyleTab) -> CamperRoomStyle {
        guard let trial else { return saved }
        return CamperRoomStyleBoard.with(saved, tab, key: trial.key)
    }

    func footer(now: CamperRoomStyle) -> CamperRoomStyleBoard.Footer {
        CamperRoomStyleBoard.footer(entry: entry, now: now)
    }
}

/// 部屋の絵と下の板の高さの分け方（2026-10-22 owner の実機: 下の板が中身より低く、見本の名前が説明と重なり、
/// 札がタブの下線にかぶり、部屋の絵が上へ押し出されて切れた）。
/// 下の板は中身が要るだけの高さ（測った値）を取り、部屋の絵は残り全部。大きい文字で中身が伸びても、
/// 部屋の絵に最低限を残し、板の方を送れるようにする
enum CamperRoomSheetFit {
    /// 部屋の絵の最低の高さ（家具が豆にならない）
    static let minScene = 240.0
    /// 下の板が取れる割合の下限（小さい画面・大きい文字でも、板が全く出ないことはない）
    static let minPanelShare = 0.45
    /// 写真を飾る板の割合（写真の一覧が縦に送れる高さを先に取る）
    static let photosShare = 0.5

    /// (部屋の絵, 下の板) の高さ。`total` は見出しとタブを除いた高さ、`need` は板の中身が要る高さ
    static func split(total: Double, need: Double, photos: Bool = false) -> (scene: Double, panel: Double) {
        let total = max(0, total)
        let cap = max(total * minPanelShare, total - minScene)
        let panel = photos ? min(cap, total * photosShare) : min(max(0, need), cap)
        return (total - panel, panel)
    }

    /// 板を送れるようにするか（中身が板より高い時だけ）
    static func scrolls(need: Double, panel: Double) -> Bool { need > panel + 0.5 }
}
