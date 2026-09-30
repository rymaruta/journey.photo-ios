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

    static let questionMax = 40
    static let optionMax = 12
    /// Web の `DEFAULT_STORY_VOTE_SIZE`（文字の既定より小さめ——札は問いと2つのボタンを持つ）
    static let defaultSize = 0.05
    /// 投票の y の上限。**これより下に置くと、下のひとことの欄・撮影地・曲の行に重なる**
    /// （レビューの計算で y > 約0.75 から重なる）。既定の y（0.7）と同じ値
    static let maxY = 0.7

    /// 投票の y を挟む（0.06〜`maxY`）。**描く・動かす・送るの3か所で同じもの**を使う
    /// ——前の版で `maxY` より下に置いた下書きを戻したとき、動かす所だけで挟むと
    /// 触った瞬間に跳び、触らずに送ると下の欄に重なる位置のまま送られた
    static func clampY(_ y: Double) -> Double {
        min(StoryTextItem.clampPosition(y), maxY)
    }

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
        .vote(.init(place: .init(x: StoryTextItem.clampPosition(x), y: Self.clampY(y),
                                 size: StoryTextItem.clampSize(size), rotate: 0),
                    question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: [optionA, optionB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
    }

    /// 指で動かした量（画面の点）を、絵の矩形（画面の点）に対する割合で足す。
    /// 幅はサーバーと同じ（0.06〜0.94。y は下の欄に重ねないよう `maxY` まで）に、`visible` があれば**見えている範囲**（割合）にも挟む
    /// ——絵を埋めて敷くと端が画面の外に出る。そこへ動かすと掴み直せなかった（274951f のレビュー）
    func moved(by translation: CGSize, in box: CGSize,
               visible: (x: ClosedRange<Double>, y: ClosedRange<Double>)? = nil) -> StoryVoteDraft {
        guard box.width > 0, box.height > 0 else { return self }
        var next = self
        next.x = StoryTextItem.clampPosition(x + Double(translation.width / box.width))
        // 描いている位置（`clampY`）から動かす——前の版の下書きで跳ばないように
        next.y = StoryTextItem.clampPosition(Self.clampY(y) + Double(translation.height / box.height))
        if let visible {
            next.x = min(max(next.x, visible.x.lowerBound), visible.x.upperBound)
            next.y = min(max(next.y, visible.y.lowerBound), visible.y.upperBound)
        }
        // 下の欄に重ねない（見えている範囲より優先——重なると札もひとことも読めない）
        next.y = min(next.y, Self.maxY)
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

    /// 投票
    static func vote(_ v: StoryVoteDraft) -> StoryPostText {
        StoryPostText(kind: "vote", x: StoryTextItem.clampPosition(v.x), y: StoryVoteDraft.clampY(v.y),
                      size: StoryTextItem.clampSize(v.size),
                      question: v.question.trimmingCharacters(in: .whitespacesAndNewlines),
                      options: [v.optionA, v.optionB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    /// ひとことを文字として送る（投票を置いた1本だけ）。
    ///
    /// **本番のサーバーが photo-gallery #257 より前の間は、この形で送る。** 古いサーバーは
    /// `texts` があると `caption` を文字の並びから作り直し、投票だけを送るとひとことが消える。
    /// #257 のあとは「文字の項目が無ければ送った `caption` を使う」ので、投票だけの `texts`
    /// ＋`caption` に切り替えられる（見る画面は、アプリ・Web とも文字の項目が無ければ下の欄に出す）。
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
    }

    private enum CodingKeys: String, CodingKey {
        case kind, x, y, size, text, font, color, bg, question, options
    }
}
