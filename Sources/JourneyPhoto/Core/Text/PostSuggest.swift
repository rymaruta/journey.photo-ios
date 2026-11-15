import Foundation

/// 投稿の画面で出す「題・説明・タグの候補」の材料と整え方（札 #622）。
///
/// **2026-11-15 判断（owner「推奨は頼むわ」）:**
/// - 候補を作るのは**端末の AI（Apple Foundation Models）だけ**（`OnDeviceAI`・`PostSuggester`）。写真も文も
///   端末の外へ送らないので、費用は0円、プライバシーポリシーも変えない。Bedrock は使わない
/// - **端末の AI が使えない機種・OS では候補を出さない**（今と同じ見え方。空の欄や案内も出さない）
/// - 材料は端末の中にあるものだけ: 撮影地・結んだ観光スポットの名前、観光スポットの台帳の季節と時間帯、
///   撮った日時、写真の中身（Vision の分類 `VNClassifyImageRequest` を端末の中で使う）
/// - 候補は押せば入り、要らなければ無視できる。**入力欄を勝手に書き換えない**（候補の札を押したときだけ入る）
/// - 自分の投稿の画面だけで使う（他人の写真には使わない・CLAUDE.md「他人の写真は、その人のもの」）
/// - 中黒の区切り・「撮りどき」「捨てる」は入れない。呼び名は「観光スポット」
/// - タグは決まった選択肢（`TagChoices.all`）からだけ選ばせる（生成の型で縛り、ここでもう一度縛る）
///
/// ここは**画面を持たない計算だけ**（Linux の試験でも走る）。AI を呼ぶのは `PostSuggester`。
enum PostSuggest {

    /// 1枚の写真の材料（端末の中にあるものだけ）
    struct Input: Equatable {
        /// 撮影地の欄の字（写真の位置から自動で入った地名か、本人が書いた・選んだ地名）
        var place: String = ""
        /// 結んだ観光スポットの名前（候補から選んだ・自動で結ぶ札がオン）
        var spotName: String?
        /// 観光スポットの台帳の、季節の案内がある季節（"spring"〜"winter"）
        var spotSeasons: [String] = []
        /// 観光スポットの台帳の、時間帯の案内がある時間帯（"dawn"・"morning"…）
        var spotTimes: [String] = []
        /// 撮った日（YYYY-MM-DD）
        var takenOn: String?
        /// 撮った時（0〜23。EXIF の時刻が読めたときだけ）
        var takenHour: Int?
        /// 写真に写っているもの（Vision の分類の識別子。英語の小文字）
        var labels: [String] = []

        /// 材料が何も無い（候補を作っても当て推量になる）
        var isEmpty: Bool {
            place.trimmed.isEmpty && (spotName ?? "").trimmed.isEmpty && takenOn == nil && labels.isEmpty
        }
    }

    /// 画面に出す候補（整えたあと）
    struct Result: Equatable {
        /// 題の候補（3つまで）
        var titles: [String] = []
        /// 説明の候補（1つまで）
        var caption: String?
        /// タグの候補（`TagChoices.all` の語だけ・3つまで）
        var tags: [String] = []

        var isEmpty: Bool { titles.isEmpty && caption == nil && tags.isEmpty }
    }

    // MARK: - 数

    /// 題の候補の数
    static let titleCount = 3
    /// タグの候補の数
    static let tagCount = 3
    /// 題の候補の長さ（字）。短い名詞句にする。長いものは落とす（切ると意味が割れる）
    static let titleLength = 2...24
    /// 説明の候補の長さ（字）
    static let captionLength = 4...120
    /// Vision の分類を材料に入れる確かさの下限と数（多いと的外れな語が混ざる）
    static let labelConfidence: Float = 0.3
    static let labelCount = 6

    // MARK: - 材料から問いを作る

    /// AI への決まり（日本語）。**材料に無いことを作らせない**のが主眼
    static let instructions = """
    あなたは写真の投稿アプリの手伝いです。利用者が自分で撮った写真に付ける、題と説明の候補を日本語で作ります。
    決まり:
    - 渡された材料（撮影地、観光スポット、季節、時間帯、写っているもの）だけを使う。材料に無い地名、名物、出来事、人の名前を作らない
    - 題は短い名詞句（4〜16文字）。3つとも違う言い方にする
    - 説明は1〜2文で、60文字まで
    - 中黒の記号で語を区切らない。並べるときは「、」を使う
    - 「撮りどき」「捨てる」という言葉は使わない。公式の場所は「観光スポット」と呼ぶ
    - 絵文字、ハッシュタグ、かぎかっこは付けない
    - タグは選択肢の中から、写真に合うものだけを0〜3個選ぶ
    """

    /// 1枚の材料を AI に渡す文にする。**無い材料の行は書かない**（「不明」と書くと、それらしい中身を作る）
    static func prompt(_ input: Input) -> String {
        var lines: [String] = []
        let place = input.place.trimmed
        if !place.isEmpty { lines.append("撮影地: \(place)") }
        if let spot = input.spotName?.trimmed, !spot.isEmpty { lines.append("観光スポット: \(spot)") }
        let seasons = input.spotSeasons.compactMap(SpotBodyText.seasonLabel)
        if !seasons.isEmpty { lines.append("観光スポットの見頃の季節: \(seasons.joined(separator: "、"))") }
        let times = input.spotTimes.compactMap(SpotBodyText.timeLabel)
        if !times.isEmpty { lines.append("撮影に向く時間帯: \(times.joined(separator: "、"))") }
        if let when = takenText(on: input.takenOn, hour: input.takenHour) { lines.append("撮った日: \(when)") }
        if !input.labels.isEmpty { lines.append("写っているもの（画像の分類、英語）: \(input.labels.joined(separator: ", "))") }
        lines.append("タグの選択肢: \(TagChoices.all.joined(separator: "、"))")
        return lines.joined(separator: "\n")
    }

    /// 「2026年11月3日 16時ごろ（秋、夕方）」。日が読めなければ nil
    static func takenText(on day: String?, hour: Int?) -> String? {
        guard let day, day.count >= 10 else { return nil }
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        var text = "\(parts[0])年\(parts[1])月\(parts[2])日"
        var notes = [SpotBodyText.seasonLabel(SpotBodyText.season(ofMonth: parts[1])) ?? ""]
        if let hour, (0...23).contains(hour) {
            text += " \(hour)時ごろ"
            notes.append(partOfDay(hour))
        }
        let shown = notes.filter { !$0.isEmpty }
        return shown.isEmpty ? text : text + "（\(shown.joined(separator: "、"))）"
    }

    /// 時刻のおおよその呼び名（材料の文だけに使う）
    static func partOfDay(_ hour: Int) -> String {
        switch hour {
        case 4..<10: return "朝"
        case 10..<15: return "昼"
        case 15..<19: return "夕方"
        default: return "夜"
        }
    }

    /// EXIF の撮影日時（`2026:11:03 16:42:10` か `2026-11-03T16:42:10`）から時を読む。読めなければ nil
    static func hour(fromExif stamp: String?) -> Int? {
        guard let stamp, stamp.count >= 13 else { return nil }
        let chars = Array(stamp)
        let sep = chars[10]
        guard sep == " " || sep == "T", let hour = Int(String(chars[11...12])), (0...23).contains(hour) else { return nil }
        return hour
    }

    // MARK: - AI の答えを整える

    /// 画面に出してよい言葉か（CLAUDE.md の言葉の決まり）。**直せない言葉を含む候補は落とす**
    static let bannedWords = ["撮りどき", "撮り時", "捨て"]

    /// 1つの候補の字を整える。出せなければ nil
    ///
    /// - 前後の空白・かぎかっこ・引用符・先頭の `#` を落とす。題は最後の「。」も落とす
    /// - 中黒（`・` `·` `･` `•`）は「、」にする（owner の好み・2026-11-12）
    /// - 「撮影スポット」は「観光スポット」にする（2026-11-12 の呼び名）
    /// - 禁じた言葉（`bannedWords`）・URL・改行の後ろは出さない
    static func tidy(_ raw: String, isTitle: Bool) -> String? {
        var text = raw
        // 1行目だけ（題に改行は入らない。説明も候補は1つの段落にする）
        if let line = text.split(whereSeparator: \.isNewline).first { text = String(line) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers: Set<Character> = ["「", "」", "『", "』", "\"", "“", "”", "'", "‘", "’", "【", "】"]
        while let first = text.first, wrappers.contains(first) || first == "#" || first == "＃" { text.removeFirst() }
        while let last = text.last, wrappers.contains(last) { text.removeLast() }
        text = text.replacingOccurrences(of: "撮影スポット", with: "観光スポット")
        for dot in ["・", "·", "･", "•"] {
            text = text.replacingOccurrences(of: " \(dot) ", with: "、")
                .replacingOccurrences(of: dot, with: "、")
        }
        while text.contains("、、") { text = text.replacingOccurrences(of: "、、", with: "、") }
        if isTitle {
            while let last = text.last, last == "。" || last == "." || last == "、" { text.removeLast() }
        }
        text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "、")))
        if bannedWords.contains(where: { text.contains($0) }) { return nil }
        if text.contains("http") || text.contains("www.") { return nil }
        let range = isTitle ? titleLength : captionLength
        guard range.contains(text.count) else { return nil }
        return text
    }

    /// AI の答え（生）を画面に出す候補にする。
    /// - Parameters:
    ///   - titles: 題の候補（生）
    ///   - caption: 説明の候補（生）
    ///   - tags: タグの候補（生）。**`TagChoices.all` に無い語は落とす**（生成の型で縛ってあるが、ここでも縛る）
    static func result(titles: [String], caption: String?, tags: [String]) -> Result {
        var seen = Set<String>()
        var shownTitles: [String] = []
        for raw in titles {
            guard let title = tidy(raw, isTitle: true) else { continue }
            guard seen.insert(title.lowercased()).inserted else { continue }
            shownTitles.append(title)
            if shownTitles.count == titleCount { break }
        }
        let shownCaption = caption.flatMap { tidy($0, isTitle: false) }
            // 題の候補と同じ字なら出さない（同じものが2か所に並ぶ）
            .flatMap { seen.contains($0.lowercased()) ? nil : $0 }
        return Result(titles: shownTitles, caption: shownCaption, tags: choices(tags))
    }

    /// タグの候補を、決まった選択肢の語（綴りも選択肢のもの）にそろえる。重なりは落とす
    static func choices(_ tags: [String]) -> [String] {
        var picked: [String] = []
        for raw in tags {
            let key = TagChoices.key(raw)
            guard let choice = TagChoices.all.first(where: { $0 == raw.trimmed || TagChoices.key($0) == key }) else { continue }
            if !picked.contains(choice) { picked.append(choice) }
            if picked.count == tagCount { break }
        }
        return picked
    }

    // MARK: - 画面

    /// 題の欄の下に候補を出すか。**欄が空のときだけ**（打った字の上に候補を並べない・欄を書き換えさせない）
    static func showsTitles(_ result: Result?, title: String) -> [String] {
        guard let result, title.trimmed.isEmpty else { return [] }
        return result.titles
    }

    /// 説明の欄の下に候補を出すか（題と同じく、欄が空のときだけ）
    static func showsCaption(_ result: Result?, caption: String) -> String? {
        guard let result, caption.trimmed.isEmpty else { return nil }
        return result.caption
    }

    /// タグの候補（まとめて付くので、写真ごとの候補を前の写真から順に合わせる）。3つまで
    static func tags(_ results: [Result?]) -> [String] {
        choices(results.compactMap { $0 }.flatMap(\.tags))
    }

    /// タグの札の並び。**候補を先頭に**、残りは決まった並びのまま（札を増やさない・押す回数も同じ）
    static func orderedChoices(suggested: [String]) -> [String] {
        let front = choices(suggested)
        return front + TagChoices.all.filter { !front.contains($0) }
    }

    /// 候補を作り直す鍵（写真ごと）。撮影地・観光スポットが変わったら作り直す
    static func key(_ input: Input) -> String {
        [input.place.trimmed, input.spotName ?? "", input.takenOn ?? "", input.takenHour.map(String.init) ?? "",
         input.spotSeasons.joined(separator: ","), input.spotTimes.joined(separator: ",")]
            .joined(separator: "|")
    }

    /// 画面写真の試験で出す決まった候補（`OnDeviceAI.Mode.sample`・Debug のみ）。AI は呼ばない
    static let sample = Result(titles: ["秋の兼六園", "雪吊りと池", "庭園の朝"],
                               caption: "紅葉の庭園を朝の光の中で歩きました。",
                               tags: ["秋", "紅葉", "公園"])
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
