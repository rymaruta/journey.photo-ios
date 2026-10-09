import XCTest
@testable import JourneyPhoto

/// メダルの凹凸（2026-10-09 owner「3D回転させた時の立体感たりない・表も裏ものっぺり」）。
/// 明るいところが高い・面は中心がふくらむ・緑が上向き・縁の帯は左右がつながる。
final class MedalReliefTests: XCTestCase {

    private func pixel(_ map: [UInt8], _ x: Int, _ y: Int, width: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(map[i]), Int(map[i + 1]), Int(map[i + 2]))
    }

    /// 平らで、ふくらみも無ければ、どこも真正面（128, 128, 255）
    func testFlatFacesForward() {
        let map = MedalRelief.normalMap(luminance: [UInt8](repeating: 90, count: 32 * 32), width: 32, height: 32,
                                        strength: 1.1, dome: 0)
        XCTAssertEqual(map.count, 32 * 32 * 4)
        for y in [0, 16, 31] {
            for x in [0, 16, 31] {
                let p = pixel(map, x, y, width: 32)
                XCTAssertEqual(p.r, 128, accuracy: 1)
                XCTAssertEqual(p.g, 128, accuracy: 1)
                XCTAssertEqual(p.b, 255, accuracy: 1)
            }
        }
    }

    /// 🔴 **ふくらみ**: 左の縁は左を、右の縁は右を、上の縁は上を向く（回すと光が面を横切る）
    func testDomeTiltsOutward() {
        let n = 64
        let map = MedalRelief.normalMap(luminance: [UInt8](repeating: 120, count: n * n), width: n, height: n,
                                        strength: MedalRelief.strength, dome: MedalRelief.dome)
        XCTAssertLessThan(pixel(map, 2, n / 2, width: n).r, 110)
        XCTAssertGreaterThan(pixel(map, n - 3, n / 2, width: n).r, 146)
        XCTAssertGreaterThan(pixel(map, n / 2, 2, width: n).g, 146)
        XCTAssertLessThan(pixel(map, n / 2, n - 3, width: n).g, 110)
        // 中心は真正面
        XCTAssertEqual(pixel(map, n / 2, n / 2, width: n).r, 128, accuracy: 4)
    }

    /// 🔴 **明るいところが高い**: 明るい縦の帯の左の斜面は左を、右の斜面は右を向く
    func testBrightIsRaised() {
        let n = 48
        var lum = [UInt8](repeating: 20, count: n * n)
        for y in 0..<n { for x in 22..<26 { lum[y * n + x] = 240 } }
        let map = MedalRelief.normalMap(luminance: lum, width: n, height: n, strength: 1.1, dome: 0)
        XCTAssertLessThan(pixel(map, 20, n / 2, width: n).r, 100)
        XCTAssertGreaterThan(pixel(map, 27, n / 2, width: n).r, 156)
    }

    /// 縁の帯は左右がつながる（端の帯の傾きが向こう側の端にも出る）
    func testEdgeStripWraps() {
        let w = 40, h = 8
        var lum = [UInt8](repeating: 20, count: w * h)
        for y in 0..<h { lum[y * w] = 240; lum[y * w + 1] = 240 }
        let wrapped = MedalRelief.normalMap(luminance: lum, width: w, height: h, strength: 1, dome: 0, wrapsX: true)
        let clamped = MedalRelief.normalMap(luminance: lum, width: w, height: h, strength: 1, dome: 0)
        XCTAssertLessThan(pixel(wrapped, w - 1, h / 2, width: w).r, 120)
        XCTAssertEqual(pixel(clamped, w - 1, h / 2, width: w).r, 128, accuracy: 1)
    }

    /// 🔴 **表と裏は明るさから凹凸を起こさない**（文字や網目が盛り上がってざらつく・owner「少し気持ち悪い」）
    func testFacesIgnoreBrightness() {
        XCTAssertEqual(MedalRelief.faceRelief, 0)
        let n = 48
        var lum = [UInt8](repeating: 20, count: n * n)
        for y in 0..<n { for x in 22..<26 { lum[y * n + x] = 240 } }
        let map = MedalRelief.normalMap(luminance: lum, width: n, height: n, strength: 1.1, dome: 0,
                                        relief: MedalRelief.faceRelief)
        XCTAssertEqual(pixel(map, 20, n / 2, width: n).r, 128, accuracy: 1)
        XCTAssertEqual(pixel(map, 27, n / 2, width: n).r, 128, accuracy: 1)
    }

    func testRejectsMismatchedSize() {
        XCTAssertTrue(MedalRelief.normalMap(luminance: [1, 2, 3], width: 4, height: 4, strength: 1, dome: 0).isEmpty)
    }

    /// 配線: 表・裏・縁に法線の絵と映り込みを付け、表と裏は明るさを使わない。環境光は控えめ（強いと陰が消える）
    func testCoinUsesRelief() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Profile/MedalViewerView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("material.normal.contents = normal"))
        XCTAssertTrue(source.contains("edge.normal.contents = normal"))
        XCTAssertTrue(source.contains("material.reflective.contents = reflection"))
        XCTAssertTrue(source.contains("ambient.light?.intensity = 400"))
        XCTAssertTrue(source.contains("relief: MedalRelief.faceRelief"))
    }
}
