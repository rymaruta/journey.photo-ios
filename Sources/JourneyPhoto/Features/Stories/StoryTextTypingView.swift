import SwiftUI

/// **写真の上で直接打つ画面**（Instagram と同じ形・`StoryTextEditing`）。
///
/// owner・2026-09-30「文字などの入力の UI や機能にまだ納得いってない・使いづらい」
/// （打つまでの手数・写真の上で打てない・下の欄がごちゃごちゃ・動かす消す直すが面倒、の4つ全部）。
///
///  - 開いたらすぐキーボード。文字は**真ん中に、仕上がりと同じ書体・色・見た目・大きさ**で出る
///    （大きさは焼き込みと同じ式・`StoryTextEditing.typingFontSize`）
///  - 書体と色は**キーボードのすぐ上に1列だけ**（左の丸で書体 ⇄ 色を切り替える）
///  - 大きさは左の縦のつまみ。揃えと見た目（白・黒・帯・縁取り）は上のボタンを押すたびに次へ
///  - 「完了」か、文字の外を押すと確定。**空なら置かない**（呼ぶ側が `StoryTextEditing.finish` を通す）
///
/// 写真の上に置くのは白だけ（デザインシステム「黒塗りの真鍮」: 写真の上に真鍮を置かない）。
/// 押せる所は 44pt。
struct StoryTextTypingView: View {

    @Binding var overlay: TextOverlay
    /// 画面上の写真の短い辺（pt）。**焼き込みと同じ大きさで見せる**ため。分からなければ 0
    let photoShortSide: Double
    var onDone: () -> Void

    @FocusState private var focused: Bool
    /// キーボードの上の列に出すもの（書体か色）
    @State private var palette: Palette = .faces

    enum Palette { case faces, inks }

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
                    Spacer(minLength: 12)
                    field(fontSize: fontSize)
                        // 左の縦のつまみと重ねない
                        .padding(.horizontal, 56)
                    Spacer(minLength: 12)
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
        .onAppear { focused = true }
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
            // 見た目（自由な文字だけ。札は帯で固定）。押すたびに 白 → 黒 → 帯 → 縁取り
            if overlay.kind.forcedStyle == nil {
                Button {
                    overlay = StoryTextEditing.nextStyle(overlay)
                } label: {
                    Text(overlay.style.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("見た目: \(overlay.style.label)", "Style: \(overlay.style.label)"))
                .accessibilityHint(L("押すと次の見た目に替わります", "Tap for the next style"))
            }
            Spacer()
            Button(action: onDone) {
                Text(L("完了", "Done"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .padding(.horizontal, 10)
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
        let input = TextField(L("文字を入力", "Type something"), text: Binding(
            get: { overlay.text },
            set: { overlay.text = TextOverlay.cleaned($0, kind: overlay.kind) }
        ), axis: overlay.kind.allowsNewlines ? .vertical : .horizontal)
        .focused($focused)
        // 書体・色・揃えは焼き込みと同じもの（`StoryCanvas.font` / `color` / `alignment`）
        .font(StoryCanvas.font(overlay.face, size: fontSize))
        .foregroundStyle(StoryCanvas.color(hex: overlay.drawnHex))
        .multilineTextAlignment(StoryCanvas.alignment(overlay.align))
        .tint(.white)
        // 縁（黒の見た目＝白い縁・縁取り＝黒い縁）。打つ欄には縁の写しを敷けないので、
        // ぼかし無しの影を4方向に重ねて近い見た目にする（置いたあとは `StoryCanvas.edged` の本物）
        return Self.edged(input, style: overlay.style, fontSize: fontSize)
            .padding(.horizontal, overlay.style == .banner ? fontSize * 0.35 : 0)
            .padding(.vertical, overlay.style == .banner ? fontSize * 0.175 : 0)
            .background(overlay.style == .banner ? Color.black.opacity(0.65) : Color.clear)
            .shadow(radius: overlay.style == .light ? 6 : 0)
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

    // MARK: - キーボードの上の列（書体 ⇄ 色）

    private var paletteRow: some View {
        HStack(spacing: 6) {
            // 書体と色を切り替える丸。**いま出していない方の印**を出す（押すとそちらへ）
            Button {
                palette = palette == .faces ? .inks : .faces
            } label: {
                Group {
                    if palette == .faces {
                        Circle()
                            .fill(StoryCanvas.color(hex: overlay.drawnHex))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    } else {
                        Text("Aa")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    }
                }
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(palette == .faces ? L("色を選ぶ", "Choose color") : L("書体を選ぶ", "Choose font"))

            switch palette {
            case .faces: OverlayFaceRow(overlay: $overlay)
            case .inks: OverlayInkRow(overlay: $overlay)
            }
        }
        .padding(.leading, 8)
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
