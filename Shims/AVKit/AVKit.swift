// AVKit の模型（Linux で型検査を通すためだけのもの）。
//
// 本物は iOS 14 以降の `VideoPlayer`。ここでは「View である」ことと
// 初期化の形だけを写す。
import SwiftUI
import AVFoundation
import UIKit

public struct VideoPlayer<Overlay: View>: View {
    public init(player: AVPlayer?) where Overlay == EmptyView {}
    public init(player: AVPlayer?, @ViewBuilder videoOverlay: () -> Overlay) {}
    public var body: some View { EmptyView() }
}

/// 音量ボタン（とカメラコントロール）で撮る（iOS 17.2〜・2026-10-16）。本物は UIKit の
/// `UIInteraction` として画面の部品に足す。**撮影の場（`AVCaptureSession`）が動いている間だけ**届く

public enum AVCaptureEventPhase: Int, Sendable {
    case began = 0, ended = 1, cancelled = 2
}

open class AVCaptureEvent: NSObject {
    open var phase: AVCaptureEventPhase { .ended }
}

open class AVCaptureEventInteraction: NSObject, UIInteraction {
    public init(handler: @escaping (AVCaptureEvent) -> Void) {}
    open var isEnabled: Bool = true
}
