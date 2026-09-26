import SwiftUI

/// 人の一覧の行の名前（板 34・39・45 で共通）: 1行目に表示名（14pt・太字）、
/// 2行目に「@ユーザー名」（12pt・白60%）。
///
/// **2行目は出せる行だけ**（`FollowUser.handle`）。ユーザー名が無い人・
/// 退会した人は名前の1行だけになる。
struct PersonNameLines: View {
    let user: FollowUser

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(user.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let handle = user.handle {
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(1)
            }
        }
    }
}
