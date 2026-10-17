// 旅のトランク（2026-10-17）で使う描く口の模型。**形だけ**で、実機では一切使わない。
// 本物と同じ名前・同じ引数ラベルで宣言する（`Canvas`・`GraphicsContext`・`EllipticalGradient`・
// `ImageRenderer`・自作の `Shape` の `fill`）。

/// 楕円のグラデーション（枠いっぱいの楕円に沿う・本物と同じ）
public struct EllipticalGradient: View, ShapeStyle {
    nonisolated public init(stops: [Gradient.Stop], center: UnitPoint = .center,
                startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {}
    nonisolated public init(colors: [Color], center: UnitPoint = .center,
                startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {}
    public var body: Never { fatalError("模型") }
}

extension Gradient {
    public init(stops: [Gradient.Stop]) { self.init() }
    public init(colors: [Color]) { self.init() }
}

/// 自由に描く面（本物は iOS 15+）
public struct Canvas: View {
    public init(opaque: Bool = false, rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {}
    public var body: Never { fatalError("模型") }
}

/// `Canvas` の描く先（使う口だけ）
public struct GraphicsContext {
    public struct Shading {
        public static func color(_ color: Color) -> Shading { Shading() }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint) -> Shading { Shading() }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat,
                                          endRadius: CGFloat) -> Shading { Shading() }
    }
    public var opacity: Double = 1
    public func fill(_ path: Path, with shading: Shading) {}
    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {}
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {}
    public mutating func translateBy(x: CGFloat, y: CGFloat) {}
    public mutating func rotate(by angle: Angle) {}
    public mutating func scaleBy(x: CGFloat, y: CGFloat) {}
    public mutating func clip(to path: Path) {}
}

/// 画面の部品を1枚の絵にする（本物は iOS 16+）
@MainActor
public final class ImageRenderer<Content: View> {
    public var scale: CGFloat = 1
    public var isOpaque = false
    public var proposedSize = ProposedViewSize()
    public init(content: Content) {}
    public var uiImage: UIImage? { nil }
}

extension Shape {
    /// 塗る（本物は `some View`）。自作の形（ラベルの輪郭）に使う
    @MainActor public func fill<S: ShapeStyle>(_ style: S) -> Rectangle { Rectangle() }
}

extension View {
    /// 重ねた層を1枚にまとめてから効果をかける（本物と同じ）
    public func compositingGroup() -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 画面の外で1枚の絵に描いてから置く（細かい模様の重さを抑える）
    public func drawingGroup() -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// 傾き（回す中心つき）
    public func rotationEffect(_ a: Angle, anchor: UnitPoint) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
}
