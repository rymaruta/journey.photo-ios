import Foundation
import ImageIO

/// 写真から代表色を取り出す（`DominantColor` の実機側）。
///
/// **失敗しても投稿を止めない。** 色は「読み込み中の地の色」でしかないので、
/// 取れなければ属性ごと付けずに上げる（Web も同じ割り切り）。
///
/// 16×16 に縮めてから平均する。元のままだと 1200万画素を舐めることになり、
/// 端末の熱と時間を無駄に使う。
enum DominantColorExtractor {

    static func hex(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: DominantColor.sampleSize,
            // **向きを直してから縮める。** 直さないと縦横が入れ替わるが、
            // 平均を取るだけなので色は変わらない——それでも揃えておく
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let width = max(1, thumb.width)
        let height = max(1, thumb.height)
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drew: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(thumb, in: CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))
            return true
        }
        guard drew else { return nil }
        return DominantColor.hex(fromRGBA: bytes)
    }
}
