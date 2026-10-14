import SwiftUI

/// **一段浮かせた小さな面の地（#1A1A1C）**（v2 の板 PostSheet の印の札・StoryReplies の吹き出し・
/// SongPicker の再生の帯・2026-10-14）。
///
/// 板の3か所が同じ値を使うので1つにまとめた（画面ごとに `Color(red: 0x1A…)` を書かない）。
/// 土台（`WebTheme`）の面は surface-1 #0E0E0F・surface-2 #161617 までで、その一段上の面はまだ無い。
/// 土台の値は変えない決まりなので、ここに置く（土台に入ったらそちらへ寄せる）
enum RaisedTile {
    /// #1A1A1C
    static let hex: UInt32 = 0x1A1A1C

    @MainActor static let fill = Color(red: Double((hex >> 16) & 0xFF) / 255,
                                       green: Double((hex >> 8) & 0xFF) / 255,
                                       blue: Double(hex & 0xFF) / 255)
}
