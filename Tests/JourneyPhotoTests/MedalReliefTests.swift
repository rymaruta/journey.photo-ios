import XCTest
@testable import JourneyPhoto

/// メダルの凹凸（2026-10-09 owner「3D回転させた時の立体感たりない・表も裏ものっぺり」）。
/// 明るいところが高い・面は中心がふくらむ・緑が上向き・縁の帯は左右がつながる。
/// 2026-10-14: 表と裏にほんの少しの浮き彫りと縁の面取り（owner「ほんの少しだけ凹凸感欲しい」）。
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

    // MARK: - ほんの少しの浮き彫りと面取り（2026-10-14 owner「ほんの少しだけ凹凸感欲しい」）

    /// 法線の色から傾きの大きさ（tan）を読む
    private func slope(_ p: (r: Int, g: Int, b: Int)) -> Double {
        let nx = Double(p.r) / 255 * 2 - 1, ny = Double(p.g) / 255 * 2 - 1, nz = max(0.01, Double(p.b) / 255 * 2 - 1)
        return (nx * nx + ny * ny).squareRoot() / nz
    }

    private func faceMap(_ lum: [UInt8], _ n: Int, amount: Double, dome: Double = 0) -> [UInt8] {
        let face = MedalRelief.face(amount: amount)
        return MedalRelief.normalMap(luminance: lum, width: n, height: n, strength: MedalRelief.strength, dome: dome,
                                     relief: face.relief, blurRadius: MedalRelief.faceBlurRadius,
                                     maxReliefSlope: face.maxSlope,
                                     bevelWidth: MedalRelief.bevelWidth, bevelDepth: face.bevelDepth)
    }

    /// 🔴 **強さは1つの定数で決まり、既定は控えめ**（10-09 の割合 1 は文字や網目までざらついた）
    func testSingleAmountDefaultIsGentle() {
        XCTAssertEqual(MedalRelief.amount, 1)
        XCTAssertLessThanOrEqual(MedalRelief.faceRelief, 0.1, "明るさを高さに使う割合が強すぎる")
        XCTAssertLessThanOrEqual(MedalRelief.maxReliefSlope, 0.35, "浮き彫りの傾きの上限が大きすぎる（約19°まで）")
        XCTAssertGreaterThan(MedalRelief.faceRelief, 0, "表と裏に浮き彫りが無い（のっぺりに戻る）")
        XCTAssertGreaterThan(MedalRelief.bevelDepth, 0, "縁の面取りが無い")
        // 強さを倍にすると、浮き彫り・上限・面取りがそろって倍になる
        let one = MedalRelief.face(amount: 1), two = MedalRelief.face(amount: 2)
        XCTAssertEqual(two.relief, one.relief * 2, accuracy: 1e-12)
        XCTAssertEqual(two.maxSlope, one.maxSlope * 2, accuracy: 1e-12)
        XCTAssertEqual(two.bevelDepth, one.bevelDepth * 2, accuracy: 1e-12)
        XCTAssertEqual(MedalRelief.face(amount: -1), MedalRelief.face(amount: 0))
    }

    /// 強さ 0 は前の作り（ふくらみだけ・明るさを見ない）と同じ絵になる
    func testAmountZeroIsPreviousLook() {
        let n = 48
        var lum = [UInt8](repeating: 20, count: n * n)
        for y in 0..<n { for x in 22..<26 { lum[y * n + x] = 240 } }
        let zero = faceMap(lum, n, amount: 0, dome: MedalRelief.dome)
        let before = MedalRelief.normalMap(luminance: lum, width: n, height: n, strength: MedalRelief.strength,
                                           dome: MedalRelief.dome, relief: 0)
        XCTAssertEqual(zero, before)
    }

    /// 🔴 **明るい形はうっすら盛り上がるが、傾きは上限まで**（急な文字の縁がぎらつかない）
    func testFaceReliefIsRaisedButCapped() {
        let n = 64
        var lum = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n { for x in 28..<36 { lum[y * n + x] = 255 } }
        let map = faceMap(lum, n, amount: 1)
        // 明るい帯の左の斜面は左を、右の斜面は右を向く
        XCTAssertLessThan(pixel(map, 27, n / 2, width: n).r, 124)
        XCTAssertGreaterThan(pixel(map, 36, n / 2, width: n).r, 132)
        // 縁の面取りより内側では、傾きは上限（少しの丸めの余裕）を超えない
        var steepest = 0.0
        for y in 12..<(n - 12) { for x in 12..<(n - 12) { steepest = max(steepest, slope(pixel(map, x, y, width: n))) } }
        XCTAssertLessThanOrEqual(steepest, MedalRelief.maxReliefSlope + 0.03)
        XCTAssertGreaterThan(steepest, MedalRelief.maxReliefSlope * 0.5, "浮き彫りが弱すぎて見えない")
    }

    /// 🔴 **細かい網目は盛り上げない**（1px の格子はぼかしで消える・10-09 の「気持ち悪い」の元）
    func testFineTextureStaysFlat() {
        let n = 48
        var lum = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n where (x + y) % 2 == 0 { lum[y * n + x] = 255 } }
        let map = faceMap(lum, n, amount: 1)
        for (x, y) in [(10, 10), (24, 24), (30, 17)] {
            XCTAssertLessThan(slope(pixel(map, x, y, width: n)), 0.03, "網目が盛り上がっている (\(x), \(y))")
        }
    }

    /// 🔴 **縁の面取り**: 円の外側の細い輪だけが外へ下がり（右の縁は右・上の縁は上を向く）、内側は平ら
    func testBevelSlopesOutwardOnlyAtRim() {
        let n = 200
        let lum = [UInt8](repeating: 128, count: n * n)
        let map = faceMap(lum, n, amount: 1)
        let mid = n / 2
        // 半径の 0.985 あたり（面取りの中ほど）
        XCTAssertGreaterThan(pixel(map, n - 2, mid, width: n).r, 150, "右の縁が右を向かない")
        XCTAssertLessThan(pixel(map, 1, mid, width: n).r, 106, "左の縁が左を向かない")
        XCTAssertGreaterThan(pixel(map, mid, 1, width: n).g, 150, "上の縁が上を向かない")
        // 内側（半径の 0.9）と中心は平ら
        XCTAssertEqual(pixel(map, mid + 90, mid, width: n).r, 128, accuracy: 1)
        XCTAssertEqual(pixel(map, mid, mid, width: n).r, 128, accuracy: 1)
        XCTAssertEqual(MedalRelief.bevelProfile(r: 0.5, width: 0.035), 0)
        XCTAssertEqual(MedalRelief.bevelProfile(r: 1, width: 0.035), 1)
        XCTAssertEqual(MedalRelief.bevelProfile(r: 1 - 0.0175, width: 0.035), 0.5, accuracy: 1e-9)
    }

    // MARK: - 角度と光

    /// 正面では、光は場面の主な光（左上手前）の向きそのまま。半周回すと左右と前後が逆になる
    func testLightInCoinFollowsRotation() {
        let k = MedalRelief.keyLight
        let len = (k.x * k.x + k.y * k.y + k.z * k.z).squareRoot()
        let front = MedalRelief.lightInCoin(yaw: 0, pitch: 0)
        XCTAssertEqual(front.x, k.x / len, accuracy: 1e-9)
        XCTAssertEqual(front.y, k.y / len, accuracy: 1e-9)
        XCTAssertEqual(front.z, k.z / len, accuracy: 1e-9)
        let turned = MedalRelief.lightInCoin(yaw: .pi, pitch: 0)
        XCTAssertEqual(turned.x, -k.x / len, accuracy: 1e-9)
        XCTAssertEqual(turned.y, k.y / len, accuracy: 1e-9)
        XCTAssertEqual(turned.z, -k.z / len, accuracy: 1e-9)
        // 長さは 1 のまま（傾けても）
        let tilted = MedalRelief.lightInCoin(yaw: 0.7, pitch: -0.14)
        XCTAssertEqual(tilted.x * tilted.x + tilted.y * tilted.y + tilted.z * tilted.z, 1, accuracy: 1e-9)
        // 右へ回す（yaw が増える）と、硬貨から見た光は左へ寄る
        XCTAssertLessThan(MedalRelief.lightInCoin(yaw: 0.5, pitch: 0).x, front.x)
    }

    /// 🔴 **回す向きで、面取りの光る側と陰る側が入れ替わる**（法線の絵を読んで確かめる）
    func testBevelHighlightSwapsWithTurn() {
        let n = 200
        let map = faceMap([UInt8](repeating: 128, count: n * n), n, amount: 1)
        func normal(_ x: Int, _ y: Int) -> (x: Double, y: Double, z: Double) {
            let p = pixel(map, x, y, width: n)
            return (Double(p.r) / 255 * 2 - 1, Double(p.g) / 255 * 2 - 1, Double(p.b) / 255 * 2 - 1)
        }
        let left = normal(1, n / 2), right = normal(n - 2, n / 2)
        let pitch = -0.14
        let leftTurn = MedalRelief.keyShade(normal: right, yaw: -0.6, pitch: pitch)
            - MedalRelief.keyShade(normal: left, yaw: -0.6, pitch: pitch)
        let rightTurn = MedalRelief.keyShade(normal: right, yaw: 0.6, pitch: pitch)
            - MedalRelief.keyShade(normal: left, yaw: 0.6, pitch: pitch)
        XCTAssertGreaterThan(leftTurn, 0.02, "左へ回したとき右の面取りが光らない")
        XCTAssertLessThan(rightTurn, -0.02, "右へ回したとき左の面取りが光らない")
    }

    /// 傾きの頭打ちは向きを変えず、小さい傾きはほぼそのまま・大きい傾きは上限に寄る
    func testSoftLimit() {
        let small = MedalRelief.softLimit(0.03, 0.04, limit: 0.3)
        XCTAssertEqual(small.0, 0.03, accuracy: 0.001)
        XCTAssertEqual(small.1, 0.04, accuracy: 0.001)
        let big = MedalRelief.softLimit(30, 40, limit: 0.3)
        XCTAssertEqual((big.0 * big.0 + big.1 * big.1).squareRoot(), 0.3, accuracy: 1e-6)
        XCTAssertEqual(big.0 / big.1, 0.75, accuracy: 1e-9)
        XCTAssertEqual(MedalRelief.softLimit(1, 1, limit: 0).0, 0)
    }

    // MARK: - 「視差効果を減らす」

    /// 🔴 **「視差効果を減らす」の人には浮き彫り（と映り込み）を半分に**（回すと動く光と陰を弱める）
    func testReduceMotionWeakensRelief() {
        XCTAssertEqual(MedalRelief.effectiveAmount(reduceMotion: false), MedalRelief.amount)
        XCTAssertEqual(MedalRelief.effectiveAmount(reduceMotion: true), MedalRelief.amount * 0.5, accuracy: 1e-12)
        XCTAssertEqual(MedalRelief.effectiveAmount(reduceMotion: true, base: 1), 0.5, accuracy: 1e-12)
        XCTAssertLessThan(MedalRelief.face(amount: MedalRelief.effectiveAmount(reduceMotion: true)).maxSlope,
                          MedalRelief.face(amount: MedalRelief.effectiveAmount(reduceMotion: false)).maxSlope)
    }

    // MARK: - 画面写真の向き

    func testPoseParsing() {
        XCTAssertEqual(MedalPose.parse("0:1,0.45:1,1.1:2"),
                       [MedalPose(yaw: 0, amount: 1), MedalPose(yaw: 0.45, amount: 1), MedalPose(yaw: 1.1, amount: 2)])
        // 強さを省くと既定・範囲の外は収める・読めない組みは飛ばす
        XCTAssertEqual(MedalPose.parse(" 0.3 , x:1, 0.5:9, 0.6:-1, 0.7:y"),
                       [MedalPose(yaw: 0.3, amount: MedalRelief.amount), MedalPose(yaw: 0.5, amount: 3),
                        MedalPose(yaw: 0.6, amount: 0)])
        XCTAssertEqual(MedalPose.parse(""), [])
    }

    func testRejectsMismatchedSize() {
        XCTAssertTrue(MedalRelief.normalMap(luminance: [1, 2, 3], width: 4, height: 4, strength: 1, dome: 0).isEmpty)
    }

    /// 配線: 表・裏・縁に法線の絵と映り込みを付け、表と裏は控えめな浮き彫りと面取り。環境光は控えめ（強いと陰が消える）。
    /// 法線の絵は画面の処理の外で作り、「視差効果を減らす」で弱め、主な光は `MedalRelief.keyLight` と同じ位置
    func testCoinUsesRelief() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Profile/MedalViewerView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("material.normal.contents = normal"))
        XCTAssertTrue(source.contains("edge.normal.contents = edgeMap"))
        XCTAssertTrue(source.contains("material.reflective.contents = reflection"))
        XCTAssertTrue(source.contains("ambient.light?.intensity = 400"))
        XCTAssertTrue(source.contains("relief: face.relief"))
        XCTAssertTrue(source.contains("maxReliefSlope: face.maxSlope"))
        XCTAssertTrue(source.contains("bevelDepth: face.bevelDepth"))
        XCTAssertTrue(source.contains("blurRadius: MedalRelief.faceBlurRadius"))
        XCTAssertTrue(source.contains("MedalRelief.effectiveAmount(reduceMotion: reduceMotion)"))
        XCTAssertTrue(source.contains("Task.detached(priority: .userInitiated)"))
        XCTAssertTrue(source.contains("let key = MedalRelief.keyLight"))
        // 画面写真の向きは Debug の起動の鍵からだけ
        XCTAssertTrue(source.contains("private let previewPoses = PreviewSession.medalPoses"))
    }
}
