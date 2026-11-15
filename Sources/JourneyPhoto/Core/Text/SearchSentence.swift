import Foundation

/// 探すの「**自然な文で探す**」（札 #623 の案2・2026-11-15 判断）。
///
/// 「京都 紅葉 夜」のような文を、**今ある絞り込み**に置き換える:
///
///  - 季節（春 夏 秋 冬）と時間帯（朝 日中 夕 夜）は、探すの季節と時間帯のチップ（`ShootingTime.Filter`）に
///  - 地名や探したいもの（「京都」「海」）は、今の字の検索の語（`SearchScope.photos` が1語で当てる）に
///
/// **新しい条件は作らない。** 端末の AI（`SearchSentenceReader`）でも、言葉の表（`readByTable`）でも、
/// 出てくるのはこの型（`Reading`）だけ。字の語は**打った文の中の字だけ**（`normalized` が文に無い語を落とす）。
///
/// 観光スポットの情報に欄が無い条件（「雨」「屋内」など・`Unsupported`）は、読めても絞らない。
/// そのことを1行で言う（`note`）。
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる（`SearchSentenceTests`）。
enum SearchSentence {

    // MARK: - 読み取った結果

    /// 文をどう読んだか。**探すの画面はこれを今の絞り込みに入れるだけ**
    struct Reading: Equatable {
        /// 打った文（最近の検索に覚えるのはこちら）
        var sentence: String
        /// 字で探す語（今の検索欄に入れる1語）。無ければ字では絞らない
        var text: String?
        var season: ShootingTime.Season?
        var dayPart: ShootingTime.DayPart?
        /// 観光スポットの情報に欄の無い条件（絞らない・`note` で言う）
        var unsupported: [Unsupported] = []
        /// 字で探さなかった語（字の検索は1語だけなので、2つ目からは使わない・`note` で言う）
        var unused: [String] = []

        /// 季節・時間帯・欄の無い条件のどれかを読めた＝**文として読んだ**。
        /// 語だけの文（「京都」「富士山 湖」「New York」「zzzz-no-photo-result」）は今の字の検索のまま
        /// （欄の字を書き換えない）
        var changesSearch: Bool {
            season != nil || dayPart != nil || !unsupported.isEmpty
        }

        /// 画面に出す1行（欄の無い条件 → 使わなかった語の順に、1つだけ）。無ければ nil
        var note: String? {
            if !unsupported.isEmpty {
                let names = unsupported.map(\.phrase).joined(separator: L("、", ", "))
                return L("\(names)は観光スポットの情報に無いので、絞らずに探しました",
                         "\(names) isn't in the spot information, so it wasn't used to narrow the search")
            }
            if !unused.isEmpty {
                let words = unused.map { L("「\($0)」", "\"\($0)\"") }.joined(separator: L("", ", "))
                return L("\(words)は字では探していません。1語ずつ探せます",
                         "\(words) wasn't searched. Try one word at a time")
            }
            return nil
        }
    }

    /// 観光スポットの情報（台帳）に欄が無い条件。**読めても絞らない**（2026-11-15 判断・札 #623）
    enum Unsupported: String, CaseIterable, Equatable {
        case rain, indoor, crowd, free, parking, station

        /// 1行の頭（「雨の日に向くかは…」）
        var phrase: String {
            switch self {
            case .rain: return L("雨の日に向くか", "Whether it suits rainy days")
            case .indoor: return L("屋内かどうか", "Whether it's indoors")
            case .crowd: return L("混み具合", "How crowded it is")
            case .free: return L("料金", "Admission fees")
            case .parking: return L("駐車場", "Parking")
            case .station: return L("駅からの近さ", "Distance from a station")
            }
        }

        /// 端末の AI に選ばせる語（`SearchSentenceDraft.unsupported` の選択肢）
        var choice: String {
            switch self {
            case .rain: return "雨"
            case .indoor: return "屋内"
            case .crowd: return "混み具合"
            case .free: return "料金"
            case .parking: return "駐車場"
            case .station: return "駅から近い"
            }
        }

        static func of(choice: String) -> Unsupported? {
            allCases.first { $0.choice == choice }
        }
    }

    // MARK: - 文として読むか

    /// 文として読むか（端末の AI に聞くか）。**1語だけの語（「京都」「富士山」「@ka_trip」）は聞かない**
    /// ——今の字の検索のまま、待たせない。空白で区切った文か、表の言葉を含むか、
    /// 漢字・片仮名とひらがなが混ざる文（「静岡で夕日の海」）だけ
    static func looksLikeSentence(_ raw: String) -> Bool {
        let text = fold(raw)
        guard text.count >= 2, !text.hasPrefix("@") else { return false }
        if text.contains(where: { $0.isWhitespace }) { return true }
        if readByTable(text).changesSearch { return true }
        let hasHiragana = text.unicodeScalars.contains { isHiragana($0) }
        let hasOther = text.unicodeScalars.contains { isKanji($0) || isKatakana($0) }
        return hasHiragana && hasOther
    }

    // MARK: - 言葉の表（端末の AI が使えない機種・AI が読み落とした言葉）

    /// 季節の言葉。**長い言葉から当てる**（「夜桜」を「夜」より先に）。2026-11-15 判断: 撮影の季節が
    /// 一つに決まる言葉だけ（「梅」は冬の終わりと春にまたがるので入れない）
    static let seasonWords: [(word: String, season: ShootingTime.Season)] = [
        ("春", .spring), ("桜", .spring), ("さくら", .spring), ("サクラ", .spring), ("花見", .spring),
        ("お花見", .spring), ("菜の花", .spring), ("ネモフィラ", .spring), ("新緑", .spring), ("藤の花", .spring),
        ("つつじ", .spring), ("チューリップ", .spring), ("芝桜", .spring), ("夜桜", .spring),
        ("夏", .summer), ("ひまわり", .summer), ("向日葵", .summer), ("花火", .summer), ("海水浴", .summer),
        ("ラベンダー", .summer), ("紫陽花", .summer), ("あじさい", .summer), ("アジサイ", .summer),
        ("蛍", .summer), ("ホタル", .summer), ("ほたる", .summer),
        ("秋", .autumn), ("紅葉", .autumn), ("もみじ", .autumn), ("モミジ", .autumn), ("紅葉狩り", .autumn),
        ("黄葉", .autumn), ("銀杏並木", .autumn), ("イチョウ", .autumn), ("いちょう", .autumn),
        ("彼岸花", .autumn), ("コスモス", .autumn), ("ススキ", .autumn), ("すすき", .autumn),
        ("冬", .winter), ("雪", .winter), ("雪景色", .winter), ("樹氷", .winter), ("流氷", .winter),
        ("霧氷", .winter), ("雪まつり", .winter), ("雪見", .winter),
    ]

    /// 時間帯の言葉（4つの区切りは `ShootingTime.DayPart`・朝 5〜9時 日中 10〜15時 夕 16〜18時 夜 19〜4時）。
    /// 「夜明け」は朝（「夜」より長いので先に当たる）
    static let dayPartWords: [(word: String, dayPart: ShootingTime.DayPart)] = [
        ("朝", .morning), ("早朝", .morning), ("朝日", .morning), ("朝焼け", .morning), ("日の出", .morning),
        ("夜明け", .morning), ("明け方", .morning), ("雲海", .morning), ("朝霧", .morning),
        ("昼", .day), ("日中", .day), ("昼間", .day), ("お昼", .day), ("青空", .day),
        ("夕", .evening), ("夕方", .evening), ("夕日", .evening), ("夕陽", .evening), ("夕焼け", .evening),
        ("夕暮れ", .evening), ("日没", .evening), ("日の入り", .evening), ("黄昏", .evening),
        ("マジックアワー", .evening), ("サンセット", .evening),
        ("夜", .night), ("夜景", .night), ("ライトアップ", .night), ("星空", .night), ("星", .night),
        ("天の川", .night), ("イルミネーション", .night), ("夜桜", .night), ("花火", .night), ("蛍", .night),
        ("ホタル", .night), ("ほたる", .night), ("満月", .night), ("月夜", .night),
    ]

    /// 欄の無い条件の言葉
    static let unsupportedWords: [(word: String, unsupported: Unsupported)] = [
        ("雨", .rain), ("雨の日", .rain), ("雨でも", .rain),
        ("屋内", .indoor), ("室内", .indoor),
        ("空いて", .crowd), ("混雑", .crowd), ("人が少な", .crowd), ("人の少な", .crowd), ("穴場", .crowd),
        ("混んで", .crowd),
        ("無料", .free), ("タダ", .free),
        ("駐車場", .parking),
        ("駅近", .station), ("駅から近", .station), ("駅チカ", .station),
    ]

    /// 字の語にしない言葉（探す文によく入るが、写真の題・撮影地には当てたくない語）
    static let fillerWords: Set<String> = [
        "写真", "撮影", "場所", "所", "スポット", "観光", "観光地", "観光スポット", "名所", "絶景", "景色",
        "綺麗", "奇麗", "素敵", "最高", "人気", "有名", "近く", "周辺", "辺り", "季節", "時期", "時間", "時間帯",
        "旅", "旅行", "見頃", "映え", "撮", "見", "行", "探", "向", "好", "多", "少", "静", "楽", "良",
        "日", "頃", "撮れる", "見れる", "行ける", "撮り", "見たい", "行きたい", "インスタ", "写真映え", "穴場",
    ]

    /// 1文字でも字の語にしてよい名詞（「海」「山」…）。ほかの1文字は動詞のかけらなので落とす
    static let singleCharacterNouns: Set<Character> = [
        "海", "山", "川", "湖", "滝", "城", "寺", "森", "島", "橋", "港", "駅", "庭", "塔", "空", "花", "岬",
        "浜", "沼", "池", "谷", "崖", "宮", "社", "街", "町", "村", "道", "坂", "岳", "峠", "浦", "湾",
    ]

    /// 表で読む。**長い言葉から当て、当てた所は使い切る**（「夜明け」が「夜」にも当たらないように）。
    /// 季節・時間帯が文の中に2つあれば、先に書いた方
    static func readByTable(_ raw: String) -> Reading {
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(fold(sentence))
        var used = [Bool](repeating: false, count: chars.count)
        var seasons: [(Int, ShootingTime.Season)] = []
        var parts: [(Int, ShootingTime.DayPart)] = []
        var unsupported: [(Int, Unsupported)] = []

        enum Hit { case season(ShootingTime.Season), part(ShootingTime.DayPart), unsupported(Unsupported) }
        var terms: [(word: [Character], hit: [Hit])] = []
        func add(_ word: String, _ hit: Hit) {
            let w = Array(fold(word))
            if let i = terms.firstIndex(where: { $0.word == w }) { terms[i].hit.append(hit) } else { terms.append((w, [hit])) }
        }
        for (w, s) in seasonWords { add(w, .season(s)) }
        for (w, p) in dayPartWords { add(w, .part(p)) }
        for (w, u) in unsupportedWords { add(w, .unsupported(u)) }
        terms.sort { $0.word.count > $1.word.count }

        for term in terms where !term.word.isEmpty && chars.count >= term.word.count {
            var i = 0
            while i + term.word.count <= chars.count {
                let range = i..<(i + term.word.count)
                if !used[range].contains(true), Array(chars[range]) == term.word {
                    for j in range { used[j] = true }
                    for hit in term.hit {
                        switch hit {
                        case .season(let s): seasons.append((i, s))
                        case .part(let p): parts.append((i, p))
                        case .unsupported(let u): unsupported.append((i, u))
                        }
                    }
                    i += term.word.count
                } else {
                    i += 1
                }
            }
        }

        // 残りの字を語に切る（空白・句読点・ひらがなの続き・使った所で切る）
        var words: [String] = []
        var current = ""
        for (index, ch) in chars.enumerated() {
            let breaks = used[index] || ch.isWhitespace || ch.isPunctuation || ch.isSymbol
                || ch.unicodeScalars.allSatisfy(isHiragana)
            if breaks {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        let keywords = words.filter(isKeyword)

        var reading = Reading(sentence: sentence)
        reading.season = seasons.min { $0.0 < $1.0 }?.1
        reading.dayPart = parts.min { $0.0 < $1.0 }?.1
        reading.unsupported = unique(unsupported.sorted { $0.0 < $1.0 }.map(\.1))
        let (text, unused) = pickText(keywords)
        reading.text = text
        reading.unused = unused
        return reading
    }

    // MARK: - 端末の AI の答えをそろえる

    /// 端末の AI の答え（`SearchSentenceDraft` の値そのまま）。画面を持たない層で確かめられるよう、ここは字だけ
    struct Draft: Equatable {
        var season: String
        var dayPart: String
        var place: String
        var keyword: String
        var unsupported: [String]

        init(season: String = "なし", dayPart: String = "なし", place: String = "なし",
             keyword: String = "なし", unsupported: [String] = []) {
            self.season = season
            self.dayPart = dayPart
            self.place = place
            self.keyword = keyword
            self.unsupported = unsupported
        }
    }

    /// AI に選ばせる季節の字（`@Guide(.anyOf)`）。「なし」は書かれていないとき
    static let seasonChoices = ["なし", "春", "夏", "秋", "冬"]
    /// AI に選ばせる時間帯の字。チップの字（`DayPart.label`）ではなく言い方（「夕方」）で聞く
    static let dayPartChoices = ["なし", "朝", "日中", "夕方", "夜"]
    static var unsupportedChoices: [String] { Unsupported.allCases.map(\.choice) }

    /// AI の答えを型に入れる。**選択肢に無い値・文に無い語は落とす**（新しい条件を作らせない）。
    ///
    /// 2026-11-15 判断: 表で読める言葉（「紅葉」「夜」）は**表を先に**使う——はっきり書かれた言葉は表のほうが確か。
    /// AI は表に無い言い方（「日が沈む頃」「もみじ狩り」）を埋める。表と AI が食い違えば表
    static func normalized(_ draft: Draft, sentence raw: String) -> Reading {
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let table = readByTable(sentence)
        var reading = Reading(sentence: sentence)
        reading.season = table.season ?? season(choice: draft.season)
        reading.dayPart = table.dayPart ?? dayPart(choice: draft.dayPart)
        reading.unsupported = unique(table.unsupported + draft.unsupported.compactMap(Unsupported.of(choice:)))

        // 字の語は文の中にある字だけ（AI が文に無い地名を足しても使わない）。
        // 地名 → 探したいもの → 表の残りの語の順に並べ、1つ目を字の語に
        let haystack = fold(sentence)
        let fromAI = [draft.place, draft.keyword]
            .map { fold($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "なし" && haystack.contains($0) && isKeyword($0) && !isConditionWord($0) }
        var keywords: [String] = []
        for word in fromAI + [table.text].compactMap({ $0 }) + table.unused
        where !keywords.contains(where: { $0.contains(word) || word.contains($0) }) {
            keywords.append(word)
        }
        let (text, unused) = pickText(keywords)
        reading.text = text
        reading.unused = unused
        return reading
    }

    static func season(choice: String) -> ShootingTime.Season? {
        switch choice {
        case "春": return .spring
        case "夏": return .summer
        case "秋": return .autumn
        case "冬": return .winter
        default: return nil
        }
    }

    static func dayPart(choice: String) -> ShootingTime.DayPart? {
        switch choice {
        case "朝": return .morning
        case "日中": return .day
        case "夕方": return .evening
        case "夜": return .night
        default: return nil
        }
    }

    // MARK: - 端末の AI に渡す文

    /// 端末の AI への決まり（短く・選ぶだけ。結果は作らせない）
    static let instructions = """
    あなたは写真と観光スポットを探すアプリの、検索の文を読み取る係です。
    利用者が打った文から、季節、時間帯、地名、探したいもの、絞れない条件を選んで答えます。
    文に書かれていないことは足さず、「なし」と答えます。地名と探したいものは、文に書かれた字のまま答えます。
    """

    static func prompt(_ sentence: String) -> String {
        "検索の文: \(sentence)"
    }
}

extension SearchSentence {

    /// 字の語を1つ選ぶ。**都道府県・地名を先に**（字の検索は1語なので、「静岡 海」なら「静岡」）。
    /// 残りは使わなかった語として返す
    static func pickText(_ keywords: [String]) -> (String?, [String]) {
        guard !keywords.isEmpty else { return (nil, []) }
        let placeIndex = keywords.firstIndex { RegionList.prefecture(named: $0) != nil || RegionList.prefectures.contains($0) }
        let index = placeIndex ?? 0
        var rest = keywords
        let text = rest.remove(at: index)
        return (text, rest)
    }

    static func isKeyword(_ word: String) -> Bool {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !fillerWords.contains(w) else { return false }
        if w.count == 1 { return w.first.map(singleCharacterNouns.contains) ?? false }
        // ひらがなだけの語は助詞・言い回し（「きれいな」）として落とす
        return !w.unicodeScalars.allSatisfy(isHiragana)
    }

    /// 表の季節・時間帯・欄の無い条件の言葉そのものか（AI が「紅葉」を地名として返したときに落とす）
    static func isConditionWord(_ word: String) -> Bool {
        let w = fold(word)
        return seasonWords.contains { fold($0.word) == w } || dayPartWords.contains { fold($0.word) == w }
            || unsupportedWords.contains { fold($0.word) == w }
    }

    /// 全角半角・大文字小文字をそろえる（`PhotoQuery.match` と同じ畳み方。全角の空白も半角に）
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{3000}", with: " ")
    }

    static func unique<T: Equatable>(_ items: [T]) -> [T] {
        var out: [T] = []
        for item in items where !out.contains(item) { out.append(item) }
        return out
    }

    static func isHiragana(_ s: Unicode.Scalar) -> Bool { (0x3041...0x309F).contains(s.value) }
    static func isKatakana(_ s: Unicode.Scalar) -> Bool { (0x30A0...0x30FF).contains(s.value) }
    static func isKanji(_ s: Unicode.Scalar) -> Bool { (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value) }
}

extension SearchSentence.Reading {
    /// 何も読めていない（季節・時間帯・欄の無い条件・字の語のどれも無い）
    var isEmptyReading: Bool {
        season == nil && dayPart == nil && unsupported.isEmpty && text == nil && unused.isEmpty
    }
}

// MARK: - 「こう読みました」の札

extension SearchSentence {

    /// 読み取りを見せる札1つ。**押すと外れる**（字の語は欄から消え、季節・時間帯はチップが外れる）
    struct Chip: Equatable, Identifiable {
        enum Kind: String { case text, season, dayPart }
        let kind: Kind
        let label: String
        /// 読み上げ（「季節 秋 を外す」）
        let spoken: String
        var id: String { kind.rawValue }
    }

    /// 今の画面の状態で、まだ効いている読み取りだけを札にする。**外した札・手で替えた絞り込みは出さない**
    /// （「秋」を外したあとに「春」を押したら、「秋」の札は出さない）
    static func chips(for reading: Reading, query: String, filter: ShootingTime.Filter) -> [Chip] {
        var chips: [Chip] = []
        if let text = reading.text, query.trimmingCharacters(in: .whitespacesAndNewlines) == text {
            chips.append(Chip(kind: .text, label: text, spoken: L("\(text) を外す", "Remove \(text)")))
        }
        if let season = reading.season, filter.season == season {
            chips.append(Chip(kind: .season, label: season.label,
                              spoken: L("季節 \(season.label) を外す", "Remove season: \(season.label)")))
        }
        if let part = reading.dayPart, filter.dayPart == part {
            chips.append(Chip(kind: .dayPart, label: part.label,
                              spoken: L("時間帯 \(part.label) を外す", "Remove time of day: \(part.label)")))
        }
        return chips
    }

    /// 「こう読みました」の段を出すか: 効いている札があるか、欄の無い条件などの1行があり欄が読み取りのままのとき
    static func showsReading(_ reading: Reading?, query: String, filter: ShootingTime.Filter) -> Bool {
        guard let reading, reading.changesSearch else { return false }
        if !chips(for: reading, query: query, filter: filter).isEmpty { return true }
        return reading.note != nil && keepsReading(reading, afterQueryChange: query)
    }

    /// 欄の字が替わったら読み取りを捨てるか（読み取りで入れた字のままなら残す）
    static func keepsReading(_ reading: Reading, afterQueryChange query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines) == (reading.text ?? "")
    }

    /// 読み取りを今の季節・時間帯に重ねる。**読めなかった軸は今の選択を残す**
    /// （「秋」を選んでから「夜景」と打てば、秋の夜）
    static func filter(applying reading: Reading, to current: ShootingTime.Filter) -> ShootingTime.Filter {
        var next = current
        if let season = reading.season { next.season = season }
        if let part = reading.dayPart { next.dayPart = part }
        return next
    }
}
