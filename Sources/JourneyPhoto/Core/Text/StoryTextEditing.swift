import Foundation

/// ストーリーの文字を**写真の上で直接打つ**ときの決まり（`StoryTextTypingView`）。
///
/// owner・2026-09-30「文字などの入力の UI や機能にまだ納得いってない・使いづらい」。
/// 以前は「文字と札」に入る → 「文字」を押す → 下の欄を押す、の3段で、打つ欄は写真の下にあった。
/// いまは**「Aa」を押すとすぐキーボードが出て、写真の上の真ん中に大きく打つ**（Instagram と同じ形）。
///
///  - 新しい文字は空で始める。**打ち終えて空なら置かない**（見えない物を焼き込まない）
///  - 置いた文字を押すと、同じ画面で打ち直す（時刻・日付・スタンプは打ち直せない＝開かない）
///  - 見た目（白・黒・帯・縁取り）と揃えは、押すたびに次へ回す（1つのボタンに畳む）
enum StoryTextEditing {

    /// 新しい文字を置く位置（真ん中より少し上。真ん中だと写真の主役に重なりやすい）
    static let newTextY = 0.35

    /// 新しい自由な文字（空・明朝）。**1枚の上限（`TextOverlay.maxCount`）に達していれば nil**
    static func newText(in overlays: [TextOverlay]) -> TextOverlay? {
        guard overlays.count < TextOverlay.maxCount else { return nil }
        return TextOverlay(text: "", x: 0.5, y: newTextY, kind: .text, face: .mincho)
    }

    /// 押したときに打つ画面を開く札か（自由な文字・撮影地・タグ・曲。時刻・日付・スタンプは開かない）
    static func opensTyping(_ overlay: TextOverlay) -> Bool {
        overlay.kind.isEditable
    }

    /// 打ち終えた。**空になった札は取り除く**（新しく足した札も、打ち直して消した札も）
    static func finish(_ overlays: [TextOverlay], id: UUID) -> [TextOverlay] {
        overlays.filter { $0.id != id || !$0.isEmpty }
    }

    /// 見た目を次へ（白 → 黒 → 帯 → 縁取り → 白）。色の寄せ方は `TextOverlay.withStyle`。
    /// **帯で固定の札（撮影地・曲など）とスタンプは変えない**
    static func nextStyle(_ overlay: TextOverlay) -> TextOverlay {
        guard overlay.kind.forcedStyle == nil else { return overlay }
        let all = TextOverlay.Style.allCases
        let i = all.firstIndex(of: overlay.style) ?? 0
        return overlay.withStyle(all[(i + 1) % all.count])
    }

    /// 揃えを次へ（中央 → 左 → 右 → 中央）。**改行できる自由な文字だけ**
    static func nextAlign(_ overlay: TextOverlay) -> TextOverlay {
        guard overlay.kind.allowsNewlines else { return overlay }
        var next = overlay
        switch overlay.align {
        case .center: next.align = .leading
        case .leading: next.align = .trailing
        case .trailing: next.align = .center
        }
        return next
    }

    /// 画面上の写真の短い辺（pt）。写真は枠いっぱいに**埋めて**敷く（`TextOverlay.filledRect`）ので、
    /// 置いたあとの文字（`StoryCanvas`）と同じ基準になる。写真の大きさが分からなければ枠を写真とみなす。
    /// 枠が測れていなければ 0（呼ぶ側が画面の幅で代える）
    static func photoShortSide(canvas: CGSize, image: CGSize?) -> Double {
        guard canvas.width > 0, canvas.height > 0 else { return 0 }
        let rect = TextOverlay.filledRect(image: image ?? canvas, in: canvas)
        return Double(min(rect.width, rect.height))
    }

    /// 打つ画面で見せる文字の大きさ（pt）。**焼き込みと同じ式**（写真の短い辺 × 割合・`TextOverlay.fontSize`）
    /// に、画面上の写真の短い辺を入れる。分からない（0）ときは画面の幅の割合で代える
    static func typingFontSize(_ overlay: TextOverlay, photoShortSide: Double, fallbackWidth: Double) -> Double {
        let side = photoShortSide > 0 ? photoShortSide : fallbackWidth
        return max(1, side * overlay.size)
    }
}
