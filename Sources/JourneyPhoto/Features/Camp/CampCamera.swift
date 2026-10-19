import AVFoundation
import SwiftUI
import UIKit

/// キャンプ場の「撮る」のカメラ（板 CampCapture 1 撮る・2026-10-18）。
///
/// 「作例を重ねて撮る」のカメラ（`ComposeCamera`）と同じ作り（撮影の場の組み立て・開始・停止は画面の処理の外、
/// 撮れた 1 枚は `PhotoCaptureDelegate` で受ける）。違いは 2 つ:
/// - 板の右下の「カメラを切り替える」のために、後ろと前を入れ替えられる
/// - 映像は画面いっぱいに敷く（`.resizeAspectFill`）。写真は主役で、四隅の枠は映像の上に置く
///
/// **端末にカメラが無い（シミュレータ）・許可が無いときは、写真から選ぶ道だけを出す**（画面の側）
@MainActor
final class CampCamera: ObservableObject {

    @Published private(set) var state: ComposeGuide.CameraState = .preparing
    @Published private(set) var isCapturing = false
    @Published private(set) var position: AVCaptureDevice.Position = .back

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "photo.journey.camp-camera")
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var starting = false
    private var pending: [ObjectIdentifier: PhotoCaptureDelegate] = [:]

    func start() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            state = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
        case .denied: state = .denied; return
        case .restricted: state = .restricted; return
        @unknown default: state = .unavailable; return
        }
        state = await run(position: position) ? .ready : .unavailable
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// 後ろ ↔ 前
    func toggle() async {
        guard state == .ready else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        if await run(position: next) { position = next }
    }

    private func run(position: AVCaptureDevice.Position) async -> Bool {
        let session = session, output = output, old = input, firstTime = !configured
        let result: AVCaptureDeviceInput? = await withCheckedContinuation { continuation in
            queue.async {
                guard let device = (position == .back ? ComposeCamera.backCamera()
                                    : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: nil)
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .photo
                if let old { session.removeInput(old) }
                guard session.canAddInput(input) else {
                    if let old { session.addInput(old) }
                    session.commitConfiguration()
                    continuation.resume(returning: nil)
                    return
                }
                session.addInput(input)
                if firstTime {
                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        continuation.resume(returning: nil)
                        return
                    }
                    session.addOutput(output)
                }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: input)
            }
        }
        guard let result else { return false }
        input = result
        configured = true
        return true
    }

    /// 1 枚撮る（撮れなければ nil）
    func capture() async -> ComposeShot? {
        guard state == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let output = output
        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate()
            let key = ObjectIdentifier(delegate)
            delegate.done = { [weak self] shot in
                continuation.resume(returning: shot)
                Task { @MainActor in self?.pending[key] = nil }
            }
            pending[key] = delegate
            queue.async {
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }
}

/// カメラの映像（画面いっぱい・指は通す）
struct CampCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreview.PreviewView {
        let view = CameraPreview.preparedView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreview.PreviewView, context: Context) {}
}
