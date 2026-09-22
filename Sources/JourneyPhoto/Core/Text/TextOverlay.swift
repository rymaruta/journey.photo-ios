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
            case .text: return L("テキスト", "Text")
            case .place: return L("場所", "Place")
            case .song: return L("BGM", "Music")
            case .time: return L("時刻", "Time")
            case .date: return L("日付", "Date")
            case .hashtag: return L("ハッシュタグ", "Hashtag")
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
         kind: Kind = .text) {
        self.id = id
        self.text = String(text.prefix(Self.maxLength))
        self.x = Self.clampPosition(x)
        self.y = Self.clampPosition(y)
        self.size = Self.clampSize(size)
        // 場所と曲は帯で固定（見た目を選ばせない＝読めない札を作らせない）
        self.style = kind.forcedStyle ?? style
        self.kind = kind
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
