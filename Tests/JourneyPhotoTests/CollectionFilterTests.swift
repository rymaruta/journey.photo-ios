import XCTest
@testable import JourneyPhoto

final class CollectionFilterTests: XCTestCase {

    private func photo(id: String, location: String? = nil, tags: [String] = []) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        if !tags.isEmpty {
            fields.append("\"tags\":[\(tags.map { "\"\($0)\"" }.joined(separator: ","))]")
        }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// **撮影地はゆるく一致させる。** Web 側の `photosInCollection` が
    /// 「パリ」「パリ, フランス」「オペラ・ガルニエ（パリ）」を寄せている。
    /// 完全一致にすると、同じ語で数えた結果が Web と食い違う。
    func testLocationMatchesLoosely() throws {
        let photos = [
            try photo(id: "a", location: "パリ"),
            try photo(id: "b", location: "パリ, フランス"),
            try photo(id: "c", location: "ロンドン"),
        ]
        let hits = PhotoQuery.photos(photos, in: .location("パリ"))
        XCTAssertEqual(hits.map(\.id), ["a", "b"])
    }

    /// タグは大文字小文字を無視した完全一致（部分一致にすると
    /// "sauna" が "sau" で引っかかる）。
    func testTagMatchesExactlyIgnoringCase() throws {
        let photos = [
            try photo(id: "a", tags: ["Sauna"]),
            try photo(id: "b", tags: ["sau"]),
        ]
        XCTAssertEqual(PhotoQuery.photos(photos, in: .tag("sauna")).map(\.id), ["a"])
    }

    /// 関連写真に自分自身を入れない。
    func testRelatedExcludesSelf() throws {
        let subject = try photo(id: "a", location: "パリ", tags: ["街"])
        let others = [subject, try photo(id: "b", location: "パリ")]
        let related = PhotoQuery.related(to: subject, from: others)
        XCTAssertEqual(related.map(\.id), ["b"])
    }

    /// 撮影地が同じものを先に出す。
    func testRelatedPrefersSameLocation() throws {
        let subject = try photo(id: "a", location: "パリ", tags: ["街"])
        let photos = [
            subject,
            try photo(id: "tagOnly", tags: ["街"]),
            try photo(id: "sameLocation", location: "パリ"),
        ]
        let related = PhotoQuery.related(to: subject, from: photos)
        XCTAssertEqual(related.first?.id, "sameLocation")
    }

    /// 検索は題・撮影地・タグ・カテゴリを横断し、大文字小文字と全角半角を
    /// 区別しない。
    func testSearchMatchesAcrossFields() throws {
        let photos = [
            try photo(id: "a", location: "Helsinki"),
            try photo(id: "b", tags: ["ｻｳﾅ"]),
        ]
        XCTAssertEqual(PhotoQuery.match(photos, query: "helsinki").map(\.id), ["a"])
    }
}

/// 共有する URL。**画像ではなくページを指す。**
final class PhotoLinkTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    func testPublishedPhotoUsesItsOwnPage() throws {
        let url = try XCTUnwrap(PhotoLink.url(photoId: "abc", isPublished: true))
        XCTAssertEqual(url.absoluteString, "https://site.example.test/photo/abc")
    }

    /// **投稿直後の写真には個別ページがまだ無い。** 静的書き出しなので、
    /// 再ビルドが終わるまで 404 になる。必ず開ける形に落とす。
    func testUnbuiltPhotoFallsBackToHome() throws {
        let url = try XCTUnwrap(PhotoLink.url(photoId: "abc", isPublished: false))
        XCTAssertEqual(url.absoluteString, "https://site.example.test?photo=abc")
    }

    func testEmptyIdHasNoLink() {
        XCTAssertNil(PhotoLink.url(photoId: "", isPublished: true))
    }
}

/// ピン留め（持ち主が選んだ並び）。
///
/// `pinnedPhotoIds` は復号していたのにどこでも見ておらず、**Web で留めた
/// 写真がアプリでは普通の位置に沈んでいた**。
final class PinnedOrderTests: XCTestCase {

    private func photo(_ id: String) -> Photo {
        let json = #"{"id":"\#(id)","src":"https://x.test/\#(id).jpg"}"#
        return try! JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    func testPinnedPhotosComeFirstInTheOrderTheyWerePinned() {
        let photos = ["a", "b", "c", "d"].map(photo)
        let sorted = PhotoPinning.pinnedFirst(photos, pinned: ["c", "a"])
        XCTAssertEqual(sorted.map { $0.id }, ["c", "a", "b", "d"])
    }

    func testNothingPinnedKeepsTheOriginalOrder() {
        let photos = ["a", "b"].map(photo)
        XCTAssertEqual(PhotoPinning.pinnedFirst(photos, pinned: []).map { $0.id }, ["a", "b"])
    }

    /// **消えた写真の ID が残っていても落ちない。** ピンはプロフィールに
    /// 残り続けるので、写真を消したあとの ID が混ざる。
    func testUnknownPinnedIdsAreIgnored() {
        let photos = ["a", "b"].map(photo)
        let sorted = PhotoPinning.pinnedFirst(photos, pinned: ["gone", "b"])
        XCTAssertEqual(sorted.map { $0.id }, ["b", "a"])
    }

    /// 同じ写真が2回出ない（ピンに入っているものを後ろでも出さない）。
    func testPinnedPhotoIsNotListedTwice() {
        let photos = ["a", "b"].map(photo)
        let sorted = PhotoPinning.pinnedFirst(photos, pinned: ["a"])
        XCTAssertEqual(sorted.count, 2)
    }
}

/// 切り抜きで残す側（`Photo.focalPoint`）。
///
/// owner が Web で掴んで動かした位置。**アプリは復号していながら見ておらず**、
/// 動かした写真がアプリでだけ中央で切られていた。
final class FocalCropTests: XCTestCase {

    private func photo(_ focal: String?) -> Photo {
        let extra = focal.map { ",\"focalPoint\":\($0)" } ?? ""
        let json = #"{"id":"a","src":"https://x.test/a.jpg"\#(extra)}"#
        return try! JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    func testNoFocalPointStaysCentered() {
        XCTAssertEqual(photo(nil).gridCrop, .center)
        XCTAssertEqual(photo(#"{"x":0.5,"y":0.5}"#).gridCrop, .center)
    }

    func testCornersRoundToTheNearestCorner() {
        XCTAssertEqual(photo(#"{"x":0.05,"y":0.05}"#).gridCrop, .topLeading)
        XCTAssertEqual(photo(#"{"x":0.95,"y":0.95}"#).gridCrop, .bottomTrailing)
        XCTAssertEqual(photo(#"{"x":0.95,"y":0.1}"#).gridCrop, .topTrailing)
        XCTAssertEqual(photo(#"{"x":0.1,"y":0.95}"#).gridCrop, .bottomLeading)
    }

    /// 人物の顔は上に寄っていることが多い——ここが中央に丸まると意味がない。
    func testUpperMiddleRoundsToTop() {
        XCTAssertEqual(photo(#"{"x":0.5,"y":0.2}"#).gridCrop, .top)
        XCTAssertEqual(photo(#"{"x":0.5,"y":0.8}"#).gridCrop, .bottom)
        XCTAssertEqual(photo(#"{"x":0.2,"y":0.5}"#).gridCrop, .leading)
        XCTAssertEqual(photo(#"{"x":0.8,"y":0.5}"#).gridCrop, .trailing)
    }
}
