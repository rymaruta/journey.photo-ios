import Foundation

/// 写真に添える**投稿者の名前**。
///
/// 🔴 **同じ写真に2つの名前が出ていた**（run 55 の実機の絵）:
///
///     ホームのカード   luzhj
///     写真の詳細       ユーザー
///
/// 理由は2つ重なっていた:
///
///  1. 詳細は `model.owner?.name`（取ってきたプロフィール）を**先に**見ていた。
///     `UserProfile.name` は名前が無いとき「ユーザー」を返す＝**nil にならない**
///     ので、写真が持っている `displayName` まで降りてこない
///  2. 取れなかったときの言葉が2つあった（ホームは「投稿者」・詳細は「ユーザー」）
///
/// だから**順番を決めて1か所に置く**:
///
///     プロフィールの本当の名前 → 写真に添えられた名前 → 「ユーザー」
///
/// **「ユーザー」は最後だけ。** 代わりの言葉が、本当の名前を追い越さない。
enum AuthorName {

    /// 空白だけの値は「無い」とみなす（サーバーには空文字の行が実在する）
    private static func trimmed(_ value: String?) -> String? {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// プロフィールが持っている**本当の名前**。無ければ nil
    /// （`UserProfile.name` と違い、**代わりの言葉を返さない**）
    static func real(_ profile: UserProfile?) -> String? {
        guard let profile else { return nil }
        return trimmed(profile.displayName) ?? trimmed(profile.username)
    }

    /// 画面に出す名前。
    /// - Parameters:
    ///   - profile: 取れていれば渡す（取れていなければ nil）
    ///   - photoDisplayName: 写真の行に添えられている名前
    static func shown(profile: UserProfile?, photoDisplayName: String?) -> String {
        real(profile) ?? trimmed(photoDisplayName) ?? Labels.Common.unnamedUser
    }

    /// **人のページの見出し**（`UserProfileView`）。
    ///
    /// 写真の詳細と同じ順番だが、写真は1枚ではなく**その人の一覧**から拾う。
    ///
    /// **まだ何も取れていないうちは nil。** 先に「ユーザー」と出してから
    /// 名前に入れ替わると、読み込みの途中が壊れて見える
    static func forProfilePage(profile: UserProfile?, photos: [Photo]) -> String? {
        if let real = real(profile) { return real }
        if let fromPhoto = photos.lazy.compactMap({ trimmed($0.displayName) }).first { return fromPhoto }
        return profile == nil && photos.isEmpty ? nil : Labels.Common.unnamedUser
    }
}
