import SwiftUI

/// 探すの欄が空の間に出す「最近の検索」（2026-11-14 判断・`RecentSearchesStore`）。
///
/// 前は探した言葉が残らず、同じ地名を毎回打ち直していた。押す回数: 前「欄」→ 全部打つ、今「言葉」を1回押す。
///
/// 見た目（デザインの板 Search と DesignSystem の決まり）:
/// - 黒地の上の行。言葉は本文（白）、時計の印と × は text-3（合図ではないので真鍮にしない）
/// - 行・×・「すべて消す」の当たりは 44pt
/// - 見出しは小さい副文（段の見出し `JPSectionHeading` ほど大きくしない。発見の段より前に出しゃばらない）
/// - 消すのは確かめずに消す（取り返しの付かない操作・費用・プライバシーではない。CLAUDE.md「聞くのは最小に」）
struct RecentSearchesSection: View {

    let words: [String]
    var onPick: (String) -> Void
    var onRemove: (String) -> Void
    var onRemoveAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("最近の検索", "Recent searches"))
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onRemoveAll) {
                    Text(L("すべて消す", "Clear all"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("最近の検索をすべて消す", "Clear all recent searches"))
                .accessibilityIdentifier("search.recent.clearAll")
            }
            ForEach(words, id: \.self) { word in
                row(word)
            }
        }
        .padding(.horizontal, JPSpace.gutter)
        .accessibilityIdentifier("search.recent")
    }

    private func row(_ word: String) -> some View {
        HStack(spacing: JPSpace.s) {
            Button { onPick(word) } label: {
                HStack(spacing: JPSpace.s) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text3)
                        .accessibilityHidden(true)
                    Text(word)
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(word)で探す", "Search for \(word)"))
            .accessibilityIdentifier("search.recent.word")

            Button { onRemove(word) } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("「\(word)」を最近の検索から消す", "Remove \"\(word)\" from recent searches"))
            .accessibilityIdentifier("search.recent.remove")
        }
    }
}
