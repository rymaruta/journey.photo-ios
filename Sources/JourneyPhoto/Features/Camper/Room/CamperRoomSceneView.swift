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
    /// 見本の起動の試験用: 額の印画の様子（`CamperRoomScene.photoProbe`）。nil なら測らない。
    /// **`onReady` より前に置く**（後ろに置くと、Swift 5 の後ろから合わせる規則で、末尾の閉包 `{ ready = $0 }` が
    /// こちらに渡り、図鑑の寄りが「組み終えた」を出さなくなった・Mac run 654）
    var onProbe: ((String) -> Void)?
    var onReady: (String) -> Void = { _ in }
    /// 額の中身が替わった（保存した中身・選んだだけの見本。額の uid → 写真 id・UI テストの読み上げの値に出す・2026-10-22）
    var onFramed: (_ framed: [String: String], _ previewed: [String: String]) -> Void = { _, _ in }
    /// 組み上がった後の最初のコマを描いた（外から入る時の覆いを消す合図・2026-10-21）
    var onDrawn: () -> Void = {}

    /// 輪郭のなめらかさ（2026-10-28 判断・重さの直し・owner 承認）。4 倍から 2 倍へ。家具の縁が少し粗くなる。
    /// 家具の接写の一覧（`CamperRoomContactSheet`）は画面の外で 1 回描くだけなので 4 倍のまま
    static let antialiasing: SCNAntialiasingMode = .multisampling2X

    func makeCoordinator() -> CamperRoomScene { CamperRoomScene() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = PreviewSession.camperAntialiasing(default: Self.antialiasing)
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
        CamperRenderMeter.shared.mark("A1viewMade", vm: true)
        // 組み上がった後の最初のコマを知らせる（Mac run 646: 組み上がった合図から実際に描くまで、シミュレーターでは数秒かかった）
        let watcher = CamperFirstFrame()
        // PR #364 の検証（Mac が重い回）: 描いた知らせの時点で、SCNView がまだ画面に大きさを持っていない・部屋が組み上がって
        // いないことがあった見立て。組み上がり、画面に載った後のコマを 2 枚描いてから知らせる。まだなら次のコマを待つ
        // 🔴 見張りの中から見張り自身を強く掴まない（掴むと `onDrawn` と見張りが循環して解放されない・2026-11-07）。
        // 見張りを持ち続けるのは `c.firstFrame`（型は `AnyObject?` の強い参照）と `c.onReady`・`c.frameMeter`——
        // 部屋の画面が生きている間は残り、`dismantleUIView` で切る。作り方は `CamperFirstFrame.connect`
        watcher.connect(isShowing: { [weak c] in
            guard let c else { return nil }
            return c.isShowingRoom
        }, requestRender: { [weak c] in c?.requestRender() }, onDrawn: {
            CamperRenderMeter.shared.mark("C1firstFrame", vm: true)
            onDrawn()
        })
        c.firstFrame = watcher
        // 計測（`-JPPreviewCamperPerf YES`）のときだけ、1 コマの時間を測り、描いた後を見張りへ渡す（2026-10-31・#430・
        // `CamperFrameMeter`）。本番では見張りをそのまま delegate にする（描く糸に何も足さない・#430 の見直し）
        if CamperRenderMeter.shared.enabled {
            let meter = CamperFrameMeter("CamperRoomFrame", next: watcher)
            c.frameMeter = meter
            view.delegate = meter
        } else {
            view.delegate = watcher
        }
        c.onReady = { marker in
            watcher.arm()
            DispatchQueue.main.async { onReady(marker) }
        }
        c.onFramed = { framed, previewed in
            DispatchQueue.main.async { onFramed(framed, previewed) }
        }
        if let onProbe { c.onProbe = { probe in DispatchQueue.main.async { onProbe(probe) } } }
        c.setCamera(camera, animated: false)
        c.setMood(mood)
        c.show(layout: layout, doc: doc, paint: paint)
        c.setPhotoImages(photoImages)
        c.setPhotosMode(photosMode, focus: focusFrame, preview: previewPhotoId)
        c.setEditing(editing)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // 値渡しの段ごとに印を付けて測る（2026-10-31・#430）
        CamperRenderMark.measure("CamperRoomUpdate") {
            let c = context.coordinator
            c.attach(view)
            CamperRenderMark.measure("CamperRoomShow") { c.show(layout: layout, doc: doc, paint: paint) }
            c.setMood(mood)
            CamperRenderMark.measure("CamperRoomSetCamera") { c.setCamera(camera, animated: animateCamera) }
            CamperRenderMark.measure("CamperRoomPhotoImages") { c.setPhotoImages(photoImages) }
            CamperRenderMark.measure("CamperRoomPhotosMode") { c.setPhotosMode(photosMode, focus: focusFrame, preview: previewPhotoId) }
            c.setEditing(editing)
            c.setSelected(drag == nil ? selected : nil)
            c.setDrag(drag, check: dragCheck)
            c.setHints(hints)
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: CamperRoomScene) {
        (coordinator.firstFrame as? CamperFirstFrame)?.disconnect()
        coordinator.cancel()
    }
}

/// 額に入れる自分の写真を読む（投稿の写真の一覧の縮小版。読めたものから額に入る）。
/// 写真は自分の投稿の一覧（`CamperPhotoLoader`・マイページと同じ口）から渡される。ここは絵を取るだけ
@MainActor
final class CamperRoomPhotoImages: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    /// 読めなかった写真（飾る画面に「読み込めませんでした」を出す。読めたら消える）
    @Published private(set) var failed = Set<String>()
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
            guard let url = photos.first(where: { $0.id == id })?.gridImageURL else {
                // 一覧に無い写真（消した・まだ届いていない）。黙って白い額にしない
                failed.insert(id)
                continue
            }
            inFlight.insert(id)
            Task {
                let data = try? await ProfileImageFromPhoto.download(url)
                inFlight.remove(id)
                if let data, let image = UIImage(data: data) {
                    failedAt[id] = nil
                    failed.remove(id)
                    images[id] = image
                } else {
                    failedAt[id] = Date()
                    failed.insert(id)
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

    /// 数えるだけの入れ物（主スレッドからだけ触る）
    private final class Counter: @unchecked Sendable { var value = 0 }

    /// 組み上がった後の最初のコマを知らせる配線。**組み上がり、画面に載った後のコマを `framesNeeded` 枚描いてから**
    /// `onDrawn` を呼ぶ（まだなら次のコマを待つ）。`isShowing` が nil を返したら（部屋の持ち主が居ない）何もしない。
    /// 🔴 `self` は弱く掴む——強く掴むと `onDrawn` と循環して解放されない
    /// 渡す閉包は **`@MainActor`**(部屋の `isShowingRoom`・`requestRender()` は主スレッドの持ち物)。呼ぶのは下の
    /// `DispatchQueue.main.async` の中だけ——元のコード(`[weak c]` の閉包)が同じ場所で `c` を触っていたのと同じ作り
    func connect(framesNeeded: Int = 2, isShowing: @escaping @MainActor () -> Bool?,
                 requestRender: @escaping @MainActor () -> Void, onDrawn done: @escaping @MainActor () -> Void) {
        let counter = Counter()
        onDrawn = { [weak self] in
            DispatchQueue.main.async {
                guard let self, let showing = isShowing() else { return }
                if showing {
                    counter.value += 1
                    if counter.value >= framesNeeded {
                        done()
                        return
                    }
                }
                self.arm()
                requestRender()
            }
        }
    }

    /// 配線を切る（部屋の画面を外すとき）
    func disconnect() {
        lock.lock()
        armed = false
        lock.unlock()
        onDrawn = nil
    }

    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        fireIfArmed()
    }

    /// 描いた後の知らせ（`renderer` から。試験は直に呼ぶ）
    func fireIfArmed() {
        lock.lock()
        let fire = armed
        armed = false
        lock.unlock()
        if fire { onDrawn?() }
    }
}
#endif
