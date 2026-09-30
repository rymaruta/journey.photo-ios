import XCTest
@testable import JourneyPhoto

/// ストーリーの撮影地 → 撮影スポットのガイド（`StorySpotLink`・2026-09-30）
final class StorySpotLinkTests: XCTestCase {

    private func story(location: String?, lat: Double? = nil, lng: Double? = nil) -> Story {
        var fields = [#""id":"s1""#, #""src":"https://x.test/s1.jpg""#, #""userId":"u1""#]
        if let location { fields.append(#""location":"\#(location)""#) }
        if let lat, let lng { fields.append(#""coords":{"lat":\#(lat),"lng":\#(lng)}"#) }
        return try! JSONDecoder.api.decode(Story.self, from: Data(("{" + fields.joined(separator: ",") + "}").utf8))
    }

    private func spot(_ slug: String, name: String, nameEn: String? = nil, lat: Double? = nil, lng: Double? = nil,
                      stage: String = "published") -> OfficialSpot {
        var fields = [#""spotId":"sp_\#(slug)""#, #""slug":"\#(slug)""#, #""name":"\#(name)""#, #""stage":"\#(stage)""#]
        if let nameEn { fields.append(#""nameEn":"\#(nameEn)""#) }
        if let lat, let lng { fields.append(#""coords":{"lat":\#(lat),"lng":\#(lng)}"#) }
        return try! JSONDecoder.api.decode(OfficialSpot.self, from: Data(("{" + fields.joined(separator: ",") + "}").utf8))
    }

    private let takaya = (lat: 34.13, lng: 133.64)

    /// 撮影地の文字にスポットの名前が入っていて、座標が近ければ結ぶ
    func testLinksByNameAndDistance() {
        let s = spot("takaya-jinja", name: "高屋神社", lat: takaya.lat, lng: takaya.lng)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "高屋神社", lat: 34.13, lng: 133.65), in: [s])?.slug,
                       "takaya-jinja")
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "高屋神社（天空の鳥居）", lat: 34.13, lng: 133.64), in: [s])?.slug,
                       "takaya-jinja", "撮影地の文字に名前が入っていれば当てる")
    }

    /// 🔴 市区町村だけの撮影地は結ばない（町の真ん中の別の場所を名乗る）
    func testCityOnlyLocationDoesNotLink() {
        let s = spot("takaya-jinja", name: "高屋神社", lat: takaya.lat, lng: takaya.lng)
        XCTAssertNil(StorySpotLink.spot(for: story(location: "観音寺市, 香川県", lat: 34.13, lng: 133.64), in: [s]))
        XCTAssertNil(StorySpotLink.spot(for: story(location: nil, lat: 34.13, lng: 133.64), in: [s]))
        XCTAssertNil(StorySpotLink.spot(for: story(location: "  "), in: [s]))
    }

    /// 同じ名前でも遠ければ別の場所。近い方を選ぶ
    func testDistanceDisambiguatesSameName() {
        let near = spot("tenjin-a", name: "天神社", lat: 35.00, lng: 135.00)
        let far = spot("tenjin-b", name: "天神社", lat: 36.00, lng: 138.00)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "天神社", lat: 35.01, lng: 135.01), in: [far, near])?.slug,
                       "tenjin-a")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "天神社", lat: 40.0, lng: 140.0), in: [near, far]),
                     "\(StorySpotLink.maxKm)km より遠いなら結ばない")
    }

    /// 座標が無ければ、名前で当たるのが1件だけのときだけ
    func testWithoutCoordsOnlyUniqueName() {
        let a = spot("tenjin-a", name: "天神社", lat: 35.00, lng: 135.00)
        let b = spot("tenjin-b", name: "天神社", lat: 36.00, lng: 138.00)
        let c = spot("takaya-jinja", name: "高屋神社", lat: takaya.lat, lng: takaya.lng)
        XCTAssertNil(StorySpotLink.spot(for: story(location: "天神社"), in: [a, b, c]))
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "高屋神社"), in: [a, b, c])?.slug, "takaya-jinja")
    }

    /// 下書きは結ばない・括弧の中（旧称）や英語名でも当たる
    func testDraftsAndAlternateNames() {
        let draft = spot("draft", name: "高屋神社", lat: takaya.lat, lng: takaya.lng, stage: "review")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "高屋神社", lat: 34.13, lng: 133.64), in: [draft]))
        let renamed = spot("asmui", name: "ASMUI Spiritual Hikes（旧・大石林山）", lat: 26.85, lng: 128.25)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "大石林山", lat: 26.85, lng: 128.25), in: [renamed])?.slug,
                       "asmui", "旧称（括弧の中）で当てる")
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "asmui spiritual hikes", lat: 26.85, lng: 128.25), in: [renamed])?.slug,
                       "asmui", "大小を畳んで当てる")
        let en = spot("matterhorn", name: "マッターホルン", nameEn: "Matterhorn", lat: 45.98, lng: 7.66)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "Matterhorn, Zermatt", lat: 45.98, lng: 7.66), in: [en])?.slug,
                       "matterhorn")
    }

    func testSplitParentheses() {
        XCTAssertEqual(StorySpotLink.splitParentheses("A（B）").outer, "A")
        XCTAssertEqual(StorySpotLink.splitParentheses("A（B）").inner, ["B"])
        XCTAssertEqual(StorySpotLink.splitParentheses("A (B) C").outer, "A  C")
        XCTAssertEqual(StorySpotLink.splitParentheses("A").inner, [])
    }
}
