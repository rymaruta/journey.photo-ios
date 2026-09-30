import Foundation

/// ストーリーの上に**データで**置いたもの（文字・スタンプ・投票）。
///
/// Web のストーリーは文字を画像に焼き込まず、`texts` として持つ
/// （`photo-gallery/lib/utils/storyText.ts`・`api-user/src/storyText.ts`）。
/// **アプリはこれを読んでいなかった**ので、Web で文字・スタンプ・投票を置いた
/// ストーリーは、アプリでは写真だけに見え、投票もできなかった（owner の
/// 「ストーリーの自由度が低い」・2026-09-29 の調べ）。
///
/// 見た目の決まりは Web の `StoryTextOverlay` と同じ:
/// - 位置は**絵の矩形**に対する割合。**置き場所の基準点は `(x, y)` の割合の点**
///   （中心ではない。CSS の `translate(-x%, -y%)`）
/// - 大きさは**絵の幅**に対する割合（字の大きさ）
/// - 傾きは度・時計回りが正（無い＝0）
/// - **並びが重なり順**（後ろほど手前）
enum StoryTextItem: Equatable {
    case text(Label)
    case stamp(Stamp)
    case vote(Vote)

    /// 置き場所（どの種類にも共通）
    struct Place: Equatable {
        var x: Double
        var y: Double
        var size: Double
        /// 度（時計回りが正）
        var rotate: Double
    }

    struct Label: Equatable {
        var place: Place
        var text: String
        var font: String
        var color: String
        var bg: String
    }

    struct Stamp: Equatable {
        var place: Place
        var stamp: String
        var glyph: String
    }

    struct Vote: Equatable {
        var place: Place
        var question: String
        var options: [String]
    }

    var place: Place {
        switch self {
        case .text(let t): return t.place
        case .stamp(let s): return s.place
        case .vote(let v): return v.place
        }
    }

    /// Web の絵柄の一覧（`STORY_STAMPS`）。**知らない鍵は描かない**（別の絵に化けさせない）
    static let stampGlyphs: [String: String] = [
        "heart": "❤️", "star": "⭐", "sparkles": "✨", "fire": "🔥", "camera": "📷", "pin": "📍",
        "plane": "✈️", "mountain": "⛰️", "wave": "🌊", "sun": "☀️", "moon": "🌙", "flower": "🌸",
    ]

    /// Web の色（`STORY_COLORS`）。`hex` は文字（下地が solid なら下地）、`on` は solid の上の文字
    static let colors: [String: (hex: UInt32, on: UInt32)] = [
        "white": (0xFFFFFF, 0x000000), "black": (0x111111, 0xFFFFFF), "red": (0xFF453A, 0xFFFFFF),
        "orange": (0xFF9F0A, 0x000000), "yellow": (0xFFD60A, 0x000000), "lime": (0xB5E853, 0x000000),
        "green": (0x32D74B, 0x000000), "mint": (0x63E6E2, 0x000000), "sky": (0x64D2FF, 0x000000),
        "blue": (0x0A84FF, 0xFFFFFF), "purple": (0xBF5AF2, 0xFFFFFF), "pink": (0xFF6482, 0x000000),
    ]

    static let fonts: Set<String> = ["gothic", "bold", "mincho", "maru", "marker", "scribble", "mono"]
    static let backgrounds: Set<String> = ["none", "soft", "solid"]

    /// 置き場所の幅（Web の `STORY_TEXT_MIN/MAX`・`STORY_SIZE_MIN/MAX`）
    static func clampPosition(_ v: Double?) -> Double {
        guard let v, v.isFinite else { return 0.5 }
        return min(max(v, 0.06), 0.94)
    }

    static func clampSize(_ v: Double?) -> Double {
        guard let v, v.isFinite else { return 0.078 }
        return min(max(v, 0.03), 0.16)
    }

    /// −180〜180 に畳む（Web の `normalizeStoryRotate`）
    static func normalizeRotate(_ v: Double?) -> Double {
        guard let v, v.isFinite else { return 0 }
        let wrapped = (v.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : wrapped
    }

    /// サーバーが返す1つぶんの生の形。**どの項目も読めなければ無いものとして読む**
    /// （1つの形が崩れていても一覧ごと落とさない・`Story.song` と同じ作法）
    struct Raw: Decodable, Equatable {
        var kind: String?
        var x: Double?
        var y: Double?
        var size: Double?
        var rotate: Double?
        var text: String?
        var font: String?
        var color: String?
        var bg: String?
        var stamp: String?
        var question: String?
        var options: [String]?

        init(kind: String? = nil, x: Double? = nil, y: Double? = nil, size: Double? = nil, rotate: Double? = nil,
             text: String? = nil, font: String? = nil, color: String? = nil, bg: String? = nil,
             stamp: String? = nil, question: String? = nil, options: [String]? = nil) {
            self.kind = kind; self.x = x; self.y = y; self.size = size; self.rotate = rotate
            self.text = text; self.font = font; self.color = color; self.bg = bg
            self.stamp = stamp; self.question = question; self.options = options
        }

        private enum CodingKeys: String, CodingKey {
            case kind, x, y, size, rotate, text, font, color, bg, stamp, question, options
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil
            x = (try? c.decodeIfPresent(Double.self, forKey: .x)) ?? nil
            y = (try? c.decodeIfPresent(Double.self, forKey: .y)) ?? nil
            size = (try? c.decodeIfPresent(Double.self, forKey: .size)) ?? nil
            rotate = (try? c.decodeIfPresent(Double.self, forKey: .rotate)) ?? nil
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil
            font = (try? c.decodeIfPresent(String.self, forKey: .font)) ?? nil
            color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil
            bg = (try? c.decodeIfPresent(String.self, forKey: .bg)) ?? nil
            stamp = (try? c.decodeIfPresent(String.self, forKey: .stamp)) ?? nil
            question = (try? c.decodeIfPresent(String.self, forKey: .question)) ?? nil
            options = (try? c.decodeIfPresent([String].self, forKey: .options)) ?? nil
        }
    }

    /// 並びの1つを、壊れていても投げずに読む（読めなければ nil）
    struct Lossy: Decodable {
        let raw: Raw?
        init(from decoder: Decoder) throws { raw = try? Raw(from: decoder) }
    }

    /// 1つ読む。**読めない・知らない種類・中身の無いものは nil**（一覧ごと落とさない）。
    /// 知らない字体・色・下地は Web と同じ既定（太ゴシック・白・無し）へ
    static func parse(_ raw: Raw) -> StoryTextItem? {
        let place = Place(x: clampPosition(raw.x), y: clampPosition(raw.y),
                          size: clampSize(raw.size), rotate: normalizeRotate(raw.rotate))
        switch raw.kind {
        case "stamp":
            guard let key = raw.stamp, let glyph = stampGlyphs[key] else { return nil }
            return .stamp(Stamp(place: place, stamp: key, glyph: glyph))
        case "vote":
            let question = (raw.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let options = (raw.options ?? []).prefix(2).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !question.isEmpty, options.count == 2, options.allSatisfy({ !$0.isEmpty }) else { return nil }
            return .vote(Vote(place: place, question: question, options: options))
        case nil, "text":
            let text = (raw.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return .text(Label(place: place, text: text,
                               font: raw.font.flatMap { fonts.contains($0) ? $0 : nil } ?? "bold",
                               color: raw.color.flatMap { colors[$0] != nil ? $0 : nil } ?? "white",
                               bg: raw.bg.flatMap { backgrounds.contains($0) ? $0 : nil } ?? "none"))
        default:
            // 知らない種類は落とす（文字に化けさせない・Web の `isStoryTextItem` と同じ線）
            return nil
        }
    }

    /// 並びを読む。**投票は1つだけ**（2つ目以降は落とす・Web と同じ）
    static func parseList(_ raws: [Raw]) -> [StoryTextItem] {
        var out: [StoryTextItem] = []
        var seenVote = false
        for raw in raws {
            guard let item = parse(raw) else { continue }
            if case .vote = item {
                if seenVote { continue }
                seenVote = true
            }
            out.append(item)
        }
        return out
    }

    /// 揃えの線の値（`alignmentGuide` に返す）。Web は `(x, y)` の割合の点を、要素の同じ割合の点に
    /// 合わせる（`left: x%` と `translate(-x%)`・中心ではない）。要素の頭は
    /// `boxStart + boxLength × f − element × f` に来る（揃えの線はその符号を返したもの）
    static func guide(fraction f: Double, element: Double, boxStart: Double, boxLength: Double) -> Double {
        element * f - (boxStart + boxLength * f)
    }
}

/// 票の状態（`GET /stories` の `vote`・`POST /stories/{id}/vote` の応答）。
/// **数は投稿者と票を入れた人にだけ返る**（入れる前に数が見えると多い方に寄る）
struct StoryVoteState: Decodable, Equatable {
    /// "a" か "b"
    var myVote: String?
    var counts: Counts?

    init(myVote: String?, counts: Counts?) {
        self.myVote = myVote
        self.counts = counts
    }

    private enum CodingKeys: String, CodingKey { case myVote, counts }

    /// 知らない値の票は「入れていない」として読む（数だけは読む）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mine = (try? c.decodeIfPresent(String.self, forKey: .myVote)) ?? nil
        myVote = mine == "a" || mine == "b" ? mine : nil
        counts = (try? c.decodeIfPresent(Counts.self, forKey: .counts)) ?? nil
    }

    struct Counts: Decodable, Equatable {
        var a: Int
        var b: Int
    }

    /// 選択肢ごとの割合（0〜100・合わせて100）。数が見えない・0票なら nil
    var percents: (a: Int, b: Int)? {
        guard let counts, counts.a + counts.b > 0 else { return nil }
        let a = Int((Double(counts.a) / Double(counts.a + counts.b) * 100).rounded())
        return (a, 100 - a)
    }
}
