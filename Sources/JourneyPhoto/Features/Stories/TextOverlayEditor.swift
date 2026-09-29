import SwiftUI
import UIKit

/// 写真と、その上の文字（作る画面の全面・板 24 / 24b）。
///
/// owner の要望:「ユーザは画面のいろんなとこにテキストを配置したい」。
///
/// **写真は画面いっぱいに埋めて敷く**（`TextOverlay.filledRect`）。文字の位置と
/// 大きさは**画像に対する割合**のままなので、焼き込み（`TextOverlayRenderer`）と
/// 同じところに出る。閲覧画面も埋めて出すので、見えている範囲もほぼ同じになる。
///
/// **置いた場所は指で決める。** 押すと選び（破線で囲む）、指で動かす。
/// 動かした先は見えている範囲の中へ寄せる（はみ出した端では掴み直せない）
struct StoryCanvas: View {

    let preview: Image
    /// 写真の本当の大きさ（画素）。分からないとき（nil）は枠いっぱいを写真とみなす
    let imageSize: CGSize?
    @Binding var overlays: [TextOverlay]
    /// 写真の合わせ方（拡大・位置・回し）。**札を選んでいないとき**、2本指の操作と
    /// 写真の上で動かす操作は写真に効く（札を選んでいれば札に効く）
    @Binding var framing: PhotoFraming
    /// 選んでいる札（破線で囲む）。nil なら選んでいない
    var selectedId: UUID?
    /// 札を押した
    var onTap: (TextOverlay) -> Void = { _ in }

    /// 指で動かしている最中の見た目の移動量（離したときに位置へ反映する）
    @State private var dragId: UUID?
    @State private var dragOffset: CGSize = .zero
    /// **キーボードで縮む前の枠の大きさ。** 見えている範囲はこれで決める——
    /// 縮んだ枠で決めると、キーボードを閉じたあとに画面の外へ出る札を作れた
    @State private var stableSize: CGSize = .zero
    /// 2本指で回している最中の札と、その角度（離したときに回しへ足す）
    @State private var rotateId: UUID?
    @State private var liveRotation: Double = 0
    /// 2本指でつまんでいる最中の札と、その倍率（離したときに大きさへ掛ける）
    @State private var scaleId: UUID?
    @State private var liveScale: Double = 1
    /// 指が触れている間だけ立つ印。**打ち切られても（着信・画面の切り替えで `onEnded` が
    /// 呼ばれない回も）SwiftUI が倒す**——倒れたら、途中の値を札へ入れて片付ける。
    /// 片付けないと、見た目だけ大きく（回って・ずれて）見えたまま、投稿される札は元のままだった
    /// （f17f17d のレビュー）
    @GestureState private var twisting = false
    @GestureState private var pinching = false
    @GestureState private var dragging = false
    /// 写真を動かしている最中の移動量（離したときに `framing` へ入れる）と、その印
    @State private var photoDrag: CGSize = .zero
    @GestureState private var photoDragging = false
    /// 2本指の操作がいま写真に効いているか（札に効いているときは false）。
    /// **始めたときに決めて、終わるまで変えない**（途中で札を選んでも移さない）
    @State private var twistsPhoto = false
    @State private var pinchesPhoto = false
    /// 1本指で動かしている間に2本指の操作が入ったか。**入った回の移動は入れない**
    /// ——札の上でつまむと、動かす操作も片方の指を追って動き、離すとずれた所で決まった
    @State private var dragSpoiled = false

    var body: some View {
        GeometryReader { geometry in
            let photo = TextOverlay.filledRect(image: imageSize ?? geometry.size, in: geometry.size)
            ZStack(alignment: .topLeading) {
                // 写真は**写真の枠（`photo`）の大きさで描き、合わせ方を重ねる**
                // （焼き込みの `PhotoFraming.placement` と同じ順: 倍率 → 回し → ずらし）。
                // 届かない所は後ろの黒
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                let shown = liveFraming(in: photo.size)
                preview.resizable()
                    .frame(width: photo.width, height: photo.height)
                    .scaleEffect(CGFloat(shown.scale))
                    .rotationEffect(.radians(shown.rotation))
                    .offset(x: CGFloat(shown.offsetX * Double(photo.width)),
                            y: CGFloat(shown.offsetY * Double(photo.height)))
                    .position(x: photo.midX, y: photo.midY)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    // 写真の上で動かす（札の上では札が先に取る）。2回押すと合わせ方を戻す
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .updating($photoDragging) { _, state, _ in state = true }
                            .onChanged { value in
                                // 2本指の操作が入ったら写真は動かさない（つまむ指で流れる）
                                photoDrag = (rotateId != nil || scaleId != nil || twistsPhoto || pinchesPhoto)
                                    ? .zero : value.translation
                            }
                            .onEnded { _ in commitPhotoDrag(photo: photo) }
                    )
                    .onTapGesture(count: 2) { framing = .identity }
                    .accessibilityElement()
                    .accessibilityLabel(L("写真", "Photo"))
                    .accessibilityHint(L("2本指で拡大・回転、指で動かします。2回押すと元に戻します",
                                         "Pinch or twist to zoom and rotate, drag to move. Double-tap to reset"))
                ForEach(overlays) { overlay in
                    text(overlay, photo: photo, canvas: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            // 2本指で**選んでいる札を**回す（板 24b「指で動かす・2本指で回す」）。
            // 札そのものに付けると、2本とも小さな札の中に置かないと効かない
            .simultaneousGesture(
                RotationGesture()
                    .updating($twisting) { _, state, _ in state = true }
                    .onChanged { angle in
                        // **回し始めた札（札を選んでいなければ写真）に固定する**
                        // （途中で選ぶ札が替わっても移さない）
                        if rotateId == nil && !twistsPhoto {
                            if let id = selectedId { rotateId = id } else { twistsPhoto = true }
                        }
                        liveRotation = angle.radians
                    }
                    .onEnded { angle in
                        // 打ち切りの片付けが先に済んでいたら何もしない
                        guard rotateId != nil || twistsPhoto else { return }
                        liveRotation = angle.radians
                        commitRotation()
                    }
            )
            // つまんで**選んでいる札の**大きさを変える（回すのと同じ理由で枠全体に付ける）。
            // 幅はスライダーと同じ（`TextOverlay.scaled`）
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinching) { _, state, _ in state = true }
                    .onChanged { value in
                        if scaleId == nil && !pinchesPhoto {
                            if let id = selectedId { scaleId = id } else { pinchesPhoto = true }
                        }
                        liveScale = Double(value)
                    }
                    .onEnded { value in
                        guard scaleId != nil || pinchesPhoto else { return }
                        liveScale = Double(value)
                        commitScale()
                    }
            )
            // 打ち切られた回の片付け（`onEnded` と、どちらが先に来ても1回だけ入る）
            .onChange(of: twisting) { _, active in if !active { commitRotation() } }
            .onChange(of: pinching) { _, active in if !active { commitScale() } }
            .onChange(of: photoDragging) { _, active in
                // 写真を動かす操作の打ち切り。**移動は入れない**
                if !active { photoDrag = .zero }
            }
            .onChange(of: dragging) { _, active in
                // 動かす操作の打ち切り。**移動は入れない**（離した位置が分からない）。
                // `dragSpoiled` はここで戻さない——`onEnded` より先に来ると、2本指が入った回の
                // 移動を入れてしまう。次に動かし始めたときに戻す
                if !active { dragId = nil; dragOffset = .zero }
            }
            .onAppear { remember(geometry.size) }
            .onChange(of: geometry.size) { _, size in remember(size) }
        }
    }

    /// 回した角度を札へ入れて片付ける。**2回目は何もしない**（`onEnded` と打ち切りの片付けの両方から来る）
    private func commitRotation() {
        if let id = rotateId, let i = overlays.firstIndex(where: { $0.id == id }) {
            overlays[i].rotation += liveRotation
        } else if twistsPhoto {
            framing = framing.rotated(by: liveRotation)
        }
        rotateId = nil
        twistsPhoto = false
        liveRotation = 0
    }

    /// つまんだ倍率を札へ入れて片付ける（同じく2回目は何もしない）
    private func commitScale() {
        if let id = scaleId, let i = overlays.firstIndex(where: { $0.id == id }) {
            overlays[i] = overlays[i].scaled(by: liveScale)
        } else if pinchesPhoto {
            framing = framing.scaled(by: liveScale)
        }
        scaleId = nil
        pinchesPhoto = false
        liveScale = 1
    }

    /// 写真を動かした量を入れる（枠＝写真の場所に対する割合）
    private func commitPhotoDrag(photo: CGRect) {
        framing = framing.moved(by: photoDrag, in: photo.size)
        photoDrag = .zero
    }

    /// 指で操作している最中の合わせ方（**離したときと同じ幅で見せる**——幅の外で動いて見えて、
    /// 離すと戻る、にしない）
    private func liveFraming(in photo: CGSize) -> PhotoFraming {
        var live = framing
        if pinchesPhoto { live = live.scaled(by: liveScale) }
        if twistsPhoto { live = live.rotated(by: liveRotation) }
        return live.moved(by: photoDrag, in: photo)
    }

    /// 書体（`TextOverlay.Face`。同梱の字か端末の字。ゴシックは端末の太字）。**大きさは固定**——
    /// 焼き込みは画像の画素で描くので、文字の大きさの設定に追従させると割れる
    static func font(_ face: TextOverlay.Face, size: Double) -> Font {
        // **読めなかったときは焼き込みと同じ端末の太字に落とす。** `Font.custom` は
        // 黙って標準の太さに落ちるので、画面だけ細くなる
        if let name = face.fontName, UIFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .bold)
    }

    /// 文字に縁を付ける（焼き込みの `strokeWidth` に合わせる）。SwiftUI の文字には縁が無いので、
    /// **縁の色の文字を8方向にずらして下に敷く**。黒の見た目（白い縁・幅3%）と
    /// 縁取り（黒い縁・幅6%）。**以前は黒の見た目の縁が画面に出ず、焼き込みにだけ付いていた**
    static func edged<Label: View>(_ text: Label, overlay: TextOverlay, fontSize: Double) -> some View {
        let edge: (color: Color, width: Double)? = overlay.style.edgeOffset(fontSize: fontSize).map {
            (overlay.style == .dark ? .white : .black, $0)
        }
        return ZStack {
            if let edge {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) * .pi / 4
                    text.foregroundStyle(edge.color)
                        .offset(x: CGFloat(cos(angle) * edge.width), y: CGFloat(sin(angle) * edge.width))
                        // 縁のための写しは読み上げない（同じ文字を9回読まれる）
                        .accessibilityHidden(true)
                }
            }
            text.foregroundStyle(color(hex: overlay.drawnHex))
        }
    }

    static func alignment(_ align: TextOverlay.Align) -> TextAlignment {
        switch align {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    static func color(_ ink: TextOverlay.Ink) -> Color {
        color(hex: ink.hex)
    }

    static func color(hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// 端末の色選びが返した色を 0xRRGGBB に。**`UIKit.` と書くのは Linux の模型のため**
    /// （模型では SwiftUI と UIKit が別々に `UIColor` を持つ。本物では同じもの）
    static func hex(of color: Color) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        _ = UIKit.UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return TextOverlay.hex(red: Double(red), green: Double(green), blue: Double(blue))
    }

    /// 幅が変わったら測り直し、同じ幅なら高い方を覚える
    private func remember(_ size: CGSize) {
        if size.width != stableSize.width || size.height > stableSize.height {
            stableSize = size
        }
    }

    private func text(_ overlay: TextOverlay, photo: CGRect, canvas: CGSize) -> some View {
        let moving = dragId == overlay.id
        // 大きさと位置は焼き込みと同じ関数（写真の短い辺に対する割合・
        // 写真に対する位置）。**下限で持ち上げない**——持ち上げると、
        // スライダーを下げても見た目が変わらないのに投稿される文字だけ
        // 小さくなる（2026-09-26 のレビュー）
        // つまんでいる最中も、離したときと同じ幅で見せる（幅の外で大きく見えて、離すと縮む、にしない）
        let size = scaleId == overlay.id ? overlay.scaled(by: liveScale).size : overlay.size
        let fontSize = TextOverlay.fontSize(size, in: photo.size)
        let center = overlay.center(in: photo)
        let rotation = overlay.rotation + (rotateId == overlay.id ? liveRotation : 0)
        return Self.edged(Text(overlay.drawnText)
            // 書体と色は焼き込みと同じもの（`TextOverlayRenderer.attributes`）
            .font(Self.font(overlay.face, size: fontSize))
            // 改行した文字の揃え（焼き込みの `TextOverlay.lineLayout` と同じ置き方）
            .multilineTextAlignment(Self.alignment(overlay.align))
            // **折り返さない**（焼き込みも折り返さない。画面の幅で折り返すと行数と揃えがずれた）
            .fixedSize(), overlay: overlay, fontSize: fontSize)
            // 帯の余白も焼き込み（`TextOverlayRenderer.draw`）と同じ割合
            .padding(.horizontal, overlay.style == .banner ? CGFloat(fontSize * 0.35) : 0)
            .padding(.vertical, overlay.style == .banner ? CGFloat(fontSize * 0.175) : 0)
            .background(overlay.style == .banner ? Color.black.opacity(0.65) : Color.clear)
            .shadow(radius: overlay.style == .light ? 6 : 0)
            // 選んでいる札は破線で囲む（板 24b）
            .overlay {
                if selectedId == overlay.id {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .padding(-8)
                }
            }
            // 小さい文字でも指で掴めるように、**押せる範囲だけ**広げる
            // （帯の見た目は広げない＝`background` より後ろに置く）
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            // 回しは中心の周り（焼き込みも中心の周り）。**破線と押せる範囲より後ろ**に
            // 置いて一緒に回す——前に置くと、縦に回した文字の端を押しても掴めない
            .rotationEffect(.radians(rotation))
            .position(x: center.x + (moving ? dragOffset.width : 0),
                      y: center.y + (moving ? dragOffset.height : 0))
            .gesture(
                DragGesture()
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        // 動かし始め（前の回の印を戻す）
                        if dragId == nil { dragSpoiled = false }
                        // 2本指の操作（回す・つまむ）が入ったら、この回は動かさない
                        if rotateId != nil || scaleId != nil { dragSpoiled = true }
                        dragId = overlay.id
                        dragOffset = dragSpoiled ? .zero : value.translation
                    }
                    .onEnded { value in
                        // **離したときに位置へ入れる。** 動かしている最中に
                        // 入れると、はみ出しの丸めが毎フレーム効いて指から離れる
                        if !dragSpoiled && rotateId == nil && scaleId == nil {
                            move(overlay, by: value.translation, photo: photo, canvas: canvas)
                        }
                        dragId = nil
                        dragOffset = .zero
                        dragSpoiled = false
                    }
            )
            // 押すと選ぶ（直す・消すのも同じ入口）。
            // **時刻と日付も押せる**——直せないが、消す口はここにしか無い
            .onTapGesture { onTap(overlay) }
            .accessibilityLabel(overlay.text)
    }

    private func move(_ overlay: TextOverlay, by translation: CGSize, photo: CGRect, canvas: CGSize) {
        guard let index = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        // 見えている範囲は縮む前の枠で決める
        let full = stableSize == .zero ? canvas : stableSize
        let fullPhoto = TextOverlay.filledRect(image: imageSize ?? full, in: full)
        overlays[index] = overlays[index]
            .moved(by: translation, in: photo.size)
            .clamped(toVisible: fullPhoto, canvas: full)
    }
}

/// 文字と札の操作欄（板 24b の下の面）。選んでいる札の文字・見た目・大きさ・消す
struct OverlayPanel: View {

    @Binding var overlay: TextOverlay
    var onDelete: () -> Void
    /// 文字の欄を打っているか。**改行できる欄は Return で閉じない**ので、閉じる口を出す
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // **端末から採った札は直させない**（時刻・日付）。直せると「いつの話か」が嘘になる
            if overlay.kind.isEditable {
                // **自由な文字は改行できる**（6行まで・`TextOverlay.accepting`）。札は1行
                HStack(spacing: 8) {
                    TextField(L("文字", "Text"), text: Binding(
                        get: { overlay.text },
                        set: { overlay.text = TextOverlay.accepting($0, old: overlay.text, kind: overlay.kind) }
                    ), axis: overlay.kind.allowsNewlines ? .vertical : .horizontal)
                    .focused($fieldFocused)
                    .lineLimit(1...3)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    // 改行できる欄は Return が改行になる。**キーボードを閉じる口**（f48800f のレビュー）
                    if fieldFocused {
                        Button { fieldFocused = false } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("キーボードを閉じる", "Hide keyboard"))
                    }
                }
            } else {
                // 時刻・日付は端末から採った値（直せない）。何の札かだけ見せる
                Text(overlay.displayText)
                    .font(.system(size: 15))
                    .foregroundStyle(WebTheme.muted)
                    .frame(minHeight: 44)
            }

            // 書体（8種）。**横に流す**——1行に収まらない。スタンプには出さない（絵文字に効かない）
            if overlay.kind.hasTypography {
            HStack(spacing: 8) {
                Text(L("書体", "Font"))
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
                    .frame(width: 36, alignment: .leading)
                // **選んでいる書体まで流して見せる**（後ろの方の書体を選んだ札を開き直すと、
                // 列の頭が出て何を選んでいるか見えなかった・bfe5e12 のレビュー）
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TextOverlay.Face.allCases) { face in
                                OverlayChip(title: face.label, selected: overlay.face == face) {
                                    overlay.face = face
                                }
                                .id(face)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(overlay.face, anchor: .center) }
                    .onChange(of: overlay.id) { _, _ in proxy.scrollTo(overlay.face, anchor: .center) }
                }
            }
            }

            // 色（12色・`TextOverlay.Ink`）。スタンプには出さない
            if overlay.kind.hasTypography {
            HStack(spacing: 10) {
                Text(L("色", "Color"))
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
                    .frame(width: 36, alignment: .leading)
                // 見た目に対して読めない色は出さない（`TextOverlay.inks(for:)`）。
                // 12色あるので横に流し、**選んでいる色まで流して見せる**（書体と同じ理由）
                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                ForEach(TextOverlay.inks(for: overlay.style)) { ink in
                    let selected = overlay.customHex == nil && overlay.drawnInk == ink
                    Button {
                        overlay.ink = ink
                        overlay.customHex = nil
                    } label: {
                        Circle()
                            .fill(StoryCanvas.color(ink))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 1 : 0.5),
                                                           lineWidth: selected ? 3 : 2))
                            .overlay(Circle().strokeBorder(Color.black, lineWidth: selected ? 1 : 0).padding(-2))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("文字の色 \(ink.label)", "Text color \(ink.label)"))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .id(ink)
                }
                customColor
                }
                }
                .onAppear { proxy.scrollTo(colorAnchor, anchor: .center) }
                .onChange(of: overlay.id) { _, _ in proxy.scrollTo(colorAnchor, anchor: .center) }
                }
            }
            }

            HStack(spacing: 8) {
                // **場所と曲は帯で固定**（読めない札を作らせない）ので見た目の選択を出さない。
                // 4つ並ぶと英語では「消す」と合わせて幅に収まらないので横に流す
                if overlay.kind == .text {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TextOverlay.Style.allCases) { style in
                                OverlayChip(title: style.label, selected: overlay.style == style) {
                                    // 色の寄せ方は `TextOverlay.withStyle`（読めない組だけ直す）
                                    overlay = overlay.withStyle(style)
                                }
                            }
                        }
                    }
                } else {
                    // 見た目の列が無いときだけ「消す」を右へ寄せる。列と並べると
                    // 残りの幅を等分し、列が半分に押し込まれる
                    Spacer(minLength: 0)
                }
                Button(action: onDelete) {
                    Label(L("消す", "Delete"), systemImage: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.danger)
                        .frame(minHeight: 36)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }

            // 大きさ。**幅は `TextOverlay` が決める**（読めない／覆う を防ぐ）。
            // 自由な文字は頭に揃え（左・中央・右）を置く（改行した行の寄せ方）
            HStack(spacing: 10) {
                if overlay.kind.allowsNewlines {
                    HStack(spacing: 0) {
                        ForEach(TextOverlay.Align.allCases) { align in
                            Button {
                                overlay.align = align
                            } label: {
                                // 選んでいるものは真鍮に**薄い地**も敷く（色だけで見分けさせない）
                                Image(systemName: align.symbol)
                                    .font(.system(size: 15, weight: overlay.align == align ? .semibold : .regular))
                                    .foregroundStyle(overlay.align == align ? WebTheme.accent : Color.white.opacity(0.72))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(overlay.align == align ? 0.12 : 0), in: Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(align.label)
                            .accessibilityAddTraits(overlay.align == align ? .isSelected : [])
                        }
                    }
                }
                Text(L("小", "S"))
                Slider(value: Binding(
                    get: { overlay.size },
                    set: { overlay.size = TextOverlay.clampSize($0) }
                ), in: TextOverlay.minSize...TextOverlay.maxSize)
                .tint(.white)
                Text(L("大", "L"))
            }
            .font(.system(size: 11))
            .foregroundStyle(WebTheme.muted2)
        }
        .padding(12)
        .background(Color(red: 12 / 255.0, green: 12 / 255.0, blue: 13 / 255.0).opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
    }
}

/// 写真の上の丸いチップ（選ぶと白地に墨・板 24b）
struct OverlayChip: View {
    let title: String
    var systemImage: String? = nil
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12))
                }
                Text(title)
            }
            .font(.system(size: selected ? 13 : 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? WebTheme.accentText : Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(selected ? AnyShapeStyle(WebTheme.accentBackground) : AnyShapeStyle(Color.black.opacity(0.55)),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension OverlayPanel {
    /// 色の列で流して見せる先（好きな色を選んでいればその丸）
    var colorAnchor: AnyHashable {
        overlay.customHex == nil ? AnyHashable(overlay.drawnInk) : AnyHashable("custom")
    }

    /// 12色の後ろに置く「好きな色」（端末の色選び・owner の「色が少ない」2026-09-29）。
    /// 選んだ色は**見た目に対して読めるところまで寄せて描く**（`TextOverlay.readableHex`）。
    /// 丸に出すのも寄せたあとの色——選んだままの色を出すと、写真の上と食い違う
    var customColor: some View {
        ColorPicker("", selection: Binding(
            get: { StoryCanvas.color(hex: overlay.drawnHex) },
            // 丸に出している色（寄せたあと）がそのまま返ってきたときは書かない。
            // 書くと選んだ元の色が寄せた色で上書きされ、白の見た目に戻しても元の色に戻らない
            set: { color in
                let hex = StoryCanvas.hex(of: color)
                if hex != overlay.drawnHex { overlay.customHex = hex }
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(Color.white, lineWidth: overlay.customHex == nil ? 0 : 3)
            .frame(width: 36, height: 36)
            .allowsHitTesting(false))
        .accessibilityLabel(L("好きな色を選ぶ", "Pick any color"))
        .accessibilityAddTraits(overlay.customHex == nil ? [] : .isSelected)
        .id("custom")
    }
}
