// 本物の SDK で Sendable の型を、模型でも Sendable にする（2026-11-25・`Shims/SwiftUI/Sendable.swift` の注記）
extension CIContext: @unchecked Sendable {}
