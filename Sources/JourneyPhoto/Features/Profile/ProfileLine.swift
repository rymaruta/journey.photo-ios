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

    static func counts(followers: Int, following: Int, photos: Int) -> [Count] {
        [Count(kind: .followers, value: "\(followers)",
               label: L("フォロワー", followers == 1 ? "follower" : "followers")),
         Count(kind: .following, value: "\(following)", label: L("フォロー中", "following")),
         Count(kind: .photos, value: "\(photos)",
               label: L("写真", photos == 1 ? "photo" : "photos"))]
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
