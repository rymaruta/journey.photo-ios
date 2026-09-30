import Foundation

/// 投票を置いた1本で、**ひとことを写真の上の文字として置く場所**（`StoryPostText.list`）。
///
/// 撮影地か曲を付けると、見る画面の下に行が出る（アプリは写真の枠の下から 96pt・ハイライトは
/// 150pt、Web は返信の帯の上）。決まった高さ（0.86・0.72）に置くと、その行や投票の札に重なった
/// （fe1bcf4 のレビュー）。重なるかどうかは次のもので変わるので、1つの数では決められない:
/// - ひとことの行数（真ん中に置くと1行は絵の幅の半分まで。字が 5% なら約10字）
/// - 絵の敷き方（アプリは画面を埋める＝横長の写真は絵の幅が画面の2倍を超え、字も大きくなる。
///   Web は収める）
/// - 投票の札の高さ（本人が見るときは「まだ票はありません」の段が増える）
///
/// ## 決まり
///
/// 見る画面の寸法の組（`screens`）の**どれでも**、ひとことが次に重ならない置き方を探す:
/// 上の名前と進み具合の段・下の撮影地と曲の行・投票の札（間を 8 空ける）。
/// 1. 字の大きさは 5% のまま（**明朝は 18pt が下限**＝デザインの板。幅 375 の画面で 18.75pt。
///    小さくして収めると下限を割る）
/// 2. 高さは**できるだけ下**（これまでの 0.86 に近い側）から上へ探す。札が下にあれば札の上、
///    札が上にあれば札の下（行より上）に落ち着く
/// 3. 3行を超えるひとこと、またはどこにも入らないときは、入る行数（3→2→1）まで切って「…」を付ける
///    （`texts` を送るとサーバーは `caption` をこの文字から作るので、保存されるひとことも切れる。
///    重ねて読めなくするより、切って読める方を選ぶ）
///
/// 寸法は実物を読んで写した値（下の `screens` の注釈）。**確かめたのは模型の上だけ**
/// （本物の端末・ブラウザでは測っていない）。
enum StoryCaptionPlacement {

    struct Result: Equatable {
        var text: String
        var y: Double
        var size: Double
    }

    /// 横の位置（真ん中）。これまでと同じ
    static let x = 0.5
    /// 字の大きさ（絵の幅に対する割合）。明朝の下限 18pt を割らないので下げない
    static let size = 0.05
    /// ひとことの行数の上限
    static let maxLines = 3
    /// 札・段・行との間
    static let gap = 8.0
    /// 写真の縦横比が分からないときに試す比（縦 9:16・縦 3:4・横 4:3）
    static let fallbackAspects = [9.0 / 16, 3.0 / 4, 4.0 / 3]

    enum Platform {
        /// アプリ（`StoryTextLayer`）: 絵は画面を**埋める**（`TextOverlay.filledRect`）。
        /// ひとことは明朝（ヒラギノ明朝 W6・行の高さ約 1.5）
        case app
        /// Web（`StoryTextOverlay`）: 絵は画面に**収める**（`object-contain`）。行の高さ 1.25
        case web
    }

    /// 見る画面の1つ。座標は写真の枠の左上から（pt / px）
    struct Screen {
        let name: String
        let platform: Platform
        let width: Double
        let height: Double
        /// 上の段（進み具合と名前）の下端
        let headerBottom: Double
        /// 撮影地と曲の行（2つとも出たとき）の上端
        let metaTop: Double
    }

    /// 寸法の組。
    /// - アプリ: 写真の枠は上の安全域まで伸び、下に足元 60pt（`footerHeight`）。上の段は
    ///   安全域＋5＋進み具合3＋間9＋44 ＝ 安全域＋61（SE 81・ノッチ 120。少し余裕を見る）。
    ///   行は `captionBlock` の下の余白（96・ハイライト 150）の上に 12pt の行2つ（約40）
    /// - Web（`StoryViewer.tsx`）: 上の段は pt-2＋安全域＋3＋mb-3＋名前2行（約 39）＝ 安全域＋62。
    ///   行は下から 安全域＋返信の帯 120＋bottom-4＋間8＋曲 36＋間8＋撮影地 28 ＝ 安全域＋216
    static let screens: [Screen] = [
        Screen(name: "アプリ SE", platform: .app, width: 375, height: 607, headerBottom: 84, metaTop: 607 - 96 - 40),
        Screen(name: "アプリ 6.1型", platform: .app, width: 390, height: 750, headerBottom: 124, metaTop: 750 - 96 - 40),
        Screen(name: "アプリ 6.7型", platform: .app, width: 430, height: 838, headerBottom: 124, metaTop: 838 - 96 - 40),
        Screen(name: "アプリ SE ハイライト", platform: .app, width: 375, height: 667, headerBottom: 84, metaTop: 667 - 150 - 40),
        Screen(name: "アプリ 6.1型 ハイライト", platform: .app, width: 390, height: 844, headerBottom: 124, metaTop: 844 - 150 - 40),
        Screen(name: "Web ホーム画面", platform: .web, width: 390, height: 844, headerBottom: 47 + 62, metaTop: 844 - 34 - 216),
        Screen(name: "Web Safari", platform: .web, width: 390, height: 664, headerBottom: 62, metaTop: 664 - 216),
        Screen(name: "Web PC", platform: .web, width: 430, height: 820, headerBottom: 62, metaTop: 820 - 216),
    ]

    // MARK: - 置く

    /// ひとことの文・高さ・大きさを決める。
    /// - Parameter photoAspect: 写真の幅÷高さ。分からなければ `fallbackAspects` の全部で見る
    static func place(caption: String, vote: StoryVoteDraft, photoAspect: Double?) -> Result {
        let aspects = photoAspect.flatMap { $0 > 0 && $0.isFinite ? [$0] : nil } ?? fallbackAspects
        let needed = lineCount(caption, size: size, width: availableWidth(x: x))
        // 入らない・長すぎるときは、入る行数まで切る
        for lines in stride(from: min(needed, maxLines), through: 1, by: -1) {
            if let y = lowestFittingY(lines: lines, size: size, vote: vote, aspects: aspects) {
                return Result(text: truncated(caption, lines: lines, size: size), y: y, size: size)
            }
        }
        // 1行でも入らない（札が絵の大きな部分を覆っている）。1行で、重なりがいちばん小さい高さへ
        var best = (y: 0.2, overlap: Double.infinity)
        for step in stride(from: 940, through: 60, by: -1) {
            let y = Double(step) / 1000
            let amount = overlap(y: y, lines: 1, size: size, vote: vote, aspects: aspects)
            if amount < best.overlap { best = (y, amount) }
        }
        return Result(text: truncated(caption, lines: 1, size: size), y: best.y, size: size)
    }

    /// 下から上へ 0.001 刻みで探し、全部の画面で重ならない最初の高さ（位置は小数3桁で保存される＝
    /// `clampStoryTextPos`）
    static func lowestFittingY(lines: Int, size: Double, vote: StoryVoteDraft, aspects: [Double]) -> Double? {
        for step in stride(from: 940, through: 60, by: -1) {
            let y = Double(step) / 1000
            let ok = screens.allSatisfy { screen in
                aspects.allSatisfy { fits(y: y, lines: lines, size: size, vote: vote, aspect: $0, on: screen) }
            }
            if ok { return y }
        }
        return nil
    }

    /// 1つの画面・1つの縦横比で、ひとことが段・行・札に重ならないか
    static func fits(y: Double, lines: Int, size: Double, vote: StoryVoteDraft, aspect: Double, on screen: Screen) -> Bool {
        let box = self.box(aspect: aspect, on: screen)
        let caption = span(fraction: y, height: captionHeight(lines: lines, size: size, boxWidth: box.width,
                                                              platform: screen.platform), box: box)
        guard caption.top >= screen.headerBottom, caption.bottom <= screen.metaTop else { return false }
        let card = span(fraction: StoryTextItem.clampPosition(vote.y),
                        height: cardHeight(vote, boxWidth: box.width, platform: screen.platform), box: box)
        return caption.bottom + gap <= card.top || caption.top >= card.bottom + gap
    }

    /// 重なっている量の和（pt）。どこにも入らないときに、いちばんましな高さを選ぶため
    static func overlap(y: Double, lines: Int, size: Double, vote: StoryVoteDraft, aspects: [Double]) -> Double {
        var total = 0.0
        for screen in screens {
            for aspect in aspects {
                let box = self.box(aspect: aspect, on: screen)
                let c = span(fraction: y, height: captionHeight(lines: lines, size: size, boxWidth: box.width,
                                                                platform: screen.platform), box: box)
                let k = span(fraction: StoryTextItem.clampPosition(vote.y),
                             height: cardHeight(vote, boxWidth: box.width, platform: screen.platform), box: box)
                total += max(0, screen.headerBottom - c.top) + max(0, c.bottom - screen.metaTop)
                total += max(0, min(c.bottom + gap, k.bottom + gap) - max(c.top, k.top))
            }
        }
        return total
    }

    // MARK: - 寸法

    struct Box { let top: Double; let width: Double; let height: Double }

    /// 絵の矩形。アプリは埋める・Web は収める
    static func box(aspect: Double, on screen: Screen) -> Box {
        let wider = aspect > screen.width / screen.height
        let fillByHeight = screen.platform == .app ? wider : !wider
        let width = fillByHeight ? screen.height * aspect : screen.width
        let height = fillByHeight ? screen.height : screen.width / aspect
        return Box(top: (screen.height - height) / 2, width: width, height: height)
    }

    /// `(x, y)` の割合の点を要素の同じ割合の点に合わせる置き方（`StoryTextItem.guide`・Web の
    /// `translate(-y%)`）での、要素の上端と下端
    static func span(fraction y: Double, height: Double, box: Box) -> (top: Double, bottom: Double) {
        let top = box.top + box.height * y - height * y
        return (top, top + height)
    }

    static func captionHeight(lines: Int, size: Double, boxWidth: Double, platform: Platform) -> Double {
        Double(lines) * (platform == .app ? 1.5 : 1.25) * size * boxWidth
    }

    /// 投票の札の高さ。**本人が見るときの形**（「まだ票はありません」の段まで）で数える
    /// - アプリ（`StoryTextLayer.voteCard`）: 問い（行 1.19）・間 0.4・ボタン（高さ 44 以上）・
    ///   間 0.4・段（0.8 の字）・上下の余白 0.18＋6
    /// - Web（`StoryTextOverlay`）: 余白 0.18em・問い（行 1.25）・間 0.4em・ボタン（0.9em・余白 0.35em）・
    ///   段（0.8em・上 0.4em）
    static func cardHeight(_ vote: StoryVoteDraft, boxWidth: Double, platform: Platform) -> Double {
        let size = StoryTextItem.clampSize(vote.size)
        let f = size * boxWidth
        let q = Double(lineCount(vote.question, size: size, width: availableWidth(x: StoryTextItem.clampPosition(vote.x))))
        switch platform {
        case .app:
            let pill = max(44, 0.9 * f * 1.19 + 2 * 0.35 * 0.9 * f)
            return q * 1.19 * f + 0.4 * f + pill + 0.4 * f + 0.8 * f * 1.19 + 2 * (0.18 * f + 6)
        case .web:
            return 2 * 0.18 * f + q * 1.25 * f + 0.4 * f + (0.9 * 1.25 + 2 * 0.35 * 0.9) * f + (0.8 * 1.25 + 0.4 * 0.8) * f
        }
    }

    /// 折り返す幅（絵の幅に対する割合）。アプリ・Web とも「絵の幅 − 左の位置」、上限 86%
    static func availableWidth(x: Double) -> Double {
        max(0.1, min(0.86, 1 - x))
    }

    // MARK: - 行数

    /// 字の幅（字の大きさを 1 とした幅）。かな・漢字・絵文字は 1、それ以外は 0.62（欧文の
    /// 平均より広めに見る——少なく数えると重なる）
    static func em(_ character: Character) -> Double {
        character.unicodeScalars.contains { $0.value >= 0x1100 } ? 1 : 0.62
    }

    /// 行数の見積もり。欧文は語の切れ目で、かな・漢字は1字ずつ折り返す（長すぎる語は途中で割る＝
    /// Web の `break-words`）
    static func lineCount(_ text: String, size: Double, width: Double) -> Int {
        lines(text, size: size, width: width).count
    }

    /// 行に分けた結果（行ごとの字）
    static func lines(_ text: String, size: Double, width: Double) -> [String] {
        let limit = width / size
        var result: [String] = []
        var line = ""
        var used = 0.0
        func push(_ token: String) {
            let w = token.reduce(0) { $0 + em($1) }
            if used + w <= limit + 1e-9 {
                line += token
                used += w
                return
            }
            if !line.isEmpty {
                result.append(line)
                line = ""
                used = 0
            }
            // 行頭の空白は捨てる
            let body = String(token.drop { $0 == " " })
            let bodyWidth = body.reduce(0) { $0 + em($1) }
            if bodyWidth <= limit + 1e-9 {
                line = body
                used = bodyWidth
                return
            }
            for character in body {
                if used + em(character) > limit + 1e-9, !line.isEmpty {
                    result.append(line)
                    line = ""
                    used = 0
                }
                line.append(character)
                used += em(character)
            }
        }
        for token in tokens(text) { push(token) }
        if !line.isEmpty { result.append(line) }
        return result.isEmpty ? [""] : result
    }

    /// 折り返しの単位。かな・漢字は1字、欧文は語（前の空白ごと）
    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        for character in text {
            if em(character) == 1 {
                if !word.isEmpty { result.append(word); word = "" }
                result.append(String(character))
            } else if character == " " {
                if !word.isEmpty, word.last != " " { result.append(word); word = "" }
                word.append(character)
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { result.append(word) }
        return result
    }

    /// `lines` 行に入るまで切り、「…」を付ける。入るならそのまま
    static func truncated(_ text: String, lines: Int, size: Double) -> String {
        let width = availableWidth(x: x)
        guard lineCount(text, size: size, width: width) > lines else { return text }
        var kept = text
        while !kept.isEmpty {
            kept.removeLast()
            let candidate = kept.trimmingCharacters(in: .whitespaces) + "…"
            if lineCount(candidate, size: size, width: width) <= lines { return candidate }
        }
        return "…"
    }
}
