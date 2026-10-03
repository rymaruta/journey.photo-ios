import XCTest
@testable import JourneyPhoto

/// ストーリーを作るときの撮影地の候補（`StorySpotSuggestion`・2026-10-03）。
///
/// 固定したいのは:
///  1. 写真の位置の近く（3km 以内）の公開済みスポットを、近い順に1つ。GPS が無ければ出さない
///  2. **見る画面で結ばれる候補だけ**（`StorySpotLink` と往復して同じスポットになる）
///  3. 候補の名前を撮影地にした回は、**写真の座標でなくスポットの座標**を送る（撮影地の単位だけ）
final class StorySpotSuggestionTests: XCTestCase {

    private func spot(_ slug: String, name: String, lat: Double, lng: Double,
                      city: String? = nil, stage: String = "published") -> OfficialSpot {
        var fields = [#""spotId":"sp_\#(slug)""#, #""slug":"\#(slug)""#, #""name":"\#(name)""#, #""stage":"\#(stage)""#,
                      #""coords":{"lat":\#(lat),"lng":\#(lng)}"#]
        if let city { fields.append(#""region":{"city":"\#(city)"}"#) }
        return try! JSONDecoder.api.decode(OfficialSpot.self, from: Data(("{" + fields.joined(separator: ",") + "}").utf8))
    }

    private let takaya = Photo.Coords(lat: 34.13, lng: 133.64)

    func testNearestPublishedSpotWithinRange() {
        let near = spot("takaya", name: "高屋神社 本宮（天空の鳥居）", lat: 34.13, lng: 133.65)
        let farther = spot("zenigata", name: "銭形砂絵", lat: 34.14, lng: 133.66)
        let draft = spot("draft", name: "下書きの場所", lat: 34.13, lng: 133.64, stage: "review")
        let far = spot("far", name: "遠い場所", lat: 34.50, lng: 133.64)
        let spots = [far, farther, draft, near]
        XCTAssertEqual(StorySpotSuggestion.spot(for: [takaya], in: spots)?.slug, "takaya")
        XCTAssertNil(StorySpotSuggestion.spot(for: [nil], in: spots), "GPS の無い写真には出さない")
        XCTAssertNil(StorySpotSuggestion.spot(for: [], in: spots))
        XCTAssertNil(StorySpotSuggestion.spot(for: [Photo.Coords(lat: 34.50, lng: 134.50)], in: spots),
                     "近くに無ければ出さない")
    }

    /// 基準は送る座標と同じ写真（仲間の多い写真）。1枚目だけ別の街でも、多い方の近くを出す
    func testUsesSameBaseAsSentCoords() {
        let near = spot("takaya", name: "高屋神社", lat: 34.13, lng: 133.64)
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)
        XCTAssertEqual(StorySpotSuggestion.spot(for: [tokyo, takaya, takaya], in: [near])?.slug, "takaya")
    }

    /// 🔴 見る画面で結ばれない候補は出さない（名前が市町村名と同じ → 地名として落ちる）。次の候補へ
    func testSkipsCandidateThatWouldNotLink() {
        let cityNamed = spot("kanonji", name: "観音寺市", lat: 34.13, lng: 133.64, city: "観音寺市")
        let shrine = spot("takaya", name: "高屋神社", lat: 34.14, lng: 133.64)
        XCTAssertEqual(StorySpotSuggestion.spot(for: [takaya], in: [cityNamed, shrine])?.slug, "takaya")
        XCTAssertNil(StorySpotSuggestion.spot(for: [takaya], in: [cityNamed]))
    }

    /// 候補を付けた1本は、見る画面でそのスポットに結ばれる（送る座標で往復する）
    func testPickedSuggestionLinksInViewer() {
        let near = spot("takaya", name: "高屋神社 本宮（天空の鳥居）", lat: 34.15, lng: 133.66)
        let spots = [near]
        let picked = StorySpotSuggestion.spot(for: [takaya], in: spots)
        XCTAssertEqual(picked?.slug, "takaya")
        let sent = StorySpotSuggestion.coordsToSend([takaya], location: near.name, suggested: picked)
        XCTAssertEqual(StorySpotLink.spot(location: near.name, coords: sent[0], in: spots)?.slug, "takaya")
    }

    /// 🔴 候補の名前を撮影地にした回は、写真の座標（本人の居た升目）でなくスポットの座標を送る
    func testPickedSuggestionSendsSpotCoordsOnly() {
        let near = spot("takaya", name: "高屋神社", lat: 34.15, lng: 133.66)
        let nearby = Photo.Coords(lat: 34.14, lng: 133.65)
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)
        let spotCoords = Photo.Coords(lat: 34.15, lng: 133.66)
        let sent = StorySpotSuggestion.coordsToSend([takaya, nil, nearby, takaya, tokyo],
                                                    location: " 高屋神社 ", suggested: near)
        XCTAssertEqual(sent, [spotCoords, nil, spotCoords, spotCoords, nil],
                       "GPS の無い写真・基準から遠い写真は送らないまま")
    }

    /// 撮影地を打ち直した（候補の名前でない）回は、これまでどおり写真の座標
    func testOtherLocationKeepsPhotoCoords() {
        let near = spot("takaya", name: "高屋神社", lat: 34.15, lng: 133.66)
        XCTAssertEqual(StorySpotSuggestion.coordsToSend([takaya], location: "観音寺の海", suggested: near), [takaya])
        XCTAssertEqual(StorySpotSuggestion.coordsToSend([takaya], location: "高屋神社", suggested: nil), [takaya])
    }

    /// 基準の写真を外へ出しても、送る座標の決まりは前のまま（`coordsToSend` の写し）
    func testBaseCoordsMatchesCoordsToSend() {
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)
        XCTAssertEqual(StoryQueue.baseCoords([tokyo, takaya, takaya]), takaya)
        XCTAssertEqual(StoryQueue.baseCoords([tokyo, takaya]), tokyo, "同数なら前の写真")
        XCTAssertNil(StoryQueue.baseCoords([nil, nil]))
    }

    /// 🔴 作る画面のつなぎ（画面は Linux で描けないので、ソースに呼び出しが残っていることを見る）。
    /// 候補は**押したときだけ**撮影地に入り、送る座標は候補の決まりを通す
    func testComposerWiring() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let composer = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift"), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(composer.contains("StorySpotSuggestion.coordsToSend(shots.map(\\.prepared.coords), location: place,"),
                      "投稿が候補の座標の決まりを通っていない")
        XCTAssertFalse(composer.contains("StoryQueue.coordsToSend("), "写真の座標をそのまま送る経路が残っている")
        XCTAssertTrue(composer.contains("spotSuggestion = StorySpotSuggestion.spot(for:"))
        // 撮影地に入れるのは候補の札を押したときだけ（黙って入れない）
        XCTAssertEqual(composer.components(separatedBy: "location = spot.name").count - 1, 1)
    }
}
