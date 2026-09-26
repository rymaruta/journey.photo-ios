import XCTest
@testable import JourneyPhoto

/// 試聴の再生器（`MusicPreviewPlayer`）の状態。音は模型なので鳴らない——
/// 見るのは「再生中の表示」と「自分が鳴らした回か」の決まりだけ
final class MusicPreviewPlayerTests: XCTestCase {

    /// 通信しない URL（シミュレータで本物の AVPlayer が読みに行かないように）
    private let url = URL(fileURLWithPath: "/nonexistent/a.m4a")
    private let tokens = [UUID(), UUID()]

    override func tearDown() {
        let player = MusicPreviewPlayer.shared
        player.stop(releaseSession: false)
        for token in tokens { player.endStoryViewing(token) }
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

    /// 閲覧画面が開いている間は場を返さない（動画の音を切らない）。返すのは
    /// **最後の1つ**が閉じたとき——作り直しで新旧が前後しても崩れない
    func testSessionIsReleasedOnlyAfterLastViewerCloses() {
        let player = MusicPreviewPlayer.shared
        let (old, new) = (tokens[0], tokens[1])
        player.beginStoryViewing(old)
        player.play(url)
        player.stop()
        XCTAssertFalse(player.hasPendingRelease, "開いている間は返す予約を入れない")

        // 作り直し: 新しい画面が先に開き、古い画面があとで閉じる
        player.beginStoryViewing(new)
        player.endStoryViewing(old)
        XCTAssertFalse(player.hasPendingRelease, "まだ1つ開いている")

        player.endStoryViewing(new)
        XCTAssertTrue(player.hasPendingRelease, "最後が閉じたら返す")
    }

    /// onAppear が2回来ても数がずれない（ずれると永久に場を返さない）
    func testRepeatedAppearDoesNotLeakViewer() {
        let player = MusicPreviewPlayer.shared
        let token = tokens[0]
        player.beginStoryViewing(token)
        player.beginStoryViewing(token)
        player.endStoryViewing(token)
        XCTAssertEqual(player.activeStoryViewers, 0)
        XCTAssertTrue(player.hasPendingRelease)
    }

    /// 開いたら、直前に止めた曲の返す予約を取り消す
    func testOpeningViewerCancelsPendingRelease() {
        let player = MusicPreviewPlayer.shared
        player.play(url)
        player.stop()
        XCTAssertTrue(player.hasPendingRelease)
        player.beginStoryViewing(tokens[0])
        XCTAssertFalse(player.hasPendingRelease)
        player.endStoryViewing(tokens[0])
        XCTAssertTrue(player.hasPendingRelease, "持ったままの場は閉じたときに返す")
    }
}
