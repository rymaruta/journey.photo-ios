import XCTest
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif
@testable import JourneyPhoto

#if canImport(SceneKit) || canImport(SceneKitShim)

/// 組み上げた場面（ノードの属性）で、灯りの組・室内灯の影・夜のにじみ・時刻の切り替えを確かめる
/// （#312 の見直し: ソースの文字列ではなく、組んだ結果を見る）
@MainActor
final class CamperSceneTests: XCTestCase {

    private func all(_ n: SCNNode) -> [SCNNode] { [n] + n.childNodes.flatMap { all($0) } }

    private func node(_ scene: CamperScene, _ name: String) -> SCNNode? {
        all(scene.scene.rootNode).first { $0.name == name }
    }

    private func lights(_ scene: CamperScene) -> [(name: String, light: SCNLight)] {
        all(scene.scene.rootNode).compactMap { n in
            guard let l = n.light, let name = n.name, name.hasPrefix("light.") else { return nil }
            return (String(name.dropFirst("light.".count)), l)
        }
    }

    /// 室内の灯りは室内の組だけを照らし、影は forward（deferred は円錐の外の画面を黒く塗った・run 538）。
    /// 外の灯りは外の組だけ。まとめた形にも組が付く
    func testLightGroupsAndInteriorShadows() async throws {
        let scene = CamperScene()
        scene.installNow(CamperConfig(stage: .camper, mood: .night))
        let ls = lights(scene)
        let interior = ls.filter { $0.name.hasPrefix("interior.") }
        XCTAssertEqual(interior.count, 2)
        for (name, l) in interior {
            XCTAssertEqual(l.categoryBitMask, CamperScene.insideMask, name)
            XCTAssertTrue(l.castsShadow, name)
            XCTAssertEqual(l.shadowMode, .forward, name)
            XCTAssertGreaterThan(l.intensity, 0, name)
        }
        let outside = ls.filter { !$0.name.hasPrefix("interior.") }
        XCTAssertFalse(outside.isEmpty)
        for (name, l) in outside { XCTAssertEqual(l.categoryBitMask, CamperScene.outsideMask, name) }
        XCTAssertEqual(try XCTUnwrap(node(scene, "camper.outside")).categoryBitMask, CamperScene.outsideMask)
        XCTAssertEqual(try XCTUnwrap(node(scene, "camper.inside")).categoryBitMask, CamperScene.insideMask)
        XCTAssertEqual(try XCTUnwrap(node(scene, "camper.door")).categoryBitMask, CamperScene.outsideMask)
        // 夜はにじみなし
        XCTAssertEqual(scene.cameraNode.camera?.bloomIntensity, 0)
    }

    /// 夜に停めている車: 前照灯・尾灯の光は場面に無い。点くのは入口の灯り（外の組・下向きの spot・減衰あり）と
    /// 室内・外の火だけ（2026-10-19 owner「テールランプとかの灯りが不自然すぎる」）
    func testParkedNightHasNoDrivingLights() async throws {
        let scene = CamperScene()
        scene.installNow(CamperConfig(stage: .camper, mood: .night))
        let ls = lights(scene)
        XCTAssertFalse(ls.contains { $0.name.hasPrefix("headlight") || $0.name.hasPrefix("taillight") }, "停めた車の走る灯りが点いている")
        let porch = try XCTUnwrap(ls.first { $0.name == "porch" }?.light, "入口の灯りが無い")
        XCTAssertEqual(porch.categoryBitMask, CamperScene.outsideMask)
        XCTAssertEqual(porch.type, .spot)
        XCTAssertFalse(porch.castsShadow)
        XCTAssertGreaterThan(porch.attenuationEndDistance, 0, "減衰が無い")
        XCTAssertLessThanOrEqual(porch.attenuationEndDistance, 1.6)
        XCTAssertNil(node(scene, "glow.beam"))
        XCTAssertNil(node(scene, "glow.tail"))
        XCTAssertNotNil(node(scene, "glow.step"))
        XCTAssertLessThanOrEqual(ls.count + 2, 8, "月と環境光を足して 8 まで")
    }

    /// 昼・夜・雪の切り替えは組み直さない（同じ形のまま、灯り・その時刻の部品・にじみだけが替わる）
    func testMoodSwitchKeepsTheModel() async throws {
        let scene = CamperScene()
        let day = CamperConfig(stage: .camper, mood: .day)
        scene.installNow(day)
        let body = try XCTUnwrap(node(scene, "camper.outside"))
        var markers: [String] = []
        scene.onReady = { markers.append($0) }

        var night = day
        night.mood = .night
        scene.show(night)
        XCTAssertTrue(try XCTUnwrap(node(scene, "camper.outside")) === body, "夜にしただけで組み直した")
        XCTAssertEqual(markers.last?.hasPrefix("camper-ready camper night"), true, "切り替えの合図が出ない")
        XCTAssertEqual(scene.currentMood, .night)
        XCTAssertTrue(all(scene.scene.rootNode).filter { $0.light != nil && ($0.name ?? "").hasPrefix("light.") }.allSatisfy { !$0.isHidden })
        XCTAssertEqual(scene.cameraNode.camera?.bloomIntensity, 0)

        scene.show(day)
        XCTAssertTrue(try XCTUnwrap(node(scene, "camper.outside")) === body)
        // 昼は夜の灯りのノードが隠れている（強さ 0 で残さない）
        let lightNodes = all(scene.scene.rootNode).filter { $0.light != nil && ($0.name ?? "").hasPrefix("light.") }
        XCTAssertFalse(lightNodes.isEmpty)
        XCTAssertTrue(lightNodes.allSatisfy(\.isHidden), "昼に夜の灯りが残っている")
        // 本物の SceneKit は Float で持つので 0.2 が 0.20000000298… になる（Mac run 39168741248）。誤差つきで比べる
        XCTAssertEqual(Double(try XCTUnwrap(scene.cameraNode.camera?.bloomIntensity)), 0.2, accuracy: 0.0001)

        // 雪の部品は雪の時だけ見える
        let snowGroups = all(scene.scene.rootNode).filter { ($0.name ?? "").hasPrefix("camper.mood") && ($0.name ?? "").contains("snow") }
        XCTAssertFalse(snowGroups.isEmpty)
        XCTAssertTrue(snowGroups.allSatisfy(\.isHidden))
        var snow = day
        snow.mood = .snow
        scene.show(snow)
        XCTAssertTrue(snowGroups.contains { !$0.isHidden })
    }

    /// 夜だけ炎と焚き火・ランタンの光が揺れる。昼は止まり、「視差効果を減らす」でも止まる
    func testFlickerOnlyAtNight() async throws {
        let scene = CamperScene()
        var l = CamperLoadout.standard
        l.picks[CamperCategory.outdoorLight.rawValue] = "brass_lantern"
        var changes: [Bool] = []
        scene.onFlickerChange = { changes.append($0) }
        scene.installNow(CamperConfig(stage: .camper, mood: .night, loadout: l))
        XCTAssertTrue(scene.isFlickering)
        let flames = all(scene.scene.rootNode).filter { ($0.name ?? "").hasSuffix("Flame") || $0.name == "fire.flame" }
        XCTAssertGreaterThanOrEqual(flames.count, 4)
        #if canImport(SceneKitShim) && !canImport(SceneKit)
        XCTAssertTrue(flames.allSatisfy { $0.actionKeys.contains("flicker") })
        #endif
        scene.setFlicker(allowed: false)
        XCTAssertFalse(scene.isFlickering)
        scene.setFlicker(allowed: true)
        var day = CamperConfig(stage: .camper, mood: .night, loadout: l)
        day.mood = .day
        scene.show(day)
        XCTAssertFalse(scene.isFlickering)
        XCTAssertEqual(changes, [true, false, true, false])
    }

    /// 夜に替えると、太陽（月）・周りの光・露出・環境光が夜の値になる。昼に戻せば昼の値（組み直さない切り替えの道）。
    /// 2026-10-19（Mac run 547）: 95b が昼の絵のまま写った。前からある試験は灯り・にじみ・雪の部品しか見ておらず、
    /// 太陽や露出を見ていなかった。また画面に絵が出る速さ（SCNView の描き直し）は Linux の模型では見えない——
    /// 原因は描き方の設定の切り替え（`CamperSceneView`）で、ここでは値が夜に替わることだけを守る
    func testNightLightingValues() async throws {
        let scene = CamperScene()
        let day = CamperConfig(stage: .camper, mood: .day)
        scene.installNow(day)
        let d = scene.lightingSnapshot
        XCTAssertEqual(d.sun, 1200, accuracy: 0.5)
        XCTAssertEqual(d.environment, 1.35, accuracy: 0.001)
        XCTAssertEqual(d.exposure, 0, accuracy: 0.001)
        var night = day
        night.mood = .night
        scene.show(night)
        let n = scene.lightingSnapshot
        XCTAssertEqual(n.sun, 260, accuracy: 0.5, "月の強さになっていない")
        XCTAssertEqual(n.environment, 0.14, accuracy: 0.001, "周りの光が昼のまま")
        XCTAssertEqual(n.exposure, -0.15, accuracy: 0.001, "露出が昼のまま")
        XCTAssertEqual(n.ambient, 60, accuracy: 0.5)
        scene.show(day)
        XCTAssertEqual(scene.lightingSnapshot.sun, 1200, accuracy: 0.5)
        XCTAssertEqual(scene.lightingSnapshot.environment, 1.35, accuracy: 0.001)
    }
}

#endif
