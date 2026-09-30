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

    /// 新しく置く投票。**問いと2択は Web と同じ既定**（`STORY_VOTE_DEFAULT`）
    static func new() -> StoryVoteDraft {
        StoryVoteDraft(question: L("この景色、好き？", "Love this view?"),
                       optionA: L("はい", "Yes"), optionB: L("いいえ", "No"),
                       x: 0.5, y: 0.7, size: defaultSize)
    }

    /// 問い・選択肢の字数を切る（打っている欄から呼ぶ）
    static func limited(_ text: String, max: Int) -> String {
        String(text.replacingOccurrences(of: "\n", with: " ").prefix(max))
    }

    /// 送れる形か（問いと2択が全部ある）。**サーバーの `isCompleteStoryVote` と同じ判断**
    var isComplete: Bool {
        [question, optionA, optionB].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 閲覧画面と同じ描き方をするための形（`StoryTextLayer` がそのまま描く）
    var asItem: StoryTextItem {
        .vote(.init(place: .init(x: StoryTextItem.clampPosition(x), y: StoryTextItem.clampPosition(y),
                                 size: StoryTextItem.clampSize(size), rotate: 0),
                    question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: [optionA, optionB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
    }

    /// 指で動かした量（画面の点）を、絵の矩形（画面の点）に対する割合で足す。
    /// 幅はサーバーと同じ（0.06〜0.94）
    func moved(by translation: CGSize, in box: CGSize) -> StoryVoteDraft {
        guard box.width > 0, box.height > 0 else { return self }
        var next = self
        next.x = StoryTextItem.clampPosition(x + Double(translation.width / box.width))
        next.y = StoryTextItem.clampPosition(y + Double(translation.height / box.height))
        return next
    }
}

/// `POST /stories` の `texts` に入れる1つ（送る形）。**鍵はサーバーの `sanitizeStoryTexts` が読むもの**
struct StoryPostText: Encodable, Equatable {
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
        StoryPostText(kind: "vote", x: StoryTextItem.clampPosition(v.x), y: StoryTextItem.clampPosition(v.y),
                      size: StoryTextItem.clampSize(v.size),
                      question: v.question.trimmingCharacters(in: .whitespacesAndNewlines),
                      options: [v.optionA, v.optionB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    /// ひとことを文字として送る（投票を置いた1本だけ）。
    ///
    /// **`texts` を送ると、サーバーは `caption` を文字の並びから作り直す**（`stories.ts`）
    /// ——投票だけを送ると、打ったひとことが消える。見る画面（アプリ・Web）も `texts` が
    /// あればひとことを出さないので、**ひとことも写真の上の文字として送る**。
    /// 置き場所は写真の下の方の真ん中、明朝・白・下地なし（アプリのひとことの見た目に近い）
    static func caption(_ text: String) -> StoryPostText {
        StoryPostText(kind: "text", x: 0.5, y: 0.86, size: 0.07,
                      text: String(text.prefix(TextOverlay.maxLength)), font: "mincho", color: "white", bg: "none")
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
