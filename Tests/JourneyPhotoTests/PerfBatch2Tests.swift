import XCTest
import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif
@testable import JourneyPhoto

/// 見た目が少し変わる重さの直し（2026-10-28・owner 承認）:
/// ホームの札のガラスの丸を外し、札が見る store を絞る／地図のピンの影を外す／
/// とおまわり号の中の形の使い回し・影・MSAA・`SCNView.prepare`
final class PerfBatch2Tests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(path),
                          encoding: .utf8)
    }

    /// 注記の行を除いたコード（注記に `.ultraThinMaterial` と書いてあっても数えない）
    private func code(_ path: String) throws -> String {
        try source(path).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func between(_ text: String, _ from: String, _ to: String) throws -> String {
        let a = try XCTUnwrap(text.range(of: from), "見つからない: \(from)")
        let b = try XCTUnwrap(text.range(of: to, range: a.upperBound..<text.endIndex), "見つからない: \(to)")
        return String(text[a.lowerBound..<b.lowerBound])
    }

    // MARK: - ホームの札

    /// ガラス（ぼかし）を外し、黒 55% の丸だけにする（いいね・「…」の両方）
    func testHomeTileCirclesHaveNoGlass() throws {
        let mosaic = try code("Features/Gallery/HomeMosaic.swift")
        XCTAssertFalse(mosaic.contains("Material"), "ホームの札にぼかしの材質が残っている")
        XCTAssertTrue(mosaic.contains(".background(Color.black.opacity(0.55), in: Capsule())"), "いいねの丸の地が無い")
        XCTAssertTrue(mosaic.contains(".background(Color.black.opacity(0.55), in: Circle())"), "「…」の丸の地が無い")
    }

    /// 札そのものはログインだけを見る。いいね・ブロックの store は、それを使う小さな部品だけが見る
    func testHomeTileObservesOnlyWhatItNeeds() throws {
        let mosaic = try code("Features/Gallery/HomeMosaic.swift")
        let tile = try between(mosaic, "struct HomeFeedTile: View {", "struct HomeTileMoreMenu: View {")
        XCTAssertEqual(tile.components(separatedBy: "@EnvironmentObject").count - 1, 1, "札が見る store が増えている")
        XCTAssertTrue(tile.contains("@EnvironmentObject private var auth: AuthStore"))
        for store in ["FavoritesStore", "LikeCountStore", "ModerationStore", "ToastCenter", "AppEnvironment"] {
            XCTAssertFalse(tile.contains(store), "札が \(store) を見ている（♥やブロックのたびに札が全部描き直される）")
        }
        XCTAssertTrue(tile.contains("HomeTileLikeButton(photo: photo)"))
        XCTAssertTrue(tile.contains("HomeTileMoreMenu(photo: photo, ownerId: ownerId, onReport: onReport)"))

        let menu = try between(mosaic, "struct HomeTileMoreMenu: View {", "struct HomeTileLikeButton: View {")
        XCTAssertTrue(menu.contains("@EnvironmentObject private var hidden: ModerationStore"))
        XCTAssertFalse(menu.contains("FavoritesStore") || menu.contains("LikeCountStore"))

        let like = try between(mosaic, "struct HomeTileLikeButton: View {", "enum HomeTileText")
        XCTAssertTrue(like.contains("@EnvironmentObject private var favorites: FavoritesStore"))
        XCTAssertTrue(like.contains("@EnvironmentObject private var likeCounts: LikeCountStore"))
        XCTAssertFalse(like.contains("ModerationStore"))
    }

    // MARK: - 地図のピン

    /// 撮影スポットの印・みんなの写真のピンに影を付けない
    func testMapPinsHaveNoShadow() throws {
        XCTAssertFalse(try code("Features/Map/SpotMapMarker.swift").contains(".shadow("), "撮影スポットのピンに影が残っている")
        let map = try code("Features/Map/PhotoMapView.swift")
        let frame = try between(map, "private static func photoPinFrame<", "private func cameraChanged(")
        XCTAssertFalse(frame.contains(".shadow("), "みんなの写真のピンに影が残っている")
        XCTAssertTrue(frame.contains(".background(Color.white, in: RoundedRectangle(cornerRadius: photoPinRadius))"),
                      "白い札の縁が無い（影を外した代わりの見分け）")
    }

    // MARK: - とおまわり号の中

    /// MSAA は 2 倍
    func testRoomAntialiasingIsTwoX() throws {
        XCTAssertEqual(CamperRoomSceneView.antialiasing, .multisampling2X)
        let view = try code("Features/Camper/Room/CamperRoomSceneView.swift")
        XCTAssertTrue(view.contains("view.antialiasingMode = Self.antialiasing"))
        XCTAssertFalse(view.contains(".multisampling4X"))
    }
}

@MainActor
final class PerfBatch2RoomSceneTests: XCTestCase {

    private let layout = CamperRoomLayout.make(.car, stage: .camper)

    private func all(_ n: SCNNode) -> [SCNNode] { [n] + n.childNodes.flatMap { all($0) } }

    private func body(_ scene: CamperRoomScene, _ uid: String) throws -> SCNNode {
        let holder = try XCTUnwrap(all(scene.scene.rootNode).first { $0.name == "item.\(uid)" }, uid)
        return try XCTUnwrap(holder.childNodes.first { $0.name == "body" }, uid)
    }

    private func isFrame(_ k: String) -> Bool { k.hasPrefix("photo_frame.") }

    /// 影を落とす光は昼の太陽だけ。太陽の影の絵は 1024・ぼかし 8。夜の灯りは影を落とさない
    func testOnlyTheSunCastsShadowsAndItsMapIsSmaller() async throws {
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        scene.installNow(layout: layout, doc: doc, paint: 0x5B6168)
        let sun = try XCTUnwrap(all(scene.scene.rootNode).first { $0.light?.type == .directional }?.light)
        XCTAssertEqual(sun.shadowMapSize.width, 1024)
        XCTAssertEqual(sun.shadowMapSize.height, 1024)
        XCTAssertEqual(sun.shadowSampleCount, 8)
        XCTAssertFalse(CamperRoomScene.lampsCastShadows)
        scene.setMood(.night)
        let lamps = all(scene.scene.rootNode).filter { $0.name?.hasPrefix("light.") == true }.compactMap(\.light)
        XCTAssertFalse(lamps.isEmpty)
        for l in lamps { XCTAssertFalse(l.castsShadow, "夜の灯りが影を落としている") }
    }

    /// 家具の形は種類ごとに 1 つ。外して置き直しても作り直さない。額だけは写し（材質が額ごと）
    func testFurnitureGeometryIsSharedAndFramesGetTheirOwnCopy() async throws {
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        scene.installNow(layout: layout, doc: doc, paint: 0x5B6168)
        let builds = scene.geometryBuilds
        let kinds = Set(doc.all.map(\.k))
        XCTAssertLessThanOrEqual(builds, kinds.count * 2, "家具ごとに形を作っている")
        var before: [String: SCNGeometry] = [:]
        for it in doc.all { before[it.u] = try body(scene, it.u).geometry }

        // 全部外して置き直す
        scene.replaceItemsNow(CamperRoomDocument(room: layout.kind))
        XCTAssertTrue(all(scene.scene.rootNode).filter { $0.name?.hasPrefix("item.") == true }.isEmpty)
        scene.replaceItemsNow(doc)
        XCTAssertEqual(scene.geometryBuilds, builds, "置き直しで形を頂点から作り直した")

        var frames = 0
        for it in doc.all {
            let now = try XCTUnwrap(try body(scene, it.u).geometry)
            let old = try XCTUnwrap(before[it.u])
            if isFrame(it.k) {
                frames += 1
                // 額は写し（同じ形を共有すると、片方の印画がもう片方に乗る）
                XCTAssertFalse(now === old, "額の形を前の額と共有している: \(it.k)")
            } else {
                XCTAssertTrue(now === old, "同じ家具の形を作り直した: \(it.k)")
            }
        }
        XCTAssertGreaterThan(frames, 0, "見本に額が無い（額の写しを確かめられない）")
    }

    /// 組んだ殻と家具の形は、場面に入れる前に `SCNView.prepare` に渡す
    func testShowPreparesShellAndFurnitureBeforeInstall() async throws {
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        let view = SCNView(frame: .zero)
        scene.attach(view)
        var markers: [String] = []
        scene.onReady = { markers.append($0) }
        scene.show(layout: layout, doc: doc, paint: 0x5B6168)
        // 同じ鍵でもう一度呼んでも、組み直しを始め直さない
        scene.show(layout: layout, doc: doc, paint: 0x5B6168)
        for _ in 0..<2400 where markers.isEmpty { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertEqual(markers.count, 1, "組み終えた合図が出ない／二度出た")
        // 同じ鍵の 2 回目で組み直しを始め直さない（`if key == buildingKey { return }`・確かめ役）
        XCTAssertEqual(scene.buildsStarted, 1, "同じ鍵の組み直しを始め直した")
        // 渡した物を覚えているのは模型（`SceneKitShim` の `SCNView.prepared`）だけ。本物の SceneKit では
        // 組み終えた合図が 1 回出ること（prepare の答えを待っても止まらない）までを見る（Mac run 709 で判明）
        #if !canImport(SceneKit)
        let prepared = view.prepared.compactMap { $0 as? SCNNode }
        XCTAssertFalse(prepared.isEmpty, "prepare に何も渡していない")
        // 殻（見せ方の組）は prepare に渡したものがそのまま場面に入る
        let shell = all(scene.scene.rootNode).filter { $0.name == "room.always" }
        XCTAssertEqual(shell.count, 1)
        XCTAssertTrue(prepared.contains { $0 === shell[0] }, "場面に入れた殻を prepare に渡していない")
        // 家具の形も渡す（置いた家具は渡した形を使う）
        let bed = try XCTUnwrap(doc.all.first { $0.k == "bed.platform" })
        let bedGeometry = try XCTUnwrap(try body(scene, bed.u).geometry)
        XCTAssertTrue(prepared.contains { $0.geometry === bedGeometry }, "家具の形を prepare に渡していない")
        // 殻を渡したのは 1 回だけ（始め直していない）
        XCTAssertEqual(view.prepared.filter { ($0 as? SCNNode)?.name == "room.always" }.count, 1)
        #endif
    }

    #if !canImport(SceneKit)
    /// prepare の答えが来なくても、待つ上限（`prepareTimeout`）で組み上げを進める（部屋が出ないままにしない）
    func testShowFinishesWhenPrepareNeverAnswers() async throws {
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        let view = SCNView(frame: .zero)
        view.answersPrepare = false
        scene.attach(view)
        var markers: [String] = []
        scene.onReady = { markers.append($0) }
        scene.show(layout: layout, doc: doc, paint: 0x5B6168)
        for _ in 0..<2400 where markers.isEmpty { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertEqual(markers.count, 1, "prepare が答えないと部屋が組み上がらない")
        XCTAssertFalse(view.prepared.isEmpty)
        XCTAssertEqual(all(scene.scene.rootNode).filter { $0.name == "room.always" }.count, 1)
    }
    #endif

    /// 組み直しの途中で取り消したら、次に同じ部屋を見せる時は組み直す（材質の控えが作り直し途中のまま
    /// 家具だけを合わせない・`cancel()` で `builtKey` を忘れる）
    func testCancelForgetsTheBuiltRoom() async throws {
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        var markers: [String] = []
        scene.onReady = { markers.append($0) }
        scene.show(layout: layout, doc: doc, paint: 0x5B6168)
        for _ in 0..<2400 where markers.isEmpty { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(scene.buildsStarted, 1)
        // 組み上がった部屋をもう一度: 組み直さない
        scene.show(layout: layout, doc: doc, paint: 0x5B6168)
        XCTAssertEqual(scene.buildsStarted, 1)
        // 別の塗装で組み直し始めて、途中で取り消す
        scene.show(layout: layout, doc: doc, paint: 0x123456)
        XCTAssertEqual(scene.buildsStarted, 2)
        scene.cancel()
        // 元の部屋に戻す: 材質を作り直し始めていたので、組み直す
        scene.show(layout: layout, doc: doc, paint: 0x5B6168)
        XCTAssertEqual(scene.buildsStarted, 3, "取り消した後に、作り直し途中の材質のまま家具だけを合わせた")
        for _ in 0..<2400 where markers.count < 2 { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertEqual(markers.count, 2)
    }
}
