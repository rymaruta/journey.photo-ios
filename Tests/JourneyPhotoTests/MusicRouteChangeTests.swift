import XCTest
@testable import JourneyPhoto

/// 曲の試聴: イヤホンを抜いた・Bluetooth が切れたとき、状態を「一時停止」に揃える（2026-11-07）。
/// OS はプレイヤーを止めるが中断の通知は来ないので、「再生中」のまま残っていた
final class MusicRouteChangeTests: XCTestCase {

    /// 前の出口が無くなった(2)だけ止める。`pausesOnRouteChange` が常に false だと落ちる
    func testOnlyOldDeviceUnavailablePauses() {
        XCTAssertTrue(MusicPreviewPlayer.pausesOnRouteChange(reason: 2), "イヤホンを抜いても止まらない")
        // 1 = 新しい出口がつながった・3 = カテゴリの変更・4 = 上書き・8 = 起動時… は止めない
        for reason: UInt in [0, 1, 3, 4, 5, 6, 7, 8] {
            XCTAssertFalse(MusicPreviewPlayer.pausesOnRouteChange(reason: reason), "理由 \(reason) で止めた")
        }
        XCTAssertFalse(MusicPreviewPlayer.pausesOnRouteChange(reason: nil))
    }

    /// 見張りは出口の変化の通知に結んである(結びを外すと、状態が再生中のまま残る)
    func testPlayerObservesRouteChangeNotification() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Common/MusicPreviewPlayer.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("AVAudioSession.routeChangeNotification"))
        XCTAssertTrue(source.contains("pausesOnRouteChange(reason: reason)"))
    }
}
