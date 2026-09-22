import Foundation

/// カテゴリの**決まった選択肢**。Web 版の `lib/utils/categoryChoices.ts` と対。
///
/// **打つのではなく選ぶ。** owner の指示（2026-09-16）で Web 側が
/// 自由入力からチップへ変わった。アプリだけ自由入力のままだと、
/// 同じ主題が綴り違いで別ページに割れる（`/category/建物` と
/// `/category/architecture`）。集約ページは3枚で検索に載る線なので、
/// 割れると**両方 noindex** になる。
enum CategoryChoices {

    /// 画面に出す7つ。**Web の `CATEGORY_CHOICES` と同じ並び**。
    static let all = ["風景", "建築", "自然", "街", "人物", "動物", "食べ物"]

    /// チップに添える記号（モック3-1・モック9）。
    ///
    /// **持っている分類にだけ付ける。** 知らない語には記号を返さない
    /// ——適当な記号を当てると、分類と絵が食い違ったチップが並ぶ。
    static func symbol(_ value: String) -> String? {
        switch key(value) {
        case key("風景"): return "photo"
        case key("建築"): return "building.columns"
        case key("自然"): return "leaf"
        case key("街"): return "building.2"
        case key("人物"): return "person"
        case key("動物"): return "pawprint"
        case key("食べ物"): return "fork.knife"
        default: return nil
        }
    }

    /// 同じ主題を指す綴り（Web の `CATEGORY_ALIASES`）。
    ///
    /// **選択肢に載せた語はここにも要る。** 載せないと日本語のまま
    /// スラッグになり、英語で保存された既存の写真と別ページに割れる。
    private static let aliases: [String: String] = [
        "風景": "landscape",
        "自然": "nature",
        "建築": "architecture",
        "建物": "architecture",
        "街": "street",
        "人物": "people",
        "動物": "animal",
        "食べ物": "food",
        "ご飯": "food",
        "写真": "photography",
        "イラスト": "illustration",
        "デザイン": "design",
    ]

    /// 比較のための鍵。
    ///
    /// **Web の `slugify(_, "category")` の「比較に要る部分」だけを写す。**
    /// あちらは URL に置けない文字の除去と 200 バイトでの切り詰めもするが、
    /// アプリはパスを組まないので要らない（写すと、写し間違いの面が増える）。
    static func key(_ value: String) -> String {
        let base = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return aliases[base] ?? base
    }

    /// いま入っている値が、その選択肢か。**綴りではなく鍵で見る。**
    static func isChosen(current: String, choice: String) -> Bool {
        let a = key(current)
        guard !a.isEmpty else { return false }
        return a == key(choice)
    }

    /// チップを押したときの新しい値。**押し直すと外れる**
    /// （`FilterBar` と同じ約束。足すだけだと、選び直せない）。
    static func toggle(current: String, choice: String) -> String {
        isChosen(current: current, choice: choice) ? "" : choice
    }

    /// その写真たちに**実際にある**選択肢だけ（`all` の並びのまま）。
    /// 押しても空になるチップを置かないため。探す画面と地図で同じ答えを使う
    static func present(in photos: [Photo]) -> [String] {
        all.filter { choice in
            photos.contains { isChosen(current: $0.category ?? "", choice: choice) }
        }
    }
}
