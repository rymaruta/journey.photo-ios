import XCTest
@testable import JourneyPhoto

/// マイページ（モック2）の、出す／出さないの決まり。
///
/// 🔴 **この画面は実機の絵で確かめられない**（CI の巡回はログインしない）。
final class ProfileSectionsTests: XCTestCase {

    // MARK: - ストーリーハイライト（モック2-5）

    /// **読み終わるまで出さない**（先に空を出すと、読み終わった瞬間に
    /// 入れ替わってちらつく）
    func testNothingBeforeItIsLoaded() {
        XCTAssertFalse(ProfileSections.showsHighlights(loaded: false, isMine: true, count: 3))
        XCTAssertFalse(ProfileSections.showsHighlights(loaded: false, isMine: false, count: 3))
    }

    /// 自分のページは0件でも出す（そこにしか「新規」が無い）
    func testOwnPageShowsEvenWhenEmpty() {
        XCTAssertTrue(ProfileSections.showsHighlights(loaded: true, isMine: true, count: 0))
    }

    /// 🔴 **他人のページで0件なら、行ごと消す。** サーバーは「追っていない人」にも
    /// 0件を返すので、「見られません」と書くと**在ることを教える**ことになる
    func testOtherPageHidesTheRowWhenEmpty() {
        XCTAssertFalse(ProfileSections.showsHighlights(loaded: true, isMine: false, count: 0))
        XCTAssertTrue(ProfileSections.showsHighlights(loaded: true, isMine: false, count: 2))
    }

    // MARK: - 行きたい場所（モック2-6）

    func testShowsTheListWhenThereIsSomething() {
        XCTAssertEqual(ProfileSections.wishlist(ledgerCount: 10, wantedCount: 2, savedIdCount: 2),
                       .list)
    }

    /// 1つも入れていない人には「まだありません」
    func testEmptyWhenNothingWasSaved() {
        XCTAssertEqual(ProfileSections.wishlist(ledgerCount: 10, wantedCount: 0, savedIdCount: 0),
                       .empty)
    }

    /// 🔴 **入れてあるのに台帳が取れていない回に「まだありません」と言わない。**
    /// 入れた覚えがあるのにそう出ると、消えたように見える
    func testCouldNotLoadIsNotTheSameAsEmpty() {
        XCTAssertEqual(ProfileSections.wishlist(ledgerCount: 0, wantedCount: 0, savedIdCount: 3),
                       .couldNotLoad)
    }

    /// 台帳は取れていて、入れた地点が台帳から消えた回は「まだありません」
    /// （取れていないのとは違う）
    func testLedgerLoadedButEntriesGoneIsEmpty() {
        XCTAssertEqual(ProfileSections.wishlist(ledgerCount: 10, wantedCount: 0, savedIdCount: 3),
                       .empty)
    }
}
