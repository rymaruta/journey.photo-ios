import Foundation

/// 乗車券の券面（**2026-10-17 owner が確定**・Artifact「特別な乗車券 10案」`Main.dc.html` の「· 確定」の5つ）。
///
/// - 既定はマルス券（`mars`）。ほかの5つは **Pro の人だけ**が選べる
/// - 選んだ券面は電波の中身（`PassExchange.Payload.face`）に1バイトで載せる。番号は**電波の番号**で、
///   一度出したら変えない（前の版のアプリが送った番号を、後の版が別の券面と読み違えない）
/// - 受け取った側は、送った人の**公開プロフィールの Pro の印**（`UserProfile.isPro`）を見て、Pro なら選んだ券面、
///   そうでなければマルス券で見せる（`shown(wire:ownerIsPro:)`）。番号を自分で書き換えた端末からでも、Pro でない人の
///   券面は特別にならない
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum PassTicketFaceStyle: UInt8, CaseIterable, Identifiable, Codable {
    /// マルス券（既定・2026-10-17 owner「マルス券いいね」）
    case mars = 0
    /// 01 真鍮の金属板
    case brassPlate = 1
    /// 06 大圏航路
    case greatCircle = 2
    /// 10 箔押しの硬券
    case foilHard = 3
    /// 21 漆と蒔絵
    case urushi = 4
    /// 26 型押しの革
    case leather = 5

    var id: UInt8 { rawValue }

    /// Pro だけが選べるか
    var needsPro: Bool { self != .mars }

    /// 選ぶ画面と読み上げの名前
    var name: String {
        switch self {
        case .mars: return L("マルス券", "Classic")
        case .brassPlate: return L("真鍮の金属板", "Brass plate")
        case .greatCircle: return L("大圏航路", "Great circle")
        case .foilHard: return L("箔押しの硬券", "Foil-stamped")
        case .urushi: return L("漆と蒔絵", "Urushi lacquer")
        case .leather: return L("型押しの革", "Embossed leather")
        }
    }

    /// 傾けると光が動く券面か（マルス券は回したときの縁の光だけ・`SpinMotion.shine`）
    var followsTilt: Bool {
        switch self {
        case .mars, .greatCircle: return false
        case .brassPlate, .foilHard, .urushi, .leather: return true
        }
    }

    /// 読み上げで表の頭に添える言葉（例「乗車券、券面は真鍮の金属板」）。マルス券は前と同じ（何も足さない）
    func spokenHeadline(_ headline: String) -> String {
        guard self != .mars else { return headline }
        return L("\(headline)、券面は\(name)", "\(headline), \(name) design")
    }

    /// 電波の番号から。**知らない番号（後の版の券面）はマルス券**
    static func fromWire(_ value: UInt8?) -> PassTicketFaceStyle {
        guard let value, let style = PassTicketFaceStyle(rawValue: value) else { return .mars }
        return style
    }

    /// 受け取ったカードで見せる券面。**送った人が Pro だと確かめられたときだけ**選んだ券面
    /// （プロフィールが読めない・Pro でない・番号が無い・知らない番号 → マルス券）
    static func shown(wire: UInt8?, ownerIsPro: Bool?) -> PassTicketFaceStyle {
        guard ownerIsPro == true else { return .mars }
        return fromWire(wire)
    }

    /// 自分の見本で見せる券面。**Pro をやめたらマルス券**（選んだ値は設定に残す・また Pro になれば戻る）
    static func own(chosen: UInt8?, isPro: Bool?) -> PassTicketFaceStyle {
        shown(wire: chosen, ownerIsPro: isPro)
    }

    /// 選ぶ画面の並び（マルス券が先・モックの番号の順）
    static var pickerOrder: [PassTicketFaceStyle] { [.mars, .brassPlate, .greatCircle, .foilHard, .urushi, .leather] }
}

/// 傾き（と回し）から決める光の位置（モックの「マウスで傾けて見る」の x・y。0〜1・0.5 が正面）。
///
/// 2026-10-17 判断: 端末の重力（CoreMotion の `gravity`）の左右（x）と、見始めた時からの前後（y）の差で動かす。
/// 「視差効果を減らす」では動かさない（いつも正面 0.5）
enum PassFaceLight {

    /// 正面
    static let center = 0.5
    /// 重力の 1 に対する光の動き（0.31 ≒ 18° 傾けると端まで）
    static let gain = 1.6
    /// これより小さい動きは描き直さない（30 回/秒の知らせを間引く）
    static let minStep = 0.01

    struct Point: Equatable {
        var x: Double
        var y: Double
        static let center = Point(x: PassFaceLight.center, y: PassFaceLight.center)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    /// 重力から光の位置。`baselineY` は見始めた時の前後の重力（持ち方の差をならす）
    static func point(gravityX: Double, gravityY: Double, baselineY: Double) -> Point {
        Point(x: clamp(center + gravityX * gain), y: clamp(center - (gravityY - baselineY) * gain))
    }

    /// 描き直すほど動いたか
    static func needsUpdate(from old: Point, to new: Point) -> Bool {
        abs(old.x - new.x) >= minStep || abs(old.y - new.y) >= minStep
    }

    /// いま描く光: 「視差効果を減らす」なら正面。指で回している間（`shine` が 0〜1）は回りに合わせ、
    /// それ以外は傾き
    static func resolved(tilt: Point, shine: Double?, reduceMotion: Bool) -> Point {
        if reduceMotion { return .center }
        if let shine, shine >= 0, shine <= 1 { return Point(x: shine, y: tilt.y) }
        return tilt
    }

    /// CSS の `linear-gradient(<deg>)` の向きを、四角の中の始点と終点（0〜1）にする。0° が上・90° が右
    static func gradientPoints(cssDegrees: Double) -> (start: Point, end: Point) {
        let r = cssDegrees * .pi / 180
        let dx = sin(r) / 2, dy = -cos(r) / 2
        return (Point(x: center - dx, y: center - dy), Point(x: center + dx, y: center + dy))
    }

    /// 光の帯（中心 `center`・半幅 `half`・0〜1 は札の幅に対する割合）を、CSS の角度 `cssDegrees` の向きに引く
    /// 始点と終点。帯の外はグラデーションの端の色（透明）がそのまま伸びる——**0〜1 の外の位置を色の位置に書かない**
    /// （モックの `transparent p-25%` は p が端に寄ると 0〜1 を越える）
    static func bandPoints(center: Double, half: Double, cssDegrees: Double) -> (start: Point, end: Point) {
        let r = cssDegrees * .pi / 180
        let dx = sin(r) * half, dy = -cos(r) * half
        return (Point(x: center - dx, y: PassFaceLight.center - dy), Point(x: center + dx, y: PassFaceLight.center + dy))
    }

    // MARK: 01 真鍮の金属板（モック `brass`・`sheen`）

    /// 板の向き（135° から左右に ±15°）
    static func brassAngle(_ light: Point) -> Double { 135 + (light.x - center) * 30 }
    /// 板のいちばん明るい所（モック 40% ±15%）。前後の色の位置（0.28・0.62）を越えないよう 0.30〜0.60 に
    static func brassHighlight(_ light: Point) -> Double { min(0.60, max(0.30, 0.40 + (light.x - center) * 0.30)) }

    // MARK: 箔（10・21・26 のモック `foil`）

    /// 箔の光る所（字の左から右へ・モック p%）
    static func foilCenter(_ light: Point) -> Double { light.x }

    // MARK: 21 漆（モック `lacquer`）

    /// 鏡面の光の中心。**写真の上には落とさない**（2026-10-17 判断: モックは写真の上も通るが、写真の映り込みは
    /// 加工にあたる。写真は光の層より上に重ねる）。写真の下の漆の面（高さの 50〜90%）を走らせる
    static func lacquerCenter(_ light: Point) -> Point { Point(x: light.x, y: 0.50 + light.y * 0.40) }
    /// 鏡面の光のいちばん明るい所の濃さ（モック .32）。**字の下を通る**ので、ラベル（#999）が光の上でも
    /// 4.5 を割らない濃さに下げた（`PassFacePalette.pairs` で測る）
    static let lacquerPeak = 0.08
    /// 写真の縁の金の覆輪の光る所（モック `mkStop`・0.05〜0.95）
    static func rimStop(_ light: Point) -> Double { min(0.95, max(0.05, light.x)) }

    // MARK: 26 革（モック `az`・`el`）

    /// 左から当たる光の重み（0 で右から・1 で左から）。しぼの陰影の2枚を混ぜる
    static func leatherFromLeft(_ light: Point) -> Double { 1 - light.x }
}

/// 06 大圏航路の形（モックの SVG 300×120 の座標）。**実際の地図や座標は描かない**——発と着は札だけ、弧は形として
enum PassGreatCircle {
    static let size = (width: 300.0, height: 120.0)
    /// 弧（発 → 着）: M262 78 C 210 6, 90 6, 38 70
    static let start = (x: 262.0, y: 78.0)
    static let control1 = (x: 210.0, y: 6.0)
    static let control2 = (x: 90.0, y: 6.0)
    static let end = (x: 38.0, y: 70.0)
    /// 光が弧を一周する長さ（モック 4 秒）
    static let period = 4.0

    /// 下の区間（明朝 20・下限 13）の大きさ: 発・着の名と「発」「着」・「—」が幅 264 に収まる大きさ
    static func routeSize(origin: String, destination: String, width: Double = 264) -> Double {
        let ems = PassCardStyle.routeEms(origin) + PassCardStyle.routeEms(destination)
        let marks = PassCardStyle.markWidth(origin: PassTicket.originMark, destination: PassTicket.destinationMark) * 2
        // 「—」と前後のすき間（12pt の字 1 つ＋ 3 × 4）
        let room = width - marks - 24
        guard ems > 0 else { return 20 }
        return min(20, max(PassCardStyle.routeMinSize, room / ems))
    }

    /// 弧の上の点（t は 0〜1）
    static func point(_ t: Double) -> (x: Double, y: Double) {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return (a * start.x + b * control1.x + c * control2.x + d * end.x,
                a * start.y + b * control1.y + c * control2.y + d * end.y)
    }

    /// 時刻から光の位置（0〜1）。「視差効果を減らす」では動かさない（弧の中ほどに置く）
    static func progress(at seconds: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0.5 }
        let f = (seconds / period).truncatingRemainder(dividingBy: 1)
        return f < 0 ? f + 1 : f
    }

    /// 経緯線（横に5本・たてに5本）: 横は M0 (12+24k) Q150 (24k) 300 (12+24k)、たては M(30+60k) 0 Q(40+60k) 60 (30+60k) 120
    static var parallels: [(from: (Double, Double), control: (Double, Double), to: (Double, Double))] {
        (0..<5).map { k in
            let y = Double(12 + k * 24)
            return ((0, y), (150, Double(k * 24)), (300, y))
        }
    }

    static var meridians: [(from: (Double, Double), control: (Double, Double), to: (Double, Double))] {
        (0..<5).map { k in
            let x = Double(30 + k * 60)
            return ((x, 0), (x + 10, 60), (x, 120))
        }
    }
}

/// 券面の色（モックの値・**文字と地の比は `PassFaceContrastTests` で測って見張る**）。
///
/// 2026-10-17 判断（モックから変えた所・測った比で決めた）:
/// - 箔のいちばん暗い所を #8E6F40 → `accentFill`（#B8955A）。モックの色では 15pt の「乗車券」が革の地で 2.9、
///   漆の地で 3.7 しかなかった
/// - 01 の板の両端を #8E6F40・#8A6A36 → #A3824C。墨の字が端で 4.0 しかなかった。小さな字の薄さ（モック 0.7）は 0.85 に
enum PassFacePalette {
    // 01 真鍮の金属板
    static let brassEdge: UInt32 = 0xA3824C
    static let brassMid: UInt32 = 0xC9A66B
    static let brassLight: UInt32 = 0xF3DCA6
    static let brassInk: UInt32 = BrandPalette.ink
    /// 小さな字（ラベル・ずっと有効）の墨の濃さ
    static let brassSmallInkOpacity = 0.85

    // 06 大圏航路
    static let routeGround: UInt32 = 0x0E0D0B
    static let routeLight: UInt32 = 0xF3DCA6

    // 10 箔押しの硬券
    static let paper: UInt32 = 0x121110

    // 箔（10・21・26）
    static let foilDark: UInt32 = BrandPalette.accentFill
    static let foilMid: UInt32 = BrandPalette.accent
    static let foilLight: UInt32 = 0xFFF1CC

    // 21 漆と蒔絵
    static let lacquerTop: UInt32 = 0x2A1410
    static let lacquerMid: UInt32 = 0x0F0605
    static let lacquerDeep: UInt32 = 0x030101
    static let rimDark: UInt32 = 0x7A5A2E
    static let rimLight: UInt32 = 0xFFF4D6
    static let goldDust: UInt32 = 0xFFDB8C
    /// 鏡面の光（モック rgba(255,250,240)）
    static let lacquerGlint: UInt32 = 0xFFFAF0

    // 26 型押しの革（モックの今の版の色）
    static let leather: UInt32 = 0x3A2A1E
    static let leatherShade: UInt32 = 0x241911
    static let leatherLabel: UInt32 = 0xBFA98F
    static let leatherValue: UInt32 = 0xE6D6C2
    static let leatherName: UInt32 = 0xC9B8A2
    static let leatherNumber: UInt32 = 0xD9B878

    // 黒い地の上の字（06・10・21）
    static let text2: UInt32 = BrandPalette.text2
    static let text3: UInt32 = 0x999999

    /// 地に重ねた字の色（`opacity` の濃さで混ぜた色）
    static func mix(_ fg: UInt32, over bg: UInt32, opacity: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        var out: UInt32 = 0
        for s: UInt32 in [16, 8, 0] {
            let v = (ch(fg, s) * opacity + ch(bg, s) * (1 - opacity)).rounded()
            out |= UInt32(max(0, min(255, v))) << s
        }
        return out
    }

    /// 測る組（名前・字・地・要る比）。字の大きさで 4.5（本文）か 3（大きな字＝区間の地名）
    struct Pair {
        let name: String
        let text: UInt32
        let ground: UInt32
        let required: Double
    }

    static var pairs: [Pair] {
        let smallInk = mix(brassInk, over: brassEdge, opacity: brassSmallInkOpacity)
        return [
            Pair(name: "01 墨の字／板の端", text: brassInk, ground: brassEdge, required: 4.5),
            Pair(name: "01 墨の小さな字（0.85）／板の端", text: smallInk, ground: brassEdge, required: 4.5),
            Pair(name: "01 墨の字／板の明るい所", text: brassInk, ground: brassLight, required: 4.5),
            Pair(name: "06 本文（text-2）／地", text: text2, ground: routeGround, required: 4.5),
            Pair(name: "06 眉ラベル（真鍮）／地", text: BrandPalette.accent, ground: routeGround, required: 4.5),
            Pair(name: "10 箔の暗い所／綿紙", text: foilDark, ground: paper, required: 4.5),
            Pair(name: "10 本文（text-2）／綿紙", text: text2, ground: paper, required: 4.5),
            Pair(name: "21 箔の暗い所／漆のいちばん明るい所", text: foilDark, ground: lacquerTop, required: 4.5),
            Pair(name: "21 ラベル（#999）／漆のいちばん明るい所", text: text3, ground: lacquerTop, required: 4.5),
            Pair(name: "21 本文（text-2）／漆のいちばん明るい所", text: text2, ground: lacquerTop, required: 4.5),
            Pair(name: "21 ラベル（#999）／鏡面の光の上", text: text3,
                 ground: mix(lacquerGlint, over: lacquerTop, opacity: PassFaceLight.lacquerPeak), required: 4.5),
            Pair(name: "21 箔の暗い所／鏡面の光の上", text: foilDark,
                 ground: mix(lacquerGlint, over: lacquerTop, opacity: PassFaceLight.lacquerPeak), required: 4.5),
            Pair(name: "26 箔の暗い所／革", text: foilDark, ground: leather, required: 4.5),
            Pair(name: "26 ラベル／革", text: leatherLabel, ground: leather, required: 4.5),
            Pair(name: "26 値／革", text: leatherValue, ground: leather, required: 4.5),
            Pair(name: "26 名前／革", text: leatherName, ground: leather, required: 4.5),
            Pair(name: "26 番号／革", text: leatherNumber, ground: leather, required: 4.5),
        ]
    }
}
