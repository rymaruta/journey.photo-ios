// AVFoundation の再生の頭出しの模型（2026-11-09・ストーリーの動画の切り取り）。
//
// **足してあるのは、アプリが使う口だけ**（`Features/Stories/StoryVideoTrimView.swift` の `StoryTrimPlayback`）。
// 本物の `AVPlayer.seek(to:toleranceBefore:toleranceAfter:)` と同じ名前・形で、模型は何もしない。
// 既存の AVFoundation.swift は別の枝が触ることがあるので別ファイルに置く。
import Foundation

extension AVPlayer {
    /// 誤差を指定した頭出し（始点の絵を正確に出す）
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {}
}
