import Foundation

// カプセルの機械（モック Gacha・GachaOpen・GachaOdds・PartsBox・2026-10-17 次の版）の計算と言葉。
// SwiftUI を読まない層（Linux でテストできるように）。

/// ハンドルの回り方（モック Gacha の `crankDown`・`crankMove`・`turnTap`）。
///
/// 指で円を描くと、その角度の差だけ回る（右回りだけ進む・左へは 0.15 倍だけ戻る）。押すたびに 4 分の 1。
/// 1 周（360°）で出る。**目盛り**は 30° ごと（触覚と音を鳴らす所・2026-10-17 判断）
struct TrunkCrank: Equatable {
    /// 見た目の角度（0〜360）。2026-11-23（札 #716）: 目盛りで引っかかる（`TrunkCrank.detent(raw:)`）。
    /// 前は指の角度にそのまま付いて -18° から回った。案の頁どおり 0°（北の目盛り）から回す
    var angle: Double { Self.detent(raw: turned) }
    /// 進んだ角度（0〜360）
    private(set) var turned: Double = 0
    /// 前の指の角度（押さえていなければ nil）
    private var last: Double?
    /// 押さえてから動いた角度の合計（少なければ「押した」とみなす）
    private(set) var moved: Double = 0

    static let goal: Double = 360
    static let tickStep: Double = 30
    static let tapStep: Double = 90
    /// 左へ回したときに戻る割合
    static let backDamping: Double = 0.15
    /// これより動かなければ「押した」（モックの `moved > 8`）
    static let tapSlop: Double = 8

    init() {}

    /// 1周した（見せる角度が 360 に届いた。指は目盛りの間の 72% で次へ跳ぶので、最後の目盛りも同じ）
    var isDone: Bool { angle >= Self.goal }
    var isHolding: Bool { last != nil }

    /// 進み（0〜100・モックの `Math.min(100, Math.round(turned / 3.6))`）
    var percent: Int { min(100, Int(TrunkRGBA.jsRound(turned / 3.6))) }

    /// 押さえた（中心からの指の位置）
    mutating func begin(dx: Double, dy: Double) {
        last = atan2(dy, dx) * 180 / .pi
        moved = 0
    }

    /// 指を動かした。越えた目盛りの数を返す
    @discardableResult
    mutating func drag(dx: Double, dy: Double) -> Int {
        guard let last, !isDone else { return 0 }
        let a = atan2(dy, dx) * 180 / .pi
        var delta = a - last
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        moved += abs(delta)
        if delta < 0 { delta *= Self.backDamping }
        self.last = a
        return advance(delta)
    }

    /// 指を離した。**押しただけ（動きが少ない）なら 4 分の 1 回す**。越えた目盛りの数を返す
    @discardableResult
    mutating func end() -> Int {
        defer { last = nil }
        guard last != nil, moved <= Self.tapSlop else { return 0 }
        return tap()
    }

    /// 押すたびに 4 分の 1（読み上げの「まわす」もこれ）
    @discardableResult
    mutating func tap() -> Int {
        guard !isDone else { return 0 }
        return advance(Self.tapStep)
    }

    /// 指を離した（押しただけでも4分の1は回さない・行き先は `TrunkGachaFlow.release` で決める・2026-11-12）
    mutating func letGo() {
        last = nil
    }

    /// 決まった角度だけ回す（自分で回るとき・`autoAdvance`）。越えた目盛りの数を返す
    mutating func turn(by delta: Double) -> Int {
        advance(delta)
    }

    private mutating func advance(_ delta: Double) -> Int {
        let before = angle
        turned = min(Self.goal, max(0, turned + delta))
        // 越えた目盛りは見せる角度で数える（跳んだときに1回だけカチッ）
        return max(0, Int(floor(angle / Self.tickStep + 1e-9)) - Int(floor(before / Self.tickStep + 1e-9)))
    }
}

/// ガラスの球の中のカプセル（モック Gacha の `pos`・`colors`）
enum TrunkCapsules {

    struct Capsule: Equatable {
        let x: Double
        let y: Double
        /// 上の半分の色・下の半分の色
        let top: TrunkRGBA
        let bottom: TrunkRGBA
        let rot: Double
    }

    static let colors: [(UInt32, UInt32)] = [(0xC8352A, 0xF4F1EA), (0x1F4E8C, 0xF4F1EA), (0xE3B23C, 0xF4F1EA),
                                             (0x2E5D50, 0xF4F1EA), (0x6F5A8E, 0xF4F1EA), (0xC9A66B, 0x1A1A1A),
                                             (0x8C2F2B, 0xEFE3C8), (0x5B8FC9, 0xF4F1EA)]

    /// 260×260 の球の中の並び（左上の点・46×46）
    static let all: [Capsule] = {
        var pos: [(Double, Double)] = []
        let r = 130.0, cx = 130.0, cy = 130.0
        for (y, off) in [(206.0, 0.0), (176, 22), (146, 6), (118, 26), (92, 12)] {
            let dy = y + 23 - cy
            let half = max(0, (r - 10) * (r - 10) - dy * dy).squareRoot()
            var x = cx - half + off
            while x + 46 <= cx + half + 4 {
                pos.append((TrunkRGBA.jsRound(x), y))
                x += 44
            }
        }
        return pos.enumerated().map { i, p in
            let c = colors[i % colors.count]
            return Capsule(x: p.0, y: p.1, top: TrunkRGBA(c.0), bottom: TrunkRGBA(c.1), rot: Double((i * 47) % 180))
        }
    }()
}

/// カプセルの機械まわりの言葉
enum TrunkGachaText {

    /// 段の中の1点あたりの確率（％・小数2桁）。**段の確率 ÷ 段の点数**（サーバーは段 → 段の中から等しく）
    static func perPart(_ rarity: TrunkPartRarity) -> Double {
        let n = TrunkPartCatalog.count(rarity)
        guard n > 0 else { return 0 }
        return (Double(rarity.percent) / Double(n) * 100).rounded() / 100
    }

    static func percentText(_ value: Double) -> String {
        String(format: "%.2f%%", value)
    }

    /// 開けた画面の見出し（モック「真鍮の錠前「菊」」）。金属の名前が部品の名前に入っていれば重ねない
    static func title(_ part: TrunkPart) -> String {
        if let metal = part.look.metal, part.kind != .handle, part.kind != .corner {
            let m = metal.name
            if !part.name.contains(m), !(metal == .darkbrass && part.name.contains("真鍮")) {
                return L("\(m)の\(part.kind.title)「\(part.name)」", "\(m) \(part.kind.title.lowercased()) \u{201C}\(part.name)\u{201D}")
            }
        }
        return L("\(part.kind.title)「\(part.name)」", "\(part.kind.title) \u{201C}\(part.name)\u{201D}")
    }

    /// 眉ラベル（「めずらしい · 錠前」）
    static func eyebrow(_ part: TrunkPart) -> String { "\(part.rarity.name)\u{2002}\(part.kind.tabName)" }

    /// 開けた画面の見出し（「錠前「菊」が出ました」・2026-11-23 札 #716）
    static func openTitle(_ part: TrunkPart) -> String {
        L("\(title(part))が出ました", "\(title(part)) came out")
    }

    /// 開けた画面の一行（新しい部品）
    static var freshNote: String { L("どの型のトランクにも付けられます", "Fits every trunk style") }

    /// 開けた画面の一行（持っている部品・かけらをもらった。数はもらったあと）
    static func duplicateNote(fragments: Int) -> String {
        let n = TrunkPartsBoxText.filledFragments(fragments)
        return L("持っている部品でした。かけらを1つもらいました（\(n) / 5）",
                 "You already had this. You got a fragment (\(n) / 5)")
    }

    /// 部品の札の右（古び方）
    static var agingNote: String { L("トランクと一緒に\n古びていきます", "Ages along\nwith your trunk") }

    /// 開けた画面の副ボタン（閉じる）
    static var keepTitle: String { L("部品箱に入れる", "Put it in the parts box") }

    /// 持っている部品が出て、硬貨があるときの主ボタン
    static var againTitle: String { L("もう1回まわす", "Turn again") }

    /// 付けたあとの知らせ
    static func equippedNotice(_ part: TrunkPart) -> String {
        L("「\(part.name)」をトランクに付けました", "Put \u{201C}\(part.name)\u{201D} on your trunk")
    }

    /// 開けた画面のボタンの組（2026-11-23 札 #716）
    enum OpenActions: Equatable {
        /// 新しい部品: 「トランクに付ける」が主、「部品箱に入れる」が副
        case equip
        /// 持っている部品で硬貨がある: 「もう1回まわす」が主、「部品箱に入れる」が副
        case again
        /// 持っている部品で硬貨が無い: 「部品箱に入れる」だけ
        case keep
    }

    static func openActions(duplicate: Bool, coins: Int) -> OpenActions {
        guard duplicate else { return .equip }
        return coins > 0 ? .again : .keep
    }

    /// 1周したあと返事を待つ間に戻った人への一言
    static func arrivedWhileAway(_ r: TrunkGachaResult) -> String {
        r.duplicate
            ? L("「\(r.part.name)」は持っている部品でした。かけらを1つもらいました",
                "\u{201C}\(r.part.name)\u{201D} was one you have. You got a fragment.")
            : L("「\(r.part.name)」が出ました。部品箱に入れました", "\u{201C}\(r.part.name)\u{201D} came out. It\u{2019}s in your parts box.")
    }
}

/// カプセルの機械の段取り
enum TrunkGachaPhase: Equatable {
    /// 硬貨を入れる前
    case idle
    /// 硬貨を入れた・ハンドルを回している
    case turning
    /// 1周した・サーバーの返事を待っている
    case waiting
    /// カプセルが出た
    case out
}

/// 部品箱の数と言葉
enum TrunkPartsBoxText {

    /// 交換に要るかけら（サーバーの `FRAGMENTS_PER_EXCHANGE`）
    static let fragmentsPerExchange = 5

    /// 持っていない部品の影の不透明度（白の一色の影絵・2026-10-17 owner。板は `brightness(0) opacity(0.35)` の黒だが、
    /// #121212 の札の上でほぼ見えないので白 10% にした。8〜12% の間で動かす）
    static let missingShadowOpacity = 0.10

    /// 集めた数（「23 / 108」）
    static func collected(_ owned: Set<String>) -> (owned: Int, total: Int) {
        (TrunkPartCatalog.all.filter { owned.contains($0.id) }.count, TrunkPartCatalog.all.count)
    }

    /// 種類ごとの集めた数（「4/12」）
    static func collected(_ owned: Set<String>, kind: TrunkPartKind) -> Int {
        TrunkPartCatalog.parts(of: kind).filter { owned.contains($0.id) }.count
    }

    /// かけらの 5 つの印のうち、埋まっている数（5 以上は 5）
    static func filledFragments(_ fragments: Int) -> Int { min(fragmentsPerExchange, max(0, fragments)) }

    static func canExchange(fragments: Int) -> Bool { fragments >= fragmentsPerExchange }

    /// かけらの読み上げ
    static func fragmentsLabel(_ fragments: Int) -> String {
        L("かけら \(fragmentsPerExchange)つのうち \(filledFragments(fragments))つ", "\(filledFragments(fragments)) of \(fragmentsPerExchange) fragments")
    }

    /// 付け替えの画面の、その場所の数の行（モック Equip「ベルトに3つまで留められます · 2 / 3」）
    static func slotNote(_ kind: TrunkPartKind, count: Int) -> String {
        switch kind {
        case .pin: return L("ベルトに3つまで留められます\u{2002}\(count) / 3", "Up to 3 on the strap\u{2002}\(count) / 3")
        case .patch: return L("胴に2つまで縫い付けられます\u{2002}\(count) / 2", "Up to 2 on the body\u{2002}\(count) / 2")
        case .lining: return L("内張りは、ふたを開けたときに見えます（次の版）", "Linings show when the lid opens (coming later)")
        default: return L("1つ付けられます", "One at a time")
        }
    }
}

/// 付け替えの決まり（付ける・外す・数の上限）
enum TrunkEquipText {

    /// 開けた画面の「トランクに付ける」: 1つの場所は置き換え、ピン・ワッペンは足す。
    /// **いっぱいなら変えずに `full`**（付け替えの画面と同じ決まり・2026-10-17 の見直し: 古いものを黙って外していた）
    static func equipping(_ part: TrunkPart, on e: TrunkEquipped) -> (equipped: TrunkEquipped, full: Bool) {
        let ids = e.ids(part.kind)
        guard !ids.contains(part.id) else { return (e, false) }
        if part.kind.capacity == 1 { return (e.setting(part.kind, [part.id]), false) }
        guard ids.count < part.kind.capacity else { return (e, true) }
        return (e.setting(part.kind, ids + [part.id]), false)
    }

    /// 付け替えの画面で押した: 付けていれば外す・付けていなければ付ける。
    /// ピン・ワッペンがいっぱいのときは変えず、`full` を返す（「3つまで」の一言を出す）
    static func toggling(_ part: TrunkPart, on e: TrunkEquipped) -> (equipped: TrunkEquipped, full: Bool) {
        let ids = e.ids(part.kind)
        if ids.contains(part.id) { return (e.setting(part.kind, ids.filter { $0 != part.id }), false) }
        if part.kind.capacity == 1 { return (e.setting(part.kind, [part.id]), false) }
        guard ids.count < part.kind.capacity else { return (e, true) }
        return (e.setting(part.kind, ids + [part.id]), false)
    }

    /// いっぱいの一言
    static func fullNote(_ kind: TrunkPartKind) -> String {
        kind == .pin ? L("ピンバッジは3つまでです。どれかを外してから付けてください。", "Up to 3 pins. Take one off first.")
            : L("ワッペンは2つまでです。どちらかを外してから付けてください。", "Up to 2 patches. Take one off first.")
    }

    /// 付け替えの画面で、いま選んでいる場所の枠（360×300 の絵の座標・真鍮の破線。内張りは見えないので nil）
    static func outline(_ kind: TrunkPartKind) -> TrunkRect? {
        switch kind {
        case .handle: return TrunkRect(x: 124, y: 0, w: 112, h: 42)
        case .corner: return TrunkRect(x: -2, y: 30, w: 48, h: 48)
        case .lock: return TrunkRect(x: 154, y: 94, w: 52, h: 46)
        case .lining: return nil
        case .tag: return TrunkRect(x: 86, y: 12, w: 46, h: 60)
        // モック Equip の `left: 82; top: 128; 58×108`（トランクは上 20 に置いてある）
        case .pin: return TrunkRect(x: 82, y: 108, w: 58, h: 108)
        case .patch: return TrunkRect(x: 254, y: 204, w: 54, h: 54)
        case .charm: return TrunkRect(x: 126, y: 6, w: 36, h: 58)
        case .key: return TrunkRect(x: 200, y: 10, w: 52, h: 62)
        }
    }
}
