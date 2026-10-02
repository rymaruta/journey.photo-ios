import SwiftUI
import UIKit

/// 写真の編集画面（Phase 2・2026-10-02）。投稿画面の帯のサムネを押すと開く（写真ごと）。
///
/// デザインは Artifact「写真の編集 — 画面の候補」の 1（owner 2026-10-02: 比べ方は**長押し**・
/// プリセット名は今のまま）。デザインシステム「黒塗りの真鍮」に合わせて:
/// - 上: 左「キャンセル」（白）、中央に取り消し・やり直し（白、押せないときは薄く）、
///   右「完了」（真鍮・太字。黒地のヘッダーの文字ボタン）
/// - 写真は黒地に収める（fit）。**長押しの間だけ元の写真（無編集）**、左上に「編集前」の札（黒 62% に白 13pt）。
///   写真の上は白だけ
/// - タブ「フィルム」「調整」。選んでいるタブは真鍮の字と下線（黒地）
/// - フィルム: 「なし」＋プリセット8つ。64pt の見本、選んでいるのは真鍮 2px の輪＋名前を真鍮。強さ 0〜100
/// - 調整: 6項目。変えた項目はアイコンを真鍮＋右上に 8pt の真鍮の点（ストーリーの道具の C 案と同じ合図）、
///   選んでいる項目は #1A1A1A の丸。つまみ −100〜+100、値、「0に戻す」
///
/// 状態と判定は `PhotoEditScreen`（純・Linux で試験）。描くのは `PhotoEditPreview`
/// （画面の処理の外で・最新だけ）。**元の画素は変えない**——返すのはレシピだけ
struct PhotoEditView: View {

    /// 編集の元を読む口（画面の処理の外で呼ぶ・`PendingPhoto.editSourceReader`）
    let source: @Sendable () -> Data
    /// 「完了」。確定したレシピを返す
    let onDone: (PhotoRecipe) -> Void
    /// 「キャンセル」（編集を捨てる）
    let onCancel: () -> Void

    @State private var screen: PhotoEditScreen
    @StateObject private var preview = PhotoEditPreview()
    @State private var confirmDiscard = false
    @Environment(\.displayScale) private var displayScale

    init(recipe: PhotoRecipe, source: @escaping @Sendable () -> Data,
         onDone: @escaping (PhotoRecipe) -> Void, onCancel: @escaping () -> Void) {
        self.source = source
        self.onDone = onDone
        self.onCancel = onCancel
        _screen = State(initialValue: PhotoEditScreen(original: recipe))
    }

    /// 板の色（黒地の上の灰。デザインシステムの値）
    private static let selectedFill = Color(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0)
    private static let idle = Color(red: 0xB8 / 255.0, green: 0xB8 / 255.0, blue: 0xB8 / 255.0)
    private static let hint = Color(red: 0x99 / 255.0, green: 0x99 / 255.0, blue: 0x99 / 255.0)
    /// つまみの塗り（板の outline #666666。#3A3A3A は黒地で見えにくかった）
    private static let track = WebTheme.outline
    /// プリセットの見本の大きさ（pt）
    private static let thumbSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            header
            photo
            Text(L("写真を長押しすると、編集前と比べられます", "Touch and hold the photo to compare with the original"))
                .font(.system(size: 12))
                .foregroundStyle(Self.hint)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 8)
            tabs
            Group {
                switch screen.tab {
                case .film: filmPanel
                case .adjust: adjustPanel
                }
            }
            .frame(height: 150, alignment: .top)
            .padding(.top, 10)
        }
        // 色の背景は安全域の外まで塗る（`background(_:ignoresSafeAreaEdges:)` の既定）
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onChange(of: screen.current) { _, recipe in
            preview.request(recipe)
        }
        .confirmationDialog(L("編集を破棄しますか？", "Discard your edits?"),
                            isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L("破棄する", "Discard"), role: .destructive) { onCancel() }
            Button(L("編集を続ける", "Keep editing"), role: .cancel) { }
        }
    }

    // MARK: - 上

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                if screen.asksBeforeDiscard { confirmDiscard = true } else { onCancel() }
            } label: {
                Text(L("キャンセル", "Cancel"))
                    .font(.system(size: 17))
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                historyButton(symbol: "arrow.uturn.backward", label: L("取り消す", "Undo"),
                              enabled: screen.canUndo) { screen.undo() }
                historyButton(symbol: "arrow.uturn.forward", label: L("やり直す", "Redo"),
                              enabled: screen.canRedo) { screen.redo() }
            }
            Spacer(minLength: 0)
            Button {
                onDone(screen.finished)
            } label: {
                Text(L("完了", "Done"))
                    .font(.system(size: 17, weight: .semibold))
                    // 黒地のヘッダーの文字ボタンなので真鍮（owner の好み: デザインの箇所は白より真鍮）
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photoEdit.done")
        }
        .padding(.horizontal, 6)
        .frame(height: 52)
    }

    private func historyButton(symbol: String, label: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(WebTheme.foreground)
                .opacity(enabled ? 1 : 0.35)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - 写真

    private var photo: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                if let shown = screen.showsBeforeLabel ? preview.before : (preview.edited ?? preview.before) {
                    Image(uiImage: shown)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if preview.failed {
                    Text(L("写真を読み込めませんでした", "Couldn't load the photo"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .tint(WebTheme.foreground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if screen.showsBeforeLabel {
                    // 写真の上なので白（真鍮は写真の上では読めない）
                    Text(L("編集前", "Original"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.62), in: Capsule())
                        .padding(12)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            // **触れている間を取る**（距離 0 の DragGesture）。`onLongPressGesture` は長押しと認めた瞬間に
            // 終わるので、離すまで編集前を出し続けられない。触れてから `holdDelay` たったら時計を送り、
            // 判定は `PhotoEditScreen.press`（純）に任せる。離したら必ず戻す
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard screen.pressedAt == nil else { return }
                        screen.press(.began(at: Date()))
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(PhotoEditScreen.holdDelay * 1_000_000_000))
                            screen.press(.tick(now: Date()))
                        }
                    }
                    .onEnded { _ in screen.press(.ended) }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(screen.showsBeforeLabel ? L("元の写真", "Original photo")
                                                        : L("編集中の写真", "Photo being edited"))
            .accessibilityAddTraits(.isImage)
            .onAppear {
                preview.start(source: source, box: proxy.size, scale: Double(displayScale),
                              thumbPoints: Double(Self.thumbSize), current: screen.current)
            }
        }
    }

    // MARK: - タブ

    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton(L("フィルム", "Film"), selected: screen.tab == .film) { screen.tab = .film }
            tabButton(L("調整", "Adjust"), selected: screen.tab == .adjust) { screen.tab = .adjust }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Self.selectedFill).frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    private func tabButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                // 選んでいるタブは真鍮の字と下線（黒地の上）
                .foregroundStyle(selected ? WebTheme.accent : Self.hint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(selected ? WebTheme.accent : Color.clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - フィルム

    private var filmPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    presetButton(id: nil, name: L("なし", "None"))
                    ForEach(PhotoPresets.all) { preset in
                        presetButton(id: preset.id, name: preset.name)
                    }
                }
                .padding(.horizontal, 16)
                // 選んでいる輪（外へ 4pt）が切れないように
                .padding(.vertical, 4)
            }
            if let strength = screen.strengthSlider {
                HStack(spacing: 14) {
                    Text(L("強さ", "Strength"))
                        .font(.system(size: 13))
                        .foregroundStyle(Self.idle)
                    Slider(value: Binding(get: { strength }, set: { screen.dragStrength($0) }),
                           in: PhotoEditScreen.strengthSliderRange,
                           onEditingChanged: { editing in if !editing { screen.endDrag() } })
                        .tint(Self.track)
                        .accessibilityLabel(L("フィルムの強さ", "Film strength"))
                        .accessibilityValue("\(Int(strength))")
                    Text("\(Int(strength))")
                        .font(JPFont.number(15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(width: 34, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
        }
    }

    private func presetButton(id: String?, name: String) -> some View {
        let selected = screen.selectedPresetId == id
        return Button {
            screen.selectPreset(id)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let thumb = preview.thumbs[id ?? PhotoEditPreview.noneKey] {
                        Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        WebTheme.surface
                    }
                }
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // 選んでいるのは真鍮 2px の輪（黒い隙間 2px を挟んで外側に）
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(selected ? WebTheme.accent : Color.clear, lineWidth: 2)
                        .padding(-4)
                )
                Text(name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? WebTheme.accent : Self.idle)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 調整

    private var adjustPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(PhotoEditScreen.Adjustment.allCases) { item in
                        adjustmentButton(item)
                    }
                }
                .padding(.horizontal, 10)
            }
            HStack(spacing: 12) {
                let value = screen.adjustmentSlider
                Slider(value: Binding(get: { value }, set: { screen.dragAdjustment($0) }),
                       in: PhotoEditScreen.adjustmentSliderRange,
                       onEditingChanged: { editing in if !editing { screen.endDrag() } })
                    .tint(Self.track)
                    .accessibilityLabel(screen.adjustment.label)
                    .accessibilityValue(PhotoEditScreen.valueText(value))
                Text(PhotoEditScreen.valueText(value))
                    .font(JPFont.number(15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: 44, alignment: .trailing)
                    .accessibilityHidden(true)
                Button {
                    screen.resetAdjustment()
                } label: {
                    Text(L("0に戻す", "Reset"))
                        .font(.system(size: 13))
                        .foregroundStyle(value == 0 ? WebTheme.faint : WebTheme.foreground)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(value == 0)
                .accessibilityLabel(L("\(screen.adjustment.label)を0に戻す", "Reset \(screen.adjustment.label)"))
            }
            .padding(.horizontal, 16)
        }
    }

    private func adjustmentButton(_ item: PhotoEditScreen.Adjustment) -> some View {
        let selected = screen.adjustment == item
        let changed = item.isChanged(in: screen.current)
        return Button {
            screen.adjustment = item
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    // 変えた項目は真鍮（黒地の上）。選んでいるだけなら白、ふだんは灰
                    .foregroundStyle(changed ? WebTheme.accent : (selected ? WebTheme.foreground : Self.idle))
                    .frame(width: 40, height: 40)
                    .background(selected ? Self.selectedFill : Color.clear, in: Circle())
                Text(item.label)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? WebTheme.foreground : Self.idle)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 76, minHeight: 64)
            .overlay(alignment: .topTrailing) {
                if changed {
                    // ストーリーの道具の C 案と同じ合図（真鍮の 8pt の点）
                    Circle()
                        .fill(WebTheme.accent)
                        .frame(width: StoryTool.dotSize, height: StoryTool.dotSize)
                        .padding(.top, 4)
                        .padding(.trailing, 14)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel(changed: changed))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 編集画面の見本を描く（Core Image・`PhotoRenderer`）。
///
/// - **画面に合う大きさに縮めて読む**（`PhotoRenderer.previewPixelSize`。原本をそのまま Core Image に渡さない）
/// - **描くのは画面の処理の外。** つまみを動かしている間も画面は止まらない
/// - **最新だけを描く**（`LatestOnlyQueue`）。描いている間に来た値は最後の1つだけ残し、途中の値は捨てる
/// - 元の写真（無編集）は最初に1回だけ描いて持つ——長押しで即座に出すため
/// - プリセットの見本（64pt）は小さく読んだものに強さ 1 で当てて、最初に1回だけ描く
@MainActor
final class PhotoEditPreview: ObservableObject {

    /// 「なし」の見本の鍵（画面の処理の外の描画からも読む）
    nonisolated static let noneKey = ""

    @Published private(set) var edited: UIImage?
    @Published private(set) var before: UIImage?
    @Published private(set) var thumbs: [String: UIImage] = [:]
    @Published private(set) var failed = false

    /// 読んだ写真（`PhotoRenderer.Loaded` は Core Image の画像を持つ。描くときは読むだけ）
    private final class Box: @unchecked Sendable {
        let loaded: PhotoRenderer.Loaded
        init(_ loaded: PhotoRenderer.Loaded) { self.loaded = loaded }
    }

    private var box: Box?
    private var started = false
    private var queue = LatestOnlyQueue<PhotoRecipe>()
    /// 読み終わる前に来た最新の値
    private var waiting: PhotoRecipe?

    func start(source: @escaping @Sendable () -> Data, box size: CGSize, scale: Double, thumbPoints: Double,
               current: PhotoRecipe) {
        guard !started else { return }
        started = true
        waiting = current
        // 枠に収める長い辺（写真の比はまだ分からないので枠の長い辺・`previewPixelSize` の注記）
        let pixels = PhotoRenderer.previewPixelSize(box: size, scale: scale) ?? 1200
        // 見本は 64pt の正方形を埋める（fill）。2:1 の写真でも短い辺が足りるよう倍を読む
        let thumbPixels = Int((thumbPoints * scale * 2).rounded(.up))
        Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { () -> (Box, UIImage?, [String: UIImage])? in
                let data = source()
                guard let full = PhotoRenderer.load(data: data, maxPixelSize: pixels) else { return nil }
                let renderer = PhotoRenderer.shared
                // 長押しで出す「編集前」は元の写真（無編集・`PhotoEditScreen.Press` の注記）
                let before = renderer.preview(.identity, loaded: full).map { UIImage(cgImage: $0) }
                var thumbs: [String: UIImage] = [:]
                if let small = PhotoRenderer.load(data: data, maxPixelSize: thumbPixels) {
                    if let image = renderer.preview(.identity, loaded: small) { thumbs[Self.noneKey] = UIImage(cgImage: image) }
                    for preset in PhotoPresets.all {
                        let recipe = PhotoRecipe(preset: .init(id: preset.id, strength: 1))
                        if let image = renderer.preview(recipe, loaded: small) { thumbs[preset.id] = UIImage(cgImage: image) }
                    }
                }
                return (Box(full), before, thumbs)
            }.value
            guard let self else { return }
            guard let loaded else {
                self.failed = true
                return
            }
            self.box = loaded.0
            self.before = loaded.1
            self.thumbs = loaded.2
            if let waiting = self.waiting {
                self.waiting = nil
                self.request(waiting)
            }
        }
    }

    /// 描いてほしい値。描いている最中なら最新だけを待たせる
    func request(_ recipe: PhotoRecipe) {
        guard box != nil else {
            waiting = recipe
            return
        }
        if let job = queue.submit(recipe) { run(job) }
    }

    private func run(_ recipe: PhotoRecipe) {
        guard let box else { return }
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                PhotoRenderer.shared.preview(recipe, loaded: box.loaded).map { UIImage(cgImage: $0) }
            }.value
            guard let self else { return }
            // 描き終えた絵は出してよい（表示中の絵より新しい）。待っていた最新があれば続けて描く
            if let image { self.edited = image }
            if let next = self.queue.finish() { self.run(next) }
        }
    }
}
