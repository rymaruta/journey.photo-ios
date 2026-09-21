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
