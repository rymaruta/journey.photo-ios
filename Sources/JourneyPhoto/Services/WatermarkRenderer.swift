import UIKit

/// SNS に渡す画像を作る: 画素だけに書き出し直し（位置などの付帯情報を落とす）、右下に
/// 「Journey Photo」の透かしを入れる（`Watermark`）。重いので画面の処理の外で呼ぶ
enum WatermarkRenderer {

    /// 読めなければ nil
    static func apply(_ data: Data, quality: Double = 0.9) -> Data? {
        guard let source = UIImage(data: data) else { return nil }
        let size = Watermark.outputSize(image: source.size)
        let image = size == source.size ? source : (source.preparingThumbnail(of: size) ?? source)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            let fontSize = Watermark.fontSize(canvas: size)
            let font = UIFont(name: JPFont.displayName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let text = Watermark.text as NSString
            let textSize = text.size(withAttributes: [.font: font])
            let origin = Watermark.origin(text: textSize, canvas: size, margin: Watermark.margin(fontSize: fontSize))
            // 明るい写真の上でも読めるよう、少しずらした薄い影を先に描く
            let offset = max(1, fontSize * 0.04)
            text.draw(at: CGPoint(x: origin.x + offset, y: origin.y + offset),
                      withAttributes: [.font: font, .foregroundColor: UIColor.black.withAlphaComponent(0.35)])
            text.draw(at: origin, withAttributes: [.font: font,
                                                   .foregroundColor: UIColor.white.withAlphaComponent(Watermark.alpha)])
        }
    }
}
