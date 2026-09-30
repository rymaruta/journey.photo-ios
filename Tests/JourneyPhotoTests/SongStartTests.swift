import XCTest
@testable import JourneyPhoto

/// ストーリーの曲の流し始め（`startSec`）を**作る側で選ぶ**（`SongStartSheet`）。
/// 丸めはサーバー（`stories.ts`）と同じ、送る形に入ること
final class SongStartTests: XCTestCase {

    private let song = Photo.Song(title: "港", artist: "歌い手", artwork: "https://a.example/a.jpg",
                                  previewUrl: "https://p.example/p.m4a", trackUrl: "https://t.example/t")

    /// 流し始めだけを入れ替える（題・歌い手・試聴は同じ）。丸めはサーバーと同じ
    func testStartingKeepsTheSongAndClampsLikeTheServer() {
        let started = song.starting(at: 12, window: 5)
        XCTAssertEqual(started.startSec, 12)
        XCTAssertEqual(started.title, song.title)
        XCTAssertEqual(started.artist, song.artist)
        XCTAssertEqual(started.artwork, song.artwork)
        XCTAssertEqual(started.previewUrl, song.previewUrl)
        XCTAssertEqual(started.trackUrl, song.trackUrl)
        XCTAssertNil(song.starting(at: 0, window: 5).startSec, "頭からは「無し」")
        XCTAssertEqual(song.starting(at: 40, window: 5).startSec, 25)
        XCTAssertEqual(song.starting(at: 12.6, window: 5).startSec, 13)
        XCTAssertNil(started.starting(at: nil, window: 5).startSec, "頭へ戻せる")
    }

    /// 送る形に入る（`POST /stories` の `song.startSec`）。頭からなら書かない
    func testStartIsSentWithTheSong() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(song.starting(at: 12, window: 5))) as? [String: Any]
        XCTAssertEqual(body?["startSec"] as? Int, 12)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(song.starting(at: 0, window: 5))) as? [String: Any]
        XCTAssertNil(plain?["startSec"])
    }

    /// 下書きにも残る（曲ごと `Codable`）
    func testStartSurvivesTheDraftRoundTrip() throws {
        let back = try JSONDecoder().decode(Photo.Song.self, from: JSONEncoder().encode(song.starting(at: 7, window: 5)))
        XCTAssertEqual(back.startSec, 7)
    }

    func testStartLabel() {
        XCTAssertEqual(Photo.Song.startLabel(nil), L("頭から", "From the start"))
        XCTAssertEqual(Photo.Song.startLabel(0), L("頭から", "From the start"))
        XCTAssertEqual(Photo.Song.startLabel(12), L("0:12 から", "From 0:12"))
        XCTAssertEqual(Photo.Song.startLabel(5), L("0:05 から", "From 0:05"))
    }

    /// 🔴 **表示秒数ぶんが試聴の中に収まる所まで**（Web の `maxSongStart` = 30 − 表示秒数）。
    /// 越えると、見る人には試聴の終わりの数秒がくり返し鳴った（841b917 のレビュー）
    func testStartLeavesRoomForTheDisplayTime() {
        XCTAssertEqual(Photo.Song.maxStart(window: 5), 25)
        XCTAssertEqual(Photo.Song.maxStart(window: 15), 15)
        XCTAssertEqual(Photo.Song.maxStart(window: 40), 0)
        XCTAssertEqual(song.starting(at: 29, window: 5).startSec, 25)
        XCTAssertEqual(song.starting(at: 29, window: 15).startSec, 15)
        XCTAssertEqual(song.starting(at: 10, window: 15).startSec, 10)
        for window in StoryService.durationRange {
            let start = song.starting(at: 29, window: window).startSec ?? 0
            XCTAssertLessThanOrEqual(start + window, Photo.Song.previewSeconds, "\(window)秒")
        }
    }

    /// 下書きを戻す・表示秒数を延ばすときに通す。**収まっていればそのまま**
    /// （同じ値＝閉じるときに「変更あり」を作らない）。越えていれば上限まで引き戻す
    func testFittingOnlyPullsBackWhatDoesNotFit() {
        let late = Photo.Song(title: "港", artist: nil, artwork: nil, previewUrl: "https://p.example/p.m4a",
                              trackUrl: nil, startSec: 29)
        XCTAssertEqual(late.fitting(window: 5).startSec, 25)
        XCTAssertEqual(late.fitting(window: 10).startSec, 20)
        let fine = song.starting(at: 12, window: 5)
        XCTAssertEqual(fine.fitting(window: 15), fine)
        XCTAssertEqual(song.fitting(window: 15), song)
    }
}
