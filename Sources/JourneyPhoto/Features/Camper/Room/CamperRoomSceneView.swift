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
    let selected: String?
    /// 持ち上げて動かしている家具（動かした先）と、置けるか
    let drag: CamperRoomItem?
    let dragCheck: CamperRoomCheck?
    let photoImages: [String: UIImage]
    var studio = false
    var onReady: (String) -> Void = { _ in }

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
        view.scene = c.scene
        view.pointOfView = c.cameraNode
        c.onReady = { marker in DispatchQueue.main.async { onReady(marker) } }
        c.setCamera(camera, animated: false)
        c.setMood(mood)
        c.show(layout: layout, doc: doc, paint: paint)
        c.setPhotoImages(photoImages)
        c.setEditing(editing)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        c.show(layout: layout, doc: doc, paint: paint)
        c.setMood(mood)
        c.setCamera(camera, animated: animateCamera)
        c.setPhotoImages(photoImages)
        c.setEditing(editing)
        c.setSelected(drag == nil ? selected : nil)
        c.setDrag(drag, check: dragCheck)
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

    /// 額に入っている写真を読む（読めた・読んでいる最中のものは読まない）
    func load(_ ids: [String], from photos: [Photo]) {
        for id in Set(ids) where images[id] == nil && !inFlight.contains(id) {
            guard let url = photos.first(where: { $0.id == id })?.gridImageURL else { continue }
            inFlight.insert(id)
            Task {
                let data = try? await ProfileImageFromPhoto.download(url)
                inFlight.remove(id)
                if let data, let image = UIImage(data: data) { images[id] = image }
            }
        }
    }
}
