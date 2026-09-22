// 画面の部品（模型）。**中身は持たない**。
import Foundation

public struct Text: View {
    public init(_ s: String) {}
    public init(_ s: Substring) {}
    public init<S: StringProtocol>(_ s: S) {}
    public var body: Never { fatalError("模型") }
}

public struct Image: View {
    public init(systemName: String) {}
    public init(uiImage: UIImageShim) {}
    public func resizable() -> Image { self }
    public func aspectRatio(_ ratio: Double? = nil, contentMode: ContentMode) -> Image { self }
    public var body: Never { fatalError("模型") }
}

public struct Label: View {
    /// 題と絵を別々に渡す版（数字と記号を組にするときに使う）
    public init<T: View, I: View>(@ViewBuilder _ title: () -> T, @ViewBuilder icon: () -> I) {}
    public init(_ title: String, systemImage: String) {}
    public init<S: StringProtocol>(_ title: S, systemImage: String) {}
    public var body: Never { fatalError("模型") }
}

public struct Button: View {
    public init<L: View>(action: @escaping () -> Void, @ViewBuilder label: () -> L) {}
    public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) {}
    public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) {}
    public init<L: View>(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}
public struct ButtonRole {
    public static let destructive = ButtonRole(), cancel = ButtonRole()
}

public struct VStack: View {
    public init<C: View>(alignment: HorizontalAlignment = .center, spacing: Double? = nil,
                         @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}
public struct LazyVStack: View {
    public init<C: View>(alignment: HorizontalAlignment = .center, spacing: Double? = nil,
                         pinnedViews: PinnedScrollableViews = [], @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}
public struct PinnedScrollableViews: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
}
public struct HStack: View {
    public init<C: View>(alignment: VerticalAlignment = .center, spacing: Double? = nil,
                         @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}
public struct ZStack: View {
    public init<C: View>(alignment: Alignment = .center, @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}
public struct Group: View {
    public init<C: View>(@ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}
public struct Spacer: View {
    public init(minLength: Double) {}
    public init() {}
    public var body: Never { fatalError("模型") }
}
public struct Divider: View {
    public init() {}
    public var body: Never { fatalError("模型") }
}
public struct ProgressView: View {
    public init() {}
    public var body: Never { fatalError("模型") }
}

public struct ScrollView: View {
    public init<C: View>(_ axes: Axis = .vertical, showsIndicators: Bool = true,
                         @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

public struct GridItem {
    public enum Size {
        case flexible(minimum: Double = 10, maximum: Double = .infinity)
        case fixed(Double)
        case adaptive(minimum: Double, maximum: Double = .infinity)
    }
    public init(_ size: Size = .flexible(), spacing: Double? = nil, alignment: Alignment? = nil) {}
}
public struct LazyVGrid: View {
    public init<C: View>(columns: [GridItem], spacing: Double? = nil, @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

public struct ForEach: View {
    public init<D: RandomAccessCollection, C: View>(
        _ data: D, @ViewBuilder content: @escaping (D.Element) -> C) where D.Element: Identifiable {}
    public init<D: RandomAccessCollection, ID: Hashable, C: View>(
        _ data: D, id: KeyPath<D.Element, ID>, @ViewBuilder content: @escaping (D.Element) -> C) {}
    public var body: Never { fatalError("模型") }
}

public struct List: View {
    public init<C: View>(@ViewBuilder content: () -> C) {}
    public init<D: RandomAccessCollection, C: View>(
        _ data: D, @ViewBuilder rowContent: @escaping (D.Element) -> C) where D.Element: Identifiable {}
    public var body: Never { fatalError("模型") }
}
public struct Section: View {
    public init<C: View>(@ViewBuilder content: () -> C) {}
    public init<C: View>(_ title: String, @ViewBuilder content: () -> C) {}
    public init<C: View, F: View>(@ViewBuilder content: () -> C, @ViewBuilder footer: () -> F) {}
    public init<C: View, H: View, F: View>(@ViewBuilder content: () -> C,
                                           @ViewBuilder header: () -> H,
                                           @ViewBuilder footer: () -> F) {}
    public init<C: View, H: View>(@ViewBuilder content: () -> C, @ViewBuilder header: () -> H) {}
    public var body: Never { fatalError("模型") }
}
public struct Form: View {
    public init<C: View>(@ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

public struct TextField: View {
    public init(_ title: String, text: Binding<String>) {}
    public init(_ title: String, text: Binding<String>, axis: Axis) {}
    public var body: Never { fatalError("模型") }
}
public struct SecureField: View {
    public init(_ title: String, text: Binding<String>) {}
    public var body: Never { fatalError("模型") }
}
public struct Toggle: View {
    public init(_ title: String, isOn: Binding<Bool>) {}
    /// 札を自分で組む版（本物にもある。説明を2行にするのに使う）
    public init<L: View>(isOn: Binding<Bool>, @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}
public struct Picker: View {
    public init<S, C: View>(_ title: String, selection: Binding<S>, @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}
public struct Menu: View {
    public init<C: View, L: View>(@ViewBuilder content: () -> C, @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}
public struct Link: View {
    public init(_ title: String, destination: URL) {}
    public init<L: View>(destination: URL, @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}
public struct ShareLink: View {
    public init(item: URL) {}
    public init<L: View>(item: URL, @ViewBuilder label: () -> L) {}
    /// 文字を配る版（本物にもある）。URL を持たないもの——地点の名前など——を配る
    public init(item: String) {}
    public init<L: View>(item: String, @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}

public struct NavigationStack: View {
    public init<R: View>(@ViewBuilder root: () -> R) {}
    public var body: Never { fatalError("模型") }
}
public struct NavigationLink: View {
    public init<D: View, L: View>(@ViewBuilder destination: () -> D, @ViewBuilder label: () -> L) {}
    public init<D: View>(_ title: String, @ViewBuilder destination: () -> D) {}
    public init<V: Hashable, L: View>(value: V, @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}
public struct TabView: View {
    public init<S, C: View>(selection: Binding<S>, @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

public struct Circle: View, Shape {
    public init() {}
    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double) -> Circle { self }
    public func fill<S: ShapeStyle>(_ style: S) -> Circle { self }
    public var body: Never { fatalError("模型") }
}
public struct Stepper: View {
    public init<L: View>(value: Binding<Int>, in range: ClosedRange<Int>, @ViewBuilder label: () -> L) {}
    public var body: Never { fatalError("模型") }
}
public struct Capsule: View, Shape {
    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double) -> Capsule { self }
    public func fill<S: ShapeStyle>(_ style: S) -> Capsule { self }
    public init() {}
    public var body: Never { fatalError("模型") }
}
public struct RoundedRectangle: View, Shape {
    public init(cornerRadius: Double) {}
    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double) -> RoundedRectangle { self }
    public func fill<S: ShapeStyle>(_ style: S) -> RoundedRectangle { self }
    public var body: Never { fatalError("模型") }
}
public protocol Shape {}

public struct AsyncImage: View {
    public init<C: View>(url: URL?, transaction: Transaction = Transaction(),
                         @ViewBuilder content: @escaping (AsyncImagePhase) -> C) {}
    public var body: Never { fatalError("模型") }
}
public enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)
}

// MARK: - App

@MainActor
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }
    init()
}
extension App {
    public static func main() {}
}
public protocol Scene {}
@resultBuilder
public struct SceneBuilder {
    public static func buildBlock<S: Scene>(_ s: S) -> S { s }
}
public struct WindowGroup: Scene {
    public init<C: View>(@ViewBuilder content: () -> C) {}
}

// MARK: - Layout

public protocol Layout {
    associatedtype Cache = Void
    typealias Subviews = LayoutSubviews
    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Cache)
}
extension Layout {
    @MainActor public func callAsFunction<C>(@ViewBuilder _ content: () -> C) -> AnyView { AnyView() }
}
public struct ProposedViewSize {
    public var width: Double?
    public var height: Double?
    public init() {}
    public init(_ size: CGSize) {}
    public static let unspecified = ProposedViewSize()
}
public struct LayoutSubviews: RandomAccessCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { 0 }
    public subscript(position: Int) -> LayoutSubview { LayoutSubview() }
}
public struct LayoutSubview {
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { CGSize(width: 0, height: 0) }
    public func place(at: CGPoint, proposal: ProposedViewSize) {}
}

/// 四角。`contentShape` に渡して「押せる範囲」を決めるのに使う。
public struct Rectangle: View, Shape {
    public init() {}
    public func fill<S: ShapeStyle>(_ style: S) -> Rectangle { self }
    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double) -> Rectangle { self }
    public var body: Never { fatalError() }
}

/// 置き場所の大きさを測る入れ物（写真の上に文字を置くのに要る）。
public struct GeometryProxy {
    public var size: CGSize { CGSize(width: 0, height: 0) }
}

public struct GeometryReader<Content: View>: View {
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {}
    public var body: Never { fatalError("模型") }
}

/// 指でつまんで動かす。
public struct DragGesture: Gesture {
    public struct Value {
        public var translation: CGSize { CGSize(width: 0, height: 0) }
        public var location: CGPoint { CGPoint(x: 0, y: 0) }
    }
    public init(minimumDistance: Double = 10) {}
    public func onChanged(_ action: @escaping (Value) -> Void) -> DragGesture { self }
    public func onEnded(_ action: @escaping (Value) -> Void) -> DragGesture { self }
}

/// つまみ（文字の大きさを決めるのに使う）。
public struct Slider: View {
    public init(value: Binding<Double>, in range: ClosedRange<Double>) {}
    public var body: Never { fatalError("模型") }
}
