import XCTest
@testable import JourneyPhoto

final class CollectionFilterTests: XCTestCase {

    private func photo(id: String, location: String? = nil, tags: [String] = [],
                       category: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let category { fields.append("\"category\":\"\(category)\"") }
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

    /// **カテゴリで絞る。**
    ///
    /// 変異試験で `==` を `!=` にしても誰も気づかなかった
    /// ——**選んだカテゴリ以外が全部出る**という壊れ方が素通りしていた。
    func testCategoryMatchesExactly() throws {
        let photos = [
            try photo(id: "a", category: "風景"),
            try photo(id: "b", category: "食"),
            try photo(id: "c"),                    // カテゴリなし
        ]
        XCTAssertEqual(PhotoQuery.photos(photos, in: .category("風景")).map(\.id), ["a"])
    }

    /// **タグが重なるものを拾う。**
    ///
    /// 変異試験で `!tags.isDisjoint(...)` の `!` を外しても気づかなかった
    /// ——**タグが1つも重ならないものだけが「近い写真」として並ぶ**という
    /// 正反対の壊れ方。
    func testRelatedFillsWithOverlappingTags() throws {
        let subject = try photo(id: "a", tags: ["桜", "春"])
        let photos = [
            subject,
            try photo(id: "overlap", tags: ["桜"]),
            try photo(id: "unrelated", tags: ["雪"]),
        ]
        XCTAssertEqual(PhotoQuery.related(to: subject, from: photos).map(\.id), ["overlap"])
    }

    /// **タグを持たない写真から、タグで拾いにいかない。**
    /// `!tags.isEmpty` を外すと、空集合は何とも重ならないので結果は
    /// 変わらない……ように見えて、撮影地だけで埋まった一覧に
    /// 無関係なものが混ざる余地ができる。
    func testRelatedWithoutTagsOnlyUsesLocation() throws {
        let subject = try photo(id: "a", location: "パリ")
        let photos = [
            subject,
            try photo(id: "sameLocation", location: "パリ"),
            try photo(id: "tagged", tags: ["桜"]),
        ]
        XCTAssertEqual(PhotoQuery.related(to: subject, from: photos).map(\.id), ["sameLocation"])
    }

    /// **上限ちょうどで止める。**
    ///
    /// なお `>=` を `>` にしてもこのテストは落ちない（最後の
    /// `prefix(limit)` が同じ形に削るため）。等価変異だと確かめたうえで、
    /// **上限そのもの**は見張る。
    func testRelatedStopsAtTheLimit() throws {
        let subject = try photo(id: "a", tags: ["桜"])
        var photos = [subject]
        for i in 0..<5 { photos.append(try photo(id: "t\(i)", tags: ["桜"])) }
        XCTAssertEqual(PhotoQuery.related(to: subject, from: photos, limit: 2).count, 2)
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

/// 撮影地の自動補完（Web の `reverseGeocode` と同じ扱い）。
final class PlaceFillTests: XCTestCase {

    func testEmptyPlaceIsFilled() {
        XCTAssertEqual(PlaceFill.value(current: "", found: "高松市"), "高松市")
        XCTAssertEqual(PlaceFill.value(current: "   ", found: " 高松市 "), "高松市")
    }

    /// **打ってあるものは奪わない。** 引いている最中に打ち始めた人からも同じ
    /// ——入れる直前にもう一度ここを通すので、この一行が割り込みを止めている。
    func testTypedPlaceIsKept() {
        XCTAssertNil(PlaceFill.value(current: "高屋神社", found: "観音寺市"))
    }

    func testNothingFoundChangesNothing() {
        XCTAssertNil(PlaceFill.value(current: "", found: nil))
        XCTAssertNil(PlaceFill.value(current: "", found: "  "))
    }
}

/// 機種名の整えと、機材での絞り込み。
///
/// Web（`lib/utils/cameraName.ts`）と同じに揃える。保存済みの値には
/// **メーカー名が二重に残っている行がある**（実データに
/// `"Hasselblad Hasselblad X2D II 100C"`）。
final class CameraNameTests: XCTestCase {

    func testDropsTheRepeatedMakerOnce() {
        XCTAssertEqual(CameraName.deduped("Hasselblad Hasselblad X2D II 100C"),
                       "Hasselblad X2D II 100C")
    }

    /// **重なっていない名前は触らない**（`Canon EOS R5` が `EOS R5` になってはいけない）
    func testKeepsANormalName() {
        XCTAssertEqual(CameraName.deduped("Canon EOS R5"), "Canon EOS R5")
    }

    /// 落とすのは**1つぶんだけ**
    func testDropsOnlyOne() {
        XCTAssertEqual(CameraName.deduped("Sony Sony Sony A7"), "Sony Sony A7")
    }

    /// **語の切れ目まで見る。** `startsWith(first)` だけで判定すると、
    /// 先頭の語が**次の語の一部**でしかない並びまで削ってしまう
    /// （`Sony SonyA7` → `SonyA7`＝メーカー名が消える）。
    /// 変異試験で実際に生き残った穴。
    func testOnlyDropsWhenTheRepeatEndsAtAWordBoundary() {
        XCTAssertEqual(CameraName.deduped("Sony SonyA7"), "Sony SonyA7")
    }

    func testEmptyIsNil() {
        XCTAssertNil(CameraName.deduped("   "))
        XCTAssertNil(CameraName.deduped(nil))
    }

    /// 1語だけの名前（空白が無い）
    func testSingleWord() {
        XCTAssertEqual(CameraName.deduped("iPhone"), "iPhone")
    }

    /// 二重のまま保存された写真も、整えた名前で集まる
    func testCameraCollectionMatchesAcrossDuplicatedNames() throws {
        let photos = [
            try photo(id: "a", camera: "Hasselblad Hasselblad X2D II 100C"),
            try photo(id: "b", camera: "Hasselblad X2D II 100C"),
            try photo(id: "c", camera: "Canon EOS R5"),
        ]
        let found = PhotoQuery.photos(photos, in: .camera("Hasselblad X2D II 100C"))
        XCTAssertEqual(found.map(\.id), ["a", "b"])
    }

    private func photo(id: String, camera: String) throws -> Photo {
        let json = """
        {"id":"\(id)","src":"https://x/\(id).jpg","exif":{"camera":"\(camera)"}}
        """
        return try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }
}
