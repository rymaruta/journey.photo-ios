import SwiftUI

/// 認証済みの印（名前の横の真鍮の封印・アーティファクトの板 08）。
///
/// **立っている人にだけ出す。** 誰も立てていなければ誰にも出ない
/// ——立てられるのは運営だけで、本人からは立てられない
/// （`api-user/src/userProfile.ts` の更新の経路は受け取らない）。
struct VerifiedBadge: View {

    let isVerified: Bool?

    var body: some View {
        if isVerified == true {
            // **真鍮の封印**（板 08・A。2026-09-26 owner が決定）。
            // 2色を渡すと記号は塗り分けになる——1つ目がチェック（墨）、
            // 2つ目が封印（真鍮＝アプリの差し色）。撮影スポットの真鍮の丸とは
            // 形（封印の山）で見分ける
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(WebTheme.accentText, WebTheme.accent)
                .accessibilityLabel(L("認証済み", "Verified"))
        }
    }
}
