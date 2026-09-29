import Foundation

/// 写真の上に置く文字。
///
/// owner の要望（2026-09-21）:「ユーザは画面のいろんなとこに
/// テキストを配置したいと思う」。Web のストーリーは**キャプション1本**を
/// 下に固定で出すだけで（`api-user/src/stories.ts` は 200字の文字列として
/// しか受け取らない）、置く場所を選べない。
///
/// **位置は画像への焼き込みで持つ。**
///
/// 座標や色を後から編集できる形にするには、サーバーに新しい項目が要る
/// （`caption` は文字列1本）。それは API の変更＝別の反映経路になるので、
/// ここでは**投稿する画像そのものに描き込む**。Web 側は何も変えなくても
/// そのまま見える。代わりに**後から文字だけ直すことはできない**
/// （直すなら投稿し直し）——Instagram なども同じ割り切り。
///
/// **位置は 0...1 の相対値**で持つ。画面の大きさ（編集中）と画像の
/// 大きさ（焼き込み）は違うので、点ではなく割合で覚える。
/// **`Codable` なのは下書きのため**（`StoryDraftStore`）。投稿すると画像に
/// 焼き込まれて消えるので、保存する形はここだけで使う。
struct TextOverlay: Identifiable, Equatable, Codable {

    let id: UUID
    var text: String
    /// 中心の位置。左上が (0, 0)、右下が (1, 1)
    var x: Double
    var y: Double
    /// 文字の大きさ。**画像の短い辺に対する割合**
    /// （大きい写真でも小さい写真でも同じ見た目になる）
    var size: Double
    var style: Style
    /// 何の札か。**場所と曲は投稿の項目としても送る**ので、
    /// ここに置くのは「写真の上の見た目」だけ
    var kind: Kind
    /// 書体（板 24b の「明朝・ゴシック・手書き風」＋ 2026-09-29 に足した5つ）
    var face: Face
    /// 文字の色（板 24b の5色 ＋ 2026-09-29 に足した7色）
    var ink: Ink
    /// 回し（ラジアン。2本指で回す）
    var rotation: Double
    /// 自由に選んだ色（0xRRGGBB・端末の色選び）。**あれば `ink` より先に使う**。
    /// 12色から選び直したら nil に戻す（owner の「色が少ない」・2026-09-29）
    var customHex: UInt32?
    /// 複数行のときの揃え（owner の「ストーリーの自由度が低い」・2026-09-29）。
    /// 1行なら見た目は変わらない（札の中心は `x` / `y` のまま）
    var align: Align = .center

    /// 行の揃え。**改行できる自由な文字だけ**が選べる（札は1行）
    enum Align: String, CaseIterable, Identifiable, Codable {
        case leading, center, trailing
        var id: String { rawValue }

        var label: String {
            switch self {
            case .leading: return L("左揃え", "Align left")
            case .center: return L("中央揃え", "Align center")
            case .trailing: return L("右揃え", "Align right")
            }
        }

        var symbol: String {
            switch self {
            case .leading: return "text.alignleft"
            case .center: return "text.aligncenter"
            case .trailing: return "text.alignright"
            }
        }
    }

    /// 書体。**アプリに同梱した字か、どの iPhone にも入っている字だけ**
    /// （端末に無い書体を選ばせると、画面と焼き込みで見た目が割れる）。
    ///
    /// owner の「フォントの種類が少ない」（2026-09-29）で 3 → 8。**足すのは端末の字が中心**
    /// ——日本語の書体は1つ 3〜4MB あり、同梱を増やすとアプリが太る。同梱は
    /// マーカー・丸文字の2つだけ（JIS 第1水準まで削って計 3.1MB・`Tools/make-display-font.py`）。
    /// 英字だけの書体（タイプ・筆記体）の日本語は、端末のゴシックで出る。
    ///
    /// ⚠️ **端末の書体の名前は Linux では確かめられない。** 名前が違っても、画面
    /// （`StoryCanvas.font`）と焼き込み（`TextOverlayRenderer`）は両方とも端末の太字に
    /// 落ちるので、割れはしない（見た目が変わらないだけ）。実機で確かめること
    enum Face: String, Codable, CaseIterable, Identifiable {
        /// Shippori Mincho B1 Bold（見出しの明朝）
        case mincho
        /// 端末のゴシック（太字）。**以前の文字はすべてこれ**
        case gothic
        /// Klee One SemiBold（手書き風）
        case hand
        /// ヒラギノ丸ゴ（端末の字）
        case maru
        /// Yusei Magic（マーカーで書いたような字・同梱）
        case marker
        /// Hachi Maru Pop（丸文字・同梱）
        case pop
        /// American Typewriter Bold（端末の字・英字だけ）
        case typewriter
        /// Snell Roundhand Bold（端末の字・英字の筆記体）
        case script

        var id: String { rawValue }

        var label: String {
            switch self {
            case .mincho: return L("明朝", "Serif")
            case .gothic: return L("ゴシック", "Sans")
            case .hand: return L("手書き風", "Handwritten")
            case .maru: return L("丸ゴシック", "Rounded")
            case .marker: return L("マーカー", "Marker")
            case .pop: return L("丸文字", "Pop")
            case .typewriter: return L("タイプ", "Typewriter")
            case .script: return L("筆記体", "Script")
            }
        }

        /// 書体の名前（PostScript 名）。ゴシックは端末の太字なので nil
        var fontName: String? {
            switch self {
            case .mincho: return "ShipporiMinchoB1-Bold"
            case .gothic: return nil
            case .hand: return "KleeOne-SemiBold"
            case .maru: return "HiraMaruProN-W4"
            case .marker: return "YuseiMagic-Regular"
            case .pop: return "HachiMaruPop-Regular"
            case .typewriter: return "AmericanTypewriter-Bold"
            case .script: return "SnellRoundhand-Bold"
            }
        }

        /// アプリに同梱した書体か（`project.yml` の `UIAppFonts` に載せるもの）
        var isBundled: Bool {
            switch self {
            case .mincho, .hand, .marker, .pop: return true
            case .gothic, .maru, .typewriter, .script: return false
            }
        }
    }

    /// 文字の色（板 24b: 白・墨・真鍮・空色・珊瑚 ＋ 2026-09-29 に足した7色）
    enum Ink: String, Codable, CaseIterable, Identifiable {
        case white, ink, brass, sky, coral
        case yellow, orange, pink, red, green, blue, purple

        var id: String { rawValue }

        /// 0xRRGGBB
        var hex: UInt32 {
            switch self {
            case .white: return 0xFFFFFF
            case .ink: return 0x07090A
            case .brass: return 0xC9A66B
            case .sky: return 0x9CC3E6
            case .coral: return 0xFF8A80
            case .yellow: return 0xFFD54F
            case .orange: return 0xFFA24C
            case .pink: return 0xFF7EB6
            case .red: return 0xF2545B
            case .green: return 0x7ED9A0
            case .blue: return 0x4C8DFF
            case .purple: return 0xB388FF
            }
        }

        var label: String {
            switch self {
            case .white: return L("白", "White")
            case .ink: return L("墨", "Ink")
            case .brass: return L("真鍮", "Brass")
            case .sky: return L("空色", "Sky")
            case .coral: return L("珊瑚", "Coral")
            case .yellow: return L("黄", "Yellow")
            case .orange: return L("橙", "Orange")
            case .pink: return L("桃", "Pink")
            case .red: return L("赤", "Red")
            case .green: return L("緑", "Green")
            case .blue: return L("青", "Blue")
            case .purple: return L("紫", "Purple")
            }
        }
    }

    /// この見た目で選べる色。**帯に墨・黒の見た目に白は読めない**ので出さない
    /// （帯は黒 65% の地、黒の見た目は白い縁——どちらも同じ色だと文字が消える）
    static func inks(for style: Style) -> [Ink] {
        switch style {
        case .light: return Ink.allCases
        case .dark: return Ink.allCases.filter { $0 != .white }
        case .banner: return Ink.allCases.filter { $0 != .ink }
        // 縁が黒なので墨は縁に溶ける
        case .outline: return Ink.allCases.filter { $0 != .ink }
        }
    }

    /// **描くときの色。** 選べない組（見た目を後から変えた・札で帯に固定された）は
    /// 読める色に寄せる
    var drawnInk: Ink {
        Self.inks(for: style).contains(ink) ? ink : (style == .dark ? .ink : .white)
    }

    /// **描くときの色（0xRRGGBB）。画面も焼き込みもこれを通す。**
    /// 自由に選んだ色があればそれを、見た目に対して読めるところまで寄せて使う
    var drawnHex: UInt32 {
        customHex.map { Self.readableHex($0, for: style) } ?? drawnInk.hex
    }

    // MARK: 自由に選んだ色を読める色に寄せる

    /// 色の組の読みやすさの下限（WCAG のコントラスト比）。
    /// **12色の決まりを数に直したもの**——黒の見た目（白い縁）は白に近い色がだめ、
    /// 帯（黒 65% の地）と縁取り（黒い縁）は黒に近い色がだめ。12色のうち出している色は
    /// 全部この線を越え、出していない白（黒の見た目）・墨（帯・縁取り）は越えない
    static let minContrastOnWhiteEdge = 1.35
    static let minContrastOnBlack = 3.0

    /// 相対輝度（WCAG 2.x）
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// その見た目で読める色か。白の見た目は影が付くのでどの色でも読める
    static func isReadable(_ hex: UInt32, on style: Style) -> Bool {
        switch style {
        case .light: return true
        case .dark: return contrast(hex, 0xFFFFFF) >= minContrastOnWhiteEdge
        case .banner, .outline: return contrast(hex, 0x000000) >= minContrastOnBlack
        }
    }

    /// 読めない色は**同じ色みのまま**読めるところまで寄せる（黒の見た目は暗く、
    /// 帯・縁取りは明るく）。選んだ色を黙って捨てると、押しても変わらないように見える
    static func readableHex(_ hex: UInt32, for style: Style) -> UInt32 {
        let hex = hex & 0xFFFFFF
        guard !isReadable(hex, on: style) else { return hex }
        let target: UInt32 = style == .dark ? 0x000000 : 0xFFFFFF
        for step in 1...20 {
            let mixed = mix(hex, target, Double(step) / 20)
            if isReadable(mixed, on: style) { return mixed }
        }
        return target
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// 0...1 の赤緑青から 0xRRGGBB（端末の色選びは範囲外の値を返すことがあるので丸める）
    static func hex(red: Double, green: Double, blue: Double) -> UInt32 {
        func channel(_ v: Double) -> UInt32 {
            UInt32((min(max(v.isFinite ? v : 0, 0), 1) * 255).rounded())
        }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }

    /// **見た目を切り替える。** 読めない組になる色だけ寄せ、他の色は残す
    /// （白→黒は墨・帯に墨は白。真鍮・空色・珊瑚はどの見た目でもそのまま）。
    /// **黒→白だけは墨を白に戻す**——黒の既定の墨を白の見た目へ持ち越すと、
    /// 白→黒→白で文字が墨のまま残る。白の見た目で墨を自分で選んだ人の墨は残す。
    /// 同じ見た目の押し直しと、札（撮影地など・帯で固定）は何もしない
    func withStyle(_ newStyle: Style) -> TextOverlay {
        guard kind.forcedStyle == nil, newStyle != style else { return self }
        var next = self
        next.style = newStyle
        switch (newStyle, ink) {
        case (.dark, .white): next.ink = .ink
        case (.banner, .ink), (.outline, .ink): next.ink = .white
        case (.light, .ink) where style == .dark: next.ink = .white
        default: break
        }
        return next
    }

    /// 札の種類（モック4-3 のスタンプ）。
    ///
    /// **持っているデータのものだけ。** モックには天気・食べ物・質問も
    /// あるが、天気は引く先が無く、質問は答えを受け取る箱が無い
    /// ——置くだけで何も起きない札は作らない。
    enum Kind: String, Equatable, Codable, CaseIterable {
        /// 自由な文字
        case text
        /// 撮影地（ピンの印を付ける）
        case place
        /// 曲（音符の印を付ける）
        case song
        /// いまの時刻（端末の時計）
        case time
        /// 今日の日付（端末の暦）
        case date
        /// ハッシュタグ
        case hashtag
        /// 絵文字のスタンプ（owner の「スタンプが少ない」・2026-09-29）。**飾りだけ**
        /// ——持っているデータを出す札ではないが、押しても何も起きないと誤解される
        /// 形（天気・質問）ではない。`TextOverlay.stamps` から選ぶ
        case stamp

        /// 札の頭に付ける印。**文字だけの札には付けない**
        var symbol: String? {
            switch self {
            case .text: return nil
            case .place: return "📍"
            case .song: return "♪"
            case .time: return "🕘"
            case .date: return "📅"
            case .hashtag: return "#"
            case .stamp: return nil
            }
        }

        /// 自由な文字以外は**必ず帯**にする（写真の上で読めなくならないように）。
        /// **スタンプは帯にしない**（絵文字そのものが見た目）
        var forcedStyle: Style? {
            switch self {
            case .text: return nil
            case .stamp: return .light
            default: return .banner
            }
        }

        /// 置いたときに入っている文字。**時刻と日付は端末から採る**
        /// ——打たせるものではないし、打たせると嘘を書ける
        func initialText(now: Date = Date(), calendar: Calendar = .current) -> String {
            switch self {
            case .time:
                let hour = calendar.component(.hour, from: now)
                let minute = calendar.component(.minute, from: now)
                return String(format: "%d:%02d", hour, minute)
            case .date:
                // 「9月27日」「9/27」は西暦の月日（端末の暦がイスラム暦などでも）
                let gregorian = calendar.gregorianKeepingZone
                let month = gregorian.component(.month, from: now)
                let day = gregorian.component(.day, from: now)
                return L("\(month)月\(day)日", "\(month)/\(day)")
            default:
                return ""
            }
        }

        /// 置いたあとに文字を直せるか。**時刻と日付は直させない**
        /// （端末から採った値なので、直せると「いつの話か」が嘘になる）。
        /// スタンプは選び直す（打つものではない）
        var isEditable: Bool {
            self != .time && self != .date && self != .stamp
        }

        /// 書体・色を選べるか。**スタンプは絵文字なので効かない**（出すと押しても変わらない）
        var hasTypography: Bool { self != .stamp }

        /// 改行できるか（と、揃えを選べるか）。**自由な文字だけ**——撮影地・タグなどは
        /// 帯の1行の札で、改行すると印（📍 #）と中身が別の行に割れる
        var allowsNewlines: Bool { self == .text }

        var toolLabel: String {
            switch self {
            // 板 24b「文字と札」のチップの言い方
            case .text: return L("文字", "Text")
            case .place: return L("撮影地", "Place")
            case .song: return L("曲", "Music")
            case .time: return L("時刻", "Time")
            case .date: return L("日付", "Date")
            case .hashtag: return L("タグ", "Tag")
            case .stamp: return L("スタンプ", "Stickers")
            }
        }

        var toolSymbol: String {
            switch self {
            case .text: return "textformat"
            case .place: return "mappin"
            case .song: return "music.note"
            case .time: return "clock"
            case .date: return "calendar"
            case .hashtag: return "number"
            case .stamp: return "face.smiling"
            }
        }
    }

    /// 選べるスタンプ（旅の写真向けの絵文字）。**端末の絵文字の字形で描く**ので同梱は要らない
    static let stamps: [String] = [
        "✈️", "🚄", "🚗", "🚲", "⛴️", "🧳", "🗺️", "📷", "📸", "🎒",
        "🗻", "⛩️", "🏯", "🏖️", "🏔️", "🌊", "🌅", "🌄", "🌃", "🎡",
        "🌸", "🍁", "🌻", "🌿", "❄️", "☀️", "🌙", "⭐️", "🌈", "☁️",
        "🍜", "🍣", "🍡", "🍵", "☕️", "🍺", "🍦", "🍰", "🍙", "🍓",
        "❤️", "💙", "✨", "🎉", "👍", "😊", "🥰", "😎", "🙌", "💯",
    ]

    /// スタンプの既定の大きさ（文字より大きく置く）
    static let stampSize = 0.12

    enum Style: String, CaseIterable, Identifiable, Codable {
        /// 白い文字に影（写真の上でいちばん読める）
        case light
        /// 黒い文字に白の縁
        case dark
        /// 黒い帯に白抜き
        case banner
        /// 色の文字に黒い太い縁（owner の「自由度が低い」・2026-09-29）。
        /// **どの写真の上でも色が読める**——明るい写真でも暗い写真でも縁が残す
        case outline

        var id: String { rawValue }

        var label: String {
            switch self {
            case .light: return L("白", "White")
            case .dark: return L("黒", "Black")
            case .banner: return L("帯", "Banner")
            case .outline: return L("縁取り", "Outline")
            }
        }

        /// 縁の幅（字の大きさに対する百分率・輪郭の両側に半分ずつ）。縁が無ければ nil。
        /// **編集画面と焼き込みの両方がここを読む**——別々に持つと画面と仕上がりの太さがずれる
        var edgePercent: Double? {
            switch self {
            case .light, .banner: return nil
            case .dark: return 3
            case .outline: return 6
            }
        }

        /// 編集画面で縁の写しをずらす量（pt）。焼き込みの縁は輪郭の両側に半分ずつ乗り、
        /// 内側は塗りが隠すので、**外に見えるのは幅の半分**
        func edgeOffset(fontSize: Double) -> Double? {
            edgePercent.map { fontSize * $0 / 100 / 2 }
        }
    }

    /// 文字の大きさの幅。**下は読めなくならない所まで、上は画面を
    /// 覆わない所まで**（短い辺の 3%〜20%）
    static let minSize = 0.03
    static let maxSize = 0.20
    static let defaultSize = 0.07

    /// 1枚に置ける数。**増やしすぎない**——写真が主役。
    /// owner の「自由度が低い」（2026-09-29）で 5 → 10
    static let maxCount = 10

    /// 文字数の上限。サーバーのキャプション（200字）に合わせる
    static let maxLength = 200

    /// 行の上限。**写真を覆わない所まで**（大きさの上限と同じ考え）
    static let maxLines = 6

    /// 打った文字を置ける形に整える。**改行は自由な文字だけ・6行まで**、字数は 200 まで。
    /// 改行できない札の改行は空白にする（貼り付けで入ってくる）
    static func cleaned(_ text: String, kind: Kind) -> String {
        guard kind.allowsNewlines else {
            return String(text.replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .prefix(maxLength))
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        return String(lines.prefix(maxLines).joined(separator: "\n").prefix(maxLength))
    }

    /// 複数行を焼き込むときの、各行の左端（ブロックの左端から）とブロックの大きさ。
    /// **編集画面の `multilineTextAlignment` と同じ置き方**——ブロックの幅はいちばん長い行、
    /// 短い行は揃えに合わせて寄せる。行の高さは書体の1行ぶん
    static func lineLayout(widths: [Double], lineHeight: Double, align: Align)
        -> (size: CGSize, xs: [Double]) {
        let width = widths.max() ?? 0
        let xs = widths.map { w -> Double in
            switch align {
            case .leading: return 0
            case .center: return (width - w) / 2
            case .trailing: return width - w
            }
        }
        return (CGSize(width: width, height: lineHeight * Double(max(widths.count, 1))), xs)
    }

    init(id: UUID = UUID(), text: String, x: Double = 0.5, y: Double = 0.5,
         size: Double = TextOverlay.defaultSize, style: Style = .light,
         kind: Kind = .text, face: Face = .gothic, ink: Ink? = nil, rotation: Double = 0) {
        self.id = id
        self.text = Self.cleaned(text, kind: kind)
        self.x = Self.clampPosition(x)
        self.y = Self.clampPosition(y)
        self.size = Self.clampSize(size)
        // 場所と曲は帯で固定（見た目を選ばせない＝読めない札を作らせない）
        let resolved = kind.forcedStyle ?? style
        self.style = resolved
        self.kind = kind
        self.face = face
        // 色を言わなければ見た目に合わせる（黒は墨、他は白）
        self.ink = ink ?? (resolved == .dark ? .ink : .white)
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, x, y, size, style, kind, face, ink, rotation, customHex, align
    }

    /// **前の版の下書きも読む。** 書体・色・回しは後から足した項目なので、
    /// 無ければ以前の見た目（ゴシック・見た目に合わせた色・回しなし）にする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let style = try c.decode(Style.self, forKey: .style)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.x = try c.decode(Double.self, forKey: .x)
        self.y = try c.decode(Double.self, forKey: .y)
        self.size = try c.decode(Double.self, forKey: .size)
        self.style = style
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.face = (try? c.decodeIfPresent(Face.self, forKey: .face)) ?? .gothic
        self.ink = (try? c.decodeIfPresent(Ink.self, forKey: .ink)) ?? (style == .dark ? .ink : .white)
        self.rotation = (try? c.decodeIfPresent(Double.self, forKey: .rotation)) ?? 0
        self.customHex = (try? c.decodeIfPresent(UInt32.self, forKey: .customHex)).map { $0 & 0xFFFFFF }
        // 揃えは後から足した項目（前の版の下書きは中央＝これまでの見た目）
        self.align = (try? c.decodeIfPresent(Align.self, forKey: .align)) ?? .center
    }

    /// 画面と画像に出す文字（印つき）。
    static func display(text: String, kind: Kind) -> String {
        guard let symbol = kind.symbol else { return text }
        return "\(symbol) \(text)"
    }

    var displayText: String { Self.display(text: text, kind: kind) }

    /// **画面の外に出さない。** 端まで動かせるが、出てしまうと
    /// 掴み直せなくなる（消す手段も無くなる）
    static func clampPosition(_ value: Double) -> Double {
        min(max(value, 0.02), 0.98)
    }

    static func clampSize(_ value: Double) -> Double {
        min(max(value, minSize), maxSize)
    }

    /// 2本指でつまんだあとの大きさ（owner の「自由度が低い」・2026-09-29）。
    /// **幅はスライダーと同じ `clampSize`**——つまめば上限を越えられる、にしない。
    /// 倍率が読めない値（0・負・無限）なら変えない
    func scaled(by factor: Double) -> TextOverlay {
        guard factor.isFinite, factor > 0 else { return self }
        var next = self
        next.size = Self.clampSize(size * factor)
        return next
    }

    // MARK: - 編集画面と焼き込みで同じ形にする

    /// 文字の大きさ。**画像の短い辺に対する割合**で決める。
    ///
    /// 編集画面（`StoryCanvas`）と焼き込み（`TextOverlayRenderer`）が
    /// **両方ともここを通る**。以前は編集画面が「3:4 の枠の高さ」、焼き込みが
    /// 「画像の短い辺」で別々に計算していて、横長の写真だと投稿した文字が
    /// 編集中より小さく出ていた（2026-09-26 のバグ探し）
    static func fontSize(_ size: Double, in image: CGSize) -> Double {
        min(image.width, image.height) * size
    }

    /// 文字の中心。`photo` は写真が占める場所（焼き込みでは画像全体、
    /// 編集画面では枠の中に収まった写真）。**両方ともここを通る**
    func center(in photo: CGRect) -> CGPoint {
        CGPoint(x: photo.minX + photo.width * x, y: photo.minY + photo.height * y)
    }

    /// `canvas` を `image` で縦横比のまま**埋めた**ときの、画像の場所
    /// （はみ出した部分は画面の外。作る画面は写真を画面いっぱいに敷く・板 24）。
    ///
    /// 文字の位置は画像に対する割合のままなので、焼き込みと同じところに出る。
    /// 閲覧画面も同じく埋めて出すので、**作る画面で見えている範囲が
    /// 見る人にもほぼ同じに見える**
    static func filledRect(image: CGSize, in canvas: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, canvas.width > 0, canvas.height > 0 else {
            return CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        }
        let scale = max(canvas.width / image.width, canvas.height / image.height)
        let width = image.width * scale
        let height = image.height * scale
        return CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2,
                      width: width, height: height)
    }

    /// 画面に見えている範囲の中へ寄せる（埋めて出すと画像の端が画面の外に出る。
    /// そこへ動かすと掴み直せず、消すこともできなくなる）
    func clamped(toVisible photo: CGRect, canvas: CGSize) -> TextOverlay {
        guard photo.width > 0, photo.height > 0 else { return self }
        let margin = 0.02
        let minX = max(0, -photo.minX / photo.width) + margin
        let maxX = min(1, (canvas.width - photo.minX) / photo.width) - margin
        let minY = max(0, -photo.minY / photo.height) + margin
        let maxY = min(1, (canvas.height - photo.minY) / photo.height) - margin
        var result = self
        result.x = min(max(x, minX), max(minX, maxX))
        result.y = min(max(y, minY), max(minY, maxY))
        return result
    }

    /// `canvas` の中に `image` を縦横比のまま収めたときの、画像の場所。
    ///
    /// 位置（`x` / `y`）は**画像に対する割合**で持つ。編集画面は 3:4 の枠に
    /// 写真を収めるので、枠と写真の形が違うと上下か左右に余白が出る——
    /// 枠に対する割合で置くと、その余白の分だけ焼き込みとずれていた
    static func fittedRect(image: CGSize, in canvas: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, canvas.width > 0, canvas.height > 0 else {
            return CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        }
        let scale = min(canvas.width / image.width, canvas.height / image.height)
        let width = image.width * scale
        let height = image.height * scale
        return CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2,
                      width: width, height: height)
    }

    /// 掴んで動かした結果の位置。`translation` は画面上の移動量、
    /// `canvas` はその画面の大きさ。
    func moved(by translation: CGSize, in canvas: CGSize) -> TextOverlay {
        guard canvas.width > 0, canvas.height > 0 else { return self }
        var moved = self
        moved.x = Self.clampPosition(x + translation.width / canvas.width)
        moved.y = Self.clampPosition(y + translation.height / canvas.height)
        return moved
    }

    /// 空白だけの文字は置かない（見えない物が画像に焼き込まれる）
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
