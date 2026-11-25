// 本物の SDK で Sendable の型を、模型でも Sendable にする（2026-11-25・Swift 6 へ移す作業。
// 決め方は `Shims/SwiftUI/Sendable.swift` の注記）
extension UIColor: @unchecked Sendable {}
extension UIFont: @unchecked Sendable {}
extension UIFont.Weight: @unchecked Sendable {}
extension UIEdgeInsets: @unchecked Sendable {}
