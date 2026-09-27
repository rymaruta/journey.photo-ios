import Foundation

/// 招待リンクからトークンを取り出す。
///
/// **`@MainActor` の型に置かない**（`TagInput` と同じ理由）。テストから
/// 呼べなくなる。
enum InviteLink {

    /// `https://…/j?t=<トークン>` からトークンを取り出す。
    /// URL でなければ、打たれた文字列そのものをトークンとみなす。
    ///
    /// **リンクをそのまま貼れるようにする。** 受け取った人に `?t=` の後ろだけを
    /// 取り出す作業をさせない（URL を貼って弾かれるのがいちばん多い失敗）。
    /// トークンを持たない URL は空を返す——URL 全体を送ると、サーバーに
    /// 無意味な問い合わせが飛ぶ。
    static func token(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return trimmed }
        if let value = components.queryItems?.first(where: { $0.name == "t" })?.value {
            return value
        }
        return components.scheme == nil ? trimmed : ""
    }
}

extension InviteLink {

    /// 招待リンクの期限から見た、いまの扱い。
    enum Expiry: Equatable {
        /// まだ使える。`until` は期限（画面に「〜まで」と出す）
        case valid(until: Date)
        /// 🔴 **期限が切れている。** サーバーは切れた招待も一覧に返し続ける
        /// （`api-user/src/albums.ts` の `listAlbums`）が、開くと 410 で断る
        /// （`invite.ts` の `inviteState`）。共有させず、作り直させる
        case expired
        /// 期限を持たない・読めない。**切れたとは言い切らない**——Web も期限が
        /// 無ければ「〜まで」を出さずにリンクだけ見せる
        case unknown
    }

    /// 期限（ISO8601）といまを比べる。境目はサーバーと同じ——**期限ちょうどは切れている**
    /// （`inviteState` は `exp > now` のときだけ `ok`）。
    ///
    /// 読み方は通知の見出しと同じ（`NotificationGroups.parse`・小数秒の有無どちらでも読む）
    static func expiry(_ raw: String?, now: Date) -> Expiry {
        guard let raw, let date = NotificationGroups.parse(raw) else { return .unknown }
        return date > now ? .valid(until: date) : .expired
    }

    /// 「〜まで」の日付。Web の `toLocaleDateString("ja-JP")` と同じ形（`2026/10/4`）。
    /// **端末のゾーンのその日**で出す
    static func untilLabel(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 招待リンクの操作が通ったときの一言。**Web の知らせと同じ文**（`app/user/albums`）。
    /// 作り直しは「前のリンクは使えなくなる」まで言う——配ったリンクが黙って切れないように
    enum Done { case created, recreated, revoked }

    static func doneMessage(_ done: Done) -> String {
        switch done {
        case .created:
            return L("招待リンクを作りました", "Invite link created")
        case .recreated:
            return L("招待リンクを作りました。前のリンクは使えなくなります",
                     "Invite link recreated. The previous link no longer works")
        case .revoked:
            return L("招待リンクを取り消しました", "Invite link revoked")
        }
    }
}
