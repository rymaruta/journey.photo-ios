import Foundation

/// プロフィールの初期設定が済んでいるか。
///
/// **Web の `ProfileSetupBanner` と同じ判定。** 登録では
/// メールとパスワードしか受け取っていないので、名前を決めない限り:
///
/// - ユーザー検索に出てこない（`api-user/src/userSearch.ts` は名前で引く）
/// - 他の人からは ID の頭8文字で呼ばれる（`UserProfile.name` の代用）
///
/// **本人には気づきようがない。** 自分の画面では自分が誰か分かるので、
/// こちらから伝えるしかない。
enum ProfileSetup {

    /// 表示名を決めてもらう案内を出すか。
    ///
    /// **username でも良しとする。** 検索も表示もそちらで代用できる
    /// （`UserProfile.name` が同じ順で見ている）。両方とも空のときだけ出す。
    static func needsName(displayName: String?, username: String?) -> Bool {
        isBlank(displayName) && isBlank(username)
    }

    private static func isBlank(_ value: String?) -> Bool {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
