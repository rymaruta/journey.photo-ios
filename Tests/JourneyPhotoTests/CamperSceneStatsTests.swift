import XCTest
import UIKit
@testable import JourneyPhoto

#if canImport(SceneKit)
import SceneKit

/// 場面の中身の数（2026-11-06・札 #430 のメモリの内訳）。測るだけで、見た目は変えない
final class CamperSceneStatsTests: XCTestCase {

    private func image(side: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return r.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    func testCountsNodesGeometriesMaterialsAndTextures() {
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = image(side: 8)
        box.materials = [material]

        let root = SCNNode()
        let a = SCNNode(geometry: box)
        let b = SCNNode(geometry: box)          // 同じ図形を使い回している（図形は 1・図形を持つ節は 2）
        let lamp = SCNNode()
        lamp.light = SCNLight()
        root.addChildNode(a)
        root.addChildNode(b)
        root.addChildNode(lamp)

        let s = CamperSceneStats.measure(root)
        XCTAssertEqual(s.nodes, 4)
        XCTAssertEqual(s.geometries, 1, "同じ図形は 1 と数える")
        XCTAssertEqual(s.instances, 2, "図形を持つ節は描く回数の目安")
        XCTAssertEqual(s.materials, 1)
        XCTAssertEqual(s.textures, 1)
        XCTAssertEqual(s.textureMB, Double(8 * 8 * 4) / 1_048_576, accuracy: 0.0001)
        XCTAssertEqual(s.lights, 1)
        XCTAssertGreaterThan(s.vertices, 0)
        XCTAssertGreaterThan(s.triangles, 0)
        XCTAssertGreaterThan(s.geometryKB, 0)
    }

    func testSameImageSharedByMaterialsCountsOnce() {
        let shared = image(side: 4)
        let g = SCNPlane(width: 1, height: 1)
        let m1 = SCNMaterial(), m2 = SCNMaterial()
        m1.diffuse.contents = shared
        m2.diffuse.contents = shared
        g.materials = [m1, m2]
        let s = CamperSceneStats.measure(SCNNode(geometry: g))
        XCTAssertEqual(s.materials, 2)
        XCTAssertEqual(s.textures, 1, "同じ貼り絵を使い回していれば 1")
    }

    func testFieldsAreOneLineWithoutSpacesInsideValues() {
        var s = CamperSceneStats()
        s.nodes = 3; s.textureMB = 1.25
        let f = s.fields
        XCTAssertTrue(f.hasPrefix("nodes=3 geoms=0 inst=0 verts=0 tris=0 geo_kb=0 mats=0 texs=0 tex_mb=1.2"), f)
        XCTAssertFalse(f.contains("\n"))
        XCTAssertFalse(f.contains(";"), "UI テストは ; で区切って読む")
    }

    func testPublishOnlyWhenMeterEnabled() {
        let root = SCNNode()
        let off = CamperRenderMeter(enabled: false)
        CamperSceneStats.publish("SceneExterior", root: root, meter: off)
        XCTAssertEqual(off.summary(), "")
        let on = CamperRenderMeter(enabled: true)
        CamperSceneStats.publish("SceneExterior", root: root, meter: on)
        XCTAssertTrue(on.summary().contains("SceneExterior nodes=1 "), on.summary())
    }
}
#endif
