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

    /// 新しく置く札。場所は撮影地の札と同じ少し下（文字の札と重なりにくい）。
    /// **長い曲名は小さくして置く**（焼き込みは1行で折り返さないので、既定の
    /// 大きさだと「Bohemian Rhapsody · Queen」で写真の幅を超えて両端が切れる）
    static func make(for song: Photo.Song) -> TextOverlay? {
        guard let text = text(for: song) else { return nil }
        let display = TextOverlay.display(text: text, kind: .song)
        return TextOverlay(text: text, x: 0.5, y: 0.6, size: fittedSize(for: display),
                           kind: .song, face: .gothic)
    }

    /// 1行で収まる幅（短い辺に対する割合）。**写真の幅ではなく見えている幅に合わせる**
    /// ——作成画面も閲覧画面も写真を画面いっぱいに敷いて端を切るので、3:4 の縦写真
    /// だと見えるのは幅の約6割
    static let fitWidth = 0.55

    /// 1行で `fitWidth` に収まる大きさ（大きさ＝短い辺に対する字のポイント数の割合）。
    /// 字の幅は目安で、全角1・半角0.6・帯の左右の余白に1字ぶん。**下限（`minSize`）
    /// でも収まらないほど長い曲名は、はみ出したまま置く**（既知の限界）
    static func fittedSize(for text: String) -> Double {
        let fit = fitWidth / ems(text)
        return max(TextOverlay.minSize, min(TextOverlay.defaultSize, fit))
    }

    /// 1行の幅の目安（字の大きさを1とした幅）。全角1・半角0.6・帯の余白に1字ぶん
    static func ems(_ text: String) -> Double {
        text.reduce(1.0) { width, char in width + (char.isASCII ? 0.6 : 1.0) }
    }

    /// 曲を変えた・外したときに、**前の曲の札だけ**を直す（変えたら文字を
    /// 差し替え、外したら消す）。自分で打ち直した札・「曲」の道具で置いた
    /// 別の文字の札には触らない。戻り値の `found` は前の曲の札があったか
    static func retext(_ overlays: [TextOverlay], from old: Photo.Song?,
                       to new: Photo.Song?) -> (overlays: [TextOverlay], found: Bool) {
        // 置くときに上限で切っているので、比べる側も切ってそろえる
        guard let old, let oldText = text(for: old).map({ String($0.prefix(TextOverlay.maxLength)) })
        else { return (overlays, false) }
        let isOld: (TextOverlay) -> Bool = { $0.kind == .song && $0.text == oldText }
        guard overlays.contains(where: isOld) else { return (overlays, false) }
        guard let new, let newText = text(for: new) else {
            return (overlays.filter { !isOld($0) }, true)
        }
        let updated = overlays.map { overlay -> TextOverlay in
            guard isOld(overlay) else { return overlay }
            var changed = overlay
            changed.text = String(newText.prefix(TextOverlay.maxLength))
            // **置いたときの大きさの比で変える。** 手を付けていない札は新しい曲名で
            // 置いたときと同じ大きさになり、自分で大きく・小さくした分は倍率として残る。
            // 曲を行き来しても元に戻る（下限・上限で切られたときだけは戻りきらない）
            let before = fittedSize(for: TextOverlay.display(text: overlay.text, kind: .song))
            let after = fittedSize(for: TextOverlay.display(text: changed.text, kind: .song))
            changed.size = TextOverlay.clampSize(overlay.size * after / before)
            return changed
        }
        return (updated, true)
    }
}
