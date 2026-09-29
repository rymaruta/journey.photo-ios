import XCTest
@testable import JourneyPhoto

/// ストーリーの写真の合わせ方（拡大・位置・回し）。編集画面と焼き込みが同じ値を読む
final class PhotoFramingTests: XCTestCase {

    func testScaleIsClamped() {
        let f = PhotoFraming.identity
        XCTAssertEqual(f.scaled(by: 2).scale, 2, accuracy: 0.0001)
        XCTAssertEqual(f.scaled(by: 100).scale, PhotoFraming.maxScale, accuracy: 0.0001)
        XCTAssertEqual(f.scaled(by: 0.01).scale, PhotoFraming.minScale, accuracy: 0.0001)
        for bad in [0, -1, Double.nan, Double.infinity] {
            XCTAssertEqual(f.scaled(by: bad), f, "\(bad)")
        }
    }

    /// 動かした量は**写真の枠（画面の点）に対する割合**。中心が枠の外へ出ない所まで
    func testMoveIsRelativeToTheFrameAndClamped() {
        let moved = PhotoFraming.identity.moved(by: CGSize(width: 40, height: -80), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(moved.offsetX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(moved.offsetY, -0.1, accuracy: 0.0001)
        let far = PhotoFraming.identity.moved(by: CGSize(width: 4000, height: -4000), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(far.offsetX, PhotoFraming.maxOffset, accuracy: 0.0001)
        XCTAssertEqual(far.offsetY, -PhotoFraming.maxOffset, accuracy: 0.0001)
        // 大きさが 0 の枠で割らない
        XCTAssertEqual(PhotoFraming.identity.moved(by: CGSize(width: 10, height: 10), in: .zero), .identity)
    }

    func testRotationAccumulates() {
        let r = PhotoFraming.identity.rotated(by: 0.5).rotated(by: 0.25)
        XCTAssertEqual(r.rotation, 0.75, accuracy: 0.0001)
        XCTAssertEqual(r.rotated(by: .nan), r)
    }

    /// 焼き込みの置き方: 枠の中心＋ずらし、描く大きさは枠×倍率。合わせていなければ枠いっぱい
    func testPlacement() {
        let size = CGSize(width: 1000, height: 2000)
        let plain = PhotoFraming.identity.placement(in: size)
        XCTAssertEqual(plain.center, CGPoint(x: 500, y: 1000))
        XCTAssertEqual(plain.drawSize, size)
        let f = PhotoFraming(scale: 2, offsetX: 0.1, offsetY: -0.25, rotation: 1)
        let placed = f.placement(in: size)
        XCTAssertEqual(placed.center, CGPoint(x: 600, y: 500))
        XCTAssertEqual(placed.drawSize, CGSize(width: 2000, height: 4000))
    }

    /// 下書きの往復。壊れた値は幅に収めて読む（写真が消えない）
    func testCodableRoundTripAndSanitize() throws {
        let f = PhotoFraming(scale: 1.5, offsetX: 0.2, offsetY: -0.1, rotation: 0.3)
        XCTAssertEqual(try JSONDecoder().decode(PhotoFraming.self, from: JSONEncoder().encode(f)), f)
        let wild = #"{"scale":99,"offsetX":-3,"offsetY":2}"#
        let read = try JSONDecoder().decode(PhotoFraming.self, from: Data(wild.utf8))
        XCTAssertEqual(read, PhotoFraming(scale: PhotoFraming.maxScale, offsetX: -0.5, offsetY: 0.5, rotation: 0))
        XCTAssertTrue(PhotoFraming.identity.isIdentity)
        XCTAssertFalse(f.isIdentity)
    }

    /// 🔴 **真っすぐ（90°ごと）の近く（±3°）は吸い付ける**。つまむだけでも指は少しひねるので、
    /// 吸い付けないと数度傾いたまま焼け、角に黒い三角が出た
    func testRotationSnapsNearStraight() {
        let deg = Double.pi / 180
        XCTAssertEqual(PhotoFraming.identity.rotated(by: 2 * deg).rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(PhotoFraming.identity.rotated(by: -2.9 * deg).rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(PhotoFraming.identity.rotated(by: 88 * deg).rotation, Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(PhotoFraming.identity.rotated(by: -181 * deg).rotation, -Double.pi, accuracy: 1e-9)
        // 離れていれば傾けたまま
        XCTAssertEqual(PhotoFraming.identity.rotated(by: 10 * deg).rotation, 10 * deg, accuracy: 1e-9)
        XCTAssertEqual(PhotoFraming.identity.rotated(by: 4 * deg).rotation, 4 * deg, accuracy: 1e-9)
    }
}
