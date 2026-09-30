// AVFoundation の模型。
import Foundation

/// 本物と同じ形にしておく。**足りないと Mac でしか気づけない**
/// **NSObject を継ぐ**（本物も同じ）。継がないと Linux の NotificationCenter が
/// `object:` で絞った見張りに一致させず、知らせのテストが書けない
open class AVPlayerItem: NSObject {
    /// 本物と同じ形（読み込みに失敗したら `.failed`）
    public enum Status: Int { case unknown, readyToPlay, failed }
    open var status: Status { .unknown }
    /// 本物と同じ形（長さ。読み込み前は無限・NaN のことがある）
    open var duration: CMTime { .zero }
}

open class AVPlayer {
    public private(set) var currentItem: AVPlayerItem? = AVPlayerItem()
    /// 本物と同じ形。ミュートの実体
    public var isMuted: Bool = false
    /// 本物と同じ形（再生の速さ。止めている・詰まっている間は 0）
    public var rate: Float = 0
    public init(url: URL) {}
    public func play() {}
    public func pause() {}
    /// 頭出し（本物は CoreMedia の CMTime。AVFoundation が再輸出する）
    public func seek(to time: CMTime) {}
    /// 本物と同じ形（いまの位置・定期の見張り）
    public func currentTime() -> CMTime { .zero }
    public func addPeriodicTimeObserver(forInterval interval: CMTime, queue: DispatchQueue?,
                                        using block: @escaping @Sendable (CMTime) -> Void) -> Any { NSObject() }
    public func removeTimeObserver(_ observer: Any) {}
}

public typealias CMTimeScale = Int32

public struct CMTime {
    public static let zero = CMTime()
    public init() {}
    /// 本物と同じ形（秒と刻み）
    public init(seconds: Double, preferredTimescale: CMTimeScale) { self.seconds = seconds }
    public var seconds: Double = 0
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
    /// 電話・Siri などで音が止められた・戻された知らせ（本物と同じ名前）。
    /// 種類は `userInfo["AVAudioSessionInterruptionTypeKey"]`（1 が始まり）
    public static let interruptionNotification = Notification.Name("AVAudioSessionInterruptionNotification")
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
