// Combine の模型。`ObservableObject` と `@Published` の**本当の住まい**はここ。
//
// `import SwiftUI` だけで使えるのは、SwiftUI が Combine を再輸出しているから。
// SwiftUI を読まないファイル（値だけを持つ層）は `import Combine` が要る。
import Foundation

public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(initialValue: Value) { self.wrappedValue = initialValue }
    public var projectedValue: Published<Value> { self }
}
