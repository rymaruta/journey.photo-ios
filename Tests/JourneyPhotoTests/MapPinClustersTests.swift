import XCTest
import CoreLocation
@testable import JourneyPhoto

/// 写真のピンを多すぎるときだけ束ねる（`MapPinClusters`）。
///
/// ピンは撮影地ごとに1つで上限が無く、各ピンが画像を読む。撮影スポットの「最大60本」に倣う
final class MapPinClustersTests: XCTestCase {

    private func photo(_ id: String, thumbSm: String? = nil, thumbSrc: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let thumbSm { fields.append("\"thumbSm\":\"\(thumbSm)\"") }
        if let thumbSrc { fields.append("\"thumbSrc\":\"\(thumbSrc)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func pin(_ lat: Double, _ lng: Double, photos: Int = 1) throws -> MapPin {
        let id = "\(lat),\(lng)"
        return MapPin(id: id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                      title: "p", photos: try (0..<photos).map { try photo("\(id)-\($0)") })
    }

    /// 0.01 度おきの格子に `count` 本（約1km おき＝撮影地の丸めと同じ細かさ）
    private func grid(_ count: Int, lat0: Double = 35, lng0: Double = 139) throws -> [MapPin] {
        try (0..<count).map { k in
            try pin(lat0 + Double(k / 20) * 0.01, lng0 + Double(k % 20) * 0.01)
        }
    }

    private let japan = MapFraming.Frame(latitude: 36, longitude: 138, latitudeSpan: 12, longitudeSpan: 12)

    // MARK: - 少ないときは今までどおり

    func testFewPinsAreLeftAloneWhateverTheFrame() throws {
        let pins = try grid(MapPinClusters.limit)
        let far = MapFraming.Frame(latitude: -30, longitude: -60, latitudeSpan: 1, longitudeSpan: 1)
        for frame in [nil, japan, far] {
            let layout = MapPinClusters.layout(pins, frame: frame)
            XCTAssertEqual(layout.pins.map(\.id), pins.map(\.id), "上限以下は枠を見ずに全部そのまま")
            XCTAssertTrue(layout.clusters.isEmpty)
        }
    }

    // MARK: - 多いときは束ねて上限以下

    func testManyPinsAreBundledUnderTheLimit() throws {
        let pins = try grid(400)
        let layout = MapPinClusters.layout(pins, frame: japan)
        XCTAssertLessThanOrEqual(layout.markerCount, MapPinClusters.limit, "置く印は上限まで")
        XCTAssertFalse(layout.clusters.isEmpty)
        // 束ねても写真は1枚も消えない（枠の中のぶん）
        let covered = layout.pins.count + layout.clusters.reduce(0) { $0 + $1.pins.count }
        XCTAssertEqual(covered, 400)
        XCTAssertTrue(layout.clusters.allSatisfy { $0.pins.count >= 2 }, "1本だけの束は作らない")
    }

    /// 写真が世界中に散らばっていて枠がまだ無い（最初の描画）ときも上限を守る
    func testWithoutAFrameEverythingIsBundled() throws {
        let pins = try (0..<300).map { k in try pin(Double(k % 60) - 30, Double(k / 60) * 30 - 70) }
        let layout = MapPinClusters.layout(pins, frame: nil)
        XCTAssertLessThanOrEqual(layout.markerCount, MapPinClusters.limit)
        XCTAssertEqual(layout.pins.count + layout.clusters.reduce(0) { $0 + $1.pins.count }, 300)
    }

    /// 寄せて枠の中が上限以下なら、**枠の中のピンだけ**をそのまま置く（束ねない）
    func testZoomedInShowsOnlyNearbyPinsUnbundled() throws {
        let tokyo = try grid(30, lat0: 35.6, lng0: 139.6)
        let osaka = try grid(200, lat0: 34.6, lng0: 135.4)
        let frame = MapFraming.Frame(latitude: 35.65, longitude: 139.7, latitudeSpan: 0.3, longitudeSpan: 0.3)
        let layout = MapPinClusters.layout(tokyo + osaka, frame: frame)
        XCTAssertTrue(layout.clusters.isEmpty)
        XCTAssertEqual(Set(layout.pins.map(\.id)), Set(tokyo.map(\.id)), "大阪のピンは置かない（見えていない）")
    }

    /// 🔴 **少し動かしただけでは組み方が変わらない**（格子は世界に固定）。変わると
    /// 全部の印が作り直され、描き直し → カメラの知らせ → … の種になる
    func testSmallPanKeepsTheSameBundles() throws {
        let pins = try grid(400)
        let a = MapPinClusters.layout(pins, frame: MapFraming.Frame(latitude: 35.1, longitude: 139.1,
                                                                    latitudeSpan: 1, longitudeSpan: 1))
        let b = MapPinClusters.layout(pins, frame: MapFraming.Frame(latitude: 35.11, longitude: 139.12,
                                                                    latitudeSpan: 1, longitudeSpan: 1))
        XCTAssertEqual(a, b)
    }

    /// 束を押したら寄る枠は、束の全部の撮影地を含む
    func testClusterFrameContainsAllItsPins() throws {
        let layout = MapPinClusters.layout(try grid(400), frame: japan)
        for cluster in layout.clusters {
            for member in cluster.pins {
                XCTAssertTrue(MapSearch.contains(cluster.frame, latitude: member.coordinate.latitude,
                                                 longitude: member.coordinate.longitude))
            }
            XCTAssertGreaterThan(cluster.photoCount, 1)
            XCTAssertNotNil(cluster.cover)
        }
    }

    /// 束の印は写真のいちばん多い撮影地の1枚
    func testCoverComesFromTheBusiestPlace() throws {
        var pins = try grid(100)
        pins[0] = try pin(35, 139, photos: 5)
        let layout = MapPinClusters.layout(pins, frame: nil)
        let holding = try XCTUnwrap(layout.clusters.first { $0.pins.contains { $0.id == "35.0,139.0" } })
        XCTAssertEqual(holding.pins.first?.id, "35.0,139.0")
        XCTAssertEqual(holding.cover?.id, "35.0,139.0-0")
    }

    // MARK: - 選んだピンが束に吸われたら選びを外す

    func testSelectionAbsorbedIntoAClusterIsHidden() throws {
        let pins = try grid(400)
        let layout = MapPinClusters.layout(pins, frame: japan)
        let absorbed = try XCTUnwrap(layout.clusters.first?.pins.first)
        XCTAssertTrue(layout.hides(absorbed, among: pins), "束に吸われたピンを札が指し続ける")
        if let shown = layout.pins.first {
            XCTAssertFalse(layout.hides(shown, among: pins))
        }
        XCTAssertFalse(layout.hides(nil, among: pins))
    }

    /// 絞り込みで結果から外れたピンは**外さない**（2026-09-30 判断: 選びは絞りの間も持ち続ける）
    func testSelectionFilteredOutIsKept() throws {
        let pins = try grid(10)
        let filteredOut = try pin(10, 10)
        XCTAssertFalse(MapPinClusters.layout(pins, frame: nil).hides(filteredOut, among: pins))
    }

    // MARK: - ピンの画像は 256px

    func testPinImagePrefersTheSmallThumbnail() throws {
        XCTAssertEqual(try photo("a", thumbSm: "https://cdn/a_thumb_sm.webp", thumbSrc: "https://cdn/a_thumb.webp")
            .pinImageURL?.absoluteString, "https://cdn/a_thumb_sm.webp", "256px を先に")
        XCTAssertEqual(try photo("a", thumbSrc: "https://cdn/a_thumb.webp").pinImageURL?.absoluteString,
                       "https://cdn/a_thumb.webp", "無ければ一覧と同じもの")
        XCTAssertEqual(try photo("a").pinImageURL?.absoluteString, "https://x/a.jpg")
        XCTAssertEqual(try photo("a", thumbSm: "", thumbSrc: "https://cdn/a_thumb.webp").pinImageURL?.absoluteString,
                       "https://cdn/a_thumb.webp", "空の thumbSm で先へ落ちない（Web の || と同じ）")
    }

    // MARK: - 枠が使えないときも写真のピンを置く（2026-10-02 の回帰の調査）

    /// 🔴 **幅0・負・数でない枠で、写真のピンを全部落とさない。** 上限を超えたときの
    /// 「枠の中だけ置く」に幅0の枠をそのまま通すと、どの点も入らず1本も出ない
    func testUnusableFrameStillPlacesThePins() throws {
        let pins = try grid(MapPinClusters.limit + 40)
        let center = MapFraming.Frame(latitude: 35.05, longitude: 139.1, latitudeSpan: 0, longitudeSpan: 0)
        let unusable: [MapFraming.Frame] = [
            center,
            MapFraming.Frame(latitude: 35.05, longitude: 139.1, latitudeSpan: 0, longitudeSpan: 0.5),
            MapFraming.Frame(latitude: 35.05, longitude: 139.1, latitudeSpan: -1, longitudeSpan: -1),
            MapFraming.Frame(latitude: .nan, longitude: 139.1, latitudeSpan: 1, longitudeSpan: 1),
            MapFraming.Frame(latitude: 35.05, longitude: 139.1, latitudeSpan: .nan, longitudeSpan: .nan),
            MapFraming.Frame(latitude: 35.05, longitude: 139.1, latitudeSpan: .infinity, longitudeSpan: 1),
        ]
        let noFrame = MapPinClusters.layout(pins, frame: nil)
        for frame in unusable {
            XCTAssertNil(MapPinClusters.usable(frame))
            let layout = MapPinClusters.layout(pins, frame: frame)
            XCTAssertGreaterThan(layout.markerCount, 0, "使えない枠（\(frame)）で写真の印が1本も置かれない")
            XCTAssertLessThanOrEqual(layout.markerCount, MapPinClusters.limit)
            XCTAssertEqual(layout, noFrame, "使えない枠は「枠がまだ無い」と同じに扱う")
            let covered = layout.pins.count + layout.clusters.reduce(0) { $0 + $1.pins.count }
            XCTAssertEqual(covered, pins.count, "使えない枠で写真を落とした")
        }
    }

    /// 少ないとき（上限以下）は枠が何でも全部置く——幅0・NaN でも
    func testFewPinsIgnoreAnUnusableFrame() throws {
        let pins = try grid(5)
        for frame in [MapFraming.Frame(latitude: 0, longitude: 0, latitudeSpan: 0, longitudeSpan: 0),
                      MapFraming.Frame(latitude: .nan, longitude: .nan, latitudeSpan: .nan, longitudeSpan: .nan)] {
            XCTAssertEqual(MapPinClusters.layout(pins, frame: frame).pins.map(\.id), pins.map(\.id))
        }
    }

    /// 使える枠はそのまま使う（`usable` が普通の枠を捨てない）
    func testUsableFrameIsKept() {
        XCTAssertEqual(MapPinClusters.usable(japan), japan)
    }
}

/// 束の読み上げ名（`PhotoMapViewModel` は `@MainActor` なので試験も揃える）
@MainActor
final class MapClusterLabelTests: XCTestCase {
    func testClusterSpokenLabel() async {
        let label = PhotoMapViewModel.clusterSpokenLabel(photos: 12, places: 3)
        XCTAssertTrue(label.contains("12"))
        XCTAssertTrue(label.contains("3"))
    }
}
