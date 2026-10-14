import SwiftUI

/// **一段浮かせた小さな面の地（#1A1A1C）**（v2 の板 PostSheet の印の札・StoryReplies の吹き出し・
/// SongPicker の再生の帯・2026-10-14）。
///
/// 板の3か所が同じ値を使うので1つにまとめた（画面ごとに `Color(red: 0x1A…)` を書かない）。
/// **値は土台の面の段 `surface3`**（2026-10-14 判断: 土台に入ったのでそちらから読む）
enum RaisedTile {
    /// #1A1A1C
    static let hex: UInt32 = BrandPalette.surface3

    @MainActor static let fill = WebTheme.surface3
}
