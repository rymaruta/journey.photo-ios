import AVFoundation
import AVKit
import Photos
import SwiftUI
import UIKit

/// 「作例を重ねて撮る」のカメラ（AVFoundation・2026-10-09）。
///
/// 投稿のカメラ（`CameraPicker`）は OS の撮影画面（`UIImagePickerController`）で、上に作例を
/// 重ねられない。ここは自前の撮影の場（`AVCaptureSession`）で、映像（`CameraPreview`）の上に
/// SwiftUI で作例・三分割の線・案内を重ねる。
///
/// - 許可: 開いたときに確かめる。まだ尋ねていなければ尋ねる（`NSCameraUsageDescription` は既にある）。
///   **端末にカメラが無い（シミュレータ）なら尋ねずに「使えません」**
/// - 撮影の場の組み立て・開始・停止は**画面の処理の外**（専用の列）で行う（`startRunning` は
///   重く、主スレッドで呼ぶと画面が止まる。Apple の注記どおり）
/// - 撮った1枚はファイルの中身（HEIF・JPEG）のまま写真に足す（`save`・追加だけの許可
///   `NSPhotoLibraryAddUsageDescription`）。位置情報は付けない（撮影の場に位置を渡していない）
///
/// - **構図の線・作例は写真に焼き込まない**（2026-10-10）。重ねは SwiftUI の上だけで、撮る1枚は
///   カメラの出力（`AVCapturePhotoOutput`）そのもの
/// - 撮る向きは端末の向きに合わせる（`AVCaptureDevice.RotationCoordinator` の
///   `videoRotationAngleForHorizonLevelCapture`・iOS 17〜・2026-10-10）
///
/// **実機のカメラでは確かめていない**（Linux の模型でビルドを通しただけ・PR の注記）。
@MainActor
final class ComposeCamera: ObservableObject {

    @Published private(set) var state: ComposeGuide.CameraState = .preparing
    /// 撮っている最中（シャッターを2度押せないように）
    @Published private(set) var isCapturing = false
    /// 拡大の段（端末のレンズから・2026-10-16）。組み立てるまでは 1× だけ
    @Published private(set) var zoomLevels = ComposeControls.zoomLevels(hasUltraWide: false, switchOver: [],
                                                                         minFactor: 1, maxFactor: 1)
    /// いまのカメラの倍率（`videoZoomFactor`）
    @Published private(set) var zoomFactor = 1.0
    /// 明るさの補正の範囲（EV）。標準のカメラ App にそろえ ±2 に絞る
    @Published private(set) var exposureRange: ClosedRange<Double> = -2...2
    /// 写っているものが大きく変わり、タップで合わせたピントを自動に戻した回数（画面はピントの枠を消す）
    @Published private(set) var focusResetCount = 0
    /// 長押しでピントと明るさを固定しているか
    @Published private(set) var focusLocked = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    /// 撮影の場を触る列（組み立て・開始・停止・撮影）。主スレッドの外
    private let queue = DispatchQueue(label: "photo.journey.compose-camera")
    private var configured = false
    /// 確かめ・組み立ての最中（許可の問い合わせで画面が一度裏に回り、戻ったときにもう一度
    /// `start` が呼ばれる。2つ同時に組み立てると2つ目の入力が足せず「使えません」になる）
    private var starting = false
    /// 撮影中の受け手（撮影の出力は受け手を強く持たないので、終わるまでここで持つ）
    private var pending: [ObjectIdentifier: PhotoCaptureDelegate] = [:]
    /// 端末の向きから撮る向きを決める係（組み立てたあとに作る）
    private var rotation: AVCaptureDevice.RotationCoordinator?
    /// 使っている後ろのカメラ（仮想カメラなら拡大でレンズが切り替わる）
    private var device: AVCaptureDevice?
    private var subjectObserver: NSObjectProtocol?

    /// 後ろのカメラを選ぶ順（2026-10-16）。**仮想カメラ（三眼・二眼）を先に**——拡大の倍率だけで
    /// 超広角・広角・望遠を OS が切り替える（標準のカメラ App と同じ）。無ければ広角1つ
    nonisolated static let backCameraTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
    ]

    nonisolated static func backCamera() -> AVCaptureDevice? {
        for type in backCameraTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    /// 許可を確かめて映像を流し始める。画面が出たときに呼ぶ
    func start() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            state = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        case .denied:
            state = .denied
            return
        case .restricted:
            state = .restricted
            return
        @unknown default:
            state = .unavailable
            return
        }
        state = await run() ? .ready : .unavailable
    }

    /// 映像を止める（画面を閉じた・裏に回った）
    func stop() {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    /// 撮影の場を組み立てて（初回だけ）流す。組み立てられなければ false
    private func run() async -> Bool {
        let session = session, output = output, alreadyConfigured = configured
        let ok: Bool = await withCheckedContinuation { continuation in
            queue.async {
                if !alreadyConfigured {
                    guard let device = Self.backCamera(),
                          let input = try? AVCaptureDeviceInput(device: device) else {
                        continuation.resume(returning: false)
                        return
                    }
                    session.beginConfiguration()
                    session.sessionPreset = .photo
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        continuation.resume(returning: false)
                        return
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    session.commitConfiguration()
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
        if ok {
            configured = true
            if device == nil, let device = Self.backCamera() {
                self.device = device
                prepare(device)
            }
        }
        return ok
    }

    /// 組み立てたカメラから、拡大の段・明るさの範囲・向きの係を作る。始めは 1×（超広角から始めない）
    private func prepare(_ device: AVCaptureDevice) {
        if rotation == nil {
            rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        }
        let ultra = device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera
        let levels = ComposeControls.zoomLevels(
            hasUltraWide: ultra,
            switchOver: device.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue),
            minFactor: Double(device.minAvailableVideoZoomFactor),
            maxFactor: Double(device.maxAvailableVideoZoomFactor))
        zoomLevels = levels
        let lo = max(Double(device.minExposureTargetBias), -2), hi = min(Double(device.maxExposureTargetBias), 2)
        exposureRange = lo <= hi ? lo...hi : 0...0
        setZoom(display: 1, animated: false)
        // 写っているものが大きく変わったら、タップで合わせたピントを自動に戻す（固定していなければ）
        subjectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.subjectAreaChanged() }
        }
    }

    // MARK: - 拡大・ピント・明るさ（2026-10-16・標準のカメラ App にそろえる）

    /// 画面の倍率（0.5×・1×・2× …）へ寄る。段のボタンは滑らかに（`ramp`）、ピンチはそのまま
    func setZoom(display: Double, animated: Bool) {
        setZoom(factor: zoomLevels.factor(display: display), animated: animated)
    }

    func setZoom(factor: Double, animated: Bool) {
        guard let device else { return }
        let target = min(max(factor, zoomLevels.minFactor), zoomLevels.maxFactor)
        zoomFactor = target
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if animated {
                device.ramp(toVideoZoomFactor: CGFloat(target), withRate: 8)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = CGFloat(target)
            }
            device.unlockForConfiguration()
        }
    }

    /// その点（カメラの座標 0〜1・`ComposeControls.devicePoint`）にピントと明るさを合わせる。
    /// `lock` なら合わせたまま固定（AE/AF ロック）。固定しないときは、写っているものが変われば自動に戻る
    func focus(at point: (x: Double, y: Double), lock: Bool) {
        guard let device else { return }
        focusLocked = lock
        let p = CGPoint(x: point.x, y: point.y)
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = p
                // 一度合わせて止まる（固定でもタップでも同じ。違いは下の見張り）
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = p
                device.exposureMode = .autoExpose
            }
            device.setExposureTargetBias(0, completionHandler: nil)
            device.isSubjectAreaChangeMonitoringEnabled = !lock
            device.unlockForConfiguration()
        }
    }

    /// 明るさの補正（EV・範囲の内）
    func setExposureBias(_ bias: Double) {
        guard let device else { return }
        let value = Float(min(max(bias, exposureRange.lowerBound), exposureRange.upperBound))
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.setExposureTargetBias(value, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    /// ピントと明るさを自動（真ん中・合わせ続ける）に戻す。固定も外す
    func resetFocus() {
        guard let device else { return }
        focusLocked = false
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.setExposureTargetBias(0, completionHandler: nil)
            device.isSubjectAreaChangeMonitoringEnabled = false
            device.unlockForConfiguration()
        }
    }

    private func subjectAreaChanged() {
        guard !focusLocked else { return }
        resetFocus()
        focusResetCount += 1
    }

    /// 1枚撮る。撮れた写真（ファイルの中身と撮影情報）。撮れなければ nil
    func capture() async -> ComposeShot? {
        guard state == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let output = output
        // 係の角度は `CGFloat`（本物の SDK）。計算は Double で、つなぎに渡すときに戻す
        let angle = CGFloat(ComposeGuide.captureAngle(
            coordinator: rotation.map { Double($0.videoRotationAngleForHorizonLevelCapture) }))
        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate()
            let key = ObjectIdentifier(delegate)
            delegate.done = { [weak self] shot in
                continuation.resume(returning: shot)
                Task { @MainActor in self?.pending[key] = nil }
            }
            pending[key] = delegate
            queue.async {
                // 2026-10-10 判断: 端末の向きで回す。以前は 90°（縦）決め打ちで、横に持って撮った写真が
                // 横倒しのまま残る疑いがあった（画面は縦だけでも、写真は持った向きで残すのが標準のカメラと同じ）
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }

    /// 撮った1枚を端末の写真に足す（追加だけの許可）
    static func save(_ data: Data) async -> ComposeGuide.SaveOutcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}

/// 撮れた1枚（ファイルの中身＝HEIF か JPEG と、カメラが付けた撮影情報）。
/// 投稿へ進めるときは `cameraCapture` で投稿のカメラと同じ形（`CameraCapture`）にする
struct ComposeShot: @unchecked Sendable {
    let data: Data
    let metadata: [String: Any]
    let capturedAt: Date

    /// 投稿画面に渡す形。`ImagePreparer` が JPEG に焼き直す（HEIF のままでも読める）
    var cameraCapture: CameraCapture {
        let data = data
        return CameraCapture(metadata: CameraCapture.metadata(from: metadata), capturedAt: capturedAt,
                             encode: { data })
    }
}

/// 撮れた知らせの受け手（1枚ごとに1つ）。**1回だけ**返す
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    /// 撮れたら呼ぶ（呼んだら外す）
    var done: ((ComposeShot?) -> Void)?

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let finish = done
        done = nil
        guard error == nil, let data = photo.fileDataRepresentation() else {
            finish?(nil)
            return
        }
        finish?(ComposeShot(data: data, metadata: photo.metadata, capturedAt: Date()))
    }
}

/// カメラの映像（`AVCaptureVideoPreviewLayer` を層にした UIView）。
///
/// 2026-10-10 判断: **撮れる範囲（3:4）の枠に、切らずに敷く**（`.resizeAspect`）。以前は映像の枠いっぱいに
/// `.resizeAspectFill` で敷いていて、左右が約 45pt 切れ、三分割の線も作例も撮れる写真とずれていた
/// （owner の決定: ファインダーを撮れる範囲に合わせる。上下は黒い地）
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = Self.preparedView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = Self.gravity
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    /// 映像の敷き方。枠が 3:4 なので切らずに敷いても余白は出ない（写真と同じ範囲が見える）
    static let gravity: AVLayerVideoGravity = .resizeAspect

    /// 映像を出す部品（層の設定の前まで）。
    ///
    /// 2026-10-10 判断: **指を受けない**（`isUserInteractionEnabled = false`）。owner の報告
    /// 「作例の1枚目しか重ねられない」（TestFlight 1.0.84）を受けて。映像は枠いっぱいの UIKit の部品で、
    /// 指を受けると UIKit の当たり判定がこの部品を返し、枠に付けた左右の払い（SwiftUI の
    /// `DragGesture`）まで届かないことがある。映像は押す物ではないので、指は外へ通す
    static func preparedView() -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        return view
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // swiftlint:disable:next force_cast
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// 音量ボタン（とカメラコントロール）で撮る（iOS 17.2〜・`AVCaptureEventInteraction`・2026-10-16）。
///
/// 標準のカメラ App と同じく、この画面を開いている間は音量ボタンがシャッターになる（音量は変わらない）。
/// 押し終えた（`.ended`）ときに1枚。構図のシートを開いている・映像が出ていないときは効かせない（`enabled`）。
/// 部品は大きさ 0 の UIView（指は受けない場所に置く）。**実機では確かめていない**
struct CaptureButtonInteraction: UIViewRepresentable {

    var enabled: Bool
    let onPress: () -> Void

    final class Coordinator {
        var onPress: () -> Void = {}
        var interaction: AnyObject?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let coordinator = context.coordinator
        coordinator.onPress = onPress
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { event in
                guard event.phase == .ended else { return }
                Task { @MainActor in coordinator.onPress() }
            }
            interaction.isEnabled = enabled
            view.addInteraction(interaction)
            coordinator.interaction = interaction
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPress = onPress
        if #available(iOS 17.2, *), let interaction = context.coordinator.interaction as? AVCaptureEventInteraction {
            interaction.isEnabled = enabled
        }
    }
}
