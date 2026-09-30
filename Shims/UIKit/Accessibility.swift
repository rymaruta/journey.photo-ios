import Foundation

// 本物の UIKit にある読み上げの API の模型（Linux のビルド用・2026-09-30）。
// 既存の shim ファイルは別の枝が触ることがあるので、別ファイルに置く。

/// `UIAccessibility.post(notification: .announcement, argument: "…")`
public enum UIAccessibility {
    public struct Notification: Equatable {
        let raw: Int
        public static let announcement = Notification(raw: 1)
        public static let layoutChanged = Notification(raw: 2)
        public static let screenChanged = Notification(raw: 3)
    }
    public static func post(notification: Notification, argument: Any?) {}
    public static var isVoiceOverRunning: Bool { false }
}
