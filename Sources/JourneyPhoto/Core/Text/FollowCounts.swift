import Foundation

/// プロフィールに出る「フォロワー N / フォロー中 N」の数字が、
/// **押して一覧を開ける状態か**。
///
/// 一覧の口（`/users/{uid}/following`・`/users/{uid}/followers`）は
/// **認証が要る**（`api-user/serverless.yml`——人の繋がりそのものであることと、
/// 1回で最大50件の GetItem を撃つため）。それを未ログインでも押せる形に
/// しておくと、押した人は**赤字の「ログインしてください」だけの行き止まり**に
/// 着く。Web は同じ理由で、未ログインのときは数字をただの札として描いている
/// （`app/components/FollowButton.tsx` の `isAuthenticated && countsKnown && followers > 0`）。
///
/// **0人のときも押させない。** 開いても「まだいません」しか無い。
enum FollowCounts {

    static func isTappable(signedIn: Bool, count: Int) -> Bool {
        signedIn && count > 0
    }
}
