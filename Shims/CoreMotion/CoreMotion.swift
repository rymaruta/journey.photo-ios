// CoreMotion の模型（2026-10-10・「構図を重ねて撮る」の水準器 `LevelMotion` に要るぶんだけ）。
// 本物と同じ名前・同じ形。中身は何もしない（Linux には傾きの知らせが来ない）
import Foundation

/// 加速度（重力）。本物は C の構造体
public struct CMAcceleration {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

open class CMDeviceMotion: NSObject {
    /// 端末から見た重力の向き（g 単位）
    open var gravity: CMAcceleration { CMAcceleration(x: 0, y: -1, z: 0) }
}

public typealias CMDeviceMotionHandler = (CMDeviceMotion?, Error?) -> Void

open class CMMotionManager: NSObject {
    public override init() {}
    open var isDeviceMotionAvailable: Bool { false }
    open var isDeviceMotionActive: Bool { false }
    open var deviceMotionUpdateInterval: TimeInterval = 0.1
    open func startDeviceMotionUpdates(to queue: OperationQueue, withHandler handler: @escaping CMDeviceMotionHandler) {}
    open func stopDeviceMotionUpdates() {}
}
