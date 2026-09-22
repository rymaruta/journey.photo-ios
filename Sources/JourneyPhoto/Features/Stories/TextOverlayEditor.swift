import SwiftUI

/// 写真の上に文字を置く編集面。
///
/// owner の要望:「ユーザは画面のいろんなとこにテキストを配置したい」。
///
/// **置いた場所は指で決める。** 入力欄を並べて座標を打たせるのではなく、
/// 写真の上を直接つまんで動かす。位置は 0...1 の相対値で持つので
/// （`TextOverlay`）、編集中の大きさと実際の画像の大きさが違っても
/// 同じところに出る。
struct TextOverlayEditor<Extra: View>: View {

    let preview: Image
    @Binding var overlays: [TextOverlay]
    /// 同じ行に並べる、写真そのものの道具（カメラ・ライブラリ）。
    /// **モック4 は6つを1列に並べる**ので、写真の道具と文字の道具を
    /// 別の場所に置かない
    @ViewBuilder var extraTools: () -> Extra

    init(preview: Image, overlays: Binding<[TextOverlay]>,
         @ViewBuilder extraTools: @escaping () -> Extra = { EmptyView() }) {
        self.preview = preview
        self._overlays = overlays
        self.extraTools = extraTools
    }

    /// いま編集している文字。nil なら入力欄を出さない
    @State private var editingId: UUID?
    @State private var draft = ""
    /// つまんでいる最中の見た目の移動量（離したときに位置へ反映する）
    @State private var dragId: UUID?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack {
                    preview
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    ForEach(overlays) { overlay in
                        text(overlay, canvas: geometry.size)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .background(WebTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            controls
        }
    }

    // MARK: - 文字

    private func text(_ overlay: TextOverlay, canvas: CGSize) -> some View {
        let moving = dragId == overlay.id
        return Text(overlay.displayText)
            .font(.system(size: max(12, canvas.height * overlay.size), weight: .bold))
            .foregroundStyle(overlay.style == .dark ? Color.black : Color.white)
            .padding(.horizontal, overlay.style == .banner ? 8 : 0)
            .padding(.vertical, overlay.style == .banner ? 4 : 0)
            .background(overlay.style == .banner ? Color.black.opacity(0.65) : Color.clear)
            .shadow(radius: overlay.style == .light ? 6 : 0)
            .position(x: canvas.width * overlay.x + (moving ? dragOffset.width : 0),
                      y: canvas.height * overlay.y + (moving ? dragOffset.height : 0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragId = overlay.id
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        // **離したときに位置へ入れる。** 動かしている最中に
                        // 入れると、はみ出しの丸めが毎フレーム効いて指から離れる
                        move(overlay, by: value.translation, in: canvas)
                        dragId = nil
                        dragOffset = .zero
                    }
            )
            // 押すと文字を直せる（消すのも同じ入口）
            .onTapGesture { startEditing(overlay) }
            .accessibilityLabel(overlay.text)
    }

    private func move(_ overlay: TextOverlay, by translation: CGSize, in canvas: CGSize) {
        guard let index = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        overlays[index] = overlays[index].moved(by: translation, in: canvas)
    }

    // MARK: - 操作

    @ViewBuilder
    private var controls: some View {
        if let editingId, let index = overlays.firstIndex(where: { $0.id == editingId }) {
            VStack(spacing: 8) {
                TextField(L("文字", "Text"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft) { _, value in
                        overlays[index].text = String(value.prefix(TextOverlay.maxLength))
                    }

                HStack(spacing: 8) {
                    // **場所と曲は帯で固定**（読めない札を作らせない）ので
                    // 見た目の選択を出さない
                    if overlays[index].kind == .text {
                        ForEach(TextOverlay.Style.allCases) { style in
                            Button(style.label) { overlays[index].style = style }
                                .buttonStyle(.bordered)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        overlays.remove(at: index)
                        self.editingId = nil
                    } label: {
                        Label(L("消す", "Delete"), systemImage: "trash")
                    }
                }

                // 大きさ。**幅は `TextOverlay` が決める**（読めない／覆う を防ぐ）
                Slider(value: Binding(
                    get: { overlays[index].size },
                    set: { overlays[index].size = TextOverlay.clampSize($0) }
                ), in: TextOverlay.minSize...TextOverlay.maxSize)

                Button(L("できた", "Done")) {
                    // 空のまま閉じたら置かない（見えない物を焼き込まない）
                    if overlays[index].isEmpty { overlays.remove(at: index) }
                    self.editingId = nil
                }
            }
        } else {
            // モック4 の下の並び（テキスト／場所／BGM）。
            // **場所と曲は投稿の項目としても送る**ので、ここに置くのは
            // 「写真の上に見た目として残すか」だけ
            HStack(spacing: 10) {
                extraTools()
                addButton(L("テキスト", "Text"), systemImage: "textformat", kind: .text)
                addButton(L("場所", "Place"), systemImage: "mappin", kind: .place)
                addButton(L("BGM", "Music"), systemImage: "music.note", kind: .song)
            }
        }
    }

    /// 道具1つぶんの見た目（外の道具も同じ形にするために公開）
    static func toolLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title3)
            Text(title).font(.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(WebTheme.foreground)
    }

    private func addButton(_ title: String, systemImage: String,
                           kind: TextOverlay.Kind) -> some View {
        Button {
            add(kind: kind)
        } label: {
            Self.toolLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(overlays.count >= TextOverlay.maxCount)
        .accessibilityIdentifier("story.add.\(kind.rawValue)")
    }

    private func add(kind: TextOverlay.Kind) {
        // **真ん中より少し上に置く。** 真ん中だと写真の主役に重なりやすい。
        // 場所と曲は少し下（文字の札と重なりにくい）
        let y = kind == .text ? 0.35 : 0.6
        let overlay = TextOverlay(text: "", x: 0.5, y: y, kind: kind)
        overlays.append(overlay)
        startEditing(overlay)
    }

    private func startEditing(_ overlay: TextOverlay) {
        editingId = overlay.id
        draft = overlay.text
    }
}
