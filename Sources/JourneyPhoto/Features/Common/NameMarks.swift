import SwiftUI
import UIKit

/// 名前の横に並ぶ印（2026-10-09）。**並びは 名前 → 公式（運営だけ）→ Pro マーク → 選んだバッジ。**
///
/// - 公式の封印（`VerifiedBadge`）: 運営が立てた人だけ。本人は外せる（付ける・外すだけ）
/// - Pro マーク（`ProMark`）: Pro 会員だけ。形は本人が選び、外すこともできる
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
        // 本人が外した印は出さない（2026-10-10）。他の人の公開プロフィールは、外した人の資格の項目を
        // サーバーが落として返すので、同じ判定のままで出ない
        self.init(verified: profile?.showsVerifiedMark,
                  proStyle: profile?.shownProMark,
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

/// 名前の横のバッジの絵。**大きいメダルの絵（棚と同じ絵）をそのまま縮めて出す**（案 C・2026-10-09
/// owner「そのままがいい」）。文字の帯を省いた小さい絵（`-s`）は使わない（選ぶ画面・お知らせだけ）。
///
/// **円の部分を公式の封印と同じ大きさにそろえ**、円の外の余白（初期ユーザーは後光）は負の余白で
/// 打ち消して行の高さを変えない（`BadgeFit`）。
///
/// 縮め方: 画面の画素ちょうどに Lanczos で縮めて軽く輪郭を立てた絵（`NameBadgeRaster`）を、
/// 画面の処理の外で1度だけ作って覚える（`RasterBadgeArt`）。できるまでは同じ大きさの透明な枠だけ
/// （一瞬空いてから出る。行の高さ・並びは動かない）
struct NameBadgeImage: View {
    let badge: EarnedBadge
    /// 横に並ぶ名前の字の大きさ（文字サイズの設定で伸ばした後の値）
    let nameSize: Double

    var body: some View {
        RasterBadgeArt(image: BadgeCatalog.nameSideImage(badge.key, tier: badge.tier),
                       side: BadgeFit.imageSide(badge.key, nameSize: nameSize))
            .padding(-BadgeFit.overhang(badge.key, nameSize: nameSize))
            // 板: drop-shadow(0 1px 3px rgba(0,0,0,0.7))。黒地でも縁が溶けないように
            .shadow(color: Color.black.opacity(0.7), radius: 1.5, x: 0, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BadgeCatalog.nameSideLabel(badge))
    }
}

/// 大きいメダルの絵を**表示の画素ちょうどに縮めて**、一辺 `side` pt の四角に出す（`NameBadgeRaster`）。
///
/// 名前の横（`NameBadgeImage`）から切り出した（2026-10-09 判断: 名前の横の画面の2つの格子・棚の
/// 「名前の横に飾る」・お知らせのメダルも、`-s` の引き伸ばしをやめて同じ縮め方にする。写しを作らない）。
/// 縮めた絵は画面の処理の外で1度だけ作って覚える（同じ鍵を同時に頼んでも1回・`NameBadgeRaster.shared`）。
///
/// **できるまでは透明な同じ大きさの枠だけ**（2026-10-09 確かめ役の指摘: 520〜780px の大きい絵を
/// 格子の 16〜24 枚ぶん画面の処理で開いて描いていた）。一瞬空いてから出る。
///
/// **作り直しの合図は絵の名前と画素の数**（`taskID`）。倍率・文字の大きさ・絵が替われば作り直し、
/// 前の鍵で作った絵は使わない（`matches`）
struct RasterBadgeArt: View {
    /// 絵の入れ物の名前（大きい絵。`BadgeCatalog.largeImage` など）
    let image: String
    /// 一辺（pt）
    let side: Double

    @Environment(\.displayScale) private var displayScale
    /// 縮めて作った絵（鍵が合うときだけ使う）
    @State private var rendered: Rendered?

    private struct Rendered: Equatable {
        let key: String
        let image: UIImage

        static func == (lhs: Rendered, rhs: Rendered) -> Bool { lhs.key == rhs.key }
    }

    /// 作り直しの合図（`.task(id:)`）。絵の名前と画素の数を含む
    nonisolated static func taskID(image: String, pixels: Int?) -> String {
        pixels.map { NameBadgeRaster.cacheKey(image: image, pixels: $0) } ?? image
    }

    /// 作った絵がいまの鍵のものか（前の倍率・前の絵で作ったものは使わない）
    nonisolated static func matches(renderedKey: String?, key: String) -> Bool { renderedKey == key }

    var body: some View {
        let name = image
        let pixels = NameBadgeRaster.pixelSide(points: side, scale: Double(displayScale))
        let key = Self.taskID(image: name, pixels: pixels)
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                if let art = art(name: name, pixels: pixels, key: key) {
                    art
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .task(id: key) {
                guard let pixels, !Self.matches(renderedKey: rendered?.key, key: key) else { return }
                let made = await NameBadgeRaster.shared(named: name, pixels: pixels)
                if let made, !Task.isCancelled { rendered = Rendered(key: key, image: made) }
            }
    }

    /// 縮めて作った絵（いまの鍵のもの・覚えにあるもの）。無ければ nil（透明の枠だけ）
    private func art(name: String, pixels: Int?, key: String) -> Image? {
        if let rendered, Self.matches(renderedKey: rendered.key, key: key) { return Image(uiImage: rendered.image) }
        if let pixels, let hit = NameBadgeRaster.cached(image: name, pixels: pixels) { return Image(uiImage: hit) }
        return nil
    }
}

/// マイページの名前の行の読み上げ（行ごと1つのボタンにまとめるので、印の名前もここで言う）
enum MyPageNameLine {
    /// 「丸田、認証済み、Pro 会員、名前の横のバッジ: 都道府県 · 銀」
    static func label(_ profile: UserProfile) -> String {
        var parts = [profile.name]
        // 名前の横に**出ている**印だけを言う（外した印は言わない・2026-10-10）
        if profile.showsVerifiedMark { parts.append(L("認証済み", "Verified")) }
        if profile.shownProMark != nil { parts.append(L("Pro 会員", "Pro member")) }
        if let badge = profile.shownBadge, BadgeCatalog.isKnown(badge.key) {
            parts.append(BadgeCatalog.nameSideLabel(badge))
        }
        return parts.joined(separator: L("、", ", "))
    }
}
