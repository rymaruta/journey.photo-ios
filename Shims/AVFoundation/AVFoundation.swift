// AVFoundation の模型。
import Foundation

/// 本物と同じ形にしておく。**足りないと Mac でしか気づけない**
/// **NSObject を継ぐ**（本物も同じ）。継がないと Linux の NotificationCenter が
/// `object:` で絞った見張りに一致させず、知らせのテストが書けない
open class AVPlayerItem: NSObject {}

open class AVPlayer {
    public private(set) var currentItem: AVPlayerItem? = AVPlayerItem()
    /// 本物と同じ形。ミュートの実体
    public var isMuted: Bool = false
    public init(url: URL) {}
    public func play() {}
    public func pause() {}
    /// 頭出し（本物は CoreMedia の CMTime。AVFoundation が再輸出する）
    public func seek(to time: CMTime) {}
}

public struct CMTime {
    public static let zero = CMTime()
}

extension NSNotification.Name {
    /// 鳴り終わりの知らせ（本物は AVFoundation が出す）
    public static let AVPlayerItemDidPlayToEndTime =
        NSNotification.Name("AVPlayerItemDidPlayToEndTime")
    /// 途中で途切れた知らせ（本物は AVFoundation が出す）
    public static let AVPlayerItemFailedToPlayToEndTime =
        NSNotification.Name("AVPlayerItemFailedToPlayToEndTime")
}

public final class AVAudioSession {
    public struct Category { public static let ambient = Category(), playback = Category() }
    public struct Mode { public static let `default` = Mode() }
    public static func sharedInstance() -> AVAudioSession { AVAudioSession() }
    public func setCategory(_ c: Category, mode: Mode) throws {}
    /// **本物と同じ形にする。** 引数を省いた模型にしておくと、
    /// `options:` を渡すコードが Linux では通らず、Mac でしか気づけない
    public struct SetActiveOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1)
    }
    public func setActive(_ active: Bool, options: SetActiveOptions = []) throws {}
}
