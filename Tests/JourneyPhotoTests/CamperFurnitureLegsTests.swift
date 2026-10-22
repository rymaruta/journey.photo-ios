import XCTest
@testable import JourneyPhoto

/// 脚のある家具の組み立て（2026-10-22 owner「椅子とかは家具によって足が壊れてたりする」）
final class CamperFurnitureLegsTests: XCTestCase {

    private typealias K = CamperRoomMeshKit
    private let wood = CamperMaterial.room(.wood(.oak))

    /// 座面 17・脚 4 本の椅子（`gap` だけ脚が短い・`spread` だけ脚が外へ・`thin` の太さ）
    private func stool(gap: Double = 0, spread: Double = 0, thin: Double = 1.5, short: Double = 0, extra: [CamperMesh] = []) -> CamperMesh {
        var parts = [K.block(CV3(16, 1.2, 16), at: CV3(0, 15.8, 0), radius: 0.3, wood)]
        for (k, (x, z)) in [(-6.5, -6.5), (6.5, -6.5), (-6.5, 6.5), (6.5, 6.5)].enumerated() {
            let s = 1 + spread / 6.5
            parts.append(K.block(CV3(thin, 15.8 - gap - (k == 0 ? short : 0), thin), at: CV3(x * s, 0, z * s), radius: min(0.3, thin * 0.2), wood))
        }
        return K.merge(parts + extra)
    }

    /// 見張りそのもの: 組み立ての崩れを 1 つずつ見分ける（直しを戻すと落ちることの裏付け）
    func testLegCheckerFindsEachKindOfBreak() {
        XCTAssertEqual(CamperRoomLegs.problems(stool()), [], "まともな椅子を壊れと言う")
        XCTAssertTrue(CamperRoomLegs.problems(stool(gap: 2)).contains { $0.hasPrefix("脚の上にすき間") }, "脚の上が座に届かない（前の机）")
        XCTAssertTrue(CamperRoomLegs.problems(stool(gap: 2)).contains { $0.hasPrefix("浮いた部品") }, "座が浮く")
        XCTAssertTrue(CamperRoomLegs.problems(stool(spread: 4)).contains { $0.hasPrefix("脚の上に何も無い") || $0.hasPrefix("脚が座・天板の外へ") },
                      "脚が座の外（前の丸座の椅子）")
        XCTAssertTrue(CamperRoomLegs.problems(stool(spread: 1.6)).contains { $0.hasPrefix("脚が座・天板の外へ") }, "脚が座の縁から外へ出る")
        XCTAssertTrue(CamperRoomLegs.problems(stool(thin: 0.3)).contains { $0.hasPrefix("細すぎる脚") }, "細すぎて消える脚")
        XCTAssertTrue(CamperRoomLegs.problems(stool(short: 1)).contains { $0.hasPrefix("脚の上にすき間") }, "1 本だけ短い脚")
        // 1 本だけ長くて座を突き抜ける
        let poke = stool(extra: [K.block(CV3(1.5, 19, 1.5), at: CV3(0, 0, 0), radius: 0.3, wood)])
        XCTAssertTrue(CamperRoomLegs.problems(poke).contains { $0.hasPrefix("脚が突き抜けて上に出る") }, "座を突き抜ける脚")
        // 床から浮いた飾り（前のそり脚の脚は桟の無い所に立っていた）
        let loose = stool(extra: [K.block(CV3(1, 1, 1), at: CV3(0, 5, 0), radius: 0.2, wood)])
        XCTAssertTrue(CamperRoomLegs.problems(loose).contains { $0.hasPrefix("浮いた部品") }, "宙に浮いた部品")
        // 部品の分け方: 同じ位置の点でつながった三角形が 1 つの部品（座 1 と脚 4）
        XCTAssertEqual(CamperRoomLegs.parts(stool()).count, 5)
        XCTAssertEqual(CamperRoomLegs.parts(stool()).filter(\.isLeg).count, 4)
    }

    /// まだ作り直していない家具（2026-10-22 に始めた待ちの一覧。1 つ直すごとに外し、いまは空。
    /// 新しく足した床の家具も、ここに入れずに組み立ての崩れが無いこと）
    static let pending: [String: String] = [:]

    /// 壁に留める床の家具（脚で立たない作り）
    static let wallHung: Set<String> = ["table.fold_down"]

    /// 床の家具の組み立て（2026-10-22 owner「椅子とかは家具によって足が壊れてたりする」）: 床から浮いた部品が無く、
    /// 脚（床に着いた細長い部品）は上端が座・天板・框に届き、座・天板の外へはみ出さず、同じ物を支える脚の長さがそろい、細すぎない
    func testFloorFurnitureStandsTogether() throws {
        let variety = Set(CamperRoomVariety.pieces.map(\.furniture.id))
        let targets = CamperRoomCatalog.all.filter { f in
            guard f.placement == .floor, f.category != .roomRug, !Self.wallHung.contains(f.id) else { return false }
            return Self.pending[variety.contains(f.id) ? "\(f.category.rawValue).x" : f.id] == nil
        }
        // 1000 点を超えるので手分けして見る（Mac run 676: 1 本ずつでは試験の 1 分の枠を超えて止められた）
        var results = [String?](repeating: nil, count: targets.count)
        let gate = NSLock()
        DispatchQueue.concurrentPerform(iterations: targets.count) { k in
            let f = targets[k]
            let p = CamperRoomFurnitureModels.rawMesh(f.id).map(CamperRoomLegs.problems) ?? ["形が無い"]
            gate.lock()
            if !p.isEmpty { results[k] = "\(f.id)（\(f.nameJa)）: \(p.joined(separator: " / "))" }
            gate.unlock()
        }
        let broken = results.compactMap { $0 }
        XCTAssertEqual(broken, [], broken.prefix(30).joined(separator: "\n"))
    }

    /// 椅子・机・寝台・棚・暖炉・床の灯りは全部、脚の形ごとに作り直した（組み合わせの椅子 220・机 180・寝台 160・棚 200・
    /// 暖炉 80・床の灯り 160 が数に入っている）
    func testRebuiltCategoriesAreAllChecked() {
        XCTAssertTrue(Self.pending.isEmpty, "作り直しの待ちが残っている: \(Self.pending)")
        for (cat, count) in [(CamperRoomCategory.seating, 220), (.table, 180), (.bed, 160), (.storage, 200), (.heater, 80), (.floorLamp, 160)] {
            XCTAssertNil(Self.pending["\(cat.rawValue).x"], "\(cat) がまだ作り直しの待ちにある")
            XCTAssertTrue(CamperRoomVariety.craftedLegs.contains(cat))
            XCTAssertEqual(CamperRoomVariety.pieces.filter { $0.furniture.category == cat }.count, count)
        }
    }

    /// 脚の接写の一覧は、脚のある板の家具全部と、組み合わせの「分類 × 脚の形」を 1 つずつ、重ならずに並べる
    func testLegSheetCoversEveryLegShape() {
        let ids = CamperRoomLegs.sheet.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for f in CamperRoomCatalog.board where f.placement == .floor && f.category != .roomRug && CamperRoomLegs.hasLegs(f) {
            XCTAssertTrue(ids.contains(f.id), f.id)
        }
        var shapes = Set<String>()
        for p in CamperRoomVariety.pieces { if let a = CamperRoomLegs.legAxis(p) { shapes.insert("\(p.furniture.category.rawValue)|\(a)") } }
        let shown = Set(CamperRoomVariety.pieces.filter { ids.contains($0.furniture.id) }.compactMap { p in
            CamperRoomLegs.legAxis(p).map { "\(p.furniture.category.rawValue)|\($0)" }
        })
        XCTAssertEqual(shown, shapes)
        XCTAssertEqual(CamperRoomLegs.views.map(\.name), ["正面", "斜め", "横", "下から"])
        XCTAssertEqual(CamperRoomLegPages.marker(page: 0), "legs-ready 1/\(ids.count)")
    }

    /// 手元で一覧を書き出す（`CAMPER_LEGS_REPORT=<file>` を渡した時だけ）
    func testWriteLegReport() throws {
        guard let path = ProcessInfo.processInfo.environment["CAMPER_LEGS_REPORT"], !path.isEmpty else { return }
        var lines: [String] = []
        if let one = ProcessInfo.processInfo.environment["CAMPER_LEGS_PARTS"], let m = CamperRoomFurnitureModels.rawMesh(one) {
            for p in CamperRoomLegs.parts(m) {
                lines.append(String(format: "%@ lo %.2f %.2f %.2f hi %.2f %.2f %.2f tri %d", p.isLeg ? "LEG" : "   ",
                                    p.lo.x, p.lo.y, p.lo.z, p.hi.x, p.hi.y, p.hi.z, p.triangles))
            }
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        for f in CamperRoomCatalog.all where f.placement == .floor && f.category != .roomRug {
            let m = try XCTUnwrap(CamperRoomFurnitureModels.rawMesh(f.id))
            let p = CamperRoomLegs.problems(m)
            let legged = CamperRoomLegs.hasLegs(f) ? "脚" : "-"
            lines.append("\(f.id)\t\(f.nameJa)\t\(f.lookJa)\t\(legged)\t\(p.isEmpty ? "OK" : p.joined(separator: " / "))")
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// 手元で 4 方向（正面・斜め・横・下から）の絵を書き出す（`CAMPER_LEGS_DUMP=<dir>`・`CAMPER_LEGS_IDS=<id,id>`）。
    /// 2×2 に並べて `<dir>/<id>.rgba`（幅・高さ 4 バイトずつの後に RGBA）
    func testDumpLegViews() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["CAMPER_LEGS_DUMP"], !dir.isEmpty, let ids = env["CAMPER_LEGS_IDS"] else { return }
        let size = 260
        for id in ids.split(separator: ",").map(String.init) {
            guard let mesh = CamperRoomFurnitureModels.mesh(id) else { continue }
            var sheet = [UInt8](repeating: 0, count: size * size * 16)
            for (k, view) in CamperRoomLegs.views.enumerated() {
                var o = CamperRoomRaster.Options()
                o.width = size
                o.height = size
                o.background = 0x202020
                o.yaw = view.yaw
                o.pitch = view.pitch
                let b = CamperRoomRaster.render(mesh, o)
                let ox = (k % 2) * size, oy = (k / 2) * size
                for y in 0..<size {
                    let src = y * size * 4, dst = ((oy + y) * size * 2 + ox) * 4
                    sheet.replaceSubrange(dst..<(dst + size * 4), with: b.rgba[src..<(src + size * 4)])
                }
            }
            var data = Data()
            withUnsafeBytes(of: UInt32(size * 2).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(size * 2).littleEndian) { data.append(contentsOf: $0) }
            data.append(contentsOf: sheet)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(id).rgba"))
        }
    }
}
