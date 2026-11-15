import SwiftUI

/// 題・説明の欄の下に出す、端末の AI の候補の札（札 #622・2026-11-15 判断）。
///
/// **押せば欄に入り、要らなければ無視できる。** 欄を勝手に書き換えない——欄が空のときだけ出し
/// （`PostSuggest.showsTitles` / `showsCaption`）、押したときだけ入れる。押したら欄が埋まるので札は消える。
/// 押す回数: 題を打つ（字の数だけ）→ 札を1回押す。
///
/// 形（デザインの板 DesignSystem 03「チップ 34、当たり 44」・Components の独立した丸いチップ）:
/// 見た目 34・左右 14・字 13（`JPFont.footnote`）・地は白 7%（`WebTheme.surface`）に白 8% の縁（`hairline`）。
/// 頭に真鍮のきらめきの印（黒い地の上の手がかり＝真鍮・owner の好み「デザインの箇所は白より真鍮」）。
/// 印で「AI の候補」と分かる形にし、読み上げは「AI の題の候補」と言う（色だけに頼らない）。
/// 説明の候補は長いので、角 12 の札で折り返す（切り詰めない・大きい字でも全部読める）
struct PostSuggestChips: View {

    enum Kind {
        case title
        case caption
    }

    let kind: Kind
    let candidates: [String]
    let onPick: (String) -> Void

    var body: some View {
        switch kind {
        case .title:
            FlowLayout(spacing: JPSpace.xs, lineSpacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { index, text in
                    titleChip(text)
                        .accessibilityIdentifier("upload.suggest.title.\(index)")
                }
            }
            // 札の上下の押せるだけの余白（5＋5）のぶん、並びを欄に寄せる（見た目の間は前の欄の間のまま）
            .padding(.vertical, -PillChip.tapSlack)
        case .caption:
            ForEach(Array(candidates.prefix(1).enumerated()), id: \.offset) { _, text in
                captionChip(text)
                    .accessibilityIdentifier("upload.suggest.caption")
            }
        }
    }

    /// 真鍮のきらめき（AI の候補の印）。読み上げは札の名前で言うので隠す
    private var mark: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(WebTheme.accent)
            .accessibilityHidden(true)
    }

    private func titleChip(_ text: String) -> some View {
        Button { onPick(text) } label: {
            HStack(spacing: JPSpace.xxs) {
                mark
                Text(text)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minWidth: WebTheme.minTapTarget, minHeight: PillChip.height)
            .background(WebTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .padding(.vertical, PillChip.tapSlack)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("AI の題の候補 \(text)", "AI title suggestion \(text)"))
        .accessibilityHint(L("押すと題に入ります", "Puts this in the title"))
    }

    private func captionChip(_ text: String) -> some View {
        Button { onPick(text) } label: {
            HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                mark
                Text(text)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: JPRadius.field))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.field)
                .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.field))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("AI の説明の候補 \(text)", "AI description suggestion \(text)"))
        .accessibilityHint(L("押すと説明に入ります", "Puts this in the description"))
    }
}
