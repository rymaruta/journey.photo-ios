import Foundation

/// 写真の題は「素の文字列」か「言語→文字列」のどちらかで保存されている
/// （`api-user/src/types.ts` の `title?: string | Record<string, string>`）。
/// どちらも来るので、読む側で吸収する。
enum LocalizedText: Decodable, Equatable {
    case plain(String)
    case byLocale([String: String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .plain(text)
        } else {
            self = .byLocale(try container.decode([String: String].self))
        }
    }

    /// 表示する1つを選ぶ。
    ///
    /// **空文字でも次の言語に落とす。** Web 側（`lib/data/photos.ts` の
    /// `getLocalized`）が `??` で書かれていた頃、`{ en: "", ja: "..." }` の
    /// 写真で英語表示が空になっていた。
    func resolved(locale: String = Locale.preferredAppLanguage) -> String {
        switch self {
        case .plain(let text):
            return text
        case .byLocale(let map):
            for key in [locale, "ja", "en"] {
                if let value = map[key], !value.isEmpty { return value }
            }
            return ""
        }
    }
}

/// 説明は言語ごとに「段落の配列」で保存されている
/// （`description?: string | Record<string, string[]>`）。
enum LocalizedParagraphs: Decodable, Equatable {
    case plain(String)
    case byLocale([String: [String]])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .plain(text)
            return
        }
        if let map = try? container.decode([String: [String]].self) {
            self = .byLocale(map)
            return
        }
        // **`{ ja: "一行" }` も受ける。** 保存する入口が3つあり、段落に
        // 割っているのは1つだけだった（`lib/data/photos.ts` の経緯）。
        // ここで弾くと、その写真1枚のために一覧全体の復号が落ちる
        let flat = try container.decode([String: String].self)
        self = .byLocale(flat.mapValues { [$0] })
    }

    /// 段落に割って返す。
    ///
    /// **改行はエントリの中に入っていても段落の区切りとして割る。** 保存する
    /// 入口が3つあり、割っているのは1つだけだったため、実データ30枚のうち
    /// 4枚は改行が1エントリに埋まったままになっている
    /// （`lib/data/photos.ts` の `getLocalizedParagraphs` と同じ判断）。
    func resolved(locale: String = Locale.preferredAppLanguage) -> [String] {
        let raw: [String]
        switch self {
        case .plain(let text):
            raw = [text]
        case .byLocale(let map):
            var picked: [String]?
            for key in [locale, "ja", "en"] {
                if let value = map[key], !value.isEmpty { picked = value; break }
            }
            raw = picked ?? []
        }
        return raw
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension Locale {
    /// 画面に出す言語。**日本語で固定。**
    ///
    /// Web は言語切替の UI を廃止して**日本語のみ**になっている
    /// （`app/i18n/context.tsx`——`locale` は常に `"ja"` で、残っていた
    /// `"en"` の記録は見つけ次第消して戻している）。
    ///
    /// アプリだけ端末の言語で英語に切り替わると、**同じ人が同じ写真を
    /// 別の言葉で見る**ことになる（写真の題と説明は言語ごとに保存されて
    /// いるので、中身まで変わる）。Web に揃えて日本語で固定する。
    ///
    /// 英語に戻すときは、**Web と同時に**戻すこと。
    static var preferredAppLanguage: String { "ja" }
}
