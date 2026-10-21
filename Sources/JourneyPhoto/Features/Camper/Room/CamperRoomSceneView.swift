import SwiftUI
import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif

// Linux では URLSession が別モジュールに居る（`ProfileImageFromPhoto` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// とおまわり号の中を描く SCNView（指の動きは SwiftUI の側が受けて、カメラと文書の値で渡す）
struct CamperRoomSceneView: UIViewRepresentable {
    let layout: CamperRoomLayout
    let doc: CamperRoomDocument
    let paint: UInt32
    let mood: CamperMood
    let camera: CamperRoomCamera
    let animateCamera: Bool
    let editing: Bool
    /// 写真を飾る場面（天井の換気窓などを隠し、選んだ額を光らせる）
    let photosMode: Bool
    /// 選んでいる額（写真を飾る場面の強調）と、まだ保存していない見本の写真 id
    let focusFrame: String?
    let previewPhotoId: String?
    let selected: String?
    /// 持ち上げて動かしている家具（動かした先）と、置けるか
    let drag: CamperRoomItem?
    let dragCheck: CamperRoomCheck?
    let photoImages: [String: UIImage]
    var studio = false
    /// 押して置くときの置ける所（薄い白のマス）
    var hints: CamperRoomFitArea?
    var onReady: (String) -> Void = { _ in }
    /// 組み上がった後の最初のコマを描いた（外から入る時の覆いを消す合図・2026-10-21）
    var onDrawn: () -> Void = {}

    func makeCoordinator() -> CamperRoomScene { CamperRoomScene() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        #if canImport(SceneKit)
        // 光る面を SDR の白より明るく出さない（外の車と同じ・2026-10-19 owner「夜の発光の仕方ひどい」）
        if #available(iOS 16.0, *), let metal = view.layer as? CAMetalLayer {
            metal.wantsExtendedDynamicRangeContent = false
        }
        #endif
        let c = context.coordinator
        c.studio = studio
        c.attach(view)
        view.scene = c.scene
        view.pointOfView = c.cameraNode
        // 組み上がった後の最初のコマを知らせる（Mac run 646: 組み上がった合図から実際に描くまで、シミュレーターでは数秒かかった）
        let watcher = CamperFirstFrame()
        watcher.onDrawn = { DispatchQueue.main.async { onDrawn() } }
        c.firstFrame = watcher
        view.delegate = watcher
        c.onReady = { marker in
            watcher.arm()
            DispatchQueue.main.async { onReady(marker) }
        }
        c.setCamera(camera, animated: false)
        c.setMood(mood)
        c.show(layout: layout, doc: doc, paint: paint)
        c.setPhotoImages(photoImages)
        c.setPhotosMode(photosMode, focus: focusFrame, preview: previewPhotoId)
        c.setEditing(editing)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        c.attach(view)
        c.show(layout: layout, doc: doc, paint: paint)
        c.setMood(mood)
        c.setCamera(camera, animated: animateCamera)
        c.setPhotoImages(photoImages)
        c.setPhotosMode(photosMode, focus: focusFrame, preview: previewPhotoId)
        c.setEditing(editing)
        c.setSelected(drag == nil ? selected : nil)
        c.setDrag(drag, check: dragCheck)
        c.setHints(hints)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: CamperRoomScene) {
        coordinator.cancel()
    }
}

/// 額に入れる自分の写真を読む（投稿の写真の一覧の縮小版。読めたものから額に入る）。
/// 写真は自分の投稿の一覧（`CamperPhotoLoader`・マイページと同じ口）から渡される。ここは絵を取るだけ
@MainActor
final class CamperRoomPhotoImages: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    private var inFlight = Set<String>()
    /// 一度失敗した id（読み直しの間隔を空ける。同じ失敗を毎フレーム繰り返さない）
    private var failedAt: [String: Date] = [:]

    /// 額に入れる／選ぶ写真を読む（飾る画面では一覧の分も先に読む。読めた・読んでいる最中のものは読まない）
    func load(_ ids: [String], from photos: [Photo], force: Bool = false) {
        let now = Date()
        for id in Set(ids) {
            if images[id] != nil { continue }
            if inFlight.contains(id) { continue }
            if !force, let at = failedAt[id], now.timeIntervalSince(at) < 2 { continue }
            guard let url = photos.first(where: { $0.id == id })?.gridImageURL else { continue }
            inFlight.insert(id)
            Task {
                let data = try? await ProfileImageFromPhoto.download(url)
                inFlight.remove(id)
                if let data, let image = UIImage(data: data) {
                    failedAt[id] = nil
                    images[id] = image
                } else {
                    failedAt[id] = Date()
                }
            }
        }
    }
}

#if canImport(SceneKit) || canImport(SceneKitShim)
/// 組み上がった後の最初のコマを描いたら 1 回だけ知らせる（描くのは SceneKit の描画の糸）
final class CamperFirstFrame: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    var onDrawn: (@Sendable () -> Void)?

    func arm() {
        lock.lock()
        armed = true
        lock.unlock()
    }

    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        let fire = armed
        armed = false
        lock.unlock()
        if fire { onDrawn?() }
    }
}
#endif
