// AVFoundation の模型。
import Foundation

open class AVPlayer {
    public init(url: URL) {}
    public func play() {}
    public func pause() {}
}

public final class AVAudioSession {
    public struct Category { public static let ambient = Category(), playback = Category() }
    public struct Mode { public static let `default` = Mode() }
    public static func sharedInstance() -> AVAudioSession { AVAudioSession() }
    public func setCategory(_ c: Category, mode: Mode) throws {}
    public func setActive(_ active: Bool) throws {}
}
