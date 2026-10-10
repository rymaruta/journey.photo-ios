import AVFoundation
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
/// **実機のカメラでは確かめていない**（Linux の模型でビルドを通しただけ・PR の注記）。
@MainActor
final class ComposeCamera: ObservableObject {

    @Published private(set) var state: ComposeGuide.CameraState = .preparing
    /// 撮っている最中（シャッターを2度押せないように）
    @Published private(set) var isCapturing = false

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
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
        if ok { configured = true }
        return ok
    }

    /// 1枚撮る。撮れた写真のファイルの中身（撮れなければ nil）
    func capture() async -> Data? {
        guard state == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let output = output
        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate()
            let key = ObjectIdentifier(delegate)
            delegate.done = { [weak self] data in
                continuation.resume(returning: data)
                Task { @MainActor in self?.pending[key] = nil }
            }
            pending[key] = delegate
            queue.async {
                // 縦持ちの画面（アプリは縦だけ）なので、写真も縦で残す（iOS 17 の回転角・縦＝90°）
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
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

/// 撮れた知らせの受け手（1枚ごとに1つ）。**1回だけ**返す
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    /// 撮れたら呼ぶ（呼んだら外す）
    var done: ((Data?) -> Void)?

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let finish = done
        done = nil
        finish?(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

/// カメラの映像（`AVCaptureVideoPreviewLayer` を層にした UIView）。枠いっぱいに敷く（板: 上 640pt）
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = Self.preparedView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

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
