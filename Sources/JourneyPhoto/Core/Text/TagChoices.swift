import Foundation

/// タグの**決まった選択肢**。Web 版の `lib/utils/tagChoices.ts` と対。
///
/// owner の指示（2026-09-16）:「タグも出てくる候補は固定化して／
/// 汎用性のないタグは候補にいらない」。以前の候補は「自分が過去に使ったタグ」で、
/// 実データ59種のうち44種が1枚にしか付いておらず、中身は地名と一回きりの名詞
/// ——**次の写真で押す相手ではない**。
///
/// **カテゴリと軸を重ねない。** カテゴリは「何を撮ったか」、こちらは
/// **季節・天気・時間・自然の被写体・場所の種類**。
/// **地名は入れない**（行き先は撮影地欄）。
enum TagChoices {

    /// 20語。**Web の `TAG_CHOICES` と同じ並び**。
    static let all = [
        // 季節・天気・時間
        "春", "夏", "秋", "冬", "雪", "雨", "朝", "夜", "夕焼け",
        // 自然の被写体
        "海", "山", "湖", "川", "森", "空", "花", "桜", "紅葉",
        // 場所の種類
        "神社", "公園",
    ]

    /// 同じ主題を指す綴り（Web の `TAG_ALIASES` ＋ `CATEGORY_ALIASES`）。
    ///
    /// **畳まないと別ページに割れる。** 実データでは `winter` 12枚・
    /// `sunset` 2枚が英語で保存済みで、日本語のチップを押すと同じ主題が
    /// 2つのタグページに分かれる（どちらも3枚に届かず**両方 noindex**）。
    private static let aliases: [String: String] = [
        "春": "spring", "夏": "summer", "秋": "autumn", "冬": "winter",
        "雪": "snow", "雨": "rain", "朝": "morning", "夜": "night", "夕焼け": "sunset",
        "海": "sea", "山": "mountain", "湖": "lake", "川": "river",
        "森": "forest", "空": "sky", "花": "flowers", "桜": "cherry", "紅葉": "autumn-leaves",
        "神社": "shrine", "公園": "park",
        // タグにもカテゴリの表を当てる（Web の `slugify(_, "tag")` と同じ）
        "風景": "landscape", "自然": "nature", "建築": "architecture", "建物": "architecture",
        "街": "street", "人物": "people", "動物": "animal", "食べ物": "food", "ご飯": "food",
        "写真": "photography", "イラスト": "illustration", "デザイン": "design",
    ]

    /// 比較のための鍵（Web の `tagKey`）。**先頭の `#` と大小は無視する。**
    static func key(_ value: String) -> String {
        var base = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while base.hasPrefix("#") { base.removeFirst() }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return aliases[base] ?? base
    }
}
