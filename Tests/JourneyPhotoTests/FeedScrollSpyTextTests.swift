import XCTest
@testable import JourneyPhoto

/// ホームの縦の送りの事実取り（`FeedScrollSpy`・2026-11-13 run 1230）が書く、呼び出しの並びの短い形
final class FeedScrollSpyTextTests: XCTestCase {

    func testFrameKeepsLibraryAndName() {
        XCTAssertEqual(FeedScrollSpyText.frame("3   UIKitCore                           0x00000001854b1234 -[UIScrollView setContentOffset:] + 120"),
                       "UIKitCore:-[UIScrollView setContentOffset:]")
        // 区切りの「;」を残さない（`FeedProbeTrail` の区切り）
        XCTAssertFalse(FeedScrollSpyText.frame("1 SwiftUI 0x1 a;b + 4").contains(";"))
    }

    func testStackDropsObserverFramesAndLimits() {
        let symbols = [
            "0   JourneyPhoto.debug.dylib 0x1 FeedScrollSpy.Coordinator.offsetChanged + 1",
            "1   Foundation 0x2 NSKeyValueNotifyObserver + 2",
            "2   UIKitCore 0x3 -[UIScrollView setContentOffset:] + 3",
            "3   SwiftUI 0x4 ScrollViewUtilities.adjust + 4",
            "4   SwiftUI 0x5 Other + 5",
        ]
        XCTAssertEqual(FeedScrollSpyText.stack(symbols, count: 2),
                       "UIKitCore:-[UIScrollView setContentOffset:] < SwiftUI:ScrollViewUtilities.adjust")
    }
}
