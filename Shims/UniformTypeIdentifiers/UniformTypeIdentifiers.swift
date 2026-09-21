// UniformTypeIdentifiers の模型。
import Foundation

public struct UTType {
    public let identifier: String
    public static let jpeg = UTType(identifier: "public.jpeg")
    public static let png = UTType(identifier: "public.png")
}
