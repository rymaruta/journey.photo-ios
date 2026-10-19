import XCTest
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif
@testable import JourneyPhoto

/// とおまわり号の中（2026-10-19）: 家具図鑑・置く決まり・置く操作と元に戻す・保存・カメラと指の位置・形と素材・場面
final class CamperRoomTests: XCTestCase {

    private let camper = CamperRoomLayout.make(.car, stage: .camper)

    // MARK: 図鑑

    /// 板の家具図鑑どおり 16 分類・64 個（1 分類 4 つ・床 7・壁 5・天井 4）、id は重ならず「分類.部品」。最初から 17 個、要サーバー 10 個
    func testCatalogMatchesTheBoard() {
        let all = CamperRoomCatalog.all
        XCTAssertEqual(all.count, 64)
        XCTAssertEqual(Set(all.map(\.id)).count, 64)
        XCTAssertEqual(CamperRoomCategory.allCases.count, 16)
        for c in CamperRoomCategory.allCases { XCTAssertEqual(CamperRoomCatalog.items(c).count, 4, c.rawValue) }
        XCTAssertEqual(CamperRoomCatalog.items(.floor).count, 28)
        XCTAssertEqual(CamperRoomCatalog.items(.wall).count, 20)
        XCTAssertEqual(CamperRoomCatalog.items(.ceiling).count, 16)
        XCTAssertEqual(all.filter { $0.unlock.isStarter }.count, 17)
        let server = all.filter { if case .base(.server) = $0.unlock { return true } else { return false } }
        XCTAssertEqual(Set(server.map(\.id)), ["bed.daybed", "seating.bench_storage", "heater.tile_hearth", "floor_lamp.paper_column",
                                               "wall_shelf.floating_corner", "poster.postcard_grid", "poster.tapestry", "string_ceiling.bunting",
                                               "plant_hanger.hanging_basket", "plant_hanger.glass_terrarium"])
        // 珍しさ（板: いつもの 17・ときどき 20・めずらしい 19・とても珍しい 8）
        XCTAssertEqual(all.filter { $0.rarity == .common }.count, 17)
        XCTAssertEqual(all.filter { $0.rarity == .occasional }.count, 20)
        XCTAssertEqual(all.filter { $0.rarity == .rare }.count, 19)
        XCTAssertEqual(all.filter { $0.rarity == .veryRare }.count, 8)
        for f in all {
            XCTAssertFalse(f.nameJa.isEmpty, f.id)
            XCTAssertFalse(f.nameEn.isEmpty, f.id)
            XCTAssertNotEqual(f.nameJa, f.nameEn, f.id)
        }
    }

    /// 最初から持っている家具は全部、形を作り込んである（初めて入った部屋に「近日」が並ばない）。形のある家具だけが届き、
    /// 形の無い家具は「近日」で数（分母）から外す
    func testBuiltFurnitureHasModelsAndOnlyBuiltCount() {
        for f in CamperRoomCatalog.all {
            XCTAssertEqual(CamperRoomFurnitureModels.mesh(f.id) != nil, f.built, f.id)
            if f.unlock.isStarter { XCTAssertTrue(f.built, f.id) }
        }
        let owned = CamperRoomCatalog.owned(CamperStats(), CamperRoomStats())
        XCTAssertEqual(owned.count, 17)
        let count = CamperRoomCatalog.dexCount(owned)
        XCTAssertEqual(count.have, 17)
        XCTAssertEqual(count.total, CamperRoomCatalog.all.filter { $0.built && $0.unlock.isAvailable }.count)
        XCTAssertEqual(CamperRoomCatalog.soonCount, 64 - count.total)
        XCTAssertGreaterThanOrEqual(count.total, 25)
    }

    /// 入手の条件は端末で数えた値で決まる（写真 40 枚で畳む布団・和室の写真でちゃぶ台・同じ日に 30 枚は数だけ）
    func testUnlocksFromPhotos() {
        var s = CamperStats()
        s.posts = 40
        var r = CamperRoomStats()
        XCTAssertTrue(CamperRoomCatalog.owned(s, r).contains("bed.futon"))
        XCTAssertFalse(CamperRoomCatalog.owned(s, r).contains("table.chabudai"))
        r.topics[.washitsu] = 1
        XCTAssertTrue(CamperRoomCatalog.owned(s, r).contains("table.chabudai"))
        // 要サーバーは条件の数を満たしても届かない
        XCTAssertFalse(CamperRoomCatalog.owned(s, r).contains("bed.daybed"))
    }

    /// 写真に写った物は撮影地・題・タグの言葉で数える（地名の「山」などは外す）・春の写真・同じ日の数
    func testRoomCounting() {
        let photos = [
            Self.photo("a", title: "旅館の和室", date: "2024:04:02 10:00:00"),
            Self.photo("b", title: "朝市の野菜", date: "2024:04:02 11:00:00"),
            Self.photo("c", title: "雪の朝", date: "2024:01:05 07:00:00"),
            Self.photo("d", title: "星空", date: "2024:08:10 23:00:00", published: false),
        ]
        let r = CamperRoomCounting.count(photos)
        XCTAssertEqual(r.count(.washitsu), 1)
        XCTAssertEqual(r.count(.market), 1)
        XCTAssertEqual(r.count(.snow), 1)
        XCTAssertEqual(r.count(.starry), 0, "下書きは数えない")
        XCTAssertEqual(r.springShots, 2)
        XCTAssertEqual(r.sameDayMax, 2)
    }

    static func photo(_ id: String, title: String, date: String, published: Bool = true) -> Photo {
        let json: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg", "title": title, "date": date, "published": published]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Photo.self, from: data)
    }

    // MARK: 置く決まり

    /// 最初の並びは、どの段の部屋でも決まりに合っていて、思った数がそろう
    func testStarterDocumentsAreValid() {
        for (kind, stage, count, width, depth) in [(CamperRoomKind.car, CamperStage.van, 9, 18, 16),
                                                    (.car, .camper, 16, 22, 18), (.trailer, .trailer, 7, 26, 20)] {
            let l = CamperRoomLayout.make(kind, stage: stage)
            XCTAssertEqual(l.width, width, "\(stage)")
            XCTAssertEqual(l.depth, depth, "\(stage)")
            let doc = CamperRoomRules.starterDocument(l)
            XCTAssertEqual(doc.all.count, count, "\(kind) \(stage)")
            for item in doc.all {
                var others = doc
                others.remove(item.u)
                XCTAssertTrue(CamperRoomRules.check(item, in: others, layout: l).ok, "\(kind) \(stage) \(item.k)")
            }
        }
    }

    /// 第1段で集められる家具は、どの段の部屋でも一度に置ける（上限で先に止まらない・床が足りなくならない）
    func testCollectedFurnitureFits() {
        let pieces = CamperRoomCatalog.all.filter { $0.built && $0.unlock.isAvailable }.sorted { a, b in
            let area: (CamperRoomFurniture) -> Int = { $0.placement == .floor && !$0.isRug ? $0.width * $0.depth : 0 }
            return area(a) > area(b)
        }
        for (kind, stage) in [(CamperRoomKind.car, CamperStage.van), (.car, .camper), (.trailer, .trailer)] {
            let layout = CamperRoomLayout.make(kind, stage: stage)
            var doc = CamperRoomDocument(room: kind)
            var missed: [String] = []
            for f in pieces {
                if let item = CamperRoomRules.firstFit(f, uid: doc.nextUid(), in: doc, layout: layout) {
                    doc.upsert(item)
                } else {
                    missed.append(f.id)
                }
            }
            XCTAssertEqual(missed, [], "\(stage)")
        }
    }

    func testFloorRules() {
        var doc = CamperRoomDocument(room: .car)
        doc.upsert(.floor("a", "storage.trunk", x: 0, z: 4))
        // 家具どうしは重ならない
        let overlap = CamperRoomRules.check(.floor("b", "storage.tall_drawers", x: 1, z: 4), in: doc, layout: camper)
        XCTAssertEqual(overlap.reason, .overlap)
        XCTAssertFalse(overlap.blocked.isEmpty)
        // 敷物は家具の下に敷ける・敷物どうしは重ならない
        XCTAssertTrue(CamperRoomRules.check(.floor("r", "room_rug.runner", x: 0, z: 4), in: doc, layout: camper).ok)
        doc.upsert(.floor("r", "room_rug.runner", x: 0, z: 4))
        XCTAssertEqual(CamperRoomRules.check(.floor("r2", "room_rug.oval_hooked", x: 2, z: 3), in: doc, layout: camper).reason, .overlap)
        // 台所・扉の前・はみ出し（扉の前は奥行きが変わっても、扉の壁から 3 マス）
        XCTAssertEqual(CamperRoomRules.check(.floor("k", "storage.trunk", x: camper.kitchen.x + 1, z: 1), in: doc, layout: camper).reason, .kitchen)
        XCTAssertEqual(CamperRoomRules.check(.floor("d", "storage.trunk", x: camper.door.lowerBound, z: camper.depth - 2), in: doc, layout: camper).reason, .doorway)
        XCTAssertEqual(CamperRoomRules.check(.floor("o", "storage.trunk", x: camper.width - 1, z: 0), in: doc, layout: camper).reason, .outside)
        // 敷物は扉の前にも敷ける
        XCTAssertTrue(CamperRoomRules.check(.floor("m", "room_rug.runner", x: camper.door.lowerBound - 3, z: camper.depth - 2), in: doc, layout: camper).ok)
    }

    /// 扉から奥（後ろの壁の列）まで通れない置き方はできない
    func testPathMustRemain() {
        var doc = CamperRoomDocument(room: .car)
        // 扉の壁の 2 列手前まで、x = 4 と 5 を 1 マスずつふさぐ。最後の 2 列は開けておく
        let last = camper.depth - 1
        for z in 0..<(last - 1) {
            doc.upsert(.floor("a\(z)", "floor_lamp.brass_stem", x: 4, z: z))
            doc.upsert(.floor("b\(z)", "floor_lamp.brass_stem", x: 5, z: z))
        }
        XCTAssertTrue(CamperRoomRules.pathRemains(solid: Set(doc.items.compactMap(\.rect).flatMap(\.cells)), layout: camper))
        // 石油ストーブ（2×2）で最後の 2 列をふさぐと、扉から奥へ通れない
        let wall = CamperRoomRules.check(.floor("x", "heater.kerosene", x: 4, z: last - 1), in: doc, layout: camper)
        XCTAssertEqual(wall.reason, .blocksPath)
    }

    func testWallAndCeilingRules() {
        var doc = CamperRoomDocument(room: .car)
        // 窓の上には掛けられない（奥の壁の窓は 3〜6 マス）
        XCTAssertEqual(CamperRoomRules.check(.wall("f", "photo_frame.landscape", .back, c: 4, row: 1), in: doc, layout: camper).reason, .window)
        XCTAssertTrue(CamperRoomRules.check(.wall("f", "photo_frame.landscape", .back, c: 8, row: 1), in: doc, layout: camper).ok)
        doc.upsert(.wall("f", "photo_frame.landscape", .back, c: 8, row: 1))
        // 壁の物どうしは重ならない
        XCTAssertEqual(CamperRoomRules.check(.wall("g", "clock.station", .back, c: 9, row: 1), in: doc, layout: camper).reason, .overlap)
        // 背の高い家具（引き出し 50）は壁に付けると腰と目の段をふさぐ
        XCTAssertEqual(CamperRoomRules.check(.floor("t", "storage.tall_drawers", x: 8, z: 0), in: doc, layout: camper).reason, .wallBlocked)
        // 台所（高さ 36）は奥の壁の腰の段をふさぐ
        XCTAssertEqual(CamperRoomRules.check(.wall("k", "clock.station", .back, c: camper.kitchen.x, row: 0), in: doc, layout: camper).reason, .wallBlocked)
        // 天井: 背の高い家具（ストーブ 88）の真上には吊れない
        doc.upsert(.floor("s", "heater.wood_stove", x: 10, z: 0))
        XCTAssertEqual(CamperRoomRules.check(.ceiling("m", "mobile.wooden_birds", x: 10, z: 1), in: doc, layout: camper).reason, .tallFurniture)
        XCTAssertTrue(CamperRoomRules.check(.ceiling("m", "mobile.wooden_birds", x: 12, z: 5), in: doc, layout: camper).ok)
        // はみ出し（段は 3 つ）
        XCTAssertEqual(CamperRoomRules.check(.wall("p", "poster.tall_print", .left, c: 0, row: 2), in: doc, layout: camper).reason, .outside)
    }

    /// 写真の上限を超える額は置けない
    func testLimits() {
        let van = CamperRoomLayout.make(.car, stage: .van)
        var doc = CamperRoomDocument(room: .car)
        for i in 0..<van.photoLimit { doc.upsert(.wall("f\(i)", "photo_frame.square", .back, c: 0, row: 0)) }
        XCTAssertEqual(CamperRoomRules.check(.wall("x", "photo_frame.oval", .back, c: 10, row: 1), in: doc, layout: van).reason, .limit)
    }

    // MARK: 置く操作

    func testEditorPlaceMoveRotateStowUndo() throws {
        let owned = CamperRoomCatalog.owned(CamperStats(), CamperRoomStats())
        var e = CamperRoomEditor(doc: CamperRoomRules.starterDocument(camper), layout: camper)
        let start = e.doc
        // 棚: 置いた家具は出ない（額は何枚でも出る）
        XCTAssertFalse(e.tray(.floor, owned: owned).contains { $0.id == "bed.platform" })
        XCTAssertTrue(e.tray(.wall, owned: owned).contains { $0.id == "photo_frame.landscape" })
        // しまうと棚に戻る
        let trunk = try XCTUnwrap(e.doc.items.first { $0.k == "storage.trunk" })
        e.stow(trunk.u)
        XCTAssertNil(e.doc.item(trunk.u))
        XCTAssertTrue(e.tray(.floor, owned: owned).contains { $0.id == "storage.trunk" })
        // 棚から置く（置ける所を探す）
        let f = try XCTUnwrap(CamperRoomCatalog.furniture("storage.trunk"))
        let uid = try XCTUnwrap(e.place(f, owned: owned))
        let placed = try XCTUnwrap(e.doc.item(uid))
        XCTAssertTrue(CamperRoomRules.check(placed, in: e.doc, layout: camper).ok)
        // 持っていない家具は置けない
        XCTAssertNil(e.place(try XCTUnwrap(CamperRoomCatalog.furniture("bed.futon")), owned: owned))
        // ぶつかる所へ動かすと、動かない（元の場所に戻る）
        var bad = placed
        bad.x = 0
        bad.z = 0
        XCTAssertFalse(e.move(bad).ok)
        XCTAssertEqual(e.doc.item(uid), placed)
        // 置ける所へ動かす
        var good = placed
        good.x = 6
        good.z = 7
        XCTAssertTrue(e.move(good).ok)
        XCTAssertEqual(e.doc.item(uid)?.x, 6)
        // 回す
        XCTAssertTrue(e.rotate(uid))
        XCTAssertEqual(e.doc.item(uid)?.turns, 1)
        // 1 手ずつ元に戻す
        XCTAssertTrue(e.undo())
        XCTAssertEqual(e.doc.item(uid)?.turns, 0)
        while e.canUndo { e.undo() }
        XCTAssertEqual(e.doc, start)
        XCTAssertFalse(e.undo())
    }

    /// 額に写真を入れる（額でない物には入らない）・元に戻せる
    func testSetPhoto() throws {
        var e = CamperRoomEditor(doc: CamperRoomRules.starterDocument(camper), layout: camper)
        let frame = try XCTUnwrap(e.doc.items.first { $0.k == "photo_frame.landscape" })
        e.setPhoto(frame.u, photoId: "P1")
        XCTAssertEqual(e.doc.item(frame.u)?.p, "P1")
        let bed = try XCTUnwrap(e.doc.items.first { $0.k == "bed.platform" })
        e.setPhoto(bed.u, photoId: "P2")
        XCTAssertNil(e.doc.item(bed.u)?.p)
        e.undo()
        XCTAssertNil(e.doc.item(frame.u)?.p)
    }

    /// 初めて入った部屋の空の額には、自分の写真を新しい順に入れる（同じ写真は 2 度入れない・元に戻すの手に数えない）
    func testFillEmptyFrames() {
        var doc = CamperRoomRules.starterDocument(camper)
        let frames = doc.all.filter { ($0.furniture?.photoSlots ?? 0) > 0 }
        XCTAssertEqual(frames.count, 2)
        var first = frames[0]
        first.p = "B"
        doc.upsert(first)
        var e = CamperRoomEditor(doc: doc, layout: camper)
        e.fillEmptyFrames(["A", "B", "C"])
        XCTAssertEqual(e.doc.item(frames[0].u)?.p, "B")
        XCTAssertEqual(e.doc.item(frames[1].u)?.p, "A")
        XCTAssertFalse(e.canUndo)
    }

    /// 持っていない家具は見せない（保存する文書からは消さない）
    func testShownHidesUnownedButKeepsSaved() {
        var doc = CamperRoomRules.starterDocument(camper)
        doc.upsert(.floor("z", "bed.futon", x: 6, z: 6))
        let e = CamperRoomEditor(doc: doc, layout: camper)
        let owned = CamperRoomCatalog.owned(CamperStats(), CamperRoomStats())
        XCTAssertNil(e.shown(owned: owned).item("z"))
        XCTAssertNotNil(e.doc.item("z"))
    }

    // MARK: 保存

    /// 人ごとの鍵に保存し、別の人には見えない。退会で消える。板の保存の形（room・rev・style・items・ceil）
    @MainActor
    func testStorePerUserAndRemoval() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "camper.room.test.\(UUID().uuidString)"))
        let a = CamperRoomStore(userId: "A", defaults: defaults)
        let b = CamperRoomStore(userId: "B", defaults: defaults)
        var doc = CamperRoomRules.starterDocument(camper)
        doc.style.curtain = "indigo"
        let saved = a.save(doc, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(saved.rev, doc.rev + 1)
        XCTAssertEqual(saved.updatedAt, "1970-01-01T00:00:00Z")
        XCTAssertEqual(a.load(camper), saved)
        XCTAssertEqual(b.load(camper), CamperRoomRules.starterDocument(camper))
        let json = try XCTUnwrap(String(data: try XCTUnwrap(defaults.data(forKey: CamperRoomStore.key("A", .car))), encoding: .utf8))
        for key in ["\"room\":\"car\"", "\"rev\"", "\"style\"", "\"items\"", "\"ceil\"", "\"k\":\"bed.platform\""] {
            XCTAssertTrue(json.contains(key), key)
        }
        XCTAssertLessThan(json.utf8.count, 5_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AccountLocalData.remove(userId: "A", username: nil, defaults: defaults, draftDirectory: dir, offlineTripsRoot: dir, passRoot: dir)
        XCTAssertNil(defaults.data(forKey: CamperRoomStore.key("A", .car)))
    }

    // MARK: カメラと指の位置

    /// 部屋の点を画面へ写して、その画面の点から光線を出すと、同じ点を通る（押した所と絵がずれない）
    func testProjectAndRayRoundTrip() throws {
        let cam = CamperRoomCamera.overview(camper)
        let viewport = CGSize(width: 390, height: 440)
        for p in [CV3(30, 0, 20), CV3(150, 0, 80), CV3(90, 0, 45)] {
            let screen = try XCTUnwrap(cam.project(p, viewport: viewport, layout: camper))
            let ray = cam.ray(screen, viewport: viewport, layout: camper)
            let hit = try XCTUnwrap(CamperRoomPick.hitHorizontal(ray, y: 0))
            XCTAssertEqual(hit.x, p.x, accuracy: 0.01)
            XCTAssertEqual(hit.z, p.z, accuracy: 0.01)
        }
        // 部屋の真ん中は画面の内に写る
        let mid = try XCTUnwrap(cam.project(CV3(camper.size.x / 2, 18, camper.size.z / 2), viewport: viewport, layout: camper))
        XCTAssertGreaterThan(mid.x, 0)
        XCTAssertLessThan(mid.x, 390)
        XCTAssertGreaterThan(mid.y, 0)
        XCTAssertLessThan(mid.y, 440)
    }

    /// 指の下の家具を拾い、動かした先はマス目に吸い付く（家具の真ん中が指の下）
    func testPickAndSnap() throws {
        let doc = CamperRoomRules.starterDocument(camper)
        let cam = CamperRoomCamera.overview(camper)
        let viewport = CGSize(width: 390, height: 440)
        let trunk = try XCTUnwrap(doc.items.first { $0.k == "storage.trunk" })
        let b = try XCTUnwrap(CamperRoomPick.bounds(trunk))
        let top = CV3((b.min.x + b.max.x) / 2, b.max.y - 1, (b.min.z + b.max.z) / 2)
        let screen = try XCTUnwrap(cam.project(top, viewport: viewport, layout: camper))
        let picked = CamperRoomPick.item(at: cam.ray(screen, viewport: viewport, layout: camper), in: doc)
        XCTAssertEqual(picked?.u, trunk.u)
        // 床の (66, 0, 72) を指すと、3×2 の鞄の左奥は (5, 6)（マスの境目ちょうどを指さない: 0.5 の丸めは端末で揺れる）
        let target = try XCTUnwrap(cam.project(CV3(66, 0, 72), viewport: viewport, layout: camper))
        let moved = CamperRoomPick.moved(trunk, ray: cam.ray(target, viewport: viewport, layout: camper), layout: camper)
        XCTAssertEqual(moved.x, 5)
        XCTAssertEqual(moved.z, 6)
        // 壁の物は指の先の壁と段へ
        let frame = try XCTUnwrap(doc.items.first { $0.k == "photo_frame.landscape" })
        let onWall = try XCTUnwrap(cam.project(CV3(120, 50, 0), viewport: viewport, layout: camper))
        let hung = CamperRoomPick.moved(frame, ray: cam.ray(onWall, viewport: viewport, layout: camper), layout: camper)
        XCTAssertEqual(hung.w, .back)
        XCTAssertEqual(hung.c, 11)
        XCTAssertEqual(hung.row, 1)
    }

    /// 回せる範囲（横 −90〜90・縦 25〜60・0.8〜1.8 倍）と、向きで切る端の壁が替わる
    func testCameraClampAndCutaway() {
        var c = CamperRoomCamera.overview(camper).dragged(dx: -2000, dy: 2000)
        XCTAssertEqual(c.yaw, 90)
        XCTAssertEqual(c.pitch, 60)
        c = c.pinched(10)
        XCTAssertEqual(c.zoom, 1.8)
        XCTAssertTrue(CamperRoomScenePlan.visible("room.end.rear.full", camera: CamperRoomCamera.overview(camper)))
        XCTAssertFalse(CamperRoomScenePlan.visible("room.end.front.full", camera: CamperRoomCamera.overview(camper)))
        var back = CamperRoomCamera.overview(camper)
        back.yaw = -40
        XCTAssertTrue(CamperRoomScenePlan.visible("room.end.front.full", camera: back))
        XCTAssertTrue(CamperRoomScenePlan.visible("room.end.rear.low", camera: back))
        XCTAssertTrue(CamperRoomScenePlan.visible("room.kitchen", camera: back))
    }

    // MARK: 形と素材

    /// 作り込んだ家具の形: 向きは長さ 1・数は有限、三角形は多すぎない（1 つ 3 万まで）、置くマスに収まる。
    /// 「箱を並べただけ」にしない目安として、どの家具も 2 種類以上の素材と 300 以上の三角形を持つ
    func testFurnitureMeshesAreSoundAndDetailed() throws {
        for f in CamperRoomCatalog.all where f.built {
            let m = try XCTUnwrap(CamperRoomFurnitureModels.mesh(f.id), f.id)
            XCTAssertGreaterThan(m.triangleCount, 200, f.id)
            XCTAssertLessThan(m.triangleCount, 30_000, f.id)
            XCTAssertGreaterThanOrEqual(Set(m.materials).count, 2, f.id)
            for n in m.normals { XCTAssertEqual(n.length, 1, accuracy: 0.01, f.id) }
            for p in m.positions { XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite, f.id) }
            let ys = m.positions.map(\.y)
            // 足元（床から 30 まで）はマスに収まる（灯りの笠など高い所は他の家具の上へ張り出してよい）
            let low = m.positions.filter { f.placement != .floor || $0.y < 30 }
            let xs = low.map(\.x), zs = low.map(\.z)
            let cell = CamperRoomLayout.cell
            switch f.placement {
            case .floor:
                XCTAssertLessThanOrEqual(xs.max()! - xs.min()!, Double(f.width) * cell + 2, f.id)
                XCTAssertLessThanOrEqual(zs.max()! - zs.min()!, Double(f.depth) * cell + 2, f.id)
                XCTAssertGreaterThanOrEqual(ys.min()!, -0.05, f.id)
                // 高さは家具そのもの。上に載せた置物（マグ・鉢・やかん）の分だけ超えてよい
                XCTAssertLessThanOrEqual(ys.max()!, max(f.height, 3) + 12, f.id)
            case .wall:
                XCTAssertLessThanOrEqual(xs.max()! - xs.min()!, Double(f.width) * cell + 1, f.id)
                XCTAssertGreaterThanOrEqual(zs.min()!, -0.05, f.id)
                XCTAssertLessThanOrEqual(ys.max()!, CamperRoomLayout.rowHeight * Double(f.depth) + 1, f.id)
            case .ceiling:
                XCTAssertLessThanOrEqual(ys.max()!, 0.05, f.id)
                XCTAssertGreaterThanOrEqual(ys.min()!, -f.height - 1, f.id)
            }
        }
    }

    /// 夜の光の決まり: どの素材も光る面の emission は 1 まで。窓の外の景色は光を受けない
    func testEmissionCapAndUnlitView() {
        var mats: Set<CamperMaterial> = []
        for f in CamperRoomCatalog.all where f.built { CamperRoomFurnitureModels.mesh(f.id)?.materials.forEach { mats.insert($0) } }
        let bp = CamperRoomBuilder.build(camper, doc: CamperRoomRules.starterDocument(camper))
        for n in bp.shell { if case .mesh(let m) = n.shape { m.materials.forEach { mats.insert($0) } } }
        for m in mats {
            for mood in [CamperMood.day, .night] {
                XCTAssertLessThanOrEqual(CamperMaterials.spec(m, paint: 0x5B6168, mood: mood).emissionIntensity, 1, "\(m)")
            }
        }
        XCTAssertTrue(CamperMaterials.spec(.room(.windowView), paint: 0, mood: .night).unlit)
        XCTAssertEqual(CamperMaterials.spec(.room(.windowView), paint: 0, mood: .night).texture, .windowNight)
    }

    /// 部屋の組み立て: 壁は 3 層・窓・台所・扉の口・端の壁の高い／低いの組がそろい、夜の灯りは室内の名前で上限まで
    func testRoomBlueprint() {
        let bp = CamperRoomBuilder.build(camper, doc: CamperRoomRules.starterDocument(camper))
        let names = Set(bp.shell.map(\.name))
        for n in ["room.floor", "room.ceiling", "room.wall.back", "room.end.rear.full", "room.end.rear.low", "room.end.front.full",
                  "room.end.front.low", "room.wall.door", "room.kitchen", "room.doorway", "room.window0"] {
            XCTAssertTrue(names.contains(n), n)
        }
        XCTAssertEqual(bp.items.count, 16)
        XCTAssertLessThanOrEqual(bp.lights.count, CamperRoomBuilder.maxLamps)
        for l in bp.lights {
            XCTAssertTrue(l.inside, l.name)
            XCTAssertEqual(l.moods, [.night], l.name)
        }
        // 部屋全体を照らす天井の灯りは置かない（Mac run 575: 夜が昼より明るかった）
        XCTAssertTrue(bp.lights.allSatisfy { $0.kind == .omni })
        // 灯りの家具の灯りがある（床の灯り・壁の灯り・電球の紐・ストーブ）
        XCTAssertGreaterThanOrEqual(bp.lights.filter { $0.name.hasPrefix("interior.lamp.") }.count, 4)
    }

    /// 夜の光の合計の上限（外の車の夜と同じ考え方）: どんなに灯りの家具を並べても、強さの和と届く距離は上限に収まる。
    /// 上限を超えると、部屋全体が黄白に光って昼より明るく見えた（Mac run 568〜575）
    func testNightLightBudget() {
        var doc = CamperRoomDocument(room: .car)
        let lit = CamperRoomCatalog.all.filter { $0.lit && $0.built }
        for (i, f) in lit.enumerated() {
            switch f.placement {
            case .floor: doc.upsert(.floor("l\(i)", f.id, x: (i * 3) % 16, z: 6))
            case .wall: doc.upsert(.wall("l\(i)", f.id, .back, c: 8 + i % 8, row: 1))
            case .ceiling: doc.upsert(.ceiling("l\(i)", f.id, x: (i * 6) % 12, z: 4))
            }
        }
        let bp = CamperRoomBuilder.build(camper, doc: doc)
        XCTAssertGreaterThanOrEqual(bp.lights.count, 4)
        XCTAssertLessThanOrEqual(bp.lights.count, CamperRoomBuilder.maxLamps)
        XCTAssertLessThanOrEqual(bp.lights.reduce(0) { $0 + $1.intensity }, CamperRoomBuilder.nightBudget.intensity + 0.001)
        for l in bp.lights { XCTAssertLessThanOrEqual(l.range, CamperRoomBuilder.nightBudget.range, l.name) }
    }

    /// 家具の小さな絵は形が写る（真ん中に色・まわりは透明）。影絵は黒と灰の縁
    func testThumbnailsRender() throws {
        let mesh = try XCTUnwrap(CamperRoomFurnitureModels.mesh("storage.trunk"))
        var o = CamperRoomRaster.Options()
        o.width = 48
        o.height = 48
        let b = CamperRoomRaster.render(mesh, o)
        XCTAssertGreaterThan(b.pixel(24, 24).a, 200)
        XCTAssertEqual(b.pixel(0, 0).a, 0)
        o.silhouette = true
        let s = CamperRoomRaster.render(mesh, o)
        let p = s.pixel(24, 24)
        XCTAssertLessThan(Int(p.r), 20)
    }

    /// 貼り絵は 256 px まで
    func testRoomTexturesAreSmall() {
        for kind: CamperTextureKind in [.planks, .chevron, .herringbone, .checkerTiles, .cork, .boards, .birchPly, .darkBoards, .wallpaperStripe,
                                        .leather, .linenSlub, .knit, .rush, .wicker, .rope, .ovalRings, .runnerWeave, .enamelChip, .castIron,
                                        .foliage, .clockDial, .windowDay, .windowNight, .matBoard, .photoPlaceholder, .wornWood] {
            let b = CamperTextures.make(kind)
            XCTAssertLessThanOrEqual(max(b.width, b.height), CamperTextures.maxSide, kind.rawValue)
            XCTAssertEqual(b.rgba.count, b.width * b.height * 4, kind.rawValue)
        }
    }

    /// 図鑑の寄りの部屋: どの作り込んだ家具も小さな部屋に収まって置ける
    func testStudioFitsEveryBuiltPiece() {
        for f in CamperRoomCatalog.all where f.built {
            let s = CamperRoomStudio.make(f)
            XCTAssertEqual(s.doc.all.count, 1, f.id)
            XCTAssertNotNil(CamperRoomBuilder.place(s.doc.all[0]), f.id)
            let cam = CamperRoomStudio.camera(f)
            XCTAssertTrue(cam.eye(s.layout).y > 0, f.id)
        }
    }
}

#if canImport(SceneKit) || canImport(SceneKitShim)

/// 組み上げた場面（ノードの属性）: 灯りの組・影・にじみ・昼と夜・家具の数
@MainActor
final class CamperRoomSceneTests: XCTestCase {

    private func all(_ n: SCNNode) -> [SCNNode] { [n] + n.childNodes.flatMap { all($0) } }

    func testSceneLightsAndMood() async throws {
        let layout = CamperRoomLayout.make(.car, stage: .camper)
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        scene.installNow(layout: layout, doc: doc, paint: 0x5B6168)
        let items = all(scene.scene.rootNode).filter { $0.name?.hasPrefix("item.") == true }
        XCTAssertEqual(items.count, doc.all.count)
        for n in items { XCTAssertEqual(n.categoryBitMask, CamperScene.insideMask, n.name ?? "") }
        let lamps = all(scene.scene.rootNode).filter { $0.name?.hasPrefix("light.interior.") == true }
        XCTAssertFalse(lamps.isEmpty)
        for n in lamps {
            XCTAssertEqual(n.light?.categoryBitMask, CamperScene.insideMask)
            XCTAssertTrue(n.isHidden, "昼は灯りを消す")
            if n.light?.castsShadow == true { XCTAssertEqual(n.light?.shadowMode, .forward) }
        }
        XCTAssertEqual(scene.lightingSnapshot.bloom, 0)
        // 太陽の影は forward（deferred は天井の下の部屋全部を影の色で塗る）
        let sun = try XCTUnwrap(all(scene.scene.rootNode).first { $0.light?.type == .directional })
        XCTAssertEqual(sun.light?.shadowMode, .forward)
        XCTAssertTrue(sun.light?.castsShadow == true)
        scene.setMood(.night)
        let night = scene.lightingSnapshot
        XCTAssertEqual(night.lampsShown, night.lamps)
        XCTAssertEqual(night.bloom, 0)
        XCTAssertLessThan(night.sun, 100)
        // 夜の値は外の車の夜にそろえる（露出 −0.15・周りの光は外より弱く・環境光はごく弱く）
        XCTAssertEqual(night.environment, 0.06, accuracy: 0.001)
        XCTAssertLessThanOrEqual(night.ambient, 10)
        XCTAssertEqual(Double(scene.cameraNode.camera?.exposureOffset ?? 0), -0.15, accuracy: 0.001)
        scene.setMood(.day)
        XCTAssertEqual(scene.lightingSnapshot.lampsShown, 0)
        XCTAssertTrue(scene.marker().contains("camper-room-ready car day"))
    }

    /// 持ち上げて動かしている間は、足元のマスを白（置ける）か赤（ぶつかる）で出し、終われば消す
    func testDragOverlay() async throws {
        let layout = CamperRoomLayout.make(.car, stage: .camper)
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        scene.installNow(layout: layout, doc: doc, paint: 0x5B6168)
        var trunk = try XCTUnwrap(doc.items.first { $0.k == "storage.trunk" })
        trunk.x = 0
        trunk.z = 0
        let check = CamperRoomRules.check(trunk, in: doc, layout: layout)
        XCTAssertFalse(check.ok)
        scene.setDrag(trunk, check: check)
        let cells = all(scene.scene.rootNode).filter { $0.name == "drag" }
        XCTAssertEqual(cells.count, 6)
        scene.setDrag(nil, check: nil)
        XCTAssertTrue(all(scene.scene.rootNode).filter { $0.name == "drag" }.isEmpty)
    }
}

#endif
