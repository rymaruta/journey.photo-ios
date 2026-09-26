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

/// **`ForEach($items) { $item in … }` のための適合**（本物も同じ）。
/// 書き換えられる並びを包んだ `Binding` は、それ自身が並びとして歩ける。
extension Binding: Sequence, Collection, BidirectionalCollection, RandomAccessCollection
where Value: MutableCollection & RandomAccessCollection {
    public typealias Element = Binding<Value.Element>
    public typealias Index = Value.Index
    public var startIndex: Value.Index { wrappedValue.startIndex }
    public var endIndex: Value.Index { wrappedValue.endIndex }
    public func index(after i: Value.Index) -> Value.Index { wrappedValue.index(after: i) }
    public func index(before i: Value.Index) -> Value.Index { wrappedValue.index(before: i) }
    public subscript(position: Value.Index) -> Binding<Value.Element> {
        Binding<Value.Element>(
            get: { wrappedValue[position] },
            set: { newValue in
                var copy = wrappedValue
                copy[position] = newValue
                wrappedValue = copy
            })
    }
}

extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

@propertyWrapper
@dynamicMemberLookup
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
    /// クロージャの `$item` のために要る（本物も持っている）。
    public init(projectedValue: Binding<Value>) { self = projectedValue }
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
    /// `$item.title` のための橋（本物も同じ形）。
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> Binding<T> {
        Binding<T>(get: { wrappedValue[keyPath: keyPath] },
                   set: { newValue in
                       var copy = wrappedValue
                       copy[keyPath: keyPath] = newValue
                       wrappedValue = copy
                   })
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

/// アプリが前面に居るか（本物は `@Environment(\.scenePhase)`）
public enum ScenePhase: Equatable { case active, inactive, background }

public struct EnvironmentValues {
    public var dismiss: DismissAction { DismissAction() }
    public var scenePhase: ScenePhase { .active }
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
    public static let clear = Color()
    public static let red = Color()
    public static let pink = Color()
    public static let yellow = Color()
    public static let orange = Color()
    public static let primary = Color()
    public static let secondary = Color()
    public static let accentColor = Color()
    nonisolated public init() {}
    nonisolated public init(_ name: String) {}
    nonisolated public init(_ ui: UIColorShim) {}
    nonisolated public init(red: Double, green: Double, blue: Double) {}
    public static let gray = Color()
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
    public static func system(size: Double, weight: Weight) -> Font { Font() }
    /// 書体の系統（`serif` は iPhone で New York）。本物は `weight` も `design` も
    /// 省略できるが、模型で両方に既定値を付けると上の2つと曖昧になるので `design` は必須
    public static func system(size: Double, weight: Weight = .regular, design: Design) -> Font { Font() }
    public enum Design { case `default`, serif, rounded, monospaced }
    public static func custom(_ name: String, size: Double, relativeTo textStyle: TextStyle) -> Font { Font() }
    public static func custom(_ name: String, fixedSize: Double) -> Font { Font() }
    public func weight(_ w: Weight) -> Font { self }
    public func monospacedDigit() -> Font { self }
    public var bold: Font { self }
    public enum TextStyle { case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2 }
    public struct Weight { public static let bold = Weight(), semibold = Weight(), medium = Weight(), regular = Weight(), heavy = Weight(), light = Weight(), thin = Weight(), ultraLight = Weight() }
}
extension Font {
    public var weight: (Weight) -> Font { { _ in self } }
}

public enum ContentMode { case fit, fill }
public enum Axis { case horizontal, vertical }
extension Axis {
    /// `ViewThatFits(in:)` が受ける軸の組
    public struct Set: ExpressibleByArrayLiteral {
        public static let horizontal = Set(), vertical = Set()
        public init() {}
        public init(arrayLiteral elements: Set...) {}
    }
}
public enum TextAlignment { case leading, center, trailing }

public struct Alignment {
    public static let center = Alignment(), leading = Alignment(), trailing = Alignment()
    public static let top = Alignment(), topTrailing = Alignment(), topLeading = Alignment()
    public static let bottom = Alignment(), bottomLeading = Alignment(), bottomTrailing = Alignment()
}
public struct HorizontalAlignment { public static let leading = HorizontalAlignment(), center = HorizontalAlignment(), trailing = HorizontalAlignment() }
/// 揃えの計算に渡る寸法（本物と同じ形）
public struct ViewDimensions {
    public var width: CGFloat { 0 }
    public var height: CGFloat { 0 }
    public subscript(guide: VerticalAlignment) -> CGFloat { 0 }
    public subscript(guide: HorizontalAlignment) -> CGFloat { 0 }
}
public struct VerticalAlignment { public static let center = VerticalAlignment(), top = VerticalAlignment(), bottom = VerticalAlignment(), firstTextBaseline = VerticalAlignment(), lastTextBaseline = VerticalAlignment() }
public struct Edge {
    public static let top = Edge(), bottom = Edge(), leading = Edge(), trailing = Edge()
    /// 本物は `OptionSet`（`[]` で「どの端も無し」を書ける）
    public struct Set: ExpressibleByArrayLiteral {
        public static let all = Set(), horizontal = Set(), vertical = Set()
        public static let top = Set(), bottom = Set(), leading = Set(), trailing = Set()
        public init() {}
        public init(arrayLiteral elements: Set...) {}
    }
}
/// `safeAreaInset(edge:)` が受ける上下。本物は `CaseIterable` の enum
public enum VerticalEdge { case top, bottom }

public struct Animation {
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static func linear(duration: Double) -> Animation { Animation() }
    public static let `default` = Animation()
}
/// 本物は `Result` を返す。模型は中身を1回呼ぶだけ
@discardableResult
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try body()
}
public struct Transaction {
    public init() {}
    public init(animation: Animation?) {}
}

// **Foundation の同じ型をそのまま使う。**
//
// 以前はここで独自に定義していたが、Linux の Foundation も
// `CGPoint` / `CGSize` / `CGRect` を持っているので、両方を読む
// ファイル（UIKit の模型を使う側）で **`CGSize` が曖昧**になり
// コンパイルできなかった。本物の iOS では CoreGraphics の1つだけなので、
// 模型も1つに寄せる。
public typealias CGPoint = Foundation.CGPoint
public typealias CGSize = Foundation.CGSize
public typealias CGRect = Foundation.CGRect
public typealias CGFloat = Foundation.CGFloat


public struct UIImageShim {
    public init?(data: Data) { return nil }
    public init() {}
    public func jpegData(compressionQuality: Double) -> Data? { nil }
}


/// `@FocusState` の模型。本物は入力欄に焦点が当たっているかを持つ。
@propertyWrapper
/// **本物は画面（`View` の struct）の中から書き換えられる**（`nonmutating set`）。
/// 模型も `@State` と同じ箱で持つ——値型のまま持つと `captionFocused = false` が
/// 「self は変えられない」で落ち、模型のビルドが止まっていた（2026-09-26）。
public struct FocusState<Value>: DynamicProperty {
    private let box: Box<Value>
    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public init() where Value == Bool { box = Box(false) }
    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    public var projectedValue: Binding<Value> { Binding(get: { box.value }, set: { box.value = $0 }) }
}


/// `@UIApplicationDelegateAdaptor` の模型。
/// 本物は UIKit の delegate を SwiftUI の `App` に繋ぐ。
@propertyWrapper
public struct UIApplicationDelegateAdaptor<DelegateType: AnyObject>: DynamicProperty {
    public var wrappedValue: DelegateType
    public init(_ type: DelegateType.Type) where DelegateType: NSObjectProtocolShim {
        wrappedValue = DelegateType.init()
    }
}

/// `NSObject` の代わり（Linux には Foundation の NSObject はあるが、
/// `init()` が要ることだけを写した軽い約束）。
public protocol NSObjectProtocolShim: AnyObject {
    init()
}

/// 線形グラデーション。写真の下に敷く帯（Web の `linear-gradient`）で使う。
/// 模型なので何も描かない。
public struct UnitPoint: Hashable, Sendable {
    public static let top = UnitPoint()
    public static let bottom = UnitPoint()
    public static let leading = UnitPoint()
    public static let trailing = UnitPoint()
    public static let center = UnitPoint()
    public init() {}
}

/// 色の位置（本物は `Gradient.Stop`）
public struct Gradient {
    public struct Stop {
        public init(color: Color, location: Double) {}
    }
}
public struct LinearGradient: View, ShapeStyle {
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {}
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {}
    public var body: Never { fatalError() }
}

/// `@Namespace`。地図の操作部品を地図の外に置く（`mapScope` / `MapCompass(scope:)`）のに使う
@propertyWrapper
public struct Namespace {
    public struct ID: Hashable { public init() {} }
    public init() {}
    public var wrappedValue: ID { ID() }
}

/// 文字サイズの段（本物と同じ並び）。上限を置く `dynamicTypeSize(...)` で使う
public enum DynamicTypeSize: Comparable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5
}
