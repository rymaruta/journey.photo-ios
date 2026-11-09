import SwiftUI
import UIKit

/// フィルターの欄（作る画面の写真の下・2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾）。
///
/// 横に流れる列: 先頭は「なし」、そのあとに `StoryFilters.all`（約10種・自作・日本語の名前）。
/// **1つ1つが、いまの写真にそのフィルターをかけた見本**（`StoryFilterRenderer.swatches`）。選ぶと写真の絵が
/// その場で替わる。選んだフィルターがあるときは、下に**強さ**のつまみ（0〜100）。
///
/// 色: 欄の地は黒（92%）なので、選んだものの輪・名前・つまみは真鍮（板「黒塗りの真鍮」・黒地の上）。
/// **色だけで選びを伝えない**——輪（形）・太字・読み上げの「選択中」でも伝える。
/// 押せる所は 44 以上（見本は 64×86）。触覚は選んだとき。文字は 12 以上・Dynamic Type に付いてくる。
///
/// **この欄は持たない**: 選び（`choice`）は呼ぶ側の写真ごとの値、見本の絵は呼ぶ側が作って渡す。
struct StoryFilterPanel: View {

    @Binding var choice: StoryFilterChoice
    /// 見本（id → 絵）。届くまでは地の色
    let swatches: [String: Image]

    /// 見本の1辺・列の幅
    static let swatchSize: CGFloat = 64
    static let tileWidth: CGFloat = 68

    private var selectedId: String { choice.sanitized.id }
    private var hasFilter: Bool { selectedId != StoryFilterChoice.noneId }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    tile(id: StoryFilterChoice.noneId, name: L("なし", "None"))
                    ForEach(StoryFilters.all) { filter in
                        tile(id: filter.id, name: filter.name)
                    }
                }
                .padding(.horizontal, 16)
            }
            if hasFilter { strengthRow }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color(red: 12 / 255.0, green: 12 / 255.0, blue: 13 / 255.0).opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .sensoryFeedback(.selection, trigger: selectedId)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("フィルター", "Filters"))
        .accessibilityIdentifier("story.filterPanel")
    }

    private func tile(id: String, name: String) -> some View {
        let selected = selectedId == id
        return Button {
            choice = choice.selecting(id)
        } label: {
            VStack(spacing: 6) {
                swatch(id)
                    .frame(width: Self.swatchSize, height: Self.swatchSize)
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
                    .overlay {
                        // 選びは輪（形）でも伝える。色は真鍮（黒地の欄の上）
                        if selected {
                            RoundedRectangle(cornerRadius: JPRadius.s)
                                .strokeBorder(WebTheme.accent, lineWidth: 2)
                        }
                    }
                Text(name)
                    .font(selected ? JPFont.caption.weight(.semibold) : JPFont.caption)
                    .foregroundStyle(selected ? WebTheme.accent : WebTheme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(WebTheme.deepestScale)
            }
            .frame(width: Self.tileWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(selected ? L("選択中", "Selected") : "")
        .accessibilityIdentifier("story.filter.\(id)")
    }

    /// 見本の絵（読み込み中は地の色）。枠いっぱいに敷いて切る
    @ViewBuilder
    private func swatch(_ id: String) -> some View {
        if let image = swatches[id] {
            Color.clear.overlay {
                image.resizable().aspectRatio(contentMode: .fill)
            }
        } else {
            WebTheme.surface3
        }
    }

    private var strengthRow: some View {
        let percent = Int((choice.sanitized.strength * 100).rounded())
        return HStack(spacing: 12) {
            Text(L("強さ", "Strength"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
            Slider(value: Binding(get: { choice.sanitized.strength },
                                  set: { choice = choice.withStrength($0) }),
                   in: 0...1)
                .tint(WebTheme.accent)
                .accessibilityLabel(L("フィルターの強さ", "Filter strength"))
                .accessibilityValue("\(percent)%")
            Text("\(percent)")
                .font(JPFont.mono(13))
                .foregroundStyle(WebTheme.text)
                .frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: WebTheme.minTapTarget)
    }
}
