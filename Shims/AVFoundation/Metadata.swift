// AVFoundation の「写っている符号を読む」口の模型（2026-11-12・プロフィールの QR の読み取り `ProfileQRScanner`）。
//
// どれも本物の AVFoundation に実在する名前・形。模型は素通し（カメラは無く、何も読まない）。
// 撮影まわり（`Capture.swift`）とは別ファイルに置く（ほかの枝が触ることがある）
import Foundation
import Dispatch

/// 読み取ったもの（本物は `NSObject` の子）
open class AVMetadataObject: NSObject {
    /// 符号の種類（本物は文字列の値の型・`AVMetadataObject.ObjectType`）
    public struct ObjectType: Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let qr = ObjectType(rawValue: "org.iso.QRCode")
    }
    open var type: ObjectType { ObjectType(rawValue: "") }
}

/// 機械で読む符号（QR など）。中身の文字は `stringValue`
open class AVMetadataMachineReadableCodeObject: AVMetadataObject {
    open var stringValue: String? { nil }
}

/// 読み取ったものを受け取る口（本物と同じ形）
public protocol AVCaptureMetadataOutputObjectsDelegate: AnyObject {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection)
}

/// 映像から符号を読む出力
open class AVCaptureMetadataOutput: AVCaptureOutput {
    public override init() {}
    /// 読める種類（セッションに足したあとで決まる・本物と同じ）
    open var availableMetadataObjectTypes: [AVMetadataObject.ObjectType] { [] }
    open var metadataObjectTypes: [AVMetadataObject.ObjectType]! = []
    open func setMetadataObjectsDelegate(_ objectsDelegate: AVCaptureMetadataOutputObjectsDelegate?,
                                         queue objectsCallbackQueue: DispatchQueue?) {}
}
