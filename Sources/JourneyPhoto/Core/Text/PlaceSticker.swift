import Foundation

/// 場所ツールで決めた撮影地を写真に置く「📍 撮影地」の札（`TextOverlay` の `.place`）。
///
/// 札 #499（owner 2026-11-08・TestFlight 1.1.72）:「場所などを入力した後、自由に場所を動かせない」。
/// 原因は、場所ツールで決めた撮影地が**動かせない固定の札**（`StoryComposerView.captionBlock` の `photoChip`）
/// だったこと（コードを読んで確かめた・曲の札と文字の札は `StoryCanvas` の操作で動く）。
/// 曲の札（`SongSticker`）と同じく動かせる札にし、投稿すると画像に焼き込まれる（`TextOverlayRenderer`）。
///
/// 2026-11-08 判断（owner・札 #499）: **`location`・`coords` は今までどおり送る**（撮影スポットへのひも付けを保つ）。
/// 札を焼き込んだ1本は `locationOnPhoto` を立てて送り、見る画面は固定の撮影地の札を出さない（二重に見えない）。
/// 曲の札と同じく、札と撮影地の文字は**文字で見分ける**（自分で打った別の「撮影地」の札は付けた撮影地ではない）。
enum PlaceSticker {

    /// 札に入れる文字（置くときに上限で切る）。空白だけなら nil
    static func text(for location: String) -> String? {
        let cleaned = TextOverlay.cleaned(location, kind: .place).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(TextOverlay.maxLength))
    }

    /// 置く縦の位置の候補（真ん中より少し下から。曲の札・トレイの撮影地の札と同じ 0.6 が先頭）
    static let rows: [Double] = [0.6, 0.7, 0.8, 0.4, 0.3]
    /// 近いとみなす縦の差（札の高さほど）
    static let rowGap = 0.07

    /// 新しく置く札。**すでにある札と縦に重ならない最初の位置**に置く（曲の札も 0.6 に置くため）。全部ふさがっていれば先頭
    static func make(for location: String, avoiding overlays: [TextOverlay] = []) -> TextOverlay? {
        guard let text = text(for: location) else { return nil }
        let y = rows.first { row in !overlays.contains { abs($0.y - row) < rowGap } } ?? rows[0]
        return TextOverlay(text: text, x: 0.5, y: y, kind: .place, face: .gothic)
    }

    /// `overlay` が**付けた撮影地の札**か（種類が撮影地で、文字がいまの撮影地）
    static func isSticker(_ overlay: TextOverlay, of location: String) -> Bool {
        guard let text = text(for: location) else { return false }
        return overlay.kind == .place && overlay.text == text
    }

    /// この写真に**いまの撮影地の札**が焼き込まれるか（`locationOnPhoto` を立てる・固定の札を出さない印）。
    /// 文字を消した札は焼き込まれないので数えない（`SongSticker.isOnPhoto` と同じ）
    static func isOnPhoto(_ overlays: [TextOverlay], location: String) -> Bool {
        overlays.contains { !$0.isEmpty && isSticker($0, of: location) }
    }

    /// どれかの写真に付けた撮影地の札があるか（札を消したあとに撮影地も外すかの判定）
    static func isOnAnyPhoto(_ shots: [[TextOverlay]], location: String) -> Bool {
        shots.contains { isOnPhoto($0, location: location) }
    }

    /// 撮影地を決めた・直した・外したときの札の置き換え。
    /// 前の札があれば**位置・大きさを残して**文字だけ差し替え、無くなれば（空にした）取り除く。
    /// `found` は前の札があったか（無ければ呼ぶ側がいまの1枚に置く）
    static func retext(_ overlays: [TextOverlay], from old: String,
                       to new: String) -> (overlays: [TextOverlay], found: Bool) {
        guard text(for: old) != nil, overlays.contains(where: { isSticker($0, of: old) }) else {
            return (overlays, false)
        }
        guard let newText = text(for: new) else {
            return (overlays.filter { !isSticker($0, of: old) }, true)
        }
        return (overlays.map { overlay in
            guard isSticker(overlay, of: old) else { return overlay }
            var changed = overlay
            changed.text = newText
            return changed
        }, true)
    }

    /// 札を消したあとに**撮影地も外すか**。付けた撮影地の札を消して、どの写真にもその札が残っていなければ外す
    /// （曲の札と同じ・`SongSticker.shouldDetach`）。札だけ消えて撮影地が黙って残ると、画面から付いていると分からない。
    /// 別の写真に残っていれば、撮影地はそこで見えているので外さない
    static func shouldDetach(removedSticker: Bool, remaining: [[TextOverlay]], location: String) -> Bool {
        guard removedSticker, text(for: location) != nil else { return false }
        return !isOnAnyPhoto(remaining, location: location)
    }
}

/// 見る画面で、撮影地の札を焼き込んだ1本にも**撮影スポットへの小さな導線**を残すか（札 #499 の直し）。
/// 固定の札を出さない（二重に見えない）一方、スポットに結べたときのガイドを開く・行きたいの口は消さない。
enum StoryPlaceLink {
    /// 焼き込み済み（固定の札を出さない）で、撮影地があり、スポットに結べたときだけ導線を出す。
    /// 固定の札が出ている1本は、札そのものが導線なので別には出さない
    static func entry(showsCard: Bool, location: String?, spotLinked: Bool) -> String? {
        guard !showsCard, spotLinked, let location, !location.isEmpty else { return nil }
        return location
    }
}
