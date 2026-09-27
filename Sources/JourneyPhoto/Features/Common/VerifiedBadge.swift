import SwiftUI

/// 認証済みの印（名前の横の真鍮の封印・アーティファクトの板 08）。
///
/// **立っている人にだけ出す。** 誰も立てていなければ誰にも出ない
/// ——立てられるのは運営だけで、本人からは立てられない
/// （`api-user/src/userProfile.ts` の更新の経路は受け取らない）。
struct VerifiedBadge: View {

    let isVerified: Bool?
    /// 横に並ぶ名前の字の大きさと、その字が従う文字サイズの段。**印は名前に合わせる**
    /// ——以前は一律 `.caption`（約12pt）で、明朝 26 の名前の横では小さすぎた
    /// （owner:「バッチの大きさを名前に合わせて欲しい」）
    var nameSize: Double = 15
    var relativeTo: Font.TextStyle = .subheadline

    /// 名前の書体に合わせた、印の大きさと上下の位置。**実機の絵を画素で測って決めた**。
    var fit: Fit = .system

    struct Fit: Equatable {
        /// 名前の字の大きさに対する、印の記号の字の大きさ
        let ratio: Double
        /// 印の高さに対する、下へずらす量。行の中央（上下の余白込み）と漢字の字面の
        /// 中央がずれる分を埋める
        let nudge: Double

        /// 本文の書体（写真の詳細の作者の行など）。測っていないので既定の8割・ずらさない
        static let system = Fit(ratio: 0.8, nudge: 0)

        /// 明朝（マイページ・人のページの名前）。1.0.14 前のマイページの実機の絵
        /// （3倍・名前 26pt）で測った:
        ///
        ///     名前の字面   73px（24.3pt）・中央 y=38
        ///     印（8割）    70px（23.3pt）・中央 y=34.5   → 1pt 小さく、1.2pt 上
        ///
        /// 記号の高さは字の大きさの約 1.12 倍なので、字面に揃えるには
        /// 24.3 / 1.12 / 26 ≈ 0.835。上のずれ 3.5px は印の高さの約 4.8%
        static let mincho = Fit(ratio: 0.835, nudge: 0.048)
    }

    var body: some View {
        if isVerified == true {
            // **真鍮の封印**（板 08・A。2026-09-26 owner が決定）。
            // 2色を渡すと記号は塗り分けになる——1つ目がチェック（墨）、
            // 2つ目が封印（真鍮＝アプリの差し色）。撮影スポットの真鍮の丸とは
            // 形（封印の山）で見分ける
            Image(systemName: "checkmark.seal.fill")
                // 名前と同じ段で拡大縮小させる（文字を大きくしても釣り合う）
                .font(JPFont.display(nameSize * fit.ratio, relativeTo: relativeTo))
                // 行の中央ではなく**字面の中央**に置く。ずらす量は印の高さに比例させる
                // （文字サイズの設定で大きくなっても同じ割合でずれを埋める）
                .alignmentGuide(VerticalAlignment.center) { d in
                    d[VerticalAlignment.center] - d.height * fit.nudge
                }
                .foregroundStyle(WebTheme.accentText, WebTheme.accent)
                .accessibilityLabel(L("認証済み", "Verified"))
        }
    }
}
