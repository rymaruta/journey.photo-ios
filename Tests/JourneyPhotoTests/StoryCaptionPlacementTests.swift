import XCTest
@testable import JourneyPhoto

/// 投票＋ひとこと＋撮影地（または曲）の1本で、ひとことが**撮影地・曲の行、投票の札、上の段**に
/// 重ならないこと（fe1bcf4 のレビュー 🔴1）。
///
/// 決まりの側（`StoryCaptionPlacement.screens`）の寸法表は使わず、**見る画面をここで別に書き起こす**。
/// 条件はレビューで挙がったもの全部:
/// - ひとことの行数 1〜3（それより長い文は3行まで切る）
/// - 絵の敷き方（アプリは埋める＝横長の写真は絵の幅が画面の2倍を超える・Web は収める）
/// - ハイライト（下の余白 150）を SE で見る
/// - 投票の札の高さ（本人が見るときの段まで）
/// - Web の行の高さ 1.25（アプリの明朝は 1.5 で見る）
/// - 字は明朝の下限（18pt・デザインの板）を割らない
final class StoryCaptionPlacementTests: XCTestCase {

    private enum Kind { case app, web }

    /// 見る画面。座標は写真の枠の左上から
    private struct Viewer {
        let name: String
        let kind: Kind
        let w: Double, h: Double
        /// 上の段の下端（アプリ: 安全域＋5＋3＋9＋44・Web: pt-2＋安全域＋3＋mb-3＋名前2行）
        let top: Double
        /// 下の余白（アプリ: `captionBlock` の 96・ハイライト 150／Web: 安全域＋返信の帯 120＋bottom-4）
        let bottomPadding: Double
        /// 撮影地と曲の行の高さの和（アプリ 12pt×2＋間8・Web チップ 28＋36＋間 8×2）
        let metaHeight: Double
        var metaTop: Double { h - bottomPadding - metaHeight }
    }

    private let viewers: [Viewer] = [
        Viewer(name: "SE", kind: .app, w: 375, h: 667 - 60, top: 20 + 61, bottomPadding: 96, metaHeight: 38),
        Viewer(name: "6.1型", kind: .app, w: 390, h: 844 - 34 - 60, top: 59 + 61, bottomPadding: 96, metaHeight: 38),
        Viewer(name: "SE ハイライト", kind: .app, w: 375, h: 667, top: 20 + 61, bottomPadding: 150, metaHeight: 38),
        Viewer(name: "6.1型 ハイライト", kind: .app, w: 390, h: 844, top: 59 + 61, bottomPadding: 150, metaHeight: 38),
        Viewer(name: "6.7型", kind: .app, w: 430, h: 932 - 34 - 60, top: 59 + 61, bottomPadding: 96, metaHeight: 38),
        Viewer(name: "Web ホーム画面", kind: .web, w: 390, h: 844, top: 47 + 62, bottomPadding: 34 + 120 + 16, metaHeight: 28 + 36 + 16),
        Viewer(name: "Web Safari", kind: .web, w: 390, h: 664, top: 62, bottomPadding: 120 + 16, metaHeight: 28 + 36 + 16),
    ]

    /// 絵の矩形（上端・幅・高さ）。アプリは埋める・Web は収める
    private func box(_ aspect: Double, _ v: Viewer) -> (top: Double, w: Double, h: Double) {
        let height = v.kind == .app ? max(v.w / aspect, v.h) : min(v.w / aspect, v.h)
        return ((v.h - height) / 2, height * aspect, height)
    }

    /// y の割合の点を要素の同じ割合の点に合わせたときの上端・下端
    private func span(_ y: Double, _ height: Double, _ b: (top: Double, w: Double, h: Double)) -> (top: Double, bottom: Double) {
        let top = b.top + b.h * y - height * y
        return (top, top + height)
    }

    /// 札の高さ（本人が見る形）。アプリ `voteCard`・Web `StoryTextOverlay` を読んで写した
    private func card(_ vote: StoryVoteDraft, _ kind: Kind, boxWidth: Double) -> Double {
        let f = vote.size * boxWidth
        let q = Double(StoryCaptionPlacement.lineCount(vote.question, size: vote.size, width: min(0.86, 1 - vote.x)))
        switch kind {
        case .app:
            return q * 1.19 * f + 0.4 * f + max(44, 1.07 * f + 0.63 * f) + 0.4 * f + 0.95 * f + 0.36 * f + 12
        case .web:
            return 0.36 * f + q * 1.25 * f + 0.4 * f + 1.76 * f + 1.32 * f
        }
    }

    private func assertClear(_ caption: String, vote: StoryVoteDraft, aspect: Double,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let list = try XCTUnwrap(StoryPostText.list(vote: vote, caption: caption, hasMetaLine: true, photoAspect: aspect))
        let text = try XCTUnwrap(list[0].text)
        let y = list[0].y, size = list[0].size
        let lines = StoryCaptionPlacement.lineCount(text, size: size, width: 0.5)
        XCTAssertLessThanOrEqual(lines, 3, "3行まで", file: file, line: line)
        XCTAssertTrue(text == caption || text.hasSuffix("…"), "切るなら「…」: \(text)", file: file, line: line)
        for v in viewers {
            let b = box(aspect, v)
            let label = "\(v.name)・比 \(aspect)・投票 y=\(vote.y) \(vote.question.count)字・ひとこと \(caption.count)字 → y=\(y) 大きさ \(size) \(lines)行"
            // ひとことは明朝。**明朝の下限は 18**（デザインの板「02 書体」）
            XCTAssertGreaterThanOrEqual(size * b.w, 18, "明朝の下限 18pt: \(label)", file: file, line: line)
            let c = span(y, Double(lines) * (v.kind == .app ? 1.5 : 1.25) * size * b.w, b)
            XCTAssertGreaterThanOrEqual(c.top, v.top, "上の段に重なる: \(label)", file: file, line: line)
            XCTAssertLessThanOrEqual(c.bottom, v.metaTop, "撮影地・曲の行に重なる: \(label)", file: file, line: line)
            let k = span(vote.y, card(vote, v.kind, boxWidth: b.w), b)
            XCTAssertTrue(c.bottom <= k.top || c.top >= k.bottom, "投票の札に重なる: \(label)", file: file, line: line)
        }
    }

    private let captions = [
        "港",
        "夕方の港、風が気持ちいい。",                                         // 2行
        "夕方の港で船を見ていた。風が気持ちよくて、ずっと",                     // 3行
        String(repeating: "旅の途中で見つけた小さな港町の夕暮れ。", count: 10),   // 190字（切る）
        "Sunset at the old harbor, the wind feels great",
    ]

    /// 🔴 レビューの条件の組を全部回す（縦 9:16・3:4・正方形・横 4:3 × 投票の高さ × 問いの長さ × ひとことの長さ）
    func testCaptionClearsTheMetaLineTheCardAndTheHeader() throws {
        for aspect in [9.0 / 16, 3.0 / 4, 1, 4.0 / 3] {
            for voteY in [0.06, 0.3, 0.5, 0.7, 0.94] {
                for question in ["この景色、好き？", "この港の夕暮れ、あなたならどっちを選ぶ？"] {
                    var vote = StoryVoteDraft.new()
                    vote.y = voteY
                    vote.question = question
                    for caption in captions {
                        try assertClear(caption, vote: vote, aspect: aspect)
                    }
                }
            }
        }
    }

    /// レビューで名指しされた組: SE のハイライトで1行（札が上半分＝ひとことは下へ。
    /// 前の決まりの 0.72 はここで撮影地・曲の行に重なった）
    func testHighlightOnSmallPhone() throws {
        var vote = StoryVoteDraft.new()
        vote.y = 0.3
        try assertClear("港", vote: vote, aspect: 9.0 / 16)
        try assertClear("港", vote: vote, aspect: 3.0 / 4)
    }

    /// 入る長さは切らない（3行のひとこと・既定の投票・縦の写真）
    func testFittingCaptionIsNotCut() throws {
        let list = try XCTUnwrap(StoryPostText.list(vote: .new(), caption: captions[2], hasMetaLine: true,
                                                    photoAspect: 3.0 / 4))
        XCTAssertEqual(list[0].text, captions[2])
    }

    /// 写真の縦横比が分からないときは、縦・横のどれでも重ならない所に置く
    func testUnknownAspectIsSafeForAllShapes() throws {
        let caption = "夕方の港、風が気持ちいい。"
        let list = try XCTUnwrap(StoryPostText.list(vote: .new(), caption: caption, hasMetaLine: true))
        let placed = list[0]
        let lines = StoryCaptionPlacement.lineCount(try XCTUnwrap(placed.text), size: placed.size, width: 0.5)
        for aspect in StoryCaptionPlacement.fallbackAspects {
            for screen in StoryCaptionPlacement.screens {
                XCTAssertTrue(StoryCaptionPlacement.fits(y: placed.y, lines: lines, size: placed.size, vote: .new(),
                                                         aspect: aspect, on: screen), "\(screen.name)・比 \(aspect)")
            }
        }
    }

    /// 行が無ければこれまでどおり（0.86・5%・切らない）
    func testNoMetaLineKeepsTheOldPlace() throws {
        let long = captions[3]
        let caption = try XCTUnwrap(StoryPostText.list(vote: .new(), caption: long))[0]
        XCTAssertEqual(caption.y, 0.86)
        XCTAssertEqual(caption.size, 0.05)
        XCTAssertEqual(caption.text, long)
    }

    /// 行数の見積もり: 真ん中に置いた 5% の字は1行に10字
    func testLineCount() {
        XCTAssertEqual(StoryCaptionPlacement.lineCount(String(repeating: "あ", count: 10), size: 0.05, width: 0.5), 1)
        XCTAssertEqual(StoryCaptionPlacement.lineCount(String(repeating: "あ", count: 11), size: 0.05, width: 0.5), 2)
        // 欧文は語の切れ目で折る（語を割らない）
        XCTAssertEqual(StoryCaptionPlacement.lines("aaaa bbbbbbbbbbbb", size: 0.05, width: 0.5),
                       ["aaaa", "bbbbbbbbbbbb"])
    }

    /// ⚪5 動画の撮影地はサーバーが捨てる（`stories.ts`）。行が出るのは曲か、写真の撮影地
    func testMetaLineOnlyWhenTheViewerShowsIt() {
        XCTAssertFalse(StoryPostText.hasMetaLine(isVideo: true, place: "横浜", hasSong: false))
        XCTAssertTrue(StoryPostText.hasMetaLine(isVideo: true, place: "横浜", hasSong: true))
        XCTAssertTrue(StoryPostText.hasMetaLine(isVideo: false, place: "横浜", hasSong: false))
        XCTAssertFalse(StoryPostText.hasMetaLine(isVideo: false, place: "  ", hasSong: false))
    }
}
