import SwiftUI

/// 撮影スポットの画面で共用する部品。
///
/// `SpotDetailView`（撮影地の集まり・モック5）から**そのまま移した**もの。
/// 台帳の撮影スポット（`OfficialSpotView`・モック13）も同じ札・見出しで
/// 組むので、2つの画面が同じ形を二度書かないようにここに置く。
@MainActor
enum SpotDetailParts {

    /// 行動の札（行きたい・シェア・地図で見る・経路）。`filled` は白地＝押した状態。
    ///
    /// **v2（2026-10-14・板 SpotDetail の `.act`）**: 同じ幅の大きな札（高さ 64・角 14・白 7%）に
    /// 印（18pt）と 13pt の太字の名前を縦に積む。印も白（押した状態は白 94% に墨）。v1 は 48 の横並び
    static func actionLabel(icon: String, title: String, filled: Bool, busy: Bool = false) -> some View {
        VStack(spacing: JPSpace.xxs) {
            // 待っている間は記号の代わりに輪（名前は替えない・札の幅に収める）
            if busy {
                ProgressView().controlSize(.small)
                    .tint(filled ? WebTheme.accentText : WebTheme.foreground)
            } else {
                Image(systemName: icon)
                    .font(.system(size: actionIconSize))
            }
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(WebTheme.minimumScale(forTextSize: JPTypeScale.footnote))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: actionHeight)
        .background(filled ? AnyShapeStyle(WebTheme.accentBackground) : AnyShapeStyle(WebTheme.surface),
                    in: RoundedRectangle(cornerRadius: JPRadius.m))
        .foregroundStyle(filled ? WebTheme.accentText : WebTheme.foreground)
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
    }

    /// 行動の札の高さ（板 64）・印の大きさ（板 18）
    nonisolated static let actionHeight: CGFloat = JPHeight.tallRow
    nonisolated static let actionIconSize: CGFloat = 18

    /// 数え札。**数えたものだけ**に使う
    static func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption)
                Text(value).font(.headline)
            }
            .foregroundStyle(WebTheme.foreground)
            Text(label)
                .font(.caption)  // 標準で 12pt（本文の最小）・字の大きさの設定に追従
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JPSpace.s)
        // v2 の札（surface-1・白 8% の縁・角 16）
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }

    /// 節の見出し。**v2（2026-10-14・板 SpotDetail の節）**: 真鍮の眉ラベルと消えていく線（`JPEyebrowLine`・
    /// 任意）→ 明朝 22 の見出し。黒地の上だけで使う（真鍮）
    ///
    /// - Parameters:
    ///   - eyebrow: 眉の字（「ABOUT」「LIGHT · 時間帯」）。無ければ見出しだけ
    ///   - spoken: 眉の読み上げ（英字の眉を日本語で読ませる）
    static func sectionHeader(_ title: String, eyebrow: String? = nil, spoken: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if let eyebrow {
                JPEyebrowLine(eyebrow, spoken: spoken)
            }
            Text(title)
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, JPSpace.m)
    }

    /// 近くの撮影地の札（表紙つき）
    static func nearbyCard(_ other: DerivedSpot.Place, km: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: other.cover?.gridImageURL, alignment: .center)
                }
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(LocationMatch.display(other.label))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                // **距離は計算したもの。** 言い方は「近くの写真」と
                // 同じ関数に寄せる（`NearbyPhotos.label`）——2つ持つと、
                // 同じ距離が画面によって「約42.7km」と「約43km」に割れる
                Text(NearbyPhotos.label(km: km))
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 180)
        // v2 の札（surface-1・白 8% の縁・角 14）
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
    }
}
