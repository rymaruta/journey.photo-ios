import XCTest
@testable import JourneyPhoto

/// マイページの見出しの下の文字（板 05c）
final class ProfileLineTests: XCTestCase {

    func testHandleAndHome() {
        XCTAssertEqual(ProfileLine.handleAndHome(username: "yuki", home: "東京"), "@yuki · 📍東京")
        XCTAssertEqual(ProfileLine.handleAndHome(username: "yuki", home: " "), "@yuki")
        XCTAssertEqual(ProfileLine.handleAndHome(username: nil, home: "東京"), "📍東京")
        XCTAssertNil(ProfileLine.handleAndHome(username: "", home: nil))
    }

    /// 空は出さず、同じ文は二度出さない
    func testAboutSkipsEmptyAndDuplicates() {
        XCTAssertEqual(ProfileLine.about(status: "旅が好き", bio: "旅が好き"), ["旅が好き"])
        XCTAssertEqual(ProfileLine.about(status: " ", bio: "写真を撮ります"), ["写真を撮ります"])
        XCTAssertEqual(ProfileLine.about(status: "春", bio: "写真"), ["春", "写真"])
        XCTAssertEqual(ProfileLine.about(status: nil, bio: nil), [])
    }

    /// 格子の印は値として全部読む（題だけにすると下書きが読まれない）
    func testGridStateListsAllMarks() {
        let all = ProfileLine.gridState(pinned: true, draft: true, multiple: true)
        XCTAssertTrue(all.contains(L("ピン留め中", "Pinned")))
        XCTAssertTrue(all.contains(L("下書き", "Draft")))
        XCTAssertTrue(all.contains(L("複数枚の投稿", "Multiple photos")))
        XCTAssertEqual(ProfileLine.gridState(pinned: false, draft: false, multiple: false), "")
    }
}
