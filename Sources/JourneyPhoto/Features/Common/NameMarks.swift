import SwiftUI

/// 名前の横に並ぶ印（2026-10-09）。**並びは 名前 → 公式（運営だけ）→ Pro マーク → 選んだバッジ。**
///
/// - 公式の封印（`VerifiedBadge`）: 運営が立てた人だけ
/// - Pro マーク（`ProMark`）: Pro 会員だけ。形は本人が選ぶ
/// - 選んだバッジ: **プロフィールの頁だけ**（`showsBadge`）。写真の詳細の作者の行には出さない。
///   名前の横の画面の下見は、選んでいる途中の値を直接渡す
///
/// 大きさはどれも名前の字に合わせる（`VerifiedBadge.Fit`・`ProMarkFit`・`BadgeFit`）。
/// 文字サイズの設定（Dynamic Type）には、名前と同じ文字の種類で伸び縮みさせる
/// ——公式の封印は記号の字の大きさで伸びるので、絵で描く2つも同じ割合で伸ばす。
struct NameMarks: View {

    /// 公式の封印（運営が立てた人だけ）
    let verified: Bool?
    /// Pro マークの形。**nil は Pro でない**（印を出さない）
    let proStyle: ProMarkStyle?
    /// 名前の横に出すバッジ（プロフィールの頁だけ渡す）
    let badge: EarnedBadge?
    var nameSize: Double = 15
    var relativeTo: Font.TextStyle = .subheadline
    var fit: VerifiedBadge.Fit = .system
    /// バッジを押したとき（人の頁: その人の棚を開く）。nil なら押せない
    var onBadgeTap: ((EarnedBadge) -> Void)?

    init(verified: Bool?, proStyle: ProMarkStyle?, badge: EarnedBadge?,
         nameSize: Double = 15, relativeTo: Font.TextStyle = .subheadline,
         fit: VerifiedBadge.Fit = .system, onBadgeTap: ((EarnedBadge) -> Void)? = nil) {
        self.verified = verified
        self.proStyle = proStyle
        self.badge = badge
        self.nameSize = nameSize
        self.relativeTo = relativeTo
        self.fit = fit
        self.onBadgeTap = onBadgeTap
    }

    /// プロフィールから。`showsBadge` はプロフィールの頁だけ true（写真の詳細の作者の行は false）
    init(profile: UserProfile?, nameSize: Double = 15, relativeTo: Font.TextStyle = .subheadline,
         fit: VerifiedBadge.Fit = .system, showsBadge: Bool = false,
         onBadgeTap: ((EarnedBadge) -> Void)? = nil) {
        self.init(verified: profile?.verified,
                  proStyle: (profile?.isPro ?? false) ? profile?.markStyle : nil,
                  badge: showsBadge ? profile?.shownBadge : nil,
                  nameSize: nameSize, relativeTo: relativeTo, fit: fit, onBadgeTap: onBadgeTap)
    }

    // 名前と同じ文字の種類で伸び縮みする倍率（`@ScaledMetric` は種類を宣言で決めるので、
    // 使う種類ぶん持って選ぶ）
    @ScaledMetric(relativeTo: .title) private var titleScale: Double = 1
    @ScaledMetric(relativeTo: .subheadline) private var subheadlineScale: Double = 1
    @ScaledMetric(relativeTo: .footnote) private var footnoteScale: Double = 1
    @ScaledMetric(relativeTo: .body) private var bodyScale: Double = 1

    private var scale: Double {
        switch relativeTo {
        case .largeTitle, .title, .title2, .title3: return titleScale
        case .subheadline: return subheadlineScale
        case .footnote, .caption, .caption2: return footnoteScale
        default: return bodyScale
        }
    }

    /// 印どうしの間（板: 明朝 26 で 7pt）。名前の字に比例させ、4pt を下回らせない
    private var spacing: Double { max(4, 7 * nameSize / BadgeFit.referenceNameSize) * scale }

    private var isMincho: Bool { fit == .mincho }

    var body: some View {
        HStack(spacing: spacing) {
            VerifiedBadge(isVerified: verified, nameSize: nameSize, relativeTo: relativeTo, fit: fit)
            if let proStyle {
                ProMark(style: proStyle,
                        side: ProMarkFit.side(nameSize: nameSize, mincho: isMincho) * scale)
                    // 公式の封印と同じく、行の中央ではなく字面の中央へ
                    .alignmentGuide(VerticalAlignment.center) { d in
                        d[VerticalAlignment.center] - d.height * fit.nudge
                    }
            }
            if let badge, BadgeCatalog.isKnown(badge.key) {
                badgeView(badge)
            }
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: EarnedBadge) -> some View {
        let mark = NameBadgeImage(badge: badge, nameSize: nameSize * scale)
            .alignmentGuide(VerticalAlignment.center) { d in
                d[VerticalAlignment.center] - d.height * fit.nudge
            }
        if let onBadgeTap {
            // 押せる範囲は 44pt 四方。**並びの上では円の大きさだけ取る**（行の高さを変えない）
            let slack = max(0, (WebTheme.minTapTarget - BadgeFit.circle(nameSize: nameSize * scale)) / 2)
            Button { onBadgeTap(badge) } label: {
                mark
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                    .padding(.horizontal, -slack)
                    .padding(.vertical, -slack)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BadgeCatalog.nameSideLabel(badge))
            .accessibilityHint(L("バッジの棚を開く", "Opens the badge shelf"))
        } else {
            mark
        }
    }
}

/// 名前の横のバッジの絵。**円の部分を公式の封印と同じ大きさにそろえ**、円の外の余白
/// （初期ユーザーは後光）は負の余白で打ち消して行の高さを変えない（`BadgeFit`）
struct NameBadgeImage: View {
    let badge: EarnedBadge
    /// 横に並ぶ名前の字の大きさ（文字サイズの設定で伸ばした後の値）
    let nameSize: Double

    var body: some View {
        let side = BadgeFit.imageSide(badge.key, nameSize: nameSize)
        Image(BadgeCatalog.smallImage(badge.key, tier: badge.tier))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
            .padding(-BadgeFit.overhang(badge.key, nameSize: nameSize))
            // 板: drop-shadow(0 1px 3px rgba(0,0,0,0.7))。黒地でも縁が溶けないように
            .shadow(color: Color.black.opacity(0.7), radius: 1.5, x: 0, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BadgeCatalog.nameSideLabel(badge))
    }

}

/// マイページの名前の行の読み上げ（行ごと1つのボタンにまとめるので、印の名前もここで言う）
enum MyPageNameLine {
    /// 「丸田、認証済み、Pro 会員、名前の横のバッジ: 都道府県 · 銀」
    static func label(_ profile: UserProfile) -> String {
        var parts = [profile.name]
        if profile.verified == true { parts.append(L("認証済み", "Verified")) }
        if profile.isPro { parts.append(L("Pro 会員", "Pro member")) }
        if let badge = profile.shownBadge, BadgeCatalog.isKnown(badge.key) {
            parts.append(BadgeCatalog.nameSideLabel(badge))
        }
        return parts.joined(separator: L("、", ", "))
    }
}
