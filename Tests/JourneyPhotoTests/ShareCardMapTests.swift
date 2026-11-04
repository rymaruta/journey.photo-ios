import XCTest
@testable import JourneyPhoto

/// SNS 共有カードの地図（案A-3・2026-11-04 owner 了承）と撮影地の折り返しの計算。
/// 描く処理は Linux では空なので、計算だけを切り出して試す（`ShareCardMap`・`ShareCardText`）。
final class ShareCardMapTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JourneyPhoto/Resources")

    private static func shapes(_ name: String) throws -> [ShareCardMap.Shape] {
        let data = try Data(contentsOf: resources.appendingPathComponent("\(name).json"))
        return try JSONDecoder().decode([ShareCardMap.Shape].self, from: data)
    }

    private static let countries: [ShareCardMap.Shape] = (try? shapes("country-outlines")) ?? []

    private func country(_ name: String) throws -> ShareCardMap.Shape {
        try XCTUnwrap(Self.countries.first { $0.n == name }, "\(name) が国の輪郭に無い")
    }

    // MARK: - 枠の寸法

    func testMapFrameIsLargestThatAvoidsSeparatorAndPhotoInEveryRatio() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            let map = layout.mapRect
            // 板（MapASize）の 290×245 以上
            XCTAssertGreaterThanOrEqual(map.width, 290, "\(ratio)")
            XCTAssertGreaterThanOrEqual(map.height, 245, "\(ratio)")
            // 下: 区切り線に当たらない
            XCTAssertLessThan(map.maxY, layout.separatorY, "\(ratio) 区切り線に当たる")
            // 上: 写真の裾の黒が 78% より薄い所（写真が透ける所）に掛からない
            XCTAssertGreaterThanOrEqual(layout.fadeAlpha(atY: map.minY), 0.78, "\(ratio) 写真に掛かる")
            XCTAssertGreaterThanOrEqual(map.minY, layout.fadeY(reaching: 0.78), "\(ratio)")
            XCTAssertGreaterThan(map.minY, layout.photoRect.minY)
            // 横: 撮影地の字（140 幅）と、写真の黒の面の右端の内側
            XCTAssertGreaterThan(map.minX, ShareCardMap.Layout.placeX + ShareCardMap.Layout.placeWidthWithMap)
            XCTAssertLessThanOrEqual(map.maxX, ShareCardMap.Layout.width - ShareCardMap.Layout.margin)
        }
    }

    func testMapFrameMeasuredValues() {
        // 4:5（1080×1350）: rowY 1032・区切り線 1206・帯の 86% は y 946.6
        let portrait = ShareCardMap.Layout(ratio: .portrait)
        XCTAssertEqual(portrait.rowY, 1032)
        XCTAssertEqual(portrait.mapRect, CGRect(x: 722, y: 947, width: 290, height: 250))
        // 9:16 は下の段が高いが、区切り線も帯も撮影者の段から測るので同じ大きさ（縦 300 は取れない）
        let story = ShareCardMap.Layout(ratio: .story)
        XCTAssertEqual(story.mapRect, CGRect(x: 722, y: 1442, width: 290, height: 250))
        let square = ShareCardMap.Layout(ratio: .square)
        XCTAssertEqual(square.mapRect, CGRect(x: 722, y: 677, width: 290, height: 250))
    }

    // MARK: - 残す島

    private func focusBounds(_ name: String, _ latitude: Double, _ longitude: Double) throws
        -> (bounds: ShareCardMap.Bounds, zoom: Double) {
        let shape = try country(name)
        let rect = ShareCardMap.Layout(ratio: .portrait).mapRect
        let focused = try XCTUnwrap(ShareCardMap.focus(shape, latitude: latitude, longitude: longitude, in: rect))
        // 前の描き方（国の全体を 250×185 に収める）と比べた縮尺
        let rings = ShareCardMap.unwrap(shape.r, aroundLongitude: longitude)
        let whole = ShareCardMap.Projection(bounds: try XCTUnwrap(ShareCardMap.Bounds(rings)),
                                            rect: CGRect(x: 0, y: 0, width: 250, height: 185))
        return (focused.projection.bounds, focused.projection.scale / whole.scale)
    }

    func testJapanMainlandDropsRemoteIslands() throws {
        // 山梨（0.5° に丸めたピン）。小笠原（27°N）・沖ノ鳥島（20°N）・南鳥島（154°E）を外す
        let (bounds, zoom) = try focusBounds("Japan", 35.5, 138.5)
        XCTAssertGreaterThan(bounds.south, 30, "小笠原・沖縄が残っている")
        XCTAssertLessThan(bounds.east, 146.5, "南鳥島が残っている")
        XCTAssertGreaterThan(bounds.north, 45, "北海道が外れている")
        XCTAssertLessThan(bounds.west, 130, "九州が外れている")
        XCTAssertEqual(zoom, 1.93, accuracy: 0.03, "板（290×245）では 1.88。枠を測って 250 にした分")
    }

    func testOkinawaKeepsOkinawa() throws {
        // 那覇（26.21, 127.68）は丸めると海の上（26.0, 127.5）。いちばん近い島＝沖縄本島が残る
        let pin = try XCTUnwrap(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 26.2124, lng: 127.6809)))
        let (bounds, zoom) = try focusBounds("Japan", pin.latitude, pin.longitude)
        XCTAssertLessThanOrEqual(bounds.south, 26.2)
        XCTAssertLessThanOrEqual(bounds.west, 127.7)
        XCTAssertGreaterThan(bounds.north, 45, "本土（一番大きい陸）も残す")
        XCTAssertEqual(zoom, 1.51, accuracy: 0.03)
    }

    func testOgasawaraKeepsOgasawara() throws {
        let (bounds, _) = try focusBounds("Japan", 27.0, 142.0)
        XCTAssertLessThanOrEqual(bounds.south, 27.0, "撮った小笠原が外れている")
        XCTAssertGreaterThanOrEqual(bounds.east, 142.1)
        XCTAssertLessThan(bounds.east, 146.5, "南鳥島は 60km より遠い")
    }

    func testFranceDropsOverseasDepartments() throws {
        let (bounds, zoom) = try focusBounds("France", 48.5, 2.5)
        XCTAssertGreaterThan(bounds.west, -6)
        XCTAssertLessThan(bounds.east, 10)
        XCTAssertGreaterThan(bounds.south, 41)
        XCTAssertLessThan(bounds.north, 52)
        XCTAssertEqual(zoom, 12.98, accuracy: 0.2)
    }

    func testHawaiiKeepsHawaiiAndMainland() throws {
        let (bounds, _) = try focusBounds("United States of America", 21.5, -158.0)
        XCTAssertLessThanOrEqual(bounds.west, -158, "撮ったハワイが外れている")
        XCTAssertLessThan(bounds.south, 21.5)
        XCTAssertGreaterThan(bounds.east, -70, "一番大きい陸（本土）も残す")
        XCTAssertLessThan(bounds.north, 50, "アラスカは 60km より遠い")
    }

    func testUSMainlandDropsHawaiiAndAlaska() throws {
        let (bounds, _) = try focusBounds("United States of America", 40.5, -74.0)
        XCTAssertGreaterThan(bounds.west, -125)
        XCTAssertGreaterThan(bounds.south, 24)
        XCTAssertLessThan(bounds.north, 50)
    }

    func testItalyKeepsSicilyAndSardinia() throws {
        let (bounds, zoom) = try focusBounds("Italy", 41.5, 12.5)
        XCTAssertLessThan(bounds.south, 37, "シチリア")
        XCTAssertLessThan(bounds.west, 8.5, "サルデーニャ")
        XCTAssertEqual(zoom, 1.38, accuracy: 0.03)
    }

    func testFocusAcrossAntimeridianStaysNarrow() throws {
        // フィジーは ±180° をまたぐ。開いて 360° 幅にならない
        let (bounds, _) = try focusBounds("Fiji", -16.5, 179.8)
        XCTAssertLessThan(bounds.east - bounds.west, 10)
        let (russia, _) = try focusBounds("Russia", 66.0, -179.0)
        XCTAssertLessThan(russia.east - russia.west, 200)
    }

    // MARK: - 塗る県

    func testPrefectureNameFromShareCardLocation() {
        XCTAssertEqual(ShareCardMap.prefectureName(in: "千葉県（市原市）"), "千葉県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "山梨県（山中湖村）"), "山梨県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "北海道（札幌市）"), "北海道")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "東京都"), "東京都")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "清水寺 (京都府, 京都市)"), "京都府")
        XCTAssertNil(ShareCardMap.prefectureName(in: "Florence, Italy"))
        XCTAssertNil(ShareCardMap.prefectureName(in: "Versailles, Île-de-France, フランス"))
        XCTAssertNil(ShareCardMap.prefectureName(in: "イヴリーヌ県（フランス）"), "海外の「県」は塗らない")
        XCTAssertNil(ShareCardMap.prefectureName(in: "千葉"), "県名がそのまま無ければ塗らない")
        XCTAssertNil(ShareCardMap.prefectureName(in: nil))
    }

    func testBundledPrefecturesMatchRegionList() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(prefectures.map(\.n), RegionList.prefectures)
        let yamanashi = try XCTUnwrap(prefectures.first { $0.n == "山梨県" })
        // 山中湖（35.42, 138.87）が山梨県の輪の中
        XCTAssertTrue(yamanashi.r.contains {
            ShareCardMap.ringContains($0, longitude: 138.87, latitude: 35.42)
        })
        let okinawa = try XCTUnwrap(prefectures.first { $0.n == "沖縄県" })
        XCTAssertFalse(okinawa.r.contains {
            ShareCardMap.ringContains($0, longitude: 138.87, latitude: 35.42)
        })
    }

    func testPrefectureShapeRequiresNearbyPin() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(ShareCardMap.prefectureShape(named: "千葉県", among: prefectures,
                                                    latitude: 35.5, longitude: 140.0)?.n, "千葉県")
        // 文字は千葉県なのにピンが沖縄: 食い違うので塗らない
        XCTAssertNil(ShareCardMap.prefectureShape(named: "千葉県", among: prefectures,
                                                  latitude: 26.0, longitude: 127.5))
        XCTAssertNil(ShareCardMap.prefectureShape(named: nil, among: prefectures,
                                                  latitude: 35.5, longitude: 140.0))
    }


    func testEnglishPrefectureNamesAreFilled() throws {
        // 英語の環境の日本の写真でも県を塗る（2026-11-04 確かめ役の指摘）
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Kyoto, (Higashiyama)"), "京都府")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Miyagi Prefecture"), "宮城県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Hyōgo Prefecture"), "兵庫県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Tokyo"), "東京都")
        XCTAssertNil(ShareCardMap.prefectureName(in: "Paris, (Versailles)"))
        XCTAssertEqual(ShareCardMap.englishPrefectures.count, RegionList.prefectures.count)
    }

    // MARK: - 撮影地の2行（2026-11-04 owner）

    private func lines(_ raw: String?) -> [String] {
        LocationMatch.shareCardPlace(raw)?.lines ?? []
    }

    func testJapanPlaceIsPrefectureThenCity() {
        XCTAssertEqual(lines("月崎, 大多喜里見線, 市原市, 千葉県, 290-0000, 日本"), ["千葉県", "（市原市）"])
        XCTAssertEqual(lines("山中湖村, 山梨県, 日本"), ["山梨県", "（山中湖村）"], "座標からの自動入力の形")
        XCTAssertEqual(lines("富士山, 静岡県, 日本"), ["静岡県"], "市区町村が無ければ1行")
        XCTAssertEqual(lines("東京タワー, 港区, 東京都, 105-0011, 日本"), ["東京都", "（港区）"])
        XCTAssertEqual(lines("札幌市時計台, 中央区, 札幌市, 北海道, 060-0001, 日本"), ["北海道", "（札幌市）"])
        XCTAssertEqual(lines("横浜赤レンガ倉庫, 中区, 横浜市, 神奈川県, 231-0001, 日本"), ["神奈川県", "（横浜市）"])
        XCTAssertEqual(lines("北海道"), ["北海道"])
        XCTAssertEqual(lines("千葉県（市原市）"), ["千葉県", "（市原市）"], "shareCardDisplay の形も割る")
        XCTAssertEqual(lines("宮城県, 白石市, 蔵王キツネ村"), ["宮城県", "（白石市）"], "人が大きい順に打った形")
    }

    func testJapanPlaceInEnglish() {
        XCTAssertEqual(lines("Kiyomizu-dera, 1, Kiyomizu, Higashiyama Ward, Kyoto, Kyoto Prefecture, 605-0862, Japan"),
                       ["Kyoto", "(Higashiyama)"])
        XCTAssertEqual(lines("Zao Fox Village, Minamizao Shichikashuku Line, Fukuoka Hachimiya, Shiroishi, Miyagi Prefecture, 989-0733, Japan"),
                       ["Miyagi", "(Shiroishi)"])
        XCTAssertEqual(lines("Tokyo, Japan"), ["Tokyo"])
    }

    func testOverseasPlaceIsCountryThenSmallestName() {
        XCTAssertEqual(lines("ヴェルサイユ, Versailles, Yvelines, イル＝ド＝フランス地域圏, フランス・メトロポリテーヌ, 78000, フランス"),
                       ["フランス", "（ヴェルサイユ）"])
        XCTAssertEqual(lines("ニューヨーク, ニューヨーク州, アメリカ合衆国"), ["アメリカ合衆国", "（ニューヨーク）"])
        XCTAssertEqual(lines("ローマ, ラツィオ州, イタリア"), ["イタリア", "（ローマ）"])
        XCTAssertEqual(lines("ソウル, 韓国"), ["韓国", "（ソウル）"])
        // ラテン文字だけなら半角の括弧（中身との間に空白を入れない）
        XCTAssertEqual(lines("Versailles, Yvelines, Île-de-France, Metropolitan France, 78000, France"),
                       ["France", "(Versailles)"])
        XCTAssertEqual(lines("Paris, Île-de-France, France"), ["France", "(Paris)"])
        // 人が打った短い文字・大きい順の英文は1行のまま
        XCTAssertEqual(lines("山中湖"), ["山中湖"])
        XCTAssertEqual(lines("Paris"), ["Paris"])
        XCTAssertEqual(lines("オペラ・ガルニエ（パリ）"), ["オペラ・ガルニエ（パリ）"])
        XCTAssertEqual(lines("Miyagi Prefecture, Shiroishi, Zao Fox Village"),
                       ["Miyagi Prefecture, Shiroishi, Zao Fox Village"])
        XCTAssertEqual(lines(nil), [])
        XCTAssertEqual(lines("  "), [])
    }

    /// Web の app/data/photos.json の 30 件の `location`（2026-11-04 に写した実データ）
    func testAllWebSampleLocations() {
        let cases: [(String?, [String])] = [
            ("山中湖", ["山中湖"]), ("山中湖", ["山中湖"]), ("バルセロナ", ["バルセロナ"]), ("パリ", ["パリ"]),
            ("大阪", ["大阪"]), ("東京", ["東京"]), ("東京", ["東京"]), ("フィンランド", ["フィンランド"]),
            (nil, []), ("福岡", ["福岡"]), ("フランス", ["フランス"]), (nil, []), (nil, []),
            ("フランス ヴェルサイユ", ["フランス ヴェルサイユ"]), ("パリ, フランス", ["フランス", "（パリ）"]),
            ("フランス ヴェルサイユ", ["フランス ヴェルサイユ"]), ("北海道", ["北海道"]),
            ("オペラ・ガルニエ（パリ）", ["オペラ・ガルニエ（パリ）"]),
            ("香川県 観音寺市 高屋神社", ["香川県", "（観音寺市）"]),
            (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []),
            ("茨城県 ひたちなか市 国営ひたち海浜公園", ["茨城県", "（ひたちなか市）"]),
        ]
        XCTAssertEqual(cases.count, 30)
        for (raw, expected) in cases {
            XCTAssertEqual(lines(raw), expected, raw ?? "nil")
        }
    }

    // MARK: - 字の収め方

    /// 和文は1字＝字の大きさ、欧文は半分で測る（Linux には字の形が無いため）
    private func measure(_ text: String, _ size: CGFloat) -> CGFloat {
        text.reduce(CGFloat(0)) { width, character in
            width + (character.isASCII || "Îé".contains(character) ? size * 0.5 : size)
        }
    }

    func testPlaceLinesShareOneSizeAndNeverWrap() {
        let fitted = ShareCardText.fitLines(["山梨県", "（山中湖村）"], maxWidth: 140, preferredSize: 26,
                                            minimumSize: 18.72, measure: measure)
        // 2行目（6字）が入る 23 に、1行目もそろえる
        XCTAssertEqual(fitted.size, 23)
        XCTAssertEqual(fitted.lines, ["山梨県", "（山中湖村）"])
        XCTAssertFalse(fitted.truncated)
    }

    func testLongOverseasCityKeepsClosingBracket() {
        let fitted = ShareCardText.fitLines(["フランス", "（サン＝ジェルマン＝アン＝レー）"], maxWidth: 140,
                                            preferredSize: 26, minimumSize: 18.72, measure: measure)
        XCTAssertTrue(fitted.truncated)
        XCTAssertEqual(fitted.size, 18.72)
        XCTAssertEqual(fitted.lines[0], "フランス")
        XCTAssertTrue(fitted.lines[1].hasPrefix("（サン"), fitted.lines[1])
        XCTAssertTrue(fitted.lines[1].hasSuffix("…）"), fitted.lines[1])
        XCTAssertLessThanOrEqual(measure(fitted.lines[1], fitted.size), 140)
        let latin = ShareCardText.fitLines(["France", "(Saint-Germain-en-Laye-sur-Seine)"], maxWidth: 140,
                                           preferredSize: 26, minimumSize: 18.72, measure: measure)
        XCTAssertTrue(latin.lines[1].hasSuffix("…)"), latin.lines[1])
    }

    func testPlaceTwoLinesFitAboveSeparator() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            let bottom = layout.rowY + ShareCardMap.Layout.placeTopFromRow + ShareCardMap.Layout.placeHeight
            // 区切り線の上・撮影者の段の縦の罫線（rowY+105）の中に収まる
            XCTAssertLessThan(bottom, layout.rowY + 105, "\(ratio)")
            XCTAssertLessThan(bottom, layout.separatorY, "\(ratio)")
        }
    }

    func testSegmentsBreakOnlyAtSeparators() {
        XCTAssertEqual(ShareCardText.segments("Versailles, Île-de-France, フランス"),
                       ["Versailles, ", "Île-de-France, ", "フランス"])
        XCTAssertEqual(ShareCardText.segments("清水寺 (京都府, 京都市)"), ["清水寺 ", "(京都府, 京都市)"],
                       "括弧の中では折らない")
        XCTAssertEqual(ShareCardText.segments("東京・浅草、雷門"), ["東京・", "浅草、", "雷門"])
        // 「/」は後ろが空白のときだけ（「f/2.8」で折らない）
        XCTAssertEqual(ShareCardText.segments("NIKKOR Z 24-70mm f/2.8 S"),
                       ["NIKKOR ", "Z ", "24-70mm ", "f/2.8 ", "S"])
        XCTAssertEqual(ShareCardText.segments("A / B"), ["A ", "/ ", "B"])
    }

    func testEquipmentFitShrinksWithoutMidWordBreak() {
        let fitted = ShareCardText.fit("Hasselblad XCD 35-100E f/2.8-4 Zoom Lens", maxWidth: 120,
                                       preferredSize: 22, minimumSize: 7, step: 0.5,
                                       maxLines: { _ in 3 }, measure: measure)
        XCTAssertFalse(fitted.truncated)
        XCTAssertEqual(fitted.lines.joined(separator: " ").split(separator: " "),
                       "Hasselblad XCD 35-100E f/2.8-4 Zoom Lens".split(separator: " "))
        for line in fitted.lines { XCTAssertLessThanOrEqual(measure(line, fitted.size), 120) }
    }

    /// 島選びの所要時間（輪の多い国）。Mac の記録に出す（2026-11-04 確かめ役の指摘）
    func testFocusTimeForCountriesWithManyIslands() throws {
        for (name, latitude, longitude) in [("Canada", 45.5, -73.5), ("Russia", 55.5, 37.5),
                                           ("United States of America", 40.5, -74.0),
                                           ("Indonesia", -6.0, 107.0)] {
            let shape = try country(name)
            let start = Date()
            _ = ShareCardMap.focus(shape, latitude: latitude, longitude: longitude,
                                   in: ShareCardMap.Layout(ratio: .portrait).mapRect)
            let seconds = Date().timeIntervalSince(start)
            print("SHARECARD-TIME \(name) rings=\(shape.r.count) seconds=\(String(format: "%.3f", seconds))")
            XCTAssertLessThan(seconds, 2, "\(name) の島選びが重い")
        }
    }

    /// 上の帯（2026-11-04 owner「ヘッダーは詰められそう」: 118 → 96）。中身が枠にも写真にも当たらず、
    /// 元の上下の比（枠から 59.5・写真まで 46.5）を保つ
    func testHeaderBandIsTighterAndKeepsItsContentInside() {
        let hs = ShareCardMap.Layout.headerShift
        let header = ShareCardMap.Layout.header
        XCTAssertEqual(header, 96)
        // 帯の中身の縦の範囲: 区切り線（46〜103）が最も外。ロゴは 49〜94
        let contentTop = 46 + hs
        let contentBottom = 103 + hs
        let frameInner: CGFloat = 12   // 枠の内側（8 + 4）
        XCTAssertGreaterThanOrEqual(contentTop - frameInner, 16, "枠に近すぎない")
        XCTAssertGreaterThanOrEqual(header - contentBottom, 4, "写真に当たらない")
        // 中心の上下の比（元は 59.5 : 46.5）
        let center = (49 + hs) + 45 / 2
        XCTAssertEqual(center - frameInner, 45.5, accuracy: 0.01)
        XCTAssertEqual(header - center, 38.5, accuracy: 0.01)
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            XCTAssertEqual(layout.photoRect.minY, header, "\(ratio) 写真は帯の下から")
            XCTAssertGreaterThan(layout.photoRect.height, 0)
        }
    }
}
