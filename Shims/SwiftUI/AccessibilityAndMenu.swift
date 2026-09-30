import Foundation

// 本物の SwiftUI（iOS 17）にある API の模型。Linux のビルドを通すためだけのもの。
// 既存の Primitives.swift は並行して別の枝が触っているので、衝突しないよう別の
// ファイルに置く（2026-09-30・旅行プランの並べ替えで使った分）。読み上げは UIKit の
// `UIAccessibility.post` を使う（Shims/UIKit/Accessibility.swift）。

/// `.menuOrder(.fixed)`（iOS 16）
public struct MenuOrder {
    public static let automatic = MenuOrder()
    public static let fixed = MenuOrder()
    public static let priority = MenuOrder()
}

extension View {
    public func menuOrder(_ order: MenuOrder) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
}
