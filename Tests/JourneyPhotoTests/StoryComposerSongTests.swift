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

    func testLoopEnd() {
        XCTAssertEqual(MusicPreviewPlayer.loopEnd(loops: true, start: 10, length: 5), 15)
        XCTAssertNil(MusicPreviewPlayer.loopEnd(loops: true, start: 0, length: nil), "幅が無ければ試聴の終わりまで")
        XCTAssertNil(MusicPreviewPlayer.loopEnd(loops: false, start: 0, length: 5), "繰り返さないなら区切らない")
        XCTAssertNil(MusicPreviewPlayer.loopEnd(loops: true, start: 0, length: 0))
    }

    /// 繰り返しを実際に仕掛ける: 項目の終わり（`forwardPlaybackEndTime`）を流し始め＋表示秒数にする。
    /// そこで鳴り終わりの知らせが来て、流し始めへ戻る
    func testPlaySetsItemEndAtWindow() throws {
        let owner = StoryComposerSong.Owner()
        let cue = try XCTUnwrap(StoryComposerSong.cue(song: song(start: 10), durationSec: 5))
        owner.play(cue)
        defer { owner.stop() }
        let item = try XCTUnwrap(MusicPreviewPlayer.shared.currentItem)
        XCTAssertEqual(item.forwardPlaybackEndTime.seconds, 15)
        XCTAssertNil(MusicPreviewPlayer.shared.playingSong, "全体の再生器（MiniPlayerBar）に出る")
        // 鳴り終わりの知らせで止まらない（繰り返す）
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        XCTAssertTrue(owner.owns)
    }

    // MARK: - 鳴らした回の係

    /// 開いたときにほかで鳴っている曲（BGM の試聴など）を止める。自分の回は止めない
    func testStopOthersOnOpen() throws {
        let player = MusicPreviewPlayer.shared
        let owner = StoryComposerSong.Owner()
        player.play(URL(fileURLWithPath: "/nonexistent/bgm.m4a"))
        owner.stopOthers()
        XCTAssertNil(player.playingURL, "前から鳴っていた曲が付けた曲と重なる")
        owner.play(try XCTUnwrap(StoryComposerSong.cue(song: song(), durationSec: 5)))
        owner.stopOthers()
        XCTAssertTrue(owner.owns, "カメラから戻ったときに自分の曲まで止めた")
        owner.stop()
    }

    /// 自分の回だけ止める。ほかの画面が鳴らし直した曲は止めない
    func testOwnerStopsOnlyOwnSession() throws {
        let player = MusicPreviewPlayer.shared
        let owner = StoryComposerSong.Owner()
        owner.play(try XCTUnwrap(StoryComposerSong.cue(song: song(), durationSec: 5)))
        player.play(URL(fileURLWithPath: "/nonexistent/other.m4a"), origin: .songPicker)
        owner.stop()
        XCTAssertNotNil(player.playingURL)
        player.stop()
    }

    /// 係が消えたら（カメラを開いたまま作る画面ごと閉じられた）自分の回を止める
    func testOwnerStopsWhenReleased() throws {
        var owner: StoryComposerSong.Owner? = StoryComposerSong.Owner()
        owner?.play(try XCTUnwrap(StoryComposerSong.cue(song: song(), durationSec: 5)))
        XCTAssertNotNil(MusicPreviewPlayer.shared.playingURL)
        owner = nil
        XCTAssertNil(MusicPreviewPlayer.shared.playingURL, "画面が消えても鳴り残る")
    }

    // MARK: - 画面のつなぎ

    private func body(of name: String, in view: String) throws -> Substring {
        let start = try XCTUnwrap(view.range(of: name))
        return view[start.upperBound...].prefix { $0 != "}" }
    }

    /// 作る画面が決まりを使い、覆い・写真が無い間・裏では止め、閉じたら止める（カメラを開いたときは止めない）
    func testComposerWiresSongPlayback() throws {
        let view = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(view.contains("StoryComposerSong.action("), "作る画面が曲を鳴らしていない")
        XCTAssertTrue(view.contains("@StateObject private var songOwner = StoryComposerSong.Owner()"))
        XCTAssertTrue(view.contains("case .play(let cue): songOwner.play(cue)"))
        XCTAssertTrue(view.contains(".onChange(of: songCue)"), "曲を替えても流し直さない")
        XCTAssertTrue(view.contains(".onChange(of: songHeldOnScreen)"), "シートで覆っても止まらない")
        XCTAssertTrue(view.contains("syncSong(foreground: phase == .active)"), "裏に回っても止まらない")
        XCTAssertTrue(view.contains("songOwner.stopOthers()"), "開いたときにほかの曲を止めていない")
        // 覆いの中身（シート・カメラ・写真選び）
        let covered = try body(of: "private var songAudioCovered: Bool {", in: view)
        for flag in ["showAudience", "showStickerTray", "showSongPicker", "showSongStart", "showCamera", "showLibrary"] {
            XCTAssertTrue(covered.contains(flag), "\(flag) で覆っても曲が止まらない")
        }
        let held = try body(of: "private var songHeldOnScreen: Bool {", in: view)
        XCTAssertTrue(held.contains("songAudioCovered") && held.contains("shots.isEmpty"),
                      "写真を全部外して写真選びの段に戻っても鳴り続ける")
        let syncBody = try XCTUnwrap(view.range(of: "private func syncSong(")).upperBound
        XCTAssertTrue(view[syncBody...].prefix(300).contains("songHeldOnScreen"))
        let disappear = try XCTUnwrap(view.range(of: ".onDisappear {"))
        XCTAssertTrue(view[disappear.upperBound...].prefix(400).contains("if !showCamera { songOwner.stop() }"),
                      "閉じても鳴り続ける・カメラを開くと止まって頭から流れ直す")
    }
}
