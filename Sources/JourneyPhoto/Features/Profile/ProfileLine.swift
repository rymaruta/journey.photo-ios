import Foundation

/// プロフィールの見出しの下に並べる文字（板 05c・05d）。
enum ProfileLine {

    /// 「@ユーザー名 · 居住地」の1行（板: 12px・白60%）。片方だけならその片方、
    /// どちらも無ければ出さない。
    ///
    /// **居住地の頭のピンは線の印**（板: 11px の線のピン）で、画面側で描く。
    /// 以前は絵文字の「📍」を文字に混ぜていて、板と違う赤いピンが出ていた
    struct HandleAndHome: Equatable {
        let handle: String?
        let home: String?

        /// 読み上げ。印は読まれないので「居住地」と言葉で添える
        var spoken: String {
            [handle, home.map { L("居住地 \($0)", "Lives in \($0)") }]
                .compactMap { $0 }
                .joined(separator: L("、", ", "))
        }
    }

    static func handleAndHome(username: String?, home: String?) -> HandleAndHome? {
        let handle = username.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : "@\($0)" }
        let place = home.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        guard handle != nil || place != nil else { return nil }
        return HandleAndHome(handle: handle, home: place)
    }

    /// 人のページの数の並び（板 31: 「000 フォロワー　000 フォロー中　000 写真」）。
    /// **数が先・名前が後**の1行で、マイページ（板 05c: 数の下に名前の3列）とは別の形。
    /// 押して一覧を開けるかは画面が決める（`FollowCounts.isTappable`）
    struct Count: Equatable, Identifiable {
        enum Kind: Equatable { case followers, following, photos }
        let kind: Kind
        let value: String
        let label: String
        var id: Kind { kind }
    }

    /// 写真の数の状態。**読み終えるまで数を言わない**——写真は読み込みの最後に
    /// 取り、取れなくても画面は出すので、配列の長さをそのまま出すと
    /// 読み込み中・失敗のあいだ「0 写真」と嘘をつく
    enum PhotoCount: Equatable {
        /// 読み込み中（ブロックして一覧を伏せたときも）。**札ごと出さない**
        case pending
        /// 取れなかった。「—」を出す（0 とは言わない）
        case failed
        case loaded(Int)

        /// 画面に並べている枚数で言い直す。**数えるのは絞ったあと**
        /// ——ブロック・通報した写真を格子から落としても、札が落とす前の
        /// 枚数のままだった。読み込み中・失敗はそのまま
        func shown(_ count: Int) -> PhotoCount {
            if case .loaded = self { return .loaded(count) }
            return self
        }
    }

    /// マイページの3列（板 05c）の数の字。**人のページの `PhotoCount` と同じ決まり**——
    /// 読み込み中は出さない（nil）・取れなければ「—」。0 と言うのは数を読めたときだけ
    /// （以前は読み込み中・失敗のあいだ「0」と出ていた）
    static func statValue(_ count: PhotoCount) -> String? {
        switch count {
        case .pending: return nil
        case .failed: return "—"
        case .loaded(let n): return "\(n)"
        }
    }

    /// **3つとも `PhotoCount` の決まり**——読み込み中は札ごと出さず、取れなければ「—」。
    /// フォロー数も以前は読み込み中・失敗のあいだ「0」と出ていた（マイページの `statValue` と同じ）
    static func counts(followers: PhotoCount, following: PhotoCount, photos: PhotoCount) -> [Count] {
        var items: [Count] = []
        if let value = statValue(followers) {
            items.append(Count(kind: .followers, value: value,
                               label: L("フォロワー", followers == .loaded(1) ? "follower" : "followers")))
        }
        if let value = statValue(following) {
            items.append(Count(kind: .following, value: value, label: L("フォロー中", "following")))
        }
        if let value = statValue(photos) {
            items.append(Count(kind: .photos, value: value,
                               label: L("写真", photos == .loaded(1) ? "photo" : "photos")))
        }
        return items
    }

    /// 人のページでフォロー・一覧の丸・ハイライト・ブロックを出すか。
    /// **ログインしていて、自分でなく、ブロック中でない**とき。ブロック中の相手に
    /// 「フォローする」を出すと、押してもサーバーに断られる
    static func canAct(viewerId: String?, userId: String, blocked: Set<String>) -> Bool {
        guard let viewerId else { return false }
        return viewerId != userId && !blocked.contains(userId)
    }

    /// ハイライトの列を作り直す鍵。**見られるかはフォローの状態で変わる**
    /// （本人とフォロワーだけ）ので、フォローを変えたら読み直す。
    /// `HighlightsRow` は `userId` が変わったときしか読み直さない
    static func highlightsKey(userId: String, isFollowing: Bool) -> String {
        "\(userId)|\(isFollowing ? "following" : "not-following")"
    }

    /// ひとことと自己紹介（板は「ひとことプロフィール」の1段落）。**空は出さない・
    /// 同じ文は二度出さない**（Web で両方に同じ文を入れている人がいる）
    static func about(status: String?, bio: String?) -> [String] {
        var lines: [String] = []
        for text in [status, bio] {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty, !lines.contains(trimmed) else { continue }
            lines.append(trimmed)
        }
        return lines
    }

    /// 格子の1枚の状態の読み上げ（ピン・下書き・複数枚）。**印は絵では見えるが
    /// 読まれないので、値として読む**
    static func gridState(pinned: Bool, draft: Bool, multiple: Bool) -> String {
        [pinned ? L("ピン留め中", "Pinned") : nil,
         draft ? L("下書き", "Draft") : nil,
         multiple ? L("複数枚の投稿", "Multiple photos") : nil]
            .compactMap { $0 }
            .joined(separator: L("、", ", "))
    }
}
