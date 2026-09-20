// 修飾子（模型）。**どれも素通し**——`Self` を返すだけ。
//
// つまり SwiftUI 側の制約（修飾子の順序・`some View` の同一性・
// ViewBuilder の枝の数）は**見ていない**。ここで見えるのは、修飾子に渡した
// 式の中にある自分たちのコードの誤りだけ。
import Foundation

public struct ToolbarItemPlacement {
    public static let topBarTrailing = ToolbarItemPlacement()
    public static let topBarLeading = ToolbarItemPlacement()
    public static let cancellationAction = ToolbarItemPlacement()
    public static let confirmationAction = ToolbarItemPlacement()
}
public struct ToolbarItem: View {
    public init<C: View>(placement: ToolbarItemPlacement = .topBarTrailing, @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

public enum NavigationBarItem { public enum TitleDisplayMode { case inline, large, automatic } }
public struct AccessibilityTraits: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isSelected = AccessibilityTraits(rawValue: 1)
    public static let isButton = AccessibilityTraits(rawValue: 2)
}
public struct TextInputAutocapitalization {
    public static let never = TextInputAutocapitalization()
    public static let sentences = TextInputAutocapitalization()
}
public struct UIKeyboardTypeShim {
    public static let emailAddress = UIKeyboardTypeShim()
    public static let numberPad = UIKeyboardTypeShim()
    public static let URL = UIKeyboardTypeShim()
    public static let numbersAndPunctuation = UIKeyboardTypeShim()
}
public struct UITextContentTypeShim {
    public static let emailAddress = UITextContentTypeShim()
    public static let password = UITextContentTypeShim()
    public static let newPassword = UITextContentTypeShim()
    public static let oneTimeCode = UITextContentTypeShim()
}
public struct PrimitiveButtonStyleShim {
    public static let plain = PrimitiveButtonStyleShim()
    public static let bordered = PrimitiveButtonStyleShim()
    public static let borderedProminent = PrimitiveButtonStyleShim()
    public static let borderless = PrimitiveButtonStyleShim()
}
public struct PickerStyleShim {
    public static let inline = PickerStyleShim()
    public static let segmented = PickerStyleShim()
    public static let menu = PickerStyleShim()
}
public struct TextFieldStyleShim {
    public static let roundedBorder = TextFieldStyleShim()
}
public struct ControlSizeShim {
    public static let large = ControlSizeShim()
    public static let regular = ControlSizeShim()
}
public struct SearchFieldPlacementShim {
    public static let automatic = SearchFieldPlacementShim()
}
public struct SubmitTriggerShim {
    public static let search = SubmitTriggerShim()
}

extension View {
    // 並びと大きさ
    public func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) -> Self { self }
    public func frame(minWidth: Double? = nil, maxWidth: Double? = nil, minHeight: Double? = nil,
                      maxHeight: Double? = nil, alignment: Alignment = .center) -> Self { self }
    public func padding(_ length: Double? = nil) -> Self { self }
    public func padding(_ edges: Edge.Set, _ length: Double? = nil) -> Self { self }
    public func aspectRatio(_ ratio: Double? = nil, contentMode: ContentMode) -> Self { self }
    public func offset(x: Double = 0, y: Double = 0) -> Self { self }
    public func clipped() -> Self { self }
    public func clipShape<S: Shape>(_ shape: S) -> Self { self }
    public func ignoresSafeArea() -> Self { self }
    public func lineLimit(_ n: Int) -> Self { self }
    public func lineLimit(_ range: ClosedRange<Int>) -> Self { self }
    public func lineLimit(_ range: PartialRangeFrom<Int>) -> Self { self }
    public func multilineTextAlignment(_ a: TextAlignment) -> Self { self }

    // 見た目
    public func font(_ f: Font?) -> Self { self }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> Self { self }
    public func background<S: ShapeStyle>(_ s: S) -> Self { self }
    public func background<S: ShapeStyle, T: Shape>(_ s: S, in shape: T) -> Self { self }
    public func tint(_ c: Color?) -> Self { self }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> Self { self }
    public func overlay<V: View>(_ content: V, alignment: Alignment = .center) -> Self { self }
    public func buttonStyle(_ s: PrimitiveButtonStyleShim) -> Self { self }
    public func pickerStyle(_ s: PickerStyleShim) -> Self { self }
    public func textFieldStyle(_ s: TextFieldStyleShim) -> Self { self }
    public func controlSize(_ s: ControlSizeShim) -> Self { self }
    public func labelsHidden() -> Self { self }
    public func disabled(_ v: Bool) -> Self { self }
    public func tag<V: Hashable>(_ v: V) -> Self { self }
    public func badge(_ count: Int) -> Self { self }
    public func id<V: Hashable>(_ v: V) -> Self { self }

    // 入力
    public func keyboardType(_ t: UIKeyboardTypeShim) -> Self { self }
    public func textContentType(_ t: UITextContentTypeShim) -> Self { self }
    public func textInputAutocapitalization(_ a: TextInputAutocapitalization) -> Self { self }
    public func autocorrectionDisabled(_ disabled: Bool = true) -> Self { self }
    public func searchable(text: Binding<String>, placement: SearchFieldPlacementShim = .automatic,
                           prompt: String? = nil) -> Self { self }
    public func onSubmit(of t: SubmitTriggerShim = .search, _ action: @escaping () -> Void) -> Self { self }

    // 画面遷移と入れ物
    public func navigationTitle(_ title: String) -> Self { self }
    public func navigationBarTitleDisplayMode(_ m: NavigationBarItem.TitleDisplayMode) -> Self { self }
    public func navigationDestination<D: Hashable, V: View>(
        for data: D.Type, @ViewBuilder destination: @escaping (D) -> V) -> Self { self }
    public func toolbar<C: View>(@ViewBuilder content: () -> C) -> Self { self }
    public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> Self { self }
    public func sheet<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> C) -> Self { self }
    public func sheet<Item: Identifiable, C: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                   @ViewBuilder content: @escaping (Item) -> C) -> Self { self }
    public func fullScreenCover<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                         @ViewBuilder content: @escaping () -> C) -> Self { self }
    public func fullScreenCover<Item: Identifiable, C: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                             @ViewBuilder content: @escaping (Item) -> C) -> Self { self }
    public func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A,
                                        @ViewBuilder message: () -> M) -> Self { self }
    public func alert<A: View>(_ title: String, isPresented: Binding<Bool>,
                               @ViewBuilder actions: () -> A) -> Self { self }

    // 仕掛け
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping () async -> Void) -> Self { self }
    public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated,
                                   _ action: @escaping () async -> Void) -> Self { self }
    public func refreshable(action: @escaping () async -> Void) -> Self { self }
    public func onAppear(perform action: (() -> Void)? = nil) -> Self { self }
    public func onDisappear(perform action: (() -> Void)? = nil) -> Self { self }
    public func onChange<V: Equatable>(of value: V, _ action: @escaping (V, V) -> Void) -> Self { self }
    public func environmentObject<T: ObservableObject>(_ object: T) -> Self { self }

    // 読み上げ
    public func accessibilityLabel(_ label: String) -> Self { self }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> Self { self }

    // 一覧の操作
    public func swipeActions<C: View>(@ViewBuilder content: () -> C) -> Self { self }
}
