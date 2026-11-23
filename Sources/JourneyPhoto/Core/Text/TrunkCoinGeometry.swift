import Foundation

/// 硬貨の形の数値（`TrunkCoinMark` が描く）。
///
/// 2026-11-23（札 #716・owner 採用「羅針盤の硬貨」）: 黒地に真鍮の羅針盤を刻んだ硬貨に描き直した。
/// 前の真鍮の円盤（縁・面・内輪・COIN の刻印）は 16pt 以下で真鍮の丸になり、未読の点（真鍮 8pt）や件数バッジと
/// 紛れた。羅針盤は 14pt でも「真鍮の縁、黒い面、真鍮の星」に見え、形で見分けられる。
///
/// 大きさで描く量を変える（案の頁の「詳しく」の表）:
/// - 14〜23pt（`small`）: 真鍮の縁、黒い面、太い8方向の星1つ、真ん中の黒い点。縁の暗い線を太く
/// - 24〜31pt（`medium`）: 上に加えて、縁のギザ、面ごとに明暗をつけた星（東西南北は長く、間の4つは短い）、真鍮の留め、内輪、縁の北の印
/// - 32pt〜（`large`）: 上に加えて、縁の目盛り 24 本（6本ごとに太い）
///
/// 座標は案の頁と同じ 100×100 の箱（中心 50,50）で持ち、描く側が `size / 100` 倍する。
/// 色は板の真鍮の段（#FFF1C4・#F2DFAE・#C9A66B・#8A6B39・#7E6438・#6E5630）と黒い面（#2C2C30 → #101012 → #050506）
struct TrunkCoinGeometry: Equatable {
    /// 正面から見た直径（pt）
    let size: Double
    /// 手前へ倒した角度（度）。0 は正面（真円）
    let tilt: Double

    init(size: Double, tilt: Double = 0) {
        self.size = max(1, size)
        self.tilt = min(80, max(0, tilt))
    }

    /// 描く量の段
    enum Tier: Int, Comparable {
        /// 14〜23pt: 縁、黒い面、太い星、真ん中の点
        case small
        /// 24〜31pt: ギザ、明暗の星、留め、内輪、北の印
        case medium
        /// 32pt〜: 縁の目盛り 24 本
        case large

        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    /// 段の境（案の頁: 24 未満は星だけ、32 以上で目盛り）
    static let mediumFrom: Double = 24
    static let largeFrom: Double = 32

    var tier: Tier {
        if size >= Self.largeFrom { return .large }
        if size >= Self.mediumFrom { return .medium }
        return .small
    }

    /// 100 の箱から pt への倍率
    var scale: Double { size / 100 }

    // MARK: 100 の箱の中の寸法（案の頁の `coin('hole', …)`）

    /// 黒い面の半径（縁の内側）
    static let faceRadius: Double = 40
    /// 縁の外の暗い線の太さ（小さいほど太く・案の頁 small 3、ほか 2）
    var outlineWidth: Double { tier == .small ? 3 : 2 }
    /// 縁のギザ（72 本・5° ごと・45.5〜49.5）。小さい段は描かない
    var knurlCount: Int { tier == .small ? 0 : 72 }
    static let knurlInner: Double = 45.5
    static let knurlOuter: Double = 49.5
    /// 内輪（半径 34 の真鍮の線と 31.5 の淡い線）。小さい段は描かない
    var showsInnerRing: Bool { tier >= .medium }
    static let innerRing: Double = 34
    /// 縁の北の印（上の小さな三角）
    var showsNorthMark: Bool { tier >= .medium }
    /// 縁の目盛り（24 本・15° ごと・6 本ごとに太く長い）
    var tickCount: Int { tier == .large ? 24 : 0 }

    /// 目盛り1本の内側の半径（6本ごとに長い: 34、ほかは 36.5。外はどれも 39）
    static func tickInner(_ i: Int) -> Double { i % 6 == 0 ? 34 : 36.5 }
    static let tickOuter: Double = 39
    static func tickWidth(_ i: Int) -> Double { i % 6 == 0 ? 1.6 : 1 }

    /// 4方向の尖った星（北・東・南・西に長さ `length`、腰の幅 `waist`、`rotation` 度回して `opacity` で重ねる）
    struct Star: Equatable {
        let length: Double
        let waist: Double
        let rotation: Double
        let opacity: Double
    }

    /// 面ごとに明暗をつけた腕1本（中心から `length`、根元の半幅 `width`、向き `angle` 度・北が 0）。
    /// 左の面は明るく（#FFF1C4・斜めは #E2C687）、右の面は暗く（#8A6B39・斜めは #7A5E30）
    struct Arm: Equatable {
        let length: Double
        let width: Double
        let angle: Double
        /// 東西南北の腕（明暗の色が明るい組）
        var cardinal: Bool { Int(angle) % 90 == 0 }
    }

    /// 下に薄く重ねる斜めの星（どの段も・長さ 17、腰 3、45° 回して 55%）
    static let backStar = Star(length: 17, waist: 3, rotation: 45, opacity: 0.55)

    /// 小さい段の星（太い1つ・長さ 30、腰 5.5）。中と大は明暗の腕（`arms`）で描くので nil
    var flatStar: Star? { tier == .small ? Star(length: 30, waist: 5.5, rotation: 0, opacity: 1) : nil }

    /// 中と大の腕: 斜めの4つ（長さ 19・半幅 3.6）を下に、東西南北（北 37・ほか 30、半幅 5.8）を上に
    var arms: [Arm] {
        guard tier != .small else { return [] }
        let diagonal = (0..<4).map { Arm(length: 19, width: 3.6, angle: 45 + Double($0) * 90) }
        let cardinal = (0..<4).map { Arm(length: $0 == 0 ? 37 : 30, width: 5.8, angle: Double($0) * 90) }
        return diagonal + cardinal
    }

    /// 星の頂点（100 の箱・北から時計回りに 8 点）
    static func starPoints(_ star: Star) -> [(x: Double, y: Double)] {
        let raw: [(Double, Double)] = [(0, -star.length), (star.waist, -star.waist), (star.length, 0), (star.waist, star.waist),
                                       (0, star.length), (-star.waist, star.waist), (-star.length, 0), (-star.waist, -star.waist)]
        let r = star.rotation * .pi / 180
        return raw.map { p in (50 + p.0 * cos(r) - p.1 * sin(r), 50 + p.0 * sin(r) + p.1 * cos(r)) }
    }

    /// 真ん中の留め（中と大は真鍮の丸 4.6 に黒い点 1.6、小さい段は黒い点 3 だけ）
    var hubRadius: Double { tier == .small ? 0 : 4.6 }
    var pinRadius: Double { tier == .small ? 3 : 1.6 }

    // MARK: 倒したとき・影

    /// 縦の潰れ（cos）。正面は 1、倒すほど楕円になる
    var squash: Double { cos(tilt * .pi / 180) }
    /// 倒したときに下に見える厚みの帯（直径の 8% × sin）
    var edgeDepth: Double { size * 0.08 * sin(tilt * .pi / 180) }
    /// 描いたときの枠の高さ
    var drawnHeight: Double { size * squash + edgeDepth }
    /// 落とす影（20pt を超える硬貨だけ・小さな印は行の字と並ぶので落とさない）
    var shadowRadius: Double { size > 20 ? max(1.5, size * 0.06) : 0 }
    var shadowY: Double { size > 20 ? max(1.5, size * 0.05) : 0 }
}

/// 重ねた硬貨（カプセルの機械の数の行・案「持っている数の出し方」）。手元の枚数だけ倒した硬貨を重ね（5枚まで描き、
/// 数は字で）、0枚は白 10% の影絵1枚（持っていない部品の影と同じ決まり `TrunkPartsBoxText.missingShadowOpacity`）
enum TrunkCoinStack {
    /// 描く最多の枚数
    static let maxDrawn = 5
    /// 倒す角度（案の頁の `scale(1, 0.5)` ＝ cos 60°）
    static let tilt: Double = 60

    /// 描く枚数（0枚でも影絵を1枚描く）
    static func drawn(_ coins: Int) -> Int { max(1, min(maxDrawn, coins)) }

    /// 1枚ずつの上下のずれ（直径の 13%）
    static func step(size: Double) -> Double { size * 0.13 }

    /// 重ねた全体の高さ（倒した1枚の高さ＋ずれ）
    static func height(coins: Int, size: Double) -> Double {
        TrunkCoinGeometry(size: size, tilt: tilt).drawnHeight + step(size: size) * Double(drawn(coins) - 1)
    }

    /// i 枚目（下から）の左のずれ（互い違いに 1.5pt・案の頁）
    static func xShift(_ i: Int) -> Double { i % 2 == 1 ? 1.5 : 0 }

    /// 影絵で描くか（0枚）
    static func isEmpty(_ coins: Int) -> Bool { coins <= 0 }
}
