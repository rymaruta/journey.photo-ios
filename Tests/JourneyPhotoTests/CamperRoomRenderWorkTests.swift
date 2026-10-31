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
        update(scene, doc, images: ["p1": UIImage(), "p2": UIImage()], camera: camera)
        XCTAssertGreaterThan(scene.photoApplies, applies, "読めた写真が増えたのに額に付け直さない")
        XCTAssertGreaterThan(scene.renderKicks, kicks)
        // 写真を飾る場面に入った
        let kicks2 = scene.renderKicks
        update(scene, doc, images: ["p1": UIImage(), "p2": UIImage()], camera: camera, photosMode: true)
        XCTAssertGreaterThan(scene.renderKicks, kicks2, "写真を飾る場面に入ったのに描き直さない")
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
