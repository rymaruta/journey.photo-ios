// 修飾子（模型）。
//
// **戻り値は `ModifiedContent<Self, …>`** で、本物と同じく**型が変わる**。
// `Self` を返す作りにしていた頃は、`some View` の同一性——「枝ごとに違う
// 修飾を付けると型が食い違う」という SwiftUI 特有の制約——を見逃していた。
// いまは ViewBuilder を通らない場所（計算プロパティの if/else など）で
// 食い違えば落ちる。
//
// なお修飾子の**順序**と実行時の挙動は、これでも見ていない。
import Foundation

/// `accessibilityElement(children:)` の指定（本物と同じ名前）
public struct AccessibilityChildBehavior {
    public static let ignore = AccessibilityChildBehavior()
    public static let combine = AccessibilityChildBehavior()
    public static let contain = AccessibilityChildBehavior()
}

public struct ToolbarItemPlacement {
    public static let topBarTrailing = ToolbarItemPlacement()
    public static let topBarLeading = ToolbarItemPlacement()
    public static let cancellationAction = ToolbarItemPlacement()
    public static let confirmationAction = ToolbarItemPlacement()
    /// 見出しの中央。自前のロゴを置くのに要る（本物にある）
    public static let principal = ToolbarItemPlacement()
}
/// **ツールバーの中身は `View` ではなく `ToolbarContent`。** 本物と同じ形に
/// しておかないと、置けないものを置いても模型では通ってしまう。
/// 本物と同じく**自分で組み立てる型**も作れる（`var body: some ToolbarContent`）。
/// 見出しを全画面で共有するのに要る（`AppHeaderItems`）
// 本物も `View` と同じく主アクタに縛られている（付けないと、
// 中で SwiftUI の部品を組む型が「nonisolated の要求を満たせない」と怒られる）
@MainActor
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent
    // **`@ToolbarContentBuilder` を要求に付けない**（`View` の模型と同じ）。
    // 付けると `body: Never { fatalError(...) }` の中身まで組み立てに回され、
    // `Never` が `View` でもあるために曖昧になる。組み立てが要る側は
    // 自分で `@ToolbarContentBuilder` と書く
    var body: Body { get }
}
/// 置くだけの部品（`ToolbarItem` など）は本物と同じく `Never`
/// （`body` は `View` の側で既に生えている——本物も1つで両方を満たす）
extension Never: ToolbarContent {}

// 中身（`ToolbarContent`）が主アクタなので、組み立てる側も揃える
@MainActor
@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildBlock() -> EmptyToolbarContent { EmptyToolbarContent() }
    public static func buildBlock<C: ToolbarContent>(_ c: C) -> C { c }
    public static func buildBlock<C1: ToolbarContent, C2: ToolbarContent>(_ c1: C1, _ c2: C2) -> EmptyToolbarContent { EmptyToolbarContent() }
    public static func buildBlock<C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent>(_ c1: C1, _ c2: C2, _ c3: C3) -> EmptyToolbarContent { EmptyToolbarContent() }
    public static func buildIf<C: ToolbarContent>(_ c: C?) -> C? { c }
    public static func buildOptional<C: ToolbarContent>(_ c: C?) -> C? { c }
    public static func buildEither<T: ToolbarContent>(first: T) -> EmptyToolbarContent { EmptyToolbarContent() }
    public static func buildEither<F: ToolbarContent>(second: F) -> EmptyToolbarContent { EmptyToolbarContent() }
    public static func buildExpression<C: ToolbarContent>(_ c: C) -> C { c }
    /// 素の View を1つだけ置く書き方も本物は受ける
    public static func buildExpression<V: View>(_ v: V) -> EmptyToolbarContent { EmptyToolbarContent() }
}

public struct EmptyToolbarContent: ToolbarContent {
    public init() {}
    public var body: Never { fatalError("模型") }
}
extension Optional: ToolbarContent where Wrapped: ToolbarContent {
    public var body: Never { fatalError("模型") }
}

public struct ToolbarItem: ToolbarContent {
    public init<C: View>(placement: ToolbarItemPlacement = .topBarTrailing, @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

public enum NavigationBarItem { public enum TitleDisplayMode { case inline, large, automatic } }
public struct AccessibilityTraits: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isSelected = AccessibilityTraits(rawValue: 1)
    public static let isModal = AccessibilityTraits(rawValue: 1 << 5)
    public static let isButton = AccessibilityTraits(rawValue: 2)
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 3)
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
    public static let name = UITextContentTypeShim()
}
/// 自前の押し方の模型（本物と同じ形）。`makeBody` に押している間かが来る
/// 本物は `@MainActor`（`makeBody` の中で修飾子を呼べるのはそのため）
@MainActor public protocol ButtonStyle {
    associatedtype Body: View
    typealias Configuration = ButtonStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}
public struct ButtonStyleConfiguration {
    public struct Label: View { public var body: Never { fatalError("模型") } }
    public let label: Label
    public let isPressed: Bool
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
    public static let plain = TextFieldStyleShim()
    public static let roundedBorder = TextFieldStyleShim()
}
public struct ScrollDismissesKeyboardModeShim {
    public static let automatic = ScrollDismissesKeyboardModeShim()
    public static let immediately = ScrollDismissesKeyboardModeShim()
    public static let interactively = ScrollDismissesKeyboardModeShim()
    public static let never = ScrollDismissesKeyboardModeShim()
}
public struct ListStyleShim {
    public static let plain = ListStyleShim()
    public static let insetGrouped = ListStyleShim()
}
/// シートの高さの段（本物と同じ形）
public struct PresentationDetent: Hashable {
    public static let medium = PresentationDetent()
    public static let large = PresentationDetent()
    public static func height(_ h: CGFloat) -> PresentationDetent { PresentationDetent() }
}
public struct VisibilityShim {
    public static let automatic = VisibilityShim()
    public static let visible = VisibilityShim()
    public static let hidden = VisibilityShim()
}

public struct ColorSchemeShim {
    public static let light = ColorSchemeShim()
    public static let dark = ColorSchemeShim()
}

public struct ToolbarPlacementShim {
    public static let navigationBar = ToolbarPlacementShim()
    public static let tabBar = ToolbarPlacementShim()
}

public struct AnyTransitionShim {
    public static let scale = AnyTransitionShim()
    public static let opacity = AnyTransitionShim()
    public static func move(edge: Edge) -> AnyTransitionShim { AnyTransitionShim() }
    public func combined(with other: AnyTransitionShim) -> AnyTransitionShim { self }
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

/// 修飾を1枚かぶせた View。本物と同じく**かぶせるたびに型が変わる**。
public struct ModifiedContent<Content, Modifier>: View {
    nonisolated public init() {}
    public var body: Never { fatalError("模型") }
}

/// 修飾子の種類。型を分けるためだけの印。
public enum Mod {
    public enum Layout {}
    public enum Style {}
    public enum Input {}
    public enum Navigation {}
    public enum Lifecycle {}
    public enum Accessibility {}
}

extension View {
    // 並びと大きさ
    public func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func frame(minWidth: Double? = nil, maxWidth: Double? = nil, minHeight: Double? = nil,
                      maxHeight: Double? = nil, alignment: Alignment = .center) -> Self { self }
    public func padding(_ length: Double? = nil) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func padding(_ edges: Edge.Set, _ length: Double? = nil) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func aspectRatio(_ ratio: Double? = nil, contentMode: ContentMode) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func offset(x: Double = 0, y: Double = 0) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func position(x: Double, y: Double) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func clipped() -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// 場所は取るが描かない（本物と同じ）
    public func hidden() -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// 重なりの順（本物と同じ）
    public func zIndex(_ value: Double) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func clipShape<S: Shape>(_ shape: S) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func ignoresSafeArea() -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// 揃えの位置を自分で決める（本物と同じ）
    public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// 端を選んで安全領域を無視する（本物は `regions:` も取る）
    public func ignoresSafeArea(edges: Edge.Set) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// 画面の端に貼り付く帯（iOS 15+）。本物はスクロールの底の余白も足す。
    /// 模型は素通し——キーボードで持ち上がるかは Mac で見る
    public func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center,
                                       spacing: CGFloat? = nil,
                                       @ViewBuilder content: () -> V) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// 見た目の薄さ。**押せなくはならない**（本物と同じ。押せなくするのは `disabled`）
    public func opacity(_ value: Double) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 折り返しを縦に伸ばす（本物と同じ）。長い説明文が1行に潰れないように
    public func fixedSize(horizontal: Bool, vertical: Bool) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func fixedSize() -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func scaledToFit() -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func scaledToFill() -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func lineLimit(_ n: Int) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// **nil は「制限しない」**（本物と同じ）。折りたたみの展開で使う
    public func lineLimit(_ n: Int?) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func lineLimit(_ range: ClosedRange<Int>) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func lineLimit(_ range: PartialRangeFrom<Int>) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func multilineTextAlignment(_ a: TextAlignment) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func lineSpacing(_ v: Double) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func minimumScaleFactor(_ v: Double) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func tracking(_ v: Double) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func dynamicTypeSize(_ range: PartialRangeThrough<DynamicTypeSize>) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func textCase(_ c: Text.Case?) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func underline(_ on: Bool = true, color: Color? = nil) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }

    // 見た目
    public func font(_ f: Font?) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 記号の色を2つに塗り分ける版（本物にもある。`xmark.circle.fill` の
    /// ×と丸を別の色にするのに使う）
    public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2)
        -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func background<S: ShapeStyle>(_ s: S) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 安全域まで伸ばす辺を言う版（本物は既定が `.all`）
    public func background<S: ShapeStyle>(_ s: S, ignoresSafeAreaEdges edges: Edge.Set) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func background<S: ShapeStyle, T: Shape>(_ s: S, in shape: T) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 後ろに View を敷く版（本物にもある）。`alignment` で寄せる
    public func background<V: View>(alignment: Alignment = .center,
                                    @ViewBuilder _ content: () -> V) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func tint(_ c: Color?) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func listRowBackground<V: View>(_ view: V) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 行の余白（本物と同じ）。`ProfileEditView` のカバーを端まで広げるのに使う
    public func listRowInsets(_ insets: EdgeInsets?) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    /// 一覧の形（本物と同じ）
    public func listStyle(_ style: ListStyleShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 行の区切り線を出すか（本物と同じ。`.listRowBackground(.clear)` では線は消えない）
    public func listRowSeparator(_ visibility: VisibilityShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func mask<V: View>(@ViewBuilder _ content: () -> V) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func shadow(radius: Double) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func shadow(color: Color, radius: Double, x: Double = 0, y: Double = 0) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func transition(_ t: AnyTransitionShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func allowsHitTesting(_ v: Bool) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func rotationEffect(_ a: Angle) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func presentationBackground<S: ShapeStyle>(_ s: S) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func presentationDragIndicator(_ v: VisibilityShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// シートの高さ（本物と同じ）
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func contentShape<T: Shape>(_ shape: T) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    // 黒地に揃えるために使う（`WebTheme`）。模型なので何も描かない
    public func scrollContentBackground(_ v: VisibilityShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func preferredColorScheme(_ s: ColorSchemeShim?) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func toolbarBackground<S: ShapeStyle>(_ s: S, for bars: ToolbarPlacementShim...) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func toolbarColorScheme(_ s: ColorSchemeShim?, for bars: ToolbarPlacementShim...) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func toolbar(_ v: VisibilityShim, for bars: ToolbarPlacementShim...) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func overlay<V: View>(_ content: V, alignment: Alignment = .center) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func buttonStyle(_ s: PrimitiveButtonStyleShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 自前の押し方（本物と同じ）
    public func buttonStyle<S: ButtonStyle>(_ s: S) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func pickerStyle(_ s: PickerStyleShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func textFieldStyle(_ s: TextFieldStyleShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func controlSize(_ s: ControlSizeShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func labelsHidden() -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// スクロールでキーボードを下げる（本物と同じ）
    public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardModeShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func focused(_ condition: Binding<Bool>) -> Self { self }
    public func disabled(_ v: Bool) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func tag<V: Hashable>(_ v: V) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func badge(_ count: Int) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func id<V: Hashable>(_ v: V) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }

    // 入力
    public func keyboardType(_ t: UIKeyboardTypeShim) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    public func textContentType(_ t: UITextContentTypeShim) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    public func textInputAutocapitalization(_ a: TextInputAutocapitalization) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    public func autocorrectionDisabled(_ disabled: Bool = true) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    public func searchable(text: Binding<String>, placement: SearchFieldPlacementShim = .automatic,
                           prompt: String? = nil) -> Self { self }
    public func onSubmit(of t: SubmitTriggerShim = .search, _ action: @escaping () -> Void) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    /// シートを下へ払って閉じるのを止める（iOS 15+）
    public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> Self { self }
    /// キーボードの確定キーの文言（iOS 15+）
    public func submitLabel(_ label: SubmitLabel) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }

    // 画面遷移と入れ物
    public func navigationTitle(_ title: String) -> ModifiedContent<Self, Mod.Navigation> { ModifiedContent() }
    public func navigationBarTitleDisplayMode(_ m: NavigationBarItem.TitleDisplayMode) -> ModifiedContent<Self, Mod.Navigation> { ModifiedContent() }
    public func navigationDestination<D: Hashable, V: View>(
        for data: D.Type, @ViewBuilder destination: @escaping (D) -> V) -> Self { self }
    public func toolbar<C: ToolbarContent>(@ToolbarContentBuilder content: () -> C) -> ModifiedContent<Self, Mod.Navigation> { ModifiedContent() }
    public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> ModifiedContent<Self, Mod.Navigation> { ModifiedContent() }
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
    /// 下から出る選択肢（本物は iOS 15 以降）。`Menu` と違い `isPresented` を
    /// 持つので、開いている間に自動送りを止められる
    public func confirmationDialog<A: View>(_ title: String, isPresented: Binding<Bool>,
                                            titleVisibility: VisibilityShim = .automatic,
                                            @ViewBuilder actions: () -> A) -> Self { self }

    /// 本物にある `message:` 付きの形（iOS 15 以降）。確認の前に
    /// 「何が起きるか」を1行添える画面で使う
    public func confirmationDialog<A: View, M: View>(_ title: String, isPresented: Binding<Bool>,
                                                     titleVisibility: VisibilityShim = .automatic,
                                                     @ViewBuilder actions: () -> A,
                                                     @ViewBuilder message: () -> M) -> Self { self }

    // 仕掛け
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping () async -> Void) -> ModifiedContent<Self, Mod.Lifecycle> { ModifiedContent() }
    public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated,
                                   _ action: @escaping () async -> Void) -> Self { self }
    public func refreshable(action: @escaping () async -> Void) -> ModifiedContent<Self, Mod.Lifecycle> { ModifiedContent() }
    public func onAppear(perform action: (() -> Void)? = nil) -> ModifiedContent<Self, Mod.Lifecycle> { ModifiedContent() }
    public func onDisappear(perform action: (() -> Void)? = nil) -> ModifiedContent<Self, Mod.Lifecycle> { ModifiedContent() }
    public func onChange<V: Equatable>(of value: V, _ action: @escaping (V, V) -> Void) -> ModifiedContent<Self, Mod.Lifecycle> { ModifiedContent() }
    public func environmentObject<T: ObservableObject>(_ object: T) -> ModifiedContent<Self, Mod.Lifecycle> { ModifiedContent() }

    // 読み上げ
    public func accessibilityLabel(_ label: String) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
    /// 中身の読み上げをまとめる（本物と同じ）。ロゴのように
    /// 「記号＋2語」で1つの名前になるものに要る
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
    /// 起動スモーク（`UITests/`）から画面の部品を名札で指すためのもの。
    /// **模型にも置く**——置かないと Linux 側のビルドだけが落ちる
    public func accessibilityIdentifier(_ id: String) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
    public func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
    /// 読み上げの補足（本物と同じ）。`DailyThemeCard` が使う——**模型に無いと
    /// Linux 側のビルドだけが落ちる**（75f98e2 で main がそうなっていた）
    public func accessibilityHint(_ hint: String) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
    public func accessibilityValue(_ value: String) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }

    // 一覧の操作
    public func contextMenu<C: View>(@ViewBuilder menuItems: () -> C) -> ModifiedContent<Self, Mod.Navigation> { ModifiedContent() }
    public func accessibilityAction(named name: String, _ handler: @escaping () -> Void) -> ModifiedContent<Self, Mod.Accessibility> { ModifiedContent() }
    public func swipeActions<C: View>(@ViewBuilder content: () -> C) -> ModifiedContent<Self, Mod.Navigation> { ModifiedContent() }
}

// MARK: - 指の操作（模型）

public protocol Gesture {}

/// 2本指で回す（文字と札の回し）
public struct RotationGesture: Gesture {
    public init() {}
    public func onChanged(_ action: @escaping (Angle) -> Void) -> RotationGesture { self }
    public func onEnded(_ action: @escaping (Angle) -> Void) -> RotationGesture { self }
}

public struct MagnificationGesture: Gesture {
    public init(minimumScaleDelta: Double = 0.01) {}
    public func onChanged(_ action: @escaping (Double) -> Void) -> MagnificationGesture { self }
    public func onEnded(_ action: @escaping (Double) -> Void) -> MagnificationGesture { self }
}

public struct TapGesture: Gesture {
    public init(count: Int = 1) {}
}

public struct TabViewStyleShim {
    public static let page = TabViewStyleShim()
    public static let automatic = TabViewStyleShim()
}

public struct IndexDisplayModeShim {
    public static let never = IndexDisplayModeShim()
    public static let always = IndexDisplayModeShim()
}

extension TabViewStyleShim {
    public static func page(indexDisplayMode: IndexDisplayModeShim) -> TabViewStyleShim { .page }
}

extension View {
    public func gesture<G: Gesture>(_ gesture: G) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    /// 本物の SwiftUI に在るので、模型にも置く。**無いと、実機で通る書き方が
    /// 手元だけで落ちる**（ストーリーのスワイプで実際にそうなった）
    public func simultaneousGesture<G: Gesture>(_ gesture: G) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    public func highPriorityGesture<G: Gesture>(_ gesture: G) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    /// 長押し。`onPressingChanged` は指の着地で true・離れで false を返す
    /// （本物の SwiftUI と同じ形。押している間だけ止める、に使う）
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                   perform action: @escaping () -> Void,
                                   onPressingChanged: ((Bool) -> Void)? = nil) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    public func scaleEffect(_ scale: Double) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func tabViewStyle(_ style: TabViewStyleShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func statusBarHidden(_ hidden: Bool = true) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
}

/// 行の余白（本物と同じ形）
public struct EdgeInsets {
    /// 本物と同じく4辺を読める（`GeometryProxy.safeAreaInsets.top` など）
    public var top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0
    public init() {}
    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = CGFloat(top); self.leading = CGFloat(leading)
        self.bottom = CGFloat(bottom); self.trailing = CGFloat(trailing)
    }
}

/// `submitLabel(_:)` が受ける確定キーの文言。本物は struct
public struct SubmitLabel {
    public static let done = SubmitLabel(), go = SubmitLabel(), send = SubmitLabel(),
                      search = SubmitLabel(), next = SubmitLabel(), `return` = SubmitLabel()
}
