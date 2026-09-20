// 画面の部品（模型）。**中身は持たない**——型検査に必要な形だけ。
import Foundation
// 本物の SwiftUI と同じく Combine を再輸出する
@_exported import Combine

// MARK: - 値の入れ物

/// 値を箱に入れて持つ。**`nonmutating set` を成り立たせるため**
/// ——本物の `@State` は構造体のまま書き換えられる。
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@propertyWrapper
public struct State<Value>: DynamicProperty {
    private let box: Box<Value>
    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public init(initialValue: Value) { box = Box(initialValue) }
    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    public var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}

@propertyWrapper
public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = set
    }
    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
    public var projectedValue: Binding<Value> { self }
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
}

@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty {
    private let object: ObjectType
    /// **その場で作る。** 画面の型は `View`（`@MainActor`）に適合していて
    /// まとめてメインアクタに載るので、ここで作っても分離の誤りにならない。
    /// 本物は遅延して作るが、模型が見たいのは型だけ
    public init(wrappedValue: @autoclosure () -> ObjectType) { object = wrappedValue() }
    public var wrappedValue: ObjectType { object }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { .init(object: object) }
}

@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty {
    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public init(initialValue: ObjectType) { self.wrappedValue = initialValue }
    public var projectedValue: Wrapper { Wrapper(object: wrappedValue) }

    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType
        public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
            Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
        }
    }
}

@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicProperty {
    public init() {}
    public var wrappedValue: ObjectType { fatalError("模型") }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { fatalError("模型") }
}

@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {}
    public var wrappedValue: Value { fatalError("模型") }
}

public protocol DynamicProperty {}

public struct EnvironmentValues {
    public var dismiss: DismissAction { DismissAction() }
    public var openURL: OpenURLAction { OpenURLAction() }
    public var colorScheme: ColorScheme { .light }
}

public struct DismissAction {
    public func callAsFunction() {}
}

public struct OpenURLAction {
    public func callAsFunction(_ url: URL) {}
}

public enum ColorScheme { case light, dark }


// MARK: - 見た目の値

public struct Color: View, ShapeStyle, Hashable {
    // `ShapeStyle` の静的プロパティから作るので、アクタに属さない init が要る
    public static let white = Color()
    public static let black = Color()
    public static let red = Color()
    public static let pink = Color()
    public static let orange = Color()
    public static let primary = Color()
    public static let secondary = Color()
    public static let accentColor = Color()
    nonisolated public init() {}
    nonisolated public init(_ name: String) {}
    nonisolated public init(_ ui: UIColorShim) {}
    nonisolated public func opacity(_ v: Double) -> Color { self }
    public var body: Never { fatalError("模型") }
}

public typealias UIColor = UIColorShim
public typealias UIImage = UIImageShim

public struct UIColorShim {
    public static let secondarySystemBackground = UIColorShim()
    public static let systemBackground = UIColorShim()
    public static let label = UIColorShim()
}

public protocol ShapeStyle {}
public struct AnyShapeStyle: ShapeStyle {
    public init<S: ShapeStyle>(_ style: S) {}
}
public struct HierarchicalShapeStyle: ShapeStyle {
    public static let primary = HierarchicalShapeStyle()
    public static let secondary = HierarchicalShapeStyle()
    public static let tertiary = HierarchicalShapeStyle()
}
public struct Material: ShapeStyle {
    public static let thin = Material()
    public static let ultraThin = Material()
    public static let bar = Material()
    public static let regular = Material()
}
extension ShapeStyle where Self == Color {
    public static var white: Color { Color() }
    public static var red: Color { Color() }
    public static var pink: Color { Color() }
    public static var orange: Color { Color() }
    public static var primary: Color { Color() }
    public static var secondary: Color { Color() }
    public static var tint: Color { Color() }
}
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var tertiary: HierarchicalShapeStyle { HierarchicalShapeStyle() }
}
extension ShapeStyle where Self == Material {
    public static var thinMaterial: Material { Material() }
    public static var ultraThinMaterial: Material { Material() }
    public static var bar: Material { Material() }
}

public struct Font {
    public static let largeTitle = Font(), title = Font(), title2 = Font(), title3 = Font()
    public static let headline = Font(), subheadline = Font(), body = Font()
    public static let callout = Font(), footnote = Font(), caption = Font(), caption2 = Font()
    public static func system(size: Double) -> Font { Font() }
    public func weight(_ w: Weight) -> Font { self }
    public var bold: Font { self }
    public struct Weight { public static let bold = Weight(), semibold = Weight(), medium = Weight() }
}
extension Font {
    public var weight: (Weight) -> Font { { _ in self } }
}

public enum ContentMode { case fit, fill }
public enum Axis { case horizontal, vertical }
public enum TextAlignment { case leading, center, trailing }

public struct Alignment {
    public static let center = Alignment(), leading = Alignment(), trailing = Alignment()
    public static let top = Alignment(), topTrailing = Alignment(), topLeading = Alignment()
    public static let bottom = Alignment(), bottomLeading = Alignment(), bottomTrailing = Alignment()
}
public struct HorizontalAlignment { public static let leading = HorizontalAlignment(), center = HorizontalAlignment() }
public struct VerticalAlignment { public static let center = VerticalAlignment(), top = VerticalAlignment() }
public struct Edge {
    public struct Set {
        public static let all = Set(), horizontal = Set(), vertical = Set()
        public static let top = Set(), bottom = Set(), leading = Set(), trailing = Set()
    }
}

public struct Animation {
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static let `default` = Animation()
}
public struct Transaction {
    public init() {}
    public init(animation: Animation?) {}
}

public struct CGPoint { public var x: Double; public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y } }
public struct CGSize { public var width: Double; public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height } }
public struct CGRect {
    public var minX: Double = 0, minY: Double = 0, maxX: Double = 0, maxY: Double = 0
}
public typealias CGFloat = Double


public struct UIImageShim {
    public init?(data: Data) { return nil }
    public init() {}
    public func jpegData(compressionQuality: Double) -> Data? { nil }
}
