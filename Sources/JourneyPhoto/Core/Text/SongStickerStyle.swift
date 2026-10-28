import Foundation

/// 曲の札の形（2026-10-28・owner「押して替える めっちゃいいね！」）。
///
/// Instagram の曲の札と同じく、**札を押すたびに形が替わる**（A→B→…→F→A）。
/// 見た目・寸法・色はモック「ストーリーの曲の札」（claude.ai/artifact/Ui1h8UFZXmSG2kPR6TM9W3）が正。
/// **写真の上なので真鍮は使わない**（白と黒のガラスだけ・CLAUDE.md）。
///
/// 形は**下書きにだけ残す**（`TextOverlay.songStyle`）。投稿すると画像に焼き込まれるので、
/// サーバーへ送る形は変わらない（`TextOverlayRenderer`）。
enum SongStickerStyle: String, Codable, CaseIterable, Identifiable {
    /// A ガラスの札（既定）。黒 55% の地にジャケット・曲名・歌手・棒
    case glass
    /// B 白い札。白い地に墨の字（暗い写真でいちばん目立つ）
    case white
    /// C 小さな帯。棒と1行だけ（ジャケットなし・写真をほとんど隠さない）
    case pill
    /// D ジャケット大。大きなジャケットの下に曲名
    case sleeve
    /// E レコード。ジャケットを中央の紙にしたレコード（作る画面で回る）
    case disc
    /// F 明朝の題字。地を置かず、明朝の大きな題字で曲名
    case title

    var id: String { rawValue }

    /// 押したら替わる先（F の次は A に戻る）
    var next: SongStickerStyle {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    /// 形の頭文字（モックの A〜F）
    var letter: String {
        switch self {
        case .glass: return "A"
        case .white: return "B"
        case .pill: return "C"
        case .sleeve: return "D"
        case .disc: return "E"
        case .title: return "F"
        }
    }

    var label: String {
        switch self {
        case .glass: return L("ガラスの札", "Glass card")
        case .white: return L("白い札", "White card")
        case .pill: return L("小さな帯", "Small pill")
        case .sleeve: return L("ジャケット大", "Large cover")
        case .disc: return L("レコード", "Record")
        case .title: return L("明朝の題字", "Serif title")
        }
    }

    /// 札が持つジャケットを描くか（C と F は字だけ）
    var showsArtwork: Bool {
        switch self {
        case .pill, .title: return false
        case .glass, .white, .sleeve, .disc: return true
        }
    }

    // MARK: 大きさ（短い辺に対する「歌手の字」の割合・`TextOverlay.size`）

    /// 置いたときの大きさ。3:4 の写真を作る画面に敷くと歌手の字が約 17pt（モックの 11.5px を 390pt に直すと 15pt）
    static let defaultSize = 0.032
    /// 小さくできる下限。**歌手の字が 12pt 相当**（9:16 の写真で 0.03 × 390 ≒ 12pt）
    static let minSize = TextOverlay.minSize
    /// 大きくできる上限。ジャケット大・レコードでも短い辺の8割ほどまで（文字の札の 0.2 は札だと写真を覆う）
    static let maxSize = 0.08
    /// 長い曲名で縮めて収める幅（短い辺に対する割合・文字の札と同じ `SongSticker.fitWidth`）
    static var fitWidth: Double { SongSticker.fitWidth }

    // MARK: 端末に覚える（最後に選んだ形を次のストーリーで最初に出す）

    static let defaultsKey = "story.songSticker.style"

    /// 最後に選んだ形。覚えていなければ A（ガラスの札）
    static func remembered(defaults: UserDefaults = .standard) -> SongStickerStyle {
        defaults.string(forKey: defaultsKey).flatMap(SongStickerStyle.init(rawValue:)) ?? .glass
    }

    static func remember(_ style: SongStickerStyle, defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: defaultsKey)
    }
}

/// 曲の札の**形の寸法**（画面を持たない計算）。
///
/// 🔴 **作る画面（`SongStickerView`）と焼き込み（`TextOverlayRenderer`）が同じこれを通す。**
/// 別々に組むと、投稿した写真の札が作る画面とずれる（文字の札で一度起きた・`TextOverlay.fontSize`）。
/// 寸法の単位 `unit` は**歌手の字の大きさ（px）**＝ `TextOverlay.fontSize(size, in:)`。モックの px を
/// 歌手の字の 11.5px で割った値で持つ（`U.*`）。
///
/// 位置はどれも**札の左上を原点**にした値。焼き込みは札の中心へ移して回してから描く（文字の札と同じ）。
struct SongStickerLayout: Equatable {

    /// 字の種類（描く側が書体に直す: 曲名＝システムの semibold・歌手＝システムの regular・題字＝明朝）
    enum FontRole: Equatable {
        case title, artist, mincho
    }

    /// 字の大きさを測る口。**描く側と同じ書体で測る**（`SongStickerPainter.measure`）。テストは決まった値を返す
    typealias Measure = (String, FontRole, Double) -> CGSize

    struct Run: Equatable {
        var text: String
        var role: FontRole
        /// 字の大きさ（px）
        var pointSize: Double
        /// 字を描く枠（左上・`NSString.draw(at:)` の点と、測った大きさ）
        var frame: CGRect
        /// 0xRRGGBB と不透明度
        var color: UInt32
        var opacity: Double
    }

    /// 影（px）。描く側は `CGContext.setShadow` / SwiftUI の `shadow` に直す
    struct Shadow: Equatable {
        var dy: Double
        var blur: Double
        var opacity: Double
    }

    enum PlateKind: Equatable {
        /// 黒 55% ＋白 12% の縁（板のガラス。焼き込みにはぼかしを掛けない）
        case glass
        /// 白 94%（B）
        case white
    }

    struct Plate: Equatable {
        var rect: CGRect
        var radius: Double
        var kind: PlateKind
        /// 縁の太さ（無ければ 0）と不透明度（白）
        var border: Double
        var borderOpacity: Double
        var shadow: Shadow?
    }

    var style: SongStickerStyle
    var unit: Double
    /// 札の大きさ（影を除く）。押せる範囲と、指の下の札の判定にも使う
    var size: CGSize
    var plate: Plate?
    /// ジャケット（四角）。レコードでは中央の紙（丸・`artworkIsCircle`）
    var artwork: CGRect?
    var artworkRadius: Double = 0
    var artworkIsCircle = false
    /// ジャケットの影（D）
    var artworkShadow: Shadow?
    /// レコードの盤・中央の穴・溝の半径（盤の中心から）
    var disc: CGRect?
    var discShadow: Shadow?
    var hole: CGRect?
    var grooves: [Double] = []
    /// 棒（3本）。**止まった絵の高さ**（焼き込み・動きを減らす設定）。下を揃える
    var bars: [CGRect] = []
    var barColor: UInt32 = 0xFFFFFF
    var texts: [Run] = []
    /// 字の影（D・E・F。地の無い字を写真の上で読ませる）
    var textShadow: Shadow?

    /// 影のために外へ取る余白（画像にするとき・px）
    var bleed: Double { unit * U.bleed }

    // MARK: - 寸法（モックの px ÷ 歌手の字 11.5px）

    enum U {
        static let px = 1.0 / 11.5
        static let bleed = 46 * px
        // A・B（札）
        static let cardPadLeft = 8 * px, cardPadRight = 14 * px, cardPadV = 8 * px
        static let cardJacket = 40 * px, cardJacketRadius = 8 * px, cardGap = 10 * px
        static let cardRadius = 14 * px, cardEqGap = 14 * px
        static let cardTextMax = 10.0
        // 字
        static let titleSize = 13 * px, artistSize = 1.0, lineGap = 1 * px
        // 棒（幅 2.5・間 2・高さ 6/12/8・箱の高さ 12）
        static let barWidth = 2.5 * px, barGap = 2 * px, eqHeight = 12 * px
        static let barHeights = [6 * px, 12 * px, 8 * px]
        static var eqWidth: Double { barWidth * 3 + barGap * 2 }
        // C（小さな帯）
        static let pillPadV = 7 * px, pillPadH = 13 * px, pillFont = 12.5 * px, pillGap = 8 * px
        static let pillTextMax = 14.0
        // D・E（ジャケット大・レコード）
        static let big = 118 * px, bigRadius = 6 * px, bigGap = 9 * px, bigTextMax = 12.0
        static let discLabel = 0.32, hole = 6 * px, groovePeriod = 3.4 * px, grooveLine = 1.4 * px
        // F（明朝の題字）
        static let typeSize = 30 * px, typeGap = 4 * px, typeRowGap = 7 * px, typeArtist = 12 * px
        static let typeTitleMax = 13.0, typeArtistMax = 12.0
    }

    /// 墨（B の字・棒）
    static let ink: UInt32 = 0x07090A

    // MARK: - 組む

    /// 形・曲名・歌手・字の大きさ（px）から寸法を組む。**長い曲名は「…」で切って幅を抑える**
    /// （焼き込みは1行で折り返さない。切らないと札が写真の外まで伸びる）
    static func make(style: SongStickerStyle, title: String, artist: String?, unit: Double,
                     measure: Measure) -> SongStickerLayout {
        let u = max(unit, 0.0001)
        let artist = artist.flatMap { $0.isEmpty ? nil : $0 }
        var layout = SongStickerLayout(style: style, unit: u, size: .zero)
        switch style {
        case .glass, .white:
            let white = style == .white
            let ts = U.titleSize * u, asz = U.artistSize * u
            let t = fit(title, .title, ts, maxWidth: U.cardTextMax * u, measure)
            let a = artist.map { fit($0, .artist, asz, maxWidth: U.cardTextMax * u, measure) }
            let tSize = measure(t, .title, ts)
            let aSize = a.map { measure($0, .artist, asz) } ?? .zero
            let textW = max(tSize.width, aSize.width)
            let textH = tSize.height + (a == nil ? 0 : U.lineGap * u + aSize.height)
            let jacket = U.cardJacket * u
            let height = U.cardPadV * u * 2 + max(jacket, textH)
            let textX = U.cardPadLeft * u + jacket + U.cardGap * u
            let eqX = textX + textW + U.cardEqGap * u
            let width = eqX + U.eqWidth * u + U.cardPadRight * u
            layout.size = CGSize(width: width, height: height)
            layout.plate = Plate(rect: CGRect(x: 0, y: 0, width: width, height: height),
                                 radius: U.cardRadius * u, kind: white ? .white : .glass,
                                 border: white ? 0 : U.px * u, borderOpacity: white ? 0 : 0.12,
                                 shadow: white ? Shadow(dy: 6 * U.px * u, blur: 22 * U.px * u, opacity: 0.35) : nil)
            layout.artwork = CGRect(x: U.cardPadLeft * u, y: (height - jacket) / 2, width: jacket, height: jacket)
            layout.artworkRadius = U.cardJacketRadius * u
            let top = (height - textH) / 2
            let color: UInt32 = white ? ink : 0xFFFFFF
            layout.texts = [Run(text: t, role: .title, pointSize: ts,
                                frame: CGRect(x: textX, y: top, width: tSize.width, height: tSize.height),
                                color: color, opacity: 1)]
            if let a {
                layout.texts.append(Run(text: a, role: .artist, pointSize: asz,
                                        frame: CGRect(x: textX, y: top + tSize.height + U.lineGap * u,
                                                      width: aSize.width, height: aSize.height),
                                        color: color, opacity: white ? 0.62 : 0.78))
            }
            layout.bars = bars(x: eqX, centerY: height / 2, u: u)
            layout.barColor = color
        case .pill:
            let fs = U.pillFont * u
            let maxW = U.pillTextMax * u
            let t = fit(title, .title, fs, maxWidth: maxW, measure)
            let tSize = measure(t, .title, fs)
            let rest = maxW - tSize.width - U.pillGap * u
            // 曲名で幅を使い切ったら歌手は出さない（「· …」だけを置かない）
            let a = rest < measure("· …", .artist, fs).width ? nil
                : artist.map { fit("· \($0)", .artist, fs, maxWidth: rest, measure) }
            let aSize = a.map { measure($0, .artist, fs) } ?? .zero
            let lineH = max(tSize.height, aSize.height, U.eqHeight * u)
            let height = U.pillPadV * u * 2 + lineH
            let eqX = U.pillPadH * u
            let tX = eqX + U.eqWidth * u + U.pillGap * u
            let aX = tX + tSize.width + U.pillGap * u
            let width = (a == nil ? tX + tSize.width : aX + aSize.width) + U.pillPadH * u
            layout.size = CGSize(width: width, height: height)
            layout.plate = Plate(rect: CGRect(x: 0, y: 0, width: width, height: height), radius: height / 2,
                                 kind: .glass, border: U.px * u, borderOpacity: 0.10, shadow: nil)
            layout.bars = bars(x: eqX, centerY: height / 2, u: u)
            layout.texts = [Run(text: t, role: .title, pointSize: fs,
                                frame: CGRect(x: tX, y: (height - tSize.height) / 2,
                                              width: tSize.width, height: tSize.height),
                                color: 0xFFFFFF, opacity: 1)]
            if let a {
                layout.texts.append(Run(text: a, role: .artist, pointSize: fs,
                                        frame: CGRect(x: aX, y: (height - aSize.height) / 2,
                                                      width: aSize.width, height: aSize.height),
                                        color: 0xFFFFFF, opacity: 0.78))
            }
        case .sleeve, .disc:
            let big = U.big * u
            let ts = U.titleSize * u, asz = U.artistSize * u
            let t = fit(title, .title, ts, maxWidth: U.bigTextMax * u, measure)
            let a = artist.map { fit($0, .artist, asz, maxWidth: U.bigTextMax * u, measure) }
            let tSize = measure(t, .title, ts)
            let aSize = a.map { measure($0, .artist, asz) } ?? .zero
            let width = max(big, tSize.width, aSize.width)
            let tY = big + U.bigGap * u
            let height = tY + tSize.height + (a == nil ? 0 : aSize.height)
            layout.size = CGSize(width: width, height: height)
            let square = CGRect(x: (width - big) / 2, y: 0, width: big, height: big)
            if style == .sleeve {
                layout.artwork = square
                layout.artworkRadius = U.bigRadius * u
                layout.artworkShadow = Shadow(dy: 14 * U.px * u, blur: 30 * U.px * u, opacity: 0.55)
            } else {
                layout.disc = square
                layout.discShadow = Shadow(dy: 12 * U.px * u, blur: 28 * U.px * u, opacity: 0.6)
                let label = big * U.discLabel
                layout.artwork = CGRect(x: square.midX - label / 2, y: square.midY - label / 2,
                                        width: label, height: label)
                layout.artworkIsCircle = true
                let hole = U.hole * u
                layout.hole = CGRect(x: square.midX - hole / 2, y: square.midY - hole / 2, width: hole, height: hole)
                // 溝（2px の暗い地と 1.4px の明るい線のくり返し・モックの repeating-radial-gradient）。紙の外だけ
                var r = (2 + 0.7) * U.px * u
                while r < big / 2 - U.grooveLine * u / 2 {
                    if r > label / 2 { layout.grooves.append(r) }
                    r += U.groovePeriod * u
                }
            }
            layout.textShadow = Shadow(dy: 1 * U.px * u, blur: 8 * U.px * u, opacity: 0.75)
            layout.texts = [Run(text: t, role: .title, pointSize: ts,
                                frame: CGRect(x: (width - tSize.width) / 2, y: tY,
                                              width: tSize.width, height: tSize.height),
                                color: 0xFFFFFF, opacity: 1)]
            if let a {
                layout.texts.append(Run(text: a, role: .artist, pointSize: asz,
                                        frame: CGRect(x: (width - aSize.width) / 2, y: tY + tSize.height,
                                                      width: aSize.width, height: aSize.height),
                                        color: 0xFFFFFF, opacity: 0.78))
            }
        case .title:
            let ts = U.typeSize * u, asz = U.typeArtist * u
            let t = fit(title, .mincho, ts, maxWidth: U.typeTitleMax * u, measure)
            let a = artist.map { fit($0, .artist, asz, maxWidth: U.typeArtistMax * u, measure) }
            let tSize = measure(t, .mincho, ts)
            let aSize = a.map { measure($0, .artist, asz) } ?? .zero
            let rowH = max(aSize.height, U.eqHeight * u)
            let rowW = U.eqWidth * u + (a == nil ? 0 : U.typeRowGap * u + aSize.width)
            let width = max(tSize.width, rowW)
            let rowY = tSize.height + U.typeGap * u
            layout.size = CGSize(width: width, height: rowY + rowH)
            layout.textShadow = Shadow(dy: 2 * U.px * u, blur: 14 * U.px * u, opacity: 0.65)
            layout.texts = [Run(text: t, role: .mincho, pointSize: ts,
                                frame: CGRect(x: (width - tSize.width) / 2, y: 0,
                                              width: tSize.width, height: tSize.height),
                                color: 0xFFFFFF, opacity: 1)]
            let rowX = (width - rowW) / 2
            layout.bars = bars(x: rowX, centerY: rowY + rowH / 2, u: u)
            if let a {
                layout.texts.append(Run(text: a, role: .artist, pointSize: asz,
                                        frame: CGRect(x: rowX + U.eqWidth * u + U.typeRowGap * u,
                                                      y: rowY + (rowH - aSize.height) / 2,
                                                      width: aSize.width, height: aSize.height),
                                        color: 0xFFFFFF, opacity: 0.9))
            }
        }
        return layout
    }

    /// 棒3本（箱の高さ 12・下を揃える）。`centerY` は箱の真ん中
    private static func bars(x: Double, centerY: Double, u: Double) -> [CGRect] {
        let bottom = centerY + U.eqHeight * u / 2
        return U.barHeights.enumerated().map { i, h in
            CGRect(x: x + Double(i) * (U.barWidth + U.barGap) * u, y: bottom - h * u,
                   width: U.barWidth * u, height: h * u)
        }
    }

    /// 幅に収まらない字を「…」で切る（測った幅で決める）
    static func fit(_ text: String, _ role: FontRole, _ size: Double, maxWidth: Double,
                    _ measure: Measure) -> String {
        guard measure(text, role, size).width > maxWidth else { return text }
        let chars = Array(text)
        var lo = 0, hi = chars.count
        // 収まるいちばん長い頭（＋「…」）を二分で探す
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = String(chars[0..<mid]).trimmingCharacters(in: .whitespaces) + "…"
            if measure(candidate, role, size).width <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return String(chars[0..<lo]).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - 動き（作る画面だけ・焼き込みは止まった絵）

    /// 棒の伸び縮み（0.4〜1 倍・1.05 秒で1往復・3本の位相はモックの animation-delay）。
    /// `time` は秒。**動きを減らす設定では呼ばない**（止まった `bars` のまま）
    static func barScale(index: Int, time: Double) -> Double {
        let delays = [-0.25, -0.6, -0.9]
        let period = 1.05
        let t = (time - delays[index % delays.count]).truncatingRemainder(dividingBy: period) / period
        let phase = t < 0 ? t + 1 : t
        // 0 → 0.4、半分 → 1、1 → 0.4（ease-in-out の近似に cos）
        return 0.7 - 0.3 * cos(phase * 2 * .pi)
    }

    /// レコードの回り（6 秒で1周・ラジアン）
    static func discAngle(time: Double) -> Double {
        let period = 6.0
        return (time.truncatingRemainder(dividingBy: period) / period) * 2 * .pi
    }

    // MARK: - 幅の目安（測る口の無い所・置くときの大きさ）

    /// 札の幅の目安（歌手の字の大きさを 1 とした幅）。全角1・半角0.6 の目安（`SongSticker.ems` と同じ）。
    /// 置くときの大きさ（`SongSticker.fittedSize`）にだけ使う。**描く寸法は `make` が測って決める**
    static func estimatedWidth(style: SongStickerStyle, title: String, artist: String?) -> Double {
        func em(_ s: String, _ size: Double) -> Double {
            s.reduce(0.0) { $0 + ($1.isASCII ? 0.6 : 1.0) } * size
        }
        let artist = artist.flatMap { $0.isEmpty ? nil : $0 }
        switch style {
        case .glass, .white:
            let text = min(U.cardTextMax, max(em(title, U.titleSize), artist.map { em($0, U.artistSize) } ?? 0))
            return U.cardPadLeft + U.cardJacket + U.cardGap + text + U.cardEqGap + U.eqWidth + U.cardPadRight
        case .pill:
            let text = em(title, U.pillFont) + (artist.map { U.pillGap + em("· \($0)", U.pillFont) } ?? 0)
            return U.pillPadH * 2 + U.eqWidth + U.pillGap + min(U.pillTextMax, text)
        case .sleeve, .disc:
            let text = min(U.bigTextMax, max(em(title, U.titleSize), artist.map { em($0, U.artistSize) } ?? 0))
            return max(U.big, text)
        case .title:
            let row = U.eqWidth + (artist.map { U.typeRowGap + min(U.typeArtistMax, em($0, U.typeArtist)) } ?? 0)
            return max(min(U.typeTitleMax, em(title, U.typeSize)), row)
        }
    }
}
