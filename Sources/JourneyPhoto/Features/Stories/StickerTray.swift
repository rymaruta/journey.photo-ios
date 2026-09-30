import SwiftUI

/// **札とスタンプのトレイ**（下から出るシート・owner・2026-09-30「使いづらい」）。
///
/// 以前は「文字と札」の編集に入り、写真の上の横に流れる列から選んでいた（文字もここにあった）。
/// いまは文字は右の列の「Aa」から直接打ち、**それ以外の札はここから選ぶ**。押したら閉じて置く。
///
///  - 撮影地・タグ・曲は置いたらすぐ打つ画面へ（呼ぶ側）。時刻・日付は端末から採って置く
///  - 投票は写真1枚に1つ（置いてあれば選び直すだけ）
///  - 1枚の上限（`TextOverlay.maxCount`）に達していれば、札とスタンプは押せない（投票は数に入らない）
///
/// 地は黒（デザインシステム「黒塗りの真鍮」の下地）。押せる所は 44pt。
struct StickerTray: View {

    /// 選んだもの
    enum Pick: Equatable {
        case kind(TextOverlay.Kind)
        case vote
        case stamp(String)
    }

    /// いまの写真に置いてある札の数（上限の判定）
    let count: Int
    /// 投票を置いてあるか（「投票」の言い方を変える）
    let hasVote: Bool
    var onPick: (Pick) -> Void

    /// トレイに並べる札（文字は「Aa」から・スタンプは下の格子）
    static let kinds: [TextOverlay.Kind] = TextOverlay.Kind.allCases.filter { $0 != .text && $0 != .stamp }

    private var full: Bool { count >= TextOverlay.maxCount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                    OverlayChip(title: hasVote ? L("投票を直す", "Edit poll") : L("投票", "Poll"),
                                systemImage: "chart.bar.xaxis") { onPick(.vote) }
                        .accessibilityIdentifier("story.add.vote")
                    ForEach(Self.kinds, id: \.rawValue) { kind in
                        OverlayChip(title: kind.toolLabel, systemImage: kind.toolSymbol) { onPick(.kind(kind)) }
                            .disabled(full)
                            .opacity(full ? 0.4 : 1)
                            .accessibilityIdentifier("story.add.\(kind.rawValue)")
                    }
                }
                Text(L("スタンプ", "Stickers"))
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 4)], spacing: 4) {
                    ForEach(TextOverlay.stamps, id: \.self) { emoji in
                        Button { onPick(.stamp(emoji)) } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 52, height: 52)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(full)
                        .opacity(full ? 0.4 : 1)
                        .accessibilityLabel(L("スタンプ \(emoji)", "Sticker \(emoji)"))
                    }
                }
                if full {
                    Text(L("文字と札は1枚に\(TextOverlay.maxCount)個までです",
                           "Up to \(TextOverlay.maxCount) items per photo"))
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted2)
                }
            }
            .padding(16)
        }
        .background(WebTheme.background)
    }
}
