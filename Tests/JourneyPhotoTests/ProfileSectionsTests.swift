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

    private func photo(_ id: String, location: String?) throws -> Photo {
        let l = location.map { ",\"location\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"likes\":0,\"createdAt\":\"2026-01-01T00:00:00Z\"\(l)}".utf8))
    }

    func testShowsTheListWhenThereIsSomething() {
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: 2, savedIdCount: 2, loaded: true, sourceFailed: false),
                       .list)
    }

    /// 1つも入れていない人には「まだありません」（読み込み中でも失敗でも）
    func testEmptyWhenNothingWasSaved() {
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: 0, savedIdCount: 0, loaded: true, sourceFailed: false),
                       .empty)
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: 0, savedIdCount: 0, loaded: false, sourceFailed: true),
                       .empty)
    }

    /// 🔴 **入れてあるのに公開一覧が取れていない回に「まだありません」と言わない。**
    /// 入れた覚えがあるのにそう出ると、消えたように見える
    func testCouldNotLoadIsNotTheSameAsEmpty() {
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: 0, savedIdCount: 3, loaded: true, sourceFailed: true),
                       .couldNotLoad)
    }

    /// 読み終える前は「まだありません」とも「取れません」とも言わない
    func testLoadingIsNeitherEmptyNorFailed() {
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: 0, savedIdCount: 3, loaded: false, sourceFailed: false),
                       .loading)
    }

    /// 取れていて、入れた地点がどこにも無くなった回は「まだありません」
    /// （取れていないのとは違う）
    func testLoadedButEntriesGoneIsEmpty() {
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: 0, savedIdCount: 3, loaded: true, sourceFailed: false),
                       .empty)
    }

    /// 🔴 **台帳の撮影スポットだけを入れた人に「まだありません」と言わない。**
    /// 呼ぶ側は `wantedCount` に撮影地の行とスポットの行（`OfficialWishlist.rows`）を
    /// 足して渡す——撮影地の集まりが1つも当たらなくても、スポットの行があれば並べる
    func testOfficialOnlyWishlistIsAList() {
        let official = OfficialWishlist.rows(keys: ["SPOT-takaya-jinja"], index: [])
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: official.count, savedIdCount: 1,
                                                loaded: true, sourceFailed: false),
                       .list)
        // 写真の一覧が取れていない回でも、スポットの行は slug から起こせるので並べる
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: official.count, savedIdCount: 1,
                                                loaded: true, sourceFailed: true),
                       .list)
    }

    /// 🔴 **他人の写真の撮影地に押した「行きたい」も並ぶ。** スポットの画面は
    /// 地図（公開一覧）から他人の写真で開くのがふつう。以前は自分の写真だけから
    /// 地点を導いていて、ここが空になっていた
    func testWantedPlacesComeFromThePublicFeedToo() throws {
        let feed = [try photo("theirs", location: "高屋神社")]
        let mine = [try photo("mine", location: "パリ")]
        let wanted = ProfileSections.wantedPlaces(keys: [LocationSlug.make("高屋神社")], feed: feed, mine: mine)
        XCTAssertEqual(wanted.map(\.label), ["高屋神社"], "他人の写真の撮影地が出ていない")
        // 自分の写真しか無い（写真を上げていない）人でも、公開一覧から引ける
        XCTAssertEqual(ProfileSections.wantedPlaces(keys: [LocationSlug.make("高屋神社")], feed: feed, mine: []).count, 1)
    }

    /// 🔴 **自分の公開写真は両方に在る。ID で1枚に寄せる**（寄せないと枚数が倍になる）
    func testPoolDeduplicatesById() throws {
        let shared = try photo("same", location: "パリ")
        let pool = ProfileSections.wishlistPool(feed: [shared, try photo("other", location: "パリ")], mine: [shared])
        XCTAssertEqual(pool.map(\.id), ["same", "other"])
        let wanted = ProfileSections.wantedPlaces(keys: [LocationSlug.make("パリ")], feed: [shared], mine: [shared])
        XCTAssertEqual(wanted.first?.count, 1, "同じ写真を2枚に数えている")
    }

    /// 🔴 **写真を1枚も上げていない人に「写真の一覧を取れませんでした」と言わない。**
    /// 以前は導いた地点が0件なら「取れていない」にしていた——公開一覧は取れているのに
    func testNoOwnPhotosIsNotAFailure() throws {
        let feed = [try photo("theirs", location: "金沢")]
        let wanted = ProfileSections.wantedPlaces(keys: ["消えた地点"], feed: feed, mine: [])
        XCTAssertEqual(ProfileSections.wishlist(wantedCount: wanted.count, savedIdCount: 1,
                                                loaded: true, sourceFailed: false),
                       .empty)
    }

    /// **同じ鍵になる別のラベルを1行に寄せる**（「高屋 神社」と「高屋　神社」）。
    /// 同じ id の行が2つ並ぶと一覧が壊れる
    func testWantedPlacesAreUniqueBySlug() throws {
        func photo(_ id: String, _ location: String) throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(
                #"{"id":"\#(id)","src":"/uploads/\#(id).jpg","location":"\#(location)"}"#.utf8))
        }
        let pool = [try photo("a", "高屋 神社"), try photo("b", "高屋　神社")]
        let key = LocationSlug.make("高屋 神社")
        XCTAssertEqual(LocationSlug.make("高屋　神社"), key, "前提: 同じ鍵になる")
        XCTAssertEqual(ProfileSections.wantedPlaces(keys: [key], pool: pool).count, 1, "同じ鍵の行が2つ並ぶ")
    }

    /// **寄せた行は両方の写真を持つ**（「高屋-神社」と「高屋 神社」は `DerivedSpot` では別の
    /// 地点、鍵は同じ）。片方だけ残すと枚数・表紙・開いた先の写真が半分になる
    func testMergedPlaceKeepsPhotosOfBothLabels() throws {
        func photo(_ id: String, _ location: String) throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(
                #"{"id":"\#(id)","src":"/uploads/\#(id).jpg","location":"\#(location)"}"#.utf8))
        }
        let pool = [try photo("a", "高屋-神社"), try photo("b", "高屋 神社")]
        let key = LocationSlug.make("高屋 神社")
        XCTAssertEqual(LocationSlug.make("高屋-神社"), key, "前提: 同じ鍵になる")
        XCTAssertEqual(DerivedSpot.all(in: pool).count, 2, "前提: 撮影地としては別の2か所")
        let wanted = ProfileSections.wantedPlaces(keys: [key], pool: pool)
        XCTAssertEqual(wanted.count, 1)
        XCTAssertEqual(Set(wanted.first?.photos.map(\.id) ?? []), ["a", "b"], "寄せた行が片方の写真しか持たない")
    }

    /// **引き当て先が取れず、一部だけ見つかった回は一行添える**（黙って行を落とさない）
    func testPartlyMissingOnlyWhenTheSourceFailed() {
        XCTAssertTrue(ProfileSections.wishlistPartlyMissing(shownCount: 1, savedIdCount: 3, sourceFailed: true))
        XCTAssertFalse(ProfileSections.wishlistPartlyMissing(shownCount: 1, savedIdCount: 3, sourceFailed: false),
                       "取れているのに欠けた（消えた撮影地）ことを失敗と言っている")
        XCTAssertFalse(ProfileSections.wishlistPartlyMissing(shownCount: 3, savedIdCount: 3, sourceFailed: true))
    }
}
