import Foundation

/// 画面の文字。**Web と同じく ja / en の2つだけ。**
///
/// Web 側は `app/i18n/labels.ts` の表と、部品の中の
/// `locale === "en" ? … : …` の2本立てになっている。アプリも同じ形にする:
/// 共通の語は下の `Labels`、画面ごとの文は `L(_:_:)`。
///
/// **端末の言語に従う。** Web は自分で切り替えられる（`LocaleProvider`）が、
/// アプリで同じものを作ると「設定が2か所にある」状態になる。
/// iOS は設定アプリで言語を選べるので、そちらに従う。
func L(_ ja: String, _ en: String) -> String {
    Locale.preferredAppLanguage == "en" ? en : ja
}

/// 語をまたいで使う共通の文字。**Web の `labels.ts` から写したもの**
/// ——同じ画面で違う言葉を使わないため。
enum Labels {

    enum Navigation {
        static var gallery: String { L("ギャラリー", "Gallery") }
        static var favorites: String { L("いいねした写真", "Liked Photos") }
        static var map: String { L("撮影地マップ", "Map") }
        static var mypage: String { L("マイページ", "My Page") }
        static var albums: String { L("共同アルバム", "Shared Albums") }
        static var account: String { L("アカウント", "Account") }
        static var upload: String { L("アップロード", "Upload") }
        static var profile: String { L("プロフィール", "Profile") }
        static var login: String { L("ログイン", "Login") }
        static var logout: String { L("ログアウト", "Logout") }
        static var signup: String { L("新規登録", "Sign up") }
    }

    enum Gallery {
        static var empty: String { L("該当する写真がありません。", "No photos found.") }
        static var search: String { L("写真を検索（タイトル・説明・タグなど）", "Search photos") }
    }

    enum Category {
        static var all: String { L("すべて", "All") }

        /// 保存されている分類の語を、画面の言葉にする。
        /// **知らない語はそのまま出す**——消すと分類が無いように見える。
        static func name(_ raw: String) -> String {
            let table: [String: String] = [
                "photography": "写真", "illustration": "イラスト", "design": "デザイン",
                "nature": "自然", "landscape": "風景", "architecture": "建築",
                "street": "街", "people": "人物", "animal": "動物", "food": "食べ物",
            ]
            guard Locale.preferredAppLanguage != "en" else {
                // 英語では保存されている語（英語）をそのまま出す
                return raw
            }
            return table[raw] ?? raw
        }
    }

    enum Common {
        static var close: String { L("閉じる", "Close") }
        static var cancel: String { L("やめる", "Cancel") }
        static var delete: String { L("削除", "Delete") }
        static var save: String { L("保存する", "Save") }
        static var retry: String { L("もう一度試す", "Try again") }
        static var send: String { L("送信", "Send") }
        static var unreachable: String {
            L("通信できませんでした。電波の良いところでもう一度お試しください",
              "Couldn't connect. Please try again with a better signal.")
        }
        static var loadFailed: String { L("読み込めませんでした", "Couldn't load") }
        static var signInRequired: String { L("ログインが必要です", "Please sign in") }
        static var deletedUser: String { L("退会したユーザー", "Deleted user") }

        /// 名前を入れていない人の呼び方。
        ///
        /// 🔴 **利用者 ID を名前として出さない。** ここは長いあいだ
        /// `String(userId.prefix(8))` で、実機の絵（run 51）に
        /// **`d7e4da78`** と人の名前の場所に出ていた。内部の値が漏れて
        /// いるうえ、壊れているようにも見える。
        ///
        /// Web 版も ID は出さない（`app/users/search/page.tsx` などが
        /// 「ユーザー」）。同じ言葉に揃える。
        static var unnamedUser: String { L("ユーザー", "User") }
    }
}

extension Labels {
    /// 英語の月名。年表の見出しで使う（Web 側 `lib/utils/photoDate.ts` と同じ並び）。
    static func monthName(_ month: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        guard (1...12).contains(month) else { return "" }
        return names[month - 1]
    }
}
