#if !os(Linux)
import UIKit
import CoreText

/// 共有の絵「暦（差し色）」を描く（寸法と字は `KoyomiCard`）。ストーリーと投稿の両方から呼ぶ。
///
/// 地は写真の平均の色を額装と同じ決まりで暗くした一色（`ShareCardMap.MatColor`）。写真は切らずに置き、上には何も重ねない。
/// 字は白と、白を地に重ねた色（地が一色なので、重ねた色を先に混ぜて不透明の色で描く。点検 `ShareCardAuditTests` が
/// 字の色をそのまま明暗の比に使えるように）。真鍮は使わない（黒い地ではない・板「黒塗りの真鍮」）。
/// 区切りに「・」を使わない（3列は位置で分ける）。
///
/// 書き出しは `UIGraphicsImageRenderer` で描き直すので、元の写真の EXIF（位置）は引き継がない。倍率は 1。
enum KoyomiCardRenderer {
    typealias K = KoyomiCard

    /// 地の色（写真の平均の色から・額装と同じ）
    static func groundRGB(_ photo: UIImage) -> (red: Double, green: Double, blue: Double) {
        let average = SignatureShareCardRenderer.averageColor(photo)
        return ShareCardMap.MatColor.color(red: average.red, green: average.green, blue: average.blue)
    }

    /// 1枚の JPEG を描く
    static func render(photo: UIImage, texts: K.Texts, frame: K.Frame) -> Data {
        let size = CGSize(width: K.width, height: frame.height)
        let ground = groundRGB(photo)
        let groundColor = UIColor(red: ground.red / 255, green: ground.green / 255, blue: ground.blue / 255, alpha: 1)
        func ink(_ alpha: Double) -> UIColor {
            func mix(_ c: Double) -> CGFloat { CGFloat((c * (1 - alpha) + 255 * alpha) / 255) }
            return UIColor(red: mix(ground.red), green: mix(ground.green), blue: mix(ground.blue), alpha: 1)
        }
        let aspect = photo.size.height > 0 ? photo.size.width / photo.size.height : 1
        let placement = K.place(aspect: aspect, in: frame)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            groundColor.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // 写真は縦横比のまま枠に入れる（枠の縦横比が写真と同じなので切れない）
            photo.draw(in: placement.photo)
            drawBlock(texts, top: placement.blockTop, ink: ink, cg: cg)
        }
    }

    /// 字の段（`top` は段の上端）
    static func drawBlock(_ texts: K.Texts, top: CGFloat, ink: (Double) -> UIColor, cg: CGContext) {
        // 英字（右端 1008 にそろえる）を先に測り、名前は英字に掛からない幅に縮める
        var latinWidth: CGFloat = 0
        if let latin = texts.latin {
            latinWidth = line(latin, font: sans(K.latinSize, .medium), color: ink(K.Ink.latin), kern: K.latinKern,
                              x: K.left, y: top + K.latinY, maxWidth: K.contentWidth, align: .right)
        }
        let headingWidth = K.right - K.headingX - (latinWidth > 0 ? latinWidth + K.headingLatinGap : 0)
        fitted(texts.heading, serif: true, size: K.headingSize, minimum: K.headingMinimumSize, color: .white,
               x: K.headingX, y: top + K.headingY, maxWidth: headingWidth)

        // 細い線（飾り）
        if ShareCardProbe.drawsContent {
            ink(K.Ink.rule).setFill()
            cg.fill(CGRect(x: K.left, y: top + K.ruleY, width: K.contentWidth, height: 1))
        }

        // 3列の眉と値
        for (index, column) in texts.columns.prefix(K.columnX.count).enumerated() {
            let x = K.columnX[index]
            line(column.key, font: sans(K.eyebrowSize, .medium), color: ink(K.Ink.eyebrow), kern: K.eyebrowKern,
                 x: x, y: top + K.eyebrowY, maxWidth: K.columnWidth)
            if column.serif {
                fitted(column.value, serif: true, size: K.valueSize, minimum: K.valueMinimumSize, color: .white,
                       x: x, y: top + K.valueY, maxWidth: K.columnWidth)
            } else {
                fitted(column.value, serif: false, size: K.valueSize, minimum: K.valueMinimumSize, color: .white,
                       x: x, y: top + K.valueY, maxWidth: K.columnWidth)
            }
        }

        if let meaning = texts.meaning {
            line(meaning, font: sans(K.meaningSize, .regular), color: ink(K.Ink.meaning), kern: 0,
                 x: K.left, y: top + K.meaningY, maxWidth: K.contentWidth)
        }
    }

    // MARK: - 字の下回り

    static func sans(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// 明朝。同梱の Shippori Mincho B1（JIS 第1水準まで）に無い字が1つでもあれば、語ぜんぶを端末の明朝にする
    /// （1語の中で字の形が混ざらないように。啓蟄の「蟄」など）
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

    /// 幅に入るまで縮めて1行（下限まで縮めても入らなければ末尾を切り詰める）
    static func fitted(_ value: String, serif: Bool, size: CGFloat, minimum: CGFloat, color: UIColor,
                       x: CGFloat, y: CGFloat, maxWidth: CGFloat) {
        func font(_ s: CGFloat) -> UIFont { serif ? mincho(s, for: value) : sans(s, .medium) }
        var current = size
        while current > minimum, (value as NSString).size(withAttributes: [.font: font(current)]).width > maxWidth {
            current -= 1
        }
        line(value, font: font(current), color: color, kern: 0, x: x, y: y, maxWidth: maxWidth)
    }

    /// 1行を描き、描いた幅を返す。点検（`ShareCardProbe`）に枠と色を記録する
    @discardableResult
    static func line(_ value: String, font: UIFont, color: UIColor, kern: CGFloat, x: CGFloat, y: CGFloat,
                     maxWidth: CGFloat, align: NSTextAlignment = .left) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                         .kern: kern * font.pointSize, .paragraphStyle: paragraph]
        let text = value as NSString
        // 字間は最後の字の後ろにも付くので、測った幅から引く（右にそろえたときに端が 1008 に来るように）
        let full = ceil(text.size(withAttributes: attributes).width - (kern > 0 ? kern * font.pointSize : 0))
        let shown = min(maxWidth, full)
        let left = align == .right ? x + maxWidth - shown : x
        // 記録する枠の高さは字の大きさの 1.3 倍まで（明朝の行の高さは下の余白が大きい・`drawFittedSerif` と同じ）
        let rect = CGRect(x: left, y: y, width: shown, height: min(font.lineHeight, font.pointSize * 1.3))
        if ShareCardProbe.note(.text, value, rect: rect, color: color, fontSize: font.pointSize,
                               truncated: full > maxWidth) {
            text.draw(in: CGRect(x: left, y: y, width: shown + (kern > 0 ? kern * font.pointSize : 0) + 1,
                                 height: font.lineHeight + 2), withAttributes: attributes)
        }
        return shown
    }
}
#endif
