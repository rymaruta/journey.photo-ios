import XCTest
@testable import JourneyPhoto

/// キャンピングカーの形の計算（穴のある多角形・閉じた立体・面の数・2026-10-18）
final class CamperGeometryTests: XCTestCase {

    private func area(_ tris: [CV2]) -> Double {
        var s = 0.0
        var i = 0
        while i + 2 < tris.count {
            s += (tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i]) / 2
            i += 3
        }
        return s
    }

    /// 穴のある四角を三角形に分けると、面積は「外 − 穴」になり、どの三角形も表向き（反時計回り）
    func testTriangulateWithHoles() {
        let outer = [CV2(0, 0), CV2(100, 0), CV2(100, 60), CV2(0, 60)]
        let holes = [CamperPolygon.roundedRect(x: 10, y: 10, w: 30, h: 20, r: 4),
                     CamperPolygon.circle(CV2(70, 30), 12, count: 20)]
        let tris = CamperPolygon.triangulate(outer: outer, holes: holes)
        let expected = 6000 - abs(CamperPolygon.signedArea(holes[0])) - abs(CamperPolygon.signedArea(holes[1]))
        XCTAssertEqual(area(tris), expected, accuracy: 0.5)
        var i = 0
        while i + 2 < tris.count {
            XCTAssertGreaterThan((tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i]), 0)
            i += 3
        }
        // 穴の真ん中は塗られていない
        let inHole = CV2(25, 20)
        var covered = false
        i = 0
        while i + 2 < tris.count {
            let a = tris[i], b = tris[i + 1], c = tris[i + 2]
            if (b - a).cross(inHole - a) > 0, (c - b).cross(inHole - b) > 0, (a - c).cross(inHole - c) > 0 { covered = true }
            i += 3
        }
        XCTAssertFalse(covered, "窓の穴が塞がっている")
    }

    /// 凹んだ形（床の切り欠き）も面積が合う
    func testTriangulateConcave() {
        let p = [CV2(0, 0), CV2(10, 0), CV2(10, 4), CV2(20, 4), CV2(20, 0), CV2(30, 0), CV2(30, 10), CV2(0, 10)]
        XCTAssertEqual(area(CamperPolygon.triangulate(outer: p)), 260, accuracy: 0.01)
    }

    /// 帯で切った三角形の面積の合計は元と同じ（塗り分けで穴が空かない）
    func testBandsKeepArea() {
        let tris = CamperPolygon.triangulate(outer: CamperPolygon.circle(CV2(0, 0), 10, count: 32))
        let total = area(tris)
        let parts = [(-100.0, -2.0), (-2.0, 1.5), (1.5, 100.0)].map { area(CamperPolygon.clipTriangles(tris, minY: $0.0, maxY: $0.1)) }
        XCTAssertEqual(parts.reduce(0, +), total, accuracy: 0.01)
    }

    /// 厚みのある板（穴あり）は閉じた立体（どの辺も2枚の面で共有）
    func testSlabIsClosed() {
        let outline = [CV2(0, 0), CV2(60, 0), CV2(60, 40), CV2(0, 40)]
        let slab = CamperMeshKit.slab(outline: outline, holes: [CamperPolygon.roundedRect(x: 10, y: 10, w: 20, h: 15, r: 3)],
                                      thickness: 4, bevel: 1.5, holeBevel: 0.6,
                                      bands: [CamperBand(minY: -.infinity, maxY: 20, material: .deep),
                                              CamperBand(minY: 20, maxY: .infinity, material: .paint)],
                                      back: .inner, reveal: .reveal)
        XCTAssertEqual(slab.openEdgeCount, 0, "板の縁が開いている")
        XCTAssertTrue(slab.materials.contains(.deep) && slab.materials.contains(.paint) && slab.materials.contains(.reveal))
    }

    /// 旋盤の形は蓋をすれば閉じる。法線は外を向く
    func testLatheClosedAndOutward() {
        let m = CamperMeshKit.lathe([CV2(14, 0), CV2(19.4, 0), CV2(22, 3), CV2(22, 19), CV2(19.4, 22), CV2(14, 22)], segments: 24,
                                    material: { _ in .rubber })
        // 内側の筒は開いている（穴）ので、縁の数は 2 本の輪の分だけ
        XCTAssertEqual(m.openEdgeCount, 48)
        for (p, n) in zip(m.positions, m.normals) where (CV2(p.x, p.z).length > 21.9) && p.y > 4 && p.y < 18 {
            XCTAssertGreaterThan(CV3(p.x, 0, p.z).normalized.dot(n), 0.9)
        }
    }

    /// 巻きは法線に合わせる（三角形の表と法線が同じ向き）
    func testWindingFollowsNormals() {
        var m = CamperMesh()
        m.tri(CV3(0, 0, 0), CV3(0, 1, 0), CV3(1, 0, 0), normal: CV3(0, 0, 1), .paint)
        let i = m.groups[0].indices.map { m.positions[Int($0)] }
        XCTAssertGreaterThan((i[1] - i[0]).cross(i[2] - i[0]).dot(CV3(0, 0, 1)), 0)
    }

    func testQuaternionRotates() {
        let q = CQuat.yTo(CV3(1, 0, 0))
        let v = q.rotate(CV3(0, 1, 0))
        XCTAssertEqual(v.x, 1, accuracy: 1e-9)
        let r = CQuat.rotation(from: CV3(0, 0, 1), to: CV3(-1, 0, 0)).rotate(CV3(0, 0, 1))
        XCTAssertEqual(r.x, -1, accuracy: 1e-9)
    }
}
