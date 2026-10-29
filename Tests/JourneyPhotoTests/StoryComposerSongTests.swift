import XCTest
@testable import JourneyPhoto

/// ストーリーを作る画面で、付けた曲をその場で流す（Issue #403・owner「インスタみたいにこの時点で流れるように」）。
/// 音は模型なので鳴らない——見るのは「いつ鳴らす・止める・流し直すか」の決まりと、画面がそれを使っていること
final class StoryComposerSongTests: XCTestCase {

    private func song(start: Int? = nil, preview: String = "https://audio-ssl.itunes.apple.com/a.m4a") -> Photo.Song {
        Photo.Song(title: "曲", artist: "歌手", artwork: nil, previewUrl: preview, trackUrl: nil, startSec: start)
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 鳴らす中身

    /// 流し始めから、表示秒数ぶん（見る人に流れる部分と同じ）
    func testCueIsStartPlusDuration() throws {
        let cue = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 12), durationSec: 10))
        XCTAssertEqual(cue.start, 12)
        XCTAssertEqual(cue.length, 10)
        XCTAssertEqual(cue.url.host, "audio-ssl.itunes.apple.com")
    }

    /// 流し始めが表示秒数に収まらないときは、送る値（`fitting`）と同じ所まで引き戻す
    func testCueStartFitsWindow() throws {
        let cue = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 29), durationSec: 15))
        XCTAssertEqual(cue.start, Double(Photo.Song.maxStart(window: 15)))
    }

    /// 曲が無い・試聴の URL が読めない・配信元が試聴のホストでない → 黙って鳴らさない
    func testNoCueForMissingOrForeignPreview() {
        XCTAssertNil(StoryComposerSong.cue(song: nil, durationSec: 5))
        XCTAssertNil(StoryComposerSong.cue(song: song(preview: ""), durationSec: 5))
        XCTAssertNil(StoryComposerSong.cue(song: song(preview: "https://evil.example.com/a.m4a"), durationSec: 5))
        XCTAssertNil(StoryComposerSong.cue(song: song(preview: "http://audio-ssl.itunes.apple.com/a.m4a"), durationSec: 5))
    }

    // MARK: - いつ鳴らす・止めるか

    func testAttachPlaysFromStart() throws {
        let cue = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 3), durationSec: 5))
        XCTAssertEqual(StoryComposerSong.action(cue: cue, played: nil, owns: false, paused: false, held: false),
                       .play(cue))
    }

    /// 替えた・流し始めを直した・表示秒数を直した → 鳴っていても流し直す
    func testChangedCueReplays() throws {
        let old = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 3), durationSec: 5))
        let moved = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 8), durationSec: 5))
        let longer = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 3), durationSec: 10))
        XCTAssertEqual(StoryComposerSong.action(cue: moved, played: old, owns: true, paused: false, held: false),
                       .play(moved))
        XCTAssertEqual(StoryComposerSong.action(cue: longer, played: old, owns: true, paused: false, held: false),
                       .play(longer))
        XCTAssertEqual(StoryComposerSong.action(cue: old, played: old, owns: true, paused: false, held: false),
                       .none, "同じ中身で鳴っていれば何もしない（頭へ戻さない）")
    }

    /// 外した → 自分の回だけ止める（ほかの画面が鳴らした曲は止めない）
    func testRemoveStopsOnlyOwnSong() throws {
        let cue = try XCTUnwrap(StoryComposerSong.cue(song: song(), durationSec: 5))
        XCTAssertEqual(StoryComposerSong.action(cue: nil, played: cue, owns: true, paused: false, held: false), .stop)
        XCTAssertEqual(StoryComposerSong.action(cue: nil, played: cue, owns: false, paused: false, held: false), .none)
    }

    /// 覆われた・裏に回った → 一時停止。覆いの間は鳴らし始めない
    func testHeldPauses() throws {
        let cue = try XCTUnwrap(StoryComposerSong.cue(song: song(), durationSec: 5))
        XCTAssertEqual(StoryComposerSong.action(cue: cue, played: cue, owns: true, paused: false, held: true), .pause)
        XCTAssertEqual(StoryComposerSong.action(cue: cue, played: cue, owns: true, paused: true, held: true), .none)
        XCTAssertEqual(StoryComposerSong.action(cue: cue, played: nil, owns: false, paused: false, held: true), .none,
                       "曲選び・流し始めのシートの試し聴きを横取りしない")
    }

    /// 覆いが外れた → まだ自分の回なら続きから。シートの試し聴きに替わっていたら流し始めから
    func testUncoverResumesOrReplays() throws {
        let cue = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 4), durationSec: 5))
        XCTAssertEqual(StoryComposerSong.action(cue: cue, played: cue, owns: true, paused: true, held: false), .resume)
        XCTAssertEqual(StoryComposerSong.action(cue: cue, played: cue, owns: false, paused: false, held: false),
                       .play(cue))
    }

    // MARK: - 繰り返す幅

    func testLoopsBackAtWindowEnd() {
        XCTAssertFalse(MusicPreviewPlayer.loopsBack(current: 14.9, start: 10, length: 5))
        XCTAssertTrue(MusicPreviewPlayer.loopsBack(current: 15, start: 10, length: 5))
        XCTAssertFalse(MusicPreviewPlayer.loopsBack(current: 29, start: 0, length: nil), "幅が無ければ試聴の終わりまで")
        XCTAssertFalse(MusicPreviewPlayer.loopsBack(current: .nan, start: 0, length: 5))
    }

    // MARK: - 画面のつなぎ

    /// 作る画面が決まりを使い、全体の再生器に出さず（`song: nil`）、幅を渡して繰り返し、閉じたら止める
    func testComposerWiresSongPlayback() throws {
        let view = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(view.contains("StoryComposerSong.action("), "作る画面が曲を鳴らしていない")
        XCTAssertTrue(view.contains("player.play(cue.url, song: nil, loops: true, from: cue.start, length: cue.length)"),
                      "流し始めから表示秒数ぶんを繰り返していない・全体の再生器に出る")
        XCTAssertTrue(view.contains(".onChange(of: songCue)"), "曲を替えても流し直さない")
        XCTAssertTrue(view.contains(".onChange(of: songAudioCovered)"), "シートで覆っても止まらない")
        XCTAssertTrue(view.contains("syncSong(foreground: phase == .active)"), "裏に回っても止まらない")
        let disappear = try XCTUnwrap(view.range(of: ".onDisappear {"))
        XCTAssertTrue(view[disappear.upperBound...].prefix(300).contains("stopSong()"), "閉じても鳴り続ける")
    }
}
