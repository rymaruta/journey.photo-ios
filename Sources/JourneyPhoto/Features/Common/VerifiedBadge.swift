import SwiftUI

/// 認証済みの印（モック6-2・モック2-1 の名前の横のチェック）。
///
/// **立っている人にだけ出す。** 誰も立てていなければ誰にも出ない
/// ——立てられるのは運営だけで、本人からは立てられない
/// （`api-user/src/userProfile.ts` の更新の経路は受け取らない）。
struct VerifiedBadge: View {

    let isVerified: Bool?

    var body: some View {
        if isVerified == true {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))
                .accessibilityLabel(L("認証済み", "Verified"))
        }
    }
}
