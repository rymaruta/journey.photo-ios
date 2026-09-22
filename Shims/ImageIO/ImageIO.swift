// ImageIO / CoreGraphics の模型。**EXIF を落とす関所**（`ImagePreparer`）を
// 型検査するために要る。
import Foundation

public typealias CFString = String
public typealias CFDictionary = NSDictionary
public typealias CFData = NSData
public typealias CFMutableData = NSMutableData

public final class CGImageSource {}
public final class CGImageDestination {}
public final class CGImage {
    public var width: Int { 0 }
    public var height: Int { 0 }
}

// MARK: - 画素を読むための最小限（CoreGraphics。本物にある口だけ）

public final class CGColorSpace {}
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }

public struct CGBitmapInfo: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 1 << 0)
}

public enum CGImageAlphaInfo: UInt32 {
    case premultipliedLast = 1
    case noneSkipLast = 6
}

public final class CGContext {
    /// 自前の入れ物に描く版（代表色を数えるのに使う）
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int,
                 bitsPerComponent: Int, bytesPerRow: Int,
                 space: CGColorSpace, bitmapInfo: UInt32) { return nil }
    public func draw(_ image: CGImage, in rect: CGRect) {}
}

public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? { nil }
public func CGImageSourceGetCount(_ source: CGImageSource) -> Int { 0 }
public func CGImageSourceCopyPropertiesAtIndex(_ source: CGImageSource, _ index: Int,
                                               _ options: CFDictionary?) -> CFDictionary? { nil }
public func CGImageSourceCreateThumbnailAtIndex(_ source: CGImageSource, _ index: Int,
                                                _ options: CFDictionary?) -> CGImage? { nil }
public func CGImageDestinationCreateWithData(_ data: CFMutableData, _ type: CFString,
                                             _ count: Int, _ options: CFDictionary?) -> CGImageDestination? { nil }
public func CGImageDestinationAddImage(_ destination: CGImageDestination, _ image: CGImage,
                                       _ properties: CFDictionary?) {}
public func CGImageDestinationFinalize(_ destination: CGImageDestination) -> Bool { false }

// 読み書きに使う鍵。**名前が本物と一致していることが要**——ここが違うと
// 実機で「いつも nil」になり、EXIF が落ちたように見えて落ちていない
public let kCGImageSourceCreateThumbnailFromImageAlways: CFString = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceCreateThumbnailWithTransform: CFString = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceThumbnailMaxPixelSize: CFString = "kCGImageSourceThumbnailMaxPixelSize"
public let kCGImageDestinationLossyCompressionQuality: CFString = "kCGImageDestinationLossyCompressionQuality"
public let kCGImagePropertyExifDictionary: CFString = "{Exif}"
public let kCGImagePropertyGPSDictionary: CFString = "{GPS}"
public let kCGImagePropertyTIFFDictionary: CFString = "{TIFF}"
public let kCGImagePropertyTIFFMake: CFString = "Make"
public let kCGImagePropertyTIFFModel: CFString = "Model"
public let kCGImagePropertyExifLensModel: CFString = "LensModel"
public let kCGImagePropertyExifFNumber: CFString = "FNumber"
public let kCGImagePropertyExifExposureTime: CFString = "ExposureTime"
public let kCGImagePropertyExifISOSpeedRatings: CFString = "ISOSpeedRatings"
public let kCGImagePropertyExifFocalLength: CFString = "FocalLength"
public let kCGImagePropertyExifDateTimeOriginal: CFString = "DateTimeOriginal"
public let kCGImagePropertyExifBodySerialNumber: CFString = "BodySerialNumber"
public let kCGImagePropertyExifLensSerialNumber: CFString = "LensSerialNumber"
public let kCGImagePropertyGPSLatitude: CFString = "Latitude"
public let kCGImagePropertyGPSLongitude: CFString = "Longitude"
public let kCGImagePropertyGPSLatitudeRef: CFString = "LatitudeRef"
public let kCGImagePropertyGPSLongitudeRef: CFString = "LongitudeRef"
