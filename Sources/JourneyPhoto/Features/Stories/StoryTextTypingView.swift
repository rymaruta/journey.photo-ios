import SwiftUI

/// **写真の上で直接打つ画面**（Instagram と同じ形・`StoryTextEditing`）。
///
/// owner・2026-09-30「文字などの入力の UI や機能にまだ納得いってない・使いづらい」
/// （打つまでの手数・写真の上で打てない・下の欄がごちゃごちゃ・動かす消す直すが面倒、の4つ全部）。
///
///  - 開いたらすぐキーボード。文字は**真ん中に、仕上がりと同じ書体・色・見た目・大きさ**で出る
///    （大きさは焼き込みと同じ式・`StoryTextEditing.typingFontSize`）
///  - **キーボードの上は1列だけ**（かんたん版・owner 2026-10-02「めっちゃいい」）:
///    「Aa 明朝」の書体ボタン（押すたびに次の書体）・背景ボタン（無し → 帯 → 縁取り）・
///    色の丸4つ（「ほかの色」で12色と好きな色の列に替わる）・消す（ゴミ箱・危険の赤）。
///    回し方と色の寄せ方は `StorySimpleRules`
///  - 大きさは左の縦のつまみ。揃えは左上のボタンを押すたびに次へ。右上は白い「完了」
///  - 「完了」か、文字の外を押すと確定。**空なら置かない**（呼ぶ側が `StoryTextEditing.finish` を通す）
///
/// 写真の上に置くのは白だけ（デザインシステム「黒塗りの真鍮」: 写真の上に真鍮を置かない）。
/// 押せる所は 44pt。
struct StoryTextTypingView: View {

    @Binding var overlay: TextOverlay
    /// 画面上の写真の短い辺（pt）。**焼き込みと同じ大きさで見せる**ため。分からなければ 0
    let photoShortSide: Double
    /// 写真の枠（打ち始めた瞬間・キーボードが出る前）と、その中に埋めて敷いた写真の場所。
    /// **仕上がりがはみ出すかは、札の置き場所と回しを入れてこの枠と比べる**（打つ画面の空きではない）。
    /// 測れていなければ 0（打つ画面の大きさで代える）
    let canvas: CGSize
    let photo: CGRect
    /// ゴミ箱。**打っている札を消す**（呼ぶ側が空にして `onDone` と同じ片付けを通す）
    var onDelete: () -> Void
    var onDone: () -> Void

    @FocusState private var focused: Bool
    /// 色の丸4つの代わりに、12色と好きな色の列（`OverlayInkRow`）を出している
    @State private var showAllInks = false

    var body: some View {
        GeometryReader { geometry in
            let fontSize = StoryTextEditing.typingFontSize(overlay, photoShortSide: photoShortSide,
                                                           fallbackWidth: Double(geometry.size.width))
            ZStack {
                // 写真を暗くする（打っている文字だけを見せる）。**押すと確定**
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDone() }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                    // **打つ欄は折り返さない**（置いたあとの `StoryCanvas` も焼き込みも折り返さない。
                    // 欄の幅で折り返すと、完了した途端に1行の長い帯になって写真からはみ出した・
                    // 4ffb74f のレビュー）。写真の幅（高さ）を超える文字は**縮めて見せて、そう伝える**
                    // ——横に流すとキャレットが画面の外へ出て追えず、流す指でキーボードも閉じた
                    // （92a38d7 のレビュー）
                    GeometryReader { area in
                        // はみ出しの断りは**仕上がり×写真の枠（置き場所・回し込み）**で決める。
                        // 枠が測れていなければ断らない（キーボードで縮んだ打つ画面で代えると断りすぎる）
                        let overflow = overlay.isEmpty || canvas.width <= 0 || canvas.height <= 0
                            ? StoryTextEditing.Overflow()
                            : StoryTextEditing.overflow(content: finishedSize(fontSize: fontSize),
                                                        center: overlay.center(in: photo),
                                                        rotation: overlay.rotation, canvas: canvas)
                        let noticeShown = overflow.any
                        let available = CGSize(width: max(0, area.size.width - Self.sideInset * 2),
                                               height: max(0, area.size.height - 24 - (noticeShown ? Self.noticeHeight : 0)))
                        let space = CGSize(width: area.size.width,
                                           height: max(0, area.size.height - (noticeShown ? Self.noticeHeight : 0)))
                        // 寄せる枠は**左の縦のつまみの内側**（左に寄せた行頭がつまみの下に潜らない）
                        let pinArea = CGSize(width: max(0, space.width - Self.sideInset * 2), height: space.height)
                        let lastLine = TextOverlayRenderer.naturalSize(overlay, text: StoryTextEditing.lastLine(overlay),
                                                                       fontSize: fontSize).width
                        let layout = StoryTextEditing.typingLayout(
                            overlay: overlay, typing: typingSize(fontSize: fontSize), lastLineWidth: Double(lastLine),
                            padding: overlay.style == .banner ? fontSize * 0.35 : 0,
                            available: available, area: pinArea)
                        // 縦だけ端に寄せる（下＝打っている最終行）。横は真ん中に置いてからキャレットの側へずらす
                        let vertical: (alignment: Alignment, anchor: UnitPoint) = layout.pinBottom
                            ? (.bottom, .bottom) : (.center, .center)
                        ZStack {
                            // 欄の外の空いた所を押しても確定する（暗幕の上を覆うので、暗幕の
                            // 「押すと確定」が届かない）。**欄の後ろに敷く**——前だと欄にピントが入らない
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { onDone() }
                                .accessibilityHidden(true)
                            // 縮めても空きに収まらないときは、キャレット（最終行の末尾）が見える所まで横にずらし、
                            // 縦は下（打っている最終行）に寄せる
                            field(fontSize: fontSize)
                                .scaleEffect(layout.scale, anchor: vertical.anchor)
                                // **大きさを決め打ちにした枠で寄せる**。上限だけの枠（maxWidth: .infinity）は
                                // 中身が大きいと中身の大きさになり、寄せ方が効かずに真ん中へ置かれ、長い文字が
                                // 画面から丸ごと消えた（ea8fa74 のレビュー）
                                .frame(width: pinArea.width, height: pinArea.height, alignment: vertical.alignment)
                                .offset(x: layout.offsetX)
                                // 寄せる枠をつまみの内側に置く（外へはみ出した分は下の clipped が切る）
                                .frame(width: space.width, height: space.height)
                                // 見本の位置: 断り書きの分だけ上に寄せる（字の下端に重ねない）
                                .padding(.bottom, noticeShown ? Self.noticeHeight : 0)
                        }
                        .frame(width: area.size.width, height: area.size.height)
                        // 収まり切らない分を、上のバーと下の列の上に描かない。**当たり判定も枠に閉じる**
                        // （`clipped` は見た目だけを切る——切れた所が「完了」の上にかぶって指を取りうる）
                        .clipped()
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if overflow.any {
                                Text(Self.notice(overflow))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.6), in: Capsule())
                            }
                        }
                    }
                    if overlay.kind.hasTypography {
                        paletteRow
                            .padding(.bottom, 8)
                    }
                }

                if overlay.kind.hasTypography {
                    sizeSlider
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                }
            }
        }
        // 画面が差し込まれた後に1拍おいてから（同じ更新でひとことの欄のピントが外れる）
        .task { focused = true }
        // **VoiceOver では打つ画面だけを読む**（後ろの「ストーリーに投稿」や他の札に移れた・
        // 4ffb74f のレビュー）。2本指の Z でも確定して閉じる
        // 入れ物を1つの読み上げの単位にしてから付ける（子それぞれに配られると、1つの要素に閉じ込められる）
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onDone() }
    }

    /// 左の縦のつまみと重ねない左右の逃げ
    static let sideInset: Double = 56
    /// 断り書きの帯の高さ（字の下端に重ねないよう、その分だけ上に寄せる）
    static let noticeHeight: Double = 28

    static func notice(_ overflow: StoryTextEditing.Overflow) -> String {
        switch (overflow.width, overflow.height) {
        case (true, true): return L("写真の幅と高さを超えています。はみ出た所は切れます",
                                    "Larger than the photo. The overflow will be cut off")
        case (false, true): return L("写真の高さを超えています。はみ出た所は切れます",
                                     "Taller than the photo. The overflow will be cut off")
        default: return L("写真の幅を超えています。はみ出た所は切れます",
                          "Wider than the photo. The overflow will be cut off")
        }
    }

    /// 欄に見えている大きさ（最後の空の行・見本の文字まで数える・帯の余白込み）
    private func typingSize(fontSize: Double) -> CGSize {
        let text = StoryTextEditing.typingMeasureText(overlay, placeholder: L("文字を入力", "Type something"))
        var size = TextOverlayRenderer.naturalSize(overlay, text: text, fontSize: fontSize)
        // 打てる欄は測った幅に少し足して渡している（`typingFieldWidth`）。その分も数える
        if overlay.kind.isEditable,
           let width = StoryTextEditing.typingFieldWidth(measured: Double(size.width), fontSize: fontSize) {
            size.width = CGFloat(width)
        }
        return padded(size, fontSize: fontSize)
    }

    /// 仕上がり（置いたあと・焼き込み）の大きさ。焼き込みと同じ測り方
    private func finishedSize(fontSize: Double) -> CGSize {
        padded(TextOverlayRenderer.naturalSize(overlay, fontSize: fontSize), fontSize: fontSize)
    }

    private func padded(_ text: CGSize, fontSize: Double) -> CGSize {
        let banner = overlay.style == .banner
        return CGSize(width: text.width + (banner ? fontSize * 0.7 : 0),
                      height: text.height + (banner ? fontSize * 0.35 : 0))
    }

    // MARK: - 上のバー

    private var topBar: some View {
        HStack(spacing: 4) {
            // 揃え（改行できる自由な文字だけ）。押すたびに 中央 → 左 → 右
            if overlay.kind.allowsNewlines {
                roundButton(symbol: overlay.align.symbol, label: overlay.align.label) {
                    overlay = StoryTextEditing.nextAlign(overlay)
                }
            }
            Spacer()
            // 白い「完了」（写真の上なので白・板「黒塗りの真鍮」）
            Button(action: onDone) {
                Text(L("完了", "Done"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(WebTheme.accentBackground, in: Capsule())
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("story.typing.done")
        }
    }

    private func roundButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - 打つ欄（仕上がりと同じ見た目）

    private func field(fontSize: Double) -> some View {
        HStack(spacing: fontSize * 0.2) {
            // 札の印（📍 # ♪）。**置いたあと（`drawnText`）と同じく頭に付ける**——打っている間だけ
            // 印が無いと、帯の幅と見た目が完了した後と違った（4ffb74f のレビュー）
            if let symbol = overlay.kind.symbol {
                Text(symbol)
                    .font(StoryCanvas.font(overlay.face, size: fontSize))
                    .foregroundStyle(StoryCanvas.color(hex: overlay.drawnHex))
                    .accessibilityHidden(true)
                    // 欄が枠より広いとき、印に回る幅が 0 になって「…」に潰れないように（e634a70 のレビュー）
                    .fixedSize()
            }
            input(fontSize: fontSize)
        }
        .padding(.horizontal, overlay.style == .banner ? fontSize * 0.35 : 0)
        .padding(.vertical, overlay.style == .banner ? fontSize * 0.175 : 0)
        .background(overlay.style == .banner ? Color.black.opacity(0.65) : Color.clear)
        .shadow(radius: overlay.style == .light ? 6 : 0)
        // 暗い文字は、暗くした写真の上で見えない。**打っている間だけ**明るい下敷きを敷く
        // （`StoryTextEditing.typingNeedsLightPlate`。置いたあとの見た目は変えない）
        .background {
            if StoryTextEditing.typingNeedsLightPlate(overlay) {
                RoundedRectangle(cornerRadius: CGFloat(max(8, fontSize * 0.3)))
                    .fill(Color.white.opacity(0.8))
                    .padding(-CGFloat(max(6, fontSize * 0.25)))
                    .accessibilityHidden(true)
            }
        }
        // **欄（と下敷き）を押したらキーボードを出し直す。** ピントを入れるのは開いたときの1回だけで、
        // 色選びなどでキーボードが閉じると戻る口が無かった（欄の外を押すと確定して閉じる）。
        // 欄そのものの押し方（キャレットの位置決め）を邪魔しないよう、同時に効かせる
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { if overlay.kind.isEditable { focused = true } })
    }

    /// 打つ欄。**時刻・日付は直せない**（端末から採った値）ので、同じ見た目の文字を出し、
    /// 書体・色・大きさだけを直す（キーボードは出ない）
    @ViewBuilder
    private func input(fontSize: Double) -> some View {
        if overlay.kind.isEditable {
            editableInput(fontSize: fontSize)
        } else {
            Self.edged(Text(overlay.text)
                .font(StoryCanvas.font(overlay.face, size: fontSize))
                .foregroundStyle(StoryCanvas.color(hex: overlay.drawnHex)),
                       style: overlay.style, fontSize: fontSize)
                .fixedSize()
                .accessibilityLabel(overlay.displayText)
        }
    }

    private func editableInput(fontSize: Double) -> some View {
        let input = TextField(L("文字を入力", "Type something"), text: Binding(
            get: { overlay.text },
            set: { overlay.text = TextOverlay.cleaned($0, kind: overlay.kind) }
        ), axis: overlay.kind.allowsNewlines ? .vertical : .horizontal)
        .focused($focused)
        // 書体・色・揃えは焼き込みと同じもの（`StoryCanvas.font` / `color` / `alignment`）
        .font(StoryCanvas.font(overlay.face, size: fontSize))
        .foregroundStyle(StoryCanvas.color(hex: overlay.drawnHex))
        .multilineTextAlignment(StoryCanvas.alignment(overlay.align))
        // キャレットの色。明るい下敷きの上では白が見えないので黒
        .tint(StoryTextEditing.typingNeedsLightPlate(overlay) ? .black : .white)
        // 縁（黒の見た目＝白い縁・縁取り＝黒い縁）。打つ欄には縁の写しを敷けないので、
        // ぼかし無しの影を4方向に重ねて近い見た目にする（置いたあとは `StoryCanvas.edged` の本物）
        // 1行の欄（撮影地・タグ・曲）は Return で確定して閉じる（キーボードだけ閉じて画面が残った）。
        // 改行できる欄では Return は改行なので、ここは呼ばれない
        .onSubmit { onDone() }
        // **幅は測って渡す＝改行した所だけで行が分かれる**（置いたあとと同じ）。高さは渡した幅での
        // 欄の高さ。`fixedSize()` で欄に任せると、縦に伸びる欄は実機で幅 0 になり何も描かれなかった
        // （`StoryTextEditing.typingFieldWidth`）
        let measured = TextOverlayRenderer.naturalSize(
            overlay, text: StoryTextEditing.typingFieldText(overlay, placeholder: L("文字を入力", "Type something")),
            fontSize: fontSize).width
        return Self.edged(input, style: overlay.style, fontSize: fontSize)
            .frame(width: StoryTextEditing.typingFieldWidth(measured: Double(measured), fontSize: fontSize)
                .map { CGFloat($0) })
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(L("文字", "Text"))
    }

    /// 打つ欄の縁（ぼかし無しの影を4方向に重ねる）。縁の色と幅は置いたあとと同じ
    /// （`TextOverlay.Style.edgeOffset`・黒の見た目は白・縁取りは黒）
    static func edged<V: View>(_ content: V, style: TextOverlay.Style, fontSize: Double) -> some View {
        let width = style.edgeOffset(fontSize: fontSize) ?? 0
        let color: Color = width > 0 ? (style == .dark ? .white : .black) : .clear
        return content
            .shadow(color: color, radius: 0, x: width, y: 0)
            .shadow(color: color, radius: 0, x: -width, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: width)
            .shadow(color: color, radius: 0, x: 0, y: -width)
    }

    // MARK: - キーボードの上の1列（書体・背景・色・消す）

    private var paletteRow: some View {
        HStack(spacing: 4) {
            faceButton
            // 背景は自由な文字だけ（札は帯で固定・前の「見た目」ボタンと同じ条件）
            if overlay.kind.forcedStyle == nil {
                backdropButton
            }
            if showAllInks {
                // 12色と好きな色（前の色の列そのまま）。左の「‹」で4つの丸へ戻る
                Button { showAllInks = false } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("色の丸4つに戻る", "Back to four colors"))
                OverlayInkRow(overlay: $overlay)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(StorySimpleRules.inks(for: overlay)) { ink in
                            inkDot(ink)
                        }
                        moreInksButton
                    }
                }
            }
            deleteButton
        }
        .padding(.horizontal, 8)
    }

    /// 「Aa 明朝」。押すたびに 明朝 → ゴシック → 手書き風 → …（`StorySimpleRules.nextFace`）
    private var faceButton: some View {
        Button {
            overlay = StorySimpleRules.nextFace(overlay)
        } label: {
            HStack(spacing: 4) {
                Text("Aa")
                    .font(StoryCanvas.font(overlay.face, size: 16))
                Text(overlay.face.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("書体: \(overlay.face.label)", "Font: \(overlay.face.label)"))
        .accessibilityHint(L("押すと次の書体に替わります", "Tap for the next font"))
    }

    /// 背景（無し → 帯 → 縁取り）。いまの段を「A」の見本で見せる
    private var backdropButton: some View {
        let backdrop = StorySimpleRules.backdrop(of: overlay.style)
        return Button {
            overlay = StorySimpleRules.nextBackdrop(overlay)
        } label: {
            Text("A")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(backdrop == .banner ? Color.black.opacity(0.65) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(backdrop == .none ? 0.7 : 1),
                                  style: StrokeStyle(lineWidth: backdrop == .outline ? 2.5 : 1.5,
                                                     dash: backdrop == .none ? [3, 2] : [])))
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("背景: \(backdrop.label)", "Background: \(backdrop.label)"))
        .accessibilityHint(L("押すと次の背景に替わります", "Tap for the next background"))
    }

    private func inkDot(_ ink: TextOverlay.Ink) -> some View {
        let selected = StorySimpleRules.isSelected(ink, in: overlay)
        return Button {
            overlay = StorySimpleRules.choose(ink, for: overlay)
        } label: {
            Circle()
                .fill(StoryCanvas.color(ink))
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 1 : 0.5),
                                               lineWidth: selected ? 3 : 2))
                .overlay(Circle().strokeBorder(Color.black, lineWidth: selected ? 1 : 0).padding(-2))
                // 見た目の丸は 26 のまま、押せる所は 44×44（入らなければ横に流す）
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("文字の色 \(ink.label)", "Text color \(ink.label)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 「ほかの色」（12色と好きな色の列へ）。4つ以外を選んでいるときは輪で知らせる
    private var moreInksButton: some View {
        let other = !StorySimpleRules.inks(for: overlay).contains { StorySimpleRules.isSelected($0, in: overlay) }
        return Button { showAllInks = true } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.white.opacity(other ? 1 : 0.5), lineWidth: other ? 3 : 1.5))
                // 見た目の丸は 26 のまま、押せる所は 44×44（入らなければ横に流す）
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("ほかの色", "More colors"))
    }

    /// 消す（ゴミ箱・危険の赤 `WebTheme.danger`）
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WebTheme.danger)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("この文字を消す", "Delete this text"))
    }

    // MARK: - 大きさ（左の縦のつまみ）

    private var sizeSlider: some View {
        // 横のつまみを回して縦に使う（長さを決めてから回し、回したあとの枠で並べる）
        Slider(value: Binding(
            get: { overlay.size },
            set: { overlay.size = TextOverlay.clampSize($0) }
        ), in: TextOverlay.minSize...TextOverlay.maxSize)
        .tint(.white)
        .frame(width: 220)
        .rotationEffect(.degrees(-90))
        .frame(width: WebTheme.minTapTarget, height: 220)
        .accessibilityLabel(L("文字の大きさ", "Text size"))
    }
}
