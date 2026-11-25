// 本物の SDK で Sendable の型を、模型でも Sendable にする（2026-11-25・`Shims/SwiftUI/Sendable.swift` の注記）。
// Objective-C の列挙は Swift に入ると Sendable になる
extension PHAuthorizationStatus: @unchecked Sendable {}
extension PHImageManager: @unchecked Sendable {}
extension PHCachingImageManager: @unchecked Sendable {}
