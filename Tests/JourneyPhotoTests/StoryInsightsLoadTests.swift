import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 反応の画面で読めなかったときに何を出すか（`StoryInsightsView.failureOutcome`）
final class StoryInsightsLoadTests: XCTestCase {

    /// 🔴 取り消しは、引き下げた回でも「読み直せませんでした」と言わない
    func testCancellationIsSilent() {
        XCTAssertEqual(StoryInsightsView.failureOutcome(CancellationError(), firstLoad: false, pulled: true), .silent)
        XCTAssertEqual(StoryInsightsView.failureOutcome(URLError(.cancelled), firstLoad: false, pulled: true), .silent)
        XCTAssertEqual(StoryInsightsView.failureOutcome(URLError(.cancelled), firstLoad: true, pulled: false), .silent)
    }

    /// 引き下げて読めなかったときだけ短く知らせる。裏での読み直しは黙る。まだ読めていなければ失敗の文
    func testPulledFailureIsNoticed() {
        let failure = APIError.unreachable
        XCTAssertEqual(StoryInsightsView.failureOutcome(failure, firstLoad: false, pulled: true), .refreshNotice)
        XCTAssertEqual(StoryInsightsView.failureOutcome(failure, firstLoad: false, pulled: false), .silent)
        XCTAssertEqual(StoryInsightsView.failureOutcome(failure, firstLoad: true, pulled: true), .errorMessage)
    }
}
