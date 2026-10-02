import XCTest
@testable import JourneyPhoto

/// 投稿した写真を Threads にも載せる（`ThreadsShare`）
final class ThreadsShareTests: XCTestCase {

    private let url = URL(string: "https://journey-photo.com/photo/abc")!

    /// 外へ渡すのは公開・全体に公開だけ
    func testEligibleOnlyForEveryone() {
        XCTAssertTrue(ThreadsShare.isEligible(published: true, audience: .everyone))
        XCTAssertFalse(ThreadsShare.isEligible(published: false, audience: .everyone))
        XCTAssertFalse(ThreadsShare.isEligible(published: true, audience: .closeFriends))
        XCTAssertFalse(ThreadsShare.isEligible(published: true, audience: .followers))
    }

    /// 題・撮影地・URL を行に分ける。空の行は入れない
    func testTextLines() {
        XCTAssertEqual(ThreadsShare.text(title: " 雲海 ", location: "高屋神社", url: url),
                       "雲海\n📍 高屋神社\nhttps://journey-photo.com/photo/abc")
        XCTAssertEqual(ThreadsShare.text(title: "", location: "", url: url), "https://journey-photo.com/photo/abc")
        XCTAssertEqual(ThreadsShare.text(title: "雲海", location: " ", url: nil), "雲海")
    }

    /// 説明は題の次の行に入る（前後の空白は落とす）
    func testTextIncludesDescription() {
        XCTAssertEqual(ThreadsShare.text(title: "朝の富士山", description: " また来たい。\n", location: "山中湖", url: url),
                       "朝の富士山\nまた来たい。\n📍 山中湖\nhttps://journey-photo.com/photo/abc")
    }

    /// 上限を超えたら題を詰める。URL は丸ごと残す
    func testTextKeepsWholeURLWithinLimit() {
        let text = ThreadsShare.text(title: String(repeating: "あ", count: 600), location: "", url: url)
        XCTAssertEqual(text.count, ThreadsShare.maxTextLength)
        XCTAssertTrue(text.hasSuffix("…\nhttps://journey-photo.com/photo/abc"))
    }
}
