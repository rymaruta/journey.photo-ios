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

    /// 題・撮影地・URL を空行で段落に分ける。無い項目の段落は作らない
    func testTextLines() {
        XCTAssertEqual(ThreadsShare.text(title: " 雲海 ", location: "高屋神社", url: url),
                       "雲海\n\n📍 高屋神社\n\nhttps://journey-photo.com/photo/abc")
        XCTAssertEqual(ThreadsShare.text(title: "", location: "", url: url), "https://journey-photo.com/photo/abc")
        XCTAssertEqual(ThreadsShare.text(title: "雲海", location: " ", url: nil), "雲海")
    }

    /// 説明は題の次の段落に入る。説明の中の空行は詰める（前後の空白は落とす）
    func testTextIncludesDescription() {
        XCTAssertEqual(ThreadsShare.text(title: "朝の富士山", description: " やっぱり特別だ。\n\n また来たい。\n", location: "山中湖", url: url),
                       "朝の富士山\n\nやっぱり特別だ。\nまた来たい。\n\n📍 山中湖\n\nhttps://journey-photo.com/photo/abc")
    }

    /// 上限を超えたら題を詰める。URL は丸ごと残す
    func testTextKeepsWholeURLWithinLimit() {
        let text = ThreadsShare.text(title: String(repeating: "あ", count: 600), location: "", url: url)
        XCTAssertEqual(text.count, ThreadsShare.maxTextLength)
        XCTAssertTrue(text.hasSuffix("…\n\nhttps://journey-photo.com/photo/abc"))
    }
}
