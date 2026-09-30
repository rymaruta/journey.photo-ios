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

    /// 打つ画面で縮めて見せる下限（これより小さいと字もキャレットも掴めない）
    static let minFitScale = 0.35

    /// 打つ画面で文字を縮めて見せる倍率（`minFitScale`〜1）。**文字そのものの大きさは変えない**。
    /// `available` は打つ画面の空き（左の縦のつまみを避けた幅・キーボードの上の高さ）で、
    /// **写真の枠ではない**——写真からはみ出すかは `overflow` で別に見る（同じ物差しにすると、
    /// 写真に収まる11〜14字の一言でも「写真の幅を超えています」と出た・ab63fb0 のレビュー）。
    /// 横に流さないのは、キャレットが画面の外へ出て追えなかったから（92a38d7 のレビュー）
    static func fitScale(content: CGSize, available: CGSize, minimum: Double = minFitScale) -> Double {
        guard content.width.isFinite, content.height.isFinite,
              available.width > 0, available.height > 0 else { return 1 }
        var scale = 1.0
        if content.width > available.width { scale = min(scale, Double(available.width / content.width)) }
        if content.height > available.height { scale = min(scale, Double(available.height / content.height)) }
        return max(minimum, scale)
    }

    /// 仕上がりが画面（写真の枠）からはみ出す向き。置いたあと・焼き込みは折り返さず、
    /// 枠の外は切れる。打つ画面はこれで断り書きを出す
    struct Overflow: Equatable {
        var width = false
        var height = false
        var any: Bool { width || height }
    }

    /// 札の**置き場所（中心）と回しを入れて**、仕上がりが枠からはみ出すか。大きさだけで比べると、
    /// 端に寄せた札は収まる大きさでも切れるのに断らず、縦に回した長い札は収まるのに断った
    /// （9702932 のレビュー）。`content` は回す前の大きさ
    static func overflow(content: CGSize, center: CGPoint, rotation: Double, canvas: CGSize) -> Overflow {
        guard canvas.width > 0, canvas.height > 0, content.width > 0, content.height > 0 else { return Overflow() }
        let c = abs(cos(rotation)), s = abs(sin(rotation))
        let w = Double(content.width) * c + Double(content.height) * s
        let h = Double(content.width) * s + Double(content.height) * c
        let x = Double(center.x), y = Double(center.y)
        let tolerance = 0.5
        return Overflow(width: x - w / 2 < -tolerance || x + w / 2 > Double(canvas.width) + tolerance,
                        height: y - h / 2 < -tolerance || y + h / 2 > Double(canvas.height) + tolerance)
    }

    /// 打つ画面の並べ方（縮み・横のずらし・下寄せ）
    struct TypingLayout: Equatable {
        var scale: Double
        /// 真ん中に置いた位置から横にずらす量（pt・縮めた後の見た目の座標）。**キャレット（最終行の末尾）が
        /// 枠に入るように**ずらす。端に寄せる形では、寄るのが欄全体の端でキャレットではないので、
        /// 前の行が長いと打っている行が丸ごと外に出た（fb7acab のレビュー）
        var offsetX: Double
        /// 縮めても縦に収まらないとき、下（いま打っている最終行）を見せる
        var pinBottom: Bool
    }

    /// 打つ画面の並べ方を決める。`typing`（欄に見えている大きさ・帯の余白込み）を打つ画面の空き
    /// `available` に縮めて収める。縮めても枠 `area` の幅を超えるときは、揃えの側を見せつつ
    /// **キャレット（最終行の末尾）が枠に入るよう**横にずらす。
    ///  - `lastLineWidth`: 最終行の幅（帯の余白を除く）。`padding`: 帯の左右の余白（無ければ 0）
    /// **はみ出しの断り（`overflow`）は別の物差し**（仕上がり×写真の枠）なので、ここでは決めない
    static func typingLayout(overlay: TextOverlay, typing: CGSize, lastLineWidth: Double, padding: Double = 0,
                             available: CGSize, area: CGSize) -> TypingLayout {
        let scale = fitScale(content: typing, available: available)
        let width = Double(typing.width) * scale
        let frame = Double(area.width)
        let pinBottom = Double(typing.height) * scale > Double(area.height) + 0.5
        guard width > frame + 0.5 else { return TypingLayout(scale: scale, offsetX: 0, pinBottom: pinBottom) }
        // 縮めた欄の左端を x、枠の左端を 0 とする。真ん中に置いたときの左端
        let centered = (frame - width) / 2
        // キャレットの位置（欄の左端から）。改行の無い文字・1行の札は行の末尾＝欄の右端
        let multiline = overlay.kind.allowsNewlines && overlay.text.contains("\n")
        let align: TextOverlay.Align = multiline ? overlay.align : .trailing
        let caret: Double
        let preferred: Double
        switch align {
        case .leading:
            caret = (padding + lastLineWidth) * scale
            preferred = 0
        case .center:
            caret = (width + lastLineWidth * scale) / 2
            preferred = centered
        case .trailing:
            caret = width - padding * scale
            preferred = frame - width
        }
        // 揃えの側を見せる位置から始め、キャレットが枠の外なら入る所までずらす
        let left = min(max(preferred, -caret), frame - caret)
        return TypingLayout(scale: scale, offsetX: left - centered, pinBottom: pinBottom)
    }

    /// 最終行（キャレットのいる行）の文字。札は印ごと（1行しか無いので同じ）
    static func lastLine(_ overlay: TextOverlay) -> String {
        overlay.displayText.components(separatedBy: "\n").last ?? ""
    }

    /// 打つ画面で大きさを測る文字。**欄に見えている行を全部数える**——置いたあとの `drawnText` は
    /// 最後の改行を落とすので、「港⏎」の直後に欄は2行なのに1行で測り、縮め足りなかった。
    /// 空なら入力の見本で測る（**空白や改行だけは空とみなさない**＝欄にはその行がある）
    static func typingMeasureText(_ overlay: TextOverlay, placeholder: String) -> String {
        guard !overlay.text.isEmpty else { return TextOverlay.display(text: placeholder, kind: overlay.kind) }
        let shown = overlay.displayText
        // 最後の空の行は、測る文字の側では字が無いと数えられないので、空白を1つ置く
        return shown.hasSuffix("\n") ? shown + " " : shown
    }

    // MARK: - 指で直接動かす（「文字と札」に入らずに・2026-09-30）

    /// 画面に置かれた札の場所（画面の座標）。指の下の札を探すのに使う
    struct Placed: Equatable {
        let id: UUID
        let center: CGPoint
        /// 回す前の大きさ（帯の余白込み）
        let size: CGSize
        /// 回し（ラジアン）
        let rotation: Double
    }

    /// 2本指の操作で、指の下の札を探す余白（pt）。小さな札でも指の間に挟めるように少し広げる
    static let pinchSlop = 24.0

    /// `point` の下にある札。**まず指の真下（余白なし・上に重なっている方を先に）**、無ければ余白の
    /// 内側で中心がいちばん近い札。余白だけで上から当てると、あとから置いた札の余白が下の札の真上を
    /// 覆って違う札が動き、大きな帯の余白が写真の拡大を奪った（81cbd07 のレビュー）
    static func overlay(at point: CGPoint, in placed: [Placed], slop: Double = pinchSlop) -> UUID? {
        func local(_ item: Placed) -> (x: Double, y: Double) {
            let dx = Double(point.x - item.center.x), dy = Double(point.y - item.center.y)
            let c = cos(-item.rotation), s = sin(-item.rotation)
            return (dx * c - dy * s, dx * s + dy * c)
        }
        func inside(_ item: Placed, margin: Double) -> Bool {
            let p = local(item)
            return abs(p.x) <= Double(item.size.width) / 2 + margin && abs(p.y) <= Double(item.size.height) / 2 + margin
        }
        if let hit = placed.reversed().first(where: { inside($0, margin: 0) }) { return hit.id }
        return placed.filter { inside($0, margin: slop) }
            .min { a, b in
                let pa = local(a), pb = local(b)
                return pa.x * pa.x + pa.y * pa.y < pb.x * pb.x + pb.y * pb.y
            }?.id
    }

    /// 2本指の操作（回す・つまむ）が効く相手
    enum GestureTarget: Equatable {
        case overlay(UUID)
        case photo
    }

    /// 2本指の操作の相手を決める。**回すとつまむは同じ相手に**——別々に決めると、認識される時刻の
    /// ずれで札は大きくなり写真は回った。順は: もう片方の操作の相手 → 1本指で運んでいる札（指が乗って
    /// いる。選んだ別の札より先——選んだ札が回った・4ed53ca のレビュー）→ 選んだ札 → 指の下の札 → 写真。
    /// `dragging` は**まだ相殺されていない**運びだけを渡す
    static func gestureTarget(other: GestureTarget?, selected: UUID?, dragging: UUID?,
                              under: () -> UUID?) -> GestureTarget {
        if let other { return other }
        if let id = dragging ?? selected ?? under() { return .overlay(id) }
        return .photo
    }

    /// 真ん中の目安に吸い付く距離（pt）
    static let snapDistance = 8.0

    /// 動かしている札の中心を、画面の真ん中の縦・横の線に吸い付ける。吸い付いた向きを返す（線を出す）
    static func snap(_ point: CGPoint, canvas: CGSize, distance: Double = snapDistance)
        -> (point: CGPoint, vertical: Bool, horizontal: Bool) {
        guard canvas.width > 0, canvas.height > 0 else { return (point, false, false) }
        var result = point
        let midX = canvas.width / 2, midY = canvas.height / 2
        let vertical = abs(Double(point.x - midX)) <= distance
        let horizontal = abs(Double(point.y - midY)) <= distance
        if vertical { result.x = midX }
        if horizontal { result.y = midY }
        return (result, vertical, horizontal)
    }

    /// ゴミ箱の中心（画面の下の真ん中・左下の写真の並びより上）と、指が入ったとみなす半径
    static let trashBottomInset = 120.0
    static let trashRadius = 44.0

    static func trashCenter(canvas: CGSize) -> CGPoint {
        CGPoint(x: canvas.width / 2, y: max(0, canvas.height - trashBottomInset))
    }

    /// 動かしている指がゴミ箱の上にあるか（**札の中心ではなく指の位置**で見る——大きな札を
    /// ゴミ箱まで運ぶのに、札の中心まで重ねさせない）
    static func isOverTrash(_ finger: CGPoint, canvas: CGSize) -> Bool {
        guard canvas.width > 0, canvas.height > 0 else { return false }
        let c = trashCenter(canvas: canvas)
        let dx = Double(finger.x - c.x), dy = Double(finger.y - c.y)
        return dx * dx + dy * dy <= trashRadius * trashRadius
    }

    /// ゴミ箱が効くか。**指がいったんゴミ箱の外にいたことがある回だけ**（`armed`）——下の真ん中に
    /// 置いた札を少しずらしただけで消えた（81cbd07 のレビュー）
    static func trashArmed(wasArmed: Bool, finger: CGPoint, canvas: CGSize) -> Bool {
        wasArmed || !isOverTrash(finger, canvas: canvas)
    }
}
