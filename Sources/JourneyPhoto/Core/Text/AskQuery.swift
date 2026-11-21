import Foundation

/// 探すの欄に打った字を、**今の字の検索**のままにするか、**AI の答え**にするかを決める（札 #652・案 A）。
///
/// 欄は1つのまま（2026-11-20 owner 承認・Artifact「AI に頼む」8版）:
/// - 「京都」「夕日」のような語、「京都 紅葉 夜」のように語を並べただけの文は、今の字の検索と
///   「こう読みました」（札 #623・言葉の表）のまま。**AI を呼ばず、回数も使わない**
/// - 頼みや質問の形（「教えて」「どこ」「作って」「近くで」「〜には」「？」など）は AI の答え（回数を1回使う）
///
/// 2026-11-20 判断: Artifact は「季節、時間帯、県、近さが読めたとき」も答えの形にする案だった。そのまま作ると
/// 「夕日」の1語で1日3回の回数を使ってしまう（今の文で探すは回数を数えていなかった）。語を並べただけの文は
/// 言葉の表で読めば足りるので、**頼みと質問の形だけ**を AI に回す。「京都 紅葉 夜」の「こう読みました」は
/// 答えの形の一部（読み取りの札）として残る。
///
/// 画面を持たない層なので Linux の `swift test` で確かめる（`AskQueryTests`）。
enum AskQuery {

    enum Form: Equatable {
        /// 今の字の検索（と、語を並べた文なら言葉の表の読み取り）
        case words
        /// AI の答え
        case ask
    }

    /// 頼みと質問の言葉（畳んだ字に当てる）
    static let askMarkers: [String] = [
        "教えて", "おしえて", "ください", "下さい", "ちょうだい",
        "どこ", "どう", "どれ", "どんな", "どの", "何", "なに", "なん", "いつ", "だれ", "誰", "なぜ", "どうして",
        "作って", "つくって", "組んで", "立てて", "探して", "さがして", "調べて", "選んで", "決めて",
        "知りたい", "行きたい", "見たい", "撮りたい", "したい",
        "おすすめ", "オススメ", "お勧め", "お薦め", "おススメ",
        "近く", "近所", "この辺", "周り",
        "コツ", "こつ", "方法", "やり方", "仕方", "しかた", "撮り方", "使い方", "付け方", "つけ方",
        "持ち物", "持っていけば", "持って行けば", "服装",
        "ですか", "ますか", "でしょう", "だろう",
    ]

    /// 文の終わりで質問と分かる形（「金沢で雨の日に行ける所は」「ストーリーに曲を付けるには」）
    static let askEndings: [String] = ["は", "には", "って", "か", "の", "？", "?"]

    /// 英語の質問の頭
    static let englishLeads: [String] = [
        "how ", "what ", "where ", "when ", "which ", "why ", "who ", "can ", "could ", "should ", "is ", "are ",
        "do ", "does ", "recommend", "suggest", "plan ", "tell ", "show me", "find ", "best ", "help ",
    ]

    /// AI の答えにするか
    static func form(_ raw: String, scope: SearchScope = .all) -> Form {
        guard scope != .people else { return .words }
        let text = SearchSentence.fold(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, !text.hasPrefix("@"), !text.hasPrefix("#") else { return .words }
        let lower = text.lowercased()
        if text.contains("？") || text.contains("?") { return .ask }
        if englishLeads.contains(where: { lower.hasPrefix($0) }) || lower.contains("near me") || lower.contains("nearby") {
            return .ask
        }
        if askMarkers.contains(where: { text.contains($0) }) { return .ask }
        // 終わりの「は」「には」「って」「か」は、ひらがなでない字（漢字、片仮名）を含む文だけ（「わかは」のような語は外す）
        let hasKanjiOrKana = text.unicodeScalars.contains { SearchSentence.isKanji($0) || SearchSentence.isKatakana($0) }
        if hasKanjiOrKana, text.count >= 4, askEndings.contains(where: { text.hasSuffix($0) }) {
            // 「京都の」「夕日の」は語のかけら。終わりの「の」は質問の形（「〜あるの」）だけ
            if text.hasSuffix("の") { return text.hasSuffix("あるの") || text.hasSuffix("いいの") ? .ask : .words }
            return .ask
        }
        return .words
    }

    // MARK: - 頼みの中身（アプリが選ぶための型）

    /// 頼みから読む「何を」。**選ぶのはアプリ**（AI は場所を作らない・Artifact「仕組み」）
    struct Intent: Equatable {
        /// 現在地から近い所（「近くで」「この辺」）
        var near = false
        /// 旅行プランを作ってほしい（「1泊2日の旅行プランを作って」）
        var plan = false
        /// 使い方の質問（「ストーリーに曲を付けるには」）
        var howTo = false
        /// 観光スポットを探している（「おすすめ」「〜所」「〜スポット」、季節や時間帯や地名が読めた）
        var spots = false
    }

    static let nearWords = ["近く", "近所", "この辺", "このへん", "周り", "周辺", "near me", "nearby", "around here"]
    static let planWords = ["プラン", "旅程", "日程", "泊", "日帰り", "itinerary", "trip plan", "day trip"]
    static let howToWords = [
        "使い方", "やり方", "方法", "仕方", "しかた", "付け方", "つけ方", "には", "できる", "どうやって", "どこから",
        "ストーリー", "投稿", "メッセージ", "dm", "アルバム", "すれちが", "乗車券", "トランク", "硬貨", "行きたい場所",
        "公開範囲", "ブロック", "通報", "下書き", "how do i", "how to", "how can i",
    ]
    static let adviceWords = ["コツ", "こつ", "撮り方", "方法", "やり方", "設定", "持ち物", "持って", "服装", "tips", "how to shoot", "what to pack"]
    static let spotWords = [
        "所", "ところ", "場所", "スポット", "名所", "観光", "絶景", "景色", "見どころ", "行ける", "撮れる", "撮影地",
        "place", "spot", "where", "sightseeing", "view",
    ]

    /// 頼みの中身を読む（`reading` は言葉の表の読み取り）
    static func intent(_ raw: String, reading: SearchSentence.Reading) -> Intent {
        let text = SearchSentence.fold(raw).lowercased()
        var intent = Intent()
        intent.near = nearWords.contains { text.contains($0) }
        let planned = planWords.contains { text.contains($0) }
        intent.plan = planned && (text.contains("作") || text.contains("組") || text.contains("立て") || text.contains("plan")
                                  || text.contains("泊") || text.contains("日帰り")
                                  // 2026-11-21 判断（札 #675 の答えの形）: 「2日の旅行プランにして」（次に頼めること、版3の例）も旅行プランの頼み
                                  || text.contains("プランにし") || text.contains("プランにす"))
        let spotish = spotWords.contains { text.contains($0) } || text.contains("おすすめ") || text.contains("オススメ")
        // 撮り方や持ち物の相談（「夕日を撮るコツは」）は、場所の言葉が無ければ観光スポットを探していない
        let advice = adviceWords.contains { text.contains($0) }
        let readable = reading.season != nil || reading.dayPart != nil
            || (reading.text.map { RegionList.prefecture(named: $0) != nil || RegionList.prefectures.contains($0) } ?? false)
        intent.spots = intent.near || intent.plan || spotish || (readable && !advice)
        // 使い方: 機能の名前か「〜には」「方法」があり、観光スポットを探していない
        intent.howTo = !intent.spots && howToWords.contains { text.contains($0) }
        return intent
    }

    // MARK: - 欄の見本の字

    /// 見本の字の頭（「AI に聞いてみる: 」）。読み上げでは欄の名前「AI に聞く、または探す」を別に読む
    static var promptHead: String { L("AI に聞いてみる: ", "Ask AI: ") }

    /// 欄の読み上げの名前（Artifact「読み上げ」）
    static var fieldLabel: String { L("AI に聞く、または探す", "Ask AI or search") }

    /// 4秒ごとに入れ替える見本（季節で替える・冬は「雪景色がきれいな所」）
    static func examples(month: Int) -> [String] {
        let seasonal: String
        switch month {
        case 12, 1, 2: seasonal = L("雪景色がきれいな所は？", "Where can I see beautiful snow?")
        case 3, 4, 5: seasonal = L("今週末、桜が見頃の所は？", "Where are cherry blossoms at their best this weekend?")
        case 6, 7, 8: seasonal = L("夏に涼しく撮れる所は？", "Where can I shoot somewhere cool in summer?")
        default: seasonal = L("今週末、紅葉が見頃の所は？", "Where are autumn leaves at their best this weekend?")
        }
        // 2026-11-20 判断: 見本はそのまま打っても AI の答えになる頼みの形にする（「〜所」だけでは今の検索になる）。
        // `AskQueryTests` が全部の月の見本を `form == .ask` で見張る
        return [
            L("近くで夕日がきれいな所は？", "Where are nearby places with great sunsets?"),
            seasonal,
            L("おすすめの観光スポットを教えて", "Recommend some tourist spots"),
            L("金沢に1泊2日の旅行プランを作って", "Make a 2-day trip plan for Kanazawa"),
        ]
    }

    /// 見本の字（`index` 番目。動きを減らす設定では 0 で止める）
    static func prompt(index: Int, month: Int) -> String {
        let list = examples(month: month)
        return promptHead + list[((index % list.count) + list.count) % list.count]
    }

    /// 見本を入れ替える間（秒）
    static let rotateSeconds: UInt64 = 4

    /// 打った文の長さの上限（サーバーの `TRIP_AI_MAX_REQUEST` と同じ 200 字）
    static let maxLength = 200

    // MARK: - 途中の字では AI を呼ばない（2026-11-20 判断・札 #662）

    /// 2026-11-20 判断（owner「文字打つだけでAI使われると結構すぐ上限きてしんどい」）: 打っている途中の字
    /// （「おすすめの」「京都で」）は、送信のボタンを押しても AI を呼ばない。回数も使わない。
    /// 1.1.107 の実機で「おすすめの」が「おすすめ」を印に頼みと読まれ、途中の字で1回使っていた。
    ///
    /// 決め方: 終わりが助詞（の、を、で、に、と、が）で、その前が短い（6字まで）語のかけら。
    /// 前が「いい」「ある」「見たい」のような言い切り（い、る、た、う、か、す、ね、よ で終わる）なら続きを待たない（「どこがいいの」）。
    /// 終わりの「は」は質問の形（「桜の名所は」）にもなるので、前が4字までで、場所の言葉も季節や県も読めないときだけ
    static let continuingParticles: [Character] = ["の", "を", "で", "に", "と", "が"]
    static let predicateEnds: Set<Character> = ["い", "る", "た", "う", "か", "す", "ね", "よ"]

    static func isUnfinished(_ raw: String) -> Bool {
        let text = SearchSentence.fold(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.last else { return false }
        let stem = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        guard let stemLast = stem.last else { return true }
        if continuingParticles.contains(last) {
            return stem.count <= 6 && !predicateEnds.contains(stemLast)
        }
        if last == "は" {
            guard stem.count <= 4, !predicateEnds.contains(stemLast) else { return false }
            let reading = SearchSentence.readByTable(stem)
            let hasContent = spotWords.contains { stem.contains($0) } || reading.season != nil || reading.dayPart != nil
                || RegionList.prefecture(named: stem) != nil || RegionList.prefectures.contains(stem)
            return !hasContent
        }
        return false
    }

    /// 送信のボタンで AI に送れるか（頼みと質問の形で、途中の字でない）。人を探すときは送らない
    static func sendsToAI(_ raw: String, scope: SearchScope = .all) -> Bool {
        form(raw, scope: scope) == .ask && !isUnfinished(raw)
    }

    /// 途中の字のときに欄の下に出す1行
    static var keepTypingLine: String { L("続けて打つと AI に聞けます", "Keep typing to ask AI") }

    static func clipped(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > maxLength ? String(t.prefix(maxLength)) : t
    }
}
