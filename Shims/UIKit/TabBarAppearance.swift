import Foundation

// 本物の UIKit にあるタブバーの見た目の API の模型（Linux のビルド用・2026-10-02）。
// 既存の shim ファイルは別の枝が触ることがあるので、別ファイルに置く。

public final class UITabBarItemStateAppearance {
    public var iconColor: UIColor?
    public var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
    public init() {}
}

public final class UITabBarItemAppearance {
    public let normal = UITabBarItemStateAppearance()
    public let selected = UITabBarItemStateAppearance()
    public init() {}
}

public final class UITabBarAppearance {
    public let stackedLayoutAppearance = UITabBarItemAppearance()
    public let inlineLayoutAppearance = UITabBarItemAppearance()
    public let compactInlineLayoutAppearance = UITabBarItemAppearance()
    public init() {}
    public func configureWithDefaultBackground() {}
    public func configureWithTransparentBackground() {}
    public func configureWithOpaqueBackground() {}
}

public final class UITabBar {
    public var tintColor: UIColor?
    public var standardAppearance = UITabBarAppearance()
    public var scrollEdgeAppearance: UITabBarAppearance?
    public init() {}
    private static let proxy = UITabBar()
    public static func appearance() -> UITabBar { proxy }
}
