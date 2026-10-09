import Foundation

/// **絵を撮るためだけの、鍵を持たないログイン**（Debug のみ・owner 承認済み）。
///
/// CI の巡回は資格情報を持たないので、ログインしないと描かれない画面
/// （マイページ）の絵が1枚も撮れなかった。渡すのは**利用者 ID だけ**で、
/// トークンは1つも作らない。
///
/// **Release では必ず `nil`**（`#if DEBUG`）。TestFlight に上げるビルドは
/// Release なので、出荷物にこの口は無い。
///
/// 綴りを2か所に持たない——`AuthStore`（入るところ）と
/// `MyPageViewModel`（鍵の要らない経路へ逃がすところ）が同じここを読む。
enum PreviewSession {

    /// 起動時の引数・`UserDefaults` の鍵。`ScreenshotTests` が
    /// `-JPPreviewUserId <id>` で渡す。
    static let defaultsKey = "JPPreviewUserId"

    /// 鍵を持たずに入っている利用者 ID。入っていなければ `nil`。
    static var userId: String? {
        #if DEBUG
        let raw = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return nil
        #else
        return nil
        #endif
    }

    /// UI テストで持たせるバッジ（Debug のみ）。`-JPPreviewBadges "prefectures:2,earlyUser:1"`。
    ///
    /// 鍵を持たない入り方では `GET /user/badges` が読めず、見本の利用者が持っているメダルも
    /// 決まらない。メダルを回す全画面の閉じ方（`MedalViewerTests`）を確かめるために、
    /// **入っている本人のプロフィールにだけ**この持ち物を重ねる。Release では必ず `nil`
    static let badgesKey = "JPPreviewBadges"

    static var badges: BadgeSet? {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: badgesKey), !raw.isEmpty else { return nil }
        let items: [EarnedBadge] = raw.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, let tier = Int(parts[1]), tier >= 1 else { return nil }
            return EarnedBadge(key: parts[0], tier: tier, at: "2026-10-01T09:00:00Z")
        }
        return items.isEmpty ? nil : BadgeSet(items)
        #else
        return nil
        #endif
    }

    /// UI テストで名前の横に出すバッジの鍵（Debug のみ）。`-JPPreviewDisplayBadge earlyUser`。
    ///
    /// 見本の利用者は名前の横のバッジを選んでいないので、マイページの名前の横（`NameMarks`）に
    /// バッジが出ない。名前の横の絵（大きいメダルの絵を縮める・2026-10-09）を撮るために、
    /// **入っている本人のプロフィールにだけ**選んだことにする（`badges` に無い鍵は出ない）。
    /// Release では必ず `nil`
    static let displayBadgeKey = "JPPreviewDisplayBadge"

    static var displayBadge: String? {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: displayBadgeKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
        #else
        return nil
        #endif
    }

    /// UI テストで Pro の人の姿にする（Debug のみ）。`-JPPreviewPro YES`。
    ///
    /// 見本の利用者は Pro を買っていないので、名前の横の画面の「PRO 限定」の段が Pro でない人の姿
    /// （鍵・「Pro で集める」）にしかならない。Pro の人の姿（説明の一行・押すと届く時期・2026-10-09）を
    /// 撮るために、**入っている本人のプロフィールにだけ** Pro を重ねる。サーバーの扱いは変わらない
    /// （Pro の口はサーバーが本当の値で断る）。Release では必ず false
    static let proKey = "JPPreviewPro"

    static var isPro: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: proKey)
        #else
        return false
        #endif
    }
}
