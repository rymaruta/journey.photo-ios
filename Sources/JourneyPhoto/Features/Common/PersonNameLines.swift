import SwiftUI

/// 人の一覧の行の名前（板 34・39・45 で共通）: 1行目に表示名、
/// 2行目に「@ユーザー名」。
///
/// 字は板どおり: 名前 14px・太さ600（`.subheadline.weight(.semibold)`）、
/// @ユーザー名 12px・白60%（`.caption`・`WebTheme.faint`）。
///
/// **行数は板に指定が無い**（折り返しも省略も書いていない）ので、画面ごとに
/// 元の見た目を保つ: 既定は折り返す（フォロー一覧・親しい友達）。ブロックした人は
/// 元から1行で切っていたので `lineLimit: 1` を渡す。
///
/// **2行目は出せる行だけ**（`FollowUser.handle`）。ユーザー名が無い人・
/// 退会した人は名前の1行だけになる。
struct PersonNameLines: View {
    let user: FollowUser
    var lineLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(user.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(lineLimit)
            if let handle = user.handle {
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(lineLimit)
            }
        }
    }
}
