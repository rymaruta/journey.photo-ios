import Foundation

/// 曲を選んだら写真に置く「♪ 曲名 · アーティスト」の札（`TextOverlay` の `.song`）。
///
/// 以前は写真の上に**動かせない**チップを出していた。札にすれば、ほかの
/// 文字と同じく動かす・大きさを変える・回す・消すができ、投稿すると画像に
/// 焼き込まれる（`TextOverlayRenderer`）。
///
/// **閲覧画面の「♪」の行は残す。** Web から投稿したストーリーには札が無く、
/// 曲名を出せるのはあの行だけ。札は投稿者が置く飾りの扱い。
enum SongSticker {

    /// 札の文字（「曲名 · アーティスト」）。題が空なら置かない
    static func text(for song: Photo.Song) -> String? {
        let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? title : "\(title) · \(artist)"
    }

    /// 新しく置く札。場所は撮影地の札と同じ少し下（文字の札と重なりにくい）
    static func make(for song: Photo.Song) -> TextOverlay? {
        guard let text = text(for: song) else { return nil }
        return TextOverlay(text: text, x: 0.5, y: 0.6, kind: .song, face: .gothic)
    }

    /// 曲を変えた・外したときに、**前の曲の札だけ**を直す（変えたら文字を
    /// 差し替え、外したら消す）。自分で打ち直した札・「曲」の道具で置いた
    /// 別の文字の札には触らない。戻り値の `found` は前の曲の札があったか
    static func retext(_ overlays: [TextOverlay], from old: Photo.Song?,
                       to new: Photo.Song?) -> (overlays: [TextOverlay], found: Bool) {
        guard let old, let oldText = text(for: old) else { return (overlays, false) }
        let isOld: (TextOverlay) -> Bool = { $0.kind == .song && $0.text == oldText }
        guard overlays.contains(where: isOld) else { return (overlays, false) }
        guard let new, let newText = text(for: new) else {
            return (overlays.filter { !isOld($0) }, true)
        }
        let updated = overlays.map { overlay -> TextOverlay in
            guard isOld(overlay) else { return overlay }
            var changed = overlay
            changed.text = String(newText.prefix(TextOverlay.maxLength))
            return changed
        }
        return (updated, true)
    }
}
