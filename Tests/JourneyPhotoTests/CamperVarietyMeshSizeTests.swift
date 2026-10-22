import XCTest
@testable import JourneyPhoto

/// 組み合わせの家具の網の大きさ（2026-10-22 確かめ役「memo を捨てないので図鑑を最後まで見ると 1〜2GB 近く」）
final class CamperVarietyMeshSizeTests: XCTestCase {

    static let bytesPerTriangle = CamperRoomVariety.bytesPerTriangle

    /// 分類ごとの 1 点の三角形の上限（2026-10-22 の実測の最大に 2 割ほどの余裕）
    static let maxTriangles: [CamperRoomCategory: Int] = [
        .bed: 13_000, .seating: 7_500, .table: 6_500, .storage: 7_500, .heater: 4_000, .floorLamp: 3_000,
        .roomRug: 2_300, .wallShelf: 2_200, .photoFrame: 2_500, .poster: 1_400, .wallLamp: 900, .clock: 1_600,
        .stringCeiling: 3_000, .mobile: 1_900, .plantHanger: 1_100, .roofHatch: 900,
    ]

    /// 網の控えは上限を超えない（図鑑を最後まで見ても 48MB まで）。古い物から捨て、捨てた物は作り直せる
    func testMeshMemoStaysBounded() throws {
        CamperRoomVariety.removeAllMeshes()
        XCTAssertEqual(CamperRoomVariety.memoCost, 0)
        let ids = CamperRoomVariety.pieces.map(\.furniture.id)
        for id in ids { _ = CamperRoomVariety.mesh(id) }
        XCTAssertGreaterThan(CamperRoomVariety.memoCost, CamperRoomVariety.memoCostLimit / 2, "控えが効いていない")
        XCTAssertLessThanOrEqual(CamperRoomVariety.memoCost, CamperRoomVariety.memoCostLimit)
        // 最初の家具はもう捨てられているが、同じ形に作り直せる
        let first = try XCTUnwrap(CamperRoomVariety.mesh(ids[0]))
        XCTAssertEqual(first.triangleCount, CamperRoomVariety.build(CamperRoomVariety.pieces[0]).triangleCount)
        CamperRoomVariety.removeAllMeshes()
        XCTAssertEqual(CamperRoomVariety.memoCost, 0)
    }

    /// 分類ごとの三角形の数（合計・最大）を数える。`CAMPER_MESH_SIZES=1` の時は表を出す
    func testVarietyMeshSizes() {
        var total: [CamperRoomCategory: Int] = [:], most: [CamperRoomCategory: (Int, String)] = [:]
        let pieces = CamperRoomVariety.pieces
        var counts = [Int](repeating: 0, count: pieces.count)
        let gate = NSLock()
        DispatchQueue.concurrentPerform(iterations: pieces.count) { k in
            let n = CamperRoomVariety.build(pieces[k]).triangleCount
            gate.lock()
            counts[k] = n
            gate.unlock()
        }
        for (k, p) in pieces.enumerated() {
            let c = p.furniture.category
            total[c, default: 0] += counts[k]
            if counts[k] > (most[c]?.0 ?? 0) { most[c] = (counts[k], p.furniture.id) }
        }
        for (c, m) in most {
            XCTAssertLessThanOrEqual(m.0, Self.maxTriangles[c] ?? 3_000, "\(c) の \(m.1) の三角形が多すぎる")
        }
        // 全部を控えたとしても 1GB を超えない大きさ（控えは上限つきなので、実際は 48MB まで）
        XCTAssertLessThan(total.values.reduce(0, +) * Self.bytesPerTriangle, 1_000_000_000)
        if ProcessInfo.processInfo.environment["CAMPER_MESH_SIZES"] != nil {
            // 図鑑の絵の描く時間（脚を作り直した分類から 12 点ずつ・網を作って 96px で描く）
            for c in [CamperRoomCategory.bed, .seating, .table, .storage, .heater, .floorLamp] {
                let sample = pieces.filter { $0.furniture.category == c }.prefix(12)
                let t0 = Date()
                for p in sample {
                    var o = CamperRoomRaster.Options()
                    o.width = 96
                    o.height = 96
                    _ = CamperRoomRaster.render(CamperRoomVariety.build(p), o)
                }
                print("TIME \(c.rawValue) 1 点 \(Int(Date().timeIntervalSince(t0) / Double(sample.count) * 1000)) ms")
            }
            for c in CamperRoomCategory.allCases where total[c] != nil {
                print("SIZE \(c.rawValue) 合計 \(total[c]!) 最大 \(most[c]!.0) \(most[c]!.1)")
            }
            let all = total.values.reduce(0, +)
            print("SIZE 全部 \(all) 三角形 ≈ \(all * Self.bytesPerTriangle / 1_000_000) MB")
        }
    }
}

/// 組み合わせの床の灯り・暖炉の光の位置（2026-10-22 確かめ役「高さの 0.72 に固定で、新しい電球・火の窓とずれる」）
final class CamperVarietyLampTests: XCTestCase {

    /// 光は電球（暖炉は火の窓）の真ん中から 1.5 以内（1 単位 = 2.5 cm）
    func testLightSitsAtTheBulbOrTheFire() throws {
        var far: [String] = []
        for p in CamperRoomVariety.pieces where p.furniture.category == .floorLamp || p.furniture.category == .heater {
            let light = try XCTUnwrap(CamperRoomVariety.lamp(p.furniture.id), p.furniture.id).position
            let mesh = CamperRoomVariety.build(p)
            let glow: CamperMaterial = p.furniture.category == .heater ? .room(.fire) : .room(.bulb)
            let g = try XCTUnwrap(mesh.groups.first { $0.material == glow }, p.furniture.id)
            let pts = g.indices.map { mesh.positions[Int($0)] }
            let lo = CV3(pts.map(\.x).min()!, pts.map(\.y).min()!, pts.map(\.z).min()!)
            let hi = CV3(pts.map(\.x).max()!, pts.map(\.y).max()!, pts.map(\.z).max()!)
            let center = (lo + hi) * 0.5
            let d = (light - center).length
            if d > 1.5 { far.append("\(p.furniture.id) 光 \(light) 電球・火 \(center) 離れ \(String(format: "%.1f", d))") }
        }
        XCTAssertEqual(far, [], far.prefix(10).joined(separator: "\n"))
    }
}

