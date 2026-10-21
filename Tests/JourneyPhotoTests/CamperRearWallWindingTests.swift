import XCTest
@testable import JourneyPhoto

/// 後部壁の巻きと法線（2026-10-20: mirror の誤用で外から内張りが見え、夜に後部が真っ白に飛んだ）
final class CamperRearWallWindingTests: XCTestCase {

    /// 巻きと頂点法線が同じ向きか（全三角形）
    private func windingMismatchCount(_ m: CamperMesh) -> (tris: Int, mismatch: Int) {
        var tris = 0, mismatch = 0
        for g in m.groups {
            var i = 0
            let idx = g.indices
            while i + 2 < idx.count {
                let ia = Int(idx[i]), ib = Int(idx[i + 1]), ic = Int(idx[i + 2])
                let pa = m.positions[ia], pb = m.positions[ib], pc = m.positions[ic]
                let n = ((m.normals[ia] + m.normals[ib] + m.normals[ic]) * (1.0 / 3)).normalized
                let geom = (pb - pa).cross(pc - pa).normalized
                tris += 1
                if geom.dot(n) < 0 { mismatch += 1 }
                i += 3
            }
        }
        return (tris, mismatch)
    }

    func testRearWallWindingMatchesNormals() {
        let b = CamperBuilder.build(CamperConfig(stage: .camper, mood: .night, loadout: .standard))
        guard case .mesh(let rear)? = b.nodes(named: "body.rearWall").first?.shape else {
            return XCTFail("body.rearWall missing")
        }
        let s = windingMismatchCount(rear)
        XCTAssertGreaterThan(s.tris, 50)
        XCTAssertEqual(s.mismatch, 0, "後部壁の巻きが法線と逆（外から内張りが見える）: \(s.mismatch)/\(s.tris)")

        // 後面の主面（法線の主成分が X）は −X。窓の面取りなど Y/Z 向きは除外
        let rearX = -122.0
        let outer: Set<CamperMaterial> = [.paint, .cap, .deep, .pinstripe, .pinstripeDark]
        var faceOut = 0, faceIn = 0
        for g in rear.groups where outer.contains(g.material) {
            var i = 0
            while i + 2 < g.indices.count {
                let ia = Int(g.indices[i]), ib = Int(g.indices[i + 1]), ic = Int(g.indices[i + 2])
                let c = (rear.positions[ia] + rear.positions[ib] + rear.positions[ic]) * (1.0 / 3)
                let n = ((rear.normals[ia] + rear.normals[ib] + rear.normals[ic]) * (1.0 / 3)).normalized
                if abs(c.x - rearX) < 0.6, abs(n.x) > abs(n.y), abs(n.x) > abs(n.z) {
                    if n.x < 0 { faceOut += 1 } else { faceIn += 1 }
                }
                i += 3
            }
        }
        XCTAssertGreaterThan(faceOut, 20)
        XCTAssertEqual(faceIn, 0, "後部の主面が内側を向いている: in=\(faceIn) out=\(faceOut)")
    }

    /// 後ろの窓枠・ガラスも同じ写し（巻きが法線と一致）
    func testRearWindowWindingMatchesNormals() {
        let b = CamperBuilder.build(CamperConfig(stage: .camper, mood: .night, loadout: .standard))
        guard case .mesh(let m)? = b.nodes(named: "rear.window").first?.shape else {
            return XCTFail("rear.window missing")
        }
        let s = windingMismatchCount(m)
        XCTAssertGreaterThan(s.tris, 10)
        XCTAssertEqual(s.mismatch, 0, "後ろの窓の巻きが法線と逆: \(s.mismatch)/\(s.tris)")
    }

    /// 側面はもともと正しい（回帰で壊さない）
    func testSideWallsStillMatch() {
        let b = CamperBuilder.build(CamperConfig(stage: .camper, mood: .night, loadout: .standard))
        for name in ["body.side.near", "body.side.far"] {
            guard case .mesh(let m)? = b.nodes(named: name).first?.shape else {
                return XCTFail("\(name) missing")
            }
            let s = windingMismatchCount(m)
            XCTAssertEqual(s.mismatch, 0, "\(name): \(s.mismatch)/\(s.tris)")
        }
    }
}
