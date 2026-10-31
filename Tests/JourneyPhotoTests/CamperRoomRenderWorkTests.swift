import XCTest
import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif
@testable import JourneyPhoto

/// とおまわり号の中: 指で回す値渡し（`updateUIView`）のたびに、変わっていない額の印画を付け直さない・
/// 止まっている SCNView を起こさない（2026-10-31・#430・Mac run 792 で回す 1 回の値渡しに印画の付け直し 18 回・起こし 2 回）
@MainActor
final class CamperRoomRenderWorkTests: XCTestCase {

    private let layout = CamperRoomLayout.make(.car, stage: .camper)
    /// 場面は SCNView を弱く持つので、試験の間ここで持つ
    private var view: SCNView?

    private func makeScene() -> (CamperRoomScene, CamperRoomDocument) {
        let doc = CamperRoomRules.starterDocument(layout)
        let scene = CamperRoomScene()
        let view = SCNView(frame: .zero)
        self.view = view
        scene.attach(view)
        scene.installNow(layout: layout, doc: doc, paint: 0x5B6168)
        return (scene, doc)
    }

    /// 値渡しと同じ順で呼ぶ（`CamperRoomSceneView.updateUIView`）
    private func update(_ scene: CamperRoomScene, _ doc: CamperRoomDocument, images: [String: UIImage], camera: CamperRoomCamera,
                        photosMode: Bool = false) {
        scene.show(layout: layout, doc: doc, paint: 0x5B6168)
        scene.setMood(.day)
        scene.setCamera(camera, animated: false)
        scene.setPhotoImages(images)
        scene.setPhotosMode(photosMode, focus: nil, preview: nil)
    }

    func testRotatingDoesNotReapplyPhotosOrKickTheView() async {
        let (scene, doc) = makeScene()
        let images = ["p1": UIImage(), "p2": UIImage()]
        update(scene, doc, images: images, camera: CamperRoomCamera())
        let applies = scene.photoApplies, kicks = scene.renderKicks
        for i in 1...30 {
            update(scene, doc, images: images, camera: CamperRoomCamera().dragged(dx: Double(i) * 4, dy: 0))
        }
        XCTAssertEqual(scene.photoApplies, applies, "回すだけの値渡しで額の印画を付け直した")
        XCTAssertEqual(scene.renderKicks, kicks, "回すだけの値渡しで止まっている SCNView を起こした")
    }

    func testNewPhotosAndPhotoModeChangesStillApply() async {
        let (scene, doc) = makeScene()
        let camera = CamperRoomCamera()
        update(scene, doc, images: ["p1": UIImage()], camera: camera)
        let applies = scene.photoApplies, kicks = scene.renderKicks
        // 読めた写真が 1 枚増えた
        let images = ["p1": UIImage(), "p2": UIImage()]
        update(scene, doc, images: images, camera: camera)
        XCTAssertGreaterThan(scene.photoApplies, applies, "読めた写真が増えたのに額に付け直さない")
        XCTAssertGreaterThan(scene.renderKicks, kicks)
        // 写真を飾る場面に入った（絵の辞書は同じ物を使い回す。iOS では新しい UIImage は別の絵として付け直しになり、
        // 場面に入ったことの描き直しかどうかを見分けられない・#430 の見直し）
        let kicks2 = scene.renderKicks
        update(scene, doc, images: images, camera: camera, photosMode: true)
        XCTAssertGreaterThan(scene.renderKicks, kicks2, "写真を飾る場面に入ったのに描き直さない")
    }

    private func all(_ n: SCNNode) -> [SCNNode] { [n] + n.childNodes.flatMap { all($0) } }

    /// 左の壁（後ろの端の壁）の家具の節を、取り消し・やり直し・自動で置いて新しく作ったとき、後ろ壁を切った向きでは隠す。
    /// 値渡しのたびの `setPhotosMode` を変わった時だけにした後も（#430 の見直し・見直し役の再現）。
    /// 同じ試験で、回すだけの値渡しが額の付け直し・起こしをしないこと（run 798 の 7,470 → 0）も確かめる
    func testRecreatedLeftWallItemIsHiddenWhenTheRearWallIsCut() async throws {
        let (scene, doc) = makeScene()
        let left = try XCTUnwrap(doc.all.first { $0.w == .left }, "見本に左の壁の家具が無い")
        var without = doc
        without.items.removeAll { $0.u == left.u }
        without.ceil.removeAll { $0.u == left.u }
        scene.replaceItemsNow(without)
        var camera = CamperRoomCamera()
        camera.yaw = -20
        XCTAssertFalse(camera.cutsFrontEnd)
        let images = ["p1": UIImage()]
        update(scene, without, images: images, camera: camera)
        // 取り消しで左の壁の家具が戻る
        scene.replaceItemsNow(doc)
        scene.setPhotosMode(false, focus: nil, preview: nil)
        let holder = try XCTUnwrap(all(scene.scene.rootNode).first { $0.name == "item.\(left.u)" })
        XCTAssertTrue(holder.isHidden, "切った後ろ壁の家具が、作り直した後に見えている（壁の上に浮く）")
        // 回すだけの値渡し（後ろ壁を切ったまま）では、付け直し・起こしをしない
        let afterUndo = (scene.photoApplies, scene.renderKicks)
        for i in 1...20 {
            camera.yaw = -20 - Double(i)
            update(scene, doc, images: images, camera: camera)
        }
        XCTAssertTrue(holder.isHidden)
        XCTAssertEqual(scene.photoApplies, afterUndo.0, "回すだけの値渡しで額の印画を付け直した")
        XCTAssertEqual(scene.renderKicks, afterUndo.1, "回すだけの値渡しで止まっている SCNView を起こした")
    }

    /// 文書の側で額の写真が替わったら、付け直して止まっている SCNView を起こす（#430 の見直し）
    func testDocPhotoChangeKicksTheView() async throws {
        let (scene, doc) = makeScene()
        let frame = try XCTUnwrap(doc.all.first { $0.k.hasPrefix("photo_frame.") }, "見本に額が無い")
        let images = ["p1": UIImage()]
        update(scene, doc, images: images, camera: CamperRoomCamera())
        let kicks = scene.renderKicks
        var hung = doc
        var item = frame
        item.p = "p1"
        hung.upsert(item)
        // 文書を家具に合わせる（`syncItems`。`installNow` の鍵は "now" なので、`show` は組み直しを始めて合わせない）
        scene.replaceItemsNow(hung)
        XCTAssertGreaterThan(scene.renderKicks, kicks, "額の写真を替えたのに描き直さない")
    }

    func testSameEntriesComparesIdentity() async {
        final class Box {}
        let a = Box(), b = Box()
        XCTAssertTrue(CamperRoomScene.sameEntries(["x": a], ["x": a]) { $0 === $1 })
        XCTAssertFalse(CamperRoomScene.sameEntries(["x": a], ["x": b]) { $0 === $1 }, "読み直した絵（別の物）を同じと見た")
        XCTAssertFalse(CamperRoomScene.sameEntries(["x": a], ["x": a, "y": b]) { $0 === $1 })
        XCTAssertFalse(CamperRoomScene.sameEntries(["x": a], ["y": a]) { $0 === $1 })
    }
}
