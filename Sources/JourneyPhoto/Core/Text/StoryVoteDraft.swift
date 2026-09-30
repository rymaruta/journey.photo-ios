import Foundation

/// 作る画面で置く**投票スタンプ**（「この景色、好き？」→ 2択）。
///
/// owner の「ストーリーの自由度が低い」（2026-09-29）。Web には投票があるのに、アプリでは
/// 作れなかった。**焼き込まずにデータで送る**（`texts` の `kind: "vote"`）——票を入れる
/// ボタンは画像では押せない。見る人のアプリと Web の両方が同じ札を描く（`StoryTextLayer`・
/// `StoryTextOverlay`）。
///
/// 決まりはサーバーと同じ（`api-user/src/storyText.ts`）:
/// - 問いは40字・選択肢は12字まで。**欠けた投票はサーバーが黙って落とす**ので、送る前に止める
/// - 1本に1つだけ（写真1枚＝1本なので、写真ごとに1つ）
/// - 位置は絵の矩形に対する割合（`(x, y)` の割合の点を札の同じ割合の点に合わせる）・
///   大きさは絵の幅に対する字の大きさ
struct StoryVoteDraft: Codable, Equatable {

    var question: String
    var optionA: String
    var optionB: String
    var x: Double
    var y: Double
    var size: Double
    /// 傾き（度・−180〜180）。**無い＝0度**で読む——この欄を足す前に残した下書きもそのまま読める。
    /// サーバーは整数の度に丸めて持つ（`clampStoryTextRotate`）
    var rotate: Double? = nil

    static let questionMax = 40
    static let optionMax = 12
    /// Web の `DEFAULT_STORY_VOTE_SIZE`（文字の既定より小さめ——札は問いと2つのボタンを持つ）
    static let defaultSize = 0.05

    /// 新しく置く投票。**問いと2択は Web と同じ既定**（`STORY_VOTE_DEFAULT`）
    static func new() -> StoryVoteDraft {
        StoryVoteDraft(question: L("この景色、好き？", "Love this view?"),
                       optionA: L("はい", "Yes"), optionB: L("いいえ", "No"),
                       x: 0.5, y: 0.7, size: defaultSize)
    }

    /// 問い・選択肢の字数を切る（打っている欄から呼ぶ）。**数え方はサーバーと同じ UTF-16**
    /// ——字で数えると、絵文字の入った問いが画面では上限内なのにサーバーで黙って切られた
    /// （274951f のレビュー）。入れようとした字のほうを削る（`PostLimits.limited`）
    static func limited(old: String, new: String, max: Int) -> String {
        PostLimits.limited(old: old, new: new.replacingOccurrences(of: "\n", with: " "), limit: max)
    }

    /// 送れる形か（問いと2択が全部ある）。**サーバーの `isCompleteStoryVote` と同じ判断**
    var isComplete: Bool {
        [question, optionA, optionB].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 閲覧画面と同じ描き方をするための形（`StoryTextLayer` がそのまま描く）
    var asItem: StoryTextItem {
        .vote(.init(place: .init(x: StoryTextItem.clampPosition(x), y: StoryTextItem.clampPosition(y),
                                 size: StoryTextItem.clampSize(size),
                                 rotate: StoryTextItem.normalizeRotate((rotate ?? 0).rounded())),
                    question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: [optionA, optionB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
    }

    /// 2本指でつまんだあとの大きさ（2026-09-30・owner「投票のサイズを縮小できない」）。
    /// **幅は送るときと同じ `StoryTextItem.clampSize`**（サーバーの `clampStoryTextSize`）
    /// ——画面でだけ大きく見えて、送ると縮む、にしない。倍率が読めない値なら変えない
    /// 2本指で回したあとの傾き。`radians` は指で回した角度（文字の札と同じ単位）。
    /// 送る形・画面とも**整数の度**に丸める（サーバーが丸めるので、画面だけ半端な角度で見せない）
    func rotated(byRadians radians: Double) -> StoryVoteDraft {
        guard radians.isFinite else { return self }
        var next = self
        let degrees = StoryTextItem.normalizeRotate(((rotate ?? 0) + radians * 180 / .pi).rounded())
        next.rotate = degrees == 0 ? nil : degrees
        return next
    }

    func scaled(by factor: Double) -> StoryVoteDraft {
        guard factor.isFinite, factor > 0 else { return self }
        var next = self
        next.size = StoryTextItem.clampSize(size * factor)
        return next
    }

    /// 指で動かした量（画面の点）を、絵の矩形（画面の点）に対する割合で足す。
    /// 幅はサーバーと同じ（0.06〜0.94）に、`visible` があれば**見えている範囲**（割合）にも挟む
    /// ——絵を埋めて敷くと端が画面の外に出る。そこへ動かすと掴み直せなかった（274951f のレビュー）
    func moved(by translation: CGSize, in box: CGSize,
               visible: (x: ClosedRange<Double>, y: ClosedRange<Double>)? = nil) -> StoryVoteDraft {
        guard box.width > 0, box.height > 0 else { return self }
        var next = self
        next.x = StoryTextItem.clampPosition(x + Double(translation.width / box.width))
        next.y = StoryTextItem.clampPosition(y + Double(translation.height / box.height))
        if let visible {
            next.x = min(max(next.x, visible.x.lowerBound), visible.x.upperBound)
            next.y = min(max(next.y, visible.y.lowerBound), visible.y.upperBound)
        }
        return next
    }

    /// 画面に見えている範囲（絵の矩形に対する割合）。**端から少し内側まで**
    static func visibleRange(photo: CGRect, canvas: CGSize) -> (x: ClosedRange<Double>, y: ClosedRange<Double>)? {
        guard photo.width > 0, photo.height > 0 else { return nil }
        func range(start: Double, length: Double, canvasLength: Double) -> ClosedRange<Double> {
            let lo = max(0.06, -start / length + 0.1)
            let hi = min(0.94, (canvasLength - start) / length - 0.1)
            return lo <= hi ? lo...hi : 0.5...0.5
        }
        return (range(start: Double(photo.minX), length: Double(photo.width), canvasLength: Double(canvas.width)),
                range(start: Double(photo.minY), length: Double(photo.height), canvasLength: Double(canvas.height)))
    }
}

/// `POST /stories` の `texts` に入れる1つ（送る形）。**鍵はサーバーの `sanitizeStoryTexts` が読むもの**
struct StoryPostText: Codable, Equatable {
    var kind: String
    var x: Double
    var y: Double
    var size: Double
    var text: String?
    var font: String?
    var color: String?
    var bg: String?
    var question: String?
    var options: [String]?
    /// 傾き（度）。**0 度は送らない**（サーバーも 0 は書かない・`sanitizeStoryTexts`）
    var rotate: Double? = nil

    /// 投票
    static func vote(_ v: StoryVoteDraft) -> StoryPostText {
        StoryPostText(kind: "vote", x: StoryTextItem.clampPosition(v.x), y: StoryTextItem.clampPosition(v.y),
                      size: StoryTextItem.clampSize(v.size),
                      question: v.question.trimmingCharacters(in: .whitespacesAndNewlines),
                      options: [v.optionA, v.optionB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                      rotate: v.asItem.place.rotate == 0 ? nil : v.asItem.place.rotate)
    }

    /// ひとことを文字として送る（投票を置いた1本だけ）。
    ///
    /// **`texts` を送ると、サーバーは `caption` を文字の並びから作り直す**（`stories.ts`）
    /// ——投票だけを送ると、打ったひとことが消える。見る画面（アプリ・Web）も `texts` が
    /// あればひとことを出さないので、**ひとことも写真の上の文字として送る**。
    /// 置き場所は写真の下の方の真ん中、明朝・白・下地なし（アプリのひとことの見た目に近い）
    ///
    /// 長さは**サーバーと同じ UTF-16 で** 200 に収める（`storyText.ts` の `STORY_TEXT_LEN_MAX`
    /// は `slice`＝UTF-16 で切る）。字（書記素）で数えると、絵文字の入った文がサーバーで
    /// 黙って切られ、しかも `slice` は絵文字の途中で割る。字の境目で切る（`PostLimits.clamp`）
    static func caption(_ text: String) -> StoryPostText {
        StoryPostText(kind: "text", x: 0.5, y: 0.86, size: 0.05,
                      text: PostLimits.clamp(text, limit: TextOverlay.maxLength), font: "mincho", color: "white", bg: "none")
    }

    /// 1本ぶんの `texts`。投票が無ければ nil（送らない＝これまでと同じ）
    static func list(vote: StoryVoteDraft?, caption: String) -> [StoryPostText]? {
        guard let vote, vote.isComplete else { return nil }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? [] : [.caption(trimmed)]) + [.vote(vote)]
    }

    // nil の鍵は書かない（サーバーは知らない鍵を読まないが、形を細く保つ）
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(size, forKey: .size)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(font, forKey: .font)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(bg, forKey: .bg)
        try c.encodeIfPresent(question, forKey: .question)
        try c.encodeIfPresent(options, forKey: .options)
        try c.encodeIfPresent(rotate, forKey: .rotate)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, x, y, size, text, font, color, bg, question, options, rotate
    }
}
