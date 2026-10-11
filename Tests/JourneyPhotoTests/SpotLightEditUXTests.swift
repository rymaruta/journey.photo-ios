import XCTest
@testable import JourneyPhoto

/// 撮影スポットの頁・光と天気の知らせ・写真を編集の使い勝手（2026-10-11・owner「おすすめで」）。
///
/// 固定したいのは:
///  1. スポットの頁: 札の行は「行きたい・地図で見る（アプリの中）・経路（Apple のマップ）」。
///     シェアは右上の1つだけ。「見つける→行く→撮る→残す」は押せる見た目にしない
///  2. 光の知らせ: 札の四角はスポットの写真・開閉の印・開いた中に「スポットを見る」「経路」。
///     Apple Weather の出典は今のまま出る
///  3. 写真を編集: 保存は右上・欄の上に名前・撮影日は日付ピッカー（空にもできる・1990年〜今日）
///
/// 画面は Linux で描けないので、決まりは関数で、画面のつなぎはソースに残っていることで見る
/// （`ScreenWiringTests` と同じ考え。書き方を変えたら、ここも合わせて直す）
@MainActor
final class SpotLightEditUXTests: XCTestCase {

    // MARK: - 下ごしらえ

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//` `///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// `from` から次の `// MARK:`（無ければ終わり）までの切り出し
    private func segment(_ text: String, from: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: from), "\(from) が無い")
        let rest = text[start.upperBound...]
        if let end = rest.range(of: "    private ") {
            return String(rest[..<end.lowerBound])
        }
        return String(rest)
    }

    private func spot(_ slug: String, stage: String = "published", image: Bool = true,
                      coords: Bool = true) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"[\(slug)]\"",
                      "\"stage\":\"\(stage)\""]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(slug).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        if coords {
            fields.append("\"coords\":{\"lat\":34.14,\"lng\":133.64}")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func place(slug: String, key: String? = nil) -> LightForecast.Place {
        .init(key: key ?? "SPOT-\(slug)", slug: slug, name: "場所", timeZone: "Asia/Tokyo", forecast: true, days: [])
    }

    // MARK: - 1. スポットの頁

    /// 座標があれば「行きたい・地図で見る・経路」。**シェアは札の行に無い**（右上の1つだけ）
    func testOfficialActionsHaveDirectionsAndNoShare() async {
        XCTAssertEqual(SpotScreen.officialActions(hasCoords: true), [.wish, .map, .directions])
        // 座標が無い地点に「地図で見る」「経路」を置かない（押しても空になる札を作らない）
        XCTAssertEqual(SpotScreen.officialActions(hasCoords: false), [.wish])
    }

    /// 画面: 札の行は `officialActions` で並べ、「地図で見る」はアプリの中の地図へ。外へは経路だけ
    func testSpotPageWiresInAppMapDirectionsAndOneShare() async throws {
        let page = try source("Features/Spots/OfficialSpotView.swift")
        XCTAssertTrue(page.contains("SpotScreen.officialActions(hasCoords: spot.coords != nil)"))
        XCTAssertTrue(page.contains("OfficialSpotMapView(spot: shown)"), "「地図で見る」がアプリの中の地図を開いていない")
        XCTAssertFalse(page.contains("Link(destination: url)"), "「地図で見る」がまだ Apple のマップへ飛ぶ")
        XCTAssertEqual(count("ShareLink(", in: page), 1, "シェアが頁に2つある")
        XCTAssertTrue(page.contains(#".accessibilityIdentifier("spot.official.share")"#))
        XCTAssertTrue(page.contains("SpotDirections.openDirections(name: name, coords: coords, stillWanted: { onScreen })"),
                      "経路が名前で探し直していない・頁を離れたあとでも開く")
        XCTAssertTrue(page.contains(#".accessibilityIdentifier("spot.official.directions")"#))

        // 地図の画面: 同じピンの部品・経路は同じ口
        let map = try source("Features/Spots/OfficialSpotMapView.swift")
        XCTAssertTrue(map.contains("SpotMapMarker(photoURL: spot.photo?.smallURL"))
        XCTAssertTrue(map.contains("SpotDirections.openDirections(name: name, coords: coords, stillWanted: { onScreen })"))
        XCTAssertFalse(map.contains("maps.apple.com"))
    }

    /// 「この場所から、次の一枚へ」は**説明の帯**。地・縁・真鍮・矢印の記号を付けない（ボタンに見せない）
    func testJourneyCueDoesNotLookTappable() async throws {
        let page = try source("Features/Spots/OfficialSpotView.swift")
        let cue = try segment(page, from: "var journeyCue: some View {")
        XCTAssertTrue(cue.contains("見つける → 行く → 撮る → 残す"))
        for look in [".background(", ".overlay(", "strokeBorder", "chevron.right", "WebTheme.accent", "Image(systemName:"] {
            XCTAssertFalse(cue.contains(look), "説明の帯に押せる見た目（\(look)）が残っている")
        }
        XCTAssertFalse(page.contains("func journeyStep("), "押せない段の札が残っている")
        XCTAssertFalse(cue.contains("Button"))
    }

    // MARK: - 2. 光と天気の知らせ

    /// 札の場所は slug で撮影スポットに当てる（無ければ key `SPOT-<slug>`）。当たらなければ nil
    func testForecastPlaceFindsItsSpot() async throws {
        let index = [try spot("takaya"), try spot("nabegataki")]
        XCTAssertEqual(LightForecastText.spot(for: place(slug: "nabegataki"), in: index)?.slug, "nabegataki")
        XCTAssertEqual(LightForecastText.spot(for: place(slug: "", key: "SPOT-takaya"), in: index)?.slug, "takaya")
        XCTAssertNil(LightForecastText.spot(for: place(slug: "nowhere"), in: index))
        XCTAssertNil(LightForecastText.spot(for: place(slug: "takaya"), in: []))
    }

    /// 開閉は読み上げでも言う（印の形だけにしない）
    func testDisclosureIsSpoken() async {
        XCTAssertNotEqual(LightForecastText.disclosureValue(isOpen: true),
                          LightForecastText.disclosureValue(isOpen: false))
        XCTAssertFalse(LightForecastText.disclosureValue(isOpen: true).isEmpty)
    }

    /// 見本（DEBUG）は写真・座標のある公開スポットの名前で組む。足りなければ伏せ字の名前のまま
    func testSampleUsesRealSpotsWhenGiven() async throws {
        let index = [try spot("draft", stage: "draft"), try spot("noimage", image: false),
                     try spot("nocoords", coords: false), try spot("takaya")]
        let picked = LightForecastText.previewSpots(index)
        XCTAssertEqual(picked.map(\.slug), ["takaya"])
        let now = Date(timeIntervalSince1970: 1_791_514_800)
        let sample = LightForecastText.sample(now: now, spots: picked)
        XCTAssertEqual(sample.places.count, 4)
        XCTAssertEqual(sample.places[0].slug, "takaya")
        XCTAssertEqual(sample.places[0].key, "SPOT-takaya")
        XCTAssertEqual(LightForecastText.spot(for: sample.places[0], in: index)?.slug, "takaya")
        XCTAssertEqual(sample.places[1].slug, "sample-2")
        // 渡さなければ今までどおり
        XCTAssertEqual(LightForecastText.sample(now: now).places.map(\.slug),
                       ["sample-1", "sample-2", "sample-3", "sample-4"])
    }

    /// 画面: 四角は写真・開閉の印・開いた中の2行。**Apple Weather の出典は残す**
    func testForecastCardWiresPhotoDisclosureAndLinks() async throws {
        let view = try source("Features/Pro/LightForecastView.swift")
        XCTAssertTrue(view.contains("LightForecastText.spot(for: $0, in: index)"))
        XCTAssertTrue(view.contains("SpotThumbImage(image: photo, assumedRatioLimit: 2)"), "札の四角に写真が無い")
        XCTAssertTrue(view.contains(#"Image(systemName: isOpen ? "chevron.down" : "chevron.right")"#), "開閉の印が無い")
        XCTAssertTrue(view.contains(".accessibilityValue(opens ? LightForecastText.disclosureValue(isOpen: isOpen)"))
        XCTAssertTrue(view.contains("OfficialSpotView(spot: spot, spots: index, photos: [], photosKnown: false)"))
        XCTAssertTrue(view.contains(#".accessibilityIdentifier("lightForecast.openSpot")"#))
        XCTAssertTrue(view.contains("SpotDirections.openDirections(name: name, coords: coords, stillWanted: { onScreen })"))
        XCTAssertTrue(view.contains(#".accessibilityIdentifier("lightForecast.directions")"#))
        // 出典（Apple が表示を求めている）
        XCTAssertTrue(view.contains("Link(destination: forecast.attribution.legalURL)"))
        XCTAssertTrue(view.contains(#".accessibilityIdentifier("lightForecast.attribution")"#))
    }

    // MARK: - 3. 写真を編集

    /// 撮影日の欄 ↔ ピッカー。空・読めない値は nil（「日付を入れる」）。選んだ日は端末の暦の `YYYY-MM-DD`
    func testDatePickerRoundTrip() async throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertNil(EditDay.pickerDate(field: "", in: tokyo))
        XCTAssertNil(EditDay.pickerDate(field: "  ", in: tokyo))
        XCTAssertNil(EditDay.pickerDate(field: "2026-02-30", in: tokyo))
        let picked = try XCTUnwrap(EditDay.pickerDate(field: "2026-09-13", in: tokyo))
        XCTAssertEqual(EditDay.field(picked: picked, in: tokyo), "2026-09-13")
        // 消した欄は「消す」を送る（今までの決まりのまま）
        XCTAssertEqual(EditDay.toSend(opened: "2026-09-13", field: ""), "")
        XCTAssertEqual(EditDay.toSend(opened: "2026-09-13", field: EditDay.field(picked: picked, in: tokyo)), nil)
    }

    /// 選べるのは 1990-01-01 から今まで（サーバーは 1990年より前・未来を断る）
    func testDatePickerRange() async throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let now = Date(timeIntervalSince1970: 1_791_514_800)  // 2026-10-09 12:00 JST
        let range = EditDay.pickerRange(now: now, in: tokyo)
        XCTAssertEqual(EditDay.field(picked: range.lowerBound, in: tokyo), "1990-01-01")
        XCTAssertEqual(range.upperBound, now)
        XCTAssertEqual(EditDay.field(picked: range.upperBound, in: tokyo), "2026-10-09")
    }

    /// 画面: 保存は右上（下のボタンは無い）・欄の上に名前・撮影日はピッカー（手打ちの欄は無い）
    func testEditPhotoWiresTopSaveLabelsAndDatePicker() async throws {
        let edit = try source("Features/Profile/EditPhotoView.swift")
        XCTAssertTrue(edit.contains("ToolbarItem(placement: .confirmationAction) { saveButton }"), "保存が右上に無い")
        XCTAssertTrue(edit.contains(#".accessibilityIdentifier("editPhoto.save")"#))
        // 保存の字は右上の1か所（字と読み上げ）。下のボタンが戻ると増える
        XCTAssertEqual(count("Labels.Common.save", in: edit), 2, "保存ボタンが2つある")
        XCTAssertTrue(edit.contains(#"JPField(L("題", "Title"))"#))
        XCTAssertTrue(edit.contains(#"JPField(L("説明", "Description"), multiline: true)"#))
        XCTAssertTrue(edit.contains(#"Text(L("撮影地", "Place"))"#))
        XCTAssertTrue(edit.contains(#"Text(L("撮影日", "Date taken"))"#))
        XCTAssertTrue(edit.contains("DatePicker("), "撮影日が日付ピッカーでない")
        XCTAssertTrue(edit.contains("in: range, displayedComponents: .date)"))
        XCTAssertTrue(edit.contains("EditDay.pickerRange(now: Date(), in: .current)"))
        XCTAssertFalse(edit.contains("YYYY-MM-DD"), "撮影日を手で打たせる欄が残っている")
        XCTAssertFalse(edit.contains("TextField(L(\"題\""), "題が見本の字だけの欄に戻っている")
    }
}
