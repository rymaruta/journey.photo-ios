import SwiftUI

/// 仕上げる画面の写真の下に並ぶ4つの道具（文字・スタンプ・曲・場所）。
///
/// **アイコン・名前・色はここ1か所。** owner がアイコンにこだわりたいと言っている
/// （2026-10-02 に C 案に決めた）。替えるときはこの型だけを直す——4つのボタンはここから描く
/// （`StoryComposerView.toolRow`）。
///
/// 色: ふだんは白（線は太め）。**使ったときは真鍮＋右上に真鍮の 8pt の点。**
/// 道具の面は黒地（#121212）なので、真鍮を置いてよい（デザインシステム「黒塗りの真鍮」:
/// 真鍮は黒い地の上だけ）。
enum StoryTool: CaseIterable, Identifiable {
    case text, sticker, song, place

    var id: Self { self }

    /// SF Symbols の名前
    var symbol: String {
        switch self {
        case .text: return "textformat"
        case .sticker: return "face.smiling"
        case .song: return "music.note"
        case .place: return "mappin"
        }
    }

    var label: String {
        switch self {
        case .text: return L("文字", "Text")
        case .sticker: return L("スタンプ", "Stickers")
        case .song: return L("曲", "Song")
        case .place: return L("場所", "Place")
        }
    }

    /// アイコンの線の太さ（owner の C 案: 太め）
    static let symbolWeight: Font.Weight = .semibold
    /// ふだんのアイコンの色
    @MainActor static var idleColor: Color { WebTheme.foreground }
    /// 使ったときのアイコンと点の色
    @MainActor static var usedColor: Color { WebTheme.accent }
    /// 使ったときの点の大きさ
    static let dotSize: CGFloat = 8

    /// 読み上げ（「文字・入れてあります」）。状態も読ませる
    func accessibilityLabel(used: Bool) -> String {
        used ? L("\(label)・入れてあります", "\(label), added") : label
    }

    /// この道具を使ったか。**表示中の1枚の札**と、全体で1つの曲・撮影地で決める。
    ///  - 文字: 表示中の1枚に文字の札が1つ以上
    ///  - スタンプ: スタンプ・タグ・時刻・日付の札か投票が1つ以上。**曲の札と撮影地の札は数えない**
    ///    （曲の札は曲を付けると自動で置かれる——スタンプが光ると、置いていないのに光って見える）
    ///  - 曲: 曲が付いている（曲の札もここ）
    ///  - 場所: 撮影地が入っているか、撮影地の札がある（空白だけは入っていない扱い。送るときも削る）
    static func isUsed(_ tool: StoryTool, overlays: [TextOverlay], hasVote: Bool,
                       hasSong: Bool, location: String) -> Bool {
        switch tool {
        case .text: return overlays.contains { $0.kind == .text }
        case .sticker: return hasVote || overlays.contains { ![.text, .song, .place].contains($0.kind) }
        case .song: return hasSong || overlays.contains { $0.kind == .song }
        case .place: return !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || overlays.contains { $0.kind == .place }
        }
    }
}
