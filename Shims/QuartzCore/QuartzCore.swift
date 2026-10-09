// QuartzCore（Core Animation）の模型。
//
// **足してあるのは、アプリが使う口だけ**（2026-10-09・「作例を重ねて撮る」のカメラの映像
// `AVCaptureVideoPreviewLayer` の親）。本物は UIKit が再輸出するので、模型の UIKit も
// `@_exported import QuartzCore` で同じ見え方にしてある。
import Foundation

/// 描く層（本物と同じ名前）。模型は何も描かない
open class CALayer {
    public init() {}
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
}
