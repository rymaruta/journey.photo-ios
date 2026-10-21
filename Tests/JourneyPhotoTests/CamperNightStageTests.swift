import XCTest
@testable import JourneyPhoto

/// 夜の外の場面の作り（2026-10-21・owner「光の感じまじで残念」「夜のキャンピングカーの外だね」）。
/// 空・地面・遠景・光の値を、素の Swift の部品で確かめる（本物の見た目は Mac の画面写真 95b・95k・95l・95n・95o・95p）
final class CamperNightStageTests: XCTestCase {

    private func luminance(_ c: (Double, Double, Double)) -> Double { 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }

    /// 空は真っ黒ではなく深い紺の階調（天頂がいちばん暗く、地平線の霞へ明るくなる）。地平線の下は霞の色で、
    /// 地面の果て（`CamperNightHaze` の色）と同じ——境目の線を出さない
    func testNightSkyIsADeepBlueGradient() {
        let sky = CamperTextures.nightSky()
        XCTAssertLessThanOrEqual(max(sky.width, sky.height), CamperTextures.maxSide)
        func px(_ y: Int) -> (Double, Double, Double) {
            let p = sky.pixel(40, y)
            return (Double(p.r) / 255, Double(p.g) / 255, Double(p.b) / 255)
        }
        let zenith = px(0), mid = px(32), horizon = px(62)
        XCTAssertLessThan(luminance(zenith), luminance(mid))
        XCTAssertLessThan(luminance(mid), luminance(horizon))
        XCTAssertGreaterThan(luminance(zenith), 0.02, "天頂が真っ黒")
        XCTAssertGreaterThan(zenith.2, zenith.0 * 1.6, "空が青くない")
        let below = sky.pixel(40, 100), haze = CamperTextures.rgb(CamperMaterials.NightStage.haze)
        XCTAssertEqual(Double(below.r) / 255, haze.0, accuracy: 0.01)
        XCTAssertEqual(Double(below.b) / 255, haze.2, accuracy: 0.01)
    }

    /// 映り込みの空は見える空より明るく（長い露出の分）、上が明るく地面が暗い（面の向きで明暗が出る）。
    /// 月の側の明るさは大きな丸で、小さな点にしない（塗装に細い光の筋がちらつく・run 532）
    func testNightEnvironmentLightsFromAbove() {
        let env = CamperTextures.nightEnvironment()
        let sky = CamperTextures.nightSky()
        func lum(_ b: CamperBitmap, _ x: Int, _ y: Int) -> Double {
            let p = b.pixel(x, y)
            return luminance((Double(p.r) / 255, Double(p.g) / 255, Double(p.b) / 255))
        }
        XCTAssertGreaterThan(lum(env, 10, 10), lum(sky, 10, 10), "映り込みの空が見える空より暗い")
        XCTAssertGreaterThan(lum(env, 10, 10), lum(env, 10, 120) * 2, "上と下の明暗が無い")
        var brightest = 0.0, count = 0
        for y in 0..<64 { for x in 0..<256 { brightest = max(brightest, lum(env, x, y)) } }
        for y in 0..<64 { for x in 0..<256 where lum(env, x, y) > brightest * 0.9 { count += 1 } }
        XCTAssertGreaterThan(count, 40, "月の明るさが小さな点になっている")
        XCTAssertLessThan(brightest, 0.6, "映り込みの空が白い")
    }

    /// 地面は繰り返す絵（256 まで）で、継ぎ目が出ない（左右の端の差が、絵の中の隣どうしの差と同じくらい）。暗い芝の色
    func testGroundTilesWithoutSeams() {
        let g = CamperTextures.groundNight()
        XCTAssertLessThanOrEqual(max(g.width, g.height), CamperTextures.maxSide)
        var diff = 0.0, inner = 0.0
        for y in 0..<g.height {
            let a = g.pixel(0, y), b = g.pixel(g.width - 1, y), c = g.pixel(g.width / 2, y), d = g.pixel(g.width / 2 + 1, y)
            diff += abs(Double(a.g) - Double(b.g))
            inner += abs(Double(c.g) - Double(d.g))
        }
        XCTAssertLessThan(diff, inner * 1.6, "左右の端に継ぎ目")
        let ground = CamperTextures.rgb(CamperMaterials.NightStage.ground)
        XCTAssertLessThan(luminance(ground), 0.4)
        XCTAssertGreaterThan(ground.1, ground.2, "芝の色が青い")
    }

    /// 遠景の木はカメラと車の間に置かない（カメラはいつも手前 +Z の側）。奥と両脇の遠くだけ。網の大きさは控えめ
    func testTreesStayBehindTheCar() {
        let trees = CamperNightScenery.trees()
        XCTAssertGreaterThanOrEqual(trees.count, 40)
        for t in trees {
            XCTAssertTrue(t.base.z < -700 || abs(t.base.x) > 1200, "木が手前にある: \(t.base)")
            XCTAssertLessThanOrEqual(t.base.z, 800)
            XCTAssertGreaterThan(t.height, 300)
        }
        let mesh = CamperNightScenery.treeMesh(trees, material: .tint(0))
        let ridge = CamperNightScenery.ridgeMesh(material: .tint(0))
        XCTAssertLessThan(mesh.triangleCount + ridge.triangleCount, 6000, "遠景の三角形が多い")
        // いちばん下の段の裾は地面まで（幹と水平な縁が四角い建物に見えた・Mac run 627）
        XCTAssertLessThanOrEqual(mesh.positions.map(\.y).min() ?? 1, 0)
        // 稜線は地面の内（一辺 140 m の半分より内）
        let r = ridge.positions.map { ($0.x * $0.x + $0.z * $0.z).squareRoot() }.max() ?? 0
        XCTAssertLessThan(r / 100, CamperMaterials.NightStage.groundSize / 2)
    }

    /// 霞の shader: 地平線の霞の色（線形）へ寄せる。昼の床の shader と同じ書き方（世界の位置）
    func testHazeShaderUsesLinearHazeColor() {
        let shader = CamperNightHaze.shader(start: 6, end: 46, mist: 0.3, floor: 0.1)
        let h = CamperMaterials.linear(CamperMaterials.NightStage.haze)
        XCTAssertTrue(shader.contains(String(format: "%.5f", h.2)))
        XCTAssertTrue(shader.contains("scn_frame.inverseViewTransform"))
        XCTAssertTrue(shader.contains("smoothstep(6.00000, 46.00000"))
        XCTAssertEqual(CamperMaterials.linear(0xFFFFFF).0, 1, accuracy: 0.0001)
        XCTAssertEqual(CamperMaterials.linear(0x808080).0, 0.2159, accuracy: 0.001)
    }

    /// 白飛びしない光の釣り合い（線形の光の量の見積もり・露出 0）: 月が当たるクリーム色の屋根でも 0.6 まで、
    /// 一様な環境光は 0（のっぺりさせない）、空の光だけの横の面も真っ黒ではない
    func testNightLightBalanceDoesNotBlowOut() {
        let st = CamperMaterials.NightStage.self
        let cap = CamperMaterials.linear(CamperMaterials.spec(.cap, paint: 0x5B6168, mood: .night).color)
        let moon = CamperMaterials.linear(CamperMaterials.sun(.night).color)
        let top = CamperMaterials.linear(st.envTop)
        let roof = luminance((cap.0 * (moon.0 * st.moon / 1000 + top.0 * st.environment),
                              cap.1 * (moon.1 * st.moon / 1000 + top.1 * st.environment),
                              cap.2 * (moon.2 * st.moon / 1000 + top.2 * st.environment)))
        XCTAssertLessThan(roof, 0.6, "月の当たる屋根が白く飛ぶ")
        XCTAssertGreaterThan(roof, 0.1, "月の当たる屋根が読めない")
        XCTAssertEqual(CamperMaterials.fill(.night).ambient, 0)
        let horizon = CamperMaterials.linear(st.envHorizon)
        let side = luminance((cap.0 * horizon.0, cap.1 * horizon.1, cap.2 * horizon.2)) * st.environment * 0.5
        XCTAssertGreaterThan(side, 0.01, "横の面が真っ黒")
    }

    /// 夜の空・空の光・地面の絵と、林と山の網は下ごしらえ（画面の処理の外）で作る（確かめ役 2026-10-21）
    func testNightAssetsArePreparedOffTheMainThread() {
        let plan = CamperScenePlan.make(CamperConfig(stage: .camper, mood: .day))
        for key in ["sky.night", "env.night.outdoor", "ground.night"] { XCTAssertNotNil(plan.bitmaps[key], key) }
        XCTAssertGreaterThan(plan.nightScenery.trees.vertexCount, 0)
        XCTAssertGreaterThan(plan.nightScenery.ridge.vertexCount, 0)
        // 三角形の数（docs/CAMPER.md の性能の記録と合わせる）
        let tris = plan.nightScenery.trees.groups.reduce(0) { $0 + $1.indices.count / 3 }
            + plan.nightScenery.ridge.groups.reduce(0) { $0 + $1.indices.count / 3 }
        XCTAssertLessThan(tris, 4200)
    }
}
