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

    /// 板の 16 分類・64 個に別種 10 分類・40 個を足す（1 分類 4 つ）。最初から 27 個、要サーバー 10 個。
    /// 形の組み合わせ（`CamperRoomVariety`）を足すと、あつまれどうぶつの森の家具 2,076 を超える。色違いでは数えない
    func testCatalogMatchesTheBoard() {
        let board = CamperRoomCatalog.board
        XCTAssertEqual(board.count, 104)
        XCTAssertEqual(Set(board.map(\.id)).count, 104)
        XCTAssertEqual(CamperRoomCategory.allCases.count, 26)
        for c in CamperRoomCategory.allCases { XCTAssertEqual(board.filter { $0.category == c }.count, 4, c.rawValue) }
        XCTAssertEqual(board.filter { $0.placement == .floor }.count, 56)
        XCTAssertEqual(board.filter { $0.placement == .wall }.count, 32)
        XCTAssertEqual(board.filter { $0.placement == .ceiling }.count, 16)
        XCTAssertEqual(board.filter { $0.unlock.isStarter }.count, 27)
        let server = board.filter { if case .base(.server) = $0.unlock { return true } else { return false } }
        XCTAssertEqual(Set(server.map(\.id)), ["bed.daybed", "seating.bench_storage", "heater.tile_hearth", "floor_lamp.paper_column",
                                               "wall_shelf.floating_corner", "poster.postcard_grid", "poster.tapestry", "string_ceiling.bunting",
                                               "plant_hanger.hanging_basket", "plant_hanger.glass_terrarium"])
        // 珍しさ（板の内訳＋別種）
        XCTAssertEqual(board.filter { $0.rarity == .common }.count, 27)
        XCTAssertEqual(board.filter { $0.rarity == .occasional }.count, 33)
        XCTAssertEqual(board.filter { $0.rarity == .rare }.count, 30)
        XCTAssertEqual(board.filter { $0.rarity == .veryRare }.count, 14)
        let all = CamperRoomCatalog.all
        XCTAssertGreaterThan(all.count, CamperRoomVariety.animalCrossingCount)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(CamperRoomVariety.pieces.map(\.signature)).count, CamperRoomVariety.pieces.count)
        XCTAssertEqual(all.filter { $0.unlock.isStarter }.count, 27)
        XCTAssertEqual(Set(all.map(\.nameJa)).count, all.count)
        XCTAssertEqual(Set(all.map(\.nameEn)).count, all.count)
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
        XCTAssertEqual(owned.count, 27)
        let count = CamperRoomCatalog.dexCount(owned)
        XCTAssertEqual(count.have, 27)
        XCTAssertEqual(count.total, CamperRoomCatalog.all.filter { $0.built && $0.unlock.isAvailable }.count)
        XCTAssertEqual(CamperRoomCatalog.soonCount, CamperRoomCatalog.board.filter { !$0.isAvailable }.count)
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

    /// 最初の並びは、殻の部屋で決まりに合っていて、思った数がそろう
    func testStarterDocumentsAreValid() {
        for (kind, stage, count, width, depth) in [(CamperRoomKind.car, CamperStage.van, 9, 12, 8),
                                                    (.car, .camper, 16, 18, 9), (.trailer, .trailer, 4, 11, 7)] {
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

    /// どの段も 7 部屋。床のマスは外の箱÷10。地面の箱の高さは天井 88。箱どうしは重ならない
    func testRoomsMatchTheOutside() {
        func overlaps(_ a: CamperVolumes.Box, _ b: CamperVolumes.Box) -> Bool {
            let ax0 = min(a.x0, a.x1), ax1 = max(a.x0, a.x1)
            let bx0 = min(b.x0, b.x1), bx1 = max(b.x0, b.x1)
            let az0 = min(a.z0, a.z1), az1 = max(a.z0, a.z1)
            let bz0 = min(b.z0, b.z1), bz1 = max(b.z0, b.z1)
            return ax0 < bx1 && bx0 < ax1 && az0 < bz1 && bz0 < az1
        }
        for stage in CamperStage.allCases {
            let rooms = CamperRoomKind.rooms(stage)
            XCTAssertGreaterThanOrEqual(rooms.count, 7, "\(stage)")
            XCTAssertEqual(Set(rooms).count, rooms.count, "\(stage)")
            XCTAssertEqual(rooms.contains(.locker), stage != .trailer, "\(stage)")
            XCTAssertEqual(rooms.contains(.trailer), stage == .trailer, "\(stage)")
            let boxes = CamperVolumes.boxes(stage)
            for kind in rooms {
                let layout = CamperRoomLayout.make(kind, stage: stage)
                if let box = boxes[kind] {
                    XCTAssertEqual(Double(layout.width) * CamperVolumes.cell, box.length, accuracy: 0.01, "\(stage) \(kind)")
                    XCTAssertEqual(Double(layout.depth) * CamperVolumes.cell, box.width, accuracy: 0.01, "\(stage) \(kind)")
                    XCTAssertEqual(layout.ceilingHeight, box.height, accuracy: 0.01, "\(stage) \(kind)")
                    if box.floorTop == CamperVolumes.groundFloorY {
                        XCTAssertEqual(box.height, CamperVolumes.groundHeight, "\(kind)")
                    } else {
                        XCTAssertEqual(box.height, CamperVolumes.upperHeight, "\(kind)")
                        XCTAssertGreaterThan(box.floorTop, CamperVolumes.roofTop(stage), "\(kind)")
                    }
                }
                let doc = CamperRoomRules.starterDocument(layout)
                for item in doc.all {
                    var others = doc
                    others.remove(item.u)
                    XCTAssertTrue(CamperRoomRules.check(item, in: others, layout: layout).ok, "\(kind) \(stage) \(item.k)")
                }
            }
            let ground = boxes.values.filter { $0.floorTop == CamperVolumes.groundFloorY }
            let upper = boxes.values.filter { $0.floorTop != CamperVolumes.groundFloorY }
            for pair in [Array(ground), Array(upper)] {
                for i in 0..<pair.count {
                    for j in (i + 1)..<pair.count {
                        XCTAssertFalse(overlaps(pair[i], pair[j]), "\(stage)")
                    }
                }
            }
        }
        let loft = CamperRoomLayout.make(.loft, stage: .camper)
        XCTAssertEqual(loft.ceilingHeight, CamperVolumes.upperHeight, accuracy: 0.01)
        XCTAssertEqual(CamperRoomRules.check(.floor("s", "heater.wood_stove", x: 0, z: 0), in: CamperRoomDocument(room: .loft), layout: loft).reason, .tooTall)
        XCTAssertTrue(CamperRoomRules.check(.floor("s", "heater.wood_stove", x: 0, z: 0), in: CamperRoomDocument(room: .car), layout: camper).ok)
        XCTAssertNil(CamperVolumes.boxes(.camper)[.car])
        XCTAssertNil(CamperVolumes.boxes(.trailer)[.trailer])
        XCTAssertEqual(CamperRoomLayout.make(.trailer, stage: .trailer).width, 11)
        XCTAssertEqual(CamperRoomLayout.make(.trailer, stage: .trailer).depth, 7)
    }

    /// 図鑑は名前か id で探せる。板の id は、形の組み合わせ「分類.x000」に埋もれない
    func testDexSearchFindsTheBoardPiece() throws {
        let stove = try XCTUnwrap(CamperRoomCatalog.furniture("heater.wood_stove"))
        XCTAssertTrue(CamperRoomCatalog.matchesDexQuery(stove, "heater.wood_stove"))
        XCTAssertTrue(CamperRoomCatalog.matchesDexQuery(stove, "薪"))
        XCTAssertTrue(CamperRoomCatalog.matchesDexQuery(stove, "  "))
        let variety = CamperRoomCatalog.all.filter { $0.id.hasPrefix("heater.x") }
        XCTAssertFalse(variety.contains { CamperRoomCatalog.matchesDexQuery($0, "heater.wood_stove") })
        XCTAssertEqual(CamperRoomCatalog.all.filter { CamperRoomCatalog.matchesDexQuery($0, "photo_frame.landscape") }.map(\.id), ["photo_frame.landscape"])
    }

    /// 図鑑の家具は、空の部屋のどれか 1 つには入る（全部を一部屋に並べると外の箱と矛盾する）。
    func testCollectedFurnitureFits() {
        let pieces = CamperRoomCatalog.all.filter { $0.built && $0.unlock.isAvailable }
        for stage in CamperStage.allCases {
            let rooms = CamperRoomKind.rooms(stage)
            var missed: [String] = []
            for f in pieces {
                let fits = rooms.contains { kind in
                    let layout = CamperRoomLayout.make(kind, stage: stage)
                    return CamperRoomRules.firstFit(f, uid: "t", in: CamperRoomDocument(room: kind), layout: layout) != nil
                }
                if !fits { missed.append(f.id) }
            }
            XCTAssertEqual(missed.count, 0, "\(stage) \(missed.prefix(8))")
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
        // 扉のすぐ手前に、1 マスだけ開けた壁を立てる。その隙間から奥（x = 0）へ抜けられる
        let cutX = camper.door.lowerBound - 1
        let gapZ = camper.depth / 2
        for z in 0..<camper.depth where z != gapZ {
            doc.upsert(.floor("p\(z)", "floor_lamp.brass_stem", x: cutX, z: z))
        }
        XCTAssertTrue(CamperRoomRules.pathRemains(solid: Set(doc.items.compactMap(\.rect).flatMap(\.cells)), layout: camper))
        let wall = CamperRoomRules.check(.floor("x", "floor_lamp.brass_stem", x: cutX, z: gapZ), in: doc, layout: camper)
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

    /// 回せる範囲（横 −90〜90・縦 25〜60・0.8〜28 倍）と、寄ったあとに部屋の中を見て回れること。向きで切る端の壁が替わる
    func testCameraClampAndCutaway() {
        var c = CamperRoomCamera.overview(camper).dragged(dx: -2000, dy: 2000)
        XCTAssertEqual(c.yaw, 90)
        XCTAssertEqual(c.pitch, 60)
        c = c.pinched(100)
        XCTAssertEqual(c.zoom, CamperRoomCamera.zoomRange.upperBound)
        let panned = c.panned(dx: 80, dy: -30, layout: camper)
        XCTAssertNotEqual(panned.target.x, c.target.x)
        XCTAssertGreaterThanOrEqual(panned.target.x, 0)
        XCTAssertLessThanOrEqual(panned.target.x, camper.size.x)
        XCTAssertGreaterThanOrEqual(panned.target.z, 0)
        XCTAssertLessThanOrEqual(panned.target.z, camper.size.z)
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
        var shapes = Set<String>()
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
            let sum = m.positions.reduce(0.0) { $0 + $1.x + $1.y * 3 + $1.z * 7 }
            shapes.insert("\(m.triangleCount)|\(Int((sum * 10).rounded()))")
        }
        // 色を変えただけが同じ輪郭に潰れていない（あつ森の家具の数より、別の形が多い）
        XCTAssertGreaterThan(shapes.count, CamperRoomVariety.animalCrossingCount - 500)
    }

    /// 張り出しなど台所なしの部屋でも、部屋の殻を組んで落ちない（#331: `1..<0` の目地ループ）
    func testWingRoomsBuildWithoutKitchen() {
        for stage in CamperStage.allCases {
            for kind in CamperRoomKind.rooms(stage) {
                let layout = CamperRoomLayout.make(kind, stage: stage)
                let doc = CamperRoomRules.starterDocument(layout)
                let bp = CamperRoomBuilder.build(layout, doc: doc)
                XCTAssertEqual(bp.layout.kind, kind, "\(stage) \(kind)")
                XCTAssertFalse(bp.shell.isEmpty, "\(stage) \(kind)")
                let hasKitchen = bp.shell.contains { $0.name == "room.kitchen" }
                if kind == .car {
                    XCTAssertTrue(hasKitchen, "\(stage) \(kind)")
                    XCTAssertGreaterThan(layout.kitchen.w, 0)
                    XCTAssertGreaterThan(layout.kitchen.d, 0)
                } else {
                    XCTAssertFalse(hasKitchen, "\(stage) \(kind)")
                    XCTAssertEqual(layout.kitchen.w, 0, "\(stage) \(kind)")
                    XCTAssertEqual(layout.kitchen.d, 0, "\(stage) \(kind)")
                }
                XCTAssertTrue(bp.shell.contains { $0.name == "room.doorway" }, "\(stage) \(kind)")
            }
        }
        // 空の台所だけ渡しても落ちず、部品は出さない
        var emptyKitchen = CamperRoomLayout.make(.sideRear, stage: .camper)
        emptyKitchen.kitchen = CamperRoomRect(x: 0, z: 0, w: 0, d: 0)
        XCTAssertTrue(CamperRoomBuilder.kitchen(emptyKitchen).isEmpty)
    }

    /// 夜の光の決まり: どの素材も光る面の emission は 1 まで。窓の外の景色は光を受けない
    func testEmissionCapAndUnlitView() throws {
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
        // 夜の窓の硝子は暗い（明るい硝子のままだと窓が白い板になる・2026-10-19 owner）
        let dayGlass = CamperMaterials.spec(.room(.glass), paint: 0, mood: .day)
        let nightGlass = CamperMaterials.spec(.room(.glass), paint: 0, mood: .night)
        XCTAssertNotEqual(dayGlass.color, nightGlass.color)
        XCTAssertLessThan(nightGlass.color, 0x202020)
        XCTAssertGreaterThan(nightGlass.opacity, dayGlass.opacity)
        XCTAssertLessThan(nightGlass.clearCoat, dayGlass.clearCoat)
        // 額の表は窓の硝子ではない。窓の硝子だと夜は暗い膜・昼は白い板になって、飾った写真が消える（2026-10-19 owner）
        let dayFrame = CamperMaterials.spec(.room(.frameGlass), paint: 0, mood: .day)
        let nightFrame = CamperMaterials.spec(.room(.frameGlass), paint: 0, mood: .night)
        XCTAssertEqual(dayFrame.color, nightFrame.color)
        XCTAssertEqual(dayFrame.opacity, nightFrame.opacity, accuracy: 0.001)
        XCTAssertLessThan(nightFrame.opacity, 0.2)
        XCTAssertFalse(nightFrame.glassShell)
        XCTAssertGreaterThan(nightFrame.color, 0xC0C0C0)
        XCTAssertNotEqual(nightFrame.color, nightGlass.color)
        XCTAssertLessThan(nightFrame.opacity, nightGlass.opacity)
        for id in ["photo_frame.landscape", "photo_frame.square", "photo_frame.triptych"] {
            let mesh = try XCTUnwrap(CamperRoomFurnitureModels.mesh(id), id)
            XCTAssertTrue(mesh.materials.contains(.room(.frameGlass)), id)
            XCTAssertTrue(mesh.materials.contains(.room(.photo("slot0"))), id)
            XCTAssertFalse(mesh.materials.contains(.room(.glass)), id)
        }
    }

    /// 写真を飾るときは、部屋の真ん中ではなく選んだ額の前に寄る
    func testPhotoFramingLooksAtTheFrame() throws {
        let layout = CamperRoomLayout.make(.car, stage: .camper)
        let doc = CamperRoomRules.starterDocument(layout)
        let back = try XCTUnwrap(doc.all.first { $0.k == "photo_frame.landscape" })
        let placed = try XCTUnwrap(CamperRoomBuilder.place(back))
        let cam = CamperRoomCamera.framing(back, layout: layout)
        XCTAssertEqual(cam.target.x, placed.position.x, accuracy: 1)
        // 額の真ん中を狙う（天井の換気窓が主役にならないよう見下ろしは浅く）
        XCTAssertEqual(cam.target.y, placed.position.y + placed.footprint.y / 2, accuracy: 1)
        XCTAssertEqual(cam.pitch, CamperRoomCamera.pitchRange.lowerBound, accuracy: 0.01)
        XCTAssertGreaterThan(cam.zoom, 1)
        XCTAssertLessThanOrEqual(cam.zoom, CamperRoomCamera.zoomRange.upperBound)
        let viewport = CGSize(width: 390, height: 440)
        let mid = CV3(placed.position.x, cam.target.y, placed.position.z)
        let onScreen = try XCTUnwrap(cam.project(mid, viewport: viewport, layout: layout))
        XCTAssertEqual(onScreen.x, viewport.width / 2, accuracy: 90)
        XCTAssertEqual(onScreen.y, viewport.height / 2, accuracy: 120)
        let side = try XCTUnwrap(doc.all.first { $0.k == "photo_frame.square" })
        let sidePlaced = try XCTUnwrap(CamperRoomBuilder.place(side))
        let sideCam = CamperRoomCamera.framing(side, layout: layout)
        XCTAssertEqual(sideCam.target.z, sidePlaced.position.z, accuracy: 1)
        XCTAssertGreaterThan(sideCam.yaw, 45)
        XCTAssertNotNil(sideCam.project(sidePlaced.position, viewport: viewport, layout: layout))
    }

    /// 額の網には写真の面がある（材質の差し替え先が空だと、飾っても黒い穴のまま）
    func testPhotoFramesHavePhotoSlotsInMesh() throws {
        for id in ["photo_frame.landscape", "photo_frame.square", "photo_frame.oval", "photo_frame.triptych", "poster.tall_print"] {
            let mesh = try XCTUnwrap(CamperRoomFurnitureModels.mesh(id), id)
            let photos = mesh.groups.filter {
                if case .room(.photo) = $0.material { return true }
                return false
            }
            XCTAssertFalse(photos.isEmpty, id)
            XCTAssertTrue(photos.allSatisfy { !$0.indices.isEmpty }, id)
        }
    }

    /// 外景色の板は窓穴より少し大きいだけ。巨大な板だと箱庭の外に青い「変な写真枠」が浮く（#324）
    func testWindowExteriorViewFitsTheHole() throws {
        let bp = CamperRoomBuilder.build(camper, doc: CamperRoomRules.starterDocument(camper))
        var found = 0
        for n in bp.shell where n.name.contains("window") {
            guard case .mesh(let mesh) = n.shape else { continue }
            var pts: [CV3] = []
            for group in mesh.groups {
                guard case .room(.windowView) = group.material else { continue }
                for i in group.indices {
                    let idx = Int(i)
                    guard idx < mesh.positions.count else { continue }
                    pts.append(mesh.positions[idx])
                }
            }
            guard !pts.isEmpty else { continue }
            found += 1
            let xs = pts.map(\.x), ys = pts.map(\.y), zs = pts.map(\.z)
            let spans = [xs.max()! - xs.min()!, ys.max()! - ys.min()!, zs.max()! - zs.min()!].sorted()
            // 薄い板の長い 2 辺が窓穴（およそ 26×32）の近傍。昔の高さ 60・横 1.9 倍を戻さない
            XCTAssertLessThan(spans[2], 45, n.name)
            XCTAssertLessThan(spans[1], 45, n.name)
            XCTAssertLessThan(spans[0], 1, n.name)
        }
        XCTAssertGreaterThanOrEqual(found, 2)
    }

    /// 後ろの壁の額は部屋の内（x≥0）に収まる。外に出ると虚空に写真面が浮く
    func testLeftWallFramesStayInsideTheRoom() throws {
        let doc = CamperRoomRules.starterDocument(camper)
        let frames = doc.all.filter { ($0.furniture?.photoSlots ?? 0) > 0 && $0.w == .left }
        XCTAssertFalse(frames.isEmpty)
        for item in frames {
            let placed = try XCTUnwrap(CamperRoomBuilder.place(item), item.k)
            XCTAssertEqual(placed.yaw, .pi / 2, accuracy: 0.001, item.k)
            let mesh = try XCTUnwrap(CamperRoomFurnitureModels.mesh(item.k), item.k)
            let q = CQuat.axisAngle(CV3(0, 1, 0), placed.yaw)
            let world = mesh.positions.map { placed.position + q.rotate($0) }
            let minX = try XCTUnwrap(world.map(\.x).min())
            XCTAssertGreaterThanOrEqual(minX, -0.05, item.k)
        }
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
        // 灯りの家具は図鑑に何百もある。上限の試験は、上限を超える少数を置けば足りる
        let lit = Array(CamperRoomCatalog.all.filter { $0.lit && $0.built }.prefix(12))
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
        // 夜の指向光は消す（残すと窓から昼の光が差し込む・2026-10-19 owner）
        XCTAssertEqual(night.sun, 0, accuracy: 0.5)
        XCTAssertFalse(sun.light?.castsShadow == true)
        // 夜の値は外の車の夜にそろえる（露出 −0.15・周りの光は外より弱く）。環境光は灯りの外が真っ黒にならない程度
        XCTAssertEqual(night.environment, 0.06, accuracy: 0.001)
        XCTAssertEqual(night.ambient, 38, accuracy: 0.5)
        XCTAssertEqual(Double(scene.cameraNode.camera?.exposureOffset ?? 0), -0.15, accuracy: 0.001)
        // 灯りの落ち方はなだらか（芯の白い丸を避ける・2026-10-20）
        for n in lamps {
            XCTAssertEqual(Double(n.light?.attenuationFalloffExponent ?? 0), 1.2, accuracy: 0.01)
            XCTAssertGreaterThan(Double(n.light?.attenuationStartDistance ?? 0), 0)
        }
        scene.setMood(.day)
        XCTAssertEqual(scene.lightingSnapshot.lampsShown, 0)
        XCTAssertTrue(sun.light?.castsShadow == true)
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
