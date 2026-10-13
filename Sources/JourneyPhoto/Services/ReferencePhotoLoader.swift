import Foundation
import ImageIO

/// 写真ライブラリの参考画像を端末内で縮小する。元画像の画素を全展開せず ImageIO で読む。
/// 書き出した JPEG はこの画面のプレビュー専用で、サーバーには渡さない。
enum ReferencePhotoLoader {
    static let maxPixelSize = 1920

    static func previewJPEG(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = ImagePreparer.downsampledImage(source: source, maxPixelSize: maxPixelSize) else {
            throw ImagePreparer.PrepareError.unreadable
        }
        // EXIF の向きを画素に焼き込み、撮影位置等のメタデータを残さない。
        return try ImagePreparer.encodeStripped(image)
    }
}
