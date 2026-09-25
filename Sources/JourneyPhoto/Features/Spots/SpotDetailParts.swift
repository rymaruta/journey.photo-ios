import SwiftUI

/// 撮影スポットの画面で共用する部品。
///
/// `SpotDetailView`（撮影地の集まり・モック5）から**そのまま移した**もの。
/// 台帳の撮影スポット（`OfficialSpotView`・モック13）も同じ札・見出しで
/// 組むので、2つの画面が同じ形を二度書かないようにここに置く。
@MainActor
enum SpotDetailParts {

    /// 行動の札（行きたい・シェア・地図で見る）。`filled` は白地＝押した状態
    static func actionLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(filled ? AnyShapeStyle(WebTheme.foreground) : AnyShapeStyle(WebTheme.surface),
                    in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(filled ? WebTheme.accentText : WebTheme.foreground)
    }

    /// 数え札。**数えたものだけ**に使う
    static func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption)
                Text(value).font(.headline)
            }
            .foregroundStyle(WebTheme.foreground)
            Text(label)
                .font(.caption2)
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 節の見出し
    static func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, 16)
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
                Text(other.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                // **距離は計算したもの。** 言い方は「近くの写真」と
                // 同じ関数に寄せる（`NearbyPhotos.label`）——2つ持つと、
                // 同じ距離が画面によって「約42.7km」と「約43km」に割れる
                Text(NearbyPhotos.label(km: km))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 180)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
