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
    /// 書体（板 24b の「明朝・ゴシック・手書き風」）
    var face: Face
    /// 文字の色（板 24b の5色）
    var ink: Ink
    /// 回し（ラジアン。2本指で回す）
    var rotation: Double

    /// 書体。**アプリに同梱した字だけ**（端末に無い書体を選ばせると、
    /// 画面と焼き込みで見た目が割れる）
    enum Face: String, Codable, CaseIterable, Identifiable {
        /// Shippori Mincho B1 Bold（見出しの明朝）
        case mincho
        /// 端末のゴシック（太字）。**以前の文字はすべてこれ**
        case gothic
        /// Klee One SemiBold（手書き風）
        case hand

        var id: String { rawValue }

        var label: String {
            switch self {
            case .mincho: return L("明朝", "Serif")
            case .gothic: return L("ゴシック", "Sans")
            case .hand: return L("手書き風", "Handwritten")
            }
        }

        /// 同梱の書体の名前（PostScript 名）。ゴシックは端末の字なので nil
        var fontName: String? {
            switch self {
            case .mincho: return "ShipporiMinchoB1-Bold"
            case .gothic: return nil
            case .hand: return "KleeOne-SemiBold"
            }
        }
    }

    /// 文字の色（板 24b: 白・墨・真鍮・空色・珊瑚）
    enum Ink: String, Codable, CaseIterable, Identifiable {
        case white, ink, brass, sky, coral

        var id: String { rawValue }

        /// 0xRRGGBB
        var hex: UInt32 {
            switch self {
            case .white: return 0xFFFFFF
            case .ink: return 0x07090A
            case .brass: return 0xC9A66B
            case .sky: return 0x9CC3E6
            case .coral: return 0xFF8A80
            }
        }

        var label: String {
            switch self {
            case .white: return L("白", "White")
            case .ink: return L("墨", "Ink")
            case .brass: return L("真鍮", "Brass")
            case .sky: return L("空色", "Sky")
            case .coral: return L("珊瑚", "Coral")
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
        }
    }

    /// **描くときの色。** 選べない組（見た目を後から変えた・札で帯に固定された）は
    /// 読める色に寄せる。画面も焼き込みもこれを通す
    var drawnInk: Ink {
        Self.inks(for: style).contains(ink) ? ink : (style == .dark ? .ink : .white)
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
        case (.banner, .ink): next.ink = .white
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

        /// 札の頭に付ける印。**文字だけの札には付けない**
        var symbol: String? {
            switch self {
            case .text: return nil
            case .place: return "📍"
            case .song: return "♪"
            case .time: return "🕘"
            case .date: return "📅"
            case .hashtag: return "#"
            }
        }

        /// 自由な文字以外は**必ず帯**にする（写真の上で読めなくならないように）
        var forcedStyle: Style? {
            self == .text ? nil : .banner
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
                let month = calendar.component(.month, from: now)
                let day = calendar.component(.day, from: now)
                return L("\(month)月\(day)日", "\(month)/\(day)")
            default:
                return ""
            }
        }

        /// 置いたあとに文字を直せるか。**時刻と日付は直させない**
        /// （端末から採った値なので、直せると「いつの話か」が嘘になる）
        var isEditable: Bool {
            self != .time && self != .date
        }

        var toolLabel: String {
            switch self {
            // 板 24b「文字と札」のチップの言い方
            case .text: return L("文字", "Text")
            case .place: return L("撮影地", "Place")
            case .song: return L("曲", "Music")
            case .time: return L("時刻", "Time")
            case .date: return L("日付", "Date")
            case .hashtag: return L("タグ", "Tag")
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
            }
        }
    }

    enum Style: String, CaseIterable, Identifiable, Codable {
        /// 白い文字に影（写真の上でいちばん読める）
        case light
        /// 黒い文字に白の縁
        case dark
        /// 黒い帯に白抜き
        case banner

        var id: String { rawValue }

        var label: String {
            switch self {
            case .light: return L("白", "White")
            case .dark: return L("黒", "Black")
            case .banner: return L("帯", "Banner")
            }
        }
    }

    /// 文字の大きさの幅。**下は読めなくならない所まで、上は画面を
    /// 覆わない所まで**（短い辺の 3%〜20%）
    static let minSize = 0.03
    static let maxSize = 0.20
    static let defaultSize = 0.07

    /// 1枚に置ける数。**増やしすぎない**——写真が主役
    static let maxCount = 5

    /// 文字数の上限。サーバーのキャプション（200字）に合わせる
    static let maxLength = 200

    init(id: UUID = UUID(), text: String, x: Double = 0.5, y: Double = 0.5,
         size: Double = TextOverlay.defaultSize, style: Style = .light,
         kind: Kind = .text, face: Face = .gothic, ink: Ink? = nil, rotation: Double = 0) {
        self.id = id
        self.text = String(text.prefix(Self.maxLength))
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
        case id, text, x, y, size, style, kind, face, ink, rotation
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
