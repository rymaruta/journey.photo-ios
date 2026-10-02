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
            // ロゴと同じ New York Bold（端末の serif）
            let base = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: fontSize) } ?? base
            let kern = Watermark.tracking(fontSize: fontSize)
            let text = Watermark.text as NSString
            let textSize = text.size(withAttributes: [.font: font, .kern: kern])
            let mark = UIImage(named: Watermark.markAssetName)
            let markSide = mark == nil ? 0 : Watermark.markSize(fontSize: fontSize)
            let gap = mark == nil ? 0 : Watermark.markGap(fontSize: fontSize)
            // マーク＋間＋字をひとかたまりとして右下に寄せる
            let block = CGSize(width: Double(textSize.width) + markSide + gap, height: Double(textSize.height))
            let origin = Watermark.origin(text: block, canvas: size, margin: Watermark.margin(fontSize: fontSize))
            let textOrigin = CGPoint(x: Double(origin.x) + markSide + gap, y: Double(origin.y))
            // 明るい写真の上でも読めるよう、少しずらした薄い影を先に描く
            let offset = max(1, fontSize * 0.04)
            let shadow = UIColor.black.withAlphaComponent(0.35)
            let white = UIColor.white.withAlphaComponent(Watermark.alpha)
            if let mark {
                // 字の高さの真ん中にマークの真ん中を合わせる
                let markRect = CGRect(x: Double(origin.x), y: Double(origin.y) + (Double(textSize.height) - markSide) / 2,
                                      width: markSide, height: markSide)
                mark.withTintColor(.black, renderingMode: .alwaysOriginal)
                    .draw(in: markRect.offsetBy(dx: offset, dy: offset), blendMode: .normal, alpha: 0.35)
                mark.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: markRect, blendMode: .normal, alpha: Watermark.alpha)
            }
            text.draw(at: CGPoint(x: textOrigin.x + offset, y: textOrigin.y + offset),
                      withAttributes: [.font: font, .kern: kern, .foregroundColor: shadow])
            text.draw(at: textOrigin, withAttributes: [.font: font, .kern: kern, .foregroundColor: white])
        }
    }
}
