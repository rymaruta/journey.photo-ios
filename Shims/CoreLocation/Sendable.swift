// 本物の SDK（Xcode 27）で警告にならない型を、模型でも Sendable にする（2026-11-25・`Shims/SwiftUI/Sendable.swift` の注記）
extension CLPlacemark: @unchecked Sendable {}
// Objective-C の列挙と C の構造体は、Swift に入ると Sendable になる
extension CLAuthorizationStatus: @unchecked Sendable {}
extension CLLocationCoordinate2D: @unchecked Sendable {}
