import SwiftUI

/// **節の見出し**（v2 の板 Search・Main・Notifications の空の状態・2026-10-14）。
///
/// 板の型は1つ: 眉（真鍮の字＋右へ消える線・`JPEyebrowLine`）→ 明朝 22 の題 → 右下に「すべて ›」。
/// 探す・ホームの段がそれぞれ見出しを書いていて（12pt の灰の字・`subheadline` の白・明朝 18）、
/// 同じ「段の見出し」が画面ごとに3通りあった。ここに寄せる（2026-10-14 判断）。
///
/// **黒地の上だけ**（眉の真鍮は写真の上では読めない・CLAUDE.md）
///
/// **節の見出しはこれ1つ**（2026-10-14 判断）。撮影スポットの `SpotDetailParts.sectionHeader`（眉と題の間 12）・
/// 旅の一冊の日の見出し（間 4）・ここ（間 8）と、同じ形が3つあり間もずれていた。間は板 Components 05 の
/// 節の見出し（`gap: 6px`）にそろえて `JPSectionHeadingLayout.eyebrowGap` に置く。
/// 札の上の小さい灰の見出し（`JPSectionTitle`・12pt）は形が違う部品なので寄せない
struct JPSectionHeading<Trailing: View>: View {

    /// 眉（英字の大文字や「THIS SEASON · 秋」）。nil なら題だけ（撮影スポットの「地図」のような段）
    let eyebrow: String?
    /// 眉の読み上げ（英字の眉を日本語で読ませる）。無ければ眉の字
    var spoken: String?
    /// 明朝の題。nil なら眉だけ（板 PlacesSearch の「種類から」のような小さい段）
    var title: String?
    /// 題の行の上限。nil なら折り返しきる（撮影スポットの節は件数入りの長い題があり、切らない）
    var titleLineLimit: Int?
    let trailing: Trailing

    init(eyebrow: String?, spoken: String? = nil, title: String? = nil, titleLineLimit: Int? = 2,
         @ViewBuilder trailing: () -> Trailing) {
        self.eyebrow = eyebrow
        self.spoken = spoken
        self.title = title
        self.titleLineLimit = titleLineLimit
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: JPSpace.s) {
            VStack(alignment: .leading, spacing: JPSectionHeadingLayout.eyebrowGap) {
                if let eyebrow {
                    JPEyebrowLine(eyebrow, spoken: spoken)
                }
                if let title {
                    Text(title)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(titleLineLimit)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

extension JPSectionHeading where Trailing == EmptyView {
    init(eyebrow: String?, spoken: String? = nil, title: String? = nil, titleLineLimit: Int? = 2) {
        self.init(eyebrow: eyebrow, spoken: spoken, title: title, titleLineLimit: titleLineLimit) { EmptyView() }
    }
}

/// 節の見出しの寸法（型が総称なので値はここに置く）
enum JPSectionHeadingLayout {
    /// 眉と題の間（板 Components 05 の節の見出し `gap: 6px`）。**`JPSpace` の 4 の律動の外**——
    /// 眉（11pt）と明朝 22 の組を板が 6 で詰めているので、板の値をそのまま持つ（2026-10-14 判断）
    nonisolated static let eyebrowGap: CGFloat = 6
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
