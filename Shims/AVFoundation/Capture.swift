// AVFoundation の撮影まわりの模型（2026-10-09・「作例を重ねて撮る」のカメラ）。
//
// **足してあるのは、アプリが使う口だけ**（`Features/Spots/ComposeCamera.swift`）。どれも本物の
// AVFoundation に実在する名前・形で、模型は素通し（カメラは無く、許可は決まらない）。
// 既存の AVFoundation.swift は再生（音楽・動画）の模型で、別の枝が触ることがあるので別ファイルに置く。
import Foundation
import QuartzCore

/// 撮るものの種類（本物は文字列の値の型）
public struct AVMediaType: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType(rawValue: "vide")
    public static let audio = AVMediaType(rawValue: "soun")
}

/// カメラ・マイクの許可の段（本物と同じ並び）
public enum AVAuthorizationStatus: Int, Sendable {
    case notDetermined = 0, restricted, denied, authorized
}

open class AVCaptureDevice: NSObject {
    /// カメラの種類（本物は文字列の値の型）
    public struct DeviceType: Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let builtInWideAngleCamera = DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInWideAngleCamera")
    }
    /// 前・後ろ（本物と同じ値）
    public enum Position: Int, Sendable {
        case unspecified = 0, back = 1, front = 2
    }
    open class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus { .notDetermined }

    /// 端末の向きから、写真・映像を回す角度を決める係（iOS 17〜・2026-10-10）。
    /// 本物は KVO で見張れる。アプリは撮る瞬間に読むだけ
    open class RotationCoordinator: NSObject {
        public init(device: AVCaptureDevice, previewLayer: CALayer?) {}
        /// 水平を保って撮るための回転角（縦持ち 90・横持ち 0 / 180）
        /// 本物と同じく `CGFloat`（2026-10-10: 模型が Double で、Mac の run 397 で初めて型の食い違いが出た）
        open var videoRotationAngleForHorizonLevelCapture: CGFloat { 90 }
        open var videoRotationAngleForHorizonLevelPreview: CGFloat { 90 }
    }
    /// 本物では完了の受け手つきの口が async に橋渡しされたもの
    open class func requestAccess(for mediaType: AVMediaType) async -> Bool { false }
    /// 模型にはカメラが無い（シミュレータと同じく nil）
    open class func `default`(_ deviceType: DeviceType, for mediaType: AVMediaType?,
                              position: Position) -> AVCaptureDevice? { nil }
}

open class AVCaptureInput: NSObject {}

open class AVCaptureDeviceInput: AVCaptureInput {
    /// 本物と同じく投げる（使用中・許可が無いなど）
    public init(device: AVCaptureDevice) throws {}
}

open class AVCaptureOutput: NSObject {
    /// 映像の流れ（向きを決めるのに使う）
    open func connection(with mediaType: AVMediaType) -> AVCaptureConnection? { nil }
}

/// 入力と出力のつなぎ（向きだけ使う・iOS 17 の回転角）
open class AVCaptureConnection: NSObject {
    /// 本物と同じく `CGFloat`
    open var videoRotationAngle: CGFloat = 0
    open func isVideoRotationAngleSupported(_ videoRotationAngle: CGFloat) -> Bool { false }
}

open class AVCaptureSession: NSObject {
    /// 撮影の場の画質（本物は文字列の値の型・`AVCaptureSession.Preset`）
    public struct Preset: Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let photo = Preset(rawValue: "AVCaptureSessionPresetPhoto")
    }
    public override init() {}
    open var sessionPreset: Preset = .photo
    open var isRunning: Bool { false }
    open func beginConfiguration() {}
    open func commitConfiguration() {}
    open func canAddInput(_ input: AVCaptureInput) -> Bool { false }
    open func addInput(_ input: AVCaptureInput) {}
    open func canAddOutput(_ output: AVCaptureOutput) -> Bool { false }
    open func addOutput(_ output: AVCaptureOutput) {}
    open func startRunning() {}
    open func stopRunning() {}
}

open class AVCapturePhotoSettings: NSObject {
    public override init() {}
}

/// 撮れた1枚
open class AVCapturePhoto: NSObject {
    /// 撮影情報つきのファイルの中身（HEIF・JPEG）
    open func fileDataRepresentation() -> Data? { nil }
    /// 撮影情報（`{Exif}`・`{TIFF}` などの入れ子の辞書）
    open var metadata: [String: Any] { [:] }
}

/// 撮れた知らせの受け手。**本物では任意の口だが、模型では必ず書く**——綴りや型を
/// 取り違えたまま「呼ばれない口」を作っても、本物は黙って通してしまうので、模型で落とす
public protocol AVCapturePhotoCaptureDelegate: AnyObject {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?)
}

open class AVCapturePhotoOutput: AVCaptureOutput {
    public override init() {}
    open func capturePhoto(with settings: AVCapturePhotoSettings, delegate: AVCapturePhotoCaptureDelegate) {}
}

/// 映像の敷き方（本物は文字列の値の型）
public struct AVLayerVideoGravity: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let resizeAspect = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspect")
    public static let resizeAspectFill = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspectFill")
}

/// カメラの映像を描く層（本物は CALayer の子）
open class AVCaptureVideoPreviewLayer: CALayer {
    public override init() {}
    open var session: AVCaptureSession?
    open var videoGravity: AVLayerVideoGravity = .resizeAspect
    open var connection: AVCaptureConnection? { nil }
}
