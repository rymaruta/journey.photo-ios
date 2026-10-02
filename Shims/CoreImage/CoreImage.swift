// Core Image の模型（Linux で型検査するためだけのもの）。写真の編集（`PhotoRenderer`）が
// 使う口の**形**だけを置く。どれも何もしない（フィルターは作れず、描いても nil）。
//
// `#if canImport(CoreImage)` で描く側を丸ごと外さずに模型を足したのは、ほかの SDK と
// 同じく**描く側のコードも型検査したい**から（綴り違い・引数ラベル・型の取り違えは
// ここで捕まる）。外すと、Mac のワークフローまで1行も検査されない
import ImageIO
import Foundation

public final class CIImage {
    public init(cgImage: CGImage) {}
    public var extent: CGRect { .zero }
    public func cropped(to rect: CGRect) -> CIImage { self }
}

/// 本物は `NSObject` の子で、引数は KVC（`setValue(_:forKey:)`）で渡す
open class CIFilter {
    public init?(name: String) { return nil }
    open func setValue(_ value: Any?, forKey key: String) {}
    open var outputImage: CIImage? { nil }
    open var inputKeys: [String] { [] }
}

public final class CIVector {
    public init(x: CGFloat, y: CGFloat) {}
}

public struct CIFormat: Equatable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let RGBA8 = CIFormat(rawValue: 0)
}

public struct CIContextOption: Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let workingColorSpace = CIContextOption(rawValue: "working_color_space")
}

public final class CIContext {
    public init() {}
    public init(options: [CIContextOption: Any]?) {}
    public func createCGImage(_ image: CIImage, from fromRect: CGRect,
                              format: CIFormat, colorSpace: CGColorSpace?) -> CGImage? { nil }
}

public let kCIInputImageKey = "inputImage"
