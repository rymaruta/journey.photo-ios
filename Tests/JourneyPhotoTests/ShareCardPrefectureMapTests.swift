import XCTest
@testable import JourneyPhoto

/// 座標の無い写真でも、撮影地の文字から都道府県が分かれば共有カードに地図を出す
/// （2026-11-19 owner「位置情報が無い写真でも、撮影地の名前（県など）が分かるなら地図を出してほしい」・
/// `SignatureShareCardRenderer.Credit.mapCoordinate`）。描く処理は Linux では空なので、ピンの点を試す。
final class ShareCardPrefectureMapTests: XCTestCase {
    private typealias R = SignatureShareCardRenderer

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func shapes(_ name: String) throws -> [ShareCardMap.Shape] {
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/\(name).json"))
        return try JSONDecoder().decode([ShareCardMap.Shape].self, from: data)
    }

    /// 本番と同じ組み立て（`PostedShareCardCredit.make`）で作るカードの情報
    private func credit(location: String?, coords: (Double, Double)? = nil) throws -> R.Credit {
        var object: [String: Any] = ["id": "p1", "src": "https://x/p1.jpg", "displayName": "あや"]
        if let location { object["location"] = location }
        if let coords { object["coords"] = ["lat": coords.0, "lng": coords.1] }
        let data = try JSONSerialization.data(withJSONObject: object)
        let photo = try JSONDecoder.api.decode(Photo.self, from: data)
        return PostedShareCardCredit.make(photo: photo, me: nil)
    }

    private func office(_ prefecture: String) throws -> Photo.Coords {
        try XCTUnwrap(PassExchange.prefectureOffices[prefecture], prefecture)
    }

    private func assertPin(_ location: String, at prefecture: String,
                           file: StaticString = #filePath, line: UInt = #line) throws {
        let c = try credit(location: location)
        XCTAssertNil(c.coords, "座標は無いまま", file: file, line: line)
        let pin = try XCTUnwrap(c.mapCoordinate, "\(location) で地図が出ない", file: file, line: line)
        let expected = try office(prefecture)
        XCTAssertEqual(pin.latitude, expected.lat, accuracy: 1e-9, location, file: file, line: line)
        XCTAssertEqual(pin.longitude, expected.lng, accuracy: 1e-9, location, file: file, line: line)
    }

    func testKanazawaWithoutCoordsPinsIshikawa() throws {
        try assertPin("金沢市, 石川県", at: "石川県")
        let pin = try XCTUnwrap(try credit(location: "金沢市, 石川県").mapCoordinate)
        XCTAssertEqual(pin.latitude, 36.594, accuracy: 1e-9)
        XCTAssertEqual(pin.longitude, 136.626, accuracy: 1e-9)
        // 塗る県も石川県になる（ピンが県の輪郭の外接矩形の中）
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(ShareCardMap.prefectureShape(named: "石川県", among: prefectures,
                                                    latitude: pin.latitude, longitude: pin.longitude)?.n, "石川県")
    }

    /// 都・道・府の4つを、和文と英文の住所の形の両方で取る
    func testTokyoOsakaKyotoHokkaidoInJapaneseAndEnglish() throws {
        let cases: [(String, String)] = [
            ("新宿区, 東京都", "東京都"),
            ("東京都新宿区西新宿2-8-1", "東京都"),
            ("石川県金沢市 兼六園", "石川県"),
            ("京都府京都市東山区", "京都府"),
            ("Shinjuku, Tokyo, Japan", "東京都"),
            ("大阪市, 大阪府", "大阪府"),
            ("Osaka, Japan", "大阪府"),
            ("清水寺, 京都市, 京都府, 日本", "京都府"),
            ("Kyoto, Kyoto Prefecture, Japan", "京都府"),
            ("札幌市, 北海道", "北海道"),
            ("Sapporo, Hokkaido, Japan", "北海道"),
            ("金沢市, 石川県, 920-0936, 日本", "石川県"),
            ("Kanazawa, Ishikawa Prefecture, Japan", "石川県"),
            ("Kanazawa, Ishikawa", "石川県"),
        ]
        for (location, prefecture) in cases {
            try assertPin(location, at: prefecture)
        }
    }

    /// 「東京都」の中の「京都」を京都府にしない
    func testTokyoIsNotKyoto() throws {
        try assertPin("東京都", at: "東京都")
    }

    func testNoMapWhenPrefectureIsUnknownOrHidden() throws {
        // 海外
        XCTAssertNil(try credit(location: "Florence, Tuscany, Italy").mapCoordinate)
        XCTAssertNil(try credit(location: "ヴェルサイユ, イヴリーヌ県, フランス").mapCoordinate)
        // 県が分からない
        XCTAssertNil(try credit(location: "富士山, 日本").mapCoordinate)
        XCTAssertNil(try credit(location: "千葉").mapCoordinate)
        // 撮影地を出さない（撮影地の文字が無い）
        XCTAssertNil(try credit(location: nil).mapCoordinate)
        XCTAssertNil(try credit(location: "").mapCoordinate)
        XCTAssertNil(R.prefectureMapCoordinate(placeLines: [], location: nil))
    }

    /// 座標のある写真は今までどおり約50km単位（県の代表点に寄せない）
    func testPhotoWithCoordsKeepsTheRoundedPoint() throws {
        let c = try credit(location: "兼六園, 金沢市, 石川県", coords: (36.5621, 136.6625))
        XCTAssertEqual(c.mapCoordinate?.latitude, 36.5)
        XCTAssertEqual(c.mapCoordinate?.longitude, 136.5)
        XCTAssertEqual(c.mapCoordinate?.latitude, c.coords?.latitude)
        XCTAssertEqual(c.mapCoordinate?.longitude, c.coords?.longitude)
        // 文字が海外でも、座標があれば今までどおり地図を出す
        let paris = try credit(location: "Paris, France", coords: (48.8566, 2.3522))
        XCTAssertEqual(paris.mapCoordinate?.latitude, 49.0)
        XCTAssertEqual(paris.mapCoordinate?.longitude, 2.5)
    }

    /// 県の代表点は47県すべてにあり、どれも地図に日本が出て（輪郭の中か、海岸から 0.15° 以内・`CountryOutline.shapeForDisplay`
    /// と同じ受け方）、その県が塗られる（`prefectureShape`）。鹿児島県庁は同梱の輪郭では海岸の外 0.038° に落ちる（2026-11-19 測った）
    func testPrefectureOfficesLieInsideTheirPrefecture() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        let japan = try XCTUnwrap(try Self.shapes("country-outlines").first { $0.n == "Japan" })
        XCTAssertEqual(Set(PassExchange.prefectureOffices.keys), Set(RegionList.prefectures))
        var outside: [String] = []
        for name in RegionList.prefectures {
            let point = try office(name)
            XCTAssertEqual(ShareCardMap.prefectureShape(named: name, among: prefectures,
                                                        latitude: point.lat, longitude: point.lng)?.n, name,
                           "\(name) が塗られない")
            if japan.r.contains(where: { ShareCardMap.ringContains($0, longitude: point.lng, latitude: point.lat) }) {
                continue
            }
            outside.append(name)
            let weight = max(0.2, cos(point.lat * .pi / 180))
            let nearest = japan.r.joined().filter { $0.count == 2 }.map { vertex -> Double in
                let dx = (vertex[0] - point.lng) * weight, dy = vertex[1] - point.lat
                return (dx * dx + dy * dy).squareRoot()
            }.min() ?? .infinity
            XCTAssertLessThanOrEqual(nearest, 0.15, "\(name) の代表点が日本の海岸から遠い（地図が出ない）")
        }
        XCTAssertEqual(outside, ["鹿児島県"], "輪郭の外に落ちる代表点")
    }

    /// 地図を描く型（帯・溶かす・ラベル・表紙・切符）は、どれも `mapCoordinate` で地図を出すかを決める
    /// （`credit.coords` で決める型が残ると、座標の無い写真でその型だけ地図が出ない）
    func testEveryMapStyleUsesMapCoordinate() throws {
        let files = ["SignatureShareCardRenderer.swift", "SignatureShareCardStyles.swift",
                     "SignatureShareCardNewStyles.swift", "SignatureShareCardMoreStyles.swift",
                     "ShareCardMoreLayouts.swift", "ShareCardNewLayouts.swift"]
        var uses = 0
        for file in files {
            let text = try String(contentsOf: Self.root.appendingPathComponent("Sources/JourneyPhoto/Services/\(file)"),
                                  encoding: .utf8)
            XCTAssertFalse(text.contains("credit.coords"), "\(file) が座標だけで地図を決めている")
            uses += text.components(separatedBy: "credit.mapCoordinate").count - 1
        }
        // 帯（幅・地図・区切り線の3か所）・溶かす・ラベル・表紙・切符
        XCTAssertEqual(uses, 7)
    }
}
