// Combine の模型。`ObservableObject` と `@Published` の**本当の住まい**はここ。
//
// `import SwiftUI` だけで使えるのは、SwiftUI が Combine を再輸出しているから。
// SwiftUI を読まないファイル（値だけを持つ層）は `import Combine` が要る。
import Foundation

/// 本物の `ObservableObjectPublisher`（値は運ばず、`send()` だけ）
public final class ObservableObjectPublisher {
    public init() {}
    public func send() {}
}

/// 本物の `ObservableObject` は既定の `objectWillChange` を持つ
public protocol ObservableObject: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
}
extension ObservableObject {
    public var objectWillChange: ObservableObjectPublisher { ObservableObjectPublisher() }
}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(initialValue: Value) { self.wrappedValue = initialValue }
    public var projectedValue: Published<Value> { self }
}
