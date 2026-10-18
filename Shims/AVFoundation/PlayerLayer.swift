// AVFoundation の再生の層の模型（2026-10-16・ストーリーの動画を画面いっぱいに敷く）。
//
// **足してあるのは、アプリが使う口だけ**（`Features/Stories/StoryMedia.swift` の `StoryVideoSurface`）。どれも本物の AVFoundation に実在する名前・形で、模型は素通し。
// 既存の AVFoundation.swift・Capture.swift は別の枝が触ることがあるので別ファイルに置く。
import Foundation
import QuartzCore

/// 動画を描く層（本物は CALayer の子）。敷き方は `AVLayerVideoGravity`（Capture.swift）
open class AVPlayerLayer: CALayer {
    public override init() {}
    open var player: AVPlayer?
    open var videoGravity: AVLayerVideoGravity = .resizeAspect
}
