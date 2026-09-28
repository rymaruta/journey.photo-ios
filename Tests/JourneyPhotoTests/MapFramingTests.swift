import XCTest
@testable import JourneyPhoto

/// 地図の初期表示。
///
/// **世界全体を出さない**（指示書 9-2）。日本とヨーロッパのピンを同時に
/// 収めようとすると地球儀の縮尺になり、1枚ずつの写真が探せない。
final class MapFramingTests: XCTestCase {

    private let tokyo = (latitude: 35.68, longitude: 139.76)
    private let niigata = (latitude: 37.63, longitude: 138.94)
    private let helsinki = (latitude: 60.17, longitude: 24.94)
    private let paris = (latitude: 48.86, longitude: 2.35)

    /// **離れた塊は混ぜない。** 日本3枚とヨーロッパ2枚なら、日本に寄る
    func testFramesTheLargestCluster() {
        let frame = MapFraming.frame(for: [tokyo, niigata,
                                           (latitude: 36.2, longitude: 139.0),
                                           helsinki, paris])
        guard let frame else { return XCTFail("枠が決まらない") }
        XCTAssertEqual(frame.latitude, 36.65, accuracy: 1.0, "日本の塊に寄っていない")
        XCTAssertLessThan(frame.latitudeSpan, 10, "縮尺が広すぎる（世界地図になっている）")
    }

    /// 1点だけなら、その点を中心に**寄りすぎない幅**で
    func testSinglePointGetsAMinimumSpan() {
        guard let frame = MapFraming.frame(for: [tokyo]) else { return XCTFail("枠が決まらない") }
        XCTAssertEqual(frame.latitude, tokyo.latitude, accuracy: 0.001)
        XCTAssertEqual(frame.latitudeSpan, MapFraming.minimumSpan, accuracy: 0.001)
    }

    /// 点が無ければ枠も無い（地図の既定に任せる）
    func testNoPointsMeansNoFrame() {
        XCTAssertNil(MapFraming.frame(for: []))
    }

    /// 🔴 **つながる点はぜんぶ1つの塊。** 2つの塊をつなぐ点が後から来ても合わせなかったので、
    /// 一続きの3点が割れて、北の2点の塊が選ばれていた
    func testPointsBridgedLaterAreOneCluster() {
        let points = [(latitude: 50.0, longitude: 0.0), (latitude: 50.0, longitude: 0.1),
                      (latitude: 40.0, longitude: 0.0), (latitude: 40.0, longitude: 4.0),
                      (latitude: 38.0, longitude: 2.0)]
        XCTAssertEqual(MapFraming.largestCluster(points).count, 3)
        guard let frame = MapFraming.frame(for: points) else { return XCTFail("枠が決まらない") }
        XCTAssertEqual(frame.latitude, 39, accuracy: 0.5, "一続きの3点の塊に寄っていない")
    }

    /// 🔴 **数えるのは写真の枚数。** 東京の1地点に40枚、パリの2地点に1枚ずつなら東京に寄る
    func testClustersAreWeighedByPhotos() {
        let paris2 = (latitude: 48.87, longitude: 2.36)
        guard let frame = MapFraming.frame(for: [tokyo, paris, paris2], weights: [40, 1, 1]) else {
            return XCTFail("枠が決まらない")
        }
        XCTAssertEqual(frame.latitude, tokyo.latitude, accuracy: 0.01)
    }

    /// 🔴 **点が密でも塊の広さに上限がある・点が多くても速い。** つながりをたどって1つに
    /// すると、世界に散った点が大陸ごと1つになり（世界に近い枠）、点の数の2乗の時間がかかった
    func testDenseWorldStaysLocalAndFast() {
        var generator = SystemRandomNumberGenerator()
        let points = (0..<20_000).map { _ in
            (latitude: Double.random(in: -60...70, using: &generator),
             longitude: Double.random(in: -180...180, using: &generator))
        }
        let started = Date()
        guard let frame = MapFraming.frame(for: points) else { return XCTFail("枠が決まらない") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "点が多いと遅すぎる")
        XCTAssertLessThan(frame.latitudeSpan, 3 * MapFraming.clusterDegrees * MapFraming.padding + 0.01,
                          "塊が広がりすぎる（世界に近い枠）")
    }

    /// **離れた1枚で枠を広げない**（717e28c のレビュー）。3×3 の升をそのまま囲んでいたので、
    /// 東京40枚に大阪1枚で、枠が大阪まで広がった
    func testAFarSinglePhotoDoesNotStretchTheFrame() {
        let osaka = (latitude: 34.69, longitude: 135.50)
        guard let frame = MapFraming.frame(for: [tokyo, osaka], weights: [40, 1]) else {
            return XCTFail("枠が決まらない")
        }
        XCTAssertEqual(frame.longitude, tokyo.longitude, accuracy: 0.01)
        XCTAssertEqual(frame.longitudeSpan, MapFraming.minimumSpan, accuracy: 0.001)
    }

    /// **重みの中心が2つの群の間に落ちても、間の1枚に寄らない**（159f8ec のレビュー）。
    /// 東京20枚・広島20枚・名古屋1枚で、名古屋の1枚に最小の幅で寄っていた
    func testDoesNotZoomToTheLonePhotoBetweenTwoGroups() {
        let hiroshima = (latitude: 34.39, longitude: 132.46)
        let nagoya = (latitude: 35.18, longitude: 136.90)
        guard let frame = MapFraming.frame(for: [tokyo, hiroshima, nagoya], weights: [20, 20, 1]) else {
            return XCTFail("枠が決まらない")
        }
        XCTAssertEqual(frame.latitude, tokyo.latitude, accuracy: 0.01, "同じ重さなら北（東京）の群")
        XCTAssertEqual(frame.longitude, tokyo.longitude, accuracy: 0.01)
    }

    /// **1つの升に写真が集まっても速い**（070c760 のレビュー）。1地点ずつを候補にしていたので、
    /// 同じ升に 20000 枚で約 100 秒かかった（地図の描き直しのたびに走る）
    func testManyPhotosInOnePlaceAreFast() {
        var generator = SystemRandomNumberGenerator()
        let tokyoArea = (0..<20_000).map { _ in
            (latitude: 35.6 + Double.random(in: 0...1, using: &generator),
             longitude: 139.5 + Double.random(in: 0...1, using: &generator))
        }
        let same = Array(repeating: tokyo, count: 20_000)
        // 細かく散らばる（東アジアくらい）——升ごとに近くの升を読む形では遅かった（da88b2a のレビュー）
        let eastAsia = (0..<20_000).map { _ in
            (latitude: 20 + Double.random(in: 0...30, using: &generator),
             longitude: 100 + Double.random(in: 0...50, using: &generator))
        }
        for points in [tokyoArea, same, eastAsia] {
            let started = Date()
            XCTAssertNotNil(MapFraming.frame(for: points))
            XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "点が多いと遅すぎる")
        }
        // 返す点は窓（中心の升から上下左右 9升）の中だけ——幅が窓を超えない
        let cluster = MapFraming.largestCluster(eastAsia)
        let lats = cluster.map(\.latitude), lons = cluster.map(\.longitude)
        XCTAssertLessThanOrEqual(lats.max()! - lats.min()!, 19 * MapFraming.clusterDegrees / 10 + 1e-9)
        XCTAssertLessThanOrEqual(lons.max()! - lons.min()!, 19 * MapFraming.clusterDegrees / 10 + 1e-9)
    }

    /// **ありえない座標で落ちない**（565d8fc のレビュー）。升目の数を広がりで決めるので、範囲外の
    /// 1点で升目が巨大になり、確保できずに落ちていた。範囲外は数えない
    func testOutOfRangeCoordinatesAreIgnored() {
        let started = Date()
        let frame = MapFraming.frame(for: [tokyo, (latitude: 1e4, longitude: 1e4), (latitude: .nan, longitude: 0)])
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(frame?.latitude ?? 0, tokyo.latitude, accuracy: 0.001)
        XCTAssertNil(MapFraming.frame(for: [(latitude: 1e4, longitude: 1e4)]), "使える点が無ければ枠も無い")
    }

    /// 近い点どうしは1つの塊
    func testNearbyPointsAreOneCluster() {
        XCTAssertEqual(MapFraming.largestCluster([tokyo, niigata]).count, 2)
    }

    /// **遠い点は別の塊**（同数なら北の塊を選ぶ＝毎回同じ結果）
    func testFarPointsAreSeparateClusters() {
        let cluster = MapFraming.largestCluster([tokyo, helsinki])
        XCTAssertEqual(cluster.count, 1)
        XCTAssertEqual(cluster.first?.latitude ?? 0, helsinki.latitude, accuracy: 0.01)
    }

    /// 枠には余白を入れる（端のピンが画面の縁に貼り付かない）
    func testFrameHasPadding() {
        guard let frame = MapFraming.frame(for: [tokyo, niigata]) else { return XCTFail("枠が決まらない") }
        let raw = abs(tokyo.latitude - niigata.latitude)
        XCTAssertGreaterThan(frame.latitudeSpan, raw, "余白が入っていない")
    }
}
