import XCTest
@testable import JourneyPhoto

/// ストーリーの動画の切り取り（2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾）。
/// 範囲の決まり（最大 60 秒・最短 1 秒・枠が 60 秒を超えたら反対側がついてくる）と、帯の座標、
/// 取り込みで 60 秒超えを断らなくなったこと、書き出しが範囲だけを切る配線。
/// AVFoundation に触る書き出し・再生の本物は Mac の CI と実機で確かめる。
final class StoryVideoTrimTests: XCTestCase {

    // MARK: - 範囲の決まり

    /// 取り込んだ直後: 60 秒以内は全部、長い動画は先頭の 60 秒
    func testInitialRange() {
        let short = StoryVideoTrim(total: 12)
        XCTAssertEqual(short.start, 0)
        XCTAssertEqual(short.end, 12)
        XCTAssertTrue(short.isFull)
        let exactly = StoryVideoTrim(total: 60)
        XCTAssertEqual(exactly.length, 60)
        XCTAssertTrue(exactly.isFull)
        let long = StoryVideoTrim(total: 125)
        XCTAssertEqual(long.start, 0)
        XCTAssertEqual(long.end, 60, "長い動画の初めの範囲が先頭の60秒でない")
        XCTAssertFalse(long.isFull)
    }

    /// 始点を動かして 60 秒を超えたら、終点が引かれてついてくる（枠は最大 60 秒のまま）
    func testMovingStartPullsEndAlong() {
        var trim = StoryVideoTrim(total: 125)            // 0 ... 60
        trim.setStart(10)
        XCTAssertEqual(trim.start, 10)
        XCTAssertEqual(trim.end, 60, "60秒に収まる動きで終点が動いている")
        // 終点を右へ伸ばして 100 にすると、60 秒を超えるので始点が押される
        trim.setEnd(100)
        XCTAssertEqual(trim.end, 100)
        XCTAssertEqual(trim.start, 40, "終点を伸ばしたのに始点が押されない（60秒を超えている）")
        // 始点を左へ戻すと、終点が引かれる
        trim.setStart(5)
        XCTAssertEqual(trim.start, 5)
        XCTAssertEqual(trim.end, 65, "始点を左へ動かしたのに終点が引かれない")
        XCTAssertLessThanOrEqual(trim.length, StoryVideoTrim.maxLength)
    }

    /// 最短 1 秒: つまみどうしは重ならない。両端（0・total）の外へも出ない
    func testMinimumLengthAndBounds() {
        var trim = StoryVideoTrim(total: 30)
        trim.setStart(29.9)
        XCTAssertEqual(trim.start, 29, accuracy: 0.0001, "始点が終点との最短1秒を割っている")
        XCTAssertEqual(trim.length, 1, accuracy: 0.0001)
        trim.setEnd(0)
        XCTAssertEqual(trim.end, trim.start + 1, accuracy: 0.0001, "終点が始点との最短1秒を割っている")
        trim.setStart(-4)
        XCTAssertEqual(trim.start, 0)
        trim.setEnd(500)
        XCTAssertEqual(trim.end, 30, "終点が動画の長さを超えている")
    }

    /// 1 秒より短い動画は、その長さが最短
    func testVeryShortVideo() {
        var trim = StoryVideoTrim(total: 0.5)
        XCTAssertEqual(trim.minimumLength, 0.5)
        trim.setStart(0.3)
        XCTAssertEqual(trim.start, 0)
        XCTAssertEqual(trim.end, 0.5)
    }

    /// 読めなかった動画（長さ 0・NaN）では何も動かない
    func testInvalidValuesAreIgnored() {
        var empty = StoryVideoTrim(total: .nan)
        empty.setStart(3)
        empty.setEnd(9)
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(empty.start, 0)
        XCTAssertEqual(empty.end, 0)
        var trim = StoryVideoTrim(total: 20)
        trim.setStart(.nan)
        trim.setEnd(.infinity)
        XCTAssertEqual(trim.start, 0)
        XCTAssertEqual(trim.end, 20, "NaN で範囲が壊れている（無限大は動画の長さまで）")
    }

    /// −1秒／＋1秒（長い動画の細かい合わせ・読み上げの増減）も同じ決まりを通る
    func testNudgeFollowsTheSameRules() {
        var trim = StoryVideoTrim(total: 125, start: 20, end: 80)
        XCTAssertEqual(trim.length, 60)
        trim.nudgeEnd(by: StoryVideoTrim.nudgeStep)
        XCTAssertEqual(trim.end, 81)
        XCTAssertEqual(trim.start, 21, "＋1秒で60秒を超えたのに始点が押されない")
        trim.nudgeStart(by: -StoryVideoTrim.nudgeStep)
        XCTAssertEqual(trim.start, 20)
        XCTAssertEqual(trim.end, 80, "−1秒で60秒を超えたのに終点が引かれない")
    }

    /// 保存した値から作るときも決まりに収める（始点が先）
    func testInitWithValuesClampsToRules() {
        let a = StoryVideoTrim(total: 125, start: 70, end: 100)
        XCTAssertEqual(a.start, 70, "始点が先の既定の終点（60秒）に引きずられている")
        XCTAssertEqual(a.end, 100)
        let b = StoryVideoTrim(total: 125, start: 10, end: 200)
        XCTAssertEqual(b.start, 10)
        XCTAssertEqual(b.end, 70, "60秒を超える範囲をそのまま持っている")
        let c = StoryVideoTrim(total: 30, start: 40, end: 50)
        XCTAssertEqual(c.start, 29)
        XCTAssertEqual(c.end, 30)
    }

    // MARK: - 帯の座標

    func testPositionAndSecondsRoundTrip() {
        let width: CGFloat = 300
        XCTAssertEqual(StoryVideoTrim.position(of: 0, total: 120, width: width), 0)
        XCTAssertEqual(StoryVideoTrim.position(of: 60, total: 120, width: width), 150)
        XCTAssertEqual(StoryVideoTrim.position(of: 999, total: 120, width: width), 300, "範囲の外を端に寄せていない")
        XCTAssertEqual(StoryVideoTrim.seconds(atPosition: 150, total: 120, width: width), 60, accuracy: 0.0001)
        XCTAssertEqual(StoryVideoTrim.seconds(atPosition: -20, total: 120, width: width), 0)
        XCTAssertEqual(StoryVideoTrim.seconds(atPosition: 900, total: 120, width: width), 120)
        XCTAssertEqual(StoryVideoTrim.position(of: 5, total: 0, width: width), 0)
        XCTAssertEqual(StoryVideoTrim.seconds(atPosition: 5, total: 120, width: 0), 0)
    }

    /// サムネイルは動画全体を等分した各区間の真ん中（0 秒ちょうどの黒い1コマを避ける）
    func testThumbnailTimes() {
        let times = StoryVideoTrim.thumbnailTimes(total: 100, count: 10)
        XCTAssertEqual(times.count, 10)
        XCTAssertEqual(times.first ?? -1, 5, accuracy: 0.0001)
        XCTAssertEqual(times.last ?? -1, 95, accuracy: 0.0001)
        XCTAssertTrue(StoryVideoTrim.thumbnailTimes(total: 0, count: 10).isEmpty)
        XCTAssertTrue(StoryVideoTrim.thumbnailTimes(total: 10, count: 0).isEmpty)
    }

    // MARK: - 取り込みと動画の持ち物

    /// 取り込みでは 60 秒超えを断らない。断るのは読めない動画と、長すぎる元の動画（3 時間）
    func testImportAcceptsLongVideos() {
        XCTAssertNil(StoryVideoRules.importProblem(durationSec: 12))
        XCTAssertNil(StoryVideoRules.importProblem(durationSec: 61), "60秒を超える動画を取り込みで断っている")
        XCTAssertNotNil(StoryVideoRules.importProblem(durationSec: 40 * 60), "数十分の動画を取り込んでいる")
        XCTAssertEqual(StoryVideoRules.maxSourceSeconds, 600)
        XCTAssertEqual(StoryVideoRules.maxSourceBytes, 2 * 1024 * 1024 * 1024)
        XCTAssertEqual(StoryVideoRules.importProblem(durationSec: 30, bytes: StoryVideoRules.maxSourceBytes + 1), .sourceTooLong, "2GB 超えを断らない")
        XCTAssertNil(StoryVideoRules.importProblem(durationSec: 30, bytes: StoryVideoRules.maxSourceBytes))
        XCTAssertEqual(StoryVideoRules.Problem.sourceTooLong.message, "長すぎます。10分までの動画を選んでください")
        XCTAssertFalse(StoryVideoRules.Problem.sourceTooLong.message.contains("捨"))
        XCTAssertNil(StoryVideoRules.importProblem(durationSec: StoryVideoRules.maxSourceSeconds))
        XCTAssertEqual(StoryVideoRules.importProblem(durationSec: StoryVideoRules.maxSourceSeconds + 1), .sourceTooLong)
        XCTAssertEqual(StoryVideoRules.importProblem(durationSec: 0), .unreadable)
        XCTAssertEqual(StoryVideoRules.importProblem(durationSec: nil), .unreadable)
        XCTAssertEqual(StoryVideoRules.importProblem(durationSec: .nan), .unreadable)
        XCTAssertFalse(StoryVideoRules.Problem.sourceTooLong.message.isEmpty)
        // 投稿する長さの確かめは今までどおり（切らずに 60 秒超えを書き出さない）
        XCTAssertEqual(StoryVideoRules.problem(durationSec: 61), .tooLong)
    }

    /// 写す前に確かめる（コピーのあとで断ると、容量と時間を先に食う）
    func testImportChecksBeforeCopying() throws {
        let pipeline = try repo("Sources/JourneyPhoto/Services/StoryVideoPipeline.swift")
        let importing = try XCTUnwrap(pipeline.components(separatedBy: "} importing: { received in").dropFirst().first?
            .components(separatedBy: "return StoryMovieFile(url: copy)").first)
        let check = try XCTUnwrap(importing.range(of: "StoryVideoRules.importProblem(durationSec: length, bytes: bytes)"))
        let copy = try XCTUnwrap(importing.range(of: "copyItem("))
        XCTAssertLessThan(check.lowerBound, copy.lowerBound, "コピーのあとで確かめている")
        XCTAssertTrue(pipeline.contains("} catch let problem as StoryVideoRules.Problem {\n            throw problem"), "断りの理由が「読み込めません」に潰れる")
    }

    func testClipCarriesTheTrim() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        var clip = StoryVideoClip(url: url, durationSec: 125, size: CGSize(width: 1080, height: 1920), bytes: 1)
        XCTAssertEqual(clip.outputSeconds, 60, "長い動画の投稿する長さが先頭の60秒でない")
        XCTAssertTrue(clip.isTrimmed)
        XCTAssertEqual(clip.durationLabel, "1:00")
        clip.trim.setStart(30)
        clip.trim.setEnd(42)
        XCTAssertEqual(clip.outputSeconds, 12)
        XCTAssertEqual(clip.durationLabel, "0:12", "長さの札が切ったあとの長さでない")
        let short = StoryVideoClip(url: url, durationSec: 12, size: .zero, bytes: 1)
        XCTAssertFalse(short.isTrimmed, "切っていない動画が切ってある扱い")
        XCTAssertEqual(short.durationLabel, "0:12")
        XCTAssertNotEqual(clip, short)
    }

    /// 書き出しの段は切ったあとの長さで選ぶ（3 時間の動画でも、残す 20 秒は 1080p から試せる）
    func testLadderUsesTheTrimmedLength() {
        var clip = StoryVideoClip(url: URL(fileURLWithPath: "/tmp/x.mov"), durationSec: 3 * 3600,
                                  size: CGSize(width: 1080, height: 1920), bytes: 1)
        XCTAssertEqual(StoryVideoRules.ladder(durationSec: clip.outputSeconds).first?.preset,
                       "AVAssetExportPreset1280x720", "先頭の60秒は720pから")
        clip.trim.setEnd(120)       // 先頭から 120 秒は 60 秒を超えるので、始点が 60 へ押される
        clip.trim.setStart(100)
        XCTAssertEqual(clip.outputSeconds, 20, accuracy: 0.0001)
        XCTAssertEqual(StoryVideoRules.ladder(durationSec: clip.outputSeconds).first?.preset,
                       "AVAssetExportPreset1920x1080")
        XCTAssertEqual(StoryVideoRules.ladder(durationSec: clip.durationSec).count, 1,
                       "元の長さで段を選ぶと最後の段だけになる（切った長さで選ぶ理由）")
    }

    // MARK: - 配線（ソース）

    private func repo(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 書き出しは範囲だけを切る・取り込みは 60 秒超えを断らない・段は切った長さ
    func testPipelineCutsOnlyTheTrimmedRange() throws {
        let pipeline = try repo("Sources/JourneyPhoto/Services/StoryVideoPipeline.swift")
        XCTAssertTrue(pipeline.contains("StoryVideoRules.importProblem(durationSec: duration)"), "取り込みが 60 秒超えを断っている")
        XCTAssertFalse(pipeline.contains("StoryVideoRules.problem(durationSec: duration)"))
        XCTAssertTrue(pipeline.contains("StoryVideoRules.ladder(durationSec: clip.outputSeconds)"), "段を元の長さで選んでいる")
        XCTAssertTrue(pipeline.contains("composition(for: asset, trim: clip.trim,"), "書き出しに切り取りの範囲を渡していない")
        XCTAssertTrue(pipeline.contains("try video.insertTimeRange(sourceRange, of: sourceVideo, at: .zero)"),
                      "映像を範囲だけ入れていない")
        XCTAssertTrue(pipeline.contains("try audio.insertTimeRange(sourceRange, of: sourceAudio, at: .zero)"),
                      "音声を範囲だけ入れていない")
        XCTAssertTrue(pipeline.contains("let range = CMTimeRange(start: .zero, duration: sourceRange.duration)"),
                      "重ねの指示の範囲が書き出す動画の長さでない（元の長さのままだと黒い尾が残る）")
        // 向き・重ね・位置情報の除去は前のまま
        XCTAssertTrue(pipeline.contains("StoryVideoRules.renderSize(for: oriented, step: step)"))
        XCTAssertTrue(pipeline.contains("session.metadataItemFilter = AVMetadataItemFilter.forSharing()"))
        XCTAssertTrue(pipeline.contains("if await hasLocationMetadata(out)"))
    }

    /// 画面: 長さの札から開く・「…」からも開く・切ったあとで書き出しを確かめる・長い動画は取り込みで開く
    func testComposerWiresTheTrimSheet() throws {
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains(".sheet(isPresented: trimSheetShown, onDismiss: {"))
        XCTAssertTrue(composer.contains("StoryVideoTrimSheet(clip: clip,"))
        XCTAssertTrue(composer.contains("applyTrim(trim, to: id)"))
        XCTAssertTrue(composer.contains("Button { openTrim() } label: {"), "長さの札から切り取りを開けない")
        XCTAssertTrue(composer.contains("systemImage: \"scissors\""), "「…」に切り取りが無い")
        XCTAssertTrue(composer.contains("done.trims[$0.id] == $0.video?.trim"), "切り直しを送る直前に見ていない")
        XCTAssertTrue(composer.contains("done.trims[id] = clip.trim"))
        XCTAssertTrue(composer.contains("imported.clip.durationSec > StoryVideoRules.maxSeconds + 0.5"),
                      "60秒超えの動画で切り取りを開かない")
        XCTAssertTrue(composer.contains("&& trimmingShotId == nil"), "切り取りを開いている間に表示の動画が移る")
        // 当たりは 44
        let badge = try XCTUnwrap(composer.components(separatedBy: "private func videoBadge").dropFirst().first?
            .components(separatedBy: "// MARK: - 動画の切り取り").first)
        XCTAssertTrue(badge.contains(".frame(minHeight: WebTheme.minTapTarget)"))
        XCTAssertTrue(badge.contains(".contentShape(Rectangle())"))
    }

    /// 切り取りの画面: つまみの当たり 44・読み上げの増減・触覚・「−1秒／＋1秒」・固定の文字の大きさなし・黒地の真鍮
    func testTrimSheetAccessibilityAndTargets() throws {
        let view = try repo("Sources/JourneyPhoto/Features/Stories/StoryVideoTrimView.swift")
        XCTAssertTrue(view.contains(".accessibilityAdjustableAction"), "つまみが読み上げで動かせない")
        XCTAssertTrue(view.contains("let hit: CGFloat = WebTheme.minTapTarget"), "つまみの当たりが 44 でない")
        XCTAssertTrue(view.contains(".sensoryFeedback(.selection, trigger: grabTick)"))
        XCTAssertTrue(view.contains(".sensoryFeedback(.impact(weight: .medium), trigger: limitTick)"))
        XCTAssertTrue(view.contains("stepButton(symbol: \"minus\""))
        XCTAssertTrue(view.contains("stepButton(symbol: \"plus\""))
        XCTAssertTrue(view.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"))
        XCTAssertFalse(view.contains(".system(size:"), "固定の大きさの文字（Dynamic Type に付いてこない）")
        XCTAssertTrue(view.contains(".fill(Color.white)"), "つまみが白でない（サムネイルの上に真鍮を置いている）")
        XCTAssertTrue(view.contains("Rectangle().strokeBorder(Color.white, lineWidth: 2)"), "範囲の枠が白でない")
        XCTAssertFalse(view.contains("strokeBorder(WebTheme.accent"))
        XCTAssertFalse(view.contains("捨"))
        // 始点を動かしている間は再生を止めてその時刻の絵を出し、離したら範囲の頭から
        XCTAssertTrue(view.contains("playback.show(at:"))
        XCTAssertTrue(view.contains("playback.setRange(start: trim.start, end: trim.end, playing: resumeAfterDrag)"))
        // 画面が消えたら見張りを外す
        XCTAssertTrue(view.contains(".onDisappear { playback.stop() }"))
    }
}
