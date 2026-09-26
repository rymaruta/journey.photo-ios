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

    /// 名前に対する印の大きさ。記号は字の高さいっぱいに描かれるので、同じ大きさだと
    /// 名前より重く見える。8割で漢字の字面の高さにそろう
    static let ratio = 0.8

    var body: some View {
        if isVerified == true {
            // **真鍮の封印**（板 08・A。2026-09-26 owner が決定）。
            // 2色を渡すと記号は塗り分けになる——1つ目がチェック（墨）、
            // 2つ目が封印（真鍮＝アプリの差し色）。撮影スポットの真鍮の丸とは
            // 形（封印の山）で見分ける
            Image(systemName: "checkmark.seal.fill")
                // 名前と同じ段で拡大縮小させる（文字を大きくしても釣り合う）
                .font(JPFont.display(nameSize * Self.ratio, relativeTo: relativeTo))
                .foregroundStyle(WebTheme.accentText, WebTheme.accent)
                .accessibilityLabel(L("認証済み", "Verified"))
        }
    }
}
