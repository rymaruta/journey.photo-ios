import XCTest
@testable import JourneyPhoto

/// 旅のトランクの部品の欠け・崩れ（#305・2026-10-18）: 立体の向き・吊るす部品の重なり・立体で吊るす物・
/// トランクに付けた錠前と角金具の形
final class TrunkPartsFitTests: XCTestCase {

    // MARK: #1・#5 立体の向き（板 TrunkSpin の `rotateX(rx) rotateY(ry)`）

    private let front = SpinMotion.Vector(x: 0, y: 0, z: 1)
    private let back = SpinMotion.Vector(x: 0, y: 0, z: -1)
    private let top = SpinMotion.Vector(x: 0, y: 1, z: 0)
    private let bottom = SpinMotion.Vector(x: 0, y: -1, z: 0)
    private let right = SpinMotion.Vector(x: 1, y: 0, z: 0)
    private let left = SpinMotion.Vector(x: -1, y: 0, z: 0)

    private func view(_ id: String) -> TrunkFaces.View {
        TrunkFaces.views.first { $0.id == id }!
    }

    private func visible(_ normal: SpinMotion.Vector, _ v: TrunkFaces.View) -> Bool {
        SpinMotion.faceVisible(normal, yaw: v.yaw, pitch: v.pitch)
    }

    /// 「上と背面」で上の面（持ち手）と背面が見え、底は見えない（前は底と背面が見えた）
    func testTopAndBackShowsTheTop() {
        let v = view("topBack")
        XCTAssertTrue(visible(top, v), "「上と背面」で上の面が見えない")
        XCTAssertTrue(visible(back, v), "「上と背面」で背面が見えない")
        XCTAssertFalse(visible(bottom, v), "「上と背面」で底が見える")
        XCTAssertFalse(visible(front, v))
    }

    /// 「側面」で右の側面と、上の面が少し見える（板の rotateX(-10deg)・前は上の面が真横を向いて消えた）
    func testSideShowsALittleOfTheTop() {
        let v = view("side")
        XCTAssertTrue(visible(right, v), "「側面」で右の側面が見えない")
        XCTAssertTrue(visible(top, v), "「側面」で上の面が見えない")
        XCTAssertFalse(visible(left, v))
        XCTAssertFalse(visible(bottom, v))
    }

    func testFrontAndBottomViews() {
        XCTAssertTrue(visible(front, view("front")))
        XCTAssertTrue(visible(top, view("front")), "正面で上の面が少し見えない（板 rotateX(-8deg)）")
        XCTAssertTrue(visible(bottom, view("bottom")), "「底」で底が見えない")
        XCTAssertFalse(visible(top, view("bottom")))
    }

    /// どれだけ横に回しても、縦に傾けると上の面が手前に来る（傾きが裏返らない）
    func testPitchNeverFlipsWithYaw() {
        for deg in stride(from: -360.0, through: 360, by: 15) {
            let yaw = deg * .pi / 180
            XCTAssertTrue(SpinMotion.faceVisible(top, yaw: yaw, pitch: 0.5), "横 \(deg)° で上へ傾けても上の面が見えない")
            XCTAssertTrue(SpinMotion.faceVisible(bottom, yaw: yaw, pitch: -0.5), "横 \(deg)° で下へ傾けても底が見えない")
        }
    }

    /// SceneKit に渡す四元数が、面の向きの計算（`rotate`）と同じ回し方であること
    func testQuaternionMatchesRotate() {
        for (yaw, pitch) in [(0.0, 0.0), (-2.79, 0.84), (-1.57, 0.17), (0.6, -1.2), (3.1, 1.4)] {
            let q = SpinMotion.boxOrientation(yaw: yaw, pitch: pitch)
            XCTAssertEqual(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w, 1, accuracy: 1e-9)
            for v in [front, top, right, SpinMotion.Vector(x: 0.3, y: -0.5, z: 0.8)] {
                // v' = q v q*（ハミルトンの積）
                let (qx, qy, qz, qw) = (q.x, q.y, q.z, q.w)
                let tx = 2 * (qy * v.z - qz * v.y), ty = 2 * (qz * v.x - qx * v.z), tz = 2 * (qx * v.y - qy * v.x)
                let rx = v.x + qw * tx + (qy * tz - qz * ty)
                let ry = v.y + qw * ty + (qz * tx - qx * tz)
                let rz = v.z + qw * tz + (qx * ty - qy * tx)
                let r = SpinMotion.rotate(v, yaw: yaw, pitch: pitch)
                XCTAssertEqual(r.x, rx, accuracy: 1e-9)
                XCTAssertEqual(r.y, ry, accuracy: 1e-9)
                XCTAssertEqual(r.z, rz, accuracy: 1e-9)
            }
        }
    }

    // MARK: #2・#3 吊るす部品とラベルのタグが重ならない

    private func parts(_ kind: TrunkPartKind) -> [TrunkPart?] {
        [nil] + TrunkPartCatalog.parts(of: kind).map { Optional($0) }
    }

    /// 部品のタグ・チャーム・鍵（それぞれ無し＋12点）× ラベルのタグ 0〜3 枚の全部で、描いた中身が交わらない。
    /// 絵の枠（360）の中に収まり、錠前（どの型でも）にもかからない
    func testHangingNeverOverlaps() {
        let tagFrames = TrunkLooks.tagSlots.map { TrunkLooks.tagFrame(x: $0.x, rot: $0.rot) }
        // 1点ずつの外接の四角を先に作る（2,197 通り × 4 で毎回作らない）
        func frame(_ part: TrunkPart?) -> TrunkRect? {
            guard let part else { return nil }
            let e: TrunkEquipped
            switch part.kind {
            case .tag: e = TrunkEquipped(tag: part.id)
            case .charm: e = TrunkEquipped(charm: part.id)
            default: e = TrunkEquipped(key: part.id)
            }
            return TrunkFittings(e).placements.first?.frame
        }
        let tags = parts(.tag).map(frame), charms = parts(.charm).map(frame), keys = parts(.key).map(frame)
        let lockTop = TrunkModel.allCases.map { m -> Double in
            let look = TrunkLooks.look(m, stage: 0)
            let mount = TrunkFittings(TrunkEquipped(lock: "lock.9")).lockMount(look)
            return TrunkLooks.bodyTop + min(TrunkLooks.lockTop(look), mount.map { $0.y + 14 * $0.side / 96 } ?? .infinity)
        }.min() ?? 0
        var checked = 0
        for t in tags { for c in charms { for k in keys {
            let hung = [t, c, k].compactMap { $0 }
            for f in hung {
                XCTAssertGreaterThanOrEqual(f.x, 0, "吊るす部品が絵の左からはみ出す")
                XCTAssertLessThanOrEqual(f.maxX, TrunkLooks.canvasWidth, "吊るす部品が絵の右からはみ出す")
                XCTAssertLessThan(f.maxY, lockTop, "吊るす部品が錠前にかかる")
            }
            for i in hung.indices { for j in hung.indices where j > i {
                XCTAssertFalse(hung[i].intersects(hung[j]), "吊るす部品どうしが重なる: \(hung[i]) と \(hung[j])")
            } }
            for n in 0...TrunkLooks.tagSlots.count {
                for f in hung { for g in tagFrames.prefix(n) {
                    XCTAssertFalse(f.intersects(g), "吊るす部品がラベルのタグ（\(n) 枚）に重なる: \(f) と \(g)")
                } }
                checked += 1
            }
        } } }
        XCTAssertEqual(checked, 13 * 13 * 13 * 4)
        // ラベルのタグどうしは板どおり重ねて吊るす（板 Trunk の3枚）。それは見ない
    }

    /// 見本（#305 の画面写真の組み合わせ: 一等船室のタグ・鳥居のチャーム・赤い札の鍵）を名指しで
    func testSampleHangingIsApart() {
        let hung = TrunkFittings(TrunkSample.equipped).placements.filter { !$0.onBody }
        XCTAssertEqual(hung.map(\.part.id), ["tag.4", "charm.1", "key.4"])
        let frames = hung.map(\.frame)
        XCTAssertFalse(frames[0].intersects(frames[1]), "tag.4 と charm.1 が重なる")
        XCTAssertFalse(frames[2].intersects(TrunkLooks.tagFrame(x: TrunkLooks.tagSlots[0].x, rot: TrunkLooks.tagSlots[0].rot)),
                       "key.4 がラベルのタグに重なる")
    }

    /// 描いた中身の外接の四角は、96 の枠より小さく（枠ごとでは置き場が足りない）、置き方を畳んでいる
    func testContentBoundsFoldTransforms() {
        let key = TrunkPartCatalog.parts(of: .key)[0]
        let b = TrunkPartDrawing.contentBounds(TrunkPartDrawing.ops(key))!
        XCTAssertEqual(b.x, 4, accuracy: 0.01, "鍵の札の左（4）")
        XCTAssertLessThanOrEqual(b.maxX, 75)
        let r = TrunkRect(x: 0, y: 0, w: 10, h: 20).rotated(90, aroundX: 0, y: 0)
        XCTAssertEqual(r.x, -20, accuracy: 1e-9)
        XCTAssertEqual(r.w, 20, accuracy: 1e-9)
        XCTAssertEqual(r.h, 10, accuracy: 1e-9)
        XCTAssertFalse(TrunkRect(x: 0, y: 0, w: 10, h: 10).intersects(TrunkRect(x: 10, y: 0, w: 5, h: 5)), "触れるだけは重ならない")
    }

    // MARK: #4 立体で吊るす物

    /// 立体の上の面: 吊るす物ごとに、持ち手の付け根の間から正面の辺（厚み 86）の吊るす点へ紐を渡す
    func testTopFaceCordsReachTheFrontEdge() {
        let fittings = TrunkFittings(TrunkSample.equipped)
        let labels = TrunkLooks.tags(stuck: TrunkSample.stuck, posts: 100)
        XCTAssertEqual(labels.count, 3)
        let cords = TrunkFaces.topCords(tags: labels, fittings: fittings)
        XCTAssertEqual(cords.count, labels.count + 3, "ラベルのタグ3枚と部品3つ")
        let lo = TrunkFaces.handleClipCenters.min()!, hi = TrunkFaces.handleClipCenters.max()!
        for c in cords {
            XCTAssertEqual(c.toY, TrunkFaces.depth, "紐が正面の辺まで届かない")
            XCTAssertTrue((lo...hi).contains(c.fromX), "紐の付け根が持ち手の外")
            XCTAssertGreaterThan(c.width, 0)
        }
        let hung = fittings.placements.filter { !$0.onBody }
        XCTAssertEqual(Set(cords.suffix(3).map(\.toX)), Set(hung.map(\.hangX)), "紐の先が吊るす点の真上に無い")
        XCTAssertTrue(TrunkFaces.topCords(tags: [], fittings: .none).isEmpty)
    }

    /// 立体の正面: 部品は胴の上の縁から吊るす点まで紐でつなぐ。ラベルのタグは紐の上の端が縁（0）に来る
    func testFrontCordsStartAtTheTopEdge() {
        let fittings = TrunkFittings(TrunkSample.equipped)
        let cords = TrunkFaces.frontCords(fittings: fittings)
        XCTAssertEqual(cords.count, 3)
        for c in cords {
            XCTAssertEqual(c.fromY, 0)
            XCTAssertGreaterThan(c.toY, 0)
            XCTAssertEqual(c.fromX, c.toX)
        }
        XCTAssertEqual(TrunkLooks.tagStringTop - TrunkFaces.frontHangLift, 0, "ラベルのタグの紐が正面の上の縁から始まらない")
    }

    // MARK: #6 トランクに付けた錠前と角金具

    /// 付けた錠前は部品1点の絵を縮めて、型の錠前の真ん中に置く（南京錠・ダイヤル・双子でも）
    func testLockMountCentersOnTheModelLock() {
        for model in TrunkModel.allCases {
            let look = TrunkLooks.look(model, stage: 0)
            for part in TrunkPartCatalog.parts(of: .lock) {
                guard case .lock(let l) = part.look,
                      let m = TrunkFittings(TrunkEquipped(lock: part.id)).lockMount(look) else {
                    return XCTFail("\(part.id) を付けても置き場が無い")
                }
                let k = m.side / TrunkPartDrawing.size
                XCTAssertGreaterThanOrEqual(k, TrunkFittings.lockMountScale.lowerBound - 1e-9, "\(part.id) の縮みが小さすぎる: \(k)")
                XCTAssertLessThanOrEqual(k, TrunkFittings.lockMountScale.upperBound + 1e-9, "\(part.id) の縮みが大きすぎる: \(k)")
                let body = TrunkPartDrawing.lockBody(l.shape).box
                XCTAssertEqual(m.y + body.midY * k, TrunkLooks.lockTop(look) + look.lock.height / 2, accuracy: 1e-9,
                               "\(model) \(part.id) の胴が型の錠前の高さの真ん中に無い")
                let all = TrunkPartDrawing.contentBounds(TrunkPartDrawing.lock(l))!
                XCTAssertEqual(m.x + all.midX * k, 180, accuracy: 1e-9, "\(part.id) が真ん中に無い")
                // 胴の中に収まる（左右・上）
                XCTAssertGreaterThan(m.x + all.x * k, 0)
                XCTAssertGreaterThan(m.y + all.y * k, 0)
            }
        }
        XCTAssertNil(TrunkFittings.none.lockMount(TrunkLooks.look(.leather, stage: 0)))
    }

    /// 角金具は 96 の枠ではそのまま（前と同じ手順）、トランクの角（30〜46）では同じ形を縮め、穴と鋲を潰さない
    func testMountedCornerKeepsHolesAndRivets() {
        let pierce = TrunkPartCatalog.parts(of: .corner).first { if case .corner(let c) = $0.look { return c.pierce } else { return false } }!
        guard case .corner(let c) = pierce.look else { return XCTFail() }
        XCTAssertEqual(TrunkPartDrawing.corner(c), TrunkPartDrawing.corner(c, box: TrunkRect(x: 12, y: 12, w: 72, h: 72)))
        let sizes = TrunkModel.allCases.map { TrunkLooks.look($0, stage: 0).corners.size }
        for size in sizes {
            let ops = TrunkPartDrawing.corner(c, box: TrunkRect(x: 0, y: 0, w: size, h: size))
            guard case .group(let inner, _, _) = ops[0] else { return XCTFail("角金具の形の組が無い") }
            // 透かしの5つの穴（黒い丸）
            let holes = inner.compactMap { op -> TrunkRect? in
                guard case let .fill(seg, .solid(color), _, _) = op, color == TrunkRGBA(0x000000) else { return nil }
                return TrunkShapes.bounds(seg)
            }
            XCTAssertEqual(holes.count, 5, "角 \(size) で透かしが消える")
            for h in holes { XCTAssertGreaterThanOrEqual(h.w, 2 * TrunkPartDrawing.mountedMinHole - 1e-9, "角 \(size) で穴が潰れる") }
            // 外の形は枠に収まる
            let shape = TrunkShapes.bounds(TrunkPartDrawing.cornerShape(TrunkRect(x: 0, y: 0, w: size, h: size)))!
            XCTAssertEqual(shape.w, size, accuracy: 1e-9)
        }
        let riveted = TrunkPartCatalog.parts(of: .corner).compactMap { p -> TrunkPartLook.Corner? in
            if case .corner(let c) = p.look, c.rivets { return c }
            return nil
        }
        XCTAssertFalse(riveted.isEmpty)
        for c in riveted {
            for size in sizes {
                let box = TrunkRect(x: 0, y: 0, w: size, h: size)
                let rivets = TrunkPartDrawing.corner(c, box: box).dropFirst().compactMap { op -> TrunkRect? in
                    guard case let .fill(seg, _, _, _) = op else { return nil }
                    return TrunkShapes.bounds(seg)
                }
                XCTAssertEqual(rivets.count, 3, "角 \(size) で鋲が欠ける")
                let arm = size * 0.34
                for r in rivets {
                    XCTAssertGreaterThanOrEqual(r.w, 2 * TrunkPartDrawing.mountedMinRivet - 1e-9, "角 \(size) で鋲が潰れる")
                    // L の腕（太さ 34%）からはみ出さない
                    XCTAssertTrue(r.maxY <= arm + 1e-9 || r.maxX <= arm + 1e-9, "角 \(size) で鋲が腕からはみ出す: \(r)")
                    XCTAssertGreaterThanOrEqual(r.x, 0)
                    XCTAssertGreaterThanOrEqual(r.y, 0)
                }
            }
        }
        XCTAssertNotNil(TrunkFittings(TrunkSample.equipped).cornerLook)
        XCTAssertNil(TrunkFittings.none.cornerLook)
    }
}
