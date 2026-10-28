import Foundation

/// 曲を選んだら写真に置く「♪ 曲名 · アーティスト」の札（`TextOverlay` の `.song`）。
///
/// 以前は写真の上に**動かせない**チップを出していた。札にすれば、ほかの
/// 文字と同じく動かす・大きさを変える・回す・消すができ、投稿すると画像に
/// 焼き込まれる（`TextOverlayRenderer`）。
///
/// **閲覧画面の「♪」の行は残す。** Web から投稿したストーリーには札が無く、
/// 曲名を出せるのはあの行だけ。札は投稿者が置く飾りの扱い。
///
/// 2026-10-28: 札は**6つの形**（`SongStickerStyle`）を持ち、押すたびに替わる（`cycled`）。
/// 曲を変えた・外したとき（`retext`・`shouldDetach`・`isOnPhoto`）は**形を問わず同じに動く**
/// ——どれも文字（「曲名 · 歌手」）で札を見分け、形は見ない。
enum SongSticker {

    /// 札の文字（「曲名 · アーティスト」）。題が空なら置かない
    /// **改行は空白にする**（札は1行・`TextOverlay.cleaned` が改行を空白に置き換える）。そのままだと
    /// 置いた札と文字が食い違い、札が「付けた曲の札」と見なされず帯と二重に出た（27430f2b のレビュー）
    static func text(for song: Photo.Song) -> String? {
        let title = TextOverlay.cleaned(song.title, kind: .song).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = TextOverlay.cleaned(song.artist ?? "", kind: .song).trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? title : "\(title) · \(artist)"
    }

    /// この写真に**いまの曲の札**が焼き込まれるか（見る画面の ♪ の行を出さない印・`songOnPhoto`）。
    /// 作る画面の `currentHasSongSticker` と同じ判定——種類だけで見ると、文字を消した札
    /// （焼き込まれない）・前の曲の札・自分で打った「曲」の札でも立ち、**曲名がどこにも
    /// 出ない**投稿ができた（686566d のレビュー）
    static func isOnPhoto(_ overlays: [TextOverlay], song: Photo.Song?) -> Bool {
        guard let song, let text = text(for: song) else { return false }
        let placed = String(text.prefix(TextOverlay.maxLength))
        return overlays.contains { $0.kind == .song && !$0.isEmpty && $0.text == placed }
    }

    /// `overlay` が**付けた曲の札**か（`retext` と同じ判定: 種類が曲で、文字がいまの曲名）。
    /// 自分で打った別の文字の「曲」の札は当たらない
    static func isSticker(_ overlay: TextOverlay, of song: Photo.Song?) -> Bool {
        guard let song, let text = text(for: song) else { return false }
        return overlay.kind == .song && overlay.text == String(text.prefix(TextOverlay.maxLength))
    }

    /// 札を消したあとに**曲も外すか**。付けた曲の札を消して、どの写真にも（打ち直していない）
    /// その曲の札が残っていなければ外す（Instagram と同じ）。別の写真に残っていれば、曲はそこで
    /// 見えているので外さない
    static func shouldDetach(removedSticker: Bool, remaining: [[TextOverlay]], song: Photo.Song?) -> Bool {
        guard removedSticker, song != nil else { return false }
        return !remaining.contains { $0.contains { isSticker($0, of: song) } }
    }

    /// 札に描く曲名と歌手（`text(for:)` と同じ整え方・改行は空白）。題が空なら nil
    static func parts(for song: Photo.Song) -> (title: String, artist: String?)? {
        let title = TextOverlay.cleaned(song.title, kind: .song).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = TextOverlay.cleaned(song.artist ?? "", kind: .song).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, artist.isEmpty ? nil : artist)
    }

    /// 新しく置く札。場所は撮影地の札と同じ少し下（文字の札と重なりにくい）。
    /// **長い曲名は小さくして置く**（焼き込みは1行で折り返さないので、既定の
    /// 大きさだと「Bohemian Rhapsody · Queen」で写真の幅を超えて両端が切れる）。
    /// `style` は札の形（作る画面は端末に覚えた形 `SongStickerStyle.remembered()`）。
    /// nil は文字だけの札（前の版の札）
    static func make(for song: Photo.Song, style: SongStickerStyle?) -> TextOverlay? {
        guard let text = text(for: song) else { return nil }
        var overlay = TextOverlay(text: text, x: 0.5, y: 0.6, size: TextOverlay.defaultSize,
                                  kind: .song, face: .gothic)
        overlay.songStyle = style
        overlay.size = fittedSize(for: overlay, song: song)
        return overlay
    }

    /// 札の形のとき、その札（`overlay`）に描く形。**付けた曲の札で形を持つときだけ**
    /// （自分で打った「曲」の札・前の版の文字だけの札・曲を外した後の札は文字のまま描く）
    static func shape(of overlay: TextOverlay, song: Photo.Song?) -> SongStickerStyle? {
        guard let style = overlay.songStyle, isSticker(overlay, of: song) else { return nil }
        return style
    }

    /// 札を押した（2026-10-28・Instagram と同じく押すたびに形が替わる）。A→B→…→F→A。
    /// 文字だけの札（前の版）は A から。**大きさは置いたときの大きさの比で替える**——形ごとに
    /// 幅が違うので、そのままだとジャケット大で写真からはみ出す。自分で大きく・小さくした分は倍率で残る
    static func cycled(_ overlay: TextOverlay, song: Photo.Song) -> TextOverlay {
        var next = overlay
        next.songStyle = overlay.songStyle?.next ?? .glass
        let before = fittedSize(for: overlay, song: song)
        let after = fittedSize(for: next, song: song)
        next.size = next.clampedSize(overlay.size * after / before)
        return next
    }

    /// その札を置いたときの大きさ（形があれば形の幅、無ければ文字の幅で決める）
    static func fittedSize(for overlay: TextOverlay, song: Photo.Song) -> Double {
        guard let style = overlay.songStyle, let parts = parts(for: song) else {
            return fittedSize(for: TextOverlay.display(text: overlay.text, kind: .song))
        }
        let width = SongStickerLayout.estimatedWidth(style: style, title: parts.title, artist: parts.artist)
        return max(SongStickerStyle.minSize, min(SongStickerStyle.defaultSize, SongStickerStyle.fitWidth / width))
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
            // 形のある札は**形の幅の比**で変える（形はそのまま・2026-10-28）
            if overlay.songStyle != nil {
                changed.size = changed.clampedSize(
                    overlay.size * fittedSize(for: changed, song: new) / fittedSize(for: overlay, song: old))
                return changed
            }
            // **置いたときの大きさの比で変える。** 手を付けていない札は新しい曲名で
            // 置いたときと同じ大きさになり、自分で大きく・小さくした分は倍率として残る。
            // 曲を行き来しても元に戻る。**例外は下限・上限で切られたとき**——最小まで
            // 小さくした札を長い曲名に変えて戻すと、ほぼ既定の大きさに戻る（見た目だけ。
            // 直すには札ごとに切る前の倍率を覚える必要があり、見送った）
            let before = fittedSize(for: TextOverlay.display(text: overlay.text, kind: .song))
            let after = fittedSize(for: TextOverlay.display(text: changed.text, kind: .song))
            changed.size = TextOverlay.clampSize(overlay.size * after / before)
            return changed
        }
        return (updated, true)
    }
}
