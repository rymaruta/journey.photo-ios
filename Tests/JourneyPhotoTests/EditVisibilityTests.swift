import XCTest
@testable import JourneyPhoto

/// 写真の編集で、公開と公開範囲を送るか（`EditVisibilityRules`・バグ探し 2026-09-27）
final class EditVisibilityTests: XCTestCase {

    /// 🔴 **触っていなければ送らない。** 古い写し（全体公開・公開）から開いて題だけ
    /// 直すと、別の画面で絞った範囲・非公開が全体公開に戻っていた
    func testUntouchedVisibilityIsNotSent() {
        let p = EditVisibilityRules.patch(openedPublished: true, openedAudience: .everyone,
                                          published: true, audience: .everyone)
        XCTAssertNil(p.published, "触っていない公開を送っている")
        XCTAssertNil(p.audience, "触っていない範囲を送っている")
    }

    /// 🔴 **非公開にするときは範囲を送らない**（範囲が消え、公開に戻すと全体に出た）
    func testUnpublishingKeepsTheAudience() {
        let p = EditVisibilityRules.patch(openedPublished: true, openedAudience: .followers,
                                          published: false, audience: .followers)
        XCTAssertEqual(p.published, false)
        XCTAssertNil(p.audience, "非公開にするとき範囲を消している")
    }

    func testChangingTheAudienceIsSent() {
        let p = EditVisibilityRules.patch(openedPublished: true, openedAudience: .everyone,
                                          published: true, audience: .followers)
        XCTAssertNil(p.published)
        XCTAssertEqual(p.audience, Audience.followers.patchValue)
        // 知らない値の写真は範囲を送らない
        let unknown = EditVisibilityRules.patch(openedPublished: true, openedAudience: nil,
                                                published: true, audience: .everyone)
        XCTAssertNil(unknown.audience)
    }

    /// 広げ直し・公開し直しの経路（範囲を戻す唯一の道・同じ範囲のまま公開し直す）
    func testWideningAndRepublishing() {
        let widen = EditVisibilityRules.patch(openedPublished: true, openedAudience: .followers,
                                              published: true, audience: .everyone)
        XCTAssertEqual(widen.audience, "", "全体に戻すのに範囲を送っていない")
        let republish = EditVisibilityRules.patch(openedPublished: false, openedAudience: .followers,
                                                  published: true, audience: .followers)
        XCTAssertEqual(republish.published, true)
        XCTAssertNil(republish.audience, "範囲は残っているので送らない")
        let both = EditVisibilityRules.patch(openedPublished: false, openedAudience: .everyone,
                                             published: true, audience: .followers)
        XCTAssertEqual(both.published, true)
        XCTAssertEqual(both.audience, Audience.followers.patchValue)
    }

    /// 触っていない本文は空（空は送らない——サーバーが 400 で断る）
    func testUntouchedPatchIsEmpty() {
        var patch = PhotoPatch()
        let v = EditVisibilityRules.patch(openedPublished: true, openedAudience: .everyone,
                                          published: true, audience: .everyone)
        patch.published = v.published
        patch.audience = v.audience
        XCTAssertTrue(patch.isEmpty)
    }
}
