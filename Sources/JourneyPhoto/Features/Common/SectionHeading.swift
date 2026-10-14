import SwiftUI

/// **節の見出し**（v2 の板 Search・Main・Notifications の空の状態・2026-10-14）。
///
/// 板の型は1つ: 眉（真鍮の字＋右へ消える線・`JPEyebrowLine`）→ 明朝 22 の題 → 右下に「すべて ›」。
/// 探す・ホームの段がそれぞれ見出しを書いていて（12pt の灰の字・`subheadline` の白・明朝 18）、
/// 同じ「段の見出し」が画面ごとに3通りあった。ここに寄せる（2026-10-14 判断）。
///
/// **黒地の上だけ**（眉の真鍮は写真の上では読めない・CLAUDE.md）
struct JPSectionHeading<Trailing: View>: View {

    /// 眉（英字の大文字や「THIS SEASON · 秋」）
    let eyebrow: String
    /// 眉の読み上げ（英字の眉を日本語で読ませる）。無ければ眉の字
    var spoken: String?
    /// 明朝の題。nil なら眉だけ（板 PlacesSearch の「種類から」のような小さい段）
    var title: String?
    let trailing: Trailing

    init(eyebrow: String, spoken: String? = nil, title: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.eyebrow = eyebrow
        self.spoken = spoken
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: JPSpace.s) {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                JPEyebrowLine(eyebrow, spoken: spoken)
                if let title {
                    Text(title)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

extension JPSectionHeading where Trailing == EmptyView {
    init(eyebrow: String, spoken: String? = nil, title: String? = nil) {
        self.init(eyebrow: eyebrow, spoken: spoken, title: title) { EmptyView() }
    }
}

/// 節の右の「すべて ›」「地図で見る ›」（板の `.more`: 13・text-2・当たりは 44）。
/// **真鍮にしない**——節の行き先は合図ではなく道（板どおり灰）
struct MoreLink: View {
    let text: String
    /// 添える件数（「すべて 95件 ›」）。等幅の数字
    var count: String?

    var body: some View {
        HStack(spacing: JPSpace.xxs) {
            Text(text)
            if let count {
                Text(count)
                    .font(JPFont.number(JPTypeScale.footnote, weight: .regular, relativeTo: .footnote))
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(JPFont.footnote)
        .foregroundStyle(WebTheme.text2)
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget, alignment: .trailing)
        .contentShape(Rectangle())
    }
}
