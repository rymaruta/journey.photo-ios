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
/// **置いた場所は指で決める。** 押すと選び（破線で囲む）、つまんで動かす。
/// 動かした先は見えている範囲の中へ寄せる（はみ出した端では掴み直せない）
struct StoryCanvas: View {

    let preview: Image
    /// 写真の本当の大きさ（画素）。分からないとき（nil）は枠いっぱいを写真とみなす
    let imageSize: CGSize?
    @Binding var overlays: [TextOverlay]
    /// 選んでいる札（破線で囲む）。nil なら選んでいない
    var selectedId: UUID?
    /// 札を押した
    var onTap: (TextOverlay) -> Void = { _ in }

    /// つまんでいる最中の見た目の移動量（離したときに位置へ反映する）
    @State private var dragId: UUID?
    @State private var dragOffset: CGSize = .zero
    /// **キーボードで縮む前の枠の大きさ。** 見えている範囲はこれで決める——
    /// 縮んだ枠で決めると、キーボードを閉じたあとに画面の外へ出る札を作れた
    @State private var stableSize: CGSize = .zero
    /// 2本指で回している最中の札と、その角度（離したときに回しへ足す）
    @State private var rotateId: UUID?
    @State private var liveRotation: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let photo = TextOverlay.filledRect(image: imageSize ?? geometry.size, in: geometry.size)
            ZStack(alignment: .topLeading) {
                // `.fill` の絵は枠より大きい寸法を申告するので、透明な枠に重ねる
                Color.clear
                    .overlay { preview.resizable().aspectRatio(contentMode: .fill) }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
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
                    .onChanged { angle in
                        guard let id = selectedId else { return }
                        rotateId = id
                        liveRotation = angle.radians
                    }
                    .onEnded { angle in
                        if let id = rotateId, let i = overlays.firstIndex(where: { $0.id == id }) {
                            overlays[i].rotation += angle.radians
                        }
                        rotateId = nil
                        liveRotation = 0
                    }
            )
            .onAppear { remember(geometry.size) }
            .onChange(of: geometry.size) { _, size in remember(size) }
        }
    }

    /// 書体（同梱の明朝・手書き風。ゴシックは端末の太字）。**大きさは固定**——
    /// 焼き込みは画像の画素で描くので、文字の大きさの設定に追従させると割れる
    static func font(_ face: TextOverlay.Face, size: Double) -> Font {
        // **読めなかったときは焼き込みと同じ端末の太字に落とす。** `Font.custom` は
        // 黙って標準の太さに落ちるので、画面だけ細くなる
        if let name = face.fontName, UIFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .bold)
    }

    static func color(_ ink: TextOverlay.Ink) -> Color {
        let hex = ink.hex
        return Color(red: Double((hex >> 16) & 0xFF) / 255,
                     green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255)
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
        let fontSize = TextOverlay.fontSize(overlay.size, in: photo.size)
        let center = overlay.center(in: photo)
        let rotation = overlay.rotation + (rotateId == overlay.id ? liveRotation : 0)
        return Text(overlay.displayText)
            // 書体と色は焼き込みと同じもの（`TextOverlayRenderer.attributes`）
            .font(Self.font(overlay.face, size: fontSize))
            .foregroundStyle(Self.color(overlay.drawnInk))
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
                    .onChanged { value in
                        dragId = overlay.id
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        // **離したときに位置へ入れる。** 動かしている最中に
                        // 入れると、はみ出しの丸めが毎フレーム効いて指から離れる
                        move(overlay, by: value.translation, photo: photo, canvas: canvas)
                        dragId = nil
                        dragOffset = .zero
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // **端末から採った札は直させない**（時刻・日付）。直せると「いつの話か」が嘘になる
            if overlay.kind.isEditable {
                TextField(L("文字", "Text"), text: Binding(
                    get: { overlay.text },
                    set: { overlay.text = String($0.prefix(TextOverlay.maxLength)) }
                ))
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                // 時刻・日付は端末から採った値（直せない）。何の札かだけ見せる
                Text(overlay.displayText)
                    .font(.system(size: 15))
                    .foregroundStyle(WebTheme.muted)
                    .frame(minHeight: 44)
            }

            // 書体（明朝・ゴシック・手書き風）
            HStack(spacing: 8) {
                Text(L("書体", "Font"))
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
                    .frame(width: 36, alignment: .leading)
                ForEach(TextOverlay.Face.allCases) { face in
                    OverlayChip(title: face.label, selected: overlay.face == face) {
                        overlay.face = face
                    }
                }
            }

            // 色（白・墨・真鍮・空色・珊瑚）
            HStack(spacing: 10) {
                Text(L("色", "Color"))
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
                    .frame(width: 36, alignment: .leading)
                // 見た目に対して読めない色は出さない（`TextOverlay.inks(for:)`）
                ForEach(TextOverlay.inks(for: overlay.style)) { ink in
                    let selected = overlay.drawnInk == ink
                    Button {
                        overlay.ink = ink
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
                }
            }

            HStack(spacing: 8) {
                // **場所と曲は帯で固定**（読めない札を作らせない）ので見た目の選択を出さない
                if overlay.kind == .text {
                    ForEach(TextOverlay.Style.allCases) { style in
                        OverlayChip(title: style.label, selected: overlay.style == style) {
                            // 色の寄せ方は `TextOverlay.withStyle`（読めない組だけ直す）
                            overlay = overlay.withStyle(style)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(action: onDelete) {
                    Label(L("消す", "Delete"), systemImage: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 1.0, green: 0x8A / 255.0, blue: 0x80 / 255.0))
                        .frame(minHeight: 36)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }

            // 大きさ。**幅は `TextOverlay` が決める**（読めない／覆う を防ぐ）
            HStack(spacing: 10) {
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
