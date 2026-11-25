import CoreLocation

// 本物の SDK（Xcode 27）で警告にならない型を、模型でも Sendable にする（2026-11-25・`Shims/SwiftUI/Sendable.swift` の注記）。
// Mac のビルドだけの回（run 1822）で、これらの型は actor の境目を越えても警告が出なかった。`MKMapItem` は出たので足さない
extension MKDirections.ETAResponse: @unchecked Sendable {}
extension MKLocalSearch: @unchecked Sendable {}
extension MKLocalSearch.Response: @unchecked Sendable {}
extension MKMapSnapshotter.Snapshot: @unchecked Sendable {}
