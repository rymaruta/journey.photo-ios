import XCTest
@testable import JourneyPhoto

/// `.equatable()` の `==` が「違う」と答えたとき、どの値が違ったかの名前（`PerfChangeLog.differences`・2026-11-28 札 #594）
final class PerfInputDifferencesTests: XCTestCase {

    private struct Inner: Equatable { let likes: Int; let title: String }
    private struct Inputs: Equatable { let photo: Inner; let large: Bool; let siblings: [Int] }

    func testNamesTheFieldsThatDiffer() {
        let base = Inputs(photo: Inner(likes: 1, title: "a"), large: false, siblings: [1])
        XCTAssertEqual(PerfChangeLog.differences(base, base, depth: 1), [])
        XCTAssertEqual(PerfChangeLog.differences(base, Inputs(photo: Inner(likes: 2, title: "a"), large: false, siblings: [1]), depth: 1),
                       ["photo.likes"], "写真の中の違う値まで名前にしない")
        XCTAssertEqual(PerfChangeLog.differences(base, Inputs(photo: Inner(likes: 1, title: "a"), large: true, siblings: [1, 2]), depth: 1),
                       ["large", "siblings.count"])
        XCTAssertEqual(PerfChangeLog.differences(base, Inputs(photo: Inner(likes: 2, title: "a"), large: false, siblings: [1]), depth: 0),
                       ["photo"])
    }
}
