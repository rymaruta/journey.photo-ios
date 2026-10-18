import Foundation

// 旅のトランクのラベルの**決まった描き方**（モック Label.dc.html・Labels.dc.html・2026-10-17）。
//
// サーバーは絵を持たない。届くのは `kind`・`place`・`season`・`timeslot`・`milestone`・`seed`・`foil`
// だけで、**同じ入力なら必ず同じ絵**になるよう、ここで形・色・絵・文字・傾き・刷りのずれを決める。
// 乱数は `seed` と土地の名前から作る自前の式（`TrunkRandom`）で、端末・OS の版・起動ごとに変わらない
// （Swift の `Hasher` は起動ごとに種が変わるので使わない）。
//
// 寸法の計算（縁の太さ・字の大きさ・余白・めくれ）もモックの式のまま持つ。画面は
// `Features/Trunk/TrunkLabelView.swift` がここの値で描くだけ。

// MARK: - 乱数（決まった並び）

/// 種から決まる乱数（SplitMix64）。**どの端末でも同じ並び**
struct TrunkRandom {
    private var state: UInt64

    init(seed: Int, salt: String) {
        state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 ^ Self.fnv1a(salt)
    }

    /// FNV-1a（64bit）。文字は UTF-8 のバイトで数える
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<n
    mutating func int(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        return Int(next() % UInt64(n))
    }

    /// 0 以上 1 未満
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func pick<T>(_ list: [T]) -> T {
        list[int(list.count)]
    }
}

// MARK: - 形と絵

/// ラベルの形（モックの10種）
enum TrunkLabelShape: String, CaseIterable {
    case oval, circle, rect, ticket, shield, diamond, hexagon, octagon, banner, burst

    /// 見本の大きさ（モック Labels の `size`）。形ごとの縦横の比はこれで決める
    var specimen: (w: Double, h: Double) {
        switch self {
        case .circle: return (96, 96)
        case .burst: return (98, 98)
        case .hexagon: return (90, 92)
        case .diamond: return (96, 96)
        case .octagon: return (92, 92)
        case .shield: return (124, 96)
        case .banner: return (138, 80)
        case .ticket: return (136, 82)
        case .oval: return (140, 92)
        case .rect: return (132, 86)
        }
    }

    /// 縦横の比を保って、枠（`maxWidth`×`maxHeight`）に収めた大きさ
    func fitted(maxWidth: Double, maxHeight: Double) -> (w: Double, h: Double) {
        let s = specimen
        let k = min(maxWidth / s.w, maxHeight / s.h)
        return ((s.w * k * 10).rounded() / 10, (s.h * k * 10).rounded() / 10)
    }

    /// 字の左右の余白（幅に対する割合・モックの `padX`）
    var padX: Double {
        switch self {
        case .diamond: return 0.24
        case .hexagon: return 0.14
        case .octagon: return 0.1
        case .oval: return 0.13
        case .circle: return 0.14
        case .burst: return 0.16
        case .banner: return 0.12
        case .shield: return 0.08
        case .ticket: return 0.12
        case .rect: return 0.08
        }
    }

    /// 輪郭の形の種類
    enum Outline: Equatable {
        /// 楕円（`border-radius: 50%`）
        case ellipse
        /// 角丸の四角（角の半径は pt で固定）
        case rounded(Double)
        /// 多角形（0〜1 の割合の頂点・`clip-path: polygon`）
        case polygon([Point])
    }

    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    var outline: Outline {
        func poly(_ pts: [(Double, Double)]) -> Outline { .polygon(pts.map { Point(x: $0.0, y: $0.1) }) }
        switch self {
        case .oval, .circle: return .ellipse
        case .rect: return .rounded(3)
        case .ticket: return .rounded(4)
        case .shield: return poly([(0, 0), (1, 0), (1, 0.62), (0.5, 1), (0, 0.62)])
        case .diamond: return poly([(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)])
        case .hexagon: return poly([(0.25, 0), (0.75, 0), (1, 0.5), (0.75, 1), (0.25, 1), (0, 0.5)])
        case .octagon: return poly([(0.3, 0), (0.7, 0), (1, 0.3), (1, 0.7), (0.7, 1), (0.3, 1), (0, 0.7), (0, 0.3)])
        case .banner: return poly([(0, 0), (1, 0), (0.93, 0.5), (1, 1), (0, 1), (0.07, 0.5)])
        case .burst: return .polygon(Self.burstPoints)
        }
    }

    /// 星形の切手の縁（28 の山・半径 50% と 46% を交互・モックの `burst()`）
    static let burstPoints: [Point] = (0..<56).map { i in
        let r = i % 2 == 1 ? 0.46 : 0.50
        let t = Double.pi * Double(i) / 28
        return Point(x: 0.5 + r * cos(t), y: 0.5 + r * sin(t))
    }
}

/// ラベルの絵（モック Label の 22 種。120×48 の枠に描く）
enum TrunkLabelArt: String, CaseIterable {
    case fuji, pagoda, wave, sun, skyline, snow, aurora, plane, ship, train, torii
    case sakura, maple, lighthouse, moon, star, firework, rain, fog, cloud, camera, globe
}

// MARK: - 1枚の図柄

/// 1枚の図柄（モックの `spec`）
struct TrunkLabelSpec: Equatable {
    let shape: TrunkLabelShape
    /// 紙の地・刷りの色・差し色（`#RRGGBB`）
    let bg: TrunkRGBA
    let fg: TrunkRGBA
    let ac: TrunkRGBA
    /// 上の欧文（字間を空けた大文字）・真ん中の土地の名前・下の小さい行
    let t1: String
    let t2: String
    let t3: String
    let art: TrunkLabelArt?
    /// 置いたときの傾き（度）
    let rot: Double
    /// 刷りのずれの強さ（0〜1・モックの `misreg`）
    let misreg: Double
    /// 箔押し（金の地）
    let foil: Bool

    func rotated(_ degrees: Double) -> TrunkLabelSpec {
        TrunkLabelSpec(shape: shape, bg: bg, fg: fg, ac: ac, t1: t1, t2: t2, t3: t3, art: art,
                       rot: degrees, misreg: misreg, foil: foil)
    }
}

enum TrunkLabelDesign {

    // MARK: 色の組（モック Labels・Main・Pocket・Reroll の見本から）

    struct Palette: Equatable {
        let bg: UInt32
        let fg: UInt32
        let ac: UInt32
    }

    private static func p(_ bg: UInt32, _ fg: UInt32, _ ac: UInt32) -> Palette { Palette(bg: bg, fg: fg, ac: ac) }

    static let palettes: [String: [Palette]] = [
        "spring": [p(0xF3E6CC, 0x8E2A22, 0xD98A7E), p(0x6F5A8E, 0xF3EAF7, 0xE9C8F2), p(0x1C1830, 0xF6D6DE, 0xF2A7B8)],
        "summer": [p(0xE4EDD6, 0x2F5A33, 0x7FB069), p(0x5C4C8C, 0xF4EEDC, 0xB79BE0), p(0xF6F0E2, 0x0F6E7A, 0xE4A23C)],
        "autumn": [p(0x9C3A1E, 0xF6E2B8, 0xF2B33D), p(0xEDE4D0, 0x2F4A3A, 0xC7652F), p(0xD29A3C, 0x2B1A0C, 0xB3261E)],
        "winter": [p(0xE9EEF2, 0x2A3B4E, 0x7FA6C9), p(0xF2EEE4, 0x22405E, 0x7FA6C9), p(0x2C4A5E, 0xF2E6CC, 0xF2E6CC),
                   p(0x21354F, 0xF3EBDD, 0x9CC3E6), p(0xEFE8DA, 0x7A1F2B, 0x7FA6C9)],
        "dawn": [p(0xF2D9C4, 0x5A2A3A, 0xE07A4A), p(0xBFD3D6, 0x1C3A44, 0xE07A4A), p(0x2A3A5A, 0xF2E6CC, 0xE9EEF2)],
        "dusk": [p(0xE2803C, 0x3A140C, 0xF7D27A), p(0xE3B23C, 0x6A1E14, 0xB3261E), p(0xF4F1EA, 0x1F4E8C, 0x5B8FC9)],
        "night": [p(0x141B30, 0xE7C77A, 0xE7C77A), p(0x20253A, 0xE7C77A, 0xE7C77A), p(0x1B2A44, 0xEFE3C8, 0xE06A4A),
                  p(0x2A1414, 0xE7C77A, 0xE7C77A), p(0x1A1F3A, 0xF1C76A, 0xF1C76A)],
        "milestone": [p(0xF3E6CC, 0x2B1A0C, 0xC8352A), p(0x1F3A5A, 0xF2E6CC, 0xE7B85A), p(0x5A1F2B, 0xF2E6CC, 0xE7B85A),
                      p(0x2E5D50, 0xF0E6CE, 0xE7C77A)],
        "home": [p(0xF3E6CC, 0x2B3A2E, 0xB3261E), p(0x1B2A44, 0xEFE3C8, 0xE06A4A), p(0xEDE4D0, 0x2F4A3A, 0xC7652F),
                 p(0xBFD3D6, 0x1C3A44, 0xE07A4A), p(0xF2EADB, 0x20406A, 0xC8503A), p(0x20253A, 0xE7C77A, 0xE7C77A),
                 p(0xF6F0E2, 0x0F6E7A, 0xE4A23C), p(0xD29A3C, 0x2B1A0C, 0xB3261E), p(0x2E5D50, 0xF0E6CE, 0xE7C77A)],
        "abroad": [p(0x8C2F2B, 0xF2E6CC, 0xE7C77A), p(0x1E3A55, 0xEFE3C8, 0xE7B85A), p(0xE3B23C, 0x6A1E14, 0xB3261E),
                   p(0xF4F1EA, 0x1F4E8C, 0x5B8FC9), p(0x253A52, 0xE6F2F4, 0x7FE0A8), p(0xE9E2D2, 0x1A1A1A, 0xC8352A),
                   p(0x2E4E5E, 0xF0E2C2, 0xE7B85A), p(0x3B2E5A, 0xD8F0E0, 0x7FE0A8)],
    ]

    /// 箔押しの色（モック Labels の「箔押し」: 地 #3A2A12・字 #3A2410・差し色 #FFF1C4）
    static let foilPalette = p(0x3A2A12, 0x3A2410, 0xFFF1C4)

    // MARK: 絵の組

    static let arts: [String: [TrunkLabelArt]] = [
        "spring": [.sakura, .torii, .fuji],
        "summer": [.sun, .wave, .lighthouse, .firework],
        "autumn": [.maple, .pagoda, .torii],
        "winter": [.snow, .moon, .train],
        "dawn": [.fuji, .sun, .cloud],
        "dusk": [.sun, .wave, .ship],
        "night": [.moon, .skyline, .firework],
        "first": [.camera],
        "count": [.star],
        "firstCountry": [.globe, .plane],
        "home": [.pagoda, .torii, .fuji, .ship, .train, .lighthouse, .wave, .cloud, .fog],
        "abroad": [.skyline, .ship, .lighthouse, .sun, .wave, .plane, .aurora, .rain],
    ]

    /// 日本の土地か（国名が無いか「日本」）。国内と海外で色と絵の組を分ける
    static func isHome(_ place: TrunkLabel.Place) -> Bool {
        guard let country = place.country else { return true }
        return country == "日本" || country.lowercased() == "japan"
    }

    /// 色と絵の組の名前（季節・時刻・節目・土地）
    static func theme(_ label: TrunkLabel) -> (palette: String, art: String) {
        switch label.kind {
        case .milestone:
            switch label.milestone {
            case .first: return ("milestone", "first")
            case .firstCountry: return ("milestone", "firstCountry")
            case .posts10, .posts50, .posts100: return ("milestone", "count")
            case nil: break
            }
        case .timeslot:
            if let t = label.timeslot { return (t.rawValue, t.rawValue) }
        case .season:
            if let s = label.season { return (s.rawValue, s.rawValue) }
        case .place:
            break
        }
        let home = isHome(label.place) ? "home" : "abroad"
        return (home, home)
    }

    // MARK: 文字

    static func seasonWords(_ s: TrunkLabel.Season) -> (en: String, ja: String) {
        switch s {
        case .spring: return ("SPRING", "春")
        case .summer: return ("SUMMER", "夏")
        case .autumn: return ("AUTUMN", "秋")
        case .winter: return ("WINTER", "冬")
        }
    }

    static func timeslotWords(_ t: TrunkLabel.Timeslot) -> (en: String, ja: String) {
        switch t {
        case .dawn: return ("DAWN", "夜明け")
        case .dusk: return ("SUNSET", "夕焼け")
        case .night: return ("NIGHT", "夜")
        }
    }

    static func milestoneWords(_ m: TrunkLabel.Milestone) -> (en: String, ja: String) {
        switch m {
        case .first: return ("FIRST", "はじめて")
        case .posts10: return ("TEN", "10 枚目")
        case .posts50: return ("FIFTY", "50 枚目")
        case .posts100: return ("HUNDRED", "100 枚目")
        case .firstCountry: return ("NEW COUNTRY", "はじめての国")
        }
    }

    /// 季節・時刻の言葉（どちらも無ければ nil）。時刻を先に見る（kind が時刻のとき）
    static func moment(_ label: TrunkLabel) -> (en: String, ja: String)? {
        if label.kind != .season, let t = label.timeslot { return timeslotWords(t) }
        if let s = label.season { return seasonWords(s) }
        if let t = label.timeslot { return timeslotWords(t) }
        return nil
    }

    /// ラベルの3行（上の欧文・土地の名前・下の行）。**紙に刷った文字なので、画面の言語で変えない**
    static func texts(_ label: TrunkLabel) -> (t1: String, t2: String, t3: String) {
        let name = label.place.name
        let latin = label.place.latin?.uppercased()
        if label.kind == .milestone, let m = label.milestone {
            let words = milestoneWords(m)
            let below: String
            switch m {
            case .first: below = name.isEmpty ? "MY FIRST PHOTO" : name
            case .posts10, .posts50, .posts100: below = "PHOTOS"
            case .firstCountry: below = label.place.country ?? (name.isEmpty ? "AROUND THE WORLD" : name)
            }
            return (words.en, words.ja, below)
        }
        let moment = moment(label)
        let t2 = name.isEmpty ? (moment?.ja ?? "旅の記録") : name
        let t1 = latin ?? moment?.en ?? "JOURNEY"
        let t3: String
        if let moment {
            t3 = "\(moment.en) · \(moment.ja)"
        } else if let country = label.place.country, country != name {
            t3 = country
        } else {
            t3 = "JOURNEY PHOTO"
        }
        return (t1, t2, t3)
    }

    /// 一覧の札の下の短い説明（モック Main の「京都 · 桜」）と読み上げ
    static func caption(_ label: TrunkLabel) -> String {
        let name = label.place.name
        var theme: String?
        if label.kind == .milestone, let m = label.milestone { theme = milestoneWords(m).ja }
        else { theme = moment(label)?.ja }
        switch (name.isEmpty, theme) {
        case (false, let theme?): return "\(name) · \(theme)"
        case (false, nil): return name
        case (true, let theme?): return theme
        case (true, nil): return L("旅の記録", "Travel log")
        }
    }

    static func accessibilityLabel(_ label: TrunkLabel) -> String {
        let base = L("\(caption(label))のラベル", "\(caption(label)) label")
        return label.foil ? base + L("（箔押し）", " (gold foil)") : base
    }

    /// 刷った日（`2026.04.03`）。届いた画面の大きいラベルの下の行
    static func serial(_ label: TrunkLabel) -> String? {
        guard let d = label.day else { return nil }
        return String(format: "%04d.%02d.%02d", d.year, d.month, d.day)
    }

    // MARK: 図柄を決める

    /// **同じラベル（同じ種）なら必ず同じ図柄。** 作り直しは種だけが替わる
    static func spec(for label: TrunkLabel) -> TrunkLabelSpec {
        var random = TrunkRandom(seed: label.seed, salt: "\(label.kind.rawValue)|\(label.place.name)")
        let theme = theme(label)
        let shape = random.pick(TrunkLabelShape.allCases)
        let palette = random.pick(palettes[theme.palette] ?? palettes["home"]!)
        let art = random.pick(arts[theme.art] ?? arts["home"]!)
        // 傾きは -7〜7 度・刷りのずれは 0.2〜1
        let rot = Double(random.int(15) - 7)
        let misreg = 0.2 + (random.unit() * 0.8 * 100).rounded() / 100
        // 100 枚目は箔押しの節目（モック Labels の見本）
        let foil = label.foil || label.milestone == .posts100
        let colors = foil ? foilPalette : palette
        let text = texts(label)
        return TrunkLabelSpec(shape: shape, bg: TrunkRGBA(colors.bg), fg: TrunkRGBA(colors.fg), ac: TrunkRGBA(colors.ac),
                              t1: text.t1, t2: text.t2, t3: text.t3, art: art, rot: rot, misreg: misreg, foil: foil)
    }
}

// MARK: - 寸法（モック Label の計算）

/// 1枚を `w`×`h` で描くときの寸法。**モックの式のまま**（縁・字の大きさ・余白・めくれ・褪せ）
struct TrunkLabelLayout: Equatable {
    let w: Double
    let h: Double
    let spec: TrunkLabelSpec
    /// 古び（0〜1）
    let age: Double

    init(w: Double, h: Double, spec: TrunkLabelSpec, age: Double = 0) {
        self.w = w
        self.h = h
        self.spec = spec
        self.age = max(0, min(1, age))
    }

    /// 外の刷りの縁の太さ（モックの `b1`）
    var border1: Double { max(1.5, ((min(w, h) * 0.035 * 10).rounded()) / 10) }
    /// 内の縁の位置（`b2 = b1 * 2 + 1`）
    var border2: Double { border1 * 2 + 1 }
    /// 内の紙の位置（`b2 + max(0.8, b1 * 0.4)`）
    var innerPaper: Double { border2 + max(0.8, border1 * 0.4) }

    var padX: Double { w * spec.shape.padX }
    /// 盾形だけ下を空ける（尖りに字がかからないように）
    var padBottom: Double { spec.shape == .shield ? h * 0.22 : 0 }
    var innerWidth: Double { w * (1 - spec.shape.padX * 2) }

    /// JavaScript の `length`（UTF-16 の数）
    private func jsLength(_ s: String) -> Double { Double(s.utf16.count) }

    var t2Size: Double {
        let len = max(2, jsLength(spec.t2))
        var size = min(h * (spec.art != nil ? 0.19 : 0.25), (innerWidth / len) * 0.96)
        if spec.shape == .diamond { size *= 0.85 }
        return size
    }

    var t1Size: Double { max(3.5, min(h * 0.075, innerWidth / max(4, jsLength(spec.t1)) * 1.25)) }
    var t3Size: Double { max(3.5, min(h * 0.064, innerWidth / max(6, jsLength(spec.t3)) * 1.5)) }
    var serialSize: Double { max(3.5, h * 0.055) }

    var artHeight: Double { h * (spec.shape == .diamond ? 0.2 : 0.27) }
    var artWidth: Double { innerWidth * 0.78 }
    var artGap: Double { h * 0.025 }

    /// 刷りのずれ（真ん中の字の影の向き・pt）
    var misregistration: Double { (0.4 + spec.misreg) * max(0.6, h / 120) }

    /// 字と字の間（モックの margin-top）
    var t2Top: Double { h * 0.012 }
    var t3Top: Double { h * 0.02 }
    var serialTop: Double { h * 0.03 }

    /// 落ちる影（`drop-shadow(0 h*0.03 h*0.05 rgba(0,0,0,0.55))`）
    var shadowY: Double { h * 0.03 }
    var shadowBlur: Double { h * 0.05 }

    /// 切符の左右の切り欠きの半径
    var ticketNotch: Double { h * 0.09 }

    /// 褪せ（`saturate(1 - age*0.4) sepia(age*0.32) brightness(1 - age*0.05)`）
    func faded(_ color: TrunkRGBA) -> TrunkRGBA {
        guard age > 0 else { return color }
        return color.filtered(saturate: 1 - age * 0.4, sepia: age * 0.32, brightness: 1 - age * 0.05)
    }

    /// 端のめくれ（古びが 0.45 を越えたら・右下の三角）
    var showsCurl: Bool { age > 0.45 }
    var curlSize: Double { min(w, h) * 0.16 }
    /// めくれの位置（楕円・円は内側に寄せる）
    var curlInset: (right: Double, bottom: Double) {
        spec.shape == .oval || spec.shape == .circle ? (w * 0.12, h * 0.1) : (0, 0)
    }
}
