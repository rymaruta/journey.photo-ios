import Foundation

/// 人の一覧（フォロー一覧・親しい友達・ブロックした人）の1行に出す名前まわり。
///
/// **@ユーザー名はサーバーが一覧の各行に付けて返す**（2026-09-26 から。
/// `api-user/src/notify.ts` の `lookupListIdentity`）。付かない行がある:
/// - ユーザー名を決めていない人
/// - 退会した人（墓石からは何も返さない）
/// - ブロック一覧の101人目以降（名前を引かない）
///
/// どれも**2行目を出さない**。「@」だけの行や、退会者の昔の名前は出さない。
enum ListIdentity {

    /// 2行目の「@ユーザー名」。出さない行は nil。
    ///
    /// 「@」の付け方と空白の扱いはプロフィールの見出しと同じ
    /// （`ProfileLine.handleAndHome`）——同じ人が画面ごとに違う綴りで出ない
    static func handle(username: String?, deleted: Bool?) -> String? {
        guard deleted != true else { return nil }
        return ProfileLine.handleAndHome(username: username, home: nil)?.handle
    }

    /// 名前で探す（板 39 の「名前で探す」）。**端末の中だけで絞る**
    /// ——並べているのは既に手元にある人（フォロー中＋選んでいる人）だけなので、
    /// サーバーに聞き直す理由が無い。
    ///
    /// 表示名と @ユーザー名のどちらかに含まれれば残す。大文字小文字・全角半角は
    /// 区別しない。頭の「@」は外して読む（「@tabi」と打っても当たる）。
    /// 空の入力は絞らない（並びもそのまま）。
    static func filter(_ users: [FollowUser], query: String) -> [FollowUser] {
        var needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.hasPrefix("@") || needle.hasPrefix("＠") { needle.removeFirst() }
        needle = fold(needle)
        guard !needle.isEmpty else { return users }
        return users.filter { user in
            haystack(user).contains { fold($0).contains(needle) }
        }
    }

    /// 突き合わせる文字。**名前の無い人の代わりの言葉（「旅人」など）は入れない**
    /// ——入れると「旅」で名前の無い人が全員当たる
    private static func haystack(_ user: FollowUser) -> [String] {
        var values: [String] = []
        if user.deleted == true {
            values.append(user.displayName)
        } else {
            if let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                values.append(name)
            }
            if let username = user.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
                values.append(username)
            }
        }
        return values
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}
