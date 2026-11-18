#if !os(Linux)
import UIKit
import CoreText

/// 共有の絵「写真の色」を描く（寸法・色の取り方・字は `PhotoColorCard`）。ストーリーと投稿の両方から呼ぶ。
///
/// 地は写真から取った淡い色、字は写真から取った濃い色（どちらも `PhotoColorCard.tone`・字と地の明暗の比 7:1 以上）。
/// 写真は切らずに置き、上には何も重ねない。真鍮は使わない（黒い地ではない・板「黒塗りの真鍮」）。
/// 区切りに「・」を使わない（県と市は空白、日付は位置で分ける）。
///
/// 書き出しは `UIGraphicsImageRenderer` で描き直すので、元の写真の EXIF（位置）は引き継がない。倍率は 1。
enum PhotoColorCardRenderer {
    typealias C = PhotoColorCard

    /// 写真の地と字の色（64×64 に縮めた画素から・`SignatureShareCardRenderer.samplePixels`）
    static func tone(_ photo: UIImage) -> C.Tone {
        let raw = SignatureShareCardRenderer.samplePixels(photo, side: C.sampleSide)
        let pixels = stride(from: 0, to: raw.count, by: 4).map {
            C.RGB(Double(raw[$0]), Double(raw[$0 + 1]), Double(raw[$0 + 2]))
        }
        return C.tone(pixels: pixels)
    }

    static func color(_ c: C.RGB) -> UIColor {
        UIColor(red: c.red / 255, green: c.green / 255, blue: c.blue / 255, alpha: 1)
    }

    /// 1枚の JPEG を描く
    static func render(photo: UIImage, texts: C.Texts, frame: C.Frame) -> Data {
        let size = CGSize(width: C.width, height: frame.height)
        let colors = tone(photo)
        let aspect = photo.size.height > 0 ? photo.size.width / photo.size.height : 1
        let placement = C.place(aspect: aspect, in: frame)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.93) { context in
            color(colors.ground).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            // 写真は縦横比のまま枠に入れる（枠の縦横比が写真と同じなので切れない）
            photo.draw(in: placement.photo)
            drawBlock(texts, in: placement.text, ink: color(colors.ink))
        }
    }

    /// 字の段（撮影地・県と市・日付）
    static func drawBlock(_ texts: C.Texts, in block: CGRect, ink: UIColor) {
        // 撮影地が最小の字でも入らなければ、一つ上の単位を大きく出す（`Texts.widened`）。それも入らなければ末尾を切り詰める
        var shown = texts
        if let place = texts.place, let widened = texts.widened,
           width(place, font: mincho(C.placeMinimumSize, for: place), kern: C.placeKern) > block.width {
            shown = widened
        }
        if let place = shown.place {
            fitted(place, font: { mincho($0, for: place) }, size: C.placeSize, minimum: C.placeMinimumSize,
                   kern: C.placeKern, color: ink, x: block.minX, y: block.minY + C.placeY, maxWidth: block.width)
        }
        var dateWidth: CGFloat = 0
        if let date = shown.date {
            dateWidth = line(date, font: sans(C.rowSize, .medium), color: ink, kern: C.dateKern,
                             x: block.minX, y: block.minY + C.rowY, maxWidth: block.width, align: .right)
        }
        if let region = shown.region {
            let maxWidth = block.width - (dateWidth > 0 ? dateWidth + C.rowGap : 0)
            fitted(region, font: { sans($0, .regular) }, size: C.rowSize, minimum: C.rowMinimumSize, kern: 0,
                   color: ink, x: block.minX, y: block.minY + C.rowY, maxWidth: maxWidth)
        }
    }

    // MARK: - 字の下回り

    /// SF（数字は等幅）
    static func sans(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// 明朝。同梱の Shippori Mincho B1（JIS 第1水準まで）に無い字が1つでもあれば、語ぜんぶを端末の明朝にする
    /// （1語の中で字の形が混ざらないように）
    static func mincho(_ size: CGFloat, for text: String) -> UIFont {
        if let font = UIFont(name: JPFont.displayName, size: size), covers(font, text) { return font }
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    static func covers(_ font: UIFont, _ text: String) -> Bool {
        var units = Array(text.utf16)
        guard !units.isEmpty else { return true }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font as CTFont, &units, &glyphs, units.count)
    }

    static func attributes(_ font: UIFont, color: UIColor, kern: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .kern: kern * font.pointSize, .paragraphStyle: paragraph]
    }

    /// 字の幅（字間は最後の字の後ろにも付くので引く）
    static func width(_ value: String, font: UIFont, kern: CGFloat) -> CGFloat {
        ceil((value as NSString).size(withAttributes: attributes(font, color: .black, kern: kern)).width
             - (kern > 0 ? kern * font.pointSize : 0))
    }

    /// 幅に入るまで 1 ずつ縮めて1行（下限まで縮めても入らなければ末尾を切り詰める）
    static func fitted(_ value: String, font: (CGFloat) -> UIFont, size: CGFloat, minimum: CGFloat, kern: CGFloat,
                       color: UIColor, x: CGFloat, y: CGFloat, maxWidth: CGFloat) {
        var current = size
        while current > minimum, width(value, font: font(current), kern: kern) > maxWidth {
            current -= 1
        }
        line(value, font: font(current), color: color, kern: kern, x: x, y: y, maxWidth: maxWidth)
    }

    /// 1行を描き、描いた幅を返す。点検（`ShareCardProbe`）に枠と色を記録する
    @discardableResult
    static func line(_ value: String, font: UIFont, color: UIColor, kern: CGFloat, x: CGFloat, y: CGFloat,
                     maxWidth: CGFloat, align: NSTextAlignment = .left) -> CGFloat {
        let full = width(value, font: font, kern: kern)
        let shown = min(maxWidth, full)
        let left = align == .right ? x + maxWidth - shown : x
        // 記録する枠の高さは字の大きさの 1.3 倍まで（明朝の行の高さは下の余白が大きい・`drawFittedSerif` と同じ）
        let rect = CGRect(x: left, y: y, width: shown, height: min(font.lineHeight, font.pointSize * 1.3))
        if ShareCardProbe.note(.text, value, rect: rect, color: color, fontSize: font.pointSize,
                               truncated: full > maxWidth) {
            (value as NSString).draw(in: CGRect(x: left, y: y, width: shown + (kern > 0 ? kern * font.pointSize : 0) + 1,
                                                height: font.lineHeight + 2),
                                     withAttributes: attributes(font, color: color, kern: kern))
        }
        return shown
    }
}
#endif
