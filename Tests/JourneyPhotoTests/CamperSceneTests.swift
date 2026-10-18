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
        XCTAssertEqual(scene.cameraNode.camera?.bloomIntensity, 0.2)

        // 雪の部品は雪の時だけ見える
        let snowGroups = all(scene.scene.rootNode).filter { ($0.name ?? "").hasPrefix("camper.mood") && ($0.name ?? "").contains("snow") }
        XCTAssertFalse(snowGroups.isEmpty)
        XCTAssertTrue(snowGroups.allSatisfy(\.isHidden))
        var snow = day
        snow.mood = .snow
        scene.show(snow)
        XCTAssertTrue(snowGroups.contains { !$0.isHidden })
    }
}

#endif
