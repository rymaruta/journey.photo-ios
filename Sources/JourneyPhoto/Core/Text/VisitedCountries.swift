import Foundation

/// 訪れた国・地域（モック2-3）。
///
/// ## なぜ「撮影地の異なり数」ではないのか
///
/// 撮影地は**自由入力の文字列**で、国の欄は無い。異なり数を数えると
/// 「パリ」「パリ, フランス」「オペラ・ガルニエ（パリ）」が3つになり、
/// **国の数とは言えない**。だから、撮影地の中に**国・地域の名前が
/// 書かれているときだけ**数える。
///
/// ## 数えないものは数えない
///
/// 「山中湖」から日本を、「バルセロナ」からスペインを**推測しない**。
/// 地名から国を当てる辞書を持っていないし、当て損なうと
/// **書いていない国が実績として並ぶ**——数えた値だけを出すという
/// 約束（`CLAUDE.md`）を破ることになる。
///
/// 代わりに画面へ「国名が書かれた写真だけを数えている」と添える。
/// 数を増やしたい人は撮影地に国名を足せばよい——それは
/// `/location/*` を厚くする動き（SEO）とも同じ向き。
enum VisitedCountries {

    /// 国・地域の名前（日本語 → 英語）。**書かれていれば当たる**だけの表で、
    /// 地名から国を当てるものではない。
    ///
    /// 並びは実データに出ている国を先に、そのあとは旅先として名前が
    /// 挙がりやすいものを入れてある。**足すのは安全**（当たる語が増える
    /// だけ）だが、**同じ国を2行に書かないこと**（二重に数える）。
    static let table: [(ja: String, en: String)] = [
        ("日本", "japan"), ("フランス", "france"), ("スペイン", "spain"),
        ("ギリシャ", "greece"), ("イタリア", "italy"), ("フィンランド", "finland"),
        ("アイスランド", "iceland"), ("ニュージーランド", "new zealand"),
        ("クロアチア", "croatia"), ("ボリビア", "bolivia"), ("ペルー", "peru"),
        ("アメリカ", "united states"), ("カナダ", "canada"), ("メキシコ", "mexico"),
        ("イギリス", "united kingdom"), ("ドイツ", "germany"), ("スイス", "switzerland"),
        ("オーストリア", "austria"), ("オランダ", "netherlands"), ("ベルギー", "belgium"),
        ("ポルトガル", "portugal"), ("ノルウェー", "norway"), ("スウェーデン", "sweden"),
        ("デンマーク", "denmark"), ("アイルランド", "ireland"), ("ポーランド", "poland"),
        ("チェコ", "czechia"), ("ハンガリー", "hungary"), ("トルコ", "turkey"),
        ("モロッコ", "morocco"), ("エジプト", "egypt"), ("南アフリカ", "south africa"),
        ("ケニア", "kenya"), ("インド", "india"), ("ネパール", "nepal"),
        ("タイ", "thailand"), ("ベトナム", "vietnam"), ("カンボジア", "cambodia"),
        ("インドネシア", "indonesia"), ("マレーシア", "malaysia"),
        ("シンガポール", "singapore"), ("フィリピン", "philippines"),
        ("韓国", "south korea"), ("台湾", "taiwan"), ("中国", "china"),
        ("香港", "hong kong"), ("モンゴル", "mongolia"),
        ("オーストラリア", "australia"), ("フィジー", "fiji"),
        ("ブラジル", "brazil"), ("アルゼンチン", "argentina"), ("チリ", "chile"),
        ("キューバ", "cuba"), ("アラブ首長国連邦", "united arab emirates"),
    ]

    /// 写真に書かれている国・地域。**同じ国は1つ**。
    ///
    /// ⚠️ **見るのは撮影地の文字列だけ。** 以前は台帳（`spot#` 行）の国も
    /// 見ていたが、本番が「台帳を持たない」と決めた
    /// （`photo-gallery/docs/spot-master.md`）ので、引く先が無い。
    static func names(in photos: [Photo]) -> Set<String> {
        var found = Set<String>()
        for photo in photos {
            if let name = country(in: photo.location ?? "") { found.insert(name) }
        }
        return found
    }

    /// その文字列に書かれている国・地域（最初に当たった1つ）。
    ///
    /// **短い名前を先に当てない。** 「中国」は「中国地方」にも当たるが、
    /// 表の並び順ではなく**長い名前から**見ることで、
    /// 「南アフリカ」が「アフリカ」より先に当たるようにする。
    static func country(in text: String) -> String? {
        let folded = fold(text)
        guard !folded.isEmpty else { return nil }
        let sorted = table.sorted { max($0.ja.count, $0.en.count) > max($1.ja.count, $1.en.count) }
        for entry in sorted {
            if folded.contains(entry.ja) || folded.contains(entry.en) { return entry.ja }
        }
        return nil
    }

    /// 数。**0 のときは画面に出さない**（0 の実績は励ましにならない）
    static func count(in photos: [Photo]) -> Int {
        names(in: photos).count
    }

    private static func fold(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "　", with: " ")
    }
}
