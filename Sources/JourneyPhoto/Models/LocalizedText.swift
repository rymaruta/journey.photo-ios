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
    /// 画面に出す言語。Web 版は ja / en の2つしか持たないので、それに揃える。
    static var preferredAppLanguage: String {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "ja"
        return code == "en" ? "en" : "ja"
    }
}
