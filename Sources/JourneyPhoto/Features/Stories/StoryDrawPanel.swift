import SwiftUI

/// 描画の欄（作る画面の写真の下・2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾）。
///
/// 筆（ペン・蛍光ペン・消しゴム）・色（12色・消しゴムのときは出さない）・太さ（筆ごとに覚える）。
/// 取り消し・やり直しと「完了」は上のバー（`StoryComposerView.topBar`）にある（描く間は欄が足元を隠す）。
///
/// 色: 欄の地は黒（92%）なので、選んだ筆・色の輪は真鍮（板「黒塗りの真鍮」・黒地の上）。
/// 色の見本そのものは線の色（写真に載る色）で、選びは**輪（形）・読み上げの「選択中」**でも伝える。
/// 押せる所は 44 以上（色は見た目 30・当たり 44）。触覚は筆・色を選んだとき。文字は 12 以上・Dynamic Type に付いてくる。
struct StoryDrawPanel: View {

    @Binding var pen: StoryPen

    /// 色の見本の見た目の大きさ（当たりは `minTapTarget`）
    static let swatchSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolRow
            if pen.tool != .eraser { colorRow }
            widthRow
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(red: 12 / 255.0, green: 12 / 255.0, blue: 13 / 255.0).opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .sensoryFeedback(.selection, trigger: pen.tool)
        .sensoryFeedback(.selection, trigger: pen.colorHex)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("描画の道具", "Drawing tools"))
        .accessibilityIdentifier("story.drawPanel")
    }

    // MARK: - 筆

    private var toolRow: some View {
        HStack(spacing: 8) {
            ForEach(StoryPenTool.allCases) { tool in
                toolButton(tool)
            }
        }
        .padding(.horizontal, 16)
    }

    private func toolButton(_ tool: StoryPenTool) -> some View {
        let selected = pen.tool == tool
        return Button {
            pen.tool = tool
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? WebTheme.accent : WebTheme.text)
                    .frame(height: 24)
                Text(tool.label)
                    .font(selected ? JPFont.caption.weight(.semibold) : JPFont.caption)
                    .foregroundStyle(selected ? WebTheme.accent : WebTheme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(WebTheme.deepestScale)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: JPRadius.s))
            .overlay {
                // 選びは輪（形）でも伝える。色は真鍮（黒地の欄の上）
                if selected {
                    RoundedRectangle(cornerRadius: JPRadius.s).strokeBorder(WebTheme.accent, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.s))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.label)
        .accessibilityValue(selected ? L("選択中", "Selected") : "")
        .accessibilityIdentifier("story.draw.\(tool.rawValue)")
    }

    // MARK: - 色

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(StoryPen.palette) { swatch in
                    colorButton(swatch)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func colorButton(_ swatch: StoryPen.Swatch) -> some View {
        let selected = pen.colorHex == swatch.hex
        let color = Color(red: Double((swatch.hex >> 16) & 0xFF) / 255,
                          green: Double((swatch.hex >> 8) & 0xFF) / 255,
                          blue: Double(swatch.hex & 0xFF) / 255)
        return Button {
            pen.colorHex = swatch.hex
        } label: {
            Circle()
                .fill(color)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                // 黒い見本が欄の黒に沈まないよう、薄い縁を引く
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                // 選びは外側の輪（形）で伝える。色は真鍮
                .overlay {
                    if selected {
                        Circle().strokeBorder(WebTheme.accent, lineWidth: 2).padding(-5)
                    }
                }
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
        .accessibilityValue(selected ? L("選択中", "Selected") : "")
        .accessibilityIdentifier("story.draw.color.\(String(swatch.hex, radix: 16))")
    }

    // MARK: - 太さ

    /// 細 — つまみ — 太。右に**いまの線の見本**（筆の色・不透明度・太さ。大きさは写真の短い辺を 390 とみなした見かけ）
    private var widthRow: some View {
        HStack(spacing: 12) {
            Circle().fill(WebTheme.text2)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { pen.widthFraction },
                                  set: { pen.setWidth(fraction: $0) }),
                   in: 0...1)
                .tint(WebTheme.accent)
                .accessibilityLabel(L("線の太さ", "Stroke width"))
                .accessibilityValue("\(Int((pen.widthFraction * 100).rounded()))%")
            Circle().fill(WebTheme.text2)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            widthPreview
        }
        .padding(.horizontal, 16)
        .frame(minHeight: WebTheme.minTapTarget)
    }

    /// いまの線の見本の丸（直径は太さ × 390 を 6〜36 に収める。消しゴムは輪）
    private var widthPreview: some View {
        let diameter = min(max(CGFloat(pen.width) * 390, 6), 36)
        let color = Color(red: Double((pen.colorHex >> 16) & 0xFF) / 255,
                          green: Double((pen.colorHex >> 8) & 0xFF) / 255,
                          blue: Double(pen.colorHex & 0xFF) / 255)
        return ZStack {
            if pen.tool == .eraser {
                Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
            } else {
                Circle().fill(color.opacity(pen.tool.opacity))
                    .frame(width: diameter, height: diameter)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
