import XCTest
@testable import JourneyPhoto

/// 探すの「撮影スポット」の段の地図（札 #524 の続き・2026-11-11 owner「iOS 側にもこの機能欲しい」）。
/// 地方の当たり・塗る県・地図の札の中身・「写真｜地図」で段の高さが変わらないこと
final class SpotRegionMapTests: XCTestCase {

    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JourneyPhoto/Resources")

    private func geometry() throws -> PrefectureMapGeometry {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent("japan-prefectures.json"))
        let shapes = try JSONDecoder().decode([ShareCardMap.Shape].self, from: data)
        return try XCTUnwrap(PrefectureMapGeometry.build(shapes: shapes))
    }

    private func spot(_ slug: String, prefecture: String, lat: Double, lng: Double,
                      image: Bool = false) throws -> OfficialSpot {
        let picture = image
            ? ",\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(slug).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}"
            : ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(slug)\",\"stage\":\"published\",\"region\":{\"prefecture\":\"\(prefecture)\"}\(picture),\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}".utf8))
    }

    /// 北海道 5件（写真つき 2件）・東京 1件。九州には無い
    private func spots() throws -> [OfficialSpot] {
        [
            try spot("zz-sapporo", prefecture: "北海道", lat: 43.06, lng: 141.35),
            try spot("akan", prefecture: "北海道", lat: 43.45, lng: 144.10, image: true),
            try spot("asahidake", prefecture: "北海道", lat: 43.66, lng: 142.85),
            try spot("tomita", prefecture: "北海道", lat: 43.42, lng: 142.42, image: true),
            try spot("goryokaku", prefecture: "北海道", lat: 41.80, lng: 140.76),
            try spot("meiji", prefecture: "東京都", lat: 35.676, lng: 139.699),
        ]
    }

    /// 地図の上の点（地図の枠の pt）。投影 → 単位の空間 → 画面
    private func screen(_ g: PrefectureMapGeometry, _ lat: Double, _ lng: Double, container: CGSize) -> CGPoint {
        VisitedMapViewport().screenPoint(forUnit: g.projection.point(latitude: lat, longitude: lng),
                                         content: g.size, container: container)
    }

    // MARK: - 当たり

    private func japan() throws -> (SpotRegionMap, [SpotMapArea]) {
        let map = SpotRegionMap.japan(try geometry())
        let areas = map.areas(SpotMapSource(spots: try spots(), japanGroups: SpotPrefectureIndex.groups(spots: try spots())))
        return (map, areas)
    }

    /// 押した点の県の地方。**撮影スポットの無い地方は選ばない**（押しても何もしない）
    func testRegionAtPointPicksRegionWithSpots() throws {
        let g = try geometry()
        let (map, areas) = try japan()
        let size = CGSize(width: SearchSpotIndexSection.mapWidth(for: g), height: SearchSpotIndexSection.mapHeight)
        func at(_ lat: Double, _ lng: Double) -> String? {
            map.area(at: screen(g, lat, lng, container: size), container: size, in: areas)
        }
        XCTAssertEqual(at(43.06, 141.35), "北海道")
        XCTAssertEqual(at(35.69, 139.70), "関東")
        XCTAssertNil(at(32.88, 131.10), "観光スポットの無い九州（阿蘇・線の内側）を選んだ")
        // 線の外（海）は、いちばん近い地方に寄せる（陣地分け）。日本海の真ん中は撮影スポットのある地方のどれか
        XCTAssertNotNil(at(38.0, 133.0))
    }

    /// 塗るのは選んだ（なぞっている）地方の県だけ。撮影スポットのある県だけを「ある」の地にする
    func testHighlightedAndCovered() throws {
        let (_, areas) = try japan()
        XCTAssertEqual(SpotRegionMap.highlighted("北海道", in: areas), ["北海道"])
        XCTAssertEqual(SpotRegionMap.highlighted("関東", in: areas).count, 7)
        XCTAssertTrue(SpotRegionMap.highlighted(nil, in: areas).isEmpty)
        XCTAssertTrue(SpotRegionMap.highlighted("四国", in: areas).isEmpty, "観光スポットの無い地方は区分に無い")
        XCTAssertEqual(SpotRegionMap.covered(areas), ["北海道", "東京都"])
    }

    // MARK: - 札

    /// 上位の名前は「代表写真がある → 台帳の並び」で 4 件。全部出せないときは「ほか」。行き先はその地方の一覧
    func testRegionCardNames() throws {
        let (_, areas) = try japan()
        let hokkaido = try XCTUnwrap(areas.first { $0.id == "北海道" })
        XCTAssertEqual(hokkaido.names, ["akan", "tomita", "zz-sapporo", "asahidake"])
        XCTAssertEqual(hokkaido.count, 5)
        XCTAssertEqual(hokkaido.namesLine,
                       L("akan、tomita、zz-sapporo、asahidake ほか", "akan, tomita, zz-sapporo, asahidake, and more"))
        XCTAssertEqual(hokkaido.scope, .region("北海道"))
        XCTAssertEqual(hokkaido.seeAll, L("北海道の観光スポットをすべて見る", "See all photo spots in Hokkaido"))
        // 札の字は地方名入り（見出しの全国の「すべて見る」と分ける）
        XCTAssertEqual(hokkaido.seeAllLabel, L("北海道をすべて見る", "See all in 北海道"))
        let kanto = try XCTUnwrap(areas.first { $0.id == "関東" })
        XCTAssertEqual(kanto.namesLine, "meiji", "全部出せたら「ほか」を付けない")
    }

    // MARK: - 地図を足せる作り（2026-11-11 owner「いずれは日本地図以外も選べるようにしたい」）

    /// 試験用の仮の地図の形: 正方形の片が3つ（A1・A2 は区分 A、B1 は区分 B）。横に並ぶ 300×100 の空間
    private struct SquareShapes: SpotMapShapes {
        let size = CGSize(width: 300, height: 100)
        let inset: CGRect? = nil
        let mapPieces: [(name: String, polygons: [[CGPoint]])] = ["A1", "A2", "B1"].enumerated().map { i, name in
            let x = CGFloat(i) * 100
            return (name, [[CGPoint(x: x, y: 0), CGPoint(x: x + 100, y: 0), CGPoint(x: x + 100, y: 100), CGPoint(x: x, y: 100)]])
        }
        func piece(at unit: CGPoint, tolerance: CGFloat) -> String? {
            guard unit.y >= 0, unit.y <= 100, unit.x >= 0, unit.x < 300 else { return nil }
            return ["A1", "A2", "B1"][Int(unit.x / 100)]
        }
        func distance(from unit: CGPoint, toPieces names: Set<String>) -> CGFloat {
            ["A1", "A2", "B1"].enumerated().filter { names.contains($0.element) }
                .map { abs(CGFloat($0.offset) * 100 + 50 - unit.x) }.min() ?? .infinity
        }
    }

    /// 仮の地図: 台帳の国で区分を作る（世界の地図を足すときの形）
    private func squareMap() -> SpotRegionMap {
        SpotRegionMap(id: "squares", title: "仮", shapes: SquareShapes()) { source in
            let byCountry = Dictionary(grouping: source.spots) { $0.region?.country ?? "" }
            return [("A", ["A1", "A2"]), ("B", ["B1"])].compactMap { id, pieces in
                guard let rows = byCountry[id], !rows.isEmpty else { return nil }
                return SpotMapArea(id: id, title: id, count: rows.count, names: rows.map(\.name),
                                   pieces: Set(pieces), coveredPieces: [pieces[0]], scope: .all, seeAll: "\(id) をすべて見る")
            }
        }
    }

    /// 🔴 **型を足すだけで増やせる**: 仮の地図でも、押した点の区分・塗る片・札の中身が同じ口で取れる。
    /// 日本以外の地図は、地方のチップと選択を分ける
    func testAnotherMapWorksThroughTheSameType() throws {
        func spot(_ slug: String, country: String) throws -> OfficialSpot {
            try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
                "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(slug)\",\"stage\":\"published\",\"region\":{\"country\":\"\(country)\"},\"coords\":{\"lat\":0,\"lng\":0}}".utf8))
        }
        let map = squareMap()
        let areas = map.areas(SpotMapSource(spots: [try spot("a", country: "A"), try spot("b", country: "A")], japanGroups: []))
        XCTAssertEqual(areas.map(\.id), ["A"], "観光スポットの無い区分 B は作らない")
        let size = CGSize(width: 150, height: 50)
        XCTAssertEqual(map.area(at: CGPoint(x: 70, y: 25), container: size, in: areas), "A", "A2 を押したら区分 A")
        XCTAssertNil(map.area(at: CGPoint(x: 130, y: 25), container: size, in: areas), "観光スポットの無い区分を選んだ")
        XCTAssertEqual(SpotRegionMap.highlighted("A", in: areas), ["A1", "A2"])
        XCTAssertEqual(SpotRegionMap.covered(areas), ["A1"])
        XCTAssertEqual(areas[0].namesLine, L("a、b", "a, b"))
        XCTAssertFalse(map.sharesRegionChips)
        XCTAssertEqual(SearchSpotIndexSection.mapWidth(for: map.shapes), 636, "縦横比 3:1 の地図は地図の高さ 212 で幅 636")
        XCTAssertTrue(map.labels.isEmpty, "札を持たない地図は札を置かない")
        XCTAssertTrue(map.labelFrames(container: size, in: areas).isEmpty)
    }

    // MARK: - 押せる広さ（陣地分け・確かめ役の指摘 2026-11-11）

    /// 8 地方ぜんぶに撮影スポットがある台帳（県庁所在地の辺り・各地方1件）
    private func allRegions() throws -> [OfficialSpot] {
        [("北海道", 43.06, 141.35), ("宮城県", 38.27, 140.87), ("東京都", 35.69, 139.69), ("愛知県", 35.18, 136.91),
         ("大阪府", 34.69, 135.50), ("広島県", 34.40, 132.46), ("香川県", 34.34, 134.04), ("福岡県", 33.59, 130.40)]
            .enumerated().map { i, p in try! spot("s\(i)", prefecture: p.0, lat: p.1, lng: p.2) }
    }

    /// 地図の枠を 1pt ごとに押して、区分ごとに当たった点を数える（＝押せる広さ pt²）
    private func hitAreas(_ hit: (CGPoint) -> String?, size: CGSize) -> [String: Int] {
        var counts: [String: Int] = [:]
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                if let area = hit(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) { counts[area, default: 0] += 1 }
            }
        }
        return counts
    }

    /// 🔴 **どの地方も 44×44（1936pt²）以上押せる**。前（線の内側と 16pt の寄せ）は四国 648・近畿 882・中国 1135・中部 1551 で
    /// 届かなかった。いまは線の内側か、いちばん近い地方（陣地分け）。前後の広さはログ（`spotMap.hitArea`）に出す
    func testEveryRegionIsAtLeast44x44() throws {
        let g = try geometry()
        let map = SpotRegionMap.japan(g)
        let spots = try allRegions()
        let areas = map.areas(SpotMapSource(spots: spots, japanGroups: SpotPrefectureIndex.groups(spots: spots)))
        XCTAssertEqual(areas.count, 8)
        let size = CGSize(width: SearchSpotIndexSection.mapWidth(for: g), height: SearchSpotIndexSection.mapHeight)
        let after = hitAreas({ map.area(at: $0, container: size, in: areas) }, size: size)
        // 前の当たり（線の内側と 16pt の寄せ・`PrefectureMapGeometry.prefecture(at:tolerance:)`）
        let viewport = VisitedMapViewport()
        let before = hitAreas({ point in
            let unit = viewport.unitPoint(forScreen: point, content: g.size, container: size)
            return g.prefecture(at: unit, tolerance: viewport.tolerance(content: g.size, container: size))
                .flatMap { PrefectureRegions.region(of: $0)?.name }
        }, size: size)
        for region in PrefectureRegions.all {
            print("spotMap.hitArea \(region.name) before=\(before[region.name] ?? 0) after=\(after[region.name] ?? 0)")
            XCTAssertGreaterThanOrEqual(after[region.name] ?? 0, 1936, "\(region.name) の押せる広さが 44×44 に届かない")
        }
        // 🔴 **沖縄の挿入図を除いた九州本土**も 44×44 以上（九州・沖縄の広さの多くは挿入図の分だった・確かめ役の指摘）
        let inset = try XCTUnwrap(g.inset)
        let a = viewport.screenPoint(forUnit: inset.origin, content: g.size, container: size)
        let b = viewport.screenPoint(forUnit: CGPoint(x: inset.maxX, y: inset.maxY), content: g.size, container: size)
        let insetScreen = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        let mainland = hitAreas({ point in
            insetScreen.contains(point) ? nil : map.area(at: point, container: size, in: areas)
        }, size: size)["九州・沖縄"] ?? 0
        let mainlandBefore = hitAreas({ point in
            guard !insetScreen.contains(point) else { return nil }
            let unit = viewport.unitPoint(forScreen: point, content: g.size, container: size)
            return g.prefecture(at: unit, tolerance: viewport.tolerance(content: g.size, container: size))
                .flatMap { PrefectureRegions.region(of: $0)?.name }
        }, size: size)["九州・沖縄"] ?? 0
        print("spotMap.hitArea 九州本土（挿入図を除く） before=\(mainlandBefore) after=\(mainland)")
        XCTAssertGreaterThanOrEqual(mainland, 1936, "九州本土の押せる広さが 44×44 に届かない")
    }

    /// 🔴 **海岸のすぐ外（`coastSlack` 以内）は、いちばん近い地方になる**（寄せで遠くの地方に取られない）。
    /// 確かめ役が見つけた点（長崎の西・鹿児島の南・宮崎の東が四国になった）と、地図の枠の全部の点で確かめる
    func testCoastPointsBelongToNearestRegion() throws {
        let g = try geometry()
        let map = SpotRegionMap.japan(g)
        let spots = try allRegions()
        let areas = map.areas(SpotMapSource(spots: spots, japanGroups: SpotPrefectureIndex.groups(spots: spots)))
        let size = CGSize(width: SearchSpotIndexSection.mapWidth(for: g), height: SearchSpotIndexSection.mapHeight)
        // 長崎の西・鹿児島の南・宮崎の東（決めたときの 143×160 の点を、地図を広げた後は緯度経度で持つ）
        for (lat, lng) in [(32.75, 129.55), (31.05, 130.55), (32.0, 131.75)] {
            let point = screen(g, lat, lng, container: size)
            XCTAssertEqual(map.area(at: point, container: size, in: areas), "九州・沖縄", "\(point) が九州にならない")
        }
        // 名前の札の上は札の地方（`testLabelsSitOnTheirRegion`）。ここでは札の外だけを見る
        let labelFrames = map.labelFrames(container: size, in: areas).map(\.frame)
        let viewport = VisitedMapViewport()
        let scale = viewport.scale(content: g.size, container: size)
        var checked = 0
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                let unit = viewport.unitPoint(forScreen: point, content: g.size, container: size)
                guard g.piece(at: unit, tolerance: 0) == nil,
                      !labelFrames.contains(where: { $0.contains(point) }) else { continue }
                let nearest = areas.map { (id: $0.id, d: g.distance(from: unit, toPieces: $0.pieces) * scale) }
                    .min { $0.d < $1.d }!
                guard nearest.d <= SpotRegionMap.coastSlack else { continue }
                checked += 1
                XCTAssertEqual(map.area(at: point, container: size, in: areas), nearest.id,
                               "海岸のすぐ外 \(point) が近い地方 \(nearest.id) にならない")
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    /// 撮影スポットの無い地方の線の内側は何もしない（隣の地方に寄せない）。読み上げの上下の払いは端で止まる
    func testNoSpotPieceAndStep() throws {
        let (map, areas) = try japan()
        let g = try geometry()
        let size = CGSize(width: SearchSpotIndexSection.mapWidth(for: g), height: SearchSpotIndexSection.mapHeight)
        XCTAssertNil(map.area(at: screen(g, 32.88, 131.10, container: size), container: size, in: areas))
        XCTAssertNil(map.area(at: CGPoint(x: -5, y: 10), container: size, in: areas), "地図の枠の外")
        XCTAssertEqual(areas.map(\.id), ["北海道", "関東"])
        XCTAssertEqual(SpotRegionMap.step("北海道", in: areas, forward: true), "関東")
        XCTAssertEqual(SpotRegionMap.step("関東", in: areas, forward: true), "関東")
        XCTAssertEqual(SpotRegionMap.step("関東", in: areas, forward: false), "北海道")
        XCTAssertEqual(SpotRegionMap.step(nil, in: areas, forward: true), "北海道")
        XCTAssertNil(SpotRegionMap.step(nil, in: [], forward: true))
    }

    // MARK: - なぞる・読み上げ・札（確かめ役の指摘 2026-11-11）

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.resources.deletingLastPathComponent().appendingPathComponent(path), encoding: .utf8)
    }

    /// 🔴 なぞる状態は**取り消しで必ず空に戻る**（スクロール・電話・タブ替えで塗りと札が残らない）。
    /// 離した点が地図の外なら選ばない。区分の外へ出た間は前の区分のまま
    func testTraceStateClearsOnCancel() {
        var trace = SpotMapTrace()
        XCTAssertNil(trace.handle(.began("北海道")))
        XCTAssertEqual(trace.area, "北海道")
        XCTAssertNil(trace.handle(.changed(nil)))
        XCTAssertEqual(trace.area, "北海道", "区分の外へ出た間は前の区分のまま")
        XCTAssertNil(trace.handle(.changed("東北")))
        XCTAssertNil(trace.handle(.cancelled))
        XCTAssertNil(trace.area, "取り消しで空に戻らない")
        _ = trace.handle(.began("関東"))
        XCTAssertEqual(trace.handle(.ended("近畿")), "近畿", "離した点の区分を選ぶ")
        XCTAssertNil(trace.area)
        _ = trace.handle(.began("関東"))
        XCTAssertNil(trace.handle(.ended(nil)), "地図の外で離したら選ばない")
        XCTAssertNil(trace.area)
    }

    /// なぞるのは UIKit の長押し（`SpotMapTraceCatcher`・取り消しを必ず届ける）。SwiftUI の「長押し → 引く」は使わない
    /// （run 1022: それがあると地図の上から払っても画面が流れなかった）。離して空に戻るときは鳴らさない。
    /// なぞっている間は探すの画面のスクロールを止める。読み上げは値と上下の払い
    func testTracingUsesUIKitPressAndStopsScroll() throws {
        let view = try source("Features/Search/SpotRegionMapView.swift")
        XCTAssertTrue(view.contains("SpotMapTraceCatcher(delay: SpotRegionMap.traceDelay)"))
        XCTAssertFalse(view.contains("LongPressGesture("), "SwiftUI の長押し → 引くが残っている（払っても画面が流れない）")
        XCTAssertTrue(view.contains("_ = trace.handle(.cancelled)"))
        XCTAssertTrue(view.contains(".onChange(of: traced) { _, now in tracing = now }"))
        XCTAssertTrue(view.contains(".sensoryFeedback(.selection, trigger: traced) { _, now in now != nil }"))
        XCTAssertTrue(view.contains(".accessibilityAdjustableAction"))
        XCTAssertTrue(view.contains(".accessibilityValue(areas.first { $0.id == selected }?.title"))
        let catcher = try source("Features/Search/SpotMapTraceCatcher.swift")
        XCTAssertTrue(catcher.contains("case .cancelled, .failed: handlers.onCancel()"))
        XCTAssertTrue(catcher.contains("if press.state == .began || press.state == .changed { handlers?.onCancel() }"))
        XCTAssertTrue(catcher.contains("press.allowableMovement = 10"))
        // 画面を離れたら、なぞっている地方を探すの画面からも消す（スクロールが止まったまま残らない）
        XCTAssertTrue(view.contains(".onDisappear { tracing = nil }"))
        // 読み上げ: 「地方」と言う・ダブルタップはいまの地方の一覧へ（地図の真ん中を押して選ばない）
        XCTAssertTrue(view.contains("上下に払うと地方を替えられます"))
        XCTAssertFalse(view.contains("区分を替えられます"))
        XCTAssertTrue(view.contains(".accessibilityAction { onActivate() }"))
        let section = try source("Features/Search/SearchSpotIndexSection.swift")
        XCTAssertTrue(section.contains("openArea = areas.first { $0.id == chosen }?.scope"))
        XCTAssertTrue(section.contains(".navigationDestination(item: $openArea)"))
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains(".scrollDisabled(spotTracing != nil)"))
        XCTAssertTrue(search.contains("tracing: $spotTracing"))
    }

    /// 大きな字: 名前の行が切れる側、「北海道をすべて見る」は切れない側
    func testSeeAllNeverTruncates() throws {
        let text = try source("Features/Search/SearchSpotIndexSection.swift")
        let names = try XCTUnwrap(text.range(of: "Text(area.namesLine)"))
        XCTAssertTrue(text[names.upperBound...].prefix(200).contains(".layoutPriority(-1)"))
        let link = try XCTUnwrap(text.range(of: "MoreLink(text: area.seeAllLabel)"))
        let after = text[link.upperBound...].prefix(500)
        XCTAssertTrue(after.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(after.contains(".layoutPriority(1)"))
    }

    /// 一覧の範囲は画面を持たない層の型（地図の区分が持つ）
    func testScopeLivesInCore() {
        XCTAssertTrue(OfficialSpotIndexView.Scope.self == SpotIndexScope.self)
    }

    /// 地図の切り替え（「日本｜世界」）は**地図が2つ以上のときだけ**。いまは日本だけなので出さない
    func testSwitcherOnlyWithTwoOrMoreMaps() throws {
        let japan = SpotRegionMap.japan(try geometry())
        XCTAssertFalse(SpotRegionMap.showsSwitcher([japan]))
        XCTAssertTrue(SpotRegionMap.showsSwitcher([japan, squareMap()]))
        XCTAssertEqual(SpotRegionMap.available(japan: try geometry()).map(\.id), ["japan"])
        XCTAssertTrue(SpotRegionMap.available(japan: nil).isEmpty, "形が読めなければ地図を出さない")
        // 切り替えは地図の枠の中に重ねる（段の高さを変えない）
        let text = try String(contentsOf: Self.resources.deletingLastPathComponent()
            .appendingPathComponent("Features/Search/SearchSpotIndexSection.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains(".overlay(alignment: .topTrailing) {\n                if SpotRegionMap.showsSwitcher(maps) { mapSwitcher(current: map) }"),
                      "切り替えが地図の枠の中に重なっていない")
    }

    /// 札の「すべて見る」の先は、その地方の県だけ（北から・県の見出しつき）
    func testRegionScopeShowsOnlyThatRegion() throws {
        let sections = RegionList.sections(photos: [], spots: try spots() + [
            try spot("minatomirai", prefecture: "神奈川県", lat: 35.457, lng: 139.632),
        ], from: nil)
        let kanto = OfficialSpotIndexView.shown(sections, scope: .region("関東"))
        XCTAssertEqual(kanto.map(\.title), ["東京都", "神奈川県"])
        XCTAssertTrue(OfficialSpotIndexView.shown(sections, scope: .region("九州・沖縄")).isEmpty)
        XCTAssertFalse(OfficialSpotIndexView.isPrefecture(.region("関東")))
        XCTAssertTrue(OfficialSpotIndexView.isPrefecture(.prefecture("東京都")))
    }

    // MARK: - 段の高さ

    /// 🔴 **「写真｜地図」で段の高さが変わらない**（owner「縦に長くならないように」）。
    /// 地図も札の列と同じ高さ（`cardColumnHeight`）に収め、段ぜんたいは `bodyHeight` の枠で固定
    func testMapFitsInsideTheSameHeight() throws {
        let g = try geometry()
        XCTAssertEqual(SearchSpotIndexSection.bodyHeight, 212)
        // 2026-11-12: 「地図」のときはチップを出さず、地図を段の高さいっぱい（212）に広げた（幅 143 → 189）
        XCTAssertEqual(SearchSpotIndexSection.mapHeight, SearchSpotIndexSection.bodyHeight)
        let width = SearchSpotIndexSection.mapWidth(for: g)
        XCTAssertEqual(width, 189)
        // 右の札は 390pt の画面で 390 − 16×2 − 189 − 12 = 157（「九州・沖縄をすべて見る」は2行に折れて切れない）
        XCTAssertLessThan(width, 200, "地図が札の場所を取りすぎる（右の札が狭い）")
        let text = try String(contentsOf: Self.resources.deletingLastPathComponent()
            .appendingPathComponent("Features/Search/SearchSpotIndexSection.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("`bodyHeight`）\n        .frame(height: Self.bodyHeight, alignment: .top)"),
                      "段（チップ＋札の列か地図）の高さを枠で固定していない")
        XCTAssertTrue(text.contains("mapRow(selected, map: map)\n                    .frame(height: Self.mapHeight)"),
                      "地図の行の高さが段の高さでない")
    }

    /// 「写真｜地図」の札は `ProfileTabBar` と同じ下線の札（目印つき）
    func testModeTabs() {
        XCTAssertEqual(SpotIndexMode.allCases.map(\.tabTitle), [L("写真", "Photos"), L("地図", "Map")])
        XCTAssertEqual(SpotIndexMode.map.tabIdentifier, "search.spotIndex.mode.map")
    }

    // MARK: - 何も選ばずに開く・地方の名前の札（2026-11-12 owner「なんも押してないのに県を選ぶというのわかりづらいな。ガイドもないし」）

    /// 🔴 **地方の名前の札**: 撮影スポットのある地方に1枚ずつ（九州・沖縄は「九州」と「沖縄」の2枚）。
    /// 札どうしが重ならず、地図の枠の中。**札の上を押すと、その札の地方**（隣の地方の陸に掛かっていても）
    func testLabelsSitOnTheirRegion() throws {
        let g = try geometry()
        let map = SpotRegionMap.japan(g)
        let spots = try allRegions()
        let areas = map.areas(SpotMapSource(spots: spots, japanGroups: SpotPrefectureIndex.groups(spots: spots)))
        let size = CGSize(width: SearchSpotIndexSection.mapWidth(for: g), height: SearchSpotIndexSection.mapHeight)
        let frames = map.labelFrames(container: size, in: areas)
        XCTAssertEqual(frames.map(\.label.text), ["北海道", "東北", "関東", "中部", "近畿", "中国", "四国", "九州", "沖縄"])
        XCTAssertEqual(Set(frames.map(\.label.area)), Set(PrefectureRegions.all.map(\.name)), "札の無い地方がある")
        let bounds = CGRect(origin: .zero, size: size)
        for (i, a) in frames.enumerated() {
            print("spotMap.label \(a.label.text) frame=\(a.frame)")
            XCTAssertTrue(bounds.contains(a.frame), "\(a.label.text) の札が地図の枠からはみ出す")
            XCTAssertEqual(a.frame.height, 22)
            XCTAssertGreaterThanOrEqual(a.frame.width, 44, "札の幅が 44 に届かない")
            for b in frames[(i + 1)...] {
                XCTAssertFalse(a.frame.intersects(b.frame), "\(a.label.text) と \(b.label.text) の札が重なる")
            }
            // 札の上のどの点を押しても札の地方（1pt ごと）
            var y = a.frame.minY + 0.5
            while y < a.frame.maxY {
                var x = a.frame.minX + 0.5
                while x < a.frame.maxX {
                    XCTAssertEqual(map.area(at: CGPoint(x: x, y: y), container: size, in: areas), a.label.area,
                                   "\(a.label.text) の札の上 (\(x), \(y)) を押しても \(a.label.area) にならない")
                    x += 1
                }
                y += 1
            }
        }
        // 撮影スポットの無い地方には札を置かない（押しても何もしない地方に「›」を出さない）
        let (onlyTwo, twoAreas) = try japan()
        XCTAssertEqual(onlyTwo.labelFrames(container: size, in: twoAreas).map(\.label.text), ["北海道", "関東"])
        // 札の幅: 漢字は字の大きさ、英数字は 0.62 倍。余白 20、最小 44
        XCTAssertEqual(SpotRegionMap.labelWidth("近畿"), 44)
        XCTAssertEqual(SpotRegionMap.labelWidth("北海道"), 56)
        XCTAssertEqual(SpotRegionMap.labelWidth("Kanto"), 58)
    }

    /// 🔴 札は**地図の上に描くだけ**で指を受けない（当たりは `area(at:)`・札の上から長押ししてもなぞれる）。
    /// 選んでいる・なぞっている地方の札は真鍮。札は読み上げから外す（地図が1つの要素）。見た目は Web の地方名の札
    func testLabelChipDrawsOnTheMap() throws {
        let view = try source("Features/Search/SpotRegionMapView.swift")
        XCTAssertTrue(view.contains(".overlay(alignment: .topLeading) { labels(size: size) }"))
        let labels = try XCTUnwrap(view.range(of: "private func labels(size: CGSize)")).upperBound
        let body = String(view[labels...].prefix(900))
        for part in ["let lit = traced ?? selected", "map.labelFrames(container: size, in: areas)",
                     "SpotMapLabelChip(text: item.label.text, on: item.label.area == lit)",
                     ".allowsHitTesting(false)", ".accessibilityHidden(true)"] {
            XCTAssertTrue(body.contains(part), "\(part) が無い")
        }
        let chip = try XCTUnwrap(view.range(of: "struct SpotMapLabelChip: View")).upperBound
        let chipBody = String(view[chip...].prefix(1500))
        for part in ["Text(verbatim: \"›\")", ".foregroundStyle(on ? WebTheme.accent : WebTheme.text)",
                     ".font(.system(size: SpotRegionMap.labelFontSize, weight: .semibold))",
                     "Capsule().fill(Color.black.opacity(Self.fillOpacity))",
                     "WebTheme.accent.opacity(on ? 1 : Self.edgeOpacity), lineWidth: on ? 1.5 : 1"] {
            XCTAssertTrue(chipBody.contains(part), "\(part) が無い")
        }
        XCTAssertEqual(SpotMapLabelChip.fillOpacity, 0.78)
        XCTAssertEqual(SpotMapLabelChip.edgeOpacity, 0.55)
        XCTAssertEqual(SpotRegionMap.labelFontSize, 12, "本文系の最小 12 を下回る")
    }

    /// 🔴 **開いたときは何も選ばない**: 地図の選択は、日本は写真のチップと同じ（nil なら何も塗らない）、ほかの地図も
    /// 押すまで空（前は件数のいちばん多い区分を選んでおいた）。何も選んでいないときの右の札は「全国」と一言。
    /// 写真のチップの先頭は「全国」。「地図」のときはチップを出さない（地図の上の名前の札で選ぶ）
    func testNothingSelectedWhenOpened() throws {
        let section = try source("Features/Search/SearchSpotIndexSection.swift")
        XCTAssertTrue(section.contains("let chosen = map.sharesRegionChips ? selected?.region.name : otherSelections[map.id]\n"))
        XCTAssertFalse(section.contains("areas.max { $0.count < $1.count }"), "押す前に件数の多い区分を選んでいる")
        XCTAssertTrue(section.contains("if let shown { areaCard(shown) } else { idleCard(total:"))
        XCTAssertEqual(SearchSpotIndexSection.idleHint, L("地方を押すと、ここに出ます", "Tap a region to see its spots here"))
        XCTAssertTrue(section.contains(".accessibilityIdentifier(\"search.spotIndex.mapHint\")"))
        XCTAssertTrue(section.contains("openArea = areas.first { $0.id == chosen }?.scope ?? .all"),
                      "何も選んでいないときの読み上げのダブルタップの行き先が無い")
        // 写真: 先頭の「全国」チップ（何も選んでいない形）・札は全国の県
        XCTAssertTrue(section.contains("selected: selected == nil) {\n                    region = nil\n                }\n                .accessibilityIdentifier(\"search.spotIndex.region.all\")"))
        XCTAssertTrue(section.contains("ForEach(selected?.cards ?? SpotPrefectureIndex.nationalCards(groups)) { card in"))
        // 地図のときはチップを出さない
        let strip = try XCTUnwrap(section.range(of: "private func strip(")).upperBound
        let stripBody = String(section[strip...].prefix(600))
        XCTAssertTrue(stripBody.contains("mapRow(selected, map: map)\n                    .frame(height: Self.mapHeight)\n            } else {\n                regionChips(selected)\n                cardsRow(selected)"))
        // 探すの画面は、出ている札（全国のときも）の表紙だけを読む
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("SpotPrefectureIndex.coverNeeds(region: spotRegion, in: spotGroups)"))
    }
}
