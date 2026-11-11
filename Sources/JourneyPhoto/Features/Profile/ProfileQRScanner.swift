import AVFoundation
import SwiftUI
import UIKit

/// プロフィールの QR の画面の下の小窓で、相手の QR を読むカメラ（札 #545・2026-11-11）。
///
/// 撮影の場（`AVCaptureSession`）に QR だけを読む出力（`AVCaptureMetadataOutput`）を足す。組み立て・開始・停止は
/// 画面の処理の外の列で行う（`ComposeCamera` と同じ。`startRunning` は重い）。
///
/// - **開いただけでは許可を聞かない**（2026-11-11 owner）。許可済みならそのまま流し、まだなら小窓に
///   「カメラを使う」のボタン（`requestAccess`）。断られていれば設定アプリへ
/// - 読めた中身は1回だけ渡す（同じ QR を映し続けても何度も開かない）。画面に戻ってきたら `resume` で読み直せる
@MainActor
final class ProfileQRScanner: ObservableObject {

    /// 小窓に出すもの。作った時点のカメラの有無と許可で決める（最初の1コマで「使えません」を見せない）
    @Published private(set) var state = ProfileQR.cameraState(hasCamera: ProfileQRScanner.hasCamera,
                                                              permission: ProfileQRScanner.permission)

    let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()
    private let queue = DispatchQueue(label: "photo.journey.profile-qr-scanner")
    private let receiver = Receiver()
    private var configured = false
    /// 1回読んだら、次に `resume` されるまで渡さない
    private var delivered = false
    private var onRead: (@MainActor (String) -> Void)?

    init() {
        receiver.owner = self
    }

    /// 端末にカメラがあるか（シミュレータには無い）
    nonisolated static var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    nonisolated static var permission: ProfileQR.Permission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    /// 画面が出たとき（相手の頁から戻ったときも）。**許可は聞かない**——許可済みなら流し始める
    func prepare(onRead: @escaping @MainActor (String) -> Void) async {
        self.onRead = onRead
        delivered = false
        state = ProfileQR.cameraState(hasCamera: Self.hasCamera, permission: Self.permission)
        if state == .scanning { await run() }
    }

    /// 「カメラを使う」を押したとき。ここで初めて許可を聞く
    func requestAccess() async {
        guard Self.hasCamera else {
            state = .unavailable
            return
        }
        if Self.permission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        state = ProfileQR.cameraState(hasCamera: true, permission: Self.permission)
        if state == .scanning { await run() }
    }

    /// 読んだ相手の頁から戻ってきた・知らせを出し終えた → もう一度読めるようにする
    func resume() {
        delivered = false
    }

    func stop() {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    /// 読めた中身（受け手から主の列で呼ばれる）
    fileprivate func handle(_ text: String) {
        guard !delivered, state == .scanning else { return }
        delivered = true
        onRead?(text)
    }

    /// UI テストの見本（`PreviewSession.qrScanFixture`）を、カメラで読んだのと同じ道で渡す。
    /// カメラの無いシミュレータでも、読んだあとの道（相手の頁が開く）を確かめられるように
    func deliverFixture(_ text: String) {
        guard !delivered else { return }
        delivered = true
        onRead?(text)
    }

    private func run() async {
        let session = session, output = output, receiver = receiver, queue = queue, alreadyConfigured = configured
        let ok: Bool = await withCheckedContinuation { continuation in
            queue.async {
                if !alreadyConfigured {
                    guard let device = ComposeCamera.backCamera(),
                          let input = try? AVCaptureDeviceInput(device: device) else {
                        continuation.resume(returning: false)
                        return
                    }
                    session.beginConfiguration()
                    session.sessionPreset = .high
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        continuation.resume(returning: false)
                        return
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    // 読む種類は出力を足したあとに決まる（足す前に QR を頼むと落ちる・Apple の注記）
                    if output.availableMetadataObjectTypes.contains(.qr) {
                        output.metadataObjectTypes = [.qr]
                    }
                    output.setMetadataObjectsDelegate(receiver, queue: .main)
                    session.commitConfiguration()
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
        configured = configured || ok
        if !ok { state = .unavailable }
    }

    /// 読めた知らせの受け手（主の列で呼ばれる）
    private final class Receiver: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        weak var owner: ProfileQRScanner?

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
                  let text = code.stringValue else { return }
            MainActor.assumeIsolated { owner?.handle(text) }
        }
    }
}

/// 小窓の映像（枠いっぱいに切って敷く）。部品は `CameraPreview` と同じ作り（指を受けない）
struct QRCameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreview.PreviewView {
        let view = CameraPreview.preparedView()
        view.previewLayer.session = session
        // 撮る写真が無いので、小窓の形いっぱいに映す（映せる所が小窓そのものになる）
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreview.PreviewView, context: Context) {}
}
