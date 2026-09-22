import XCTest
@testable import JourneyPhoto

/// 公開範囲を絞った写真（`GET /feed/restricted`）を一覧に混ぜるところ。
final class RestrictedFeedTests: XCTestCase {

    private func photo(_ id: String, at: String? = nil, audience: String? = nil) throws -> Photo {
        let c = at.map { ",\"createdAt\":\"\($0)\"" } ?? ""
        let a = audience.map { ",\"audience\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(c)\(a)}".utf8))
    }

    /// 新しい順に混ざる（公開と絞りが交互でも）
    func testMergedFeedIsNewestFirst() throws {
        let merged = RestrictedFeed.merge(
            publicPhotos: [try photo("a", at: "2026-09-20T00:00:00Z"),
                           try photo("c", at: "2026-09-18T00:00:00Z")],
            restricted: [try photo("b", at: "2026-09-19T00:00:00Z", audience: "followers")])
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
    }

    /// **自分の写真は絞りの口にも返る。** 二重に並べない
    func testSamePhotoIsNotListedTwice() throws {
        let merged = RestrictedFeed.merge(
            publicPhotos: [try photo("a", at: "2026-09-20T00:00:00Z")],
            restricted: [try photo("a", at: "2026-09-20T00:00:00Z", audience: "followers")])
        XCTAssertEqual(merged.count, 1)
    }

    /// **`createdAt` の無い行を落とさない。** 落とすと古い投稿が一覧から消える
    func testPhotosWithoutTimestampSurvive() throws {
        let merged = RestrictedFeed.merge(
            publicPhotos: [try photo("a", at: "2026-09-20T00:00:00Z"), try photo("old")],
            restricted: [])
        XCTAssertEqual(merged.map(\.id), ["a", "old"])
    }

    /// 印が無ければ全体に公開。札も出さない
    func testUnmarkedPhotoHasNoBadge() throws {
        XCTAssertNil(RestrictedFeed.badge(try photo("a")))
        XCTAssertFalse(RestrictedFeed.isRestricted(try photo("a")))
    }

    func testKnownAudienceShowsItsLabel() throws {
        XCTAssertEqual(RestrictedFeed.badge(try photo("a", audience: "closeFriends")),
                       Audience.closeFriends.label)
    }

    /// **知らない値は広げない。** サーバーが選択肢を増やしたときに、
    /// 古いアプリが「全体に公開」として見せてしまわないこと
    func testUnknownAudienceIsStillTreatedAsRestricted() throws {
        let unknown = try photo("a", audience: "mutuals")
        XCTAssertTrue(RestrictedFeed.isRestricted(unknown))
        XCTAssertNotNil(RestrictedFeed.badge(unknown))
        XCTAssertNotEqual(RestrictedFeed.badge(unknown), Audience.everyone.label)
    }

    /// **非公開の写真に絞りの印を付けない。** 非公開は誰にも見えないので、
    /// 絞りを重ねると「フォロワーには見える」と誤解させる
    @MainActor
    func testPrivatePhotoSendsNoAudience() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"))
        let model = UploadViewModel(uploads: UploadService(api: api),
                                    albums: AlbumService(api: api),
                                    photos: PhotoService(api: api),
                                    discovery: DiscoveryService(api: api))
        model.audience = .closeFriends
        model.published = false
        XCTAssertEqual(model.audienceToSend, .everyone)
        model.published = true
        XCTAssertEqual(model.audienceToSend, .closeFriends)
    }

    /// 「全体に公開」はサーバーへ送らない（属性を書かない形に揃える）
    func testEveryoneIsNotSentOverTheWire() {
        XCTAssertNil(Audience.everyone.wireValue)
        XCTAssertEqual(Audience.followers.wireValue, "followers")
        XCTAssertEqual(Audience.closeFriends.wireValue, "closeFriends")
    }
}

/// `PUT /photos/{id}` に載せる公開範囲。
final class AudiencePatchTests: XCTestCase {

    /// **「全体に公開」は空文字で送る。** キーごと消えると、サーバーは
    /// 既にある印をそのまま残す＝一度絞ったら二度と外せない
    func testEveryoneIsSentAsAnEmptyString() {
        XCTAssertEqual(Audience.everyone.patchValue, "")
        XCTAssertEqual(Audience.followers.patchValue, "followers")
    }

    /// 送らない回は「触らない」。`isEmpty` が拾わないと、公開範囲だけ
    /// 変えた保存が「更新項目がありません」で捨てられる
    func testPatchWithOnlyAudienceIsNotEmpty() {
        var patch = PhotoPatch()
        XCTAssertTrue(patch.isEmpty)
        patch.audience = Audience.followers.patchValue
        XCTAssertFalse(patch.isEmpty)
    }

    /// 空文字も「触る」——外す指示そのものなので、捨ててはいけない
    func testClearingAudienceIsAlsoAChange() {
        var patch = PhotoPatch()
        patch.audience = Audience.everyone.patchValue
        XCTAssertFalse(patch.isEmpty)
    }
}

/// もとは `StoryPlaybackTests` に在った。ストーリーの公開範囲は owner の
/// 判断で無くなった（`api-user/src/storyVisibility.ts`）ので、**写真だけが
/// この三択を使う**。検査もこちらへ移す。
final class AudienceChoicesTests: XCTestCase {

    /// 三択ぶん、言葉が揃っていること（空の札を並べない）
    func testEveryChoiceHasWords() {
        XCTAssertEqual(Audience.allCases.count, 3)
        for choice in Audience.allCases {
            XCTAssertFalse(choice.label.isEmpty)
            XCTAssertFalse(choice.note.isEmpty)
            XCTAssertFalse(choice.photoNote.isEmpty)
        }
    }

    /// 送る値は**サーバーが受け取る綴りちょうど**
    /// （`api-user/src/sanitize.ts` の `sanitizeAudience`）
    func testWireValuesMatchTheServer() {
        XCTAssertEqual(Audience.followers.wireValue, "followers")
        XCTAssertEqual(Audience.closeFriends.wireValue, "closeFriends")
    }
}
