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
}
