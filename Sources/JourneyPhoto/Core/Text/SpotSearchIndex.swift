import Foundation

/// 撮影スポットの一覧の検索窓が引く、**折りたたみ済みの索引**（2026-11-09・owner「撮影スポットを探す一覧に検索窓がほしい」）。
///
/// 通信しない。端末にある索引（`OfficialSpot`）と別名（`OfficialSpotService.fetchAliases`）だけを使う。
///
/// 🔴 **規則の正本は Web**: journey.photo-web の `docs/spot-list-search.md` と `lib/utils/spotListSearch.ts`
/// （ebeb916f・規則 1〜7＋入力→期待の表）。食い違ったらこちらを合わせる。試験は `SpotSearchTests`（表の値を固定）。
///
/// - 折りたたみ（`fold`）: NFKC → 小文字 → カタカナをひらがなへ（ァ〜ヶ・ヽヾ。長音「ー」は残す）→
///   空白・中黒・読点・括弧・ピリオド（. 。）を落とす。`OfficialSpotIndex.spotName`（自動リンクなど他の用途）とは別
/// - 語: 空白・読点で分け、最大 6 語。**先に、続けた1語として名前の欄に当て**、外れたときだけ語ごとに AND
/// - 名前の欄（名前・英語名・読み・別名）: 完全一致 0・前方一致 1・部分一致 2。地域の欄は 3
/// - 地域の欄: 国（日本以外）・県・市区町村・県＋市・全部。語が欄で**始まる**か、**名前として**入っている（`LocationMatch.nameIn`）
/// - 県の読み（ひらがな 2 文字以上）・英語名（3 文字以上）の前方なら、その県の名前を地域の欄に当てる
/// - 行の順位 = 語ごとに当てたときは**いちばん弱い語**。小さい順・同順位は索引の順
///
/// 名前・読み・別名・地域は**最初に1回だけ折りたたんで持つ**（索引・別名が替わったときだけ作り直す・
/// `PhotoMapViewModel.spotSearchHits`）。
struct SpotSearchIndex {

    struct Hit: Equatable {
        let spot: OfficialSpot
        /// 0 完全一致・1 前方一致・2 部分一致・3 地域（語ごとの当たりは、いちばん弱い語）
        let rank: Int
    }

    private struct Entry {
        let spot: OfficialSpot
        /// 名前・英語名・読み・別名（`fold` 済み・空は除く）
        let names: [String]
        /// 国・県・市区町村・県＋市・全部（`fold` 済み・空は除く）
        let regionFields: [String]
    }

    private struct TermInfo {
        let term: String
        let prefNames: [String]
    }

    private let entries: [Entry]

    init(_ spots: [OfficialSpot], aliases: [String: [String]] = [:]) {
        entries = spots.map { spot in
            let raw: [String?] = [spot.name, spot.nameEn, spot.reading] + (aliases[spot.slug] ?? [])
            return Entry(spot: spot,
                         names: raw.map { Self.fold($0) }.filter { !$0.isEmpty },
                         regionFields: Self.regionFields(of: spot))
        }
    }

    var count: Int { entries.count }

    /// 当たったスポット（順位 → 渡された順）。**空の語は何も当てない**（「絞っていない」）
    func hits(query: String, limit: Int? = nil) -> [Hit] {
        let terms = Self.terms(query)
        guard !terms.isEmpty else { return [] }
        let infos = terms.map { TermInfo(term: $0, prefNames: Self.prefectureNames(byReading: $0)) }
        let joined = terms.joined()
        var found: [(hit: Hit, index: Int)] = []
        for (i, entry) in entries.enumerated() {
            let rank = Self.rowRank(entry, infos: infos, joined: joined)
            if rank >= 0 { found.append((hit: Hit(spot: entry.spot, rank: rank), index: i)) }
        }
        found.sort { $0.hit.rank != $1.hit.rank ? $0.hit.rank < $1.hit.rank : $0.index < $1.index }
        let hits = found.map { $0.hit }
        guard let limit else { return hits }
        return Array(hits.prefix(limit))
    }

    // MARK: - 折りたたみ・語

    /// 検索窓の折りたたみ（Web の `foldSpotText`）。濁点・長音・「ヶ／ケ／が」は寄せない
    static func fold(_ value: String?) -> String {
        let nfkc = (value ?? "").precomposedStringWithCompatibilityMapping.lowercased()
        var out = String.UnicodeScalarView()
        for u in nfkc.unicodeScalars {
            if dropped.contains(u) || CharacterSet.whitespacesAndNewlines.contains(u) { continue }
            let v = u.value
            if (0x30A1...0x30F6).contains(v) || v == 0x30FD || v == 0x30FE, let h = Unicode.Scalar(v - 0x60) {
                out.append(h)
            } else {
                out.append(u)
            }
        }
        return String(out)
    }

    /// 落とす字（空白は別に見る）: 中黒・読点・括弧・ピリオド
    private static let dropped: Set<Unicode.Scalar> = Set("・･,、，()（）「」『』.。".unicodeScalars)

    /// 検索に使う最大の語数（長すぎる貼り付けで重くならないように）
    static let maxTerms = 6

    /// 打った語を空白（全角含む）・読点で分けて折りたたんだ語（空は捨てる・最大 6 語）
    static func terms(_ query: String) -> [String] {
        let separators = CharacterSet(charactersIn: "、,，").union(.whitespacesAndNewlines)
        let words = query.precomposedStringWithCompatibilityMapping
            .components(separatedBy: separators)
            .map { fold($0) }
            .filter { !$0.isEmpty }
        return Array(words.prefix(maxTerms))
    }

    // MARK: - 当たり

    /// 名前の欄の順位（完全 0・前方 1・部分 2・外れ -1）。`names` は `fold` 済み
    static func nameRank(_ names: [String], _ term: String) -> Int {
        var rank = -1
        for name in names {
            if name == term { return 0 }
            if name.hasPrefix(term) { rank = 1; continue }
            if name.contains(term), rank < 0 { rank = 2 }
        }
        return rank
    }

    private static func rowRank(_ entry: Entry, infos: [TermInfo], joined: String) -> Int {
        // 先に、続けた1語として名前の欄に当てる（当たればその順位で確定）
        if infos.count > 1 {
            let whole = nameRank(entry.names, joined)
            if whole >= 0 { return whole }
        }
        var worst = 0
        for info in infos {
            var r = nameRank(entry.names, info.term)
            if r < 0 {
                let byRegion = regionHit(fields: entry.regionFields, word: info.term)
                    || info.prefNames.contains(where: { regionHit(fields: entry.regionFields, word: $0) })
                if byRegion { r = 3 }
            }
            if r < 0 { return -1 }
            worst = max(worst, r)
        }
        return worst
    }

    // MARK: - 地域

    /// 国（日本以外）・県・市区町村・県＋市・全部をつないだ字（`fold` 済み・空は除く）。地域の無い行は空
    static func regionFields(of spot: OfficialSpot) -> [String] {
        guard let r = spot.region else { return [] }
        let country = r.country == "日本" ? nil : r.country
        let pair: String = [r.prefecture, r.city].compactMap { $0 }.joined()
        let whole: String = [country, r.prefecture, r.city].compactMap { $0 }.joined()
        let raw: [String?] = [country, r.prefecture, r.city, pair, whole]
        return raw.map { fold($0) }.filter { !$0.isEmpty }
    }

    /// 1語（`fold` 済み）が地域の欄に当たるか: 欄が語で**始まる**、または欄の中に**名前として**入っている
    static func regionHit(fields: [String], word: String) -> Bool {
        !word.isEmpty && fields.contains { $0.hasPrefix(word) || LocationMatch.nameIn($0, word, boundaries: regionMarks) }
    }

    /// 地域だけで当たるか（`OfficialSpotIndex.regionMatches` の本体）。空白で区切った語は**どの語もどれかの欄に**当たること。
    /// 区切らずに続けた「東京都千代田区」は県＋市をつないだ字に当てる
    static func regionMatches(fields: [String], query: String) -> Bool {
        guard !fields.isEmpty else { return false }
        let words = terms(query)
        if words.count > 1, words.allSatisfy({ regionHit(fields: fields, word: $0) }) { return true }
        return regionHit(fields: fields, word: fold(query))
    }

    /// 海外の地域名の切れ目（「アンダルシア州」「ブルターニュ地方」）
    private static let regionMarks = ["州", "地方"]

    // MARK: - 県の読み・英語名

    /// 読み（かな）の前方一致に使う最小の字数
    static let prefectureReadingMin = 2
    /// 英語名（ローマ字）の前方一致に使う最小の字数。「to」で Tokyo・Tottori・Toyama… を全部引かない
    static let prefectureLatinMin = 3

    /// 県の名前・英語名・読み（Web の `PREFECTURES` / `PREFECTURE_READING`・`RegionList.prefectures` と同じ並び）
    private static let prefectureRows: [(String, String, String)] = [
        ("北海道", "Hokkaido", "ほっかいどう"), ("青森県", "Aomori", "あおもり"), ("岩手県", "Iwate", "いわて"),
        ("宮城県", "Miyagi", "みやぎ"), ("秋田県", "Akita", "あきた"), ("山形県", "Yamagata", "やまがた"),
        ("福島県", "Fukushima", "ふくしま"), ("茨城県", "Ibaraki", "いばらき"), ("栃木県", "Tochigi", "とちぎ"),
        ("群馬県", "Gunma", "ぐんま"), ("埼玉県", "Saitama", "さいたま"), ("千葉県", "Chiba", "ちば"),
        ("東京都", "Tokyo", "とうきょう"), ("神奈川県", "Kanagawa", "かながわ"), ("新潟県", "Niigata", "にいがた"),
        ("富山県", "Toyama", "とやま"), ("石川県", "Ishikawa", "いしかわ"), ("福井県", "Fukui", "ふくい"),
        ("山梨県", "Yamanashi", "やまなし"), ("長野県", "Nagano", "ながの"), ("岐阜県", "Gifu", "ぎふ"),
        ("静岡県", "Shizuoka", "しずおか"), ("愛知県", "Aichi", "あいち"), ("三重県", "Mie", "みえ"),
        ("滋賀県", "Shiga", "しが"), ("京都府", "Kyoto", "きょうと"), ("大阪府", "Osaka", "おおさか"),
        ("兵庫県", "Hyogo", "ひょうご"), ("奈良県", "Nara", "なら"), ("和歌山県", "Wakayama", "わかやま"),
        ("鳥取県", "Tottori", "とっとり"), ("島根県", "Shimane", "しまね"), ("岡山県", "Okayama", "おかやま"),
        ("広島県", "Hiroshima", "ひろしま"), ("山口県", "Yamaguchi", "やまぐち"), ("徳島県", "Tokushima", "とくしま"),
        ("香川県", "Kagawa", "かがわ"), ("愛媛県", "Ehime", "えひめ"), ("高知県", "Kochi", "こうち"),
        ("福岡県", "Fukuoka", "ふくおか"), ("佐賀県", "Saga", "さが"), ("長崎県", "Nagasaki", "ながさき"),
        ("熊本県", "Kumamoto", "くまもと"), ("大分県", "Oita", "おおいた"), ("宮崎県", "Miyazaki", "みやざき"),
        ("鹿児島県", "Kagoshima", "かごしま"), ("沖縄県", "Okinawa", "おきなわ"),
    ]

    /// `fold` 済みの県の表（1回だけ作る）
    private static let prefectureTable: [(name: String, en: String, reading: String)] =
        prefectureRows.map { (name: fold($0.0), en: fold($0.1), reading: fold($0.2)) }

    /// 語が県の読み（かな 2 文字以上）か英語名（3 文字以上）の前方なら、その県の名前（`fold` 済み）。**語ごとに1回**
    static func prefectureNames(byReading term: String) -> [String] {
        let latin = term.unicodeScalars.allSatisfy { $0.isASCII }
        if latin ? term.count < prefectureLatinMin : term.count < prefectureReadingMin { return [] }
        return prefectureTable
            .filter { latin ? $0.en.hasPrefix(term) : $0.reading.hasPrefix(term) }
            .map { $0.name }
    }
}
