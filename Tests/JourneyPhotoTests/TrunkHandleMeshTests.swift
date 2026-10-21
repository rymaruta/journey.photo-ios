import XCTest
@testable import JourneyPhoto

/// 立体の持ち手（2026-10-19）。穴の押し出しが蓋の粒を乗せ、縫い目を内側へ伸ばし、付け根を単色の塊にしていた
final class TrunkHandleMeshTests: XCTestCase {

    private let depth = 0.24 * 0.25 * TrunkLooks.bodyWidth

    /// 革は帯の上だけにある（穴の中にトゲが出ない・外形は 2D の持ち手と同じ 100×36）
    func testLeatherStaysOnTheStrap() {
        let mesh = TrunkHandleMesh.make(depth: depth, stitched: true)
        let line = TrunkHandleMesh.centerline()
        let leather = mesh.caps + mesh.walls
        XCTAssertFalse(leather.isEmpty)
        XCTAssertLessThan(leather.count, 2000, "三角が割れて増えている")
        for v in leather {
            XCTAssertGreaterThanOrEqual(v.y, -0.01)
            XCTAssertLessThanOrEqual(v.y, 36.2)
            XCTAssertGreaterThanOrEqual(v.x, -50.2)
            XCTAssertLessThanOrEqual(v.x, 50.2)
            XCTAssertLessThanOrEqual(abs(v.z), depth / 2 + 0.05)
            let along = outwardComponent(v.x, v.y, line: line)
            XCTAssertEqual(abs(along), 5, accuracy: 0.35, "革が帯（太さ 10）から外れている (\(v.x), \(v.y))")
        }
        XCTAssertEqual(leather.map(\.y).max() ?? 0, 36, accuracy: 0.05, "上が 2D の持ち手より低い")
        XCTAssertEqual(leather.map(\.y).min() ?? 1, 0, accuracy: 0.05, "足が胴から浮く")
        assertSolid(mesh.caps, mesh.capIndices, "前後")
        assertSolid(mesh.walls, mesh.wallIndices, "壁")
    }

    /// 前後の絵は持ち手自身の枠（0〜1）に貼る。蓋（幅 360）の一部を伸ばさない
    func testCapPictureFillsTheHandleNotTheLid() {
        let mesh = TrunkHandleMesh.make(depth: depth, stitched: true)
        let us = mesh.caps.map(\.u), vs = mesh.caps.map(\.v)
        XCTAssertEqual(us.min() ?? 1, 0, accuracy: 0.02)
        XCTAssertEqual(us.max() ?? 0, 1, accuracy: 0.02)
        XCTAssertEqual(vs.min() ?? 1, 0, accuracy: 0.02)
        XCTAssertEqual(vs.max() ?? 0, 1, accuracy: 0.02)
        for v in mesh.caps {
            XCTAssertGreaterThanOrEqual(v.u, -0.001)
            XCTAssertLessThanOrEqual(v.u, 1.001)
            XCTAssertGreaterThanOrEqual(v.v, -0.001)
            XCTAssertLessThanOrEqual(v.v, 1.001)
        }
    }

    /// 縫い目は外側の面にある。穴の内側の縁には乗らない。アルミと漆は縫わない
    func testStitchSitsOnTheOutside() {
        let mesh = TrunkHandleMesh.make(depth: depth, stitched: true)
        let line = TrunkHandleMesh.centerline()
        XCTAssertFalse(mesh.stitch.isEmpty)
        for v in mesh.stitch {
            let along = outwardComponent(v.x, v.y, line: line)
            XCTAssertEqual(along, 5.8, accuracy: 0.45, "縫い目が内側にある (\(v.x), \(v.y))")
            XCTAssertLessThanOrEqual(abs(v.z), 0.55, "縫い目が前後に広がっている")
        }
        assertSolid(mesh.stitch, mesh.stitchIndices, "縫い目")
        let plain = TrunkHandleMesh.make(depth: depth, stitched: false)
        XCTAssertTrue(plain.stitch.isEmpty)
        XCTAssertTrue(plain.stitchIndices.isEmpty)
        XCTAssertFalse(TrunkFaces.handleStitched(.aluminum))
        XCTAssertFalse(TrunkFaces.handleStitched(.urushi))
        XCTAssertTrue(TrunkFaces.handleStitched(.leather))
    }

    /// 付け根の金具は 6 面とも絵が 0〜1 で 1 回ずつ貼られる（面取りで潰さない）
    func testClipShowsTheWholePictureOnEveryFace() {
        let clip = TrunkHandleMesh.clip(depth: depth + 4)
        XCTAssertEqual(clip.vertices.count, 24, "面が 6 枚でない")
        XCTAssertEqual(clip.indices.count, 36)
        var face = 0
        while face < clip.vertices.count {
            let uvs = clip.vertices[face..<(face + 4)].map { uvKey($0.u, $0.v) }.sorted()
            XCTAssertEqual(uvs, ["0,0", "0,1", "1,0", "1,1"], "面 \(face / 4) の絵が潰れている")
            face += 4
        }
        let xs = clip.vertices.map(\.x), ys = clip.vertices.map(\.y), zs = clip.vertices.map(\.z)
        XCTAssertEqual(xs.max()! - xs.min()!, 20, accuracy: 0.01)
        XCTAssertEqual(ys.max()! - ys.min()!, 14, accuracy: 0.01)
        XCTAssertEqual(zs.max()! - zs.min()!, depth + 4, accuracy: 0.01)
        assertSolid(clip.vertices, clip.indices, "金具")
    }

    /// 三角は外を向き、面積がある（裏向きだと持ち手が消える）
    private func assertSolid(_ vertices: [TrunkHandleMesh.Vertex], _ indices: [Int], _ name: String) {
        var i = 0
        var count = 0
        while i + 2 < indices.count {
            let a = vertices[indices[i]], b = vertices[indices[i + 1]], c = vertices[indices[i + 2]]
            let n = cross(a, b, c)
            let area = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
            XCTAssertGreaterThan(area, 0.02, "\(name) に潰れた三角がある")
            let vx = (a.nx + b.nx + c.nx) / 3, vy = (a.ny + b.ny + c.ny) / 3, vz = (a.nz + b.nz + c.nz) / 3
            XCTAssertGreaterThan(n.x * vx + n.y * vy + n.z * vz, 0, "\(name) の面が裏を向いている")
            i += 3
            count += 1
        }
        XCTAssertGreaterThan(count, 0)
    }

    /// 中心線から外向きに何 pt 離れているか（内側は負）
    private func outwardComponent(_ x: Double, _ y: Double, line: [TrunkHandleMesh.LinePoint]) -> Double {
        var best = line[0]
        var bestD = Double.greatestFiniteMagnitude
        for p in line {
            let d = hypot(x - p.x, y - p.y)
            if d < bestD { bestD = d; best = p }
        }
        return (x - best.x) * best.ox + (y - best.y) * best.oy
    }

    private func cross(_ a: TrunkHandleMesh.Vertex, _ b: TrunkHandleMesh.Vertex,
                       _ c: TrunkHandleMesh.Vertex) -> (x: Double, y: Double, z: Double) {
        let ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z
        let vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z
        return (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
    }

    private func uvKey(_ u: Double, _ v: Double) -> String {
        "\(Int((u * 1000).rounded() / 1000)),\(Int((v * 1000).rounded() / 1000))"
    }
}
