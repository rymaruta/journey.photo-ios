import XCTest
@testable import JourneyPhoto

/// 試聴の再生器（`MusicPreviewPlayer`）の状態。音は模型なので鳴らない——
/// 見るのは「再生中の表示」と「自分が鳴らした回か」の決まりだけ
final class MusicPreviewPlayerTests: XCTestCase {

    private let url = URL(string: "https://audio-ssl.itunes.apple.com/a.m4a")!

    override func tearDown() {
        MusicPreviewPlayer.shared.stop(releaseSession: false)
        super.tearDown()
    }

    /// 鳴らすたびに回の番号が進む（同じ曲でも。前の画面の後始末が新しい方を止めない）
    func testSessionAdvancesOnEveryPlay() {
        let player = MusicPreviewPlayer.shared
        let first = player.play(url)
        let second = player.play(url)
        XCTAssertGreaterThan(second, first)
    }

    /// 一時停止中は「再生中」と言わない（ほかの画面の ▶ が ⏸ のままになる）
    func testPausedIsNotPlaying() {
        let player = MusicPreviewPlayer.shared
        player.play(url)
        XCTAssertTrue(player.isPlaying(url))
        player.pause()
        XCTAssertFalse(player.isPlaying(url))
        player.resume()
        XCTAssertTrue(player.isPlaying(url))
    }

    /// 一時停止中の同じ曲の ▶ を押したら鳴らす（止めると押しても何も起きない）
    func testToggleWhilePausedPlays() {
        let player = MusicPreviewPlayer.shared
        let before = player.play(url)
        player.pause()
        player.toggle(url)
        XCTAssertTrue(player.isPlaying(url))
        XCTAssertGreaterThan(player.session, before, "利用者の曲として鳴らし直す")
        player.toggle(url)
        XCTAssertFalse(player.isPlaying(url), "鳴っているときは止める")
    }
}
