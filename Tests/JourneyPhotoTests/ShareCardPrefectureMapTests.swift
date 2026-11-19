import XCTest
import CoreLocation
@testable import JourneyPhoto

/// 座標の無い写真でも、撮影地の文字から市区町村・都道府県が分かれば共有カードに地図を出す
/// （2026-11-19 owner「位置情報が無い写真でも、撮影地の名前（県など）が分かるなら地図を出してほしい」
/// 「金沢市, 石川県なら金沢市にピン」・`SignatureShareCardRenderer.shareMapPoint`・`Credit.mapCoordinate`）。
/// 描く処理は Linux では空なので、ピンの点を試す。
///
/// 市区町村の表（`japan-municipal-offices.json`）は、Linux の `swift test` ではアプリの束に無い
/// （`MunicipalOffices.bundled` が空）。市の試験は表をファイルから読んで渡す
final class ShareCardPrefectureMapTests: XCTestCase {
    private typealias R = SignatureShareCardRenderer

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func resource(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/\(name).json"))
    }

    private static func shapes(_ name: String) throws -> [ShareCardMap.Shape] {
        try JSONDecoder().decode([ShareCardMap.Shape].self, from: resource(name))
    }

    private static let offices: [MunicipalOffices.Entry] =
        (try? MunicipalOffices.parse(resource("japan-municipal-offices"))) ?? []

    /// 本番と同じ組み立て（`PostedShareCardCredit.make`）で作るカードの情報
    private func credit(location: String?, coords: (Double, Double)? = nil) throws -> R.Credit {
        var object: [String: Any] = ["id": "p1", "src": "https://x/p1.jpg", "displayName": "あや"]
        if let location { object["location"] = location }
        if let coords { object["coords"] = ["lat": coords.0, "lng": coords.1] }
        let data = try JSONSerialization.data(withJSONObject: object)
        let photo = try JSONDecoder.api.decode(Photo.self, from: data)
        return PostedShareCardCredit.make(photo: photo, me: nil)
    }

    /// カードと同じ文字（place は shareCardPlace、location は shareCardDisplay）で引いたピン
    private func point(_ raw: String, cityLevel: Bool) -> CLLocationCoordinate2D? {
        R.shareMapPoint(place: LocationMatch.shareCardPlace(raw), location: LocationMatch.shareCardDisplay(raw),
                        cityLevel: cityLevel, offices: Self.offices)
    }

    private func office(_ prefecture: String) throws -> Photo.Coords {
        try XCTUnwrap(PassExchange.prefectureOffices[prefecture], prefecture)
    }

    private func city(_ name: String, _ prefecture: String) throws -> Photo.Coords {
        let hits = Self.offices.filter { $0.name == name && $0.prefecture == prefecture }
        XCTAssertEqual(hits.count, 1, "\(prefecture) \(name)")
        return try XCTUnwrap(hits.first?.coords, "\(prefecture) \(name) が表に無い")
    }

    private func assertPin(_ pin: CLLocationCoordinate2D?, at expected: Photo.Coords, _ message: String,
                           file: StaticString = #filePath, line: UInt = #line) throws {
        let pin = try XCTUnwrap(pin, "\(message) で地図が出ない", file: file, line: line)
        XCTAssertEqual(pin.latitude, expected.lat, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(pin.longitude, expected.lng, accuracy: 1e-9, message, file: file, line: line)
    }

    // MARK: - 市区町村

    /// 「金沢市, 石川県」は金沢市役所（36.561, 136.657）に打つ。ぼかさない（0.5° に丸めると 36.5, 136.5）
    func testKanazawaPinsKanazawaCityOffice() throws {
        let kanazawa = try city("金沢市", "石川県")
        XCTAssertEqual(kanazawa.lat, 36.561, accuracy: 1e-9)
        XCTAssertEqual(kanazawa.lng, 136.657, accuracy: 1e-9)
        for raw in ["金沢市, 石川県", "兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本", "石川県（金沢市）", "金沢市"] {
            try assertPin(point(raw, cityLevel: true), at: kanazawa, raw)
        }
        // 塗る県も石川県になる（ピンが県の輪郭の外接矩形の中）
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(ShareCardMap.prefectureShape(named: "石川県", among: prefectures,
                                                    latitude: kanazawa.lat, longitude: kanazawa.lng)?.n, "石川県")
    }

    /// 本番の束（Mac の単体テスト・アプリの中）では、カードの情報からそのまま金沢市に打つ。Linux では表が束に無いので飛ばす
    func testCreditUsesTheBundledCityTable() throws {
        try XCTSkipIf(MunicipalOffices.bundled.isEmpty, "Linux の swift test には同梱の表が無い")
        try assertPin(try credit(location: "金沢市, 石川県").mapCoordinate, at: try city("金沢市", "石川県"), "金沢市, 石川県")
    }

    /// 投稿の共有カード（`Credit.mapCoordinate`）は市まで引く（`cityLevel: true`）。Linux でも見張れるよう、
    /// 同梱の表を読まずに小さな表を渡す（点はわざと本物と違う値にして、表から来たと分かるようにする）
    func testCreditPinsTheCityWithAGivenTable() throws {
        let table = [MunicipalOffices.Entry(prefecture: "石川県", name: "金沢市", coords: Photo.Coords(lat: 36.111, lng: 136.222)),
                     MunicipalOffices.Entry(prefecture: "東京都", name: "府中市", coords: Photo.Coords(lat: 35.111, lng: 139.222)),
                     MunicipalOffices.Entry(prefecture: "広島県", name: "府中市", coords: Photo.Coords(lat: 34.111, lng: 133.222))]
        try assertPin(try credit(location: "金沢市, 石川県").mapCoordinate(offices: table),
                      at: Photo.Coords(lat: 36.111, lng: 136.222), "金沢市, 石川県")
        try assertPin(try credit(location: "府中市, 広島県").mapCoordinate(offices: table),
                      at: Photo.Coords(lat: 34.111, lng: 133.222), "府中市, 広島県")
        // 表に無い市は県庁
        try assertPin(try credit(location: "加賀市, 石川県").mapCoordinate(offices: table),
                      at: try office("石川県"), "加賀市, 石川県")
        // 座標のある写真は表を見ない
        let withCoords = try credit(location: "金沢市, 石川県", coords: (36.5621, 136.6625)).mapCoordinate(offices: table)
        XCTAssertEqual(withCoords?.latitude, 36.5)
        XCTAssertEqual(withCoords?.longitude, 136.5)
    }

    /// ピンと塗りは同じ引き方で県を決める（`ShareCardMap.cardPrefecture`・2026-11-19 確かめ役の指摘）。
    /// 区切りの無い住所でも、ピンを打った県が塗られる
    func testPinAndFillUseTheSamePrefecture() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        let cases: [(String, String)] = [
            ("東京都新宿区西新宿2-8-1", "東京都"),
            ("石川県金沢市 兼六園", "石川県"),
            ("京都府京都市東山区", "京都府"),
            ("金沢市, 石川県", "石川県"),
            ("Kyoto, Kyoto Prefecture, Japan", "京都府"),
        ]
        for (raw, prefecture) in cases {
            let c = try credit(location: raw)
            let pin = try XCTUnwrap(c.mapCoordinate(offices: Self.offices), raw)
            // 描く側と同じ文字（`drawAtLocation` に渡す placeText）
            let placeText = (c.placeLines + [c.location ?? ""]).joined(separator: ", ")
            XCTAssertEqual(ShareCardMap.cardPrefecture(in: placeText), prefecture, raw)
            XCTAssertEqual(ShareCardMap.fillShape(place: placeText, among: prefectures,
                                                  latitude: pin.latitude, longitude: pin.longitude)?.n, prefecture, raw)
        }
        // 海外の「〜県」は塗らない
        XCTAssertNil(ShareCardMap.cardPrefecture(in: "イヴリーヌ県（フランス）"))
        // 描く側がこの関数を使っている
        let renderer = try String(contentsOf: Self.root.appendingPathComponent("Sources/JourneyPhoto/Services/SignatureShareCardRenderer.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(renderer.contains("ShareCardMap.fillShape(place: place, among: prefectures,"))
        XCTAssertTrue(renderer.contains("let prefecture = ShareCardMap.cardPrefecture(in: text)"))
    }

    /// 同じ名前の市区町村は県と組み合わせて引く。県が分からず名前が重なるときは引かない
    func testSameNamedMunicipalitiesNeedThePrefecture() throws {
        let fuchuTokyo = try city("府中市", "東京都"), fuchuHiroshima = try city("府中市", "広島県")
        XCTAssertGreaterThan(abs(fuchuTokyo.lng - fuchuHiroshima.lng), 5)
        try assertPin(point("府中市, 東京都", cityLevel: true), at: fuchuTokyo, "府中市, 東京都")
        try assertPin(point("府中市, 広島県", cityLevel: true), at: fuchuHiroshima, "府中市, 広島県")
        try assertPin(point("東京都（府中市）", cityLevel: true), at: fuchuTokyo, "東京都（府中市）")
        // 港区: 東京都の特別区と、名古屋市・大阪市の区（表では「名古屋市港区」）
        let minato = try city("港区", "東京都")
        try assertPin(point("港区, 東京都", cityLevel: true), at: minato, "港区, 東京都")
        try assertPin(point("港区, 名古屋市, 愛知県", cityLevel: true), at: try city("名古屋市", "愛知県"), "名古屋市港区")
        // 県が分からず名前が重なる: 市では引かず、県も無いので地図を出さない
        XCTAssertNil(point("府中市", cityLevel: true))
        XCTAssertNil(MunicipalOffices.office(named: "府中市", prefecture: nil, among: Self.offices))
        XCTAssertNil(MunicipalOffices.office(named: "港区", prefecture: nil, among: Self.offices), "名古屋市・大阪市にも港区がある")
        XCTAssertNil(point("港区", cityLevel: true))
        // 県と名前が合わないものは引かない（金沢市は石川県だけ）
        XCTAssertNil(MunicipalOffices.office(named: "金沢市", prefecture: "富山県", among: Self.offices))
        try assertPin(point("金沢市, 富山県", cityLevel: true), at: try office("富山県"), "県と合わない市は県まで")
        // 「ヶ」「ケ」の揺れ
        XCTAssertNotNil(MunicipalOffices.office(named: "鎌ヶ谷市", prefecture: "千葉県", among: Self.offices))
    }

    /// 県までの細かさでは、市区町村が分かっても県の代表点
    func testPrefectureLevelPinsThePrefectureOffice() throws {
        let ishikawa = try office("石川県")
        XCTAssertEqual(ishikawa.lat, 36.594, accuracy: 1e-9)
        try assertPin(point("金沢市, 石川県", cityLevel: false), at: ishikawa, "県まで")
        // 県しか分からない・市が表に無い（英語の市名）ときは、市までの細かさでも県
        try assertPin(point("石川県", cityLevel: true), at: ishikawa, "石川県")
        try assertPin(point("Kanazawa, Ishikawa Prefecture, Japan", cityLevel: true), at: ishikawa, "英語の市名")
        try assertPin(point("兼六園, 石川県", cityLevel: true), at: ishikawa, "市区町村でない欠片")
    }

    // MARK: - 都道府県

    /// 都・道・府の4つを、和文と英文の住所の形の両方で取る（県までの細かさ）
    func testTokyoOsakaKyotoHokkaidoInJapaneseAndEnglish() throws {
        let cases: [(String, String)] = [
            ("新宿区, 東京都", "東京都"),
            ("東京都", "東京都"),   // 「東京都」の中の「京都」を京都府にしない
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
        for (raw, prefecture) in cases {
            try assertPin(point(raw, cityLevel: false), at: try office(prefecture), raw)
        }
        // 4つは市までの細かさでも市の代表点（東京都の新宿区・大阪市・京都市・札幌市）
        try assertPin(point("新宿区, 東京都", cityLevel: true), at: try city("新宿区", "東京都"), "新宿区")
        try assertPin(point("大阪市, 大阪府", cityLevel: true), at: try city("大阪市", "大阪府"), "大阪市")
        try assertPin(point("清水寺, 京都市, 京都府, 日本", cityLevel: true), at: try city("京都市", "京都府"), "京都市")
        try assertPin(point("札幌市, 北海道", cityLevel: true), at: try city("札幌市", "北海道"), "札幌市")
    }

    func testNoMapWhenPlaceIsUnknownOrHidden() throws {
        for level in [true, false] {
            // 海外
            XCTAssertNil(point("Florence, Tuscany, Italy", cityLevel: level))
            XCTAssertNil(point("ヴェルサイユ, イヴリーヌ県, フランス", cityLevel: level))
            // 県も市も分からない
            XCTAssertNil(point("富士山, 日本", cityLevel: level))
            XCTAssertNil(point("千葉", cityLevel: level))
        }
        XCTAssertNil(try credit(location: "Florence, Tuscany, Italy").mapCoordinate)
        XCTAssertNil(try credit(location: "富士山, 日本").mapCoordinate)
        // 撮影地を出さない（撮影地の文字が無い）
        XCTAssertNil(try credit(location: nil).mapCoordinate)
        XCTAssertNil(try credit(location: "").mapCoordinate)
        XCTAssertNil(R.shareMapPoint(place: nil, location: nil, cityLevel: true, offices: Self.offices))
    }

    /// 座標のある写真は今までどおり約50km単位（市・県の代表点に寄せない）
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

    // MARK: - 表

    /// 同梱の市区町村の表: 行の数、47県すべてにあり、各点が自分の県の輪郭の外接矩形の中（塗る県と食い違わない）
    func testBundledMunicipalOfficesTable() throws {
        let data = try Self.resource("japan-municipal-offices")
        print("measured [municipal-offices] rows=\(Self.offices.count) bytes=\(data.count)")
        XCTAssertGreaterThanOrEqual(Self.offices.count, 1850)
        XCTAssertEqual(Set(Self.offices.map(\.prefecture)), Set(RegionList.prefectures))
        let prefectures = try Self.shapes("japan-prefectures")
        var keys = Set<String>()
        var farOff: [String] = []
        for entry in Self.offices {
            XCTAssertTrue(keys.insert("\(entry.prefecture)|\(entry.name)").inserted, "重複 \(entry.prefecture) \(entry.name)")
            XCTAssertTrue("市区町村".contains(entry.name.last ?? " "), entry.name)
            if ShareCardMap.prefectureShape(named: entry.prefecture, among: prefectures,
                                            latitude: entry.coords.lat, longitude: entry.coords.lng) == nil {
                farOff.append("\(entry.prefecture)\(entry.name)")
            }
        }
        // 奄美群島の12市町村だけ。点は正しい（鹿児島県）が、同梱の県の輪郭（Natural Earth）が奄美群島を沖縄県の輪に
        // 入れていて、鹿児島県の輪郭は北緯 29.44° まで（2026-11-19 測った）。このときピンは打ち、県は塗らない
        // （`prefectureShape` が nil。座標のある奄美の写真の今の動きと同じ）
        XCTAssertEqual(Set(farOff), Set(["鹿児島県奄美市", "鹿児島県大和村", "鹿児島県宇検村", "鹿児島県瀬戸内町",
                                         "鹿児島県龍郷町", "鹿児島県喜界町", "鹿児島県徳之島町", "鹿児島県天城町",
                                         "鹿児島県伊仙町", "鹿児島県和泊町", "鹿児島県知名町", "鹿児島県与論町"]),
                       "県の輪郭から 1° 以上離れた市区町村の点")
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
